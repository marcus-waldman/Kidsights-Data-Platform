# Complete Cross-Validation Workflow for σ_sum_w Tuning
#
# This script orchestrates the full 3-phase cross-validation procedure for
# selecting the optimal σ_sum_w hyperparameter in the skewness-penalized
# authenticity screening model.
#
# PHASES:
#   Phase 1a: Fit base 2D IRT model (no penalty)
#   Phase 1b: Fit penalized models with σ_sum_w grid
#   Phase 2:  Extract logitwgt and create stratified folds
#   Phase 3:  Run 16-fold CV loop (144 total fits)
#
# INPUTS:
#   - M_data: Response data (person_id, item_id, response, age)
#   - J_data: Item metadata (item_id, K, dimension)
#
# OUTPUTS:
#   - optimal_sigma: Selected σ_sum_w value
#   - cv_summary: CV loss for all σ values
#   - All intermediate results saved to output directory
#
# USAGE:
#   source("scripts/authenticity_screening/in_development/run_cv_workflow.R")
#   results <- run_complete_cv_workflow(M_data, J_data)

library(rstan)
library(dplyr)

# Source all phase scripts
source("scripts/authenticity_screening/in_development/gh_quadrature_utils.R")
source("scripts/authenticity_screening/in_development/phase1_fit_base_model.R")
source("scripts/authenticity_screening/in_development/phase1_fit_penalized_models.R")
source("scripts/authenticity_screening/in_development/phase1c_sanity_check.R")
source("scripts/authenticity_screening/in_development/phase2_create_folds.R")
source("scripts/authenticity_screening/in_development/phase3_cv_loop.R")
source("scripts/authenticity_screening/in_development/00_prepare_cv_data.R")

# Step 0: Load pre-prepared data
# NOTE: Data is automatically prepared when 00_prepare_cv_data.R is sourced above
# (auto-execution block runs in non-interactive mode)
M_data <- readRDS("data/temp/cv_M_data.rds")
J_data <- readRDS("data/temp/cv_J_data.rds")

cat(sprintf("Participants: %d\n", length(unique(M_data$person_id))))
cat(sprintf("Observations: %d\n", nrow(M_data)))
cat(sprintf("Items: %d\n", nrow(J_data)))
cat(sprintf("  - Psychosocial/Behavioral (dimension 1): %d items\n", sum(J_data$dimension == 1)))
cat(sprintf("  - Developmental Skills (dimension 2): %d items\n", sum(J_data$dimension == 2)))

#' Run Complete CV Workflow
#'
#' Executes all three phases of the cross-validation procedure to select
#' optimal σ_sum_w hyperparameter.
#'
#' @param M_data Data frame with columns: person_id, item_id, response, age
#' @param J_data Data frame with columns: item_id, K (num categories), dimension
#' @param sigma_grid Vector of σ_sum_w values to evaluate (default: 2^(seq(-1,1,by=0.25)))
#' @param lambda_skew Skewness penalty strength (default: 1.0, fixed)
#' @param n_folds Number of CV folds (default: 16)
#' @param output_dir Directory to save all results (default: "output/authenticity_cv")
#' @param iter Maximum iterations for L-BFGS optimization (default: 10000)
#' @param algorithm Optimization algorithm to use (default: "LBFGS")
#' @param verbose Print optimization progress (default: FALSE for Phase 1b/3)
#' @param refresh Print update every N iterations (default: 0 for Phase 1b/3)
#' @param history_size L-BFGS history size (default: 500)
#' @param tol_obj Absolute tolerance for objective function (default: 1e-12)
#' @param tol_rel_obj Relative tolerance for objective function (default: 1)
#' @param tol_grad Absolute tolerance for gradient (default: 1e-8)
#' @param tol_rel_grad Relative tolerance for gradient (default: 1e3)
#' @param tol_param Absolute tolerance for parameters (default: 1e-8)
#' @param skip_phase1 Skip Phase 1 if already run (default: FALSE)
#' @param skip_phase1c Skip Phase 1c sanity check (default: FALSE)
#' @param skip_phase2 Skip Phase 2 if already run (default: FALSE)
#' @return List with optimal_sigma, cv_summary, and paths to all outputs
run_complete_cv_workflow <- function(M_data, J_data,
                                      sigma_grid = 2^(seq(-2, 2, len = 16)),
                                      lambda_skew = 1.0,
                                      n_folds = 2,
                                      output_dir = "output/authenticity_cv",
                                      iter = 10000, algorithm = "LBFGS",
                                      verbose = TRUE, refresh = 20, history_size = 500,
                                      tol_obj = 1e-12, tol_rel_obj = 1, tol_grad = 1e-8,
                                      tol_rel_grad = 1e3, tol_param = 1e-8,
                                      skip_phase1 = FALSE,
                                      skip_phase1c = FALSE,
                                      skip_phase2 = FALSE) {

  workflow_start <- Sys.time()

  cat("\n")
  cat("################################################################################\n")
  cat("#                                                                              #\n")
  cat("#     AUTHENTICITY SCREENING: σ_sum_w CROSS-VALIDATION WORKFLOW                #\n")
  cat("#                                                                              #\n")
  cat("################################################################################\n")
  cat("\n")

  cat("Configuration:\n")
  cat(sprintf("  Output directory: %s\n", output_dir))
  cat(sprintf("  σ_sum_w grid: %d values (%.3f to %.3f)\n",
              length(sigma_grid), min(sigma_grid), max(sigma_grid)))
  cat(sprintf("  lambda_skew: %.2f (fixed)\n", lambda_skew))
  cat(sprintf("  Number of folds: %d\n", n_folds))
  cat(sprintf("  Total CV fits: %d × %d = %d\n",
              length(sigma_grid), n_folds, length(sigma_grid) * n_folds))
  cat("\n")

  cat("Data summary:\n")
  cat(sprintf("  Participants: %d unique person_ids\n", length(unique(M_data$person_id))))
  cat(sprintf("  Observations: %d total responses\n", nrow(M_data)))
  cat(sprintf("  Items: %d total items\n", nrow(J_data)))
  cat(sprintf("  Age range: %.2f to %.2f years\n",
              min(M_data$age), max(M_data$age)))
  cat("\n")

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat(sprintf("[OK] Created output directory: %s\n\n", output_dir))
  }

  # ============================================================================
  # PHASE 1a: Fit Base Model
  # ============================================================================

  if (!skip_phase1) {
    cat("\n")
    cat("*** STARTING PHASE 1a: Base Model ***\n")
    cat("\n")

    fit0_full <- fit_base_model(
      M_data = M_data,
      J_data = J_data,
      output_dir = output_dir,
      init =0,
      iter = iter,
      algorithm = algorithm,
      verbose = verbose,
      refresh = refresh,
      history_size = history_size,
      tol_obj = tol_obj,
      tol_rel_obj = tol_rel_obj,
      tol_grad = tol_grad,
      tol_rel_grad = tol_rel_grad,
      tol_param = tol_param
    )

    fit0_params <- readRDS(file.path(output_dir, "fit0_params.rds"))

  } else {
    cat("\n")
    cat("*** SKIPPING PHASE 1a (loading existing results) ***\n")
    cat("\n")

    fit0_params <- readRDS(file.path(output_dir, "fit0_params.rds"))
    cat("[OK] Loaded Phase 1a results\n\n")
  }

  # ============================================================================
  # PHASE 1b: Fit Penalized Models
  # ============================================================================

  if (!skip_phase1) {
    cat("\n")
    cat("*** STARTING PHASE 1b: Penalized Models ***\n")
    cat("\n")

    phase1b_results <- fit_penalized_models(
      M_data = M_data,
      J_data = J_data,
      fit0_params = fit0_params,
      sigma_grid = sigma_grid,
      lambda_skew = lambda_skew,
      output_dir = output_dir,
      iter = 2000,
      algorithm = algorithm,
      verbose = verbose,
      refresh = refresh,
      history_size = history_size,
      tol_obj = tol_obj,
      tol_rel_obj = tol_rel_obj,
      tol_grad = tol_grad,
      tol_rel_grad = tol_rel_grad,
      tol_param = tol_param
    )

    # Load the saved fits_params for downstream use
    fits_params <- readRDS(file.path(output_dir, "fits_full_penalty_params.rds"))

  } else {
    cat("\n")
    cat("*** SKIPPING PHASE 1b (loading existing results) ***\n")
    cat("\n")

    fits_params <- readRDS(file.path(output_dir, "fits_full_penalty_params.rds"))
    cat("[OK] Loaded Phase 1b results\n\n")
  }

  # ============================================================================
  # PHASE 1c: Sanity Check - Weight vs Eta Correspondence
  # ============================================================================

  if (!skip_phase1c) {
    cat("\n")
    cat("*** STARTING PHASE 1c: Sanity Check ***\n")
    cat("\n")

    sanity_check_results <- run_sanity_check(
      fit0_params = fit0_params,
      fits_params = fits_params,
      sigma_grid = sigma_grid,
      output_dir = output_dir,
      weight_threshold = 0.5,
      eta_threshold_prob = 0.99
    )

    # Optionally halt workflow if sanity check fails
    if (!sanity_check_results$overall_pass) {
      warning("Phase 1c sanity check failed. Review diagnostic plots before continuing.")
      cat("\n")
      cat("Workflow will continue, but results should be carefully inspected.\n")
      cat("Set skip_phase1c = TRUE to bypass this check in future runs.\n")
      cat("\n")
    }

  } else {
    cat("\n")
    cat("*** SKIPPING PHASE 1c (sanity check disabled) ***\n")
    cat("\n")
  }

  # ============================================================================
  # PHASE 2: Create σ-Specific Stratified Folds
  # ============================================================================

  if (!skip_phase2) {
    cat("\n")
    cat("*** STARTING PHASE 2: σ-Specific Stratified Folds ***\n")
    cat("\n")

    fold_metadata <- create_folds_phase2_multi_sigma(
      M_data = M_data,
      fits_params = fits_params,
      weight_threshold = 0.5,
      n_folds = n_folds,
      output_dir = output_dir,
      create_plots = TRUE
    )

  } else {
    cat("\n")
    cat("*** SKIPPING PHASE 2 (will load σ-specific folds in Phase 3) ***\n")
    cat("\n")

    fold_metadata <- readRDS(file.path(output_dir, "fold_metadata.rds"))
    cat("[OK] Loaded Phase 2 metadata\n\n")
  }

  # ============================================================================
  # PHASE 3: Cross-Validation Loop (REFACTORED)
  # ============================================================================

  cat("\n")
  cat("*** STARTING PHASE 3: CV Loop (Integrated Likelihood) ***\n")
  cat("\n")

  cv_results <- run_cv_loop(
    M_data = M_data,
    J_data = J_data,
    fits_params = fits_params,
    sigma_grid = sigma_grid,
    weight_threshold = 0.5,
    integrate_training = TRUE,  # DEFAULT: Use integrated likelihood
    n_folds = n_folds,
    output_dir = output_dir,
    iter = iter,
    algorithm = algorithm,
    verbose = verbose,
    refresh = refresh,
    history_size = history_size,
    tol_obj = tol_obj,
    tol_rel_obj = tol_rel_obj,
    tol_grad = tol_grad,
    tol_rel_grad = tol_rel_grad,
    tol_param = tol_param
  )

  # ============================================================================
  # FINAL SUMMARY
  # ============================================================================

  workflow_end <- Sys.time()
  workflow_duration <- as.numeric(difftime(workflow_end, workflow_start, units = "hours"))

  cat("\n")
  cat("################################################################################\n")
  cat("#                                                                              #\n")
  cat("#     WORKFLOW COMPLETE                                                         #\n")
  cat("#                                                                              #\n")
  cat("################################################################################\n")
  cat("\n")

  cat(sprintf("Total workflow time: %.2f hours\n", workflow_duration))
  cat("\n")

  cat("================================================================================\n")
  cat("  FINAL RESULTS\n")
  cat("================================================================================\n")
  cat("\n")

  cat("CV Summary:\n")
  print(cv_results$cv_summary, n = nrow(cv_results$cv_summary))
  cat("\n")

  cat(sprintf("OPTIMAL HYPERPARAMETER:\n"))
  cat(sprintf("  σ_sum_w = %.3f\n", cv_results$optimal_sigma))
  cat(sprintf("  CV loss = %.4f\n",
              cv_results$cv_summary$cv_loss[cv_results$cv_summary$sigma_sum_w == cv_results$optimal_sigma]))
  cat("\n")

  cat("Output files:\n")
  cat(sprintf("  %s/fit0_full.rds - Base model fit\n", output_dir))
  cat(sprintf("  %s/fits_full_penalty.rds - Penalized model fits\n", output_dir))
  cat(sprintf("  %s/fold_assignments.rds - CV fold assignments\n", output_dir))
  cat(sprintf("  %s/cv_results.rds - All CV results\n", output_dir))
  cat(sprintf("  %s/cv_summary.rds - CV summary by σ\n", output_dir))
  cat(sprintf("  %s/optimal_sigma.rds - Optimal σ value\n", output_dir))
  cat(sprintf("  %s/plots/ - Diagnostic plots\n", output_dir))
  cat("\n")

  cat("NEXT STEPS:\n")
  cat("  1. Review cv_summary to inspect CV loss across all σ values\n")
  cat("  2. Check diagnostic plots in output_dir/plots/\n")
  cat("  3. Refit final model on full dataset using optimal σ_sum_w\n")
  cat("  4. Validate exclusion rate is sensible (5-15%)\n")
  cat("\n")

  return(list(
    optimal_sigma = cv_results$optimal_sigma,
    cv_summary = cv_results$cv_summary,
    cv_results = cv_results$cv_results,
    output_dir = output_dir,
    workflow_duration_hours = workflow_duration
  ))
}


################################################################################
# EXAMPLE USAGE
################################################################################

# Run complete workflow
results <- run_complete_cv_workflow(
  M_data = M_data,
  J_data = J_data,
  output_dir = "output/authenticity_cv"
)

# Inspect results
print(results$optimal_sigma)
print(results$cv_summary)

# # To skip already-completed phases (for iterating on Phase 3):
# results <- run_complete_cv_workflow(
#   M_data = M_data,
#   J_data = J_data,
#   skip_phase1 = TRUE,
#   skip_phase2 = TRUE
# )

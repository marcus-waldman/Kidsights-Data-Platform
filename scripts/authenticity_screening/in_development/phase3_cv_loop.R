# Phase 3: Cross-Validation Loop with Parallel Execution (REFACTORED)
#
# This script runs 16-fold cross-validation for each σ_sum_w value in the grid.
# Total fits: 9 σ values × 16 folds = 144 models fitted in parallel.
#
# KEY CHANGES from previous version:
#   - NO weight estimation (data filtered to w > 0.5 per σ in Phase 2)
#   - Uses σ-specific fold assignments (different sample sizes per σ)
#   - Integrated likelihood by DEFAULT (integrates out η in model block)
#   - Optional joint posterior (estimates η as parameters)
#
# For each (σ, fold) combination:
#   1. Load σ-specific fold assignments from Phase 2
#   2. Filter data to w > 0.5 (same filter used in Phase 2)
#   3. Split into training (15/16) and holdout (1/16)
#   4. Fit model on training data (warm start from Phase 1b item parameters)
#   5. Evaluate holdout via Gauss-Hermite quadrature
#   6. Extract fold_loss (mean per-person deviance)
#
# Outputs:
#   - cv_results.rds: Fold losses for all (σ, fold) combinations
#   - cv_summary.rds: Aggregated CV loss for each σ value
#   - optimal_sigma.rds: Selected σ with minimum CV loss

library(rstan)
library(dplyr)
library(parallel)

# Source utilities
source("scripts/authenticity_screening/in_development/gh_quadrature_utils.R")

#' Run Cross-Validation Loop (Refactored for σ-Specific Folds + Integrated Likelihood)
#'
#' @param M_data Data frame with columns: person_id (1:N), item_id, response, age
#' @param J_data Data frame with columns: item_id, K (num categories), dimension
#' @param fits_params List of parameters from Phase 1b (for warm starting + filtering)
#' @param sigma_grid Vector of σ_sum_w values to evaluate (default: 2^seq(-1,1,0.25))
#' @param weight_threshold Minimum weight for inclusion (default: 0.5, matches Phase 2)
#' @param integrate_training Use integrated likelihood (TRUE) or joint posterior (FALSE) (default: TRUE)
#' @param n_folds Number of folds (default: 16, must match Phase 2)
#' @param output_dir Directory to save results and load fold assignments from Phase 2
#' @param iter Maximum iterations for L-BFGS optimization (default: 10000)
#' @param algorithm Optimization algorithm to use (default: "LBFGS")
#' @param verbose Print optimization progress for each fit (default: FALSE)
#' @param refresh Print update every N iterations (default: 0 to suppress output)
#' @param history_size L-BFGS history size for Hessian approximation (default: 500)
#' @param tol_obj Absolute tolerance for objective function (default: 1e-12)
#' @param tol_rel_obj Relative tolerance for objective function (default: 1)
#' @param tol_grad Absolute tolerance for gradient (default: 1e-8)
#' @param tol_rel_grad Relative tolerance for gradient (default: 1e3)
#' @param tol_param Absolute tolerance for parameters (default: 1e-8)
#' @param n_parallel_jobs Number of parallel jobs (default: min(16, detectCores()/2))
#' @return List with cv_results, cv_summary, and optimal_sigma
#'
#' @details
#' NOTE: M_data uses person_id (1:N) as unique identifier.
#' This is created in 00_prepare_cv_data.R by mapping (pid, record_id) → person_id.
run_cv_loop <- function(M_data, J_data, fits_params,
                        sigma_grid,
                        weight_threshold = 0.5,
                        integrate_training = TRUE,
                        n_folds = 16,
                        output_dir = "output/authenticity_cv",
                        iter = 10000, algorithm = "LBFGS",
                        verbose = FALSE, refresh = 0, history_size = 500,
                        tol_obj = 1e-12, tol_rel_obj = 1, tol_grad = 1e-8,
                        tol_rel_grad = 1e3, tol_param = 1e-8,
                        n_parallel_jobs = min(n_folds, parallel::detectCores()/2)) {

  cat("\n")
  cat("================================================================================\n")
  cat("  PHASE 3: Cross-Validation Loop (REFACTORED)\n")
  cat("================================================================================\n")
  cat("\n")

  cat(sprintf("Configuration:\n"))
  cat(sprintf("  σ_sum_w grid: %d values (%.3f to %.3f)\n",
              length(sigma_grid), min(sigma_grid), max(sigma_grid)))
  cat(sprintf("  Weight threshold: w > %.2f\n", weight_threshold))
  cat(sprintf("  Integration mode: %s\n", if (integrate_training) "INTEGRATED (default)" else "JOINT POSTERIOR"))
  cat(sprintf("  Number of folds: %d\n", n_folds))
  cat(sprintf("  Total fits: %d (σ) × %d (folds) = %d\n",
              length(sigma_grid), n_folds, length(sigma_grid) * n_folds))
  cat(sprintf("  Parallel jobs: %d\n", n_parallel_jobs))
  cat(sprintf("  Optimization: %s (max %d iterations)\n", algorithm, iter))
  cat("\n")

  # Generate Gauss-Hermite nodes/weights
  cat("Generating Gauss-Hermite quadrature nodes...\n")
  gh <- get_gh_nodes_weights(n_nodes = 21)
  cat("\n")

  # Compile appropriate CV Stan model (once, for all fits)
  if (integrate_training) {
    model_file <- "models/in_development/authenticity_glmm_cv_integrated.stan"
    model_name <- "cv_integrated"
  } else {
    model_file <- "models/in_development/authenticity_glmm_cv_joint.stan"
    model_name <- "cv_joint"
  }

  if (!file.exists(model_file)) {
    stop(sprintf("CV model file not found: %s", model_file))
  }

  cat(sprintf("Compiling CV model: %s\n", model_file))
  stan_model_cv <- rstan::stan_model(file = model_file, model_name = model_name)
  cat("[OK] CV model compiled successfully\n\n")

  # Create grid of all (σ, fold) combinations
  cv_grid <- expand.grid(
    sigma_idx = 1:length(sigma_grid),
    fold = 1:n_folds,
    stringsAsFactors = FALSE
  )

  cv_grid$sigma_sum_w <- sigma_grid[cv_grid$sigma_idx]
  cv_grid$job_id <- 1:nrow(cv_grid)

  cat(sprintf("Total CV jobs: %d\n", nrow(cv_grid)))
  if (integrate_training) {
    cat(sprintf("Estimated time: %.0f-%.0f minutes (INTEGRATED mode, slower)\n",
                nrow(cv_grid) * 2 / n_parallel_jobs,
                nrow(cv_grid) * 10 / n_parallel_jobs))
  } else {
    cat(sprintf("Estimated time: %.0f-%.0f minutes (JOINT mode, faster)\n",
                nrow(cv_grid) * 0.5 / n_parallel_jobs,
                nrow(cv_grid) * 2 / n_parallel_jobs))
  }
  cat("\n")

  # Function to fit one (σ, fold) combination
  fit_one_cv_job <- function(job_row) {
    job_id <- job_row$job_id
    sigma_idx <- job_row$sigma_idx
    sigma_sum_w <- job_row$sigma_sum_w
    holdout_fold <- job_row$fold

    # Get warm start parameters from Phase 1b
    init_params <- fits_params[[sigma_idx]]

    # Load σ-specific fold assignments from Phase 2
    fold_file <- file.path(output_dir, sprintf("fold_assignments_sigma_%d.rds", sigma_idx))
    if (!file.exists(fold_file)) {
      warning(sprintf("[Job %d] Fold file not found: %s. Skipping.", job_id, fold_file))
      return(data.frame(
        job_id = job_id,
        sigma_idx = sigma_idx,
        sigma_sum_w = sigma_sum_w,
        fold = holdout_fold,
        fold_loss = NA,
        N_holdout = NA,
        return_code = -1,
        converged = FALSE,
        fit_success = FALSE
      ))
    }

    fold_assignments <- readRDS(fold_file)

    # Filter M_data to participants with w > weight_threshold for this σ
    # person_id is artificial (1:N), already unique
    w_all <- init_params$w
    person_lookup <- M_data %>%
      dplyr::select(person_id) %>%
      dplyr::distinct() %>%
      dplyr::arrange(person_id) %>%
      dplyr::mutate(person_idx = dplyr::row_number())

    person_lookup$w <- w_all

    # Get person_ids that meet threshold
    persons_included <- person_lookup %>%
      dplyr::filter(w > weight_threshold) %>%
      dplyr::select(person_id)

    # Filter M_data to included persons only
    M_data_filtered <- M_data %>%
      dplyr::inner_join(persons_included, by = "person_id")

    # Merge with fold assignments (which were created from same filtered set)
    M_data_with_folds <- M_data_filtered %>%
      dplyr::left_join(fold_assignments, by = "person_id")

    if (any(is.na(M_data_with_folds$fold))) {
      warning(sprintf("[Job %d] Some person_ids missing fold assignments. Skipping.", job_id))
      return(data.frame(
        job_id = job_id,
        sigma_idx = sigma_idx,
        sigma_sum_w = sigma_sum_w,
        fold = holdout_fold,
        fold_loss = NA,
        N_holdout = NA,
        return_code = -1,
        converged = FALSE,
        fit_success = FALSE
      ))
    }

    # Extract person-level folds (one per unique person_id)
    person_folds <- M_data_with_folds %>%
      dplyr::select(person_id, fold) %>%
      dplyr::distinct() %>%
      dplyr::arrange(person_id) %>%
      dplyr::pull(fold)

    # Prepare CV data
    stan_data <- prepare_cv_stan_data(
      M_data = M_data_with_folds,
      J_data = J_data,
      folds = person_folds,
      holdout_fold = holdout_fold,
      gh = gh
    )

    # Create init function (warm start from Phase 1b ITEM parameters only)
    # Person effects (eta) are either integrated out or estimated from scratch
    if (integrate_training) {
      # Integrated model: NO eta parameters
      init_fn <- function() {
        list(
          tau = init_params$tau,
          beta1 = init_params$beta1,
          delta = init_params$delta
        )
      }
    } else {
      # Joint model: Has eta parameters, but we initialize them to 0 (not from Phase 1b)
      # because Phase 1b eta values correspond to ALL persons, not filtered training set
      init_fn <- function() {
        list(
          tau = init_params$tau,
          beta1 = init_params$beta1,
          delta = init_params$delta,
          eta_psychosocial_train = rep(0, stan_data$N_train),
          eta_developmental_train = rep(0, stan_data$N_train)
        )
      }
    }

    # Validate init (make sure we have required parameters)
    init_vals <- init_fn()
    if (any(is.na(init_vals$tau)) || any(is.na(init_vals$beta1)) || any(is.na(init_vals$delta))) {
      warning(sprintf("[Job %d] Invalid initialization values (NA in item parameters). Skipping.", job_id))
      return(data.frame(
        job_id = job_id,
        sigma_idx = sigma_idx,
        sigma_sum_w = sigma_sum_w,
        fold = holdout_fold,
        fold_loss = NA,
        N_holdout = stan_data$N_holdout,
        return_code = -1,
        converged = FALSE,
        fit_success = FALSE
      ))
    }

    # Fit CV model
    fit <- tryCatch({
      rstan::optimizing(
        stan_model_cv,
        data = stan_data,
        init = init_fn,
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
    }, error = function(e) {
      warning(sprintf("[Job %d] Fit failed: %s", job_id, e$message))
      return(NULL)
    })

    if (is.null(fit)) {
      return(data.frame(
        job_id = job_id,
        sigma_idx = sigma_idx,
        sigma_sum_w = sigma_sum_w,
        fold = holdout_fold,
        fold_loss = NA,
        N_holdout = NA,
        converged = FALSE,
        fit_success = FALSE
      ))
    }

    # Extract fold_loss
    fold_loss <- fit$par["fold_loss"]

    # Get holdout size
    N_holdout <- stan_data$N_holdout

    # Check convergence
    return_code <- fit$return_code
    converged <- (return_code == 0)

    return(data.frame(
      job_id = job_id,
      sigma_idx = sigma_idx,
      sigma_sum_w = sigma_sum_w,
      fold = holdout_fold,
      fold_loss = fold_loss,
      N_holdout = N_holdout,
      return_code = return_code,
      converged = converged,
      fit_success = TRUE
    ))
  }

  # Run all CV jobs in parallel
  cat("Running CV loop (this will take a while)...\n")
  cat(sprintf("Progress: Jobs will be processed in batches of %d\n\n", n_parallel_jobs))

  cv_start <- Sys.time()

  # Use mclapply for Unix-like, or lapply for Windows
  if (.Platform$OS.type == "unix") {
    # Try to use progress bar for Unix (pbmcapply package)
    if (requireNamespace("pbmcapply", quietly = TRUE)) {
      cat("[INFO] Using pbmcapply for progress tracking\n\n")
      cv_results_list <- pbmcapply::pbmclapply(
        split(cv_grid, cv_grid$job_id),
        fit_one_cv_job,
        mc.cores = n_parallel_jobs
      )
    } else {
      cat("[WARN] Install 'pbmcapply' package for progress bar support\n")
      cat("       Running without progress bar...\n\n")
      cv_results_list <- parallel::mclapply(
        split(cv_grid, cv_grid$job_id),
        fit_one_cv_job,
        mc.cores = n_parallel_jobs
      )
    }
  } else {
    # Windows: Use parallel cluster with progress bar
    cat("[INFO] Windows detected - using parallel cluster\n")

    # Try to use progress bar (pbapply package)
    use_progress <- requireNamespace("pbapply", quietly = TRUE)
    if (use_progress) {
      cat("[INFO] Using pbapply for progress tracking\n\n")
    } else {
      cat("[WARN] Install 'pbapply' package for progress bar support\n")
      cat("       Running without progress bar...\n\n")
    }

    cl <- parallel::makeCluster(n_parallel_jobs)

    # Export necessary objects to cluster
    parallel::clusterExport(cl, c(
      "stan_model_cv", "M_data", "J_data", "fits_params",
      "gh", "weight_threshold", "integrate_training", "output_dir",
      "iter", "algorithm", "verbose", "refresh",
      "history_size", "tol_obj", "tol_rel_obj", "tol_grad",
      "tol_rel_grad", "tol_param", "prepare_cv_stan_data"
    ), envir = environment())

    # Load packages on each worker
    parallel::clusterEvalQ(cl, {
      library(rstan)
      library(dplyr)
    })

    # Run with or without progress bar
    if (use_progress) {
      cv_results_list <- pbapply::pblapply(
        split(cv_grid, cv_grid$job_id),
        fit_one_cv_job,
        cl = cl
      )
    } else {
      cv_results_list <- parallel::parLapply(
        cl,
        split(cv_grid, cv_grid$job_id),
        fit_one_cv_job
      )
    }

    parallel::stopCluster(cl)
  }

  cv_end <- Sys.time()
  cv_duration <- as.numeric(difftime(cv_end, cv_start, units = "mins"))

  cat("\n")
  cat(sprintf("[OK] CV loop complete (%.1f minutes)\n", cv_duration))
  cat("\n")

  # Combine results
  cv_results <- dplyr::bind_rows(cv_results_list)

  # Check for failures
  n_failures <- sum(!cv_results$fit_success)
  if (n_failures > 0) {
    warning(sprintf("%d fits failed out of %d total", n_failures, nrow(cv_results)))
  }

  # Aggregate by sigma (weighted average by N_holdout)
  cv_summary <- cv_results %>%
    dplyr::filter(fit_success) %>%
    dplyr::group_by(sigma_idx, sigma_sum_w) %>%
    dplyr::summarise(
      cv_loss = sum(fold_loss * N_holdout, na.rm = TRUE) / sum(N_holdout, na.rm = TRUE),
      se_loss = sd(fold_loss, na.rm = TRUE) / sqrt(dplyr::n()),
      n_folds_converged = dplyr::n(),
      n_folds_success = sum(converged, na.rm = TRUE),
      total_holdout = sum(N_holdout, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(cv_loss)

  # Identify optimal sigma
  optimal_idx <- which.min(cv_summary$cv_loss)
  optimal_sigma <- cv_summary$sigma_sum_w[optimal_idx]
  optimal_cv_loss <- cv_summary$cv_loss[optimal_idx]

  cat("================================================================================\n")
  cat("  CV RESULTS\n")
  cat("================================================================================\n")
  cat("\n")

  cat("CV loss by σ_sum_w:\n")
  print(cv_summary, n = nrow(cv_summary))
  cat("\n")

  cat(sprintf("OPTIMAL σ_sum_w: %.3f (CV loss = %.4f)\n", optimal_sigma, optimal_cv_loss))
  cat("\n")

  # Save results
  results_file <- file.path(output_dir, "cv_results.rds")
  summary_file <- file.path(output_dir, "cv_summary.rds")
  optimal_file <- file.path(output_dir, "optimal_sigma.rds")

  saveRDS(cv_results, results_file)
  saveRDS(cv_summary, summary_file)
  saveRDS(optimal_sigma, optimal_file)

  cat(sprintf("[OK] Saved CV results: %s\n", results_file))
  cat(sprintf("[OK] Saved CV summary: %s\n", summary_file))
  cat(sprintf("[OK] Saved optimal σ: %s\n", optimal_file))
  cat("\n")

  cat("================================================================================\n")
  cat("  PHASE 3 COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  return(list(
    cv_results = cv_results,
    cv_summary = cv_summary,
    optimal_sigma = optimal_sigma
  ))
}


# Example usage (commented out - run interactively)
# fits_params <- readRDS("output/authenticity_cv/fits_full_penalty_params.rds")
# fold_assignments <- readRDS("output/authenticity_cv/fold_assignments.rds")
# cv_results <- run_cv_loop(M_data, J_data, fold_assignments, fits_params)

# Phase 3: Cross-Validation Loop with Parallel Execution
#
# This script runs 16-fold cross-validation for each σ_sum_w value in the grid.
# Total fits: 9 σ values × 16 folds = 144 models fitted in parallel.
#
# For each (σ, fold) combination:
#   1. Split data into training (15/16) and holdout (1/16)
#   2. Fit model on training data (warm start from Phase 1b)
#   3. Evaluate holdout via Gauss-Hermite quadrature
#   4. Extract fold_loss (mean per-person deviance)
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

#' Run Cross-Validation Loop
#'
#' @param M_data Data frame with columns: pid, item_id, response, age
#' @param J_data Data frame with columns: item_id, K (num categories), dimension
#' @param fold_assignments Data frame with columns: pid, fold
#' @param fits_params List of parameters from Phase 1b (for warm starting)
#' @param sigma_grid Vector of σ_sum_w values to evaluate
#' @param lambda_skew Skewness penalty strength (default: 1.0)
#' @param n_folds Number of folds (default: 16)
#' @param output_dir Directory to save results
#' @param n_chains Number of MCMC chains per fit (default: 2, faster for CV)
#' @param n_iter Number of iterations per chain (default: 1000, faster for CV)
#' @param n_cores_per_fit Cores per model fit (default: 2)
#' @param n_parallel_jobs Number of parallel jobs (default: min(144, detectCores()))
#' @return List with cv_results, cv_summary, and optimal_sigma
run_cv_loop <- function(M_data, J_data, fold_assignments, fits_params,
                        sigma_grid = 2^(seq(-1, 1, by = 0.25)),
                        lambda_skew = 1.0,
                        n_folds = 16,
                        output_dir = "output/authenticity_cv",
                        n_chains = 2, n_iter = 1000,
                        n_cores_per_fit = 2,
                        n_parallel_jobs = min(144, parallel::detectCores())) {

  cat("\n")
  cat("================================================================================\n")
  cat("  PHASE 3: Cross-Validation Loop\n")
  cat("================================================================================\n")
  cat("\n")

  cat(sprintf("Configuration:\n"))
  cat(sprintf("  σ_sum_w grid: %d values (%.3f to %.3f)\n",
              length(sigma_grid), min(sigma_grid), max(sigma_grid)))
  cat(sprintf("  Number of folds: %d\n", n_folds))
  cat(sprintf("  Total fits: %d (σ) × %d (folds) = %d\n",
              length(sigma_grid), n_folds, length(sigma_grid) * n_folds))
  cat(sprintf("  Parallel jobs: %d\n", n_parallel_jobs))
  cat(sprintf("  Chains per fit: %d, Iterations: %d\n", n_chains, n_iter))
  cat("\n")

  # Generate Gauss-Hermite nodes/weights
  cat("Generating Gauss-Hermite quadrature nodes...\n")
  gh <- get_gh_nodes_weights(n_nodes = 21)
  cat("\n")

  # Merge fold assignments with data
  M_data_with_folds <- M_data %>%
    dplyr::left_join(fold_assignments, by = "pid")

  if (any(is.na(M_data_with_folds$fold))) {
    stop("Some PIDs in M_data do not have fold assignments")
  }

  # Compile CV Stan model (once, for all fits)
  model_file <- "models/in_development/authenticity_glmm_cv.stan"

  if (!file.exists(model_file)) {
    stop(sprintf("CV model file not found: %s", model_file))
  }

  cat(sprintf("Compiling CV model: %s\n", model_file))
  stan_model_cv <- rstan::stan_model(file = model_file, model_name = "cv_model")
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
  cat(sprintf("Estimated time: %.0f-%.0f minutes (depends on hardware)\n",
              nrow(cv_grid) * 2 / n_parallel_jobs,
              nrow(cv_grid) * 5 / n_parallel_jobs))
  cat("\n")

  # Function to fit one (σ, fold) combination
  fit_one_cv_job <- function(job_row) {
    job_id <- job_row$job_id
    sigma_idx <- job_row$sigma_idx
    sigma_sum_w <- job_row$sigma_sum_w
    holdout_fold <- job_row$fold

    # Get warm start parameters from Phase 1b
    init_params <- fits_params[[sigma_idx]]

    # Prepare CV data
    stan_data <- prepare_cv_stan_data(
      M_data = M_data_with_folds,
      J_data = J_data,
      folds = M_data_with_folds$fold,
      holdout_fold = holdout_fold,
      gh = gh,
      lambda_skew = lambda_skew,
      sigma_sum_w = sigma_sum_w
    )

    # Create init function (warm start from Phase 1b)
    init_fn <- function() {
      list(
        tau = init_params$tau,
        beta1 = init_params$beta1,
        delta = init_params$delta,
        eta_psychosocial_train = init_params$eta_psychosocial[stan_data$ivec_train],
        eta_developmental_train = init_params$eta_developmental[stan_data$ivec_train],
        logitwgt_train = init_params$logitwgt[stan_data$ivec_train]
      )
    }

    # Fit CV model
    fit <- tryCatch({
      rstan::sampling(
        stan_model_cv,
        data = stan_data,
        init = init_fn,
        chains = n_chains,
        iter = n_iter,
        warmup = floor(n_iter / 2),
        cores = n_cores_per_fit,
        refresh = 0,
        control = list(adapt_delta = 0.95, max_treedepth = 10),
        seed = 12345 + job_id
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
        fit_success = FALSE
      ))
    }

    # Extract fold_loss
    fold_loss_samples <- rstan::extract(fit, "fold_loss")[[1]]
    fold_loss <- mean(fold_loss_samples)

    # Get holdout size
    N_holdout <- stan_data$N_holdout

    # Quick convergence check
    summary_fit <- rstan::summary(fit, pars = c("tau", "beta1", "delta"))$summary
    max_rhat <- max(summary_fit[, "Rhat"], na.rm = TRUE)

    return(data.frame(
      job_id = job_id,
      sigma_idx = sigma_idx,
      sigma_sum_w = sigma_sum_w,
      fold = holdout_fold,
      fold_loss = fold_loss,
      N_holdout = N_holdout,
      max_rhat = max_rhat,
      fit_success = TRUE
    ))
  }

  # Run all CV jobs in parallel
  cat("Running CV loop (this will take a while)...\n")
  cat(sprintf("Progress: Jobs will be processed in batches of %d\n\n", n_parallel_jobs))

  cv_start <- Sys.time()

  # Use mclapply for Unix-like, or lapply for Windows
  if (.Platform$OS.type == "unix") {
    cv_results_list <- parallel::mclapply(
      split(cv_grid, cv_grid$job_id),
      fit_one_cv_job,
      mc.cores = n_parallel_jobs
    )
  } else {
    # Windows: Use parallel cluster
    cat("[INFO] Windows detected - using parallel cluster\n")
    cl <- parallel::makeCluster(n_parallel_jobs)

    # Export necessary objects to cluster
    parallel::clusterExport(cl, c(
      "stan_model_cv", "M_data_with_folds", "J_data", "fits_params",
      "gh", "lambda_skew", "n_chains", "n_iter", "n_cores_per_fit",
      "prepare_cv_stan_data"
    ), envir = environment())

    # Load packages on each worker
    parallel::clusterEvalQ(cl, {
      library(rstan)
      library(dplyr)
    })

    cv_results_list <- parallel::parLapply(
      cl,
      split(cv_grid, cv_grid$job_id),
      fit_one_cv_job
    )

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

  # Aggregate by sigma
  cv_summary <- cv_results %>%
    dplyr::filter(fit_success) %>%
    dplyr::group_by(sigma_idx, sigma_sum_w) %>%
    dplyr::summarise(
      cv_loss = mean(fold_loss, na.rm = TRUE),
      se_loss = sd(fold_loss, na.rm = TRUE) / sqrt(dplyr::n()),
      n_folds_converged = dplyr::n(),
      mean_rhat = mean(max_rhat, na.rm = TRUE),
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

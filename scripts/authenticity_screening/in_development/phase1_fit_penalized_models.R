# Phase 1b: Fit Penalized Models with Grid of σ_sum_w Values
#
# This script fits the skewness-penalized model with 9 different σ_sum_w values
# using the base model parameters as warm starts. All 9 models are fitted in
# parallel for computational efficiency.
#
# Model: authenticity_glmm_beta_sumprior_stable.stan
#   - 2D IRT + participant weights + skewness penalty
#   - Logit-scale parameterization
#   - Normal sum prior with varying σ_sum_w
#
# Outputs:
#   - fits_full_penalty: List of 9 Stan fit objects
#   - fits_full_penalty_params.rds: Extracted parameters for all σ values

library(rstan)
library(dplyr)
library(parallel)

# Source utilities
source("scripts/authenticity_screening/in_development/gh_quadrature_utils.R")

#' Fit Penalized Models with σ_sum_w Grid
#'
#' @param M_data Data frame with columns: pid, item_id, response, age
#' @param J_data Data frame with columns: item_id, K (num categories), dimension
#' @param fit0_params List of base model parameters from Phase 1a
#' @param sigma_grid Vector of σ_sum_w values (default: 2^(seq(-1, 1, by=0.25)))
#' @param lambda_skew Skewness penalty strength (default: 1.0)
#' @param output_dir Directory to save results
#' @param iter Maximum iterations for L-BFGS optimization (default: 10000)
#' @param algorithm Optimization algorithm to use (default: "LBFGS")
#' @param verbose Print optimization progress for each model (default: FALSE for parallel)
#' @param refresh Print update every N iterations (default: 0 to suppress output)
#' @param history_size L-BFGS history size for Hessian approximation (default: 500)
#' @param tol_obj Absolute tolerance for objective function (default: 1e-12)
#' @param tol_rel_obj Relative tolerance for objective function (default: 1)
#' @param tol_grad Absolute tolerance for gradient (default: 1e-8)
#' @param tol_rel_grad Relative tolerance for gradient (default: 1e3)
#' @param tol_param Absolute tolerance for parameters (default: 1e-8)
#' @param n_parallel Number of models to fit in parallel (default: 9 for all)
#' @return List of Stan fit objects (one per σ value)
fit_penalized_models <- function(M_data, J_data, fit0_params,
                                  sigma_grid = 2^(seq(-1, 1, by = 0.25)),
                                  lambda_skew = 1.0,
                                  output_dir = "output/authenticity_cv",
                                  iter = 10000, algorithm = "LBFGS",
                                  verbose = FALSE, refresh = 0, history_size = 500,
                                  tol_obj = 1e-12, tol_rel_obj = 1, tol_grad = 1e-8,
                                  tol_rel_grad = 1e3, tol_param = 1e-8,
                                  n_parallel = max(c(parallel::detectCores()/2, length(sigma_grid)))) {

  cat("\n")
  cat("================================================================================\n")
  cat("  PHASE 1b: Fitting Penalized Models (σ_sum_w Grid)\n")
  cat("================================================================================\n")
  cat("\n")

  # Validate sigma grid
  if (length(sigma_grid) != 9) {
    warning(sprintf("Expected 9 sigma values, got %d. Proceeding anyway.", length(sigma_grid)))
  }

  cat(sprintf("σ_sum_w grid (%d values): ", length(sigma_grid)))
  cat(paste(sprintf("%.3f", sigma_grid), collapse = ", "))
  cat("\n")
  cat(sprintf("lambda_skew: %.2f (fixed)\n", lambda_skew))
  cat(sprintf("Parallel execution: %d models simultaneously\n", n_parallel))
  cat("\n")

  # Prepare Stan data (same across all σ values)
  unique_person_ids <- unique(M_data$person_id)
  N <- length(unique_person_ids)

  person_map <- data.frame(person_id = unique_person_ids, new_id = 1:N)
  M_data$ivec <- person_map$new_id[match(M_data$person_id, person_map$person_id)]

  age <- M_data %>%
    dplyr::group_by(ivec) %>%
    dplyr::summarise(age = dplyr::first(age), .groups = "drop") %>%
    dplyr::arrange(ivec) %>%
    dplyr::pull(age)

  stan_data_base <- list(
    M = nrow(M_data),
    N = N,
    J = nrow(J_data),
    ivec = M_data$ivec,
    jvec = M_data$item_id,
    yvec = M_data$response,
    age = age,
    K = J_data$K,
    dimension = J_data$dimension,
    lambda_skew = lambda_skew
  )

  cat(sprintf("Data summary:\n"))
  cat(sprintf("  N = %d persons\n", N))
  cat(sprintf("  M = %d observations\n", nrow(M_data)))
  cat(sprintf("  J = %d items\n", nrow(J_data)))
  cat("\n")

  # Compile model
  model_file <- "models/authenticity_glmm_beta_sumprior_stable.stan"

  if (!file.exists(model_file)) {
    stop(sprintf("Model file not found: %s", model_file))
  }

  cat(sprintf("Compiling model: %s\n", model_file))
  stan_model <- rstan::stan_model(file = model_file, model_name = "penalized_stable")
  cat("[OK] Model compiled successfully\n\n")

  # Create initialization function (warm start from fit0)
  init_fn <- function() {
    list(
      tau = fit0_params$tau,
      beta1 = fit0_params$beta1,
      delta = fit0_params$delta,
      eta_psychosocial = fit0_params$eta_psychosocial,
      eta_developmental = fit0_params$eta_developmental,
      logitwgt = rep(0, N)  # Neutral weights: inv_logit(0) ≈ 0.5
    )
  }

  # Fit one model (helper function for parallel execution)
  fit_one_sigma <- function(sigma_sum_w, idx) {
    cat(sprintf("\n[%d/%d] Fitting model with σ_sum_w = %.3f...\n",
                idx, length(sigma_grid), sigma_sum_w))

    # Add sigma_sum_w to data
    stan_data <- stan_data_base
    stan_data$sigma_sum_w <- sigma_sum_w

    fit_start <- Sys.time()

    fit <- rstan::optimizing(
      stan_model,
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

    fit_end <- Sys.time()
    fit_duration <- as.numeric(difftime(fit_end, fit_start, units = "mins"))

    # Check convergence
    return_code <- fit$return_code
    converged <- (return_code == 0)

    cat(sprintf("[%d/%d] Complete (%.1f min) | return_code: %d %s | log-posterior: %.2f\n",
                idx, length(sigma_grid), fit_duration, return_code,
                ifelse(converged, "[OK]", "[WARNING]"), fit$value))

    if (!converged) {
      warning(sprintf("Model %d (sigma=%.3f) did not converge (return_code=%d)",
                      idx, sigma_sum_w, return_code))
    }

    return(fit)
  }

  # Fit all models in parallel
  cat(sprintf("\nFitting %d models in parallel (this may take 10-20 minutes with optimization)...\n",
              length(sigma_grid)))

  fit_start_all <- Sys.time()

  # Use mclapply for Unix-like systems, or parLapply for Windows
  if (.Platform$OS.type == "unix") {
    fits_full_penalty <- parallel::mclapply(
      seq_along(sigma_grid),
      function(i) fit_one_sigma(sigma_grid[i], i),
      mc.cores = n_parallel
    )
  } else {
    # Windows: Use parallel cluster
    cat(sprintf("[INFO] Windows detected - using parallel cluster (%d cores)\n", n_parallel))
    cl <- parallel::makeCluster(n_parallel)

    # Export necessary objects to cluster
    parallel::clusterExport(cl, c(
      "stan_model", "stan_data_base", "sigma_grid", "fit0_params", "N",
      "iter", "algorithm", "verbose", "refresh", "history_size",
      "tol_obj", "tol_rel_obj", "tol_grad", "tol_rel_grad", "tol_param"
    ), envir = environment())

    # Load packages on each worker
    parallel::clusterEvalQ(cl, {
      library(rstan)
      library(dplyr)
    })

    # Fit models in parallel
    fits_full_penalty <- parallel::parLapply(
      cl,
      seq_along(sigma_grid),
      function(i) {
        sigma_sum_w <- sigma_grid[i]
        cat(sprintf("\n[%d/%d] Fitting model with sigma_sum_w = %.3f...\n",
                    i, length(sigma_grid), sigma_sum_w))

        # Add sigma_sum_w to data
        stan_data <- stan_data_base
        stan_data$sigma_sum_w <- sigma_sum_w

        # Create init function
        init_fn <- function() {
          list(
            tau = fit0_params$tau,
            beta1 = fit0_params$beta1,
            delta = fit0_params$delta,
            eta_psychosocial = fit0_params$eta_psychosocial,
            eta_developmental = fit0_params$eta_developmental,
            logitwgt = rep(0, N)
          )
        }

        fit_start <- Sys.time()

        fit <- rstan::optimizing(
          stan_model,
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

        fit_end <- Sys.time()
        fit_duration <- as.numeric(difftime(fit_end, fit_start, units = "mins"))

        return_code <- fit$return_code
        converged <- (return_code == 0)

        cat(sprintf("[%d/%d] Complete (%.1f min) | return_code: %d %s | log-posterior: %.2f\n",
                    i, length(sigma_grid), fit_duration, return_code,
                    ifelse(converged, "[OK]", "[WARNING]"), fit$value))

        if (!converged) {
          warning(sprintf("Model %d (sigma=%.3f) did not converge (return_code=%d)",
                          i, sigma_sum_w, return_code))
        }

        return(fit)
      }
    )

    parallel::stopCluster(cl)
  }

  fit_end_all <- Sys.time()
  fit_duration_all <- as.numeric(difftime(fit_end_all, fit_start_all, units = "mins"))

  cat("\n")
  cat(sprintf("[OK] All %d models fitted (%.1f minutes total)\n",
              length(sigma_grid), fit_duration_all))
  cat("\n")

  # Name list elements
  names(fits_full_penalty) <- sprintf("sigma_%.3f", sigma_grid)

  # Extract parameters from all fits
  cat("Extracting parameters from all fits...\n")

  fits_params <- lapply(seq_along(fits_full_penalty), function(i) {
    fit <- fits_full_penalty[[i]]
    list(
      sigma_sum_w = sigma_grid[i],
      tau = fit$par[startsWith(names(fit$par), "tau")],
      beta1 = fit$par[startsWith(names(fit$par), "beta1")],
      delta = fit$par[startsWith(names(fit$par), "delta")],
      eta_psychosocial = fit$par[startsWith(names(fit$par), "eta") & endsWith(names(fit$par), "1]")],
      eta_developmental = fit$par[startsWith(names(fit$par), "eta") & endsWith(names(fit$par), "2]")],
      logitwgt = fit$par[startsWith(names(fit$par), "logitwgt")],
      w = fit$par[startsWith(names(fit$par), "w[")],
      sum_w = fit$par["sum_weight"],
      n_excluded = fit$par["n_excluded"],
      n_included = fit$par["n_included"]
    )
  })

  names(fits_params) <- names(fits_full_penalty)

  # Save results
  fits_file <- file.path(output_dir, "fits_full_penalty.rds")
  params_file <- file.path(output_dir, "fits_full_penalty_params.rds")

  saveRDS(fits_full_penalty, fits_file)
  saveRDS(fits_params, params_file)

  cat(sprintf("[OK] Saved fit objects: %s\n", fits_file))
  cat(sprintf("[OK] Saved parameters: %s\n", params_file))
  cat("\n")

  # Summary table
  cat("Summary across σ_sum_w values:\n")
  cat(sprintf("%-10s | %8s | %10s | %10s | %10s\n",
              "σ_sum_w", "sum(w)", "N_excluded", "N_included", "N_uncertain"))
  cat(strrep("-", 65), "\n")

  for (i in seq_along(fits_params)) {
    p <- fits_params[[i]]
    n_uncertain <- N - p$n_excluded - p$n_included
    cat(sprintf("%10.3f | %8.1f | %10.0f | %10.0f | %10.0f\n",
                p$sigma_sum_w, p$sum_w, p$n_excluded, p$n_included, n_uncertain))
  }
  cat("\n")

  cat("================================================================================\n")
  cat("  PHASE 1b COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  return(list(
    fits = fits_full_penalty,
    params = fits_params,
    sigma_grid = sigma_grid
  ))
}


# Example usage (commented out - run interactively)
# fit0_params <- readRDS("output/authenticity_cv/fit0_params.rds")
# results <- fit_penalized_models(M_data, J_data, fit0_params)

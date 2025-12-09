# Calibration Estimator with Random Effects Wrapper
# Purpose: Estimate survey weights using hierarchical random effects model
# Uses: Stan optimization with individual-level deviations
#
# Mathematical form:
#   log(wgt[i]) = alpha + X[i,] * beta + sigma_u * u[i]
#   u[i] ~ Normal(0, 1) with sum(u) = 0
#
# Parameters: K+1 fixed effects + N random effects + 1 variance = N+K+2 total

library(cmdstanr)
library(dplyr)
library(posterior)

# ============================================================================
# Main Calibration Function (Random Effects)
# ============================================================================

calibrate_weights_random_effects <- function(data, target_mean, target_cov, calibration_vars,
                                             verbose = TRUE) {

  cat("\n========================================\n")
  cat("Calibrating Survey Weights (RANDOM EFFECTS)\n")
  cat("(KL divergence minimization via hierarchical model)\n")
  cat("========================================\n\n")

  # Validate inputs
  if (!all(calibration_vars %in% names(data))) {
    missing <- setdiff(calibration_vars, names(data))
    stop(sprintf("Calibration variables not in data: %s", paste(missing, collapse = ", ")))
  }

  if (length(target_mean) != length(calibration_vars)) {
    stop("target_mean length must match calibration_vars length")
  }

  if (!is.matrix(target_cov) || nrow(target_cov) != length(calibration_vars) ||
      ncol(target_cov) != length(calibration_vars)) {
    stop("target_cov must be a square matrix matching calibration_vars length")
  }

  # Extract dimensions
  N <- nrow(data)
  K <- length(calibration_vars)

  cat("[1] Data Summary:\n")
  cat(sprintf("    N (observations): %d\n", N))
  cat(sprintf("    K (calibration variables): %d\n", K))
  cat(sprintf("    Total parameters: %d (alpha + %d betas + %d random effects + sigma_u)\n",
              N + K + 2, K, N))
  cat(sprintf("    Calibration variables: %s\n\n", paste(calibration_vars, collapse = ", ")))

  # Check for missing values
  cat("[2] Missing Data Check:\n\n")

  X_raw <- data %>% dplyr::select(all_of(calibration_vars))
  n_missing <- colSums(is.na(X_raw))

  data_for_validation <- X_raw

  if (any(n_missing > 0)) {
    cat("[WARNING] Missing values detected:\n")
    for (i in which(n_missing > 0)) {
      cat(sprintf("  %s: %d/%d (%.1f%%)\n",
                  calibration_vars[i], n_missing[i], N, n_missing[i] / N * 100))
    }
    cat("\n")
  } else {
    cat("    All variables complete - no missing data\n\n")
  }

  # Display targets
  cat("[3] Target Mean Vector:\n\n")

  for (k in seq_along(calibration_vars)) {
    cat(sprintf("    %s: %.4f\n", calibration_vars[k], target_mean[k]))
  }
  cat("\n")

  cat("[4] Target Covariance Matrix:\n\n")
  cat("    Diagonal (variances):\n")
  for (k in seq_along(calibration_vars)) {
    cat(sprintf("      %s: %.4f\n", calibration_vars[k], target_cov[k, k]))
  }
  cat("\n")

  # Prepare design matrix
  cat("[5] Preparing design matrix:\n\n")

  X_matrix <- as.matrix(X_raw)

  cat(sprintf("    Design matrix: %d x %d\n", nrow(X_matrix), ncol(X_matrix)))
  cat(sprintf("    Column means: %s\n",
              paste(round(colMeans(X_matrix, na.rm = TRUE), 4), collapse = ", ")))
  cat("\n")

  # Prepare data for Stan
  stan_data <- list(
    N = N,
    K = K,
    X = X_matrix,
    target_mean = as.vector(target_mean),
    target_cov = target_cov
  )

  # Compile Stan model
  cat("[6] Compiling Stan model (random effects):\n\n")

  stan_file <- "scripts/raking/ne25/utils/calibrate_weights_random_effects.stan"

  if (!file.exists(stan_file)) {
    stop(sprintf("Stan file not found: %s", stan_file))
  }

  tryCatch({
    mod <- cmdstanr::cmdstan_model(stan_file, quiet = TRUE)
    cat("    Stan model compiled successfully\n\n")
  }, error = function(e) {
    stop(sprintf("Error compiling Stan model:\n%s", e$message))
  })

  # Run Stan optimization
  cat("[7] Running Stan optimizer (L-BFGS algorithm with random effects):\n\n")
  cat(sprintf("    Note: Optimizing %d parameters (K+1 fixed + N random + sigma_u)\n\n",
              N + K + 2))

  tryCatch({
    fit <- mod$optimize(
      data = stan_data,
      seed = 12345,
      init = 0.1,                   # Small initial values for random effects
      algorithm = "lbfgs",          # L-BFGS for high-dimensional problems
      history_size = 100,           # Larger history for better convergence (default: 5)
      tol_rel_grad = 1e-10,
      tol_grad = 1e-10,
      tol_rel_obj = 1e-6,
      tol_param = 1e-10,
      iter = 10000,
      show_exceptions = FALSE,
      refresh = 10                  # Less frequent updates for large N
    )
  }, error = function(e) {
    stop(sprintf("Stan optimization failed:\n%s", e$message))
  })

  cat("\n[8] Optimizer completed\n\n")

  # Extract optimal parameters
  cat("[9] Extracting optimal parameters:\n\n")

  theta_optimal <- fit$draws(variables = c("alpha", "beta", "sigma_u"), format = "df")

  if (nrow(theta_optimal) == 0) {
    stop("Could not extract parameters from optimization result")
  }

  alpha_opt <- as.numeric(theta_optimal[1, "alpha"])
  beta_cols <- grep("^beta\\[", names(theta_optimal), value = TRUE)
  beta_opt <- as.numeric(theta_optimal[1, beta_cols])
  sigma_u_opt <- as.numeric(theta_optimal[1, "sigma_u"])

  cat(sprintf("    Intercept (alpha): %.6f\n", alpha_opt))
  cat(sprintf("    Random effects SD (sigma_u): %.6f\n\n", sigma_u_opt))
  cat(sprintf("    Fixed effects coefficients (beta):\n"))

  for (k in seq_along(calibration_vars)) {
    cat(sprintf("      %s: %.6f\n", calibration_vars[k], beta_opt[k]))
  }
  cat("\n")

  # Extract final weights
  wgt_final_cols <- grep("^wgt_final\\[", names(fit$draws(format = "df")), value = TRUE)

  if (length(wgt_final_cols) > 0) {
    theta_optimal_wgt <- fit$draws(variables = "wgt_final", format = "df")
    final_weights <- as.numeric(theta_optimal_wgt[1, wgt_final_cols])
  } else {
    # Extract u and compute weights in R
    cat("    Note: Computing weights in R (wgt_final not in Stan output)\n")
    u_cols <- grep("^u\\[", names(fit$draws(format = "df")), value = TRUE)
    theta_u <- fit$draws(variables = "u", format = "df")
    u_opt <- as.numeric(theta_u[1, u_cols])

    log_wgt_final <- alpha_opt + X_matrix %*% beta_opt + sigma_u_opt * u_opt
    final_weights <- as.vector(exp(log_wgt_final))
  }

  # Marginal verification
  cat("[10] Final Marginal Verification:\n\n")
  cat(sprintf("    DEBUG: nrow(X_matrix) = %d, length(final_weights) = %d\n\n",
              nrow(X_matrix), length(final_weights)))

  final_check <- data.frame(
    Variable = calibration_vars,
    Target = target_mean,
    Initial = NA_real_,
    Achieved = NA_real_,
    Difference = NA_real_,
    Pct_Diff = NA_real_
  )

  for (j in seq_along(calibration_vars)) {
    var <- calibration_vars[j]
    initial <- mean(data_for_validation[[var]], na.rm = TRUE)
    achieved <- weighted.mean(data_for_validation[[var]], final_weights, na.rm = TRUE)
    diff <- abs(achieved - target_mean[j])
    pct_diff <- (diff / abs(target_mean[j])) * 100

    final_check$Initial[j] <- initial
    final_check$Achieved[j] <- achieved
    final_check$Difference[j] <- diff
    final_check$Pct_Diff[j] <- pct_diff
  }

  print(final_check)

  # Weight diagnostics
  cat("\n[11] Weight Diagnostics:\n\n")

  weight_sum <- sum(final_weights, na.rm = TRUE)
  weight_sum_sq <- sum(final_weights^2, na.rm = TRUE)
  n_eff <- weight_sum^2 / weight_sum_sq

  cat(sprintf("    Min weight: %.4f\n", min(final_weights)))
  cat(sprintf("    Max weight: %.4f\n", max(final_weights)))
  cat(sprintf("    Mean weight: %.4f\n", mean(final_weights)))
  cat(sprintf("    Median weight: %.4f\n", median(final_weights)))
  cat(sprintf("    Std dev: %.4f\n", sd(final_weights)))
  cat(sprintf("    Weight ratio (max/min): %.2f\n\n", max(final_weights) / min(final_weights)))

  cat(sprintf("    Weighted N: %.0f\n", weight_sum))
  cat(sprintf("    Effective N (Kish): %.1f\n", n_eff))
  cat(sprintf("    Efficiency: %.1f%%\n\n", n_eff / N * 100))

  # Check convergence
  tolerance_default <- 0.01
  converged <- all(final_check$Pct_Diff < tolerance_default)

  if (converged) {
    cat("[OK] Convergence achieved (all marginals within 1%)\n")
    cat(sprintf("     Max %% difference: %.2f%%\n\n", max(final_check$Pct_Diff)))
  } else {
    cat("[WARNING] Did not achieve <1%% convergence\n")
    cat(sprintf("     Max %% difference: %.2f%%\n", max(final_check$Pct_Diff)))
    cat("     Consider adjusting hyperprior on sigma_u\n\n")
  }

  # Optimization diagnostics
  cat("[12] Optimization Diagnostics:\n\n")

  log_prob <- fit$draws(variables = "lp__", format = "df")[1, 1]
  cat(sprintf("    Log probability at optimum: %.2f\n", log_prob))
  cat(sprintf("    (More negative = better fit to targets)\n\n"))

  # Return results
  cat("========================================\n")
  cat("Calibration Complete (Random Effects)\n")
  cat("========================================\n\n")

  list(
    data = data %>% dplyr::mutate(calibrated_weight = final_weights),
    calibrated_weight = final_weights,
    converged = converged,
    alpha = alpha_opt,
    beta = beta_opt,
    sigma_u = sigma_u_opt,
    beta_names = calibration_vars,
    final_marginals = final_check,
    effective_n = n_eff,
    efficiency_pct = n_eff / N * 100,
    weight_ratio = max(final_weights) / min(final_weights),
    log_prob = log_prob,
    stan_fit = fit,
    stan_data = stan_data
  )
}

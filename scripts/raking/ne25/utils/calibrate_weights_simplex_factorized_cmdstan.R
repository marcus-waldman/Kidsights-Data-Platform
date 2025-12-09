# Calibration Estimator Wrapper: Simplex with Factorized Covariance
# Purpose: Estimate survey weights with incomplete covariance structure
# Uses: Stan optimization with N-dimensional simplex (flexible parameterization)
#
# Key Features:
#   - N parameters (one weight per observation) instead of K+1
#   - Weight constraints: min_weight <= wgt[i] <= max_weight
#   - Handles factorized (singular) covariance matrices
#   - Dirichlet prior for smoothing

library(cmdstanr)
library(dplyr)
library(posterior)

# ============================================================================
# Main Calibration Function (Simplex Parameterization)
# ============================================================================

calibrate_weights_simplex_factorized_stan <- function(data, target_mean, target_cov, cov_mask,
                                                      calibration_vars,
                                                      min_weight = 0.1,
                                                      max_weight = 10.0,
                                                      concentration = 1.0,
                                                      verbose = TRUE, 
                                                      history_size = 100, 
                                                      refresh = 1, 
                                                      iter = 1000) {

  cat("\n========================================\n")
  cat("Calibrating Survey Weights (Simplex Parameterization)\n")
  cat("(Masked KL divergence with weight constraints)\n")
  cat("========================================\n\n")

  cat(sprintf("Weight constraints: %.1f <= wgt[i] <= %.1f\n", min_weight, max_weight))
  cat(sprintf("Concentration parameter: %.2f\n\n", concentration))

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

  if (!is.matrix(cov_mask) || !all(dim(cov_mask) == dim(target_cov))) {
    stop("cov_mask must have same dimensions as target_cov")
  }

  # Extract dimensions
  N <- nrow(data)
  K <- length(calibration_vars)

  cat("[1] Data Summary:\n")
  cat(sprintf("    N (observations): %d\n", N))
  cat(sprintf("    K (calibration variables): %d\n", K))
  cat(sprintf("    Calibration variables: %s\n\n", paste(calibration_vars, collapse = ", ")))

  # Covariance mask summary
  n_total_cov <- K * K
  n_observed_cov <- sum(cov_mask > 0.5)
  pct_observed <- (n_observed_cov / n_total_cov) * 100

  cat("[2] Covariance Mask:\n")
  cat(sprintf("    Total covariance elements: %d (K × K)\n", n_total_cov))
  cat(sprintf("    Observed elements (mask = 1): %d (%.1f%%)\n", n_observed_cov, pct_observed))
  cat(sprintf("    Unobserved elements (mask = 0): %d (%.1f%%)\n",
              n_total_cov - n_observed_cov, 100 - pct_observed))
  cat("\n")

  # Check for missing values
  cat("[3] Missing Data Check:\n\n")

  X_raw <- data %>% dplyr::select(dplyr::all_of(calibration_vars))
  n_missing <- colSums(is.na(X_raw))

  # Store for validation
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
  cat("[4] Target Mean Vector:\n\n")

  for (k in seq_along(calibration_vars)) {
    cat(sprintf("    %s: %.4f\n", calibration_vars[k], target_mean[k]))
  }
  cat("\n")

  cat("[5] Target Covariance Matrix:\n\n")
  cat("    Diagonal (variances):\n")
  for (k in seq_along(calibration_vars)) {
    cat(sprintf("      %s: %.4f\n", calibration_vars[k], target_cov[k, k]))
  }
  cat("\n")

  # Prepare design matrix for Stan
  cat("[6] Preparing design matrix:\n\n")

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
    target_cov = target_cov,
    cov_mask = cov_mask,
    concentration = concentration,
    min_weight_multiplier = min_weight,
    max_weight_multiplier = max_weight
  )

  # Compile Stan model
  cat("[7] Compiling Stan model (simplex factorized version):\n\n")

  stan_file <- "scripts/raking/ne25/utils/calibrate_weights_simplex_factorized.stan"

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
  cat("[8] Running Stan optimizer (simplex with weight constraints):\n\n")

  tryCatch({
    fit <- mod$optimize(
      data = stan_data,
      seed = 12345,
      init = 0,
      algorithm = "lbfgs",
      tol_rel_grad = 1e-10,
      tol_grad = 1e-10,
      tol_rel_obj = 1e-6,
      tol_param = 1e-10,
      iter = iter,
      show_exceptions = FALSE,
      refresh = refresh,
      history_size = history_size
    )
  }, error = function(e) {
    stop(sprintf("Stan optimization failed:\n%s", e$message))
  })

  cat("\n[9] Optimizer completed\n\n")

  # Extract optimal weights
  cat("[10] Extracting optimal weights:\n\n")

  # Simplex model outputs wgt_final directly (no alpha/beta coefficients)
  wgt_final_cols <- grep("^wgt_final\\[", names(fit$draws(format = "df")), value = TRUE)

  if (length(wgt_final_cols) > 0) {
    theta_optimal <- fit$draws(variables = "wgt_final", format = "df")
    final_weights <- as.numeric(theta_optimal[1, wgt_final_cols])
    cat(sprintf("    Extracted %d weights from Stan output\n", length(final_weights)))
  } else {
    stop("Could not extract wgt_final from Stan optimization result")
  }

  cat(sprintf("    Min weight: %.4f\n", min(final_weights)))
  cat(sprintf("    Max weight: %.4f\n", max(final_weights)))
  cat(sprintf("    Mean weight: %.4f\n\n", mean(final_weights)))

  # Final verification
  cat("[11] Final Marginal Verification:\n\n")
  cat(sprintf("    DEBUG: nrow(X_matrix) = %d, length(final_weights) = %d, nrow(data_for_validation) = %d\n",
              nrow(X_matrix), length(final_weights), nrow(data_for_validation)))
  cat("\n")

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
  cat("\n[12] Weight Diagnostics:\n\n")

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
  tolerance_default <- 0.01  # 1%
  converged <- all(final_check$Pct_Diff < tolerance_default)

  if (converged) {
    cat("[OK] Convergence achieved (all marginals within 1%)\n")
    cat(sprintf("     Max %% difference: %.2f%%\n\n", max(final_check$Pct_Diff)))
  } else {
    cat("[WARNING] Did not achieve <1%% convergence\n")
    cat(sprintf("     Max %% difference: %.2f%%\n", max(final_check$Pct_Diff)))
    cat("     Consider re-running optimization\n\n")
  }

  # Extract optimization diagnostics
  cat("[13] Optimization Diagnostics:\n\n")

  log_prob <- fit$draws(variables = "lp__", format = "df")[1, 1]
  cat(sprintf("    Log probability at optimum: %.2f\n", log_prob))
  cat(sprintf("    (More negative = larger penalty for deviation from targets)\n\n"))

  # Return results
  cat("========================================\n")
  cat("Calibration Complete (Simplex Parameterization)\n")
  cat("========================================\n\n")

  list(
    data = data %>% dplyr::mutate(calibrated_weight = final_weights),
    calibrated_weight = final_weights,
    converged = converged,
    final_marginals = final_check,
    effective_n = n_eff,
    efficiency_pct = n_eff / N * 100,
    weight_ratio = max(final_weights) / min(final_weights),
    log_prob = log_prob,
    n_observed_cov = n_observed_cov,
    pct_observed_cov = pct_observed,
    min_weight = min_weight,
    max_weight = max_weight,
    concentration = concentration,
    stan_fit = fit,
    stan_data = stan_data
  )
}

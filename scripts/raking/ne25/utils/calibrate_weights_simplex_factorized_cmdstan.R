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
  X_raw_matrix <- as.matrix(X_raw)  # Convert to matrix for correlation calculations
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

  # ========================================================================
  # Compute Standardization Factors (Z-score normalization)
  # ========================================================================
  # These improve Stan optimizer efficiency by scaling all variables to mean=0, sd=1
  # Weights are scale-invariant, so no back-transformation needed

  cat("[6b] Computing standardization factors for improved optimizer efficiency:\n\n")

  scale_mean <- colMeans(X_matrix, na.rm = TRUE)
  scale_sd <- apply(X_matrix, 2, sd, na.rm = TRUE)

  # Replace zero SDs with 1.0 to avoid division by zero
  scale_sd[scale_sd < 1e-10] <- 1.0

  cat("     Variable standardization factors:\n")
  for (k in seq_along(calibration_vars)) {
    cat(sprintf("       %s: mean=%.4f, sd=%.4f\n",
                calibration_vars[k], scale_mean[k], scale_sd[k]))
  }
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
    max_weight_multiplier = max_weight,
    # NEW: Standardization factors for improved optimizer efficiency
    scale_mean = as.vector(scale_mean),
    scale_sd = as.vector(scale_sd),
    use_standardization = 1L  # 1 = use standardization, 0 = raw scale
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

  cat("    Configuration:\n")
  cat("      - Algorithm: LBFGS (quasi-Newton with line search)\n")
  cat("      - Standardization: ENABLED (Z-score normalization)\n")
  cat("        → Improves numerical stability and convergence (typically 20-40%% faster)\n")
  cat("      - Weight constraints: Enforced via simplex parameterization\n")
  cat("      - Convergence tolerances:\n")
  cat("        → Gradient tolerance: 1e-10\n")
  cat("        → Objective tolerance: 1e-6\n")
  cat("        → Parameter tolerance: 1e-10\n")
  cat("      - Max iterations: ", iter, "\n\n")

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
  cat("[11] Final Marginal Verification (on original scale):\n\n")
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

  # ========================================================================
  # [14] Correlation Improvement Analysis
  # ========================================================================

  cat("[14] Correlation Improvement Analysis:\n\n")

  # Compute unweighted correlations (before weighting)
  unweighted_cov <- cor(X_raw_matrix)
  unweighted_cov[is.na(unweighted_cov)] <- 0  # Handle NAs from missing data

  # Extract target correlations from target covariance
  target_corr <- target_cov / outer(sqrt(diag(target_cov)), sqrt(diag(target_cov)))
  target_corr[is.nan(target_corr)] <- 0

  # Compute weighted correlations (after weighting)
  # Need to handle missing values carefully - align weights with non-missing data
  weighted_cov_matrix <- matrix(0, nrow = K, ncol = K)
  for (i in 1:K) {
    for (j in 1:K) {
      # Only use rows where both variables are observed
      na_mask <- !is.na(X_raw_matrix[, i]) & !is.na(X_raw_matrix[, j])
      if (sum(na_mask) > 1) {
        X_i_complete <- X_raw_matrix[na_mask, i]
        X_j_complete <- X_raw_matrix[na_mask, j]
        w_complete <- final_weights[na_mask]

        mean_i <- weighted.mean(X_i_complete, w_complete)
        mean_j <- weighted.mean(X_j_complete, w_complete)
        dev_i <- X_i_complete - mean_i
        dev_j <- X_j_complete - mean_j
        weighted_cov_matrix[i, j] <- weighted.mean(dev_i * dev_j, w_complete)
      }
    }
  }
  weighted_corr <- weighted_cov_matrix / outer(sqrt(diag(weighted_cov_matrix)), sqrt(diag(weighted_cov_matrix)))
  weighted_corr[is.nan(weighted_corr)] <- 0

  # Compute correlation errors
  # Only look at observed covariance elements (where mask = 1)
  unweighted_errors <- abs(unweighted_cov - target_corr) * cov_mask
  weighted_errors <- abs(weighted_corr - target_corr) * cov_mask

  # Summary statistics (excluding diagonal)
  mask_offdiag <- cov_mask - diag(diag(cov_mask))
  unweighted_rmse <- sqrt(mean((unweighted_cov - target_corr)^2 * mask_offdiag))
  weighted_rmse <- sqrt(mean((weighted_corr - target_corr)^2 * mask_offdiag))

  cat(sprintf("    Unweighted RMSE (correlations): %.6f\n", unweighted_rmse))
  cat(sprintf("    Weighted RMSE (correlations):   %.6f\n", weighted_rmse))
  cat(sprintf("    Improvement: %.1f%%\n\n",
              (1 - weighted_rmse / unweighted_rmse) * 100))

  # Show top correlations that improved most
  improvements <- data.frame(
    var_i = character(),
    var_j = character(),
    target_corr = numeric(),
    before_corr = numeric(),
    after_corr = numeric(),
    error_before = numeric(),
    error_after = numeric(),
    improvement = numeric()
  )

  for (i in 2:K) {
    for (j in 1:(i-1)) {
      if (cov_mask[i, j] > 0.5) {
        improvements <- rbind(improvements, data.frame(
          var_i = calibration_vars[i],
          var_j = calibration_vars[j],
          target_corr = target_corr[i, j],
          before_corr = unweighted_cov[i, j],
          after_corr = weighted_corr[i, j],
          error_before = unweighted_errors[i, j],
          error_after = weighted_errors[i, j],
          improvement = unweighted_errors[i, j] - weighted_errors[i, j]
        ))
      }
    }
  }

  # Sort by improvement (largest improvements first)
  improvements <- improvements[order(improvements$improvement, decreasing = TRUE), ]

  cat(sprintf("    Top 10 correlations with largest improvements:\n\n"))
  top_improvements <- head(improvements, 10)
  for (row in 1:nrow(top_improvements)) {
    cat(sprintf("      %s × %s:\n", top_improvements$var_i[row], top_improvements$var_j[row]))
    cat(sprintf("        Target: %.4f, Before: %.4f, After: %.4f, Error reduced by: %.4f\n\n",
                top_improvements$target_corr[row],
                top_improvements$before_corr[row],
                top_improvements$after_corr[row],
                top_improvements$improvement[row]))
  }

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
    # Standardization factors (for documentation)
    scale_mean = scale_mean,
    scale_sd = scale_sd,
    use_standardization = TRUE,
    # Correlation improvement diagnostics
    unweighted_rmse_corr = unweighted_rmse,
    weighted_rmse_corr = weighted_rmse,
    correlation_improvement_pct = (1 - weighted_rmse / unweighted_rmse) * 100,
    unweighted_correlations = unweighted_cov,
    target_correlations = target_corr,
    weighted_correlations = weighted_corr,
    correlation_improvements = improvements,
    stan_fit = fit,
    stan_data = stan_data
  )
}

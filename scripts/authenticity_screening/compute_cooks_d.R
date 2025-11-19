#!/usr/bin/env Rscript

#' Compute Cook's D Influence Diagnostics from LOOCV Results
#'
#' Uses jackknife-based Hessian approximation to compute Cook's D for each
#' participant in the authenticity screening LOOCV analysis.
#'
#' Mathematical Details:
#'   1. Each LOOCV iteration provides parameter differences: theta_(-i) - theta_full
#'   2. Empirical covariance: Sigma_jack = cov(diff_matrix) * (N-1)
#'   3. Approximate Hessian: H ≈ inv(Sigma_jack)
#'   4. Cook's D for person i: D_i = diff_i' * H * diff_i / p
#'
#' Input:
#'   - results/loocv_results.rds (from 03_run_loocv.R)
#'   - param_diff field in each LOOCV result
#'
#' Output:
#'   - results/loocv_cooks_d.rds (data frame with Cook's D and diagnostics)
#'   - results/loocv_hessian_approx.rds (jackknife Hessian matrix)
#'
#' Author: Kidsights Data Platform
#' Date: November 2025

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY SCREENING: COOK'S D INFLUENCE DIAGNOSTICS\n")
cat("================================================================================\n")
cat("\n")

# ============================================================================
# PHASE 1: LOAD AND VALIDATE LOOCV RESULTS
# ============================================================================

cat("=== PHASE 1: LOAD LOOCV RESULTS ===\n\n")

cat("[Step 1/2] Loading LOOCV results...\n")
loocv_results <- readRDS("results/loocv_authentic_results.rds")

N <- nrow(loocv_results)
cat(sprintf("      Loaded: %d LOOCV iterations\n", N))

# Check for param_diff field
if (!"param_diff" %in% names(loocv_results)) {
  stop("[ERROR] param_diff field not found in LOOCV results. Re-run 03_run_loocv.R with updated version.")
}

cat("\n[Step 2/2] Validating param_diff availability...\n")

# Count non-NULL param_diff (successful N-1 model fits)
n_valid <- sum(!sapply(loocv_results$param_diff, is.null))
n_missing <- N - n_valid

cat(sprintf("      Valid param_diff: %d / %d (%.1f%%)\n",
            n_valid, N, 100 * n_valid / N))

if (n_missing > 0) {
  cat(sprintf("      [WARNING] %d participants missing param_diff (N-1 model failed)\n",
              n_missing))
}

if (n_valid < 100) {
  stop("[ERROR] Insufficient valid param_diff for reliable Hessian estimation (need N >= 100)")
}

# ============================================================================
# PHASE 2: CONSTRUCT PARAMETER DIFFERENCE MATRIX
# ============================================================================

cat("\n=== PHASE 2: CONSTRUCT DIFFERENCE MATRIX ===\n\n")

cat("[Step 1/3] Extracting parameter differences...\n")

# Get parameter dimensions from first valid param_diff
first_valid <- which(!sapply(loocv_results$param_diff, is.null))[1]
param_diff_example <- loocv_results$param_diff[[first_valid]]

J <- length(param_diff_example$tau_diff)  # Number of items
p <- 2 * J + 3  # tau (J) + beta1 (J) + delta (2) + eta_corr (1)

cat(sprintf("      J = %d items\n", J))
cat(sprintf("      p = %d total item parameters\n", p))

cat("\n[Step 2/3] Building N x p difference matrix...\n")

# Initialize matrix (will have NAs for failed iterations)
diff_matrix <- matrix(NA_real_, nrow = N, ncol = p)

# Fill in difference matrix
for (i in 1:N) {
  param_diff <- loocv_results$param_diff[[i]]

  if (!is.null(param_diff)) {
    # Concatenate all parameter differences into single vector
    diff_matrix[i, ] <- c(
      param_diff$tau_diff,        # Positions 1:J
      param_diff$beta1_diff,      # Positions (J+1):(2J)
      param_diff$delta_diff,      # Positions (2J+1):(2J+2) - now 2-element vector
      param_diff$eta_corr_diff    # Position 2J+3
    )
  }
}

# Remove rows with NA (failed N-1 fits) for covariance calculation
diff_matrix_complete <- diff_matrix[!is.na(diff_matrix[, 1]), , drop = FALSE]
n_complete <- nrow(diff_matrix_complete)

cat(sprintf("      Complete cases: %d / %d\n", n_complete, N))

cat("\n[Step 3/3] Computing parameter statistics...\n")

# Parameter-wise RMSEs (diagnostic)
rmse_by_param <- sqrt(colMeans(diff_matrix_complete^2))

# Identify most influential parameters
max_rmse <- max(rmse_by_param)
param_names <- c(
  paste0("tau[", 1:J, "]"),
  paste0("beta1[", 1:J, "]"),
  "delta[1]",
  "delta[2]",
  "eta_correlation"
)
most_influential <- which.max(rmse_by_param)

cat(sprintf("      Max RMSE: %.6f (%s)\n", max_rmse, param_names[most_influential]))
cat(sprintf("      Mean RMSE: %.6f\n", mean(rmse_by_param)))

# ============================================================================
# PHASE 3: JACKKNIFE HESSIAN APPROXIMATION
# ============================================================================

cat("\n=== PHASE 3: JACKKNIFE HESSIAN ===\n\n")

cat("[Step 1/3] Computing jackknife covariance matrix...\n")

# Empirical covariance of parameter differences (jackknife scaling)
Sigma_jack <- cov(diff_matrix_complete) * (n_complete - 1)

cat(sprintf("      Sigma_jack: %d x %d matrix\n", nrow(Sigma_jack), ncol(Sigma_jack)))

cat("\n[Step 2/3] Inverting to get Hessian approximation...\n")

# Check condition number before inversion
eig_vals <- eigen(Sigma_jack, only.values = TRUE)$values
condition_number <- max(eig_vals) / min(eig_vals)

cat(sprintf("      Condition number: %.2e\n", condition_number))

if (condition_number > 1e10) {
  cat("      [WARNING] Matrix is ill-conditioned, using regularized inversion\n")

  # Regularized inversion (add small ridge to diagonal)
  ridge <- 1e-6 * mean(diag(Sigma_jack))
  Sigma_reg <- Sigma_jack + diag(ridge, nrow = p, ncol = p)
  H_approx <- solve(Sigma_reg)

} else {
  # Standard inversion
  H_approx <- solve(Sigma_jack)
}

cat(sprintf("      H_approx: %d x %d matrix\n", nrow(H_approx), ncol(H_approx)))

cat("\n[Step 3/3] Saving Hessian matrix...\n")

saveRDS(H_approx, "results/loocv_hessian_approx.rds")
cat("      Saved: results/loocv_hessian_approx.rds\n")

# ============================================================================
# PHASE 4: COMPUTE COOK'S D
# ============================================================================

cat("\n=== PHASE 4: COMPUTE COOK'S D ===\n\n")

cat("[Step 1/2] Computing Cook's D for all participants...\n")

# Initialize Cook's D vector
cooks_d <- rep(NA_real_, N)

# Compute Cook's D for each participant with valid param_diff
for (i in 1:N) {
  if (!is.na(diff_matrix[i, 1])) {
    diff_i <- diff_matrix[i, ]

    # Cook's D formula: D_i = (diff_i' * H * diff_i) / p
    cooks_d[i] <- as.numeric(t(diff_i) %*% H_approx %*% diff_i) / p
  }
}

# Sample-size invariant version: D_i * N
cooks_d_scaled <- cooks_d * N

n_computed <- sum(!is.na(cooks_d))

cat(sprintf("      Computed: %d / %d Cook's D values\n", n_computed, N))
cat(sprintf("      Scaled by N=%d for sample-size invariance\n", N))

cat("\n[Step 2/2] Computing influence diagnostics...\n")

# Summary statistics (scaled version - sample-size invariant)
cooks_d_scaled_valid <- cooks_d_scaled[!is.na(cooks_d_scaled)]

summary_stats_scaled <- list(
  min = min(cooks_d_scaled_valid),
  q25 = quantile(cooks_d_scaled_valid, 0.25),
  median = median(cooks_d_scaled_valid),
  q75 = quantile(cooks_d_scaled_valid, 0.75),
  max = max(cooks_d_scaled_valid),
  mean = mean(cooks_d_scaled_valid),
  sd = sd(cooks_d_scaled_valid)
)

cat("      Scaled Cook's D (D × N) summary:\n")
cat(sprintf("        Min:    %.2f\n", summary_stats_scaled$min))
cat(sprintf("        Q1:     %.2f\n", summary_stats_scaled$q25))
cat(sprintf("        Median: %.2f\n", summary_stats_scaled$median))
cat(sprintf("        Q3:     %.2f\n", summary_stats_scaled$q75))
cat(sprintf("        Max:    %.2f\n", summary_stats_scaled$max))
cat(sprintf("        Mean:   %.2f\n", summary_stats_scaled$mean))
cat(sprintf("        SD:     %.2f\n", summary_stats_scaled$sd))

# Identify highly influential participants using sample-size invariant thresholds
# Threshold = 4 (equivalent to traditional 4/N, now constant across sample sizes)
n_influential_4 <- sum(cooks_d_scaled_valid > 4, na.rm = TRUE)

cat(sprintf("\n      High influence (D×N > 4): %d participants (%.1f%%)\n",
            n_influential_4, 100 * n_influential_4 / n_computed))

# Very high influence: D×N > N (equivalent to unscaled D > 1)
n_influential_N <- sum(cooks_d_scaled_valid > N, na.rm = TRUE)

cat(sprintf("      Very high influence (D×N > %d): %d participants (%.1f%%)\n",
            N, n_influential_N, 100 * n_influential_N / n_computed))

# ============================================================================
# PHASE 5: SAVE RESULTS
# ============================================================================

cat("\n=== PHASE 5: SAVE RESULTS ===\n\n")

cat("[Step 1/2] Creating results data frame...\n")

# Combine with LOOCV results
loocv_with_cooks_d <- loocv_results
loocv_with_cooks_d$cooks_d <- cooks_d
loocv_with_cooks_d$cooks_d_scaled <- cooks_d_scaled
loocv_with_cooks_d$influential_4 <- cooks_d_scaled > 4
loocv_with_cooks_d$influential_N <- cooks_d_scaled > N

cat(sprintf("      Added: cooks_d, cooks_d_scaled, influential_4, influential_N columns\n"))

cat("\n[Step 2/2] Saving results...\n")

saveRDS(loocv_with_cooks_d, "results/loocv_cooks_d.rds")
cat("      Saved: results/loocv_cooks_d.rds\n")

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n")
cat("================================================================================\n")
cat("  COOK'S D COMPUTATION COMPLETE\n")
cat("================================================================================\n")
cat("\n")

cat("Summary:\n")
cat(sprintf("  Total participants: %d\n", N))
cat(sprintf("  Valid Cook's D: %d (%.1f%%)\n", n_computed, 100 * n_computed / N))
cat(sprintf("  Highly influential (D×N > 4): %d (%.1f%%)\n",
            n_influential_4, 100 * n_influential_4 / n_computed))
cat(sprintf("  Very high influence (D×N > %d): %d (%.1f%%)\n",
            N, n_influential_N, 100 * n_influential_N / n_computed))
cat("\n")

cat("Output files:\n")
cat("  results/loocv_cooks_d.rds (LOOCV results + scaled Cook's D)\n")
cat("  results/loocv_hessian_approx.rds (Jackknife Hessian matrix)\n")
cat("\n")

cat("Note: Using sample-size invariant Cook's D (D×N)\n")
cat("  - Threshold D×N > 4 is constant across studies (equivalent to D > 4/N)\n")
cat("  - Allows direct comparison of influence across different sample sizes\n")
cat("\n")

cat("Next steps:\n")
cat("  1. Examine influential participants: loocv_cooks_d.rds %>% filter(influential_4)\n")
cat("  2. Cross-reference with low log_posterior to identify potential inauthenticity\n")
cat("  3. Investigate which parameters are most affected (high diff values)\n")
cat("\n")

cat("[OK] Cook's D influence diagnostics complete!\n")
cat("\n")

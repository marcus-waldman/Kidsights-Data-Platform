# ============================================================================
# Script 33: Compute KL Divergence Raking Weights (24 Variables)
# ============================================================================
#
# Purpose: Calculate survey weights that match population targets via KL divergence minimization
#
# Inputs:
#   - data/raking/ne25/ne25_harmonized/ne25_harmonized_m1.feather (2,785 × 27)
#   - data/raking/ne25/unified_moments.rds (24-variable targets: μ, Σ, n_eff)
#
# Method:
#   - Stan optimization: minimize KL(target || achieved)
#   - Linear model: log(wgt[i]) = α + X[i,] β
#   - Matches 24 means + factorized 24×24 covariance structure
#
# Outputs:
#   - data/raking/ne25/ne25_weights/ne25_calibrated_weights_m1.feather
#   - data/raking/ne25/ne25_weights/calibration_diagnostics_m1.rds
#
# Block Structure (24 variables):
#   Block 1: Demographics + PUMA (21 variables)
#     - Demographics (7): pooled ACS/NHIS/NSCH
#     - PUMA (14): ACS-only geographic stratification
#   Block 2: Mental Health (2 variables, NHIS-only)
#   Block 3: Child Outcome (1 variable, NSCH-only)
#
# Factorized Covariance:
#   - Observed blocks: Demographics×Demographics, PUMA×PUMA, Demographics×PUMA,
#                      Demographics×MentalHealth, Demographics×ChildOutcome
#   - Unobserved blocks (set to 0): PUMA×MentalHealth, PUMA×ChildOutcome,
#                                    MentalHealth×ChildOutcome
#
# Execution time: ~2-5 minutes (Stan optimization with K=24)
#
# Author: Generated via Claude Code
# Date: December 2025
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

# Source the simplex Stan wrapper (handles incomplete covariance structure)
# NOTE: Using simplex parameterization for flexibility with 24 variables
source("scripts/raking/ne25/utils/calibrate_weights_simplex_factorized_cmdstan.R")

# ============================================================================
# [1] Load NE25 Harmonized Data
# ============================================================================

cat("\n========================================\n")
cat("SCRIPT 33: KL DIVERGENCE RAKING WEIGHTS\n")
cat("========================================\n\n")

cat("[1] Loading NE25 harmonized data (imputation m=1)...\n\n")

harmonized_file <- "data/raking/ne25/ne25_harmonized/ne25_harmonized_m1.feather"

if (!file.exists(harmonized_file)) {
  stop(sprintf("Harmonized data not found: %s\nRun script 32 first.", harmonized_file))
}

ne25 <- arrow::read_feather(harmonized_file)

cat(sprintf("    Loaded: %d records × %d columns\n", nrow(ne25), ncol(ne25)))
cat(sprintf("    Expected: 3 identifiers + 24 variables = 27 columns\n\n"))

# Validate structure
expected_cols <- c("pid", "record_id", "study_id",
                   "male", "age", "white_nh", "black", "hispanic",
                   "educ_years", "poverty_ratio",
                   sprintf("puma_%d", c(100, 200, 300, 400, 500, 600, 701, 702,
                                        801, 802, 901, 902, 903, 904)),
                   "phq2_total", "gad2_total", "excellent_health")

missing_cols <- setdiff(expected_cols, names(ne25))
if (length(missing_cols) > 0) {
  stop(sprintf("Missing expected columns: %s", paste(missing_cols, collapse = ", ")))
}

# ============================================================================
# [2] Load Unified Moments (24-variable targets)
# ============================================================================

cat("[2] Loading unified moments (24-variable targets)...\n\n")

moments_file <- "data/raking/ne25/unified_moments.rds"

if (!file.exists(moments_file)) {
  stop(sprintf("Unified moments not found: %s\nRun script 30b first.", moments_file))
}

unified <- readRDS(moments_file)

cat("    Loaded unified moments structure:\n")
cat(sprintf("      - Target mean vector (μ): %d elements\n", length(unified$mu)))
cat(sprintf("      - Target covariance matrix (Σ): %d × %d\n",
            nrow(unified$Sigma), ncol(unified$Sigma)))
cat(sprintf("      - Variable names: %d variables\n", length(unified$variable_names)))
cat(sprintf("      - Effective sample sizes: Block 1=%.1f, Block 2=%.1f, Block 3=%.1f\n\n",
            unified$n_eff$block1, unified$n_eff$block2, unified$n_eff$block3))

# Validate dimensions
if (length(unified$mu) != 24) {
  stop(sprintf("Expected 24-element mean vector, got %d", length(unified$mu)))
}

if (!all(dim(unified$Sigma) == c(24, 24))) {
  stop(sprintf("Expected 24×24 covariance matrix, got %d × %d",
               nrow(unified$Sigma), ncol(unified$Sigma)))
}

# ============================================================================
# [3] Prepare Calibration Variables
# ============================================================================

cat("[3] Preparing calibration variables for Stan...\n\n")

# Define 24 calibration variables (ordered to match unified moments)
calibration_vars <- unified$variable_names

cat("    Calibration variables (24 total):\n\n")
cat("      Block 1 - Demographics (7):\n")
cat(sprintf("        %s\n", paste(calibration_vars[1:7], collapse = ", ")))
cat("\n      Block 1 - PUMA (14):\n")
cat(sprintf("        %s\n", paste(calibration_vars[8:21], collapse = ", ")))
cat("\n      Block 2 - Mental Health (2):\n")
cat(sprintf("        %s\n", paste(calibration_vars[22:23], collapse = ", ")))
cat("\n      Block 3 - Child Outcome (1):\n")
cat(sprintf("        %s\n\n", calibration_vars[24]))

# Check for missing values in calibration variables
missing_check <- ne25 %>%
  dplyr::select(dplyr::all_of(calibration_vars)) %>%
  dplyr::summarise(dplyr::across(dplyr::everything(), ~sum(is.na(.))))

n_missing_total <- sum(as.numeric(missing_check[1, ]))

cat("    Missing values check:\n")
if (n_missing_total > 0) {
  cat("[WARNING] Missing values detected in calibration variables:\n")
  for (var in names(missing_check)) {
    n_miss <- as.numeric(missing_check[1, var])
    if (n_miss > 0) {
      cat(sprintf("      %s: %d / %d (%.1f%%)\n",
                  var, n_miss, nrow(ne25), n_miss / nrow(ne25) * 100))
    }
  }
  cat("\n      Strategy: Listwise deletion for calibration (observations with ANY missing values excluded)\n")
  cat("                This maintains consistency with unified moments computation.\n\n")

  # Filter to complete cases
  ne25_complete <- ne25 %>%
    dplyr::filter(!dplyr::if_any(dplyr::all_of(calibration_vars), is.na))

  cat(sprintf("      Complete cases: %d / %d (%.1f%%)\n\n",
              nrow(ne25_complete), nrow(ne25), nrow(ne25_complete) / nrow(ne25) * 100))
} else {
  cat("      [OK] All calibration variables complete - no missing data\n\n")
  ne25_complete <- ne25
}

# ============================================================================
# [4] Run Stan Optimization
# ============================================================================

cat("[4] Running Stan KL divergence optimization...\n\n")

cat("    Model: Linear calibration (K+1 parameters)\n")
cat(sprintf("      - Intercept (α): 1 parameter\n"))
cat(sprintf("      - Coefficients (β): %d parameters (one per calibration variable)\n",
            length(calibration_vars)))
cat(sprintf("      - Total parameters: %d\n\n", length(calibration_vars) + 1))

cat("    Objective: Minimize KL(target || achieved)\n")
cat("      - Matches 24 target means (μ)\n")
cat("      - Matches factorized 24×24 covariance structure (Σ)\n")
cat("      - Factorization: Observed blocks from ACS/NHIS/NSCH, unobserved cross-blocks set to 0\n\n")

cat("    Stan optimization settings:\n")
cat("      - Algorithm: BFGS (full Hessian)\n")
cat("      - Convergence: Strict tolerances (1e-10 gradient, 1e-6 objective)\n")
cat("      - Max iterations: 10,000\n\n")

cat("    NOTE: This may take 2-5 minutes for K=24 variables...\n\n")

# Call simplex Stan optimization wrapper
calibration_result <- calibrate_weights_simplex_factorized_stan(
  data = ne25_complete,
  target_mean = unified$mu,
  target_cov = unified$Sigma,
  cov_mask = unified$cov_mask,
  calibration_vars = calibration_vars,
  min_weight = 1E-2,         # Minimum weight per observation
  max_weight = 100,        # Maximum weight per observation
  concentration = 1.0,      # Dirichlet prior (1.0 = uniform)
  verbose = TRUE, 
  history_size = 500, 
  refresh = 20, 
  iter = 5000
)

# ============================================================================
# [5] Save Calibrated Weights
# ============================================================================

cat("[5] Saving calibrated weights...\n\n")

# Create output directory
output_dir <- "data/raking/ne25/ne25_weights"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
  cat(sprintf("    Created directory: %s\n", output_dir))
}

# Prepare output: complete cases with weights
output_data <- ne25_complete %>%
  dplyr::mutate(calibrated_weight = calibration_result$calibrated_weight)

output_file <- file.path(output_dir, "ne25_calibrated_weights_m1.feather")
arrow::write_feather(output_data, output_file)

cat(sprintf("    Saved: %s\n", output_file))
cat(sprintf("      - %d records × %d columns\n", nrow(output_data), ncol(output_data)))
cat(sprintf("      - New column: calibrated_weight\n\n"))

# Save diagnostics
diagnostics <- list(
  converged = calibration_result$converged,
  alpha = calibration_result$alpha,
  beta = calibration_result$beta,
  beta_names = calibration_result$beta_names,
  final_marginals = calibration_result$final_marginals,
  effective_n = calibration_result$effective_n,
  efficiency_pct = calibration_result$efficiency_pct,
  weight_ratio = calibration_result$weight_ratio,
  log_prob = calibration_result$log_prob,
  n_complete_cases = nrow(ne25_complete),
  n_total_cases = nrow(ne25),
  completion_rate = nrow(ne25_complete) / nrow(ne25) * 100,
  target_mean = unified$mu,
  target_cov = unified$Sigma,
  variable_names = unified$variable_names,
  n_eff_blocks = unified$n_eff,
  pooling_weights = unified$pooling_weights
)

diagnostics_file <- file.path(output_dir, "calibration_diagnostics_m1.rds")
saveRDS(diagnostics, diagnostics_file)

cat(sprintf("    Saved: %s\n\n", diagnostics_file))

# ============================================================================
# [6] Summary Report
# ============================================================================

cat("\n========================================\n")
cat("CALIBRATION SUMMARY\n")
cat("========================================\n\n")

cat("Input Data:\n")
cat(sprintf("  - Total NE25 records: %d\n", nrow(ne25)))
cat(sprintf("  - Complete cases: %d (%.1f%%)\n",
            nrow(ne25_complete), nrow(ne25_complete) / nrow(ne25) * 100))
cat(sprintf("  - Calibration variables: %d\n\n", length(calibration_vars)))

cat("Target Moments:\n")
cat(sprintf("  - Block 1 effective N: %.1f (%.1f%% ACS, %.1f%% NHIS, %.1f%% NSCH)\n",
            unified$n_eff$block1,
            unified$pooling_weights$acs * 100,
            unified$pooling_weights$nhis * 100,
            unified$pooling_weights$nsch * 100))
cat(sprintf("  - Block 2 effective N: %.1f (NHIS)\n", unified$n_eff$block2))
cat(sprintf("  - Block 3 effective N: %.1f (NSCH)\n\n", unified$n_eff$block3))

cat("Calibration Results:\n")
cat(sprintf("  - Convergence: %s\n",
            ifelse(calibration_result$converged, "[OK] Achieved", "[WARNING] Not achieved")))
cat(sprintf("  - Effective N (Kish): %.1f\n", calibration_result$effective_n))
cat(sprintf("  - Efficiency: %.1f%%\n", calibration_result$efficiency_pct))
cat(sprintf("  - Weight ratio (max/min): %.2f\n\n", calibration_result$weight_ratio))

cat("Marginal Accuracy:\n")
max_pct_diff <- max(calibration_result$final_marginals$Pct_Diff)
cat(sprintf("  - Max percent difference: %.2f%%\n", max_pct_diff))

# Show variables with >1% difference
large_diff <- calibration_result$final_marginals %>%
  dplyr::filter(Pct_Diff > 1.0) %>%
  dplyr::arrange(dplyr::desc(Pct_Diff))

if (nrow(large_diff) > 0) {
  cat("\n  Variables with >1%% difference from targets:\n")
  for (i in 1:nrow(large_diff)) {
    cat(sprintf("    %s: %.2f%% (target: %.4f, achieved: %.4f)\n",
                large_diff$Variable[i], large_diff$Pct_Diff[i],
                large_diff$Target[i], large_diff$Achieved[i]))
  }
} else {
  cat("  [OK] All variables within 1%% of targets\n")
}

cat("\n========================================\n")
cat("SCRIPT 33 COMPLETE\n")
cat("========================================\n\n")

cat("Next Steps:\n")
cat("  1. Review calibration diagnostics in calibration_diagnostics_m1.rds\n")
cat("  2. Validate weight distributions and effective sample size\n")
cat("  3. Use ne25_calibrated_weights_m1.feather for weighted analyses\n")
cat("  4. Apply weights to all M=5 imputations (repeat for m2-m5)\n\n")

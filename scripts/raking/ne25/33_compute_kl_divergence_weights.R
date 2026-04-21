# ============================================================================
# Script 33: Compute KL Divergence Raking Weights (24 Variables)
# ============================================================================
#
# Purpose: Produce M calibrated weight sets (one per imputation) by running
#          masked KL-divergence / moment-matching optimization in Stan for
#          each of the M harmonized datasets emitted by script 32.
#
# Inputs (per imputation m):
#   - data/raking/ne25/ne25_harmonized/ne25_harmonized_m{m}.feather
#   - data/raking/ne25/unified_moments.rds  (shared across imputations)
#
# Outputs (per imputation m):
#   - data/raking/ne25/ne25_weights/ne25_calibrated_weights_m{m}.feather
#   - data/raking/ne25/ne25_weights/calibration_diagnostics_m{m}.rds
#
# Method:
#   - Simplex-N Stan parameterization (one weight per observation).
#   - Dirichlet(1) prior (flat over simplex).
#   - Masked moment-matching loss: all 24 means + 488 observed cells of the
#     24x24 target covariance (see WEIGHT_CONSTRUCTION.qmd section 3.3).
#   - cmdstanr compiles the Stan model once and caches it at ~/.cmdstanr/,
#     so iterations 2..M skip compilation.
#
# Block Structure (24 variables):
#   Block 1: Demographics + PUMA (21 variables)
#     - Demographics (7): pooled ACS/NHIS/NSCH
#     - PUMA (14): ACS-only geographic stratification
#   Block 2: Mental Health (2 variables, NHIS-only)
#   Block 3: Child Outcome (1 variable, NSCH-only)
#
# Typical timing: ~3 min per imputation; ~15 min total for M=5.
#
# Part of NE25 Bucket 2 (multi-imputation integration). See
# docs/archive/raking/ne25/ne25_weights_roadmap.md and WEIGHT_CONSTRUCTION.qmd section 5.1.
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
})

source("scripts/raking/ne25/utils/calibrate_weights_simplex_factorized_cmdstan.R")
source("R/imputation/config.R")  # for get_n_imputations()

# ============================================================================
# [0] Shared Setup (once; independent of m)
# ============================================================================

cat("\n========================================\n")
cat("SCRIPT 33: KL DIVERGENCE RAKING WEIGHTS (M imputations)\n")
cat("========================================\n\n")

M <- get_n_imputations()
cat(sprintf("Number of imputations (from config): M = %d\n\n", M))

# Unified moments are imputation-invariant — load once
moments_file <- "data/raking/ne25/unified_moments.rds"
if (!file.exists(moments_file)) {
  stop(sprintf("Unified moments not found: %s\nRun script 30b first.", moments_file))
}
unified <- readRDS(moments_file)

if (length(unified$mu) != 24) {
  stop(sprintf("Expected 24-element mean vector, got %d", length(unified$mu)))
}
if (!all(dim(unified$Sigma) == c(24, 24))) {
  stop(sprintf("Expected 24x24 covariance matrix, got %d x %d",
               nrow(unified$Sigma), ncol(unified$Sigma)))
}

calibration_vars <- unified$variable_names
cat(sprintf("Unified moments loaded: %d variables, n_eff blocks = (%.0f, %.0f, %.0f)\n",
            length(calibration_vars),
            unified$n_eff$block1, unified$n_eff$block2, unified$n_eff$block3))

# Validate expected columns (same check for every m)
expected_cols <- c("pid", "record_id", "study_id",
                   "male", "age", "white_nh", "black", "hispanic",
                   "educ_years", "poverty_ratio",
                   sprintf("puma_%d", c(100, 200, 300, 400, 500, 600, 701, 702,
                                        801, 802, 901, 902, 903, 904)),
                   "phq2_total", "gad2_total", "excellent_health")

output_dir <- "data/raking/ne25/ne25_weights"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# ============================================================================
# [1] Per-Imputation Calibration Loop
# ============================================================================

all_diagnostics <- vector("list", M)

for (m in seq_len(M)) {
  cat(sprintf("\n----------------------------------------\n"))
  cat(sprintf("  Calibrating imputation m = %d of %d\n", m, M))
  cat(sprintf("----------------------------------------\n"))

  harmonized_file <- sprintf(
    "data/raking/ne25/ne25_harmonized/ne25_harmonized_m%d.feather", m
  )
  if (!file.exists(harmonized_file)) {
    stop(sprintf("Harmonized file not found: %s\nRun script 32 first.",
                 harmonized_file))
  }

  ne25 <- arrow::read_feather(harmonized_file)
  cat(sprintf("[1a] Loaded: %d records x %d columns (from %s)\n",
              nrow(ne25), ncol(ne25), basename(harmonized_file)))

  missing_cols <- setdiff(expected_cols, names(ne25))
  if (length(missing_cols) > 0) {
    stop(sprintf("Missing expected columns in m=%d: %s",
                 m, paste(missing_cols, collapse = ", ")))
  }

  # Listwise-delete any residual NAs in calibration vars (should be zero per
  # script 32's fallback mice step; kept as a safety net)
  missing_counts <- colSums(is.na(ne25[, calibration_vars]))
  if (any(missing_counts > 0)) {
    cat("[1b] [WARN] Residual NAs in calibration vars after script 32:\n")
    for (v in names(missing_counts)[missing_counts > 0]) {
      cat(sprintf("      %s: %d\n", v, missing_counts[v]))
    }
    ne25_complete <- ne25 %>%
      dplyr::filter(!dplyr::if_any(dplyr::all_of(calibration_vars), is.na))
    cat(sprintf("      Complete cases retained: %d / %d\n",
                nrow(ne25_complete), nrow(ne25)))
  } else {
    ne25_complete <- ne25
    cat(sprintf("[1b] All %d calibration inputs complete (no NAs)\n",
                nrow(ne25_complete)))
  }

  # --------------------------------------------------------------------------
  # [1c] Run Stan optimization (cmdstanr caches the compiled model)
  # --------------------------------------------------------------------------
  cat(sprintf("[1c] Running Stan (simplex-N, history_size=50, iter=1000)...\n"))

  calibration_result <- calibrate_weights_simplex_factorized_stan(
    data = ne25_complete,
    target_mean = unified$mu,
    target_cov = unified$Sigma,
    cov_mask = unified$cov_mask,
    calibration_vars = calibration_vars,
    min_weight = 1E-2,
    max_weight = 100,
    concentration = 1,
    verbose = TRUE,
    history_size = 50,
    refresh = 20,
    iter = 1000
  )

  # --------------------------------------------------------------------------
  # [1d] Save weights feather
  # --------------------------------------------------------------------------
  output_data <- ne25_complete %>%
    dplyr::mutate(calibrated_weight = calibration_result$calibrated_weight)

  output_file <- file.path(
    output_dir, sprintf("ne25_calibrated_weights_m%d.feather", m)
  )
  arrow::write_feather(output_data, output_file)
  cat(sprintf("[1d] Saved: %s (%d records)\n",
              output_file, nrow(output_data)))

  # --------------------------------------------------------------------------
  # [1e] Save diagnostics RDS
  # --------------------------------------------------------------------------
  diagnostics <- list(
    imputation_m = m,
    stan_terminated_normally = calibration_result$stan_terminated_normally,
    stan_return_code = calibration_result$stan_return_code,
    marginals_within_1pct = calibration_result$marginals_within_1pct,
    converged = calibration_result$marginals_within_1pct,  # deprecated alias
    final_marginals = calibration_result$final_marginals,
    effective_n = calibration_result$effective_n,
    efficiency_pct = calibration_result$efficiency_pct,
    weight_ratio = calibration_result$weight_ratio,
    log_prob = calibration_result$log_prob,
    unweighted_rmse_corr = calibration_result$unweighted_rmse_corr,
    weighted_rmse_corr = calibration_result$weighted_rmse_corr,
    correlation_improvement_pct = calibration_result$correlation_improvement_pct,
    unweighted_correlations = calibration_result$unweighted_correlations,
    target_correlations = calibration_result$target_correlations,
    weighted_correlations = calibration_result$weighted_correlations,
    correlation_improvements_by_pair = calibration_result$correlation_improvements,
    n_complete_cases = nrow(ne25_complete),
    n_total_cases = nrow(ne25),
    completion_rate = nrow(ne25_complete) / nrow(ne25) * 100,
    target_mean = unified$mu,
    target_cov = unified$Sigma,
    variable_names = unified$variable_names,
    n_eff_blocks = unified$n_eff,
    pooling_weights = unified$pooling_weights
  )
  diagnostics_file <- file.path(
    output_dir, sprintf("calibration_diagnostics_m%d.rds", m)
  )
  saveRDS(diagnostics, diagnostics_file)
  cat(sprintf("[1e] Saved: %s\n", diagnostics_file))

  # --------------------------------------------------------------------------
  # [1f] Per-imputation summary
  # --------------------------------------------------------------------------
  max_pct_diff <- max(calibration_result$final_marginals$Pct_Diff)
  cat(sprintf("[1f] m=%d: Kish N=%.1f, efficiency=%.1f%%, ratio=%.2f, max|Pct_Diff|=%.2f%%\n",
              m,
              calibration_result$effective_n,
              calibration_result$efficiency_pct,
              calibration_result$weight_ratio,
              max_pct_diff))

  all_diagnostics[[m]] <- diagnostics
}

# ============================================================================
# [2] Cross-Imputation Summary
# ============================================================================

cat("\n========================================\n")
cat("CROSS-IMPUTATION SUMMARY\n")
cat("========================================\n\n")

summary_tbl <- data.frame(
  m                  = seq_len(M),
  n                  = vapply(all_diagnostics, function(d) d$n_complete_cases, integer(1)),
  stan_ok            = vapply(all_diagnostics, function(d) d$stan_terminated_normally, logical(1)),
  within_1pct        = vapply(all_diagnostics, function(d) d$marginals_within_1pct, logical(1)),
  kish_n             = vapply(all_diagnostics, function(d) d$effective_n, numeric(1)),
  efficiency_pct     = vapply(all_diagnostics, function(d) d$efficiency_pct, numeric(1)),
  weight_ratio       = vapply(all_diagnostics, function(d) d$weight_ratio, numeric(1)),
  corr_rmse_weighted = vapply(all_diagnostics, function(d) d$weighted_rmse_corr, numeric(1))
)

print(summary_tbl, row.names = FALSE, digits = 4)

kish_cv <- stats::sd(summary_tbl$kish_n) / mean(summary_tbl$kish_n)
rmse_range <- diff(range(summary_tbl$corr_rmse_weighted))

cat(sprintf("\nAcceptance checks:\n"))
cat(sprintf("  Kish N coefficient of variation: %.3f (target < 0.05)\n", kish_cv))
cat(sprintf("  Correlation RMSE range:          %.5f (target < 0.005)\n", rmse_range))
cat(sprintf("  Stan terminated normally in all: %s\n",
            ifelse(all(summary_tbl$stan_ok), "YES", "NO")))

cat("\n========================================\n")
cat("SCRIPT 33 COMPLETE\n")
cat("========================================\n\n")

cat("Next step: run scripts/raking/ne25/34_store_raked_weights_long.R\n")
cat("to insert the M weight sets into the ne25_raked_weights DuckDB table.\n")

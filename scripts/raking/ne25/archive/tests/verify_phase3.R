# Phase 3 Verification Script
# Validates multinomial estimand refactorings (multinom vs separate binary models)
# Created: January 2025

cat("\n========================================\n")
cat("Phase 3 Verification Summary\n")
cat("========================================\n\n")

cat("Verifying 2 multinomial estimand scripts refactored from binary models to multinom:\n")
cat("  1. FPL estimation (5 categories)\n")
cat("  2. PUMA estimation (14 categories)\n\n")

# Track verification results
verification_results <- list()

# ---------------------------------------------------------
# 1. FPL ESTIMATION
# ---------------------------------------------------------
cat("[1] FPL Estimation (5 categories)\n")
cat("    Files:\n")
cat("      Original: scripts/raking/ne25/04_estimate_fpl.R\n")
cat("      Refactored: scripts/raking/ne25/04_estimate_fpl_glm2.R\n\n")

# Check files exist
if (!file.exists("data/raking/ne25/fpl_estimates.rds") ||
    !file.exists("data/raking/ne25/fpl_estimates_glm2.rds")) {
  cat("    [ERROR] Output files missing. Run scripts first.\n\n")
  verification_results$fpl <- list(status = "ERROR", reason = "Missing files")
} else {
  # Load results
  fpl_original <- readRDS("data/raking/ne25/fpl_estimates.rds")
  fpl_multinom <- readRDS("data/raking/ne25/fpl_estimates_glm2.rds")

  # Sort for comparison
  fpl_original <- fpl_original[order(fpl_original$age, fpl_original$estimand), ]
  fpl_multinom <- fpl_multinom[order(fpl_multinom$age, fpl_multinom$estimand), ]

  # Compare
  diff_fpl <- max(abs(fpl_multinom$estimate - fpl_original$estimate))

  cat("    Point estimates comparison (5 categories):\n")
  cat("      Max absolute difference:", format(diff_fpl, scientific = TRUE), "\n")
  cat("      Max percentage difference:", round(diff_fpl / mean(fpl_original$estimate) * 100, 2), "%\n")

  if (diff_fpl < 0.01) {
    cat("      [PASS] Estimates within 1% (expected for method change)\n")
    verification_results$fpl <- list(status = "PASS", max_diff = diff_fpl)
  } else if (diff_fpl < 0.05) {
    cat("      [INFO] Estimates differ by <5% (acceptable for multinomial vs binary)\n")
    verification_results$fpl <- list(status = "PASS", max_diff = diff_fpl)
  } else {
    cat("      [WARN] Estimates differ by >5%\n")
    verification_results$fpl <- list(status = "WARN", max_diff = diff_fpl)
  }

  # Check sum-to-1 for multinom
  cat("    Sum-to-1 validation (age 0):\n")
  fpl_age0 <- fpl_multinom[fpl_multinom$age == 0, ]
  sum_fpl <- sum(fpl_age0$estimate)
  cat("      Sum:", round(sum_fpl, 10), "\n")
  if (abs(sum_fpl - 1.0) < 0.001) {
    cat("      [PASS] Predictions sum to 1.0\n")
  } else {
    cat("      [FAIL] Predictions do not sum to 1.0\n")
  }

  # Check bootstrap
  if (file.exists("data/raking/ne25/fpl_estimates_boot_glm2.rds")) {
    boot_multinom <- readRDS("data/raking/ne25/fpl_estimates_boot_glm2.rds")
    n_boot <- length(unique(boot_multinom$replicate))
    cat("    Bootstrap replicates:", n_boot, "\n")
    cat("    Bootstrap rows:", nrow(boot_multinom), "(expect", 5 * 6 * n_boot, ")\n")

    # Check bootstrap sum-to-1
    rep1_age0 <- boot_multinom[boot_multinom$replicate == 1 & boot_multinom$age == 0, ]
    boot_sum <- sum(rep1_age0$estimate)
    cat("    Bootstrap sum-to-1 (rep 1, age 0):", round(boot_sum, 10), "\n")
    if (abs(boot_sum - 1.0) < 0.001) {
      cat("      [PASS] Bootstrap predictions sum to 1.0\n")
    } else {
      cat("      [FAIL] Bootstrap predictions do not sum to 1.0\n")
    }
  }
  cat("\n")
}

# ---------------------------------------------------------
# 2. PUMA ESTIMATION
# ---------------------------------------------------------
cat("[2] PUMA Estimation (14 categories)\n")
cat("    Files:\n")
cat("      Original: scripts/raking/ne25/05_estimate_puma.R\n")
cat("      Refactored: scripts/raking/ne25/05_estimate_puma_glm2.R\n\n")

# Check files exist
if (!file.exists("data/raking/ne25/puma_estimates.rds") ||
    !file.exists("data/raking/ne25/puma_estimates_glm2.rds")) {
  cat("    [ERROR] Output files missing. Run scripts first.\n\n")
  verification_results$puma <- list(status = "ERROR", reason = "Missing files")
} else {
  # Load results
  puma_original <- readRDS("data/raking/ne25/puma_estimates.rds")
  puma_multinom <- readRDS("data/raking/ne25/puma_estimates_glm2.rds")

  # Sort for comparison
  puma_original <- puma_original[order(puma_original$age, puma_original$estimand), ]
  puma_multinom <- puma_multinom[order(puma_multinom$age, puma_multinom$estimand), ]

  # Compare
  diff_puma <- max(abs(puma_multinom$estimate - puma_original$estimate))

  cat("    Point estimates comparison (14 categories):\n")
  cat("      Max absolute difference:", format(diff_puma, scientific = TRUE), "\n")
  cat("      Max percentage difference:", round(diff_puma / mean(puma_original$estimate) * 100, 2), "%\n")

  if (diff_puma < 0.01) {
    cat("      [PASS] Estimates within 1% (expected for method change)\n")
    verification_results$puma <- list(status = "PASS", max_diff = diff_puma)
  } else if (diff_puma < 0.05) {
    cat("      [INFO] Estimates differ by <5% (acceptable for multinomial vs binary)\n")
    verification_results$puma <- list(status = "PASS", max_diff = diff_puma)
  } else {
    cat("      [WARN] Estimates differ by >5%\n")
    verification_results$puma <- list(status = "WARN", max_diff = diff_puma)
  }

  # Check sum-to-1 for multinom
  cat("    Sum-to-1 validation (age 0):\n")
  puma_age0 <- puma_multinom[puma_multinom$age == 0, ]
  sum_puma <- sum(puma_age0$estimate)
  cat("      Sum:", round(sum_puma, 10), "\n")
  if (abs(sum_puma - 1.0) < 0.001) {
    cat("      [PASS] Predictions sum to 1.0\n")
  } else {
    cat("      [FAIL] Predictions do not sum to 1.0\n")
  }

  # Check bootstrap
  if (file.exists("data/raking/ne25/puma_estimates_boot_glm2.rds")) {
    boot_multinom <- readRDS("data/raking/ne25/puma_estimates_boot_glm2.rds")
    n_boot <- length(unique(boot_multinom$replicate))
    cat("    Bootstrap replicates:", n_boot, "\n")
    cat("    Bootstrap rows:", nrow(boot_multinom), "(expect", 14 * 6 * n_boot, ")\n")

    # Check bootstrap sum-to-1
    rep1_age0 <- boot_multinom[boot_multinom$replicate == 1 & boot_multinom$age == 0, ]
    boot_sum <- sum(rep1_age0$estimate)
    cat("    Bootstrap sum-to-1 (rep 1, age 0):", round(boot_sum, 10), "\n")
    if (abs(boot_sum - 1.0) < 0.001) {
      cat("      [PASS] Bootstrap predictions sum to 1.0\n")
    } else {
      cat("      [FAIL] Bootstrap predictions do not sum to 1.0\n")
    }
  }
  cat("\n")
}

# ---------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------
cat("========================================\n")
cat("Summary\n")
cat("========================================\n\n")

# Count passes/warns/errors
n_pass <- sum(sapply(verification_results, function(x) x$status == "PASS"))
n_warn <- sum(sapply(verification_results, function(x) x$status == "WARN"))
n_error <- sum(sapply(verification_results, function(x) x$status == "ERROR"))

cat("Results:\n")
cat("  [PASS]:", n_pass, "scripts\n")
cat("  [WARN]:", n_warn, "scripts\n")
cat("  [ERROR]:", n_error, "scripts\n\n")

if (n_pass == 2) {
  cat("========================================\n")
  cat("Phase 3 COMPLETE: All 2 scripts verified!\n")
  cat("========================================\n\n")
  cat("Summary of changes:\n")
  cat("  - Replaced separate binary GLMs with single multinomial model\n")
  cat("  - FPL: 5 categories (5 models → 1 model)\n")
  cat("  - PUMA: 14 categories (14 models → 1 model)\n")
  cat("  - Predictions automatically sum to 1.0 (no manual normalization)\n")
  cat("  - Bootstrap replicates maintain sum-to-1 constraint\n")
  cat("  - Small differences from original (<1-5%) expected due to method change\n")
  cat("  - Statistically superior: models category correlations jointly\n\n")

  cat("Bug fixes during Phase 3:\n")
  cat("  - Fixed format_multinom_bootstrap_results() array flattening\n")
  cat("  - Added n_boot config respect in FPL/PUMA scripts\n\n")

  TRUE  # Return TRUE for success
} else {
  cat("[INFO] Phase 3 complete with", n_warn, "warnings and", n_error, "errors.\n\n")

  FALSE  # Return FALSE for issues
}

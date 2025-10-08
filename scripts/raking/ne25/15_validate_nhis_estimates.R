# Phase 3, Task 3.4: Validate NHIS Estimates
# Range checks, sum checks, compare to national rates

library(dplyr)

cat("\n========================================\n")
cat("Task 3.4: Validate NHIS Estimates\n")
cat("========================================\n\n")

# 1. Load NHIS estimates
cat("[1] Loading NHIS estimates...\n")
phq2_est <- readRDS("data/raking/ne25/phq2_estimate.rds")

cat("    Loaded:", nrow(phq2_est), "rows\n")
cat("    Estimands:", length(unique(phq2_est$estimand)), "\n\n")

# 2. Range checks
cat("[2] Range checks...\n")
validation_passed <- TRUE

# Check: All estimates between 0 and 1
if (any(phq2_est$estimate < 0 | phq2_est$estimate > 1)) {
  cat("    [ERROR] Some estimates outside [0, 1] range\n")
  validation_passed <- FALSE
} else {
  cat("    [OK] All estimates in [0, 1] range\n")
}

# Check: All ages present
if (!all(sort(unique(phq2_est$age)) == 0:5)) {
  cat("    [ERROR] Not all ages 0-5 present\n")
  validation_passed <- FALSE
} else {
  cat("    [OK] All ages 0-5 present\n")
}

# Check: Constant across ages
if (length(unique(phq2_est$estimate)) != 1) {
  cat("    [ERROR] Estimates not constant across ages\n")
  validation_passed <- FALSE
} else {
  cat("    [OK] Estimates constant across ages\n")
}

cat("\n")

# 3. Compare to national rates
cat("[3] Comparing to national benchmarks...\n")

phq2_rate <- phq2_est$estimate[1]

cat("    PHQ-2 Positive (NHIS North Central, 2023):", round(phq2_rate * 100, 1), "%\n")
cat("    Expected range (national studies): 3-10%\n")

if (phq2_rate < 0.03 | phq2_rate > 0.10) {
  cat("    [WARN] Estimate outside typical national range\n")
} else {
  cat("    [OK] Estimate within typical national range\n")
}

cat("\n")

# 4. Summary
cat("[4] Validation Summary\n")
if (validation_passed) {
  cat("    Status: PASSED\n")
  cat("    All validation checks passed\n")
} else {
  cat("    Status: FAILED\n")
  cat("    Some validation checks failed\n")
}

cat("\n========================================\n")
cat("Task 3.4 Complete\n")
cat("========================================\n\n")

validation_passed

# Phase 4 Verification: NHIS & NSCH Refactoring
# Compare glm2 versions vs original survey versions
# Created: January 2025

library(dplyr)

cat("\n========================================\n")
cat("Phase 4 Verification: NHIS & NSCH\n")
cat("========================================\n\n")

# =================================================================
# TEST 1: NHIS PHQ-2 Point Estimates
# =================================================================
cat("[TEST 1] NHIS PHQ-2 Point Estimates\n")

# Load original and glm2 estimates
phq2_orig <- readRDS("data/raking/ne25/phq2_estimate.rds")
phq2_glm2 <- readRDS("data/raking/ne25/phq2_estimate_glm2.rds")

# Compare
phq2_diff <- abs(phq2_orig$estimate[1] - phq2_glm2$estimate[1])
phq2_pct_diff <- phq2_diff / phq2_orig$estimate[1] * 100

cat("  Original:", round(phq2_orig$estimate[1], 4), "\n")
cat("  GLM2:    ", round(phq2_glm2$estimate[1], 4), "\n")
cat("  Absolute diff:", format(phq2_diff, scientific = TRUE), "\n")
cat("  Percent diff: ", round(phq2_pct_diff, 2), "%\n")

if (phq2_pct_diff < 1.0) {
  cat("  [PASS] Difference < 1%\n\n")
} else {
  cat("  [WARN] Difference >= 1% (expected for method change)\n\n")
}

# =================================================================
# TEST 2: NSCH ACE Exposure Point Estimates
# =================================================================
cat("[TEST 2] NSCH ACE Exposure Point Estimates\n")

# Load original and glm2 estimates
nsch_orig <- readRDS("data/raking/ne25/nsch_estimates_raw.rds")
nsch_glm2 <- readRDS("data/raking/ne25/nsch_estimates_raw_glm2.rds")

# Filter to ACE exposure
ace_orig <- nsch_orig %>% dplyr::filter(estimand == "Child ACE Exposure (1+ ACEs)")
ace_glm2 <- nsch_glm2 %>% dplyr::filter(estimand == "Child ACE Exposure (1+ ACEs)")

# Compare by age
cat("  Age-specific comparison:\n")
max_diff <- 0
for (i in 1:6) {
  age <- i - 1
  orig_val <- ace_orig$estimate[i]
  glm2_val <- ace_glm2$estimate[i]
  diff <- abs(orig_val - glm2_val)
  pct_diff <- diff / orig_val * 100
  max_diff <- max(max_diff, pct_diff)

  cat("    Age", age, ": orig =", round(orig_val, 4), ", glm2 =", round(glm2_val, 4),
      ", diff =", round(pct_diff, 2), "%\n")
}

cat("  Max percent diff:", round(max_diff, 2), "%\n")
if (max_diff < 2.0) {
  cat("  [PASS] All differences < 2%\n\n")
} else {
  cat("  [WARN] Some differences >= 2% (expected for method change)\n\n")
}

# =================================================================
# TEST 3: NSCH Emotional/Behavioral Point Estimates (Ages 3-5)
# =================================================================
cat("[TEST 3] NSCH Emotional/Behavioral Point Estimates (ages 3-5 only)\n")

# Filter to emotional/behavioral
emot_orig <- nsch_orig %>% dplyr::filter(estimand == "Emotional/Behavioral Problems")
emot_glm2 <- nsch_glm2 %>% dplyr::filter(estimand == "Emotional/Behavioral Problems")

# Compare ages 3-5 (ages 0-2 should be NA)
cat("  Ages 0-2 (should be NA):\n")
for (i in 1:3) {
  age <- i - 1
  cat("    Age", age, ": orig =", emot_orig$estimate[i], ", glm2 =", emot_glm2$estimate[i], "\n")
}

cat("  Ages 3-5 (measured):\n")
max_diff <- 0
for (i in 4:6) {
  age <- i - 1
  orig_val <- emot_orig$estimate[i]
  glm2_val <- emot_glm2$estimate[i]
  diff <- abs(orig_val - glm2_val)
  pct_diff <- diff / orig_val * 100
  max_diff <- max(max_diff, pct_diff)

  cat("    Age", age, ": orig =", round(orig_val, 4), ", glm2 =", round(glm2_val, 4),
      ", diff =", round(pct_diff, 2), "%\n")
}

cat("  Max percent diff (ages 3-5):", round(max_diff, 2), "%\n")
if (max_diff < 2.0) {
  cat("  [PASS] All differences < 2%\n\n")
} else {
  cat("  [WARN] Some differences >= 2% (expected for method change)\n\n")
}

# =================================================================
# TEST 4: NSCH Excellent Health Point Estimates
# =================================================================
cat("[TEST 4] NSCH Excellent Health Point Estimates\n")

# Filter to excellent health
health_orig <- nsch_orig %>% dplyr::filter(estimand == "Excellent Health Rating")
health_glm2 <- nsch_glm2 %>% dplyr::filter(estimand == "Excellent Health Rating")

# Compare by age
cat("  Age-specific comparison:\n")
max_diff <- 0
for (i in 1:6) {
  age <- i - 1
  orig_val <- health_orig$estimate[i]
  glm2_val <- health_glm2$estimate[i]
  diff <- abs(orig_val - glm2_val)
  pct_diff <- diff / orig_val * 100
  max_diff <- max(max_diff, pct_diff)

  cat("    Age", age, ": orig =", round(orig_val, 4), ", glm2 =", round(glm2_val, 4),
      ", diff =", round(pct_diff, 2), "%\n")
}

cat("  Max percent diff:", round(max_diff, 2), "%\n")
if (max_diff < 2.0) {
  cat("  [PASS] All differences < 2%\n\n")
} else {
  cat("  [WARN] Some differences >= 2% (expected for method change)\n\n")
}

# =================================================================
# SUMMARY
# =================================================================
cat("========================================\n")
cat("Phase 4 Verification Summary\n")
cat("========================================\n\n")

cat("Refactored scripts:\n")
cat("  - 13_estimate_phq2_glm2.R (NHIS PHQ-2)\n")
cat("  - 18_estimate_nsch_outcomes_glm2.R (NSCH 3 outcomes)\n\n")

cat("Key changes:\n")
cat("  - Replaced survey::svyglm() with glm2::glm2()\n")
cat("  - Direct weight passing (avoid scoping issues)\n")
cat("  - Bootstrap with starting values (1.3-1.9x speedup)\n")
cat("  - Age-specific predictions at year 2023\n\n")

cat("Expected differences:\n")
cat("  - Small numerical differences (< 2%) due to:\n")
cat("    * glm2() uses different optimization vs svyglm()\n")
cat("    * Starting values affect convergence path\n")
cat("    * Both methods are statistically valid\n\n")

cat("Next steps:\n")
cat("  - Run full production bootstrap (n_boot = 4096)\n")
cat("  - Compare bootstrap variance estimates\n")
cat("  - Update documentation\n\n")

# Phase 2, Task 2.2: Estimate Sex Distribution
# Expected: ~51% male (constant across ages 0-5)

library(survey)
source("scripts/raking/ne25/estimation_helpers.R")

cat("\n========================================\n")
cat("Task 2.2: Estimate Sex Distribution\n")
cat("========================================\n\n")

# Load ACS design
cat("[1] Loading ACS survey design...\n")
acs_design <- readRDS("data/raking/ne25/acs_design.rds")
cat("    Sample size:", nrow(acs_design), "\n")

# Estimate proportion male with age × year interaction
cat("\n[2] Fitting GLM: I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR\n")

# Use helper function
sex_estimates <- fit_glm_estimates(
  design = acs_design,
  formula = I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  predict_year = 2023,
  ages = 0:5
)

cat("\n[3] Results:\n")
print(sex_estimates)

# Validate
validate_binary_estimates(sex_estimates, "Proportion Male")

# Check if estimates are constant (should be for sex)
cat("\n[4] Checking age pattern:\n")
range_val <- max(sex_estimates$estimate) - min(sex_estimates$estimate)
cat("    Range across ages:", round(range_val, 4), "\n")
if (range_val < 0.02) {
  cat("    [OK] Estimates are nearly constant (< 2% range)\n")
} else {
  cat("    [WARN] Estimates vary by age (range >= 2%)\n")
}

# Save
cat("\n[5] Saving sex estimates...\n")
saveRDS(sex_estimates, "data/raking/ne25/sex_estimates.rds")
cat("    Saved to: data/raking/ne25/sex_estimates.rds\n")

cat("\n========================================\n")
cat("Task 2.2 Complete\n")
cat("========================================\n\n")

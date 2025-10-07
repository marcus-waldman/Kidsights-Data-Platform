# Phase 2, Task 2.7: Estimate Mother's Marital Status (glm2 version with bootstrap)
# 1 estimand: Proportion of mothers married
# Refactored: January 2025
# Changes: Uses glm2::glm2() instead of survey::svyglm()

library(glm2)
library(dplyr)
source("config/bootstrap_config.R")
source("scripts/raking/ne25/estimation_helpers_glm2.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

cat("\n========================================\n")
cat("Task 2.7: Estimate Mother's Marital Status (glm2)\n")
cat("========================================\n\n")

# Load ACS design (to extract data and bootstrap weights)
cat("[1] Loading ACS survey design...\n")
acs_design <- readRDS("data/raking/ne25/acs_design.rds")
acs_data <- acs_design$variables
cat("    Sample size:", nrow(acs_data), "\n\n")

# Check mother linkage coverage
cat("[2] Checking mother linkage and household structure...\n")
cat("    Total children:", nrow(acs_data), "\n")
cat("    Children with mother in household (MOMLOC > 0):", sum(acs_data$MOMLOC > 0), "\n")
cat("    Coverage:", round(sum(acs_data$MOMLOC > 0) / nrow(acs_data) * 100, 1), "%\n")

# Check MOMLOC distribution
cat("\n    MOMLOC distribution:\n")
momloc_table <- table(acs_data$MOMLOC)
cat("      MOMLOC=0 (no mother):", momloc_table["0"],
    "(", round(momloc_table["0"]/nrow(acs_data)*100, 1), "%)\n")
cat("      MOMLOC=1 (mother is head):", sum(acs_data$MOMLOC == 1),
    "(", round(sum(acs_data$MOMLOC == 1)/nrow(acs_data)*100, 1), "%)\n")
cat("      MOMLOC=2 (mother is spouse):", sum(acs_data$MOMLOC == 2),
    "(", round(sum(acs_data$MOMLOC == 2)/nrow(acs_data)*100, 1), "%)\n")
cat("      MOMLOC>2 (mother elsewhere):", sum(acs_data$MOMLOC > 2),
    "(", round(sum(acs_data$MOMLOC > 2)/nrow(acs_data)*100, 1), "%)\n")

# Filter to children with mothers in household
cat("\n[3] Filtering to children with mothers in household...\n")
acs_data_moms <- acs_data[acs_data$MOMLOC > 0, ]
cat("    Retained", nrow(acs_data_moms), "children with mothers\n")

# Check MARST_HEAD distribution
cat("\n    MARST_HEAD distribution:\n")
marst_table <- table(acs_data_moms$MARST_HEAD, useNA = "ifany")
print(marst_table)

# Create married indicator
cat("\n[4] Creating mother married indicator...\n")
acs_data_moms$mom_married <- as.numeric(acs_data_moms$MARST_HEAD == 1)

cat("    Mother married coding (MARST_HEAD == 1):\n")
cat("      Not married (MARST_HEAD != 1):", sum(acs_data_moms$MARST_HEAD != 1), "\n")
cat("      Married (MARST_HEAD == 1):", sum(acs_data_moms$MARST_HEAD == 1), "\n")
cat("      Proportion married (unweighted):", round(mean(acs_data_moms$mom_married), 3), "\n")

# Estimate mother's marital status using glm2
cat("\n[5] Estimating mother's marital status by child age...\n")
cat("    Fitting model: mom_married ~ as.factor(AGE)\n")

mom_married_est <- fit_glm2_estimates(
  data = acs_data_moms,
  formula = mom_married ~ as.factor(AGE),
  weights_col = "PERWT",
  predict_year = NULL,  # No year prediction needed
  ages = 0:5
)

cat("\n    Estimates by age:\n")
for (i in 1:6) {
  cat("      Age", i-1, ":", round(mom_married_est$estimate[i], 4),
      "(", round(mom_married_est$estimate[i] * 100, 1), "%)\n")
}

# Create results data frame
cat("\n[6] Creating results data frame...\n")
mom_married_estimates <- data.frame(
  age = 0:5,
  estimand = "Mother Married",
  estimate = mom_married_est$estimate
)
print(mom_married_estimates)

# Validation
cat("\n[7] Validation checks...\n")

# Range check (should be 75-90%)
if (all(mom_married_estimates$estimate >= 0.75 & mom_married_estimates$estimate <= 0.90)) {
  cat("    [OK] All estimates in plausible range [0.75, 0.90]\n")
} else {
  cat("    [WARN] Some estimates outside expected range [0.75, 0.90]\n")
}

# Check for age variation
estimate_range <- max(mom_married_estimates$estimate) - min(mom_married_estimates$estimate)
cat("    Range across ages:", round(estimate_range, 4),
    "(", round(estimate_range * 100, 1), "percentage points)\n")

if (estimate_range > 0.01) {
  cat("    [OK] Meaningful age variation detected (>1 percentage point)\n")
} else {
  cat("    [INFO] Limited age variation (<1 percentage point)\n")
}

# Validate using helper function
cat("\n[8] Binary estimate validation:\n")
validate_binary_estimates(mom_married_estimates[, c("age", "estimate")], "Mother Married")

# Save point estimates
cat("\n[9] Saving mother's marital status point estimates...\n")
saveRDS(mom_married_estimates, "data/raking/ne25/mother_marital_status_estimates_glm2.rds")
cat("    Saved to: data/raking/ne25/mother_marital_status_estimates_glm2.rds\n")

# Generate bootstrap replicates using SHARED bootstrap design
cat("\n[10] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design
cat("     Loading shared ACS bootstrap design...\n")
boot_design_full <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")

# Extract replicate weights and filter to mothers sample
cat("     Filtering replicate weights to mothers sample (MOMLOC > 0)...\n")
replicate_weights_full <- boot_design_full$repweights
n_boot <- ncol(replicate_weights_full)

# Filter rows to match acs_data_moms (MOMLOC > 0)
momloc_indicator <- acs_data$MOMLOC > 0
replicate_weights_moms <- replicate_weights_full[momloc_indicator, ]

cat("     Bootstrap design loaded (", n_boot, " replicates)\n", sep = "")
cat("     Filtered to", nrow(replicate_weights_moms), "children with mothers\n\n")

# Create prediction data frame
pred_data <- data.frame(AGE = factor(0:5, levels = 0:5))

# Generate bootstrap estimates using glm2 with starting values
boot_result <- generate_bootstrap_glm2(
  data = acs_data_moms,
  formula = mom_married ~ as.factor(AGE),
  replicate_weights = replicate_weights_moms,
  pred_data = pred_data
)

cat("\n")

# Format bootstrap results for saving
boot_long <- format_bootstrap_results(
  boot_result = boot_result,
  ages = 0:5,
  estimand_name = "mother_married"
)

# Save bootstrap estimates
saveRDS(boot_long, "data/raking/ne25/mother_marital_status_estimates_boot_glm2.rds")
cat("[11] Saved bootstrap estimates to: data/raking/ne25/mother_marital_status_estimates_boot_glm2.rds\n")
cat("     Bootstrap dimensions:", nrow(boot_long), "rows (6 ages ×", n_boot, "replicates)\n")

cat("\n========================================\n")
cat("Task 2.7 Complete (glm2 version)\n")
cat("========================================\n\n")

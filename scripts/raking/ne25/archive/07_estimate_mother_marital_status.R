# Phase 2, Task 2.7: Estimate Mother's Marital Status (with bootstrap replicates)
# 1 estimand (age-stratified): Proportion of mothers married

library(survey)
source("scripts/raking/ne25/estimation_helpers.R")
source("scripts/raking/ne25/bootstrap_helpers.R")

cat("\n========================================\n")
cat("Task 2.7: Estimate Mother's Marital Status\n")
cat("========================================\n\n")

# Load ACS design
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

# 1. Check mother linkage coverage
cat("[1] Checking mother linkage and household structure...\n")
acs_data <- acs_design$variables

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

# 2. Filter to children with mothers
cat("\n[2] Filtering to children with mothers in household...\n")
acs_data_moms <- acs_data[acs_data$MOMLOC > 0, ]
cat("    Retained", nrow(acs_data_moms), "children with mothers\n")

# Check MARST_HEAD distribution
cat("\n    MARST_HEAD distribution:\n")
marst_table <- table(acs_data_moms$MARST_HEAD, useNA = "ifany")
print(marst_table)

# Create survey design with filtered data
acs_design_moms <- survey::svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_moms,
  nest = TRUE
)

# 3. Create married indicator
cat("\n[3] Creating mother married indicator...\n")
acs_design_moms$variables$mom_married <- as.numeric(acs_design_moms$variables$MARST_HEAD == 1)

# Check coding
cat("    Mother married coding (MARST_HEAD == 1):\n")
cat("      Not married (MARST_HEAD != 1):", sum(acs_design_moms$variables$MARST_HEAD != 1), "\n")
cat("      Married (MARST_HEAD == 1):", sum(acs_design_moms$variables$MARST_HEAD == 1), "\n")
cat("      Proportion married (unweighted):",
    round(mean(acs_design_moms$variables$mom_married), 3), "\n")

# 4. Estimate by age using GLM
cat("\n[4] Estimating mother's marital status by child age...\n")

# Fit model with AGE only (no year interaction, as per specification)
model_mom_married <- survey::svyglm(
  mom_married ~ as.factor(AGE),
  design = acs_design_moms,
  family = quasibinomial()
)

cat("    Model fitted successfully\n")

# Get predictions for each age
pred_data <- data.frame(AGE = factor(0:5, levels = 0:5))
mom_married_predictions <- predict(model_mom_married, newdata = pred_data, type = "response")

cat("\n    Estimates by age:\n")
for (i in 1:6) {
  cat("      Age", i-1, ":", round(mom_married_predictions[i], 4),
      "(", round(mom_married_predictions[i] * 100, 1), "%)\n")
}

# 5. Create results data frame
cat("\n[5] Creating results data frame...\n")

mom_married_estimates <- data.frame(
  age = 0:5,
  estimand = "Mother Married",
  estimate = as.numeric(mom_married_predictions)
)

print(mom_married_estimates)

# 6. Validation
cat("\n[6] Validation checks...\n")

# Range check (should be 75-90%)
if (all(mom_married_estimates$estimate >= 0.75 & mom_married_estimates$estimate <= 0.90)) {
  cat("    ✓ All estimates in plausible range [0.75, 0.90]\n")
} else {
  cat("    ✗ WARNING: Some estimates outside expected range [0.75, 0.90]\n")
}

# Check for age variation
estimate_range <- max(mom_married_estimates$estimate) - min(mom_married_estimates$estimate)
cat("    Range across ages:", round(estimate_range, 4),
    "(", round(estimate_range * 100, 1), "percentage points)\n")

if (estimate_range > 0.01) {
  cat("    ✓ Meaningful age variation detected (>1 percentage point)\n")
} else {
  cat("    ⚠ Limited age variation (<1 percentage point)\n")
}

# 7. Compare to expected values (from documentation)
cat("\n[7] Comparison to documentation expectations:\n")
expected <- c(0.799, 0.827, 0.837, 0.840, 0.815, 0.793)
comparison <- data.frame(
  age = 0:5,
  estimate = round(mom_married_estimates$estimate, 3),
  expected = expected,
  diff = round(mom_married_estimates$estimate - expected, 3)
)
print(comparison)

# 8. Validate using helper function
cat("\n[8] Binary estimate validation:\n")
validate_binary_estimates(mom_married_estimates[, c("age", "estimate")], "Mother Married")

# 9. Save point estimates
cat("\n[9] Saving mother's marital status point estimates...\n")
saveRDS(mom_married_estimates, "data/raking/ne25/mother_marital_status_estimates.rds")
cat("    Saved to: data/raking/ne25/mother_marital_status_estimates.rds\n")

# 10. Generate bootstrap replicates using SHARED bootstrap design
cat("\n[10] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design (but need to filter to mothers sample)
cat("     Loading shared ACS bootstrap design...\n")
boot_design_full <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")

# Filter bootstrap design to match acs_design_moms sample (MOMLOC > 0)
# Use survey::subset() to properly maintain bootstrap structure
boot_design_moms <- subset(boot_design_full, MOMLOC > 0)

# Add mom_married variable to subsetted bootstrap design
boot_design_moms$variables$mom_married <- as.numeric(boot_design_moms$variables$MARST_HEAD == 1)

cat("     Bootstrap design loaded (", ncol(boot_design_moms$repweights), " replicates)\n\n", sep = "")

# Prediction data (same as point estimates)
pred_data <- data.frame(AGE = factor(0:5, levels = 0:5))

# Generate bootstrap estimates using SHARED replicate weights
boot_result <- generate_acs_bootstrap(
  boot_design = boot_design_moms,
  formula = mom_married ~ as.factor(AGE),
  pred_data = pred_data,
  family = quasibinomial()
)

# Format bootstrap results
boot_long <- format_bootstrap_results(
  boot_result = boot_result,
  ages = 0:5,
  estimand_name = "mother_married"
)

# Save bootstrap estimates
saveRDS(boot_long, "data/raking/ne25/mother_marital_status_estimates_boot.rds")
cat("    Saved bootstrap estimates to: data/raking/ne25/mother_marital_status_estimates_boot.rds\n")
cat("    Bootstrap dimensions:", nrow(boot_long), "rows (6 ages × 4 replicates)\n")

cat("\n========================================\n")
cat("Task 2.7 Complete (with Bootstrap)\n")
cat("========================================\n\n")

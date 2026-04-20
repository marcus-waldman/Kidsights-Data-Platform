# Phase 2, Task 2.6: Estimate Mother's Education (with bootstrap replicates)
# 1 estimand (age-stratified): Proportion with Bachelor's+ degree

library(survey)
source("scripts/raking/ne25/estimation_helpers.R")
source("scripts/raking/ne25/bootstrap_helpers.R")

cat("\n========================================\n")
cat("Task 2.6: Estimate Mother's Education\n")
cat("========================================\n\n")

# Load ACS design
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

# 1. Check mother linkage coverage
cat("[1] Checking mother linkage coverage...\n")
acs_data <- acs_design$variables

cat("    Total children:", nrow(acs_data), "\n")
cat("    Children with mother in household (MOMLOC > 0):", sum(acs_data$MOMLOC > 0), "\n")
cat("    Coverage:", round(sum(acs_data$MOMLOC > 0) / nrow(acs_data) * 100, 1), "%\n")

# 2. Filter to children with mothers
cat("\n[2] Filtering to children with mothers in household...\n")
acs_data_moms <- acs_data[acs_data$MOMLOC > 0, ]
cat("    Retained", nrow(acs_data_moms), "children with mothers\n")

# Check EDUC_MOM distribution
cat("\n    EDUC_MOM distribution:\n")
educ_table <- table(acs_data_moms$EDUC_MOM, useNA = "ifany")
print(educ_table)

# Create survey design with filtered data
acs_design_moms <- survey::svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_moms,
  nest = TRUE
)

# 3. Create Bachelor's+ indicator
cat("\n[3] Creating Bachelor's degree or higher indicator...\n")
acs_design_moms$variables$bachelors_plus <- as.numeric(acs_design_moms$variables$EDUC_MOM >= 10)

# Check coding
cat("    Bachelor's+ coding (EDUC_MOM >= 10):\n")
cat("      Less than Bachelor's (0-9):", sum(acs_design_moms$variables$EDUC_MOM < 10), "\n")
cat("      Bachelor's or higher (10+):", sum(acs_design_moms$variables$EDUC_MOM >= 10), "\n")

# 4. Estimate by age using GLM
cat("\n[4] Estimating mother's education by child age...\n")

# Fit model with AGE only (no year interaction, as per specification)
model_mom_educ <- survey::svyglm(
  bachelors_plus ~ as.factor(AGE),
  design = acs_design_moms,
  family = quasibinomial()
)

cat("    Model fitted successfully\n")

# Get predictions for each age
pred_data <- data.frame(AGE = factor(0:5, levels = 0:5))
mom_educ_predictions <- predict(model_mom_educ, newdata = pred_data, type = "response")

cat("\n    Estimates by age:\n")
for (i in 1:6) {
  cat("      Age", i-1, ":", round(mom_educ_predictions[i], 4),
      "(", round(mom_educ_predictions[i] * 100, 1), "%)\n")
}

# 5. Create results data frame
cat("\n[5] Creating results data frame...\n")

mom_educ_estimates <- data.frame(
  age = 0:5,
  estimand = "Mother Bachelor's+",
  estimate = as.numeric(mom_educ_predictions)
)

print(mom_educ_estimates)

# 6. Validation
cat("\n[6] Validation checks...\n")

# Range check (should be 40-50%)
if (all(mom_educ_estimates$estimate >= 0.40 & mom_educ_estimates$estimate <= 0.50)) {
  cat("    ✓ All estimates in plausible range [0.40, 0.50]\n")
} else {
  cat("    ✗ WARNING: Some estimates outside expected range [0.40, 0.50]\n")
}

# Check for age variation
estimate_range <- max(mom_educ_estimates$estimate) - min(mom_educ_estimates$estimate)
cat("    Range across ages:", round(estimate_range, 4),
    "(", round(estimate_range * 100, 1), "percentage points)\n")

if (estimate_range > 0.01) {
  cat("    ✓ Meaningful age variation detected (>1 percentage point)\n")
} else {
  cat("    ⚠ Limited age variation (<1 percentage point)\n")
}

# 7. Compare to expected values (from documentation)
cat("\n[7] Comparison to documentation expectations:\n")
expected <- c(0.459, 0.458, 0.442, 0.474, 0.464, 0.459)
comparison <- data.frame(
  age = 0:5,
  estimate = round(mom_educ_estimates$estimate, 3),
  expected = expected,
  diff = round(mom_educ_estimates$estimate - expected, 3)
)
print(comparison)

# 8. Validate using helper function
cat("\n[8] Binary estimate validation:\n")
validate_binary_estimates(mom_educ_estimates[, c("age", "estimate")], "Mother Bachelor's+")

# 9. Save point estimates
cat("\n[9] Saving mother's education point estimates...\n")
saveRDS(mom_educ_estimates, "data/raking/ne25/mother_education_estimates.rds")
cat("    Saved to: data/raking/ne25/mother_education_estimates.rds\n")

# 10. Generate bootstrap replicates using SHARED bootstrap design
cat("\n[10] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design (but need to filter to mothers sample)
cat("     Loading shared ACS bootstrap design...\n")
boot_design_full <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")

# Filter bootstrap design to match acs_design_moms sample (MOMLOC > 0)
# Use survey::subset() to properly maintain bootstrap structure
boot_design_moms <- subset(boot_design_full, MOMLOC > 0)

# Add bachelors_plus variable to subsetted bootstrap design
boot_design_moms$variables$bachelors_plus <- as.numeric(boot_design_moms$variables$EDUC_MOM >= 10)

cat("     Bootstrap design loaded (", ncol(boot_design_moms$repweights), " replicates)\n\n", sep = "")

# Prediction data (same as point estimates)
pred_data <- data.frame(AGE = factor(0:5, levels = 0:5))

# Generate bootstrap estimates using SHARED replicate weights
boot_result <- generate_acs_bootstrap(
  boot_design = boot_design_moms,
  formula = bachelors_plus ~ as.factor(AGE),
  pred_data = pred_data,
  family = quasibinomial()
)

# Format bootstrap results
boot_long <- format_bootstrap_results(
  boot_result = boot_result,
  ages = 0:5,
  estimand_name = "mother_bachelors_plus"
)

# Save bootstrap estimates
saveRDS(boot_long, "data/raking/ne25/mother_education_estimates_boot.rds")
cat("    Saved bootstrap estimates to: data/raking/ne25/mother_education_estimates_boot.rds\n")
cat("    Bootstrap dimensions:", nrow(boot_long), "rows (6 ages × 4 replicates)\n")

cat("\n========================================\n")
cat("Task 2.6 Complete (with Bootstrap)\n")
cat("========================================\n\n")

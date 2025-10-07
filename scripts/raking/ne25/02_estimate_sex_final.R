# Phase 2, Task 2.2: Estimate Sex Distribution (with bootstrap replicates)

library(survey)
source("scripts/raking/ne25/estimation_helpers.R")
source("scripts/raking/ne25/bootstrap_helpers.R")

cat("\n========================================\n")
cat("Task 2.2: Estimate Sex Distribution\n")
cat("========================================\n\n")

# Load ACS design
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

# Test 1: Model with interaction
cat("[1] Testing interaction model...\n")
model_interact <- survey::svyglm(
  I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design,
  family = quasibinomial()
)

# Test 2: Model without interaction  
model_main <- survey::svyglm(
  I(SEX == 1) ~ AGE + MULTYEAR,
  design = acs_design,
  family = quasibinomial()
)

# Test 3: Intercept-only
model_intercept <- survey::svyglm(
  I(SEX == 1) ~ 1,
  design = acs_design,
  family = quasibinomial()
)

# Compare models with AIC
cat("\n[2] Model comparison (AIC):\n")
cat("    Interaction model AIC:", AIC(model_interact), "\n")
cat("    Main effects model AIC:", AIC(model_main), "\n")
cat("    Intercept-only model AIC:", AIC(model_intercept), "\n")

# Anova test for interaction
cat("\n[3] Testing interaction significance:\n")
anova_result <- anova(model_main, model_interact)
print(anova_result)

# Use intercept-only (sex shouldn't vary by age/year)
cat("\n[4] Using intercept-only model (sex is biological constant)...\n")
prop_male <- predict(model_intercept, type = "response")[1]
cat("    Proportion male:", round(prop_male, 4), "\n")

# Create result (same for all ages)
sex_estimates <- data.frame(
  age = 0:5,
  estimate = rep(prop_male, 6)
)

print(sex_estimates)

# Validate
validate_binary_estimates(sex_estimates, "Proportion Male")

# Save point estimates
saveRDS(sex_estimates, "data/raking/ne25/sex_estimates.rds")
cat("\n[5] Saved point estimates to: data/raking/ne25/sex_estimates.rds\n")

# Generate bootstrap replicates using SHARED bootstrap design
cat("\n[6] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design (created by 01a_create_acs_bootstrap_design.R)
cat("    Loading shared ACS bootstrap design...\n")
boot_design <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")
cat("    Bootstrap design loaded (", ncol(boot_design$repweights), " replicates)\n\n", sep = "")

# Create prediction data frame (even though intercept-only, need structure)
pred_data <- data.frame(
  age = 0:5
)

# Generate bootstrap estimates using SHARED replicate weights
boot_result <- generate_acs_bootstrap(
  boot_design = boot_design,
  formula = I(SEX == 1) ~ 1,
  pred_data = pred_data,
  family = quasibinomial()
)

# Format bootstrap results
boot_long <- format_bootstrap_results(
  boot_result = boot_result,
  ages = 0:5,
  estimand_name = "sex_male"
)

# Save bootstrap estimates
saveRDS(boot_long, "data/raking/ne25/sex_estimates_boot.rds")
cat("    Saved bootstrap estimates to: data/raking/ne25/sex_estimates_boot.rds\n")
cat("    Bootstrap dimensions:", nrow(boot_long), "rows (6 ages × 4 replicates)\n")

cat("\n========================================\n")
cat("Task 2.2 Complete (with Bootstrap)\n")
cat("========================================\n\n")

# Phase 2, Task 2.2: Estimate Sex Distribution (glm2 version with bootstrap)
# Refactored: January 2025
# Changes: Uses glm2::glm2() instead of survey::svyglm()

library(glm2)
source("config/bootstrap_config.R")
source("scripts/raking/ne25/estimation_helpers_glm2.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

cat("\n========================================\n")
cat("Task 2.2: Estimate Sex Distribution (glm2)\n")
cat("========================================\n\n")

# Load ACS design (to extract data and bootstrap weights)
cat("[1] Loading ACS survey design...\n")
acs_design <- readRDS("data/raking/ne25/acs_design.rds")
acs_data <- acs_design$variables
cat("    Sample size:", nrow(acs_data), "\n\n")

# Test different models to determine best specification
cat("[2] Model comparison...\n")

# Model 1: Interaction model
cat("    [2a] Fitting interaction model...\n")
sex_interact <- fit_glm2_estimates(
  data = acs_data,
  formula = I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  weights_col = "PERWT",
  predict_year = 2023,
  ages = 0:5
)

# Model 2: Main effects only
cat("    [2b] Fitting main effects model...\n")
sex_main <- fit_glm2_estimates(
  data = acs_data,
  formula = I(SEX == 1) ~ AGE + MULTYEAR,
  weights_col = "PERWT",
  predict_year = 2023,
  ages = 0:5
)

# Model 3: Intercept-only (sex is biological constant)
cat("    [2c] Fitting intercept-only model...\n")
sex_intercept <- fit_glm2_estimates(
  data = acs_data,
  formula = I(SEX == 1) ~ 1,
  weights_col = "PERWT",
  predict_year = 2023,
  ages = 0:5
)

cat("\n")

# Compare variation across ages
cat("[3] Comparing age variation:\n")
cat("    Interaction model range:",
    round(max(sex_interact$estimate) - min(sex_interact$estimate), 4), "\n")
cat("    Main effects model range:",
    round(max(sex_main$estimate) - min(sex_main$estimate), 4), "\n")
cat("    Intercept-only model range:",
    round(max(sex_intercept$estimate) - min(sex_intercept$estimate), 4), "\n")

cat("\n    [Decision] Using intercept-only model (sex is biological constant)\n")
cat("    Proportion male:", round(sex_intercept$estimate[1], 4), "\n\n")

# Use intercept-only model as final result
sex_estimates <- sex_intercept

cat("[4] Final estimates:\n")
print(sex_estimates)

# Validate
validate_binary_estimates(sex_estimates, "Proportion Male")

# Save point estimates
cat("\n[5] Saving sex point estimates...\n")
saveRDS(sex_estimates, "data/raking/ne25/sex_estimates_glm2.rds")
cat("    Saved to: data/raking/ne25/sex_estimates_glm2.rds\n")

# Generate bootstrap replicates using SHARED bootstrap design
cat("\n[6] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design
cat("    Loading shared ACS bootstrap design...\n")
boot_design <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")

# Extract replicate weights matrix
replicate_weights <- boot_design$repweights
n_boot <- ncol(replicate_weights)
cat("    Bootstrap design loaded (", n_boot, " replicates)\n\n", sep = "")

# Create prediction data frame
pred_data <- data.frame(AGE = 0:5, MULTYEAR = 2023)

# Generate bootstrap estimates using glm2 with starting values
boot_result <- generate_bootstrap_glm2(
  data = acs_data,
  formula = I(SEX == 1) ~ 1,  # Intercept-only (sex constant)
  replicate_weights = replicate_weights,
  pred_data = pred_data
)

cat("\n")

# Format bootstrap results for saving
boot_long <- format_bootstrap_results(
  boot_result = boot_result,
  ages = 0:5,
  estimand_name = "sex_male"
)

# Save bootstrap estimates
saveRDS(boot_long, "data/raking/ne25/sex_estimates_boot_glm2.rds")
cat("[7] Saved bootstrap estimates to: data/raking/ne25/sex_estimates_boot_glm2.rds\n")
cat("    Bootstrap dimensions:", nrow(boot_long), "rows (6 ages ×", n_boot, "replicates)\n")

cat("\n========================================\n")
cat("Task 2.2 Complete (glm2 version)\n")
cat("========================================\n\n")

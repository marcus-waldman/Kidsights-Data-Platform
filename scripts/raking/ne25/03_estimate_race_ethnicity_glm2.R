# Phase 2, Task 2.3: Estimate Race/Ethnicity Distributions (glm2 version with bootstrap)
# 3 estimands: White non-Hispanic, Black, Hispanic
# Refactored: January 2025
# Changes: Uses glm2::glm2() instead of survey::svyglm()

library(glm2)
library(dplyr)
source("config/bootstrap_config.R")
source("scripts/raking/ne25/estimation_helpers_glm2.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

cat("\n========================================\n")
cat("Task 2.3: Estimate Race/Ethnicity (glm2)\n")
cat("========================================\n\n")

# Load ACS design (to extract data and bootstrap weights)
cat("[1] Loading ACS survey design...\n")
acs_design <- readRDS("data/raking/ne25/acs_design.rds")
acs_data <- acs_design$variables
cat("    Sample size:", nrow(acs_data), "\n\n")

# Initialize results list
race_results <- list()

# Estimand 1: White non-Hispanic
cat("[2] Estimating White non-Hispanic...\n")
white_nh_est <- fit_glm2_estimates(
  data = acs_data,
  formula = I((RACE == 1) & (HISPAN == 0)) ~ 1,
  weights_col = "PERWT",
  predict_year = 2023,
  ages = 0:5
)
cat("    Proportion White non-Hispanic:", round(white_nh_est$estimate[1], 4), "\n")

race_results$white_nh <- data.frame(
  age = 0:5,
  estimand = "White non-Hispanic",
  estimate = white_nh_est$estimate
)

# Estimand 2: Black (any ethnicity)
cat("\n[3] Estimating Black (any ethnicity)...\n")
black_est <- fit_glm2_estimates(
  data = acs_data,
  formula = I(RACE == 2) ~ 1,
  weights_col = "PERWT",
  predict_year = 2023,
  ages = 0:5
)
cat("    Proportion Black:", round(black_est$estimate[1], 4), "\n")

race_results$black <- data.frame(
  age = 0:5,
  estimand = "Black",
  estimate = black_est$estimate
)

# Estimand 3: Hispanic (any race)
cat("\n[4] Estimating Hispanic (any race)...\n")
hispanic_est <- fit_glm2_estimates(
  data = acs_data,
  formula = I(HISPAN >= 1) ~ 1,
  weights_col = "PERWT",
  predict_year = 2023,
  ages = 0:5
)
cat("    Proportion Hispanic:", round(hispanic_est$estimate[1], 4), "\n")

race_results$hispanic <- data.frame(
  age = 0:5,
  estimand = "Hispanic",
  estimate = hispanic_est$estimate
)

# Combine results
cat("\n[5] Combined race/ethnicity estimates:\n")
race_estimates <- dplyr::bind_rows(race_results)
print(race_estimates)

# Validate each
cat("\n[6] Validation:\n")
validate_binary_estimates(race_results$white_nh[,c("age","estimate")], "White non-Hispanic")
validate_binary_estimates(race_results$black[,c("age","estimate")], "Black")
validate_binary_estimates(race_results$hispanic[,c("age","estimate")], "Hispanic")

# Check plausibility for Nebraska
cat("\n[7] Plausibility check (Nebraska demographics):\n")
cat("    White non-Hispanic:", round(white_nh_est$estimate[1] * 100, 1), "% (expect ~70-80%)\n")
cat("    Black:", round(black_est$estimate[1] * 100, 1), "% (expect ~5-10%)\n")
cat("    Hispanic:", round(hispanic_est$estimate[1] * 100, 1), "% (expect ~10-15%)\n")

# Save point estimates
cat("\n[8] Saving race/ethnicity point estimates...\n")
saveRDS(race_estimates, "data/raking/ne25/race_ethnicity_estimates_glm2.rds")
cat("    Saved to: data/raking/ne25/race_ethnicity_estimates_glm2.rds\n")

# Generate bootstrap replicates for all 3 estimands using SHARED bootstrap design
cat("\n[9] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design
cat("    Loading shared ACS bootstrap design...\n")
boot_design <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")

# Extract replicate weights matrix
replicate_weights <- boot_design$repweights
n_boot <- ncol(replicate_weights)
cat("    Bootstrap design loaded (", n_boot, " replicates)\n\n", sep = "")

# Create prediction data frame
pred_data <- data.frame(AGE = 0:5, MULTYEAR = 2023)

# Bootstrap 1: White non-Hispanic
cat("    [9.1] White non-Hispanic bootstrap...\n")
boot_white <- generate_bootstrap_glm2(
  data = acs_data,
  formula = I((RACE == 1) & (HISPAN == 0)) ~ 1,
  replicate_weights = replicate_weights,
  pred_data = pred_data
)
boot_white_long <- format_bootstrap_results(boot_white, ages = 0:5, estimand_name = "race_white_nh")

cat("\n")

# Bootstrap 2: Black
cat("    [9.2] Black bootstrap...\n")
boot_black <- generate_bootstrap_glm2(
  data = acs_data,
  formula = I(RACE == 2) ~ 1,
  replicate_weights = replicate_weights,
  pred_data = pred_data
)
boot_black_long <- format_bootstrap_results(boot_black, ages = 0:5, estimand_name = "race_black")

cat("\n")

# Bootstrap 3: Hispanic
cat("    [9.3] Hispanic bootstrap...\n")
boot_hispanic <- generate_bootstrap_glm2(
  data = acs_data,
  formula = I(HISPAN >= 1) ~ 1,
  replicate_weights = replicate_weights,
  pred_data = pred_data
)
boot_hispanic_long <- format_bootstrap_results(boot_hispanic, ages = 0:5, estimand_name = "race_hispanic")

cat("\n")

# Combine all bootstrap results
race_boot_estimates <- dplyr::bind_rows(
  boot_white_long,
  boot_black_long,
  boot_hispanic_long
)

# Save bootstrap estimates
saveRDS(race_boot_estimates, "data/raking/ne25/race_ethnicity_estimates_boot_glm2.rds")
cat("[10] Saved bootstrap estimates to: data/raking/ne25/race_ethnicity_estimates_boot_glm2.rds\n")
cat("     Bootstrap dimensions:", nrow(race_boot_estimates), "rows (3 estimands × 6 ages ×", n_boot, "replicates)\n")

cat("\n========================================\n")
cat("Task 2.3 Complete (glm2 version)\n")
cat("========================================\n\n")

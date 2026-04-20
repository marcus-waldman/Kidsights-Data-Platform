# Phase 2, Task 2.3: Estimate Race/Ethnicity Distributions (with bootstrap replicates)
# 3 estimands: White non-Hispanic, Black, Hispanic

library(survey)
source("scripts/raking/ne25/estimation_helpers.R")
source("scripts/raking/ne25/bootstrap_helpers.R")

cat("\n========================================\n")
cat("Task 2.3: Estimate Race/Ethnicity\n")
cat("========================================\n\n")

# Load ACS design
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

# Initialize results list
race_results <- list()

# 1. White non-Hispanic
cat("[1] Estimating White non-Hispanic...\n")
model_white <- survey::svyglm(
  I((RACE == 1) & (HISPAN == 0)) ~ 1,
  design = acs_design,
  family = quasibinomial()
)
prop_white <- predict(model_white, type = "response")[1]
cat("    Proportion White non-Hispanic:", round(prop_white, 4), "\n")

race_results$white_nh <- data.frame(
  age = 0:5,
  estimand = "White non-Hispanic",
  estimate = rep(prop_white, 6)
)

# 2. Black any
cat("\n[2] Estimating Black (any ethnicity)...\n")
model_black <- survey::svyglm(
  I(RACE == 2) ~ 1,
  design = acs_design,
  family = quasibinomial()
)
prop_black <- predict(model_black, type = "response")[1]
cat("    Proportion Black:", round(prop_black, 4), "\n")

race_results$black <- data.frame(
  age = 0:5,
  estimand = "Black",
  estimate = rep(prop_black, 6)
)

# 3. Hispanic any
cat("\n[3] Estimating Hispanic (any race)...\n")
model_hispanic <- survey::svyglm(
  I(HISPAN >= 1) ~ 1,
  design = acs_design,
  family = quasibinomial()
)
prop_hispanic <- predict(model_hispanic, type = "response")[1]
cat("    Proportion Hispanic:", round(prop_hispanic, 4), "\n")

race_results$hispanic <- data.frame(
  age = 0:5,
  estimand = "Hispanic",
  estimate = rep(prop_hispanic, 6)
)

# Combine results
cat("\n[4] Combined race/ethnicity estimates:\n")
race_estimates <- dplyr::bind_rows(race_results)
print(race_estimates)

# Validate each
cat("\n[5] Validation:\n")
validate_binary_estimates(race_results$white_nh[,c("age","estimate")], "White non-Hispanic")
validate_binary_estimates(race_results$black[,c("age","estimate")], "Black")
validate_binary_estimates(race_results$hispanic[,c("age","estimate")], "Hispanic")

# Check plausibility for Nebraska
cat("\n[6] Plausibility check (Nebraska demographics):\n")
cat("    White non-Hispanic:", round(prop_white * 100, 1), "% (expect ~70-80%)\n")
cat("    Black:", round(prop_black * 100, 1), "% (expect ~5-10%)\n")
cat("    Hispanic:", round(prop_hispanic * 100, 1), "% (expect ~10-15%)\n")

# Save point estimates
cat("\n[7] Saving race/ethnicity point estimates...\n")
saveRDS(race_estimates, "data/raking/ne25/race_ethnicity_estimates.rds")
cat("    Saved to: data/raking/ne25/race_ethnicity_estimates.rds\n")

# Generate bootstrap replicates for all 3 estimands using SHARED bootstrap design
cat("\n[8] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design
cat("    Loading shared ACS bootstrap design...\n")
boot_design <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")
cat("    Bootstrap design loaded (", ncol(boot_design$repweights), " replicates)\n\n", sep = "")

# Prediction data frame
pred_data <- data.frame(age = 0:5)

# 8.1: White non-Hispanic bootstrap
cat("    [8.1] White non-Hispanic bootstrap...\n")
boot_white <- generate_acs_bootstrap(
  boot_design = boot_design,
  formula = I((RACE == 1) & (HISPAN == 0)) ~ 1,
  pred_data = pred_data,
  family = quasibinomial()
)
boot_white_long <- format_bootstrap_results(boot_white, ages = 0:5, estimand_name = "race_white_nh")

# 8.2: Black bootstrap
cat("    [8.2] Black bootstrap...\n")
boot_black <- generate_acs_bootstrap(
  boot_design = boot_design,
  formula = I(RACE == 2) ~ 1,
  pred_data = pred_data,
  family = quasibinomial()
)
boot_black_long <- format_bootstrap_results(boot_black, ages = 0:5, estimand_name = "race_black")

# 8.3: Hispanic bootstrap
cat("    [8.3] Hispanic bootstrap...\n")
boot_hispanic <- generate_acs_bootstrap(
  boot_design = boot_design,
  formula = I(HISPAN >= 1) ~ 1,
  pred_data = pred_data,
  family = quasibinomial()
)
boot_hispanic_long <- format_bootstrap_results(boot_hispanic, ages = 0:5, estimand_name = "race_hispanic")

# Combine all bootstrap results
race_boot_estimates <- dplyr::bind_rows(
  boot_white_long,
  boot_black_long,
  boot_hispanic_long
)

# Save bootstrap estimates
saveRDS(race_boot_estimates, "data/raking/ne25/race_ethnicity_estimates_boot.rds")
cat("    Saved bootstrap estimates to: data/raking/ne25/race_ethnicity_estimates_boot.rds\n")
cat("    Bootstrap dimensions:", nrow(race_boot_estimates), "rows (3 estimands × 6 ages × 4 replicates)\n")

cat("\n========================================\n")
cat("Task 2.3 Complete (with Bootstrap)\n")
cat("========================================\n\n")

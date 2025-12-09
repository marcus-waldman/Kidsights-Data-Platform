# Phase 4a, Task 2: Estimate Nebraska Propensity Model
# Estimates P(Nebraska | Demographics) from ACS North Central states data
# Purpose: Create propensity weights to make NHIS/NSCH North Central "look like" Nebraska

library(dplyr)
library(arrow)

cat("\n========================================\n")
cat("Task 4a.2: Estimate Nebraska Propensity Model\n")
cat("========================================\n\n")

# Source harmonization utilities
cat("[1] Loading harmonization utilities...\n")
source("scripts/raking/ne25/utils/harmonize_race_ethnicity.R")
source("scripts/raking/ne25/utils/harmonize_education.R")
source("scripts/raking/ne25/utils/harmonize_marital_status.R")
cat("    ✓ Utilities loaded\n\n")

# 1. Load ACS North Central data
cat("[2] Loading ACS North Central data...\n")
if (!file.exists("data/raking/ne25/acs_north_central.feather")) {
  stop("ACS North Central data not found. Run 25_extract_acs_north_central.R first.")
}

acs_nc <- arrow::read_feather("data/raking/ne25/acs_north_central.feather")
cat("    Loaded:", nrow(acs_nc), "records\n")
cat("    Nebraska records:", sum(acs_nc$STATEFIP == 31), "\n\n")

# 2. Create harmonized variables for propensity model
cat("[3] Creating harmonized demographic variables...\n")

# Sex: male indicator (1=Male in ACS)
acs_nc$male <- as.integer(acs_nc$SEX == 1)

# Age: continuous (already 0-5)
acs_nc$age <- acs_nc$AGE

# Race/ethnicity: 4-category harmonization
acs_nc$race_harmonized <- harmonize_acs_race(acs_nc$RACE, acs_nc$HISPAN)

# Create race dummies
race_dummies <- create_race_dummies(acs_nc$race_harmonized)
acs_nc$white_nh <- race_dummies$white_nh
acs_nc$black <- race_dummies$black
acs_nc$hispanic <- race_dummies$hispanic

# Education: years of schooling
acs_nc$educ_years <- harmonize_acs_education(acs_nc$EDUC_MOM)

# Marital status: binary married indicator
acs_nc$married <- harmonize_acs_marital(acs_nc$MARST_HEAD)

# FPL: continuous poverty ratio (1-501)
acs_nc$poverty_ratio <- acs_nc$POVERTY

cat("    ✓ Created 8 harmonized variables:\n")
cat("      - male (binary)\n")
cat("      - age (continuous 0-5)\n")
cat("      - white_nh, black, hispanic (3 race dummies)\n")
cat("      - educ_years (continuous 2-20)\n")
cat("      - married (binary)\n")
cat("      - poverty_ratio (continuous 1-501)\n\n")

# 3. Check for missing values in harmonized variables
cat("[4] Checking for missing values...\n")

harmonized_vars <- c("male", "age", "white_nh", "black", "hispanic",
                     "educ_years", "married", "poverty_ratio")

missing_counts <- sapply(harmonized_vars, function(v) sum(is.na(acs_nc[[v]])))
missing_pct <- round(missing_counts / nrow(acs_nc) * 100, 2)

missing_df <- data.frame(
  variable = harmonized_vars,
  n_missing = missing_counts,
  pct_missing = missing_pct
)

print(missing_df)

# Remove records with any missing harmonized variables
acs_nc_complete <- acs_nc %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(married) & !is.na(poverty_ratio)
  )

cat("\n    Records with complete data:", nrow(acs_nc_complete), "/", nrow(acs_nc),
    "(", round(nrow(acs_nc_complete) / nrow(acs_nc) * 100, 1), "%)\n\n")

# 4. Create Nebraska indicator
cat("[5] Creating Nebraska outcome variable...\n")
acs_nc_complete$nebraska <- as.integer(acs_nc_complete$STATEFIP == 31)

nebraska_n <- sum(acs_nc_complete$nebraska == 1)
non_nebraska_n <- sum(acs_nc_complete$nebraska == 0)

cat("    Nebraska (target):", nebraska_n, "\n")
cat("    Other NC states:", non_nebraska_n, "\n")
cat("    Prevalence:", round(nebraska_n / nrow(acs_nc_complete) * 100, 2), "%\n\n")

# 5. Estimate propensity model: P(Nebraska | Demographics)
cat("[6] Estimating propensity model (weighted logistic regression)...\n")
cat("    Model: P(Nebraska=1 | age, male, race, educ, married, poverty)\n\n")

# Fit weighted logistic regression
# Include interactions to capture non-linear relationships
propensity_formula <- nebraska ~ age + male + white_nh + black + hispanic +
                                  educ_years + married + poverty_ratio +
                                  age:poverty_ratio + educ_years:poverty_ratio

propensity_model <- glm(
  propensity_formula,
  data = acs_nc_complete,
  family = binomial(link = "logit"),
  weights = PERWT
)

cat("    ✓ Model estimated\n\n")

# 6. Model summary
cat("[7] Model summary:\n\n")
print(summary(propensity_model))

# 7. Predict propensity scores for all North Central observations
cat("\n[8] Predicting propensity scores...\n")

acs_nc_complete$p_nebraska <- predict(propensity_model, type = "response")

cat("    Propensity score range:\n")
cat("      Min:", round(min(acs_nc_complete$p_nebraska), 4), "\n")
cat("      Median:", round(median(acs_nc_complete$p_nebraska), 4), "\n")
cat("      Mean:", round(mean(acs_nc_complete$p_nebraska), 4), "\n")
cat("      Max:", round(max(acs_nc_complete$p_nebraska), 4), "\n\n")

# Compare propensity distribution: Nebraska vs. other states
cat("[9] Propensity score distributions:\n")

p_nebraska_subset <- acs_nc_complete$p_nebraska[acs_nc_complete$nebraska == 1]
p_other_subset <- acs_nc_complete$p_nebraska[acs_nc_complete$nebraska == 0]

cat("    Nebraska observations:\n")
cat("      Mean propensity:", round(mean(p_nebraska_subset), 4), "\n")
cat("      Median propensity:", round(median(p_nebraska_subset), 4), "\n")
cat("      Range:", round(min(p_nebraska_subset), 4), "-",
    round(max(p_nebraska_subset), 4), "\n\n")

cat("    Other NC states:\n")
cat("      Mean propensity:", round(mean(p_other_subset), 4), "\n")
cat("      Median propensity:", round(median(p_other_subset), 4), "\n")
cat("      Range:", round(min(p_other_subset), 4), "-",
    round(max(p_other_subset), 4), "\n\n")

# 8. Check common support
cat("[10] Checking common support (overlap)...\n")

# Common support: range where both Nebraska and non-Nebraska observations exist
ne_min <- min(p_nebraska_subset)
ne_max <- max(p_nebraska_subset)
other_min <- min(p_other_subset)
other_max <- max(p_other_subset)

overlap_min <- max(ne_min, other_min)
overlap_max <- min(ne_max, other_max)

cat("    Common support range:", round(overlap_min, 4), "to", round(overlap_max, 4), "\n")

# Proportion of observations in common support
in_support <- acs_nc_complete$p_nebraska >= overlap_min &
              acs_nc_complete$p_nebraska <= overlap_max
pct_in_support <- round(sum(in_support) / nrow(acs_nc_complete) * 100, 1)

cat("    Observations in common support:", sum(in_support), "/", nrow(acs_nc_complete),
    "(", pct_in_support, "%)\n\n")

if (pct_in_support < 90) {
  cat("    WARNING: Less than 90% of observations in common support.\n")
  cat("    Consider adding more flexible terms to propensity model.\n\n")
}

# 9. Save propensity model
cat("[11] Saving propensity model...\n")

# Save model object
saveRDS(propensity_model, "data/raking/ne25/nebraska_propensity_model.rds")
cat("    ✓ Model saved to: data/raking/ne25/nebraska_propensity_model.rds\n\n")

# Save data with propensity scores for diagnostics
saveRDS(acs_nc_complete, "data/raking/ne25/acs_nc_with_propensity.rds")
cat("    ✓ Data with scores saved to: data/raking/ne25/acs_nc_with_propensity.rds\n\n")

# 10. Save model summary for documentation
cat("[12] Saving model summary...\n")

model_summary <- list(
  formula = propensity_formula,
  n_obs = nrow(acs_nc_complete),
  n_nebraska = nebraska_n,
  n_other = non_nebraska_n,
  prevalence = nebraska_n / nrow(acs_nc_complete),
  coefficients = coef(propensity_model),
  aic = AIC(propensity_model),
  propensity_range = c(min(acs_nc_complete$p_nebraska), max(acs_nc_complete$p_nebraska)),
  common_support = c(overlap_min, overlap_max),
  pct_in_support = pct_in_support
)

saveRDS(model_summary, "data/raking/ne25/propensity_model_summary.rds")
cat("    ✓ Summary saved to: data/raking/ne25/propensity_model_summary.rds\n\n")

cat("========================================\n")
cat("Task 4a.2 Complete: Propensity Model Estimated\n")
cat("========================================\n\n")

cat("Model diagnostics:\n")
cat("  - AIC:", round(model_summary$aic, 1), "\n")
cat("  - Common support:", round(overlap_min, 4), "to", round(overlap_max, 4), "\n")
cat("  - % in support:", pct_in_support, "%\n\n")

cat("Ready for Task 4a.3: Apply propensity reweighting to NHIS and NSCH\n\n")

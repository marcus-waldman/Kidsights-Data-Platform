# Phase 4a, Task 3: Apply Propensity Reweighting to NHIS
# Scores NHIS North Central parent-child pairs with Nebraska propensity model
# Creates adjusted_weight = SAMPWEIGHT * (p_nebraska / mean(p_nebraska))

library(dplyr)

cat("\n========================================\n")
cat("Task 4a.3: Apply Propensity Reweighting to NHIS\n")
cat("========================================\n\n")

# Source harmonization utilities
cat("[1] Loading utilities...\n")
source("scripts/raking/ne25/utils/harmonize_race_ethnicity.R")
source("scripts/raking/ne25/utils/harmonize_education.R")
source("scripts/raking/ne25/utils/harmonize_marital_status.R")
source("scripts/raking/ne25/utils/weighted_covariance.R")
source("scripts/raking/ne25/utils/validate_raw_inputs.R")
cat("    ✓ Utilities loaded\n\n")

# 1. Load Nebraska propensity model
cat("[2] Loading Nebraska propensity model...\n")
if (!file.exists("data/raking/ne25/nebraska_propensity_model.rds")) {
  stop("Propensity model not found. Run 26_estimate_propensity_model.R first.")
}

propensity_model <- readRDS("data/raking/ne25/nebraska_propensity_model.rds")
cat("    ✓ Model loaded\n\n")

# 2. Load NHIS parent-child linked data
cat("[3] Loading NHIS parent-child data...\n")
if (!file.exists("data/raking/ne25/nhis_parent_child_linked.rds")) {
  stop("NHIS parent-child data not found. Run 12_filter_nhis_parents.R first.")
}

nhis <- readRDS("data/raking/ne25/nhis_parent_child_linked.rds")
cat("    Loaded:", nrow(nhis), "parent-child pairs\n")
cat("    Years:", paste(sort(unique(nhis$YEAR)), collapse = ", "), "\n\n")

# 2b. Pre-harmonization input validation
cat("[3b] Running pre-harmonization input validation...\n")
nhis_validation <- validate_nhis_inputs(nhis)

if (!nhis_validation$valid) {
  cat("\nWARNING: NHIS input validation detected issues\n")
  cat("Continuing with analysis, but review issues above\n\n")
}

# 3. Check NHIS variables needed for harmonization
cat("[4] Checking NHIS variable availability...\n")

# Check for available variables - account for naming variations
# Weight variables: SAMPWEIGHT_child, SAMPWEIGHT, PARTWEIGHT, LONGWEIGHT
weight_var_candidates <- c("SAMPWEIGHT_child", "SAMPWEIGHT", "PARTWEIGHT", "LONGWEIGHT")
weight_var <- intersect(weight_var_candidates, names(nhis))[1]

# Race variables: RACENEW_parent or variations
race_var_candidates <- c("RACENEW_parent", "RACENEW", "RACE_parent")
race_var <- intersect(race_var_candidates, names(nhis))[1]

# Hispanic variables
hisp_var_candidates <- c("HISPETH_parent", "HISPAN_parent", "HISPAN")
hisp_var <- intersect(hisp_var_candidates, names(nhis))[1]

all_vars <- c("AGE_child", "SEX_child", "YEAR", weight_var, race_var, hisp_var)
missing_vars <- setdiff(all_vars, c(names(nhis), weight_var, race_var, hisp_var))

if (length(missing_vars) > 0) {
  cat("    ERROR: Missing required variables:\n")
  print(missing_vars)
  cat("\n    Available column names (first 30):\n")
  print(head(names(nhis), 30))
  stop("Required NHIS variables not found")
}

cat("    ✓ All required variables present\n\n")

# 4. Create harmonized variables for propensity scoring
cat("[5] Creating harmonized demographic variables...\n")

# Sex: male indicator (1=Male in NHIS)
nhis$male <- as.integer(nhis$SEX_child == 1)

# Age: continuous (child age 0-5)
nhis$age <- nhis$AGE_child

# Race/ethnicity: Use parent's race if available, otherwise pooled
# Note: Variables may be RACENEW_parent/HISPETH_parent or just RACENEW/HISPETH
race_var <- ifelse("RACENEW_parent" %in% names(nhis), "RACENEW_parent", "RACENEW")
hisp_var <- ifelse("HISPETH_parent" %in% names(nhis), "HISPETH_parent",
                   ifelse("HISPETH" %in% names(nhis), "HISPETH",
                          ifelse("HISPAN_parent" %in% names(nhis), "HISPAN_parent", "HISPAN")))

if (!(race_var %in% names(nhis)) || !(hisp_var %in% names(nhis))) {
  cat("    ERROR: Cannot find race/ethnicity variables\n")
  cat("    Available variables containing 'RACE':\n")
  print(grep("RACE", names(nhis), value = TRUE, ignore.case = TRUE))
  cat("    Available variables containing 'HISP/ETH':\n")
  print(grep("HISP|ETH", names(nhis), value = TRUE, ignore.case = TRUE))
  stop("Race/ethnicity variables not found")
}

cat("    Using race variable:", race_var, "and Hispanic variable:", hisp_var, "\n")
nhis$race_harmonized <- harmonize_nhis_race(nhis[[race_var]], nhis[[hisp_var]])

# Create race dummies
race_dummies <- create_race_dummies(nhis$race_harmonized)
nhis$white_nh <- race_dummies$white_nh
nhis$black <- race_dummies$black
nhis$hispanic <- race_dummies$hispanic

# Education: years of schooling (use parent's education if available)
# Check for EDUCPARENT or similar variable
educ_var_candidates <- c("EDUCPARENT_parent", "EDUCPARENT", "EDUC_parent", "EDUC")
educ_var <- intersect(educ_var_candidates, names(nhis))[1]

if (is.na(educ_var)) {
  cat("    ERROR: Cannot find education variable\n")
  cat("    Candidates checked:", paste(educ_var_candidates, collapse = ", "), "\n")
  cat("    Available variables containing 'EDUC':\n")
  print(grep("EDUC", names(nhis), value = TRUE, ignore.case = TRUE))
  stop("Education variable not found")
}

cat("    Using education variable:", educ_var, "\n")
nhis$educ_years <- harmonize_nhis_education(nhis[[educ_var]])

# Marital status: Use parent's marital status if available
marital_var_candidates <- c("PAR1MARST", "MARSTAT_parent", "MARITAL_parent")
marital_var <- intersect(marital_var_candidates, names(nhis))[1]

if (is.na(marital_var)) {
  cat("    WARNING: Cannot find marital status variable\n")
  cat("    Candidates checked:", paste(marital_var_candidates, collapse = ", "), "\n")
  cat("    Setting married = NA for all observations\n")
  nhis$married <- NA_integer_
} else {
  cat("    Using marital variable:", marital_var, "\n")
  nhis$married <- harmonize_nhis_marital(nhis[[marital_var]])
}

# FPL: continuous poverty ratio
poverty_var_candidates <- c("POVERTY_parent", "POVERTY", "RATCAT_parent", "RATCAT")
poverty_var <- intersect(poverty_var_candidates, names(nhis))[1]

if (is.na(poverty_var)) {
  cat("    ERROR: Cannot find poverty ratio variable\n")
  cat("    Candidates checked:", paste(poverty_var_candidates, collapse = ", "), "\n")
  cat("    Available variables containing 'POV' or 'RAT':\n")
  print(grep("POV|RAT", names(nhis), value = TRUE, ignore.case = TRUE))
  stop("Poverty variable not found")
}

cat("    Using poverty variable:", poverty_var, "\n")

# NHIS POVERTY coding: typically 0-500+ (similar to ACS)
# Need to verify and potentially rescale
nhis$poverty_ratio <- nhis[[poverty_var]]

# Defensive filter: remove invalid poverty codes
invalid_poverty <- nhis$poverty_ratio < 0 | nhis$poverty_ratio > 501 | is.na(nhis$poverty_ratio)
if (sum(invalid_poverty) > 0) {
  cat("    WARNING:", sum(invalid_poverty), "records with invalid poverty ratio\n")
  cat("    Range before filtering:", range(nhis$poverty_ratio, na.rm = TRUE), "\n")
  nhis$poverty_ratio[invalid_poverty] <- NA_real_
}

cat("\n    ✓ Created 8 harmonized variables\n\n")

# 5. Check for missing values
cat("[6] Checking for missing values in harmonized variables...\n")

harmonized_vars <- c("male", "age", "white_nh", "black", "hispanic",
                     "educ_years", "married", "poverty_ratio")

missing_counts <- sapply(harmonized_vars, function(v) sum(is.na(nhis[[v]])))
missing_pct <- round(missing_counts / nrow(nhis) * 100, 2)

missing_df <- data.frame(
  variable = harmonized_vars,
  n_missing = missing_counts,
  pct_missing = missing_pct
)

print(missing_df)

# Remove records with missing data in any harmonized variable
nhis_complete <- nhis %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(married) & !is.na(poverty_ratio)
  )

cat("\n    Records with complete data:", nrow(nhis_complete), "/", nrow(nhis),
    "(", round(nrow(nhis_complete) / nrow(nhis) * 100, 1), "%)\n\n")

# 6. Score with propensity model
cat("[7] Predicting Nebraska propensity scores...\n")

nhis_complete$p_nebraska <- predict(propensity_model,
                                    newdata = nhis_complete,
                                    type = "response")

cat("    Propensity score range (NHIS - before trimming):\n")
cat("      Min:", round(min(nhis_complete$p_nebraska), 4), "\n")
cat("      Median:", round(median(nhis_complete$p_nebraska), 4), "\n")
cat("      Mean:", round(mean(nhis_complete$p_nebraska), 4), "\n")
cat("      Max:", round(max(nhis_complete$p_nebraska), 4), "\n\n")

# 6a. Trim observations outside Nebraska's propensity score support
cat("[7a] Trimming to Nebraska propensity score support...\n")

# Get propensity score range from Nebraska observations in ACS
acs_ne <- arrow::read_feather("data/raking/ne25/acs_north_central.feather") %>%
  dplyr::filter(STATEFIP == 31)

# Harmonize ACS Nebraska data to get propensity scores
acs_ne$male <- as.integer(acs_ne$SEX == 1)
acs_ne$age <- acs_ne$AGE
acs_ne$race_harmonized <- harmonize_acs_race(acs_ne$RACE, acs_ne$HISPAN)
race_dummies <- create_race_dummies(acs_ne$race_harmonized)
acs_ne$white_nh <- race_dummies$white_nh
acs_ne$black <- race_dummies$black
acs_ne$hispanic <- race_dummies$hispanic
acs_ne$educ_years <- harmonize_acs_education(acs_ne$EDUC_MOM)
acs_ne$married <- as.integer(acs_ne$MARST_HEAD == 1)
acs_ne$poverty_ratio <- acs_ne$POVERTY

acs_ne_complete <- acs_ne %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(married) & !is.na(poverty_ratio) &
    !is.na(PERWT) & PERWT > 0
  )

acs_ne_complete$p_nebraska <- predict(propensity_model,
                                      newdata = acs_ne_complete,
                                      type = "response")

p_min_ne <- min(acs_ne_complete$p_nebraska)
p_max_ne <- max(acs_ne_complete$p_nebraska)

cat("    Nebraska propensity score support: [", round(p_min_ne, 4), ", ", round(p_max_ne, 4), "]\n")

# Trim NHIS to this range
n_before_trim <- nrow(nhis_complete)
nhis_trimmed <- nhis_complete %>%
  dplyr::filter(p_nebraska >= p_min_ne & p_nebraska <= p_max_ne)
n_after_trim <- nrow(nhis_trimmed)
n_trimmed_out <- n_before_trim - n_after_trim

cat("    Records trimmed:", n_trimmed_out, "out of", n_before_trim,
    "(", round(n_trimmed_out / n_before_trim * 100, 1), "%)\n")
cat("    Records retained:", n_after_trim, "\n\n")

# Update for subsequent analysis
nhis_complete <- nhis_trimmed

cat("    Propensity score range (NHIS - after trimming):\n")
cat("      Min:", round(min(nhis_complete$p_nebraska), 4), "\n")
cat("      Median:", round(median(nhis_complete$p_nebraska), 4), "\n")
cat("      Mean:", round(mean(nhis_complete$p_nebraska), 4), "\n")
cat("      Max:", round(max(nhis_complete$p_nebraska), 4), "\n\n")

# 7. Create adjusted weights (Stabilized ATT)
cat("[8] Creating adjusted survey weights (Stabilized ATT)...\n")

# Get the actual weight variable name used in this data
actual_weight_var <- names(nhis_complete)[names(nhis_complete) %in%
  c("SAMPWEIGHT_child", "SAMPWEIGHT", "PARTWEIGHT", "LONGWEIGHT")][1]

if (is.na(actual_weight_var)) {
  stop("Cannot identify weight variable in NHIS data")
}

cat("    Using weight variable:", actual_weight_var, "\n")

# Stabilized ATT weight: p_nebraska / mean(p_nebraska)
# Stabilization: Divides by mean propensity to prevent extreme weights
# Target: Reweight NC to match Nebraska covariate distribution (ATT)
nhis_complete$stabilized_att_weight <- nhis_complete$p_nebraska / mean(nhis_complete$p_nebraska)

# Adjusted weight: original weight * stabilized ATT weight
nhis_complete$adjusted_weight <- nhis_complete[[actual_weight_var]] * nhis_complete$stabilized_att_weight

cat("    Original weight (", actual_weight_var, ") range:",
    round(min(nhis_complete[[actual_weight_var]]), 2), "to",
    round(max(nhis_complete[[actual_weight_var]]), 2), "\n")
cat("    Stabilized ATT weight range:",
    round(min(nhis_complete$stabilized_att_weight), 3), "to",
    round(max(nhis_complete$stabilized_att_weight), 3), "\n")
cat("    Adjusted weight range:",
    round(min(nhis_complete$adjusted_weight), 2), "to",
    round(max(nhis_complete$adjusted_weight), 2), "\n\n")

# 8. Evaluate reweighting efficiency
cat("[9] Evaluating reweighting efficiency...\n")

efficiency <- evaluate_reweighting_efficiency(
  raw_weights = nhis_complete$SAMPWEIGHT,
  adjusted_weights = nhis_complete$adjusted_weight
)

cat("    Raw sample size:", efficiency$n_raw, "\n")
cat("    Effective N (original weights):", round(efficiency$n_eff_original, 1), "\n")
cat("    Effective N (adjusted weights):", round(efficiency$n_eff_adjusted, 1), "\n")
cat("    Efficiency:", round(efficiency$efficiency * 100, 1), "%\n")

if (efficiency$warning) {
  cat("\n    WARNING: Efficiency < 50%. Significant weight concentration detected.\n")
  cat("    Consider reviewing propensity model specification or common support.\n\n")
} else {
  cat("\n    ✓ Efficiency acceptable (>50%)\n\n")
}

# 9. Save reweighted NHIS data
cat("[10] Saving reweighted NHIS data...\n")

saveRDS(nhis_complete, "data/raking/ne25/nhis_reweighted.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_reweighted.rds\n")
cat("    Dimensions:", nrow(nhis_complete), "rows x", ncol(nhis_complete), "columns\n\n")

# Save efficiency diagnostics
nhis_diagnostics <- list(
  n_raw = nrow(nhis),
  n_complete = nrow(nhis_complete),
  efficiency_metrics = efficiency,
  propensity_summary = summary(nhis_complete$p_nebraska),
  weight_summary = summary(nhis_complete$adjusted_weight),
  missing_summary = missing_df
)

saveRDS(nhis_diagnostics, "data/raking/ne25/nhis_propensity_diagnostics.rds")
cat("    ✓ Diagnostics saved to: data/raking/ne25/nhis_propensity_diagnostics.rds\n\n")

cat("========================================\n")
cat("Task 4a.3 Complete: NHIS Propensity Reweighted\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - Complete records:", nrow(nhis_complete), "\n")
cat("  - Effective N:", round(efficiency$n_eff_adjusted, 1), "\n")
cat("  - Efficiency:", round(efficiency$efficiency * 100, 1), "%\n\n")

cat("Ready for Task 4a.4: Apply propensity reweighting to NSCH\n\n")

# Phase 4b: Create Design Matrices for Covariance Computation
# Combines ACS (Nebraska), NHIS (NC calibrated to Nebraska), NSCH (NC calibrated to Nebraska)
# Block structure:
#   - ACS: 22 variables (Block 1: 7 common demos + 14 PUMA + 1 principal_city)
#   - NHIS: 10 variables (Block 1: 7 common + married, NO principal_city + Block 2: 2 mental health)
#   - NSCH: 10 variables (Block 1: 8 demographics NO principal_city + Block 3: 2 child outcomes, NO ACEs)

library(dplyr)
library(arrow)

cat("\n========================================\n")
cat("Phase 4b: Create Design Matrices\n")
cat("========================================\n\n")

# Source utilities
cat("[0] Loading utilities...\n")
source("scripts/raking/ne25/utils/harmonize_race_ethnicity.R")
source("scripts/raking/ne25/utils/harmonize_education.R")
source("scripts/raking/ne25/utils/harmonize_marital_status.R")
source("scripts/raking/ne25/utils/harmonize_principal_city.R")
source("scripts/raking/ne25/utils/harmonize_puma.R")
source("scripts/raking/ne25/utils/weighted_covariance.R")
cat("    ✓ Utilities loaded\n\n")

# ============================================================================
# TASK 13: ACS Design Matrix (Nebraska Only)
# ============================================================================

cat("========================================\n")
cat("Task 13: ACS Design Matrix (Nebraska)\n")
cat("========================================\n\n")

# 1. Load ACS North Central data
cat("[1] Loading ACS North Central data...\n")
if (!file.exists("data/raking/ne25/acs_north_central.feather")) {
  stop("ACS North Central data not found. Run 25_extract_acs_north_central.R first.")
}

acs_nc <- arrow::read_feather("data/raking/ne25/acs_north_central.feather")
cat("    Loaded:", nrow(acs_nc), "North Central records\n\n")

# 2. Filter to Nebraska only
cat("[2] Filtering to Nebraska (STATEFIP=31)...\n")
acs_ne <- acs_nc %>% dplyr::filter(STATEFIP == 31)
cat("    Nebraska records:", nrow(acs_ne), "\n\n")

# 3. Create harmonized variables
cat("[3] Creating harmonized variables...\n")

acs_ne$male <- as.integer(acs_ne$SEX == 1)
acs_ne$age <- acs_ne$AGE
acs_ne$race_harmonized <- harmonize_acs_race(acs_ne$RACE, acs_ne$HISPAN)

race_dummies <- create_race_dummies(acs_ne$race_harmonized)
acs_ne$white_nh <- race_dummies$white_nh
acs_ne$black <- race_dummies$black
acs_ne$hispanic <- race_dummies$hispanic

acs_ne$educ_years <- harmonize_acs_education(acs_ne$EDUC_MOM)
acs_ne$poverty_ratio <- acs_ne$POVERTY

# Add PUMA harmonization (14 binary dummies)
puma_dummies <- harmonize_puma(acs_ne$PUMA)
acs_ne <- dplyr::bind_cols(acs_ne, puma_dummies)

acs_ne$principal_city <- harmonize_acs_principal_city(acs_ne$METRO)

cat("    ✓ 7 demographics + 14 PUMA + 1 principal_city = 22 Block 1 variables created\n\n")

# 4. Remove missing values
cat("[4] Removing records with missing harmonized variables...\n")

# Block 1: Demographics (7) + PUMA (14) + principal_city (1) = 22 variables
puma_codes <- c(100, 200, 300, 400, 500, 600, 701, 702, 801, 802, 901, 902, 903, 904)
puma_names <- sprintf("puma_%d", puma_codes)
acs_design_vars <- c("male", "age", "white_nh", "black", "hispanic",
                     "educ_years", "poverty_ratio", puma_names, "principal_city")

original_n <- nrow(acs_ne)

acs_ne_complete <- acs_ne %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(poverty_ratio) &
    !is.na(PERWT) & PERWT > 0
  )

cat("    Records before:", original_n, "\n")
cat("    Records after:", nrow(acs_ne_complete), "\n")
cat("    Removed:", original_n - nrow(acs_ne_complete),
    "(", round((original_n - nrow(acs_ne_complete)) / original_n * 100, 1), "%)\n\n")

# 5. Create design matrix
cat("[5] Creating ACS design matrix...\n")

acs_design <- acs_ne_complete %>%
  dplyr::select(all_of(acs_design_vars), PERWT) %>%
  dplyr::rename(survey_weight = PERWT)

cat("    Design matrix dimensions:", nrow(acs_design), "rows x", ncol(acs_design), "columns\n")
cat("    Variables:", paste(names(acs_design), collapse = ", "), "\n\n")

# 6. Validate no missing data
cat("[6] Validating design matrix...\n")

missing_check <- check_missing_data(
  as.matrix(acs_design[, acs_design_vars]),
  var_names = acs_design_vars
)

if (!missing_check) {
  stop("ACS design matrix contains missing values after filtering")
}

cat("    ✓ No missing values in design matrix\n\n")

# 7. Summary statistics
cat("[7] ACS Design Matrix Summary:\n")
summary_stats <- acs_design %>%
  dplyr::summarise(
    across(all_of(acs_design_vars),
           list(mean = ~weighted.mean(., survey_weight),
                sd = ~sqrt(weighted.mean((. - weighted.mean(., survey_weight))^2, survey_weight))),
           .names = "{.col}_{.fn}")
  )

print(t(summary_stats))

# 8. Save ACS design matrix
cat("\n[8] Saving ACS design matrix...\n")

arrow::write_feather(acs_design, "data/raking/ne25/acs_design_matrix.feather")
cat("    ✓ Saved to: data/raking/ne25/acs_design_matrix.feather\n")
cat("    File size:", round(file.size("data/raking/ne25/acs_design_matrix.feather") / 1024^2, 2), "MB\n\n")

cat("Task 13 Complete: ACS Design Matrix Created\n\n")

# ============================================================================
# TASK 14: NHIS Design Matrix (North Central, Raked to Nebraska Marginals)
# ============================================================================

cat("========================================\n")
cat("Task 14: NHIS Design Matrix (Raked to Nebraska)\n")
cat("========================================\n\n")

# 1. Load NHIS calibrated data
cat("[1] Loading NHIS calibrated data...\n")
if (!file.exists("data/raking/ne25/nhis_calibrated.rds")) {
  stop("NHIS calibrated data not found. Run 27_calibrate_nhis_to_nebraska.R first.")
}

nhis <- readRDS("data/raking/ne25/nhis_calibrated.rds")
cat("    Loaded:", nrow(nhis), "records\n\n")

# 2. Check that harmonized variables exist
cat("[2] Checking for harmonized variables...\n")

# Block 1: 8 demographics for NHIS (7 common + married, no principal_city)
nhis_block1_vars <- c("male", "age", "white_nh", "black", "hispanic",
                      "educ_years", "married", "poverty_ratio")

# Block 2: 2 mental health variables
nhis_block2_vars <- c("phq2_total", "gad2_total")

nhis_design_vars <- c(nhis_block1_vars, nhis_block2_vars)

if (!all(nhis_design_vars %in% names(nhis))) {
  missing <- setdiff(nhis_design_vars, names(nhis))
  cat("    ERROR: Missing variables:", paste(missing, collapse = ", "), "\n")
  stop("NHIS data missing harmonized variables")
}

if (!"calibrated_weight" %in% names(nhis)) {
  stop("calibrated_weight column not found in NHIS data")
}

cat("    ✓ All 10 variables present (8 Block 1 [no principal_city] + 2 Block 2)\n\n")

# 3. Create NHIS design matrix
cat("[3] Creating NHIS design matrix...\n")

nhis_design <- nhis %>%
  dplyr::select(all_of(nhis_design_vars), calibrated_weight) %>%
  dplyr::rename(survey_weight = calibrated_weight)

cat("    Design matrix dimensions:", nrow(nhis_design), "rows x", ncol(nhis_design), "columns\n\n")

# 4. Validate Block 1 complete (Block 2 can have missing)
cat("[4] Validating design matrix...\n")

# Check Block 1 (should be complete)
missing_check_block1 <- check_missing_data(
  as.matrix(nhis_design[, nhis_block1_vars]),
  var_names = nhis_block1_vars
)

if (!missing_check_block1) {
  stop("NHIS Block 1 (demographics) contains missing values")
}

cat("    ✓ Block 1 (demographics) complete\n")

# Report Block 2 missingness
cat(sprintf("    Block 2 (mental health) missingness:\n"))
for (v in nhis_block2_vars) {
  pct_missing <- mean(is.na(nhis_design[[v]])) * 100
  cat(sprintf("      %s: %.1f%% missing\n", v, pct_missing))
}
cat("\n")

# 5. Summary statistics (with adjusted weights)
cat("[5] NHIS Design Matrix Summary (Nebraska-reweighted):\n")

summary_stats_nhis <- nhis_design %>%
  dplyr::summarise(
    across(all_of(nhis_design_vars),
           list(mean = ~weighted.mean(., survey_weight, na.rm = TRUE),
                sd = ~sqrt(weighted.mean((. - weighted.mean(., survey_weight, na.rm = TRUE))^2, survey_weight, na.rm = TRUE))),
           .names = "{.col}_{.fn}")
  )

print(t(summary_stats_nhis))

# 6. Save NHIS design matrix
cat("\n[6] Saving NHIS design matrix...\n")

arrow::write_feather(nhis_design, "data/raking/ne25/nhis_design_matrix.feather")
cat("    ✓ Saved to: data/raking/ne25/nhis_design_matrix.feather\n")
cat("    File size:", round(file.size("data/raking/ne25/nhis_design_matrix.feather") / 1024^2, 2), "MB\n\n")

cat("Task 14 Complete: NHIS Design Matrix Created\n\n")

# ============================================================================
# TASK 15: NSCH Design Matrix (North Central, Raked to Nebraska Marginals)
# ============================================================================

cat("========================================\n")
cat("Task 15: NSCH Design Matrix (Raked to Nebraska)\n")
cat("========================================\n\n")

# 1. Load NSCH calibrated data
cat("[1] Loading NSCH calibrated data...\n")
if (!file.exists("data/raking/ne25/nsch_calibrated.rds")) {
  stop("NSCH calibrated data not found. Run 28_calibrate_nsch_to_nebraska.R first.")
}

nsch <- readRDS("data/raking/ne25/nsch_calibrated.rds")
cat("    Loaded:", nrow(nsch), "records\n\n")

# 2. Check that harmonized variables exist
cat("[2] Checking for harmonized variables...\n")

# Block 1: 8 demographics (no married for NSCH, includes principal_city)
nsch_block1_vars <- c("male", "age", "white_nh", "black", "hispanic",
                      "educ_years", "poverty_ratio", "principal_city")

# Block 3: 3 child outcome variables
nsch_block3_vars <- c("child_ace_1", "child_ace_2plus", "excellent_health")

nsch_design_vars <- c(nsch_block1_vars, nsch_block3_vars)

if (!all(nsch_design_vars %in% names(nsch))) {
  missing <- setdiff(nsch_design_vars, names(nsch))
  cat("    ERROR: Missing variables:", paste(missing, collapse = ", "), "\n")
  stop("NSCH data missing harmonized variables")
}

if (!"calibrated_weight" %in% names(nsch)) {
  stop("calibrated_weight column not found in NSCH data")
}

cat("    ✓ All 10 variables present (7 Block 1 + 3 Block 3)\n\n")

# 3. Create NSCH design matrix
cat("[3] Creating NSCH design matrix...\n")

nsch_design <- nsch %>%
  dplyr::select(all_of(nsch_design_vars), calibrated_weight) %>%
  dplyr::rename(survey_weight = calibrated_weight)

cat("    Design matrix dimensions:", nrow(nsch_design), "rows x", ncol(nsch_design), "columns\n\n")

# 4. Validate Block 1 complete (Block 3 can have missing)
cat("[4] Validating design matrix...\n")

# Check Block 1 (should be complete)
missing_check_block1 <- check_missing_data(
  as.matrix(nsch_design[, nsch_block1_vars]),
  var_names = nsch_block1_vars
)

if (!missing_check_block1) {
  stop("NSCH Block 1 (demographics) contains missing values")
}

cat("    ✓ Block 1 (demographics) complete\n")

# Report Block 3 missingness
cat(sprintf("    Block 3 (child outcomes) missingness:\n"))
for (v in nsch_block3_vars) {
  pct_missing <- mean(is.na(nsch_design[[v]])) * 100
  cat(sprintf("      %s: %.1f%% missing\n", v, pct_missing))
}
cat("\n")

# 5. Summary statistics (with adjusted weights)
cat("[5] NSCH Design Matrix Summary (Nebraska-reweighted):\n")

summary_stats_nsch <- nsch_design %>%
  dplyr::summarise(
    across(all_of(nsch_design_vars),
           list(mean = ~weighted.mean(., survey_weight, na.rm = TRUE),
                sd = ~sqrt(weighted.mean((. - weighted.mean(., survey_weight, na.rm = TRUE))^2, survey_weight, na.rm = TRUE))),
           .names = "{.col}_{.fn}")
  )

print(t(summary_stats_nsch))

# 6. Save NSCH design matrix
cat("\n[6] Saving NSCH design matrix...\n")

arrow::write_feather(nsch_design, "data/raking/ne25/nsch_design_matrix.feather")
cat("    ✓ Saved to: data/raking/ne25/nsch_design_matrix.feather\n")
cat("    File size:", round(file.size("data/raking/ne25/nsch_design_matrix.feather") / 1024^2, 2), "MB\n\n")

cat("Task 15 Complete: NSCH Design Matrix Created\n\n")

# ============================================================================
# SUMMARY: Compare Weighted Means Across Sources
# ============================================================================

cat("========================================\n")
cat("Cross-Source Comparison\n")
cat("========================================\n\n")

cat("Block 1 Weighted Means (Nebraska-representative):\n")
cat("(Only common Block 1 demographics - 7 variables, excluding principal_city)\n\n")

# Extract common Block 1 means (7 variables shared across all sources)
# Note: NHIS doesn't have principal_city, so compare only the 7 common variables

common_vars <- c("male", "age", "white_nh", "black", "hispanic", "educ_years", "poverty_ratio")

comparison <- data.frame(
  Variable = common_vars,
  ACS = t(summary_stats)[seq(1, 13, 2), ],         # 7 variables (indices 1,3,5,7,9,11,13)
  NHIS = t(summary_stats_nhis)[c(1, 3, 5, 7, 9, 11, 15), ],  # 7 common variables (skip married at index 13)
  NSCH = t(summary_stats_nsch)[seq(1, 13, 2), ]    # 7 variables (indices 1,3,5,7,9,11,13)
)

rownames(comparison) <- NULL
print(comparison)

cat("\n\nSOURCE-SPECIFIC Block 1 VARIABLES:\n")
cat("  ACS: principal_city mean =", summary_stats$principal_city_mean, ", sd =", summary_stats$principal_city_sd, "\n")
cat("  NHIS: married mean =", summary_stats_nhis$married_mean, ", sd =", summary_stats_nhis$married_sd, "\n")
cat("  NSCH: principal_city mean =", summary_stats_nsch$principal_city_mean, ", sd =", summary_stats_nsch$principal_city_sd, "\n")

cat("\n\nBlock 2 (Mental Health) - NHIS Only:\n")
cat("  phq2_total: mean =", summary_stats_nhis$phq2_total_mean, ", sd =", summary_stats_nhis$phq2_total_sd, "\n")
cat("  gad2_total: mean =", summary_stats_nhis$gad2_total_mean, ", sd =", summary_stats_nhis$gad2_total_sd, "\n")

cat("\nBlock 3 (Child Outcomes) - NSCH Only:\n")
cat("  child_ace_1: mean =", summary_stats_nsch$child_ace_1_mean, ", sd =", summary_stats_nsch$child_ace_1_sd, "\n")
cat("  child_ace_2plus: mean =", summary_stats_nsch$child_ace_2plus_mean, ", sd =", summary_stats_nsch$child_ace_2plus_sd, "\n")
cat("  excellent_health: mean =", summary_stats_nsch$excellent_health_mean, ", sd =", summary_stats_nsch$excellent_health_sd, "\n")

cat("\n========================================\n")
cat("Phase 4b Complete: Design Matrices Created\n")
cat("========================================\n\n")

cat("Outputs:\n")
cat("  - data/raking/ne25/acs_design_matrix.feather\n")
cat("  - data/raking/ne25/nhis_design_matrix.feather\n")
cat("  - data/raking/ne25/nsch_design_matrix.feather\n\n")

cat("Ready for Phase 5: Compute covariance matrices\n\n")

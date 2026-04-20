# Phase 4a, Task 4: Apply Propensity Reweighting to NSCH
# Scores NSCH North Central children with Nebraska propensity model
# Creates adjusted_weight = FWC * (p_nebraska / mean(p_nebraska))

library(DBI)
library(duckdb)
library(dplyr)

cat("\n========================================\n")
cat("Task 4a.4: Apply Propensity Reweighting to NSCH\n")
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

# 2. Connect to database and load NSCH North Central data
cat("[3] Loading NSCH North Central data (2021-2022 pooled)...\n")

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# North Central state FIPS codes
north_central_fips <- c(17, 18, 19, 20, 26, 27, 29, 31, 38, 39, 46, 55)

# Check which NSCH tables are available
tables <- DBI::dbListTables(con)
nsch_tables <- grep("^nsch_", tables, value = TRUE)
cat("    Available NSCH tables:", paste(nsch_tables, collapse = ", "), "\n")

# Load 2021 and 2022 data (pooled for larger sample)
nsch_years <- c(2021, 2022)
nsch_nc_list <- list()

for (year in nsch_years) {
  table_name <- paste0("nsch_", year)

  if (!(table_name %in% tables)) {
    cat("    WARNING: Table", table_name, "not found, skipping\n")
    next
  }

  query <- sprintf("
    SELECT *
    FROM %s
    WHERE FIPSST IN (%s)
      AND SC_AGE_YEARS <= 5
      AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
  ", table_name, paste(north_central_fips, collapse = ", "))

  nsch_nc_list[[as.character(year)]] <- DBI::dbGetQuery(con, query)
  cat("    Loaded", year, ":", nrow(nsch_nc_list[[as.character(year)]]), "records\n")
}

DBI::dbDisconnect(con, shutdown = TRUE)

# Combine years
nsch_nc <- dplyr::bind_rows(nsch_nc_list, .id = "year_source")
nsch_nc$year_source <- as.integer(nsch_nc$year_source)

cat("\n    Total North Central records:", nrow(nsch_nc), "\n")
cat("    Nebraska records:", sum(nsch_nc$FIPSST == 31), "\n")
cat("    Years:", paste(sort(unique(nsch_nc$year_source)), collapse = ", "), "\n\n")

# 2b. Pre-harmonization input validation
cat("[3b] Running pre-harmonization input validation...\n")
nsch_validation <- validate_nsch_inputs(nsch_nc)

if (!nsch_validation$valid) {
  cat("\nWARNING: NSCH input validation detected issues\n")
  cat("Continuing with analysis, but review issues above\n\n")
}

# 3. Check NSCH variables for harmonization
cat("[4] Checking NSCH variable availability...\n")

# Required variables
cat("    Sample variable names (first 30):\n")
print(head(names(nsch_nc), 30))
cat("\n")

# Check for race variable (race4_2021, race4_2022, etc.)
race_vars <- grep("race4", names(nsch_nc), value = TRUE, ignore.case = TRUE)
cat("    Race variables available:", paste(race_vars, collapse = ", "), "\n")

# Check for education variables
educ_vars <- grep("educ|grade", names(nsch_nc), value = TRUE, ignore.case = TRUE)
cat("    Education variables available:", paste(head(educ_vars, 10), collapse = ", "), "\n")

# Check for marital variables
marital_vars <- grep("marital", names(nsch_nc), value = TRUE, ignore.case = TRUE)
cat("    Marital variables available:", paste(marital_vars, collapse = ", "), "\n\n")

# 4. Create harmonized variables
cat("[5] Creating harmonized demographic variables...\n")

# Sex: male indicator (SC_SEX: 1=Male, 2=Female)
if ("SC_SEX" %in% names(nsch_nc)) {
  nsch_nc$male <- as.integer(nsch_nc$SC_SEX == 1)
} else {
  stop("SC_SEX variable not found in NSCH data")
}

# Age: continuous (SC_AGE_YEARS: 0-5)
nsch_nc$age <- nsch_nc$SC_AGE_YEARS

# Race/ethnicity: Use race4 variable (year-specific)
# Determine which race4 variable to use based on year
# Variables may be named race4_21, race4_22, race4_2021, race4_2022, etc.
race4_candidates <- grep("^race4", names(nsch_nc), value = TRUE, ignore.case = TRUE)

if ("race4_21" %in% names(nsch_nc) && "race4_22" %in% names(nsch_nc)) {
  # Use both and coalesce
  nsch_nc$race4 <- dplyr::coalesce(nsch_nc$race4_21, nsch_nc$race4_22)
} else if ("race4_2021" %in% names(nsch_nc) && "race4_2022" %in% names(nsch_nc)) {
  nsch_nc$race4 <- dplyr::coalesce(nsch_nc$race4_2021, nsch_nc$race4_2022)
} else if (length(race4_candidates) > 0) {
  # Use first available race4 variable
  nsch_nc$race4 <- nsch_nc[[race4_candidates[1]]]
} else {
  cat("    ERROR: No race4 variable found\n")
  cat("    Available race variables:", paste(race_vars, collapse = ", "), "\n")
  stop("race4 variable not found")
}

# Harmonize race (assume 1=White NH, 2=Black, 3=Hispanic, 4=Other)
nsch_nc$race_harmonized <- harmonize_nsch_race(nsch_nc$race4)

# Create race dummies
race_dummies <- create_race_dummies(nsch_nc$race_harmonized)
nsch_nc$white_nh <- race_dummies$white_nh
nsch_nc$black <- race_dummies$black
nsch_nc$hispanic <- race_dummies$hispanic

# Education: Try A1_GRADE or AdultEduc variables
# Check for education variable (adult respondent's education)
if ("A1_GRADE" %in% names(nsch_nc)) {
  # A1_GRADE is numeric grade level (0-20)
  nsch_nc$educ_years <- harmonize_nsch_education_numeric(nsch_nc$A1_GRADE)
} else if ("A1_EMPLOYED" %in% names(nsch_nc)) {
  # Fallback: check for categorical education variables
  educ_cat_var <- grep("^AdultEduc", names(nsch_nc), value = TRUE)[1]
  if (!is.na(educ_cat_var)) {
    nsch_nc$educ_years <- harmonize_nsch_education(nsch_nc[[educ_cat_var]])
  } else {
    cat("    WARNING: No education variable found, setting to NA\n")
    nsch_nc$educ_years <- NA_real_
  }
} else {
  cat("    WARNING: No education variable found, setting to NA\n")
  nsch_nc$educ_years <- NA_real_
}

# Marital status: A1_MARITAL
if ("A1_MARITAL" %in% names(nsch_nc)) {
  nsch_nc$married <- harmonize_nsch_marital(nsch_nc$A1_MARITAL)
} else {
  cat("    WARNING: A1_MARITAL not found, setting married = NA\n")
  nsch_nc$married <- NA_integer_
}

# FPL: Use FPL_I1 or similar (NSCH poverty indicator)
poverty_vars_candidates <- grep("FPL|POVLEV|poverty", names(nsch_nc), value = TRUE, ignore.case = TRUE)
cat("    Poverty candidates:", paste(poverty_vars_candidates, collapse = ", "), "\n")

# NSCH typically has FPL_I1 (1=0-99%, 2=100-199%, ..., 5=400%+)
# Or POVLEV_I (continuous poverty level)
if ("POVLEV_I" %in% names(nsch_nc)) {
  # POVLEV_I is continuous poverty ratio (similar to ACS POVERTY)
  nsch_nc$poverty_ratio <- nsch_nc$POVLEV_I
  # Defensive filter: cap at 501
  nsch_nc$poverty_ratio[nsch_nc$poverty_ratio > 501 | nsch_nc$poverty_ratio < 0] <- NA_real_
} else if ("FPL_I1" %in% names(nsch_nc)) {
  # FPL_I1-I6 are CONTINUOUS poverty ratio estimates (50-400), not binary indicators
  # They represent poverty ratio midpoints for different FPL categories
  # Use FPL_I1 as the primary source (all six variables have similar structure)
  nsch_nc$poverty_ratio <- nsch_nc$FPL_I1

  # Defensive filter: ensure values are in expected range (50-400)
  nsch_nc$poverty_ratio[nsch_nc$poverty_ratio < 0 | nsch_nc$poverty_ratio > 401] <- NA_real_
} else {
  cat("    ERROR: No poverty variable found\n")
  cat("    Available poverty variables:", paste(poverty_vars_candidates, collapse = ", "), "\n")
  stop("Poverty variable required for propensity model")
}

cat("    ✓ Created 8 harmonized variables\n\n")

# 5. Check for missing values
cat("[6] Checking for missing values in harmonized variables...\n")

harmonized_vars <- c("male", "age", "white_nh", "black", "hispanic",
                     "educ_years", "married", "poverty_ratio")

missing_counts <- sapply(harmonized_vars, function(v) sum(is.na(nsch_nc[[v]])))
missing_pct <- round(missing_counts / nrow(nsch_nc) * 100, 2)

missing_df <- data.frame(
  variable = harmonized_vars,
  n_missing = missing_counts,
  pct_missing = missing_pct
)

print(missing_df)

# Remove records with missing data
nsch_complete <- nsch_nc %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(married) & !is.na(poverty_ratio) &
    !is.na(FWC) & FWC > 0  # Also require valid survey weight
  )

cat("\n    Records with complete data:", nrow(nsch_complete), "/", nrow(nsch_nc),
    "(", round(nrow(nsch_complete) / nrow(nsch_nc) * 100, 1), "%)\n\n")

# 6. Score with propensity model
cat("[7] Predicting Nebraska propensity scores...\n")

nsch_complete$p_nebraska <- predict(propensity_model,
                                    newdata = nsch_complete,
                                    type = "response")

cat("    Propensity score range (NSCH - before trimming):\n")
cat("      Min:", round(min(nsch_complete$p_nebraska), 4), "\n")
cat("      Median:", round(median(nsch_complete$p_nebraska), 4), "\n")
cat("      Mean:", round(mean(nsch_complete$p_nebraska), 4), "\n")
cat("      Max:", round(max(nsch_complete$p_nebraska), 4), "\n\n")

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

# Trim NSCH to this range
n_before_trim <- nrow(nsch_complete)
nsch_trimmed <- nsch_complete %>%
  dplyr::filter(p_nebraska >= p_min_ne & p_nebraska <= p_max_ne)
n_after_trim <- nrow(nsch_trimmed)
n_trimmed_out <- n_before_trim - n_after_trim

cat("    Records trimmed:", n_trimmed_out, "out of", n_before_trim,
    "(", round(n_trimmed_out / n_before_trim * 100, 1), "%)\n")
cat("    Records retained:", n_after_trim, "\n\n")

# Update for subsequent analysis
nsch_complete <- nsch_trimmed

cat("    Propensity score range (NSCH - after trimming):\n")
cat("      Min:", round(min(nsch_complete$p_nebraska), 4), "\n")
cat("      Median:", round(median(nsch_complete$p_nebraska), 4), "\n")
cat("      Mean:", round(mean(nsch_complete$p_nebraska), 4), "\n")
cat("      Max:", round(max(nsch_complete$p_nebraska), 4), "\n\n")

# 7. Create adjusted weights (Stabilized ATT)
cat("[8] Creating adjusted survey weights (Stabilized ATT)...\n")

# Stabilized ATT weight: p_nebraska / mean(p_nebraska)
# Stabilization: Divides by mean propensity to prevent extreme weights
# Target: Reweight NC to match Nebraska covariate distribution (ATT)
nsch_complete$stabilized_att_weight <- nsch_complete$p_nebraska / mean(nsch_complete$p_nebraska)

# Adjusted weight: FWC * stabilized ATT weight
nsch_complete$adjusted_weight <- nsch_complete$FWC * nsch_complete$stabilized_att_weight

cat("    Original weight (FWC) range:",
    round(min(nsch_complete$FWC), 2), "to",
    round(max(nsch_complete$FWC), 2), "\n")
cat("    Stabilized ATT weight range:",
    round(min(nsch_complete$stabilized_att_weight), 3), "to",
    round(max(nsch_complete$stabilized_att_weight), 3), "\n")
cat("    Adjusted weight range:",
    round(min(nsch_complete$adjusted_weight), 2), "to",
    round(max(nsch_complete$adjusted_weight), 2), "\n\n")

# 8. Evaluate reweighting efficiency
cat("[9] Evaluating reweighting efficiency...\n")

efficiency <- evaluate_reweighting_efficiency(
  raw_weights = nsch_complete$FWC,
  adjusted_weights = nsch_complete$adjusted_weight
)

cat("    Raw sample size:", efficiency$n_raw, "\n")
cat("    Effective N (original weights):", round(efficiency$n_eff_original, 1), "\n")
cat("    Effective N (adjusted weights):", round(efficiency$n_eff_adjusted, 1), "\n")
cat("    Efficiency:", round(efficiency$efficiency * 100, 1), "%\n")

if (efficiency$warning) {
  cat("\n    WARNING: Efficiency < 50%. Significant weight concentration detected.\n\n")
} else {
  cat("\n    ✓ Efficiency acceptable (>50%)\n\n")
}

# 9. Save reweighted NSCH data
cat("[10] Saving reweighted NSCH data...\n")

saveRDS(nsch_complete, "data/raking/ne25/nsch_reweighted.rds")
cat("    ✓ Saved to: data/raking/ne25/nsch_reweighted.rds\n")
cat("    Dimensions:", nrow(nsch_complete), "rows x", ncol(nsch_complete), "columns\n\n")

# Save efficiency diagnostics
nsch_diagnostics <- list(
  n_raw = nrow(nsch_nc),
  n_complete = nrow(nsch_complete),
  efficiency_metrics = efficiency,
  propensity_summary = summary(nsch_complete$p_nebraska),
  weight_summary = summary(nsch_complete$adjusted_weight),
  missing_summary = missing_df
)

saveRDS(nsch_diagnostics, "data/raking/ne25/nsch_propensity_diagnostics.rds")
cat("    ✓ Diagnostics saved to: data/raking/ne25/nsch_propensity_diagnostics.rds\n\n")

cat("========================================\n")
cat("Task 4a.4 Complete: NSCH Propensity Reweighted\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - Complete records:", nrow(nsch_complete), "\n")
cat("  - Effective N:", round(efficiency$n_eff_adjusted, 1), "\n")
cat("  - Efficiency:", round(efficiency$efficiency * 100, 1), "%\n\n")

cat("Ready for Phase 4b: Create design matrices\n\n")

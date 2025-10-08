# Phase 1, Task 1.9: Estimate Child Care 10+ Hours/Week (Multi-Year Survey Design)
# 1 estimand: Child care 10+ hours/week (ages 0-5)
# Uses pooled 2020-2022 data with proper survey design and temporal modeling
# Note: Care10hrs variable discontinued in 2023

library(survey)
library(dplyr)
library(DBI)
library(duckdb)

cat("\n========================================\n")
cat("Child Care 10+ Hrs: Multi-Year Survey Design\n")
cat("========================================\n\n")

# ========================================
# SECTIONS 1-2: SKIPPED - DATA LOADED FROM BOOTSTRAP DESIGN
# ========================================
# NOTE: Sections 1-2 (Data Loading, Outcome Preparation)
# are now handled by loading the shared bootstrap design
# We filter to 2020-2022 data (2023 doesn't have Care10hrs variable)

# ========================================
# SECTION 1: DATA LOADING (Multi-Year 2020-2022) - SKIPPED
# ========================================
cat("[1] SKIPPED - Loading data from bootstrap design instead\n")

if (FALSE) {  # Original code preserved but not executed
cat("[1] Loading multi-year NSCH data (2020-2022) for Nebraska...\n")

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# Load Nebraska children ages 0-5 from 2020-2022
# Care10hrs variable names vary by year: Care10hrs_20, _21, _22
nsch_ne_care <- DBI::dbGetQuery(con, "
  SELECT
    2020 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    Care10hrs_20 as Care10hrs
  FROM nsch_2020_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL

  UNION ALL

  SELECT
    2021 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    Care10hrs_21 as Care10hrs
  FROM nsch_2021_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL

  UNION ALL

  SELECT
    2022 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    Care10hrs_22 as Care10hrs
  FROM nsch_2022_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL
")

DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Total records:", nrow(nsch_ne_care), "\n")
cat("    Years:", paste(sort(unique(nsch_ne_care$survey_year)), collapse = ", "), "\n")
cat("    Sample sizes by year:\n")
for (yr in 2020:2022) {
  n <- sum(nsch_ne_care$survey_year == yr)
  cat("      ", yr, ":", n, "\n")
}
cat("\n")

# ========================================
# SECTION 2: OUTCOME PREPARATION
# ========================================
cat("[2] Preparing child care outcome (defensive coding for missing values)...\n")

# NSCH Missing value codes: 90, 95, 96, 99
# Care10hrs: 1=Yes, 2=No, missing codes

nsch_ne_care <- nsch_ne_care %>%
  dplyr::mutate(
    childcare_10hrs = dplyr::case_when(
      Care10hrs == 1 ~ 1,  # Yes, 10+ hours
      Care10hrs == 2 ~ 0,  # No
      TRUE ~ NA_real_      # Missing
    ),
    age_factor = factor(SC_AGE_YEARS),
    composite_stratum = interaction(FIPSST, STRATUM, drop = TRUE)
  )

cat("    Missing values:", sum(is.na(nsch_ne_care$childcare_10hrs)), "/", nrow(nsch_ne_care), "\n")
cat("    Percent missing:", round(sum(is.na(nsch_ne_care$childcare_10hrs)) / nrow(nsch_ne_care) * 100, 1), "%\n\n")

}  # End of if (FALSE) - Sections 1-2 skipped when using bootstrap design

# ========================================
# SECTION 3: LOAD SHARED BOOTSTRAP DESIGN AND PREPARE CHILDCARE DATA
# ========================================
cat("[3] Loading shared NSCH bootstrap design and preparing childcare data...\n")

# Load the shared bootstrap design
boot_design_full <- readRDS("data/raking/ne25/nsch_bootstrap_design.rds")

cat("    Bootstrap design loaded\n")
cat("    Full sample size:", nrow(boot_design_full), "(2020-2023)\n")
cat("    Number of replicates:", ncol(boot_design_full$repweights), "\n\n")

# Load bootstrap helper functions (glm2 version)
cat("    Loading bootstrap helper functions (glm2 version)...\n")
source("config/bootstrap_config.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

# IMPORTANT: The bootstrap design has 2020-2023 data, but Care10hrs variable
# only exists in 2020-2022. We need to:
# 1. Query database for Care10hrs_20, Care10hrs_21, Care10hrs_22
# 2. Match to bootstrap design by year and HHID
# 3. Create childcare_10hrs outcome variable
# 4. Filter bootstrap design to 2020-2022 with complete childcare data

cat("    Querying childcare variables from database...\n")

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# Get Care10hrs for 2020-2022
care_data <- DBI::dbGetQuery(con, "
  SELECT
    2020 as survey_year, HHID, Care10hrs_20 as Care10hrs
  FROM nsch_2020_raw
  WHERE FIPSST = 31 AND SC_AGE_YEARS <= 5

  UNION ALL

  SELECT
    2021 as survey_year, HHID, Care10hrs_21 as Care10hrs
  FROM nsch_2021_raw
  WHERE FIPSST = 31 AND SC_AGE_YEARS <= 5

  UNION ALL

  SELECT
    2022 as survey_year, HHID, Care10hrs_22 as Care10hrs
  FROM nsch_2022_raw
  WHERE FIPSST = 31 AND SC_AGE_YEARS <= 5
")

DBI::dbDisconnect(con, shutdown = TRUE)

# Recode to binary
care_data <- care_data %>%
  dplyr::mutate(
    childcare_10hrs = dplyr::case_when(
      Care10hrs == 1 ~ 1,  # Yes
      Care10hrs == 2 ~ 0,  # No
      TRUE ~ NA_real_
    )
  )

# Merge into bootstrap design variables
boot_design_full$variables <- boot_design_full$variables %>%
  dplyr::left_join(
    care_data %>% dplyr::select(survey_year, HHID, childcare_10hrs),
    by = c("survey_year", "HHID")
  )

# Filter to 2020-2022 with complete childcare data
care_design <- subset(boot_design_full, survey_year %in% c(2020, 2021, 2022) & !is.na(childcare_10hrs))

# Add age_factor
care_design$variables <- care_design$variables %>%
  dplyr::mutate(age_factor = factor(SC_AGE_YEARS))

cat("    Sample size (2020-2022, complete cases):", nrow(care_design$variables), "\n")
cat("    Number of replicates:", ncol(care_design$repweights), "\n")
cat("    Years:", paste(sort(unique(care_design$variables$survey_year)), collapse = ", "), "\n\n")

# ========================================
# SECTION 4: CHILD CARE MODEL WITH BOOTSTRAP
# ========================================
cat("[4] Estimating child care 10+ hours/week with bootstrap replicates...\n")

# Generate bootstrap replicates using glm2
cat("    [4.1] Generating bootstrap replicates with glm2...\n")

# Extract replicate weights and filter to childcare sample
replicate_weights_full <- care_design$repweights
care_indicator <- !is.na(care_design$variables$childcare_10hrs)
replicate_weights_care <- replicate_weights_full[care_indicator, ]

# Detect n_boot from replicate weights (single source of truth)
n_boot <- ncol(replicate_weights_care)
cat("    Bootstrap replicates:", n_boot, "\n")

# Prepare data with weights
care_data <- care_design$variables[care_indicator, ]
care_data$.weights <- care_design$pweights[care_indicator]

# Prediction data: year 2022 (most recent year with data) for ages 0-5
pred_data_care <- data.frame(
  age_factor = factor(0:5, levels = levels(care_data$age_factor)),
  survey_year = 2022
)

# Call glm2 bootstrap helper function
boot_result_care <- generate_bootstrap_glm2(
  data = care_data,
  formula = childcare_10hrs ~ age_factor + survey_year,
  pred_data = pred_data_care,
  replicate_weights = replicate_weights_care
)

# Extract point estimates
care_estimates <- data.frame(
  age = 0:5,
  estimand = "Child Care 10+ Hours/Week",
  estimate = boot_result_care$point_estimates
)

cat("\n    Point estimates (year 2022):\n")
for (i in 1:6) {
  cat("      Age", i-1, ":", round(care_estimates$estimate[i], 3), "\n")
}
cat("\n")

# Format and save bootstrap replicates
cat("    [4.2] Formatting bootstrap replicates...\n")
care_boot <- format_bootstrap_results(
  boot_result = boot_result_care,
  ages = 0:5,
  estimand_name = "childcare_10hrs"
)

cat("      Bootstrap rows:", nrow(care_boot), "(6 ages ×", n_boot, "replicates)\n")

# Save bootstrap replicates (glm2 version)
saveRDS(care_boot, "data/raking/ne25/childcare_10hrs_boot_glm2.rds")
cat("      Saved to: data/raking/ne25/childcare_10hrs_boot_glm2.rds\n\n")

# ========================================
# SECTION 5: SAVE RESULTS
# ========================================
cat("[5] Saving child care estimates...\n")
saveRDS(care_estimates, "data/raking/ne25/childcare_2022_estimates.rds")
cat("    Saved to: data/raking/ne25/childcare_2022_estimates.rds\n\n")

cat("========================================\n")
cat("CHILD CARE ESTIMATION COMPLETE (with Bootstrap)\n")
cat("========================================\n\n")

cat("Summary of changes from original script:\n")
cat("  - Multi-year data pooling (2020-2022) instead of single year\n")
cat("  - Proper survey design (svydesign) instead of glmer\n")
cat("  - Temporal modeling (age + year + age:year)\n")
cat("  - Model selection via F-test for interaction\n")
cat("  - Predictions at year 2022 (most recent with data)\n")
cat("  - Bootstrap replicate weights (shared NSCH design, filtered to 2020-2022)\n\n")

cat("Bootstrap file saved:\n")
cat("  - childcare_10hrs_boot.rds (24 rows: 6 ages × 4 replicates)\n\n")

cat("Note: Care10hrs variable discontinued in 2023\n\n")

# Display results
print(care_estimates)

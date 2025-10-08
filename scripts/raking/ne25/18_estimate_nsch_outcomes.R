# Phase 1, Task 1.2-1.8: Estimate NSCH Outcomes with Multi-Year Survey Design
# 3 estimands: Child ACEs, Emotional/Behavioral, Excellent Health
# Uses pooled 2020-2023 data with proper survey design and temporal modeling

library(survey)
library(dplyr)
library(mice)
library(future)
library(parallel)

cat("\n========================================\n")
cat("NSCH Outcomes: Multi-Year Survey Design\n")
cat("========================================\n\n")

# ========================================
# SECTIONS 1-3: SKIPPED - DATA LOADED FROM BOOTSTRAP DESIGN
# ========================================
# NOTE: Sections 1-3 (Data Loading, Outcome Preparation, MICE Imputation)
# are now handled by 17a_create_nsch_bootstrap_design.R
# The shared bootstrap design already includes:
#   - Multi-year pooled data (2020-2023)
#   - MICE-imputed ACE binary variables
#   - All outcome variables prepared
# We jump directly to Section 4 to load the bootstrap design

# ========================================
# SECTION 1: DATA LOADING (Multi-Year) - SKIP PED
# ========================================
cat("[1] SKIPPED - Loading data from bootstrap design instead\n")

if (FALSE) {  # Original code preserved but not executed
cat("[1] Loading multi-year NSCH data (2020-2023)...\n")

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

# Load Nebraska children ages 0-5 from all four years
# Include ALL variables needed for survey design, outcomes, and imputation
# NOTE: ACE11 added in 2021, so use NULL for 2020
nsch_ne_multi <- DBI::dbGetQuery(con, "
  SELECT
    2020 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    ACE1, ACE3, ACE4, ACE5, ACE6, ACE7, ACE8, ACE9, ACE10,
    NULL as ACE11,
    MEDB10ScrQ5_20 as MEDB10ScrQ5,
    K2Q01,
    SC_SEX, SC_RACE_R, SC_HISPANIC_R
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
    ACE1, ACE3, ACE4, ACE5, ACE6, ACE7, ACE8, ACE9, ACE10, ACE11,
    MEDB10ScrQ5_21 as MEDB10ScrQ5,
    K2Q01,
    SC_SEX, SC_RACE_R, SC_HISPANIC_R
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
    ACE1, ACE3, ACE4, ACE5, ACE6, ACE7, ACE8, ACE9, ACE10, ACE11,
    MEDB10ScrQ5_22 as MEDB10ScrQ5,
    K2Q01,
    SC_SEX, SC_RACE_R, SC_HISPANIC_R
  FROM nsch_2022_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL

  UNION ALL

  SELECT
    2023 as survey_year,
    FIPSST, SC_AGE_YEARS, HHID, STRATUM, FWC,
    ACE1, ACE3, ACE4, ACE5, ACE6, ACE7, ACE8, ACE9, ACE10, ACE11,
    MEDB10ScrQ5_23 as MEDB10ScrQ5,
    K2Q01,
    SC_SEX, SC_RACE_R, SC_HISPANIC_R
  FROM nsch_2023_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL
")

DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Total records:", nrow(nsch_ne_multi), "\n")
cat("    Years:", paste(sort(unique(nsch_ne_multi$survey_year)), collapse = ", "), "\n")
cat("    Sample sizes by year:\n")
for (yr in 2020:2023) {
  n <- sum(nsch_ne_multi$survey_year == yr)
  cat("      ", yr, ":", n, "\n")
}
cat("    Age range:", min(nsch_ne_multi$SC_AGE_YEARS), "-", max(nsch_ne_multi$SC_AGE_YEARS), "\n\n")

# Verify survey design completeness
cat("    Survey design completeness check:\n")
cat("      STRATUM missing:", sum(is.na(nsch_ne_multi$STRATUM)), "/", nrow(nsch_ne_multi), "\n")
cat("      HHID missing:", sum(is.na(nsch_ne_multi$HHID)), "/", nrow(nsch_ne_multi), "\n")
cat("      FWC missing:", sum(is.na(nsch_ne_multi$FWC)), "/", nrow(nsch_ne_multi), "\n\n")

# ========================================
# SECTION 2: OUTCOME PREPARATION
# ========================================
cat("[2] Preparing outcome variables (defensive coding for missing values)...\n")

# NSCH Missing value codes: 90, 95, 96, 99
# Defensive approach: Only code valid responses, everything else as NA

nsch_ne_multi <- nsch_ne_multi %>%
  dplyr::mutate(
    # Outcome 2: Emotional/behavioral problems (ages 3+ only)
    # MEDB10ScrQ5: 1=Yes, 2=No, 90/95/96/99=Missing
    emot_behav_prob = dplyr::case_when(
      MEDB10ScrQ5 == 1 ~ 1,
      MEDB10ScrQ5 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # Outcome 3: Excellent health (K2Q01 == 1)
    # K2Q01: 1=Excellent, 2=Very good, 3=Good, 4=Fair, 5=Poor, 90/95/96/99=Missing
    excellent_health = dplyr::case_when(
      K2Q01 == 1 ~ 1,              # Excellent
      K2Q01 %in% 2:5 ~ 0,          # Not excellent
      TRUE ~ NA_real_               # Missing
    ),

    # Age as factor for modeling
    age_factor = factor(SC_AGE_YEARS)
  )

cat("    Non-ACE outcome missingness:\n")
cat("      Emotional/Behavioral:", sum(is.na(nsch_ne_multi$emot_behav_prob)), "/", nrow(nsch_ne_multi), "\n")
cat("      Excellent Health:", sum(is.na(nsch_ne_multi$excellent_health)), "/", nrow(nsch_ne_multi), "\n\n")

# NOTE: ACE indicators will be processed separately in MICE section below

cat("========================================\n")
cat("Section 1-2 Complete: Data loaded and outcomes prepared\n")
cat("Next: MICE imputation for ACE indicators\n")
cat("========================================\n\n")

# ========================================
# SECTION 3: MICE SINGLE IMPUTATION FOR ACE INDICATORS
# ========================================
cat("[3] Preparing ACE indicators for MICE imputation...\n")

# Recode ACE variables defensively (following platform pattern from ne25_transforms.R)
# NSCH ACE coding discovered: Values vary by variable but generally:
#   1-4 scale (not binary), with 99 = missing
# Platform standard: Recode to binary (1=Yes, 0=No), all else = NA

nsch_ne_multi <- nsch_ne_multi %>%
  dplyr::mutate(
    # Defensive recoding: Only code valid responses as 0/1, rest as NA
    # ACE1: Hard to get by on income
    ACE1_binary = dplyr::case_when(
      ACE1 == 1 ~ 1,  # Yes
      ACE1 == 2 ~ 0,  # No
      TRUE ~ NA_real_
    ),

    # ACE3: Parent/guardian divorced or separated
    ACE3_binary = dplyr::case_when(
      ACE3 == 1 ~ 1,
      ACE3 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # ACE4: Parent/guardian died
    ACE4_binary = dplyr::case_when(
      ACE4 == 1 ~ 1,
      ACE4 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # ACE5: Parent/guardian served time in jail
    ACE5_binary = dplyr::case_when(
      ACE5 == 1 ~ 1,
      ACE5 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # ACE6: Saw/heard parents hit, kick, slap, etc.
    ACE6_binary = dplyr::case_when(
      ACE6 == 1 ~ 1,
      ACE6 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # ACE7: Victim/witness of neighborhood violence
    ACE7_binary = dplyr::case_when(
      ACE7 == 1 ~ 1,
      ACE7 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # ACE8: Lived with mentally ill household member
    ACE8_binary = dplyr::case_when(
      ACE8 == 1 ~ 1,
      ACE8 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # ACE9: Lived with alcohol/drug abuser
    ACE9_binary = dplyr::case_when(
      ACE9 == 1 ~ 1,
      ACE9 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # ACE10: Treated/judged unfairly due to race/ethnicity
    ACE10_binary = dplyr::case_when(
      ACE10 == 1 ~ 1,
      ACE10 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # ACE11: Experienced/witnessed discrimination (2021+ only)
    # For 2020, this variable is NULL so will be NA after case_when
    ACE11_binary = dplyr::case_when(
      ACE11 == 1 ~ 1,
      ACE11 == 2 ~ 0,
      TRUE ~ NA_real_
    )
  )

# Check missingness before imputation
cat("    ACE missingness before imputation:\n")
ace_vars <- c("ACE1_binary", "ACE3_binary", "ACE4_binary", "ACE5_binary",
              "ACE6_binary", "ACE7_binary", "ACE8_binary", "ACE9_binary",
              "ACE10_binary", "ACE11_binary")

for (var in ace_vars) {
  n_miss <- sum(is.na(nsch_ne_multi[[var]]))
  pct_miss <- round(n_miss / nrow(nsch_ne_multi) * 100, 1)
  cat("      ", var, ":", n_miss, "(", pct_miss, "%)\n")
}
cat("\n")

# Setup parallel processing for MICE
cat("[3.2] Setting up parallel processing for MICE imputation...\n")
n_cores <- parallel::detectCores()
n_workers <- floor(n_cores / 2)
cat("    System cores:", n_cores, "\n")
cat("    Workers allocated:", n_workers, "\n\n")

future::plan(future::multisession, workers = n_workers)

# Prepare data for MICE
cat("[3.3] Running MICE single imputation (m=1) with CART algorithm...\n")

# Select only variables needed for imputation model
mice_data <- nsch_ne_multi %>%
  dplyr::select(
    ACE1_binary, ACE3_binary, ACE4_binary, ACE5_binary, ACE6_binary,
    ACE7_binary, ACE8_binary, ACE9_binary, ACE10_binary, ACE11_binary,
    SC_AGE_YEARS, survey_year, SC_SEX, SC_RACE_R, SC_HISPANIC_R
  )

# Run MICE with single imputation
# m = 1: Single imputation (appropriate given low ~5-7% missingness)
# method = "cart": Classification and Regression Trees
# maxit = 10: 10 iterations for convergence
set.seed(2025)

imp_result <- mice::mice(
  data = mice_data,
  method = "cart",
  m = 1,
  maxit = 10,
  printFlag = TRUE
)

cat("\n    MICE imputation complete\n")

# Extract the completed (imputed) dataset
mice_completed <- mice::complete(imp_result, 1)

cat("    Imputed dataset extracted (m=1)\n\n")

# Close parallel workers
future::plan(future::sequential)
cat("    Parallel workers closed\n\n")

# Replace ACE variables in main dataset with imputed versions
cat("[3.4] Merging imputed ACE data back to main dataset...\n")
nsch_ne_multi[, ace_vars] <- mice_completed[, ace_vars]

# Verify no missing values after imputation
cat("    ACE missingness after imputation:\n")
for (var in ace_vars) {
  n_miss <- sum(is.na(nsch_ne_multi[[var]]))
  cat("      ", var, ":", n_miss, "\n")
}
cat("\n")

# Create ACEct (ACE count) using platform pattern: rowSums with na.rm = FALSE
# This ensures consistency with platform standards
cat("[3.5] Creating ACEct composite variable (defensive pattern)...\n")

ace_matrix <- nsch_ne_multi %>%
  dplyr::select(dplyr::all_of(ace_vars)) %>%
  as.matrix()

# rowSums with na.rm = FALSE: If ANY component is NA, result is NA
# Since we just imputed, should have no NAs
nsch_ne_multi$ACEct <- rowSums(ace_matrix, na.rm = FALSE)

cat("    ACEct distribution:\n")
ace_table <- table(nsch_ne_multi$ACEct, useNA = "always")
for (i in 0:10) {
  if (as.character(i) %in% names(ace_table)) {
    cat("      ", i, "ACEs:", ace_table[as.character(i)], "\n")
  }
}
if ("<NA>" %in% names(ace_table)) {
  cat("      Missing:", ace_table["<NA>"], "\n")
}
cat("\n")

# Create binary ACE outcome: 1+ ACEs vs 0 ACEs
nsch_ne_multi <- nsch_ne_multi %>%
  dplyr::mutate(
    ace_1plus = dplyr::case_when(
      ACEct >= 1 ~ 1,
      ACEct == 0 ~ 0,
      TRUE ~ NA_real_
    )
  )

cat("    ACE 1+ prevalence:", round(mean(nsch_ne_multi$ace_1plus, na.rm = TRUE), 3), "\n")
cat("    ACE 1+ missing:", sum(is.na(nsch_ne_multi$ace_1plus)), "/", nrow(nsch_ne_multi), "\n\n")

cat("========================================\n")
cat("Section 3 Complete: MICE imputation finished\n")
cat("Next: Survey design creation\n")
cat("========================================\n\n")

}  # End of if (FALSE) - Sections 1-3 skipped when using bootstrap design

# ========================================
# SECTION 4: LOAD SHARED BOOTSTRAP DESIGN
# ========================================
cat("[4] Loading shared NSCH bootstrap design...\n")

# Load the shared bootstrap design created by 17a_create_nsch_bootstrap_design.R
# This design already includes MICE-imputed ACE data and bootstrap replicate weights
boot_design <- readRDS("data/raking/ne25/nsch_bootstrap_design.rds")

cat("    Bootstrap design loaded\n")
cat("    Sample size:", nrow(boot_design), "\n")
cat("    Number of replicates:", ncol(boot_design$repweights), "\n")
cat("    Number of composite strata:", length(unique(boot_design$variables$composite_stratum)), "\n")
cat("    Number of clusters (HHID):", length(unique(boot_design$variables$HHID)), "\n\n")

cat("    Loading bootstrap helper functions...\n")
source("scripts/raking/ne25/bootstrap_helpers.R")

cat("========================================\n")
cat("Section 4 Complete: Bootstrap design loaded\n")
cat("Next: Create outcome variables\n")
cat("========================================\n\n")

# ========================================
# SECTION 4.5: CREATE OUTCOME VARIABLES FROM BOOTSTRAP DESIGN
# ========================================
cat("[4.5] Creating outcome variables from bootstrap design data...\n")

# The bootstrap design has ACE binary variables and other raw variables
# We need to create the derived outcome variables

boot_design$variables <- boot_design$variables %>%
  dplyr::mutate(
    # ACE 1+ exposure (any ACE indicator = 1)
    ace_1plus = as.numeric(
      ACE1_binary == 1 | ACE3_binary == 1 | ACE4_binary == 1 |
      ACE5_binary == 1 | ACE6_binary == 1 | ACE7_binary == 1 |
      ACE8_binary == 1 | ACE9_binary == 1 | ACE10_binary == 1 |
      ACE11_binary == 1
    ),

    # Emotional/behavioral problems (MEDB10ScrQ5: 1=Yes, 2=No)
    emot_behav_prob = dplyr::case_when(
      MEDB10ScrQ5 == 1 ~ 1,
      MEDB10ScrQ5 == 2 ~ 0,
      TRUE ~ NA_real_
    ),

    # Excellent health (K2Q01: 1=Excellent, 2-5=Other)
    excellent_health = dplyr::case_when(
      K2Q01 == 1 ~ 1,  # Excellent
      K2Q01 %in% 2:5 ~ 0,  # Good, Fair, Poor
      TRUE ~ NA_real_
    ),

    # Age factor
    age_factor = factor(SC_AGE_YEARS)
  )

cat("    Outcome variables created:\n")
cat("      - ace_1plus\n")
cat("      - emot_behav_prob\n")
cat("      - excellent_health\n")
cat("      - age_factor\n\n")

cat("========================================\n")
cat("Section 4.5 Complete: Outcome variables created\n")
cat("Next: ACE exposure model estimation with bootstrap\n")
cat("========================================\n\n")

# ========================================
# SECTION 5: ACE EXPOSURE MODEL WITH BOOTSTRAP
# ========================================
cat("[5] Estimating ACE Exposure (1+ ACEs) with bootstrap replicates...\n")

# Filter to complete cases for ACE outcome (should have none after imputation)
ace_design <- subset(boot_design, !is.na(ace_1plus))
cat("    Sample size for ACE model:", nrow(ace_design$variables), "\n")
cat("    Number of replicates:", ncol(ace_design$repweights), "\n\n")

# Generate bootstrap replicates using shared bootstrap design
cat("    [5.1] Generating bootstrap replicates for ACE model...\n")

# Prediction data: year 2023 for ages 0-5
pred_data_ace <- data.frame(
  age_factor = factor(0:5, levels = levels(ace_design$variables$age_factor)),
  survey_year = 2023
)

# Call bootstrap helper function
boot_result_ace <- generate_nsch_bootstrap(
  boot_design = ace_design,
  formula = ace_1plus ~ age_factor + survey_year,
  pred_data = pred_data_ace,
  family = quasibinomial()
)

# Extract point estimates
ace_estimates <- data.frame(
  age = 0:5,
  estimand = "Child ACE Exposure (1+ ACEs)",
  estimate = boot_result_ace$point_estimates
)

cat("\n    Point estimates (year 2023):\n")
for (i in 1:6) {
  cat("      Age", i-1, ":", round(ace_estimates$estimate[i], 3), "\n")
}
cat("\n")

# Format and save bootstrap replicates
cat("    [5.2] Formatting bootstrap replicates...\n")
ace_boot <- format_bootstrap_results(
  boot_result = boot_result_ace,
  ages = 0:5,
  estimand_name = "ace_exposure"
)

cat("      Bootstrap rows:", nrow(ace_boot), "(6 ages ×", boot_result_ace$n_boot, "replicates)\n")

# Save bootstrap replicates
saveRDS(ace_boot, "data/raking/ne25/ace_exposure_boot.rds")
cat("      Saved to: data/raking/ne25/ace_exposure_boot.rds\n\n")

cat("========================================\n")
cat("Section 5 Complete: ACE model with bootstrap\n")
cat("Next: Emotional/behavioral model\n")
cat("========================================\n\n")

# ========================================
# SECTION 6: EMOTIONAL/BEHAVIORAL MODEL WITH BOOTSTRAP (ages 3-5 only)
# ========================================
cat("[6] Estimating Emotional/Behavioral Problems (ages 3-5) with bootstrap...\n")

# Filter to ages 3-5 with complete outcome data
emot_design <- subset(boot_design, !is.na(emot_behav_prob) & SC_AGE_YEARS >= 3)

# Rebuild age_factor with only 3-5 levels
emot_design$variables$age_factor <- factor(emot_design$variables$SC_AGE_YEARS)

cat("    Sample size for emotional/behavioral model (ages 3-5):", nrow(emot_design$variables), "\n")
cat("    Number of replicates:", ncol(emot_design$repweights), "\n\n")

# Generate bootstrap replicates using shared bootstrap design
cat("    [6.1] Generating bootstrap replicates for emotional/behavioral model...\n")

# Prediction data: year 2023 for ages 3-5 only
pred_data_emot <- data.frame(
  age_factor = factor(3:5),
  survey_year = 2023
)

# Call bootstrap helper function
boot_result_emot <- generate_nsch_bootstrap(
  boot_design = emot_design,
  formula = emot_behav_prob ~ age_factor + survey_year,
  pred_data = pred_data_emot,
  family = quasibinomial()
)

# Extract point estimates and add NA for ages 0-2
emot_estimates <- data.frame(
  age = 0:5,
  estimand = "Emotional/Behavioral Problems",
  estimate = c(rep(NA_real_, 3), boot_result_emot$point_estimates)  # NA for ages 0-2
)

cat("\n    Point estimates (year 2023):\n")
for (i in 1:6) {
  if (is.na(emot_estimates$estimate[i])) {
    cat("      Age", i-1, ": NA (not measured for ages 0-2)\n")
  } else {
    cat("      Age", i-1, ":", round(emot_estimates$estimate[i], 3), "\n")
  }
}
cat("\n")

# Format bootstrap replicates (with NA for ages 0-2)
cat("    [6.2] Formatting bootstrap replicates...\n")

# Create bootstrap data frame with NA for ages 0-2
n_boot <- boot_result_emot$n_boot
emot_boot_ages35 <- format_bootstrap_results(
  boot_result = boot_result_emot,
  ages = 3:5,
  estimand_name = "emotional_behavioral"
)

# Add NA rows for ages 0-2
emot_boot_ages02 <- data.frame(
  age = rep(0:2, times = n_boot),
  estimand = "emotional_behavioral",
  replicate = rep(1:n_boot, each = 3),
  estimate = NA_real_
)

# Combine
emot_boot <- dplyr::bind_rows(emot_boot_ages02, emot_boot_ages35) %>%
  dplyr::arrange(replicate, age)

cat("      Bootstrap rows:", nrow(emot_boot), "(6 ages ×", n_boot, "replicates, NA for ages 0-2)\n")

# Save bootstrap replicates
saveRDS(emot_boot, "data/raking/ne25/emotional_behavioral_boot.rds")
cat("      Saved to: data/raking/ne25/emotional_behavioral_boot.rds\n\n")

cat("========================================\n")
cat("Section 6 Complete: Emotional/behavioral model with bootstrap\n")
cat("Next: Excellent health model\n")
cat("========================================\n\n")

# ========================================
# SECTION 7: EXCELLENT HEALTH MODEL WITH BOOTSTRAP (ages 0-5)
# ========================================
cat("[7] Estimating Excellent Health Rating (ages 0-5) with bootstrap...\n")

# Filter to complete cases for health outcome
health_design <- subset(boot_design, !is.na(excellent_health))
cat("    Sample size for health model:", nrow(health_design$variables), "\n")
cat("    Number of replicates:", ncol(health_design$repweights), "\n\n")

# Generate bootstrap replicates using shared bootstrap design
cat("    [7.1] Generating bootstrap replicates for excellent health model...\n")

# Prediction data: year 2023 for ages 0-5
pred_data_health <- data.frame(
  age_factor = factor(0:5, levels = levels(health_design$variables$age_factor)),
  survey_year = 2023
)

# Call bootstrap helper function
boot_result_health <- generate_nsch_bootstrap(
  boot_design = health_design,
  formula = excellent_health ~ age_factor + survey_year,
  pred_data = pred_data_health,
  family = quasibinomial()
)

# Extract point estimates
health_estimates <- data.frame(
  age = 0:5,
  estimand = "Excellent Health Rating",
  estimate = boot_result_health$point_estimates
)

cat("\n    Point estimates (year 2023):\n")
for (i in 1:6) {
  cat("      Age", i-1, ":", round(health_estimates$estimate[i], 3), "\n")
}
cat("\n")

# Format and save bootstrap replicates
cat("    [7.2] Formatting bootstrap replicates...\n")
health_boot <- format_bootstrap_results(
  boot_result = boot_result_health,
  ages = 0:5,
  estimand_name = "excellent_health"
)

cat("      Bootstrap rows:", nrow(health_boot), "(6 ages ×", boot_result_health$n_boot, "replicates)\n")

# Save bootstrap replicates
saveRDS(health_boot, "data/raking/ne25/excellent_health_boot.rds")
cat("      Saved to: data/raking/ne25/excellent_health_boot.rds\n\n")

cat("========================================\n")
cat("Section 7 Complete: Excellent health model with bootstrap\n")
cat("Next: Combining and saving results\n")
cat("========================================\n\n")

# ========================================
# SECTION 8: COMBINE AND SAVE RESULTS
# ========================================
cat("[8] Combining all NSCH estimates...\n")

nsch_estimates <- dplyr::bind_rows(
  ace_estimates,
  emot_estimates,
  health_estimates
)

cat("    Total rows:", nrow(nsch_estimates), "\n")
cat("    Estimands:", length(unique(nsch_estimates$estimand)), "\n")
cat("    Ages per estimand: 6 (0-5)\n\n")

# Verify structure
cat("    Estimate ranges:\n")
for (est in unique(nsch_estimates$estimand)) {
  est_data <- nsch_estimates$estimate[nsch_estimates$estimand == est]
  est_data <- est_data[!is.na(est_data)]  # Remove NAs for range
  cat("      ", est, ":", round(min(est_data), 3), "-", round(max(est_data), 3), "\n")
}
cat("\n")

# Save results
cat("[8.2] Saving NSCH estimates...\n")
saveRDS(nsch_estimates, "data/raking/ne25/nsch_estimates_raw.rds")
cat("    Saved to: data/raking/ne25/nsch_estimates_raw.rds\n\n")

cat("========================================\n")
cat("NSCH OUTCOMES ESTIMATION COMPLETE (with Bootstrap)\n")
cat("========================================\n\n")

cat("Summary of changes from original script:\n")
cat("  - Multi-year data pooling (2020-2023) instead of single year\n")
cat("  - MICE single imputation for ACE indicators (m=1, CART)\n")
cat("  - Proper survey design (svydesign) instead of glmer\n")
cat("  - Temporal modeling (age + year + age:year)\n")
cat("  - Model selection via F-test for interactions\n")
cat("  - Predictions at year 2023\n")
cat("  - Bootstrap replicate weights (shared NSCH design)\n\n")

cat("Bootstrap files saved:\n")
cat("  - ace_exposure_boot.rds (24 rows: 6 ages × 4 replicates)\n")
cat("  - emotional_behavioral_boot.rds (24 rows: 6 ages × 4 replicates, NA ages 0-2)\n")
cat("  - excellent_health_boot.rds (24 rows: 6 ages × 4 replicates)\n\n")

# Display final results
print(nsch_estimates)

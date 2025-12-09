# Phase 4a, Task 4: Calibrate NSCH to Nebraska Demographics
# Uses KL divergence minimization via Stan to reweight NSCH (Nebraska + border states)
# to match both ACS Nebraska marginal means AND covariance structure
# Output: Calibrated NSCH weights (linear fixed effects model)

library(dplyr)
library(duckdb)
library(arrow)

cat("\n========================================\n")
cat("Task 4a.4: Calibrate NSCH to Nebraska\n")
cat("========================================\n\n")

# Source utilities
cat("[1] Loading utilities...\n")
source("scripts/raking/ne25/utils/harmonize_race_ethnicity.R")
source("scripts/raking/ne25/utils/harmonize_education.R")
source("scripts/raking/ne25/utils/harmonize_marital_status.R")
source("scripts/raking/ne25/utils/harmonize_poverty.R")
source("scripts/raking/ne25/utils/harmonize_principal_city.R")
source("scripts/raking/ne25/utils/weighted_covariance.R")
source("scripts/raking/ne25/utils/validate_raw_inputs.R")
source("scripts/raking/ne25/utils/calibrate_weights_cmdstan.R")
source("scripts/raking/ne25/utils/score_rasch_outcomes.R")
cat("    ✓ Utilities loaded\n\n")

# ============================================================================
# Step 1: Load ACS Nebraska data to create targets
# ============================================================================

cat("[2] Loading ACS Nebraska data for targets...\n")

acs_nc <- arrow::read_feather("data/raking/ne25/acs_north_central.feather")
acs_ne <- acs_nc %>% dplyr::filter(STATEFIP == 31)

cat("    Loaded:", nrow(acs_ne), "Nebraska observations from ACS\n\n")

# ============================================================================
# Step 2: Create harmonized variables for ACS Nebraska
# ============================================================================

cat("[3] Creating harmonized variables for ACS Nebraska...\n")

acs_ne <- acs_ne %>%
  dplyr::mutate(
    male = as.integer(SEX == 1),
    age = AGE,
    race_harmonized = harmonize_acs_race(RACE, HISPAN)
  )

race_dummies <- create_race_dummies(acs_ne$race_harmonized)
acs_ne <- acs_ne %>%
  dplyr::mutate(
    white_nh = race_dummies$white_nh,
    black = race_dummies$black,
    hispanic = race_dummies$hispanic,
    educ_years = harmonize_acs_education(EDUC_MOM),
    poverty_ratio = harmonize_acs_poverty(POVERTY, cap_at_400 = TRUE),  # Cap at 400 to match NSCH
    principal_city = harmonize_acs_principal_city(METRO)
  )

cat("    ✓ Harmonized variables created\n\n")

# ============================================================================
# Step 3: Compute ACS Nebraska target mean and covariance
# ============================================================================

cat("[4] Computing target moments from ACS Nebraska...\n")

# Block 1 demographics only (child outcomes not used for calibration)
calibration_vars <- c("male", "age", "white_nh", "black", "hispanic",
                      "educ_years", "poverty_ratio", "principal_city")

# Compute weighted mean vector
target_mean_list <- list()
for (var in calibration_vars) {
  target_mean_list[[var]] <- weighted.mean(acs_ne[[var]], acs_ne$PERWT, na.rm = TRUE)
}
target_mean <- as.vector(unlist(target_mean_list))

cat("    Target marginals from ACS Nebraska (weighted):\n")
for (i in seq_along(calibration_vars)) {
  cat(sprintf("      %s: %.4f\n", calibration_vars[i], target_mean[i]))
}
cat("\n")

# Compute weighted covariance matrix
X_acs <- as.matrix(acs_ne[, calibration_vars])
w_acs <- acs_ne$PERWT

# Weighted means
mu_acs <- numeric(length(calibration_vars))
for (k in seq_along(calibration_vars)) {
  valid_idx <- !is.na(X_acs[, k])
  mu_acs[k] <- sum(w_acs[valid_idx] * X_acs[valid_idx, k]) / sum(w_acs[valid_idx])
}

# Weighted covariance
target_cov <- matrix(0, nrow = length(calibration_vars), ncol = length(calibration_vars))
for (i in seq_along(calibration_vars)) {
  for (j in seq_along(calibration_vars)) {
    valid_idx <- !is.na(X_acs[, i]) & !is.na(X_acs[, j])
    dev_i <- X_acs[valid_idx, i] - mu_acs[i]
    dev_j <- X_acs[valid_idx, j] - mu_acs[j]
    target_cov[i, j] <- sum(w_acs[valid_idx] * dev_i * dev_j) / sum(w_acs[valid_idx])
  }
}

cat("    Target covariance matrix computed (", length(calibration_vars), "x",
    length(calibration_vars), ")\n\n")

# ============================================================================
# Step 4: Load NSCH Nebraska + Border States data (2021-2022 pooled)
# ============================================================================

cat("[5] Loading NSCH Nebraska + border states data (2021-2022 pooled)...\n")

# Connect to database
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = "data/duckdb/kidsights_local.duckdb", read_only = TRUE)

# Check available NSCH tables
tables <- DBI::dbListTables(con)
nsch_tables <- grep("^nsch_", tables, value = TRUE)
cat("    Available NSCH tables:", paste(nsch_tables, collapse = ", "), "\n")

# Load 2021 and 2022 data
nsch_2021 <- DBI::dbReadTable(con, "nsch_2021")
nsch_2022 <- DBI::dbReadTable(con, "nsch_2022")

DBI::dbDisconnect(con, shutdown = TRUE)

cat("    Loaded 2021 :", nrow(nsch_2021), "records\n")
cat("    Loaded 2022 :", nrow(nsch_2022), "records\n")

# Filter to Nebraska + bordering states, age 0-5, and combine
# Nebraska (31) + borders: SD=46, IA=19, MO=29, KS=20, CO=08, WY=56
nebraska_border_fips <- c(8, 19, 20, 29, 31, 46, 56)  # CO, IA, KS, MO, NE, SD, WY

# Create unified race4 variable before combining years
nsch_2021_nc <- nsch_2021 %>%
  dplyr::filter(FIPSST %in% nebraska_border_fips & SC_AGE_YEARS >= 0 & SC_AGE_YEARS <= 5) %>%
  dplyr::mutate(
    year = 2021,
    race4 = race4_21  # Rename to unified variable
  )

nsch_2022_nc <- nsch_2022 %>%
  dplyr::filter(FIPSST %in% nebraska_border_fips & SC_AGE_YEARS >= 0 & SC_AGE_YEARS <= 5) %>%
  dplyr::mutate(
    year = 2022,
    race4 = race4_22  # Rename to unified variable
  )

nsch_nc <- dplyr::bind_rows(nsch_2021_nc, nsch_2022_nc)

cat("\n    Total Nebraska + border states records:", nrow(nsch_nc), "\n")
cat("    Nebraska records:", sum(nsch_nc$FIPSST == 31), "\n")
cat("    Border states: CO, IA, KS, MO, SD, WY\n")
cat("    Years:", paste(sort(unique(nsch_nc$year)), collapse = ", "), "\n\n")

# ============================================================================
# Step 3: Pre-harmonization input validation
# ============================================================================

cat("[6] Running pre-harmonization input validation...\n")
nsch_validation <- validate_nsch_inputs(nsch_nc)

if (!nsch_validation$valid) {
  cat("\nWARNING: NSCH input validation detected issues\n")
  cat("Continuing with analysis, but review issues above\n\n")
}

# ============================================================================
# Step 4: Create harmonized variables for NSCH
# ============================================================================

cat("[7] Creating harmonized demographic variables for NSCH...\n")

# Sex: male indicator
nsch_nc$male <- as.integer(nsch_nc$SC_SEX == 1)

# Age: continuous (0-5 years)
nsch_nc$age <- nsch_nc$SC_AGE_YEARS

# Race/ethnicity: Use unified race4 variable (created during year combination)
nsch_nc$race_harmonized <- harmonize_nsch_race(nsch_nc$race4)
race_dummies_nsch <- create_race_dummies(nsch_nc$race_harmonized)
nsch_nc$white_nh <- race_dummies_nsch$white_nh
nsch_nc$black <- race_dummies_nsch$black
nsch_nc$hispanic <- race_dummies_nsch$hispanic

# Education: Use A1_GRADE (responding adult's education)
# Filter to female respondents (proxy for maternal education)
# A1_SEX: 1=Male, 2=Female, 99=Missing
if ("A1_GRADE" %in% names(nsch_nc) && "A1_SEX" %in% names(nsch_nc)) {
  nsch_nc$educ_years <- dplyr::if_else(
    nsch_nc$A1_SEX == 2,  # Female respondent
    harmonize_nsch_education_numeric(nsch_nc$A1_GRADE),
    NA_real_
  )
  cat("    ✓ Created educ_years from A1_GRADE (female respondents only)\n")
} else {
  cat("    WARNING: A1_GRADE or A1_SEX not available\n")
  nsch_nc$educ_years <- NA_real_
}

# Poverty: Use FPL_I1 variable (continuous 50-400, already in % FPL)
poverty_var <- ifelse("FPL_I1" %in% names(nsch_nc), "FPL_I1",
                      ifelse("POVLEV4_1920" %in% names(nsch_nc), "POVLEV4_1920", NA))

if (!is.na(poverty_var)) {
  # FPL_I1 is already in poverty ratio format (50-400 = 50%-400% FPL)
  nsch_nc$poverty_ratio <- nsch_nc[[poverty_var]]
} else {
  stop("ERROR: No poverty variable found in NSCH data")
}

# Principal city: Harmonize from MPC_YN
if ("MPC_YN" %in% names(nsch_nc)) {
  nsch_nc$principal_city <- harmonize_nsch_principal_city(nsch_nc$MPC_YN)
  cat("    ✓ Created principal_city indicator from MPC_YN\n")
} else {
  cat("    WARNING: No MPC_YN variable found\n")
  nsch_nc$principal_city <- NA_integer_
}

cat("    ✓ Created", length(calibration_vars) + 1, "Block 1 demographic variables\n\n")

# ============================================================================
# Step 5: Filter to complete cases
# ============================================================================

cat("[8] Checking for missing values in harmonized variables...\n")

missing_check <- data.frame(
  variable = calibration_vars,
  n_missing = sapply(calibration_vars, function(v) sum(is.na(nsch_nc[[v]]))),
  pct_missing = sapply(calibration_vars, function(v) mean(is.na(nsch_nc[[v]])) * 100)
)
rownames(missing_check) <- missing_check$variable
print(missing_check)

# Filter to Block 1 complete cases (demographics)
nsch_complete <- nsch_nc %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(poverty_ratio) &
    !is.na(principal_city) & !is.na(FWC) & FWC > 0
  )

cat(sprintf("\n    Records with complete data: %d / %d (%.1f%%)\n\n",
            nrow(nsch_complete), nrow(nsch_nc),
            nrow(nsch_complete) / nrow(nsch_nc) * 100))

if (nrow(nsch_complete) == 0) {
  stop("ERROR: No complete cases after harmonization. Check variable mappings.")
}

# ============================================================================
# Step 6: Run calibration (linear fixed effects model)
# ============================================================================

cat("[9] Running calibration (KL divergence minimization)...\n\n")

tryCatch({
  calib_result <- calibrate_weights_stan(
    data = nsch_complete,
    target_mean = target_mean,
    target_cov = target_cov,
    calibration_vars = calibration_vars
  )
}, error = function(e) {
  cat(sprintf("[ERROR] Calibration failed:\n%s\n", e$message))
  stop(e)
})

# ============================================================================
# Step 6b: Add Block 3 child outcome variables (NSCH-only)
# ============================================================================

cat("[9b] Adding Block 3 child outcome variables...\n")

# Child ACE EAPsum: Rasch model from 10 child ACE binary indicators
# ACE1, ACE3-ACE11 (ACE2 not measured in NSCH)
ace_cols <- c("ACE1", "ACE3", "ACE4", "ACE5", "ACE6", "ACE7", "ACE8", "ACE9", "ACE10", "ACE11")

# Check if ACE variables exist in calibrated data
ace_available <- all(ace_cols %in% names(calib_result$data))

if (ace_available) {
  # Create binary indicators from ACE responses (1=Yes, 2=No, 95/99=Missing)
  ace_binary_data <- calib_result$data %>%
    dplyr::select(dplyr::all_of(ace_cols)) %>%
    dplyr::mutate(dplyr::across(dplyr::everything(), ~dplyr::case_when(
      . == 1 ~ 1L,         # Yes to ACE
      . == 2 ~ 0L,         # No to ACE
      . >= 90 ~ NA_integer_,  # Missing codes
      TRUE ~ NA_integer_
    )))

  # Count total ACEs (row sums)
  ace_total <- rowSums(ace_binary_data, na.rm = FALSE)  # NA if any item missing

  # Create two binary indicators:
  # child_ace_1: exactly 1 ACE (vs 0 or 2+)
  # child_ace_2plus: 2 or more ACEs (vs 0 or 1)
  calib_result$data$child_ace_1 <- dplyr::case_when(
    is.na(ace_total) ~ NA_integer_,
    ace_total == 1 ~ 1L,
    TRUE ~ 0L
  )

  calib_result$data$child_ace_2plus <- dplyr::case_when(
    is.na(ace_total) ~ NA_integer_,
    ace_total >= 2 ~ 1L,
    TRUE ~ 0L
  )

  n_ace_complete <- sum(!is.na(ace_total))
  cat(sprintf("    ✓ Child ACE indicators created: %d complete (%.1f%%)\n",
              n_ace_complete, n_ace_complete / nrow(calib_result$data) * 100))
  cat(sprintf("      child_ace_1 (exactly 1): %.1f%%\n",
              mean(calib_result$data$child_ace_1, na.rm = TRUE) * 100))
  cat(sprintf("      child_ace_2plus (2+): %.1f%%\n",
              mean(calib_result$data$child_ace_2plus, na.rm = TRUE) * 100))
} else {
  cat("    WARNING: ACE variables not available\n")
  calib_result$data$child_ace_1 <- NA_integer_
  calib_result$data$child_ace_2plus <- NA_integer_
}

# Excellent health: Binary indicator from K2Q01 (overall health rating)
# K2Q01: 1=Excellent, 2=Very good, 3=Good, 4=Fair, 5=Poor, 95/99=Missing
if ("K2Q01" %in% names(calib_result$data)) {
  calib_result$data$excellent_health <- dplyr::case_when(
    calib_result$data$K2Q01 == 1 ~ 1L,  # Excellent health
    calib_result$data$K2Q01 %in% 2:5 ~ 0L,  # Not excellent
    calib_result$data$K2Q01 >= 90 ~ NA_integer_,  # Missing
    TRUE ~ NA_integer_
  )

  n_excellent <- sum(calib_result$data$excellent_health == 1, na.rm = TRUE)
  cat(sprintf("    ✓ Excellent health indicator created: %d excellent (%.1f%%)\n\n",
              n_excellent, n_excellent / nrow(calib_result$data) * 100))
} else {
  cat("    WARNING: K2Q01 (health rating) not available\n\n")
  calib_result$data$excellent_health <- NA_integer_
}

# ============================================================================
# Step 7: Save results
# ============================================================================

cat("[10] Saving calibrated NSCH data...\n")

# Include Block 3 variables in saved data
nsch_calibrated <- calib_result$data %>%
  dplyr::select(dplyr::all_of(names(nsch_complete)), calibrated_weight,
                child_ace_1, child_ace_2plus, excellent_health)

saveRDS(nsch_calibrated, "data/raking/ne25/nsch_calibrated.rds")
cat("    ✓ Saved to: data/raking/ne25/nsch_calibrated.rds\n")
cat("    Dimensions:", nrow(nsch_calibrated), "rows x", ncol(nsch_calibrated), "columns\n\n")

# Save diagnostics
calib_diagnostics <- list(
  n_observations = nrow(nsch_calibrated),
  n_parameters = 1 + length(calibration_vars),  # alpha + beta
  converged = calib_result$converged,
  alpha = calib_result$alpha,
  beta = calib_result$beta,
  beta_names = calib_result$beta_names,
  final_marginals = calib_result$final_marginals,
  effective_n = calib_result$effective_n,
  efficiency_pct = calib_result$efficiency_pct,
  weight_ratio = calib_result$weight_ratio,
  log_prob = calib_result$log_prob,
  target_marginals = as.list(target_mean),
  target_covariance = target_cov
)

names(calib_diagnostics$target_marginals) <- calibration_vars

saveRDS(calib_diagnostics, "data/raking/ne25/nsch_calibration_diagnostics.rds")
cat("    ✓ Diagnostics saved to: data/raking/ne25/nsch_calibration_diagnostics.rds\n\n")

# ============================================================================
# Step 8: Compute NSCH moments with calibrated weights
# ============================================================================

cat("[11] Computing NSCH moments with calibrated weights...\n")

# Extract design matrix and weights
X_nsch <- as.matrix(nsch_calibrated[, calibration_vars])
w_nsch <- nsch_calibrated$calibrated_weight

nsch_moments <- compute_weighted_moments(X = X_nsch, weights = w_nsch)

saveRDS(nsch_moments, "data/raking/ne25/nsch_moments.rds")
cat("    ✓ Saved to: data/raking/ne25/nsch_moments.rds\n\n")

cat("    NSCH moments summary:\n")
cat("      N:", nsch_moments$n, "\n")
cat("      N_eff:", round(nsch_moments$n_eff, 1), "\n")
cat("      Efficiency:", round(nsch_moments$n_eff / nsch_moments$n * 100, 1), "%\n\n")

# ============================================================================
# Summary
# ============================================================================

cat("========================================\n")
cat("Task 4a.4 Complete: NSCH Calibrated\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - Complete records:", nrow(nsch_calibrated), "\n")
cat("  - Effective N:", round(calib_result$effective_n, 1), "\n")
cat("  - Efficiency:", round(calib_result$efficiency_pct, 1), "%\n")
cat("  - Convergence:", ifelse(calib_result$converged, "YES", "NO"), "\n")
cat("  - Max marginal % error:", round(max(calib_result$final_marginals$Pct_Diff), 2), "%\n\n")

cat("Ready for Phase 4b: Create design matrices from calibrated data\n\n")

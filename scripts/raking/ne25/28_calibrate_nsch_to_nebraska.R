# Phase 4a, Task 4: Calibrate NSCH to Nebraska Demographics
# Uses KL divergence minimization via Stan to reweight NSCH North Central
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
source("scripts/raking/ne25/utils/weighted_covariance.R")
source("scripts/raking/ne25/utils/validate_raw_inputs.R")
source("scripts/raking/ne25/utils/calibrate_weights_cmdstan.R")
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
    poverty_ratio = harmonize_acs_poverty(POVERTY, cap_at_400 = TRUE)  # Cap at 400 to match NSCH
  )

cat("    ✓ Harmonized variables created\n\n")

# ============================================================================
# Step 3: Compute ACS Nebraska target mean and covariance
# ============================================================================

cat("[4] Computing target moments from ACS Nebraska...\n")

calibration_vars <- c("male", "age", "white_nh", "black", "hispanic",
                      "educ_years", "poverty_ratio")

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
# Step 4: Load NSCH North Central data (2021-2022 pooled)
# ============================================================================

cat("[5] Loading NSCH North Central data (2021-2022 pooled)...\n")

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

# Filter to North Central region, age 0-5, and combine
# North Central FIPS codes: IA=19, KS=20, MN=27, MO=29, NE=31, ND=38, SD=46
north_central_fips <- c(19, 20, 27, 29, 31, 38, 46)

nsch_2021_nc <- nsch_2021 %>%
  dplyr::filter(FIPSST %in% north_central_fips & SC_AGE_YEARS >= 0 & SC_AGE_YEARS <= 5) %>%
  dplyr::mutate(year = 2021)

nsch_2022_nc <- nsch_2022 %>%
  dplyr::filter(FIPSST %in% north_central_fips & SC_AGE_YEARS >= 0 & SC_AGE_YEARS <= 5) %>%
  dplyr::mutate(year = 2022)

nsch_nc <- dplyr::bind_rows(nsch_2021_nc, nsch_2022_nc)

cat("\n    Total North Central records:", nrow(nsch_nc), "\n")
cat("    Nebraska records:", sum(nsch_nc$FIPSST == 31), "\n")
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

# Race/ethnicity: Use race4 variable (available in both years)
race4_var <- ifelse("race4_21" %in% names(nsch_nc), "race4_21",
                    ifelse("race4" %in% names(nsch_nc), "race4", NA))

if (!is.na(race4_var)) {
  nsch_nc$race_harmonized <- harmonize_nsch_race(nsch_nc[[race4_var]])
  race_dummies_nsch <- create_race_dummies(nsch_nc$race_harmonized)
  nsch_nc$white_nh <- race_dummies_nsch$white_nh
  nsch_nc$black <- race_dummies_nsch$black
  nsch_nc$hispanic <- race_dummies_nsch$hispanic
} else {
  stop("ERROR: No race4 variable found in NSCH data")
}

# Education: Not available in NSCH - set to median from ACS
cat("    WARNING: No parent education variable in NSCH\n")
cat("    Setting educ_years to ACS target median:", round(target_mean[6], 2), "\n")
nsch_nc$educ_years <- target_mean[6]  # Use ACS target as constant

# Poverty: Use FPL_I1 variable (continuous 50-400, already in % FPL)
poverty_var <- ifelse("FPL_I1" %in% names(nsch_nc), "FPL_I1",
                      ifelse("POVLEV4_1920" %in% names(nsch_nc), "POVLEV4_1920", NA))

if (!is.na(poverty_var)) {
  # FPL_I1 is already in poverty ratio format (50-400 = 50%-400% FPL)
  nsch_nc$poverty_ratio <- nsch_nc[[poverty_var]]
} else {
  stop("ERROR: No poverty variable found in NSCH data")
}

cat("    ✓ Created", length(calibration_vars), "harmonized variables\n\n")

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

# Filter to complete cases
nsch_complete <- nsch_nc %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(poverty_ratio) &
    !is.na(FWC) & FWC > 0
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
# Step 7: Save results
# ============================================================================

cat("[10] Saving calibrated NSCH data...\n")

nsch_calibrated <- calib_result$data %>%
  dplyr::select(dplyr::all_of(names(nsch_complete)), calibrated_weight)

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

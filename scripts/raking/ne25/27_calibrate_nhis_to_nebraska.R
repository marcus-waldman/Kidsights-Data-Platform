# Phase 4a, Task 3: Calibrate NHIS to Nebraska Demographics
# Uses KL divergence minimization via Stan to reweight NHIS North Central
# to match both ACS Nebraska marginal means AND covariance structure
# Output: Calibrated NHIS weights (linear fixed effects model)

library(dplyr)
library(arrow)

cat("\n========================================\n")
cat("Task 4a.3: Calibrate NHIS to Nebraska\n")
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
source("scripts/raking/ne25/utils/score_mental_health.R")
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
    married = harmonize_acs_marital(MARST_HEAD),
    poverty_ratio = harmonize_acs_poverty(POVERTY)
  )

cat("    ✓ Harmonized variables created\n\n")

# ============================================================================
# Step 3: Compute ACS Nebraska target mean and covariance
# ============================================================================

cat("[4] Computing target moments from ACS Nebraska...\n")

# Block 1 demographics only (mental health and ACEs not used for calibration)
calibration_vars <- c("male", "age", "white_nh", "black", "hispanic",
                      "educ_years", "married", "poverty_ratio")

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
# Step 4: Load NHIS North Central data
# ============================================================================

cat("[5] Loading NHIS North Central data...\n")

if (!file.exists("data/raking/ne25/nhis_parent_child_linked.rds")) {
  stop("NHIS parent-child data not found. Run 12_filter_nhis_parents.R first.")
}

nhis <- readRDS("data/raking/ne25/nhis_parent_child_linked.rds")
cat("    Loaded:", nrow(nhis), "parent-child pairs\n")
cat("    Years:", paste(sort(unique(nhis$YEAR)), collapse = ", "), "\n\n")

# ============================================================================
# Step 5: Pre-harmonization input validation
# ============================================================================

cat("[6] Running pre-harmonization input validation...\n")
nhis_validation <- validate_nhis_inputs(nhis)

if (!nhis_validation$valid) {
  cat("\nWARNING: NHIS input validation detected issues\n")
  cat("Continuing with analysis, but review issues above\n\n")
}

# ============================================================================
# Step 6: Create harmonized variables for NHIS
# ============================================================================

cat("[7] Creating harmonized demographic variables for NHIS...\n")

# Sex: male indicator (1=Male in NHIS)
sex_col <- if ("SEX_child" %in% names(nhis)) "SEX_child" else "SEX"
nhis$male <- as.integer(nhis[[sex_col]] == 1)

# Age: continuous (child age 0-5)
age_col <- if ("AGE_child" %in% names(nhis)) "AGE_child" else "AGE"
nhis$age <- nhis[[age_col]]

# Race/ethnicity: Use parent's race if available
race_var <- ifelse("RACENEW_parent" %in% names(nhis), "RACENEW_parent", "RACENEW")
hisp_var <- ifelse("HISPETH_parent" %in% names(nhis), "HISPETH_parent",
                   ifelse("HISPETH" %in% names(nhis), "HISPETH",
                          ifelse("HISPAN_parent" %in% names(nhis), "HISPAN_parent", "HISPAN")))

nhis$race_harmonized <- harmonize_nhis_race(nhis[[race_var]], nhis[[hisp_var]])

race_dummies_nhis <- create_race_dummies(nhis$race_harmonized)
nhis$white_nh <- race_dummies_nhis$white_nh
nhis$black <- race_dummies_nhis$black
nhis$hispanic <- race_dummies_nhis$hispanic

# Education: harmonize from EDUCPARENT
educ_var <- ifelse("EDUCPARENT" %in% names(nhis), "EDUCPARENT",
                   ifelse("EDUC_parent" %in% names(nhis), "EDUC_parent", NA))

if (!is.na(educ_var)) {
  nhis$educ_years <- harmonize_nhis_education(nhis[[educ_var]])
} else {
  cat("    WARNING: No parent education variable found\n")
  nhis$educ_years <- NA_real_
}

# Poverty: harmonize from POVERTY
poverty_var <- ifelse("POVERTY" %in% names(nhis), "POVERTY",
                      ifelse("POVERTY_parent" %in% names(nhis), "POVERTY_parent", NA))

if (!is.na(poverty_var)) {
  nhis$poverty_ratio <- harmonize_nhis_poverty(nhis[[poverty_var]])
} else {
  cat("    WARNING: No poverty variable found\n")
  nhis$poverty_ratio <- NA_real_
}

# Marital status: harmonize from PAR1MARST
if ("PAR1MARST" %in% names(nhis)) {
  nhis$married <- harmonize_nhis_marital(nhis$PAR1MARST)
  cat("    ✓ Created married indicator from PAR1MARST\n")
} else {
  cat("    WARNING: No marital status variable found (PAR1MARST)\n")
  nhis$married <- NA_real_
}

# Principal city: harmonize from METRO
if ("METRO" %in% names(nhis)) {
  nhis$principal_city <- harmonize_nhis_principal_city(nhis$METRO)
  cat("    ✓ Created principal_city indicator from METRO\n")
} else {
  cat("    WARNING: No METRO variable found\n")
  nhis$principal_city <- NA_integer_
}

cat("    ✓ Created", length(calibration_vars) + 1, "Block 1 demographic variables\n\n")

# ============================================================================
# Step 6b: Score mental health variables (Block 2)
# ============================================================================

cat("[7b] Scoring mental health variables (Block 2)...\n")

# PHQ-2 total score (0-6)
# IPUMS variables: PHQINTR, PHQDEP (with or without _parent suffix)
phqintr_var <- ifelse("PHQINTR_parent" %in% names(nhis), "PHQINTR_parent",
                      ifelse("PHQINTR" %in% names(nhis), "PHQINTR", NA))
phqdep_var <- ifelse("PHQDEP_parent" %in% names(nhis), "PHQDEP_parent",
                     ifelse("PHQDEP" %in% names(nhis), "PHQDEP", NA))

if (!is.na(phqintr_var) && !is.na(phqdep_var)) {
  # Recode IPUMS missing codes to NA
  nhis$phqintr_recoded <- recode_nhis_mh_item(nhis[[phqintr_var]])
  nhis$phqdep_recoded <- recode_nhis_mh_item(nhis[[phqdep_var]])

  # Score PHQ-2 total
  nhis$phq2_total <- score_phq2_total(nhis$phqintr_recoded, nhis$phqdep_recoded)

  n_phq2_complete <- sum(!is.na(nhis$phq2_total))
  cat(sprintf("    ✓ PHQ-2 total scored (0-6 scale): %d complete (%.1f%%)\n",
              n_phq2_complete, n_phq2_complete / nrow(nhis) * 100))
} else {
  cat("    WARNING: PHQ-2 items not found (PHQINTR, PHQDEP)\n")
  nhis$phq2_total <- NA_real_
}

# GAD-2 total score (0-6)
gadanx_var <- ifelse("GADANX_parent" %in% names(nhis), "GADANX_parent",
                     ifelse("GADANX" %in% names(nhis), "GADANX", NA))
gadworctrl_var <- ifelse("GADWORCTRL_parent" %in% names(nhis), "GADWORCTRL_parent",
                         ifelse("GADWORCTRL" %in% names(nhis), "GADWORCTRL", NA))

if (!is.na(gadanx_var) && !is.na(gadworctrl_var)) {
  # Recode IPUMS missing codes to NA
  nhis$gadanx_recoded <- recode_nhis_mh_item(nhis[[gadanx_var]])
  nhis$gadworctrl_recoded <- recode_nhis_mh_item(nhis[[gadworctrl_var]])

  # Score GAD-2 total
  nhis$gad2_total <- score_gad2_total(nhis$gadanx_recoded, nhis$gadworctrl_recoded)

  n_gad2_complete <- sum(!is.na(nhis$gad2_total))
  cat(sprintf("    ✓ GAD-2 total scored (0-6 scale): %d complete (%.1f%%)\n\n",
              n_gad2_complete, n_gad2_complete / nrow(nhis) * 100))
} else {
  cat("    WARNING: GAD-2 items not found (GADANX, GADWORCTRL)\n\n")
  nhis$gad2_total <- NA_real_
}

# ============================================================================
# Step 6c: Score parental ACEs (Block 3)
# ============================================================================
# NOTE: Parental ACEs (Block 3) removed from NHIS calibration
# Reason: ACE questions only asked of sampled adults, not all household adults
# Parent-child linkage results in mostly 0/NA values (parents weren't sampled adults)
# NHIS covariance will be limited to Blocks 1-2 (demographics + mental health)
# ============================================================================

cat("[7c] Skipping parental ACEs (not available for linked parents)...\n")
cat("    Block 3 (Parental ACEs) excluded from NHIS calibration\n")
cat("    NHIS will contribute Blocks 1-2 only (demographics + mental health)\n\n")

# ============================================================================
# Step 7: Filter to Block 1 complete cases (demographics only)
# ============================================================================

cat("[8] Checking for missing values in Block 1 (demographics)...\n")

missing_check_block1 <- data.frame(
  variable = calibration_vars,
  n_missing = sapply(calibration_vars, function(v) sum(is.na(nhis[[v]]))),
  pct_missing = sapply(calibration_vars, function(v) mean(is.na(nhis[[v]])) * 100)
)
rownames(missing_check_block1) <- missing_check_block1$variable
print(missing_check_block1)

# Filter to Block 1 complete cases (demographics)
# Mental health and ACEs allowed to have missing values
# Detect SAMPWEIGHT column name (with or without _child suffix)
sampweight_col <- if ("SAMPWEIGHT_child" %in% names(nhis)) "SAMPWEIGHT_child" else "SAMPWEIGHT"

nhis_complete <- nhis %>%
  dplyr::filter(
    !is.na(male) & !is.na(age) & !is.na(white_nh) & !is.na(black) &
    !is.na(hispanic) & !is.na(educ_years) & !is.na(married) & !is.na(poverty_ratio) &
    !is.na(.data[[sampweight_col]]) & .data[[sampweight_col]] > 0
  )

cat(sprintf("\n    Records with complete Block 1 (demographics): %d / %d (%.1f%%)\n",
            nrow(nhis_complete), nrow(nhis),
            nrow(nhis_complete) / nrow(nhis) * 100))

if (nrow(nhis_complete) == 0) {
  stop("ERROR: No complete cases after harmonization. Check variable mappings.")
}

# Report missingness for Block 2 (among Block 1 complete cases)
cat("\n    Block 2 (Mental Health) missingness:\n")
cat(sprintf("      phq2_total: %d / %d (%.1f%%)\n",
            sum(is.na(nhis_complete$phq2_total)), nrow(nhis_complete),
            mean(is.na(nhis_complete$phq2_total)) * 100))
cat(sprintf("      gad2_total: %d / %d (%.1f%%)\n\n",
            sum(is.na(nhis_complete$gad2_total)), nrow(nhis_complete),
            mean(is.na(nhis_complete$gad2_total)) * 100))

# ============================================================================
# Step 8: Run calibration (linear fixed effects model)
# ============================================================================

cat("[9] Running calibration (KL divergence minimization)...\n\n")

tryCatch({
  calib_result <- calibrate_weights_stan(
    data = nhis_complete,
    target_mean = target_mean,
    target_cov = target_cov,
    calibration_vars = calibration_vars
  )
}, error = function(e) {
  cat(sprintf("[ERROR] Calibration failed:\n%s\n", e$message))
  stop(e)
})

# ============================================================================
# Step 9: Save results
# ============================================================================

cat("[10] Saving calibrated NHIS data...\n")

nhis_calibrated <- calib_result$data %>%
  dplyr::select(dplyr::all_of(names(nhis_complete)), calibrated_weight)

saveRDS(nhis_calibrated, "data/raking/ne25/nhis_calibrated.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_calibrated.rds\n")
cat("    Dimensions:", nrow(nhis_calibrated), "rows x", ncol(nhis_calibrated), "columns\n\n")

# Save diagnostics
calib_diagnostics <- list(
  n_observations = nrow(nhis_calibrated),
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
  target_marginals = target_mean_list,
  target_covariance = target_cov
)

saveRDS(calib_diagnostics, "data/raking/ne25/nhis_calibration_diagnostics.rds")
cat("    ✓ Diagnostics saved to: data/raking/ne25/nhis_calibration_diagnostics.rds\n\n")

# ============================================================================
# Step 10: Compute NHIS moments with calibrated weights
# ============================================================================

cat("[11] Computing NHIS moments with calibrated weights...\n")

# Extract design matrix and weights
X_nhis <- as.matrix(nhis_calibrated[, calibration_vars])
w_nhis <- nhis_calibrated$calibrated_weight

nhis_moments <- compute_weighted_moments(X = X_nhis, weights = w_nhis)

saveRDS(nhis_moments, "data/raking/ne25/nhis_moments.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_moments.rds\n\n")

cat("    NHIS moments summary:\n")
cat("      N:", nhis_moments$n, "\n")
cat("      N_eff:", round(nhis_moments$n_eff, 1), "\n")
cat("      Efficiency:", round(nhis_moments$n_eff / nhis_moments$n * 100, 1), "%\n\n")

# ============================================================================
# Summary
# ============================================================================

cat("========================================\n")
cat("Task 4a.3 Complete: NHIS Calibrated\n")
cat("========================================\n\n")

cat("Summary:\n")
cat("  - Complete records:", nrow(nhis_calibrated), "\n")
cat("  - Effective N:", round(calib_result$effective_n, 1), "\n")
cat("  - Efficiency:", round(calib_result$efficiency_pct, 1), "%\n")
cat("  - Convergence:", ifelse(calib_result$converged, "YES", "NO"), "\n")
cat("  - Max marginal % error:", round(max(calib_result$final_marginals$Pct_Diff), 2), "%\n\n")

cat("Ready for Task 4a.4: Calibrate NSCH to Nebraska\n\n")

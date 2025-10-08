# Phase 5, Tasks 5.1-5.3: Load and Consolidate All Estimates
# Combine ACS (150) + NHIS (12) + NSCH (24) = 186 rows
# 31 estimands total (25 ACS + 2 NHIS + 4 NSCH)

library(dplyr)

cat("\n========================================\n")
cat("Phase 5: Consolidate Raking Targets\n")
cat("========================================\n\n")

# 1. Load all estimate files
cat("[1] Loading estimate files...\n")

acs_est <- readRDS("data/raking/ne25/acs_estimates.rds")
phq2_est <- readRDS("data/raking/ne25/phq2_estimate_glm2.rds")
gad2_est <- readRDS("data/raking/ne25/gad2_estimate_glm2.rds")
nsch_main_est <- readRDS("data/raking/ne25/nsch_estimates_raw_glm2.rds")  # 3 outcomes
childcare_est <- readRDS("data/raking/ne25/childcare_2022_estimates.rds")  # 1 outcome

# Combine NHIS mental health outcomes
nhis_est <- dplyr::bind_rows(phq2_est, gad2_est)

# Combine NSCH outcomes
nsch_est <- dplyr::bind_rows(nsch_main_est, childcare_est)

cat("    ACS estimates:", nrow(acs_est), "rows\n")
cat("    NHIS estimates:", nrow(nhis_est), "rows\n")
cat("    NSCH estimates:", nrow(nsch_est), "rows\n")
cat("    Expected total: 186 rows\n\n")

# Verify row counts
if (nrow(acs_est) != 150) {
  stop("ERROR: ACS should have 150 rows (25 estimands × 6 ages), got ", nrow(acs_est))
}
if (nrow(nhis_est) != 12) {
  stop("ERROR: NHIS should have 12 rows (2 estimands × 6 ages), got ", nrow(nhis_est))
}
if (nrow(nsch_est) != 24) {
  stop("ERROR: NSCH should have 24 rows (4 estimands × 6 ages), got ", nrow(nsch_est))
}

cat("    [OK] All row counts verified\n\n")

# 2. Standardize column names and add data source
cat("[2] Standardizing column names and adding data source...\n")

# ACS already has age_years, NHIS and NSCH have age
# Select common columns and add data_source

acs_est <- acs_est %>%
  dplyr::select(age_years, estimand, estimate) %>%
  dplyr::mutate(data_source = "ACS")

nhis_est <- nhis_est %>%
  dplyr::rename(age_years = age) %>%
  dplyr::select(age_years, estimand, estimate) %>%
  dplyr::mutate(data_source = "NHIS")

nsch_est <- nsch_est %>%
  dplyr::rename(age_years = age) %>%
  dplyr::select(age_years, estimand, estimate) %>%
  dplyr::mutate(data_source = "NSCH")

cat("    [OK] Columns standardized, data source added\n\n")

# 3. Combine all estimates
cat("[3] Combining all estimates...\n")

all_estimates <- dplyr::bind_rows(acs_est, nhis_est, nsch_est)

cat("    Total rows:", nrow(all_estimates), "\n")
cat("    Total estimands:", length(unique(all_estimates$estimand)), "\n\n")

# Verify total
if (nrow(all_estimates) != 186) {
  stop("ERROR: Expected 186 total rows, got ", nrow(all_estimates))
}

cat("    [OK] Total row count verified\n\n")

# 4. Add additional required columns
cat("[4] Adding additional columns...\n")

all_estimates <- all_estimates %>%
  dplyr::mutate(
    # Primary key
    target_id = 1:dplyr::n(),

    # Survey identifier
    survey = "ne25",

    # Estimator type (all use survey-weighted GLM now)
    estimator = "Survey GLM",

    # Estimation date
    estimation_date = as.Date(Sys.Date()),

    # Placeholder columns (will populate later)
    se = NA_real_,
    lower_ci = NA_real_,
    upper_ci = NA_real_,
    sample_size = NA_integer_,
    notes = NA_character_
  )

cat("    Columns added:\n")
cat("      - target_id (1-186)\n")
cat("      - survey ('ne25')\n")
cat("      - estimator (GLM/GLMM)\n")
cat("      - estimation_date\n")
cat("      - se, lower_ci, upper_ci (placeholder)\n")
cat("      - sample_size (placeholder)\n")
cat("      - notes (placeholder)\n\n")

# 5. Reorder columns for final structure
cat("[5] Reordering columns...\n")

all_estimates <- all_estimates %>%
  dplyr::select(
    target_id,
    survey,
    age_years,
    estimand,
    data_source,
    estimator,
    estimate,
    se,
    lower_ci,
    upper_ci,
    sample_size,
    estimation_date,
    notes
  )

cat("    Final column order:\n")
cat("      ", paste(names(all_estimates), collapse = ", "), "\n\n")

# 6. Summary by data source
cat("[6] Summary by data source:\n")

summary_table <- all_estimates %>%
  dplyr::group_by(data_source) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    n_estimands = length(unique(estimand)),
    n_missing = sum(is.na(estimate)),
    .groups = "drop"
  )

print(summary_table)

cat("\n")

# 8. Save consolidated estimates
cat("[8] Saving consolidated estimates...\n")

saveRDS(all_estimates, "data/raking/ne25/raking_targets_consolidated.rds")

cat("    Saved to: data/raking/ne25/raking_targets_consolidated.rds\n")
cat("    Dimensions:", nrow(all_estimates), "rows x", ncol(all_estimates), "columns\n\n")

cat("========================================\n")
cat("Tasks 5.1-5.3 Complete\n")
cat("========================================\n\n")

# Return for inspection
all_estimates

# Phase 2, Task 2.8: Compile All ACS Estimates
# Combine 26 estimands into 156-row matrix (26 × 6 ages)

library(dplyr)

cat("\n========================================\n")
cat("Task 2.8: Compile ACS Estimates\n")
cat("========================================\n\n")

# 1. Load all individual estimate files (GLM2 versions)
cat("[1] Loading individual estimate files (GLM2 versions)...\n")

sex_est <- readRDS("data/raking/ne25/sex_estimates_glm2.rds")
cat("    ✓ Sex estimates loaded:", nrow(sex_est), "rows\n")

race_est <- readRDS("data/raking/ne25/race_ethnicity_estimates_glm2.rds")
cat("    ✓ Race/ethnicity estimates loaded:", nrow(race_est), "rows\n")

fpl_est <- readRDS("data/raking/ne25/fpl_estimates_glm2.rds")
cat("    ✓ FPL estimates loaded:", nrow(fpl_est), "rows\n")

puma_est <- readRDS("data/raking/ne25/puma_estimates_glm2.rds")
cat("    ✓ PUMA estimates loaded:", nrow(puma_est), "rows\n")

mom_educ_est <- readRDS("data/raking/ne25/mother_education_estimates_glm2.rds")
cat("    ✓ Mother's education estimates loaded:", nrow(mom_educ_est), "rows\n")

mom_married_est <- readRDS("data/raking/ne25/mother_marital_status_estimates_glm2.rds")
cat("    ✓ Mother's marital status estimates loaded:", nrow(mom_married_est), "rows\n")

cat("\n    Total rows loaded:",
    nrow(sex_est) + nrow(race_est) + nrow(fpl_est) +
    nrow(puma_est) + nrow(mom_educ_est) + nrow(mom_married_est), "\n")

# 2. Standardize column names
cat("\n[2] Standardizing data frames...\n")

# All should have: age, estimand, estimate
# Check each one
cat("    Sex columns:", paste(names(sex_est), collapse = ", "), "\n")
cat("    Race columns:", paste(names(race_est), collapse = ", "), "\n")
cat("    FPL columns:", paste(names(fpl_est), collapse = ", "), "\n")
cat("    PUMA columns:", paste(names(puma_est), collapse = ", "), "\n")
cat("    Mom educ columns:", paste(names(mom_educ_est), collapse = ", "), "\n")
cat("    Mom married columns:", paste(names(mom_married_est), collapse = ", "), "\n")

# Sex estimates only has age and estimate - add estimand column
if (!"estimand" %in% names(sex_est)) {
  cat("    Adding estimand column to sex_est\n")
  sex_est <- sex_est %>%
    dplyr::mutate(estimand = "Male", .before = "estimate")
}

# 3. Combine all estimates
cat("\n[3] Combining all estimates...\n")

acs_estimates <- dplyr::bind_rows(
  sex_est,
  race_est,
  fpl_est,
  puma_est,
  mom_educ_est,
  mom_married_est
)

cat("    Combined data frame created\n")
cat("    Total rows:", nrow(acs_estimates), "\n")
cat("    Expected rows: 150 (25 estimands × 6 ages)\n")

if (nrow(acs_estimates) == 150) {
  cat("    ✓ Row count matches expected!\n")
} else {
  cat("    ✗ WARNING: Row count mismatch (expected 150)\n")
}

# 4. Count estimands
cat("\n[4] Counting unique estimands...\n")
estimands <- unique(acs_estimates$estimand)
cat("    Total unique estimands:", length(estimands), "\n")
cat("    Expected: 25 estimands (1 sex + 3 race + 5 FPL + 14 PUMA + 2 mother)\n")

if (length(estimands) == 25) {
  cat("    ✓ Estimand count matches expected!\n")
} else {
  cat("    ✗ WARNING: Estimand count mismatch (expected 25)\n")
}

cat("\n    Estimands:\n")
for (i in 1:length(estimands)) {
  est_count <- sum(acs_estimates$estimand == estimands[i])
  cat("      ", sprintf("%2d", i), ". ", estimands[i], " (", est_count, " rows)\n", sep = "")
}

# 5. Summary by source
cat("\n[5] Summary by data source:\n")

# Count rows by source type
cat("    Sex (1 estimand × 6 ages):", sum(acs_estimates$estimand == "Male"), "rows\n")
cat("    Race/Ethnicity (3 estimands × 6 ages):",
    sum(acs_estimates$estimand %in% c("White non-Hispanic", "Black", "Hispanic")), "rows\n")
cat("    FPL (5 estimands × 6 ages):",
    sum(grepl("^[0-9]", acs_estimates$estimand)), "rows\n")
cat("    PUMA (14 estimands × 6 ages):",
    sum(grepl("^PUMA_", acs_estimates$estimand)), "rows\n")
cat("    Mother's education (1 estimand × 6 ages):",
    sum(acs_estimates$estimand == "Mother Bachelor's+"), "rows\n")
cat("    Mother's marital status (1 estimand × 6 ages):",
    sum(acs_estimates$estimand == "Mother Married"), "rows\n")

# 6. Check for missing values
cat("\n[6] Checking for missing values...\n")

missing_ages <- sum(is.na(acs_estimates$age))
missing_estimands <- sum(is.na(acs_estimates$estimand))
missing_estimates <- sum(is.na(acs_estimates$estimate))

cat("    Missing ages:", missing_ages, "\n")
cat("    Missing estimand labels:", missing_estimands, "\n")
cat("    Missing estimate values:", missing_estimates, "\n")

if (missing_ages == 0 && missing_estimands == 0 && missing_estimates == 0) {
  cat("    ✓ No missing values detected\n")
} else {
  cat("    ✗ WARNING: Missing values detected\n")
}

# 7. Check estimate ranges
cat("\n[7] Checking estimate value ranges...\n")

# All estimates should be between 0 and 1
if (all(acs_estimates$estimate >= 0 & acs_estimates$estimate <= 1)) {
  cat("    ✓ All estimates in valid range [0, 1]\n")
} else {
  cat("    ✗ WARNING: Some estimates outside [0, 1]\n")
  invalid <- acs_estimates[acs_estimates$estimate < 0 | acs_estimates$estimate > 1, ]
  print(invalid)
}

cat("    Overall range:", round(min(acs_estimates$estimate), 4), "to",
    round(max(acs_estimates$estimate), 4), "\n")

# 8. Preview final data
cat("\n[8] Preview of compiled estimates:\n")
cat("    First 10 rows:\n")
print(head(acs_estimates, 10))

cat("\n    Last 10 rows:\n")
print(tail(acs_estimates, 10))

# 9. Arrange by age and estimand for consistency
cat("\n[9] Sorting data frame (by age, then estimand)...\n")
acs_estimates <- acs_estimates %>%
  dplyr::arrange(age, estimand)

cat("    Data frame sorted\n")

# 10. Summary statistics
cat("\n[10] Summary statistics:\n")
cat("     Total rows:", nrow(acs_estimates), "\n")
cat("     Total estimands:", length(unique(acs_estimates$estimand)), "\n")
cat("     Ages covered:", min(acs_estimates$age), "to", max(acs_estimates$age), "\n")
cat("     Estimate range:", round(min(acs_estimates$estimate), 4), "to",
    round(max(acs_estimates$estimate), 4), "\n")

# 11. Create metadata
cat("\n[11] Creating metadata...\n")

acs_metadata <- list(
  n_rows = nrow(acs_estimates),
  n_estimands = length(unique(acs_estimates$estimand)),
  estimands = unique(acs_estimates$estimand),
  age_range = c(min(acs_estimates$age), max(acs_estimates$age)),
  estimate_range = c(min(acs_estimates$estimate), max(acs_estimates$estimate)),
  sources = list(
    sex = "02_estimate_sex_final.R",
    race_ethnicity = "03_estimate_race_ethnicity.R",
    fpl = "04_estimate_fpl.R",
    puma = "05_estimate_puma.R",
    mother_education = "06_estimate_mother_education.R",
    mother_marital_status = "07_estimate_mother_marital_status.R"
  ),
  created_date = Sys.time()
)

cat("    Metadata created\n")

# 12. Save compiled estimates
cat("\n[12] Saving compiled ACS estimates...\n")

# Save data frame
saveRDS(acs_estimates, "data/raking/ne25/acs_estimates_compiled.rds")
cat("    ✓ Saved data frame to: data/raking/ne25/acs_estimates_compiled.rds\n")

# Save metadata
saveRDS(acs_metadata, "data/raking/ne25/acs_estimates_metadata.rds")
cat("    ✓ Saved metadata to: data/raking/ne25/acs_estimates_metadata.rds\n")

cat("\n========================================\n")
cat("Task 2.8 Complete: ACS Estimates Compiled\n")
cat("========================================\n")
cat("\nFinal Summary:\n")
cat("  - Total rows: 150 (25 estimands × 6 ages)\n")
cat("  - Sex: 6 rows (1 estimand)\n")
cat("  - Race/Ethnicity: 18 rows (3 estimands)\n")
cat("  - Federal Poverty Level: 30 rows (5 estimands)\n")
cat("  - PUMA Geography: 84 rows (14 estimands)\n")
cat("  - Mother's Education: 6 rows (1 estimand)\n")
cat("  - Mother's Marital Status: 6 rows (1 estimand)\n")
cat("  - Saved to: data/raking/ne25/acs_estimates_compiled.rds\n\n")

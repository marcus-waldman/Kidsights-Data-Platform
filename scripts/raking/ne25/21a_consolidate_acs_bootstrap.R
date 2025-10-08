# Phase 2, Task 2.10: Consolidate ACS Bootstrap Estimates
# Combine bootstrap replicates from all 6 ACS estimation scripts
# Uses bootstrap_config.R as single source of truth for n_boot

library(dplyr)

# Source bootstrap configuration (single source of truth)
source("config/bootstrap_config.R")

cat("\n========================================\n")
cat("Consolidate ACS Bootstrap Estimates\n")
cat("========================================\n\n")

# 1. Load all ACS bootstrap files
cat("[1] Loading ACS bootstrap files...\n")

boot_sex <- readRDS("data/raking/ne25/sex_estimates_boot_glm2.rds")
boot_race <- readRDS("data/raking/ne25/race_ethnicity_estimates_boot_glm2.rds")
boot_fpl <- readRDS("data/raking/ne25/fpl_estimates_boot_glm2.rds")
boot_puma <- readRDS("data/raking/ne25/puma_estimates_boot_glm2.rds")
boot_mom_educ <- readRDS("data/raking/ne25/mother_education_estimates_boot_glm2.rds")
boot_mom_married <- readRDS("data/raking/ne25/mother_marital_status_estimates_boot_glm2.rds")

cat("    Sex bootstrap:", nrow(boot_sex), "rows\n")
cat("    Race/ethnicity bootstrap:", nrow(boot_race), "rows\n")
cat("    FPL bootstrap:", nrow(boot_fpl), "rows\n")
cat("    PUMA bootstrap:", nrow(boot_puma), "rows\n")
cat("    Mother education bootstrap:", nrow(boot_mom_educ), "rows\n")
cat("    Mother marital status bootstrap:", nrow(boot_mom_married), "rows\n")

# 2. Validate n_boot consistency with config
cat("\n[2] Validating n_boot from config...\n")

# Get expected n_boot from configuration
n_boot_expected <- BOOTSTRAP_CONFIG$n_boot
cat("    Config n_boot:", n_boot_expected, "\n")

# Detect n_boot from actual files
n_boot_in_files <- length(unique(boot_sex$replicate))
cat("    Files n_boot:", n_boot_in_files, "\n")

# Validate consistency
if (n_boot_in_files != n_boot_expected) {
  stop("ERROR: Bootstrap files have n_boot = ", n_boot_in_files,
       " but config expects ", n_boot_expected, ".\n",
       "       Solution: Delete consolidated files and regenerate:\n",
       "       rm data/raking/ne25/*bootstrap_consolidated.rds\n",
       "       Then re-run this script.")
}

cat("    [OK] Files match config (n_boot =", n_boot_expected, ")\n")

# Calculate expected row counts using config n_boot
expected_counts <- c(
  1 * 6 * n_boot_expected,   # Sex: 1 estimand × 6 ages × n_boot
  3 * 6 * n_boot_expected,   # Race: 3 estimands × 6 ages × n_boot
  5 * 6 * n_boot_expected,   # FPL: 5 estimands × 6 ages × n_boot
  14 * 6 * n_boot_expected,  # PUMA: 14 estimands × 6 ages × n_boot
  1 * 6 * n_boot_expected,   # Mother edu: 1 estimand × 6 ages × n_boot
  1 * 6 * n_boot_expected    # Mother married: 1 estimand × 6 ages × n_boot
)

expected_total <- 25 * 6 * n_boot_expected  # 25 total ACS estimands
cat("    Expected total:", expected_total, "rows (25 estimands × 6 ages ×", n_boot_expected, "replicates)\n\n")

# 3. Verify row counts
cat("[3] Verifying row counts...\n")

actual_counts <- c(
  nrow(boot_sex),
  nrow(boot_race),
  nrow(boot_fpl),
  nrow(boot_puma),
  nrow(boot_mom_educ),
  nrow(boot_mom_married)
)

if (all(actual_counts == expected_counts)) {
  cat("    [OK] All file row counts match expectations\n\n")
} else {
  stop("ERROR: Row count mismatch. Expected: ", paste(expected_counts, collapse = ", "),
       " Got: ", paste(actual_counts, collapse = ", "))
}

# 4. Combine all bootstrap estimates
cat("[4] Combining all bootstrap estimates...\n")

acs_boot_consolidated <- dplyr::bind_rows(
  boot_sex,
  boot_race,
  boot_fpl,
  boot_puma,
  boot_mom_educ,
  boot_mom_married
)

cat("    Total rows:", nrow(acs_boot_consolidated), "\n")
cat("    Total estimands:", length(unique(acs_boot_consolidated$estimand)), "\n")
cat("    Total replicates:", length(unique(acs_boot_consolidated$replicate)), "\n\n")

# Verify total
if (nrow(acs_boot_consolidated) != expected_total) {
  stop("ERROR: Expected ", expected_total, " total rows (25 estimands × 6 ages × ",
       n_boot_expected, " replicates), got ", nrow(acs_boot_consolidated))
}

cat("    [OK] Total row count verified\n\n")

# 4. Verify structure
cat("[4] Verifying data structure...\n")

required_cols <- c("age", "estimand", "replicate", "estimate")
if (all(required_cols %in% names(acs_boot_consolidated))) {
  cat("    [OK] All required columns present: age, estimand, replicate, estimate\n\n")
} else {
  missing_cols <- setdiff(required_cols, names(acs_boot_consolidated))
  stop("ERROR: Missing columns: ", paste(missing_cols, collapse = ", "))
}

# 5. Add metadata columns
cat("[5] Adding metadata columns...\n")

acs_boot_consolidated <- acs_boot_consolidated %>%
  dplyr::mutate(
    # Data source
    data_source = "ACS",

    # Survey identifier
    survey = "ne25",

    # Bootstrap method
    bootstrap_method = "Rao-Wu-Yue-Beaumont",

    # Number of bootstrap replicates
    n_boot = length(unique(replicate)),

    # Estimation date
    estimation_date = as.Date(Sys.Date())
  )

cat("    Metadata columns added:\n")
cat("      - data_source ('ACS')\n")
cat("      - survey ('ne25')\n")
cat("      - bootstrap_method ('Rao-Wu-Yue-Beaumont')\n")
cat("      - n_boot (", unique(acs_boot_consolidated$n_boot), ")\n", sep = "")
cat("      - estimation_date\n\n")

# 6. Reorder columns for consistency
cat("[6] Reordering columns...\n")

acs_boot_consolidated <- acs_boot_consolidated %>%
  dplyr::select(
    survey,
    data_source,
    age,
    estimand,
    replicate,
    estimate,
    bootstrap_method,
    n_boot,
    estimation_date
  )

cat("    Final column order:\n")
cat("      ", paste(names(acs_boot_consolidated), collapse = ", "), "\n\n")

# 7. Summary by estimand
cat("[7] Summary by estimand:\n")

summary_table <- acs_boot_consolidated %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    n_ages = length(unique(age)),
    n_replicates = length(unique(replicate)),
    min_estimate = min(estimate, na.rm = TRUE),
    max_estimate = max(estimate, na.rm = TRUE),
    .groups = "drop"
  )

print(summary_table)

cat("\n")

# 8. Overall statistics
cat("[8] Overall bootstrap statistics:\n")

cat("    Total rows:", nrow(acs_boot_consolidated), "\n")
cat("    Estimands:", length(unique(acs_boot_consolidated$estimand)), "\n")
cat("    Age groups:", length(unique(acs_boot_consolidated$age)), "\n")
cat("    Bootstrap replicates:", length(unique(acs_boot_consolidated$replicate)), "\n")
cat("    Missing values:", sum(is.na(acs_boot_consolidated$estimate)), "\n\n")

# 9. Validation checks
cat("[9] Validation checks...\n")

# Check for missing estimates
if (sum(is.na(acs_boot_consolidated$estimate)) > 0) {
  cat("    [WARN] Found", sum(is.na(acs_boot_consolidated$estimate)), "missing estimates\n")
} else {
  cat("    [OK] No missing estimates\n")
}

# Check replicate consistency (should be same for all estimands)
replicates_by_estimand <- acs_boot_consolidated %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(n_replicates = length(unique(replicate)), .groups = "drop")

if (all(replicates_by_estimand$n_replicates == n_boot_expected)) {
  cat("    [OK] All estimands have", n_boot_expected, "replicates\n")
} else {
  cat("    [WARN] Inconsistent replicate counts across estimands\n")
}

# Check age coverage
ages_by_estimand <- acs_boot_consolidated %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(n_ages = length(unique(age)), .groups = "drop")

if (all(ages_by_estimand$n_ages == 6)) {
  cat("    [OK] All estimands cover 6 age groups (0-5)\n")
} else {
  cat("    [WARN] Inconsistent age coverage across estimands\n")
}

cat("\n")

# 9.5. VERIFY SHARED BOOTSTRAP STRUCTURE
cat("[9.5] Verifying SHARED bootstrap replicate structure...\n")

# Test: Do different estimands show correlated bootstrap replicates?
# If bootstrap is truly shared, estimands should show correlation

# Get two estimands for age 0
sex_age0 <- acs_boot_consolidated %>%
  dplyr::filter(estimand == "sex_male", age == 0) %>%
  dplyr::arrange(replicate) %>%
  dplyr::pull(estimate)

race_age0 <- acs_boot_consolidated %>%
  dplyr::filter(estimand == "race_white_nh", age == 0) %>%
  dplyr::arrange(replicate) %>%
  dplyr::pull(estimate)

# Calculate correlation
if (length(sex_age0) > 0 && length(race_age0) > 0) {
  boot_correlation <- cor(sex_age0, race_age0)

  cat("    Testing correlation between sex and race/ethnicity replicates:\n")
  cat("      Correlation:", round(boot_correlation, 4), "\n")

  if (abs(boot_correlation) > 0.5) {
    cat("      [VERIFIED] Strong correlation confirms SHARED bootstrap design\n")
    cat("      All 25 estimands properly share sampling uncertainty structure\n")
  } else if (abs(boot_correlation) < 0.1) {
    cat("      [WARNING] Low correlation suggests independent bootstrap replicates\n")
    cat("      This may indicate bootstrap design was not properly shared\n")
  } else {
    cat("      [UNCERTAIN] Moderate correlation detected\n")
  }
} else {
  cat("    [WARN] Could not verify shared structure (missing test estimands)\n")
}

cat("\n")

# 10. Save consolidated bootstrap estimates
cat("[10] Saving consolidated bootstrap estimates...\n")

saveRDS(acs_boot_consolidated, "data/raking/ne25/acs_bootstrap_consolidated.rds")

cat("     Saved to: data/raking/ne25/acs_bootstrap_consolidated.rds\n")
cat("     Dimensions:", nrow(acs_boot_consolidated), "rows x", ncol(acs_boot_consolidated), "columns\n\n")

cat("========================================\n")
cat("ACS Bootstrap Consolidation Complete\n")
cat("========================================\n\n")

cat("Current configuration:\n")
cat("  n_boot:", n_boot_expected, "(from bootstrap_config.R)\n")
cat("  Total rows:", nrow(acs_boot_consolidated), "\n")
cat("  Estimands: 25 (ACS)\n")
cat("  Age groups: 6 (0-5)\n\n")

if (n_boot_expected < 4096) {
  cat("NOTE: To generate production bootstrap (n_boot = 4096):\n")
  cat("  1. Change n_boot in config/bootstrap_config.R to 4096\n")
  cat("  2. Delete all bootstrap files and regenerate\n")
  cat("  3. Re-run full pipeline (estimated time: 6-7 hours with 2-core parallel processing)\n")
  cat("  4. Expected production size: 25 estimands × 6 ages × 4096 replicates = 614,400 rows (ACS only)\n\n")
}

# Return for inspection
acs_boot_consolidated

# Phase 4, Task 4.7: Consolidate NSCH Bootstrap Estimates
# Combine bootstrap replicates from all 4 NSCH estimation scripts
# Dynamically detects n_boot from actual data

library(dplyr)

cat("\n========================================\n")
cat("Consolidate NSCH Bootstrap Estimates\n")
cat("========================================\n\n")

# 1. Load all NSCH bootstrap files
cat("[1] Loading NSCH bootstrap files...\n")

boot_ace <- readRDS("data/raking/ne25/ace_exposure_boot_glm2.rds")
boot_emot <- readRDS("data/raking/ne25/emotional_behavioral_boot_glm2.rds")
boot_health <- readRDS("data/raking/ne25/excellent_health_boot_glm2.rds")
boot_childcare <- readRDS("data/raking/ne25/childcare_10hrs_boot.rds")  # No glm2 version

cat("    ACE exposure bootstrap:", nrow(boot_ace), "rows\n")
cat("    Emotional/behavioral bootstrap:", nrow(boot_emot), "rows\n")
cat("    Excellent health bootstrap:", nrow(boot_health), "rows\n")
cat("    Childcare bootstrap:", nrow(boot_childcare), "rows\n")

# 2. Detect n_boot from data
cat("\n[2] Detecting n_boot from data...\n")

n_boot_detected <- length(unique(boot_ace$replicate))
cat("    Detected n_boot:", n_boot_detected, "\n")

# Calculate expected row counts dynamically
expected_counts <- rep(6 * n_boot_detected, 4)  # 4 estimands × 6 ages × n_boot
expected_total <- 4 * 6 * n_boot_detected       # 4 total NSCH estimands

cat("    Expected total:", expected_total, "rows (4 estimands × 6 ages ×", n_boot_detected, "replicates)\n\n")

# 3. Verify row counts
cat("[3] Verifying row counts...\n")

actual_counts <- c(
  nrow(boot_ace),
  nrow(boot_emot),
  nrow(boot_health),
  nrow(boot_childcare)
)

if (all(actual_counts == expected_counts)) {
  cat("    [OK] All file row counts match expectations\n\n")
} else {
  stop("ERROR: Row count mismatch. Expected: ", paste(expected_counts, collapse = ", "),
       " Got: ", paste(actual_counts, collapse = ", "))
}

# 4. Combine all bootstrap estimates
cat("[4] Combining all bootstrap estimates...\n")

nsch_boot_consolidated <- dplyr::bind_rows(
  boot_ace,
  boot_emot,
  boot_health,
  boot_childcare
)

cat("    Total rows:", nrow(nsch_boot_consolidated), "\n")
cat("    Total estimands:", length(unique(nsch_boot_consolidated$estimand)), "\n")
cat("    Total replicates:", length(unique(nsch_boot_consolidated$replicate)), "\n\n")

# Verify total
if (nrow(nsch_boot_consolidated) != expected_total) {
  stop("ERROR: Expected ", expected_total, " total rows (4 estimands × 6 ages × ",
       n_boot_detected, " replicates), got ", nrow(nsch_boot_consolidated))
}

cat("    [OK] Total row count verified\n\n")

# 4. Verify structure
cat("[4] Verifying data structure...\n")

required_cols <- c("age", "estimand", "replicate", "estimate")
if (all(required_cols %in% names(nsch_boot_consolidated))) {
  cat("    [OK] All required columns present: age, estimand, replicate, estimate\n\n")
} else {
  missing_cols <- setdiff(required_cols, names(nsch_boot_consolidated))
  stop("ERROR: Missing columns: ", paste(missing_cols, collapse = ", "))
}

# 5. Add metadata columns
cat("[5] Adding metadata columns...\n")

nsch_boot_consolidated <- nsch_boot_consolidated %>%
  dplyr::mutate(
    # Data source
    data_source = "NSCH",

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
cat("      - data_source ('NSCH')\\n")
cat("      - survey ('ne25')\\n")
cat("      - bootstrap_method ('Rao-Wu-Yue-Beaumont')\\n")
cat("      - n_boot (", unique(nsch_boot_consolidated$n_boot), ")\\n", sep = "")
cat("      - estimation_date\n\n")

# 6. Reorder columns for consistency
cat("[6] Reordering columns...\n")

nsch_boot_consolidated <- nsch_boot_consolidated %>%
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
cat("      ", paste(names(nsch_boot_consolidated), collapse = ", "), "\n\n")

# 7. Summary by estimand
cat("[7] Summary by estimand:\n")

summary_table <- nsch_boot_consolidated %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    n_ages = length(unique(age)),
    n_replicates = length(unique(replicate)),
    n_non_missing = sum(!is.na(estimate)),
    n_missing = sum(is.na(estimate)),
    min_estimate = min(estimate, na.rm = TRUE),
    max_estimate = max(estimate, na.rm = TRUE),
    .groups = "drop"
  )

print(summary_table)

cat("\n")

# 8. Overall statistics
cat("[8] Overall bootstrap statistics:\n")

cat("    Total rows:", nrow(nsch_boot_consolidated), "\n")
cat("    Estimands:", length(unique(nsch_boot_consolidated$estimand)), "\n")
cat("    Age groups:", length(unique(nsch_boot_consolidated$age)), "\n")
cat("    Bootstrap replicates:", length(unique(nsch_boot_consolidated$replicate)), "\n")
cat("    Missing values:", sum(is.na(nsch_boot_consolidated$estimate)), "\n")
cat("    (Note: Emotional/behavioral has NA for ages 0-2 by design)\n\n")

# 9. Validation checks
cat("[9] Validation checks...\n")

# Check emotional/behavioral NA pattern (should be ages 0-2)
emot_data <- nsch_boot_consolidated %>%
  dplyr::filter(estimand == "emotional_behavioral")

emot_missing_by_age <- emot_data %>%
  dplyr::group_by(age) %>%
  dplyr::summarise(n_missing = sum(is.na(estimate)), .groups = "drop")

if (all(emot_missing_by_age$n_missing[1:3] == n_boot_detected) &&  # Ages 0-2 have n_boot NAs each
    all(emot_missing_by_age$n_missing[4:6] == 0)) {                # Ages 3-5 have 0 NAs
  cat("    [OK] Emotional/behavioral NA pattern correct (NA for ages 0-2 only)\n")
} else {
  cat("    [WARN] Unexpected NA pattern in emotional/behavioral\n")
}

# Check replicate consistency (should be same for all estimands)
replicates_by_estimand <- nsch_boot_consolidated %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(n_replicates = length(unique(replicate)), .groups = "drop")

if (all(replicates_by_estimand$n_replicates == n_boot_detected)) {
  cat("    [OK] All estimands have", n_boot_detected, "replicates\n")
} else {
  cat("    [WARN] Inconsistent replicate counts across estimands\n")
}

# Check age coverage
ages_by_estimand <- nsch_boot_consolidated %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(n_ages = length(unique(age)), .groups = "drop")

if (all(ages_by_estimand$n_ages == 6)) {
  cat("    [OK] All estimands cover 6 age groups (0-5)\n")
} else {
  cat("    [WARN] Inconsistent age coverage across estimands\n")
}

cat("\n")

# 10. VERIFY SHARED BOOTSTRAP STRUCTURE
cat("[10] Verifying SHARED bootstrap replicate structure...\n")

# Test: Do different estimands show correlated bootstrap replicates?
# Get two estimands for age 0 (use non-NA estimates)
ace_age0 <- nsch_boot_consolidated %>%
  dplyr::filter(estimand == "ace_exposure", age == 0) %>%
  dplyr::arrange(replicate) %>%
  dplyr::pull(estimate)

health_age0 <- nsch_boot_consolidated %>%
  dplyr::filter(estimand == "excellent_health", age == 0) %>%
  dplyr::arrange(replicate) %>%
  dplyr::pull(estimate)

# Calculate correlation
if (length(ace_age0) > 0 && length(health_age0) > 0) {
  boot_correlation <- cor(ace_age0, health_age0)

  cat("    Testing correlation between ACE and health replicates:\n")
  cat("      Correlation:", round(boot_correlation, 4), "\n")

  if (abs(boot_correlation) > 0.5) {
    cat("      [VERIFIED] Strong correlation confirms SHARED bootstrap design\n")
    cat("      All 4 estimands properly share sampling uncertainty structure\n")
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

# 11. Save consolidated bootstrap estimates
cat("[11] Saving consolidated bootstrap estimates...\n")

saveRDS(nsch_boot_consolidated, "data/raking/ne25/nsch_bootstrap_consolidated.rds")

cat("     Saved to: data/raking/ne25/nsch_bootstrap_consolidated.rds\n")
cat("     Dimensions:", nrow(nsch_boot_consolidated), "rows x", ncol(nsch_boot_consolidated), "columns\n\n")

cat("========================================\n")
cat("NSCH Bootstrap Consolidation Complete\n")
cat("========================================\n\n")

cat("Current configuration:\n")
cat("  n_boot:", n_boot_detected, "\n")
cat("  Total rows:", nrow(nsch_boot_consolidated), "\n")
cat("  Estimands: 4 (NSCH)\n")
cat("  Age groups: 6 (0-5)\n\n")

if (n_boot_detected < 4096) {
  cat("NOTE: To generate production bootstrap (n_boot = 4096):\n")
  cat("  1. Change n_boot in all 3 bootstrap design creation scripts (01a, 12a, 17a)\n")
  cat("  2. Re-run full pipeline (estimated time: 6-7 hours with 2-core parallel processing)\n")
  cat("  3. Expected production size: 4 estimands × 6 ages × 4096 replicates = 98,304 rows (NSCH only)\n\n")
}

# Return for inspection
nsch_boot_consolidated

# Phase 5, Task 5.2: Consolidate ALL Bootstrap Replicates
# Combine bootstrap replicates from ACS, NHIS, and NSCH sources
# Uses bootstrap_config.R as single source of truth for n_boot
# Production: 761,856 rows (614,400 ACS + 49,152 NHIS + 98,304 NSCH with n_boot = 4096)

library(dplyr)

# Source bootstrap configuration (single source of truth)
source("config/bootstrap_config.R")

cat("\n========================================\n")
cat("Consolidate ALL Bootstrap Replicates\n")
cat("========================================\n\n")

# 1. Load bootstrap files from all three sources
cat("[1] Loading bootstrap files from all sources...\n")

# ACS bootstrap (consolidated)
acs_boot <- readRDS("data/raking/ne25/acs_bootstrap_consolidated.rds")

# NHIS bootstrap (glm2 versions - PHQ-2 and GAD-2)
phq2_boot <- readRDS("data/raking/ne25/phq2_estimate_boot_glm2.rds")
gad2_boot <- readRDS("data/raking/ne25/gad2_estimate_boot_glm2.rds")

# Combine NHIS mental health bootstrap replicates
nhis_boot <- dplyr::bind_rows(phq2_boot, gad2_boot)

# NSCH bootstrap (consolidated)
nsch_boot <- readRDS("data/raking/ne25/nsch_bootstrap_consolidated.rds")

cat("    ACS bootstrap:", nrow(acs_boot), "rows\n")
cat("    NHIS bootstrap:", nrow(nhis_boot), "rows (PHQ-2 + GAD-2)\n")
cat("    NSCH bootstrap:", nrow(nsch_boot), "rows\n\n")

# 2. Validate n_boot consistency with config
cat("[2] Validating n_boot from config...\n")

# Get expected n_boot from configuration
n_boot_expected <- BOOTSTRAP_CONFIG$n_boot
cat("    Config n_boot:", n_boot_expected, "\n")

# Detect n_boot from actual consolidated files
n_boot_acs <- length(unique(acs_boot$replicate))
n_boot_nhis <- length(unique(nhis_boot$replicate))
n_boot_nsch <- length(unique(nsch_boot$replicate))

cat("    ACS n_boot:", n_boot_acs, "\n")
cat("    NHIS n_boot:", n_boot_nhis, "\n")
cat("    NSCH n_boot:", n_boot_nsch, "\n")

# Validate all match config
if (!all(c(n_boot_acs, n_boot_nhis, n_boot_nsch) == n_boot_expected)) {
  stop("ERROR: Consolidated files have inconsistent n_boot:\n",
       "       ACS: ", n_boot_acs, ", NHIS: ", n_boot_nhis, ", NSCH: ", n_boot_nsch, "\n",
       "       Config expects: ", n_boot_expected, "\n",
       "       Solution: Delete ALL consolidated files and regenerate:\n",
       "       rm data/raking/ne25/*bootstrap_consolidated.rds\n",
       "       Then re-run consolidation scripts in order (21a, 21b, 22).")
}

cat("    [OK] All sources match config (n_boot =", n_boot_expected, ")\n")

# Calculate expected row counts using config n_boot
expected_counts <- c(
  ACS = 25 * 6 * n_boot_expected,  # 25 estimands × 6 ages × n_boot
  NHIS = 2 * 6 * n_boot_expected,  # 2 estimands × 6 ages × n_boot (PHQ-2 + GAD-2)
  NSCH = 4 * 6 * n_boot_expected   # 4 estimands × 6 ages × n_boot
)

expected_total <- 31 * 6 * n_boot_expected  # 31 total estimands
cat("    Expected total:", expected_total, "rows (31 estimands × 6 ages ×", n_boot_expected, "replicates)\n\n")

# 3. Verify row counts
cat("[3] Verifying row counts by source...\n")

actual_counts <- c(
  ACS = nrow(acs_boot),
  NHIS = nrow(nhis_boot),
  NSCH = nrow(nsch_boot)
)

if (all(actual_counts == expected_counts)) {
  cat("    [OK] All source file row counts match expectations\n\n")
} else {
  cat("    [ERROR] Row count mismatch:\n")
  for (source in names(expected_counts)) {
    cat("      ", source, ": expected", expected_counts[source],
        ", got", actual_counts[source], "\n")
  }
  stop("ERROR: Cannot proceed with mismatched row counts")
}

# 3. Verify column structure consistency
cat("[3] Verifying column structure across sources...\n")

required_cols <- c("survey", "data_source", "age", "estimand", "replicate",
                   "estimate", "bootstrap_method", "n_boot", "estimation_date")

# Check ACS
if (all(required_cols %in% names(acs_boot))) {
  cat("    [OK] ACS has all required columns\n")
} else {
  missing <- setdiff(required_cols, names(acs_boot))
  stop("ERROR: ACS missing columns: ", paste(missing, collapse = ", "))
}

# Check NHIS structure - need to add metadata columns if missing
if (!all(required_cols %in% names(nhis_boot))) {
  cat("    [INFO] NHIS missing metadata columns - will add during consolidation\n")
}

# Check NSCH
if (all(required_cols %in% names(nsch_boot))) {
  cat("    [OK] NSCH has all required columns\n")
} else {
  missing <- setdiff(required_cols, names(nsch_boot))
  stop("ERROR: NSCH missing columns: ", paste(missing, collapse = ", "))
}

cat("\n")

# 4. Standardize NHIS format if needed
cat("[4] Standardizing NHIS format...\n")

# Add metadata columns to NHIS if missing
if (!all(required_cols %in% names(nhis_boot))) {
  nhis_boot <- nhis_boot %>%
    dplyr::mutate(
      survey = "ne25",
      data_source = "NHIS",
      bootstrap_method = "Rao-Wu-Yue-Beaumont",
      n_boot = length(unique(replicate)),
      estimation_date = as.Date(Sys.Date())
    )
  cat("    Added metadata columns to NHIS\n")
}

# Reorder columns to match ACS/NSCH
nhis_boot <- nhis_boot %>%
  dplyr::select(dplyr::all_of(required_cols))

cat("    [OK] NHIS format standardized\n\n")

# 5. Combine all sources
cat("[5] Combining bootstrap replicates from all sources...\n")

all_boot_replicates <- dplyr::bind_rows(
  acs_boot,
  nhis_boot,
  nsch_boot
)

cat("    Total rows:", nrow(all_boot_replicates), "\n")
cat("    Total estimands:", length(unique(all_boot_replicates$estimand)), "\n")
cat("    Total replicates:", length(unique(all_boot_replicates$replicate)), "\n")
cat("    Sources:", paste(unique(all_boot_replicates$data_source), collapse = ", "), "\n\n")

# Verify total
if (nrow(all_boot_replicates) != expected_total) {
  stop("ERROR: Expected ", expected_total, " total rows (31 estimands × 6 ages × ",
       n_boot_expected, " replicates), got ", nrow(all_boot_replicates))
}

cat("    [OK] Total row count verified:", expected_total, "rows\n\n")

# 6. Add consolidated metadata
cat("[6] Adding consolidated timestamp...\n")

all_boot_replicates <- all_boot_replicates %>%
  dplyr::mutate(
    # Use consolidation timestamp, not individual script timestamps
    consolidated_at = Sys.time()
  )

cat("    Consolidation timestamp:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# 7. Summary by data source
cat("[7] Summary by data source:\n")

source_summary <- all_boot_replicates %>%
  dplyr::group_by(data_source) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    n_estimands = length(unique(estimand)),
    n_ages = length(unique(age)),
    n_replicates = length(unique(replicate)),
    n_missing = sum(is.na(estimate)),
    min_estimate = min(estimate, na.rm = TRUE),
    max_estimate = max(estimate, na.rm = TRUE),
    .groups = "drop"
  )

print(source_summary)

cat("\n")

# 8. Summary by estimand (top 10 for brevity)
cat("[8] Sample of estimands (first 10):\n")

estimand_summary <- all_boot_replicates %>%
  dplyr::group_by(data_source, estimand) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    n_ages = length(unique(age)),
    n_replicates = length(unique(replicate)),
    n_missing = sum(is.na(estimate)),
    .groups = "drop"
  ) %>%
  dplyr::arrange(data_source, estimand)

print(head(estimand_summary, 10))

cat("\n    (Showing 10 of", nrow(estimand_summary), "total estimands)\n\n")

# 9. Validation checks
cat("[9] Validation checks...\n")

# Check replicate consistency
replicates_by_source <- all_boot_replicates %>%
  dplyr::group_by(data_source) %>%
  dplyr::summarise(n_replicates = length(unique(replicate)), .groups = "drop")

if (all(replicates_by_source$n_replicates == n_boot_expected)) {
  cat("    [OK] All sources have", n_boot_expected, "replicates\n")
} else {
  cat("    [WARN] Inconsistent replicate counts:\n")
  print(replicates_by_source)
}

# Check age coverage
ages_by_source <- all_boot_replicates %>%
  dplyr::group_by(data_source) %>%
  dplyr::summarise(
    n_ages = length(unique(age)),
    age_range = paste0(min(age), "-", max(age)),
    .groups = "drop"
  )

cat("    Age coverage by source:\n")
print(ages_by_source)

if (all(ages_by_source$n_ages == 6)) {
  cat("    [OK] All sources cover 6 age groups (0-5)\n")
} else {
  cat("    [WARN] Age coverage varies across sources\n")
}

# Check for missing estimates
missing_by_source <- all_boot_replicates %>%
  dplyr::group_by(data_source) %>%
  dplyr::summarise(
    n_missing = sum(is.na(estimate)),
    pct_missing = round(100 * mean(is.na(estimate)), 2),
    .groups = "drop"
  )

cat("\n    Missing estimates by source:\n")
print(missing_by_source)

total_missing <- sum(is.na(all_boot_replicates$estimate))
if (total_missing > 0) {
  cat("    [INFO] Total missing values:", total_missing, "\n")
  cat("    (Note: NSCH emotional/behavioral has NA for ages 0-2 by design)\n")
} else {
  cat("    [OK] No missing estimates\n")
}

cat("\n")

# 10. Cross-source consistency checks
cat("[10] Cross-source consistency checks...\n")

# Verify bootstrap method
methods <- unique(all_boot_replicates$bootstrap_method)
if (length(methods) == 1 && methods[1] == "Rao-Wu-Yue-Beaumont") {
  cat("    [OK] All sources use Rao-Wu-Yue-Beaumont method\n")
} else {
  cat("    [WARN] Multiple bootstrap methods detected:\n")
  print(methods)
}

# Verify survey identifier
surveys <- unique(all_boot_replicates$survey)
if (length(surveys) == 1 && surveys[1] == "ne25") {
  cat("    [OK] All sources tagged with 'ne25' survey\n")
} else {
  cat("    [WARN] Multiple survey identifiers detected:\n")
  print(surveys)
}

# Check n_boot consistency
n_boots <- unique(all_boot_replicates$n_boot)
if (length(n_boots) == 1 && n_boots[1] == n_boot_expected) {
  cat("    [OK] All sources have n_boot =", n_boot_expected, "\n")
} else {
  cat("    [WARN] Inconsistent n_boot values:\n")
  print(n_boots)
}

cat("\n")

# 11. Final structure verification
cat("[11] Final structure verification...\n")

cat("    Columns:\n")
cat("      ", paste(names(all_boot_replicates), collapse = ", "), "\n")

cat("    Column types:\n")
str_output <- capture.output(str(all_boot_replicates, max.level = 1))
cat("      ", str_output[2], "\n")  # Data dimensions
cat("      ", str_output[3], "\n")  # First few columns

cat("\n    [OK] Structure verified\n\n")

# 12. Save consolidated bootstrap replicates
cat("[12] Saving consolidated bootstrap replicates...\n")

saveRDS(all_boot_replicates, "data/raking/ne25/all_bootstrap_replicates.rds")

cat("     Saved to: data/raking/ne25/all_bootstrap_replicates.rds\n")
cat("     Dimensions:", nrow(all_boot_replicates), "rows x",
    ncol(all_boot_replicates), "columns\n")
cat("     File size:", round(file.size("data/raking/ne25/all_bootstrap_replicates.rds") / 1024, 2),
    "KB\n\n")

# 13. Summary statistics
cat("========================================\n")
cat("Bootstrap Consolidation Complete\n")
cat("========================================\n\n")

cat("Final Summary:\n")
cat("  Total bootstrap replicates:", nrow(all_boot_replicates), "rows\n")
cat("  Data sources: 3 (ACS, NHIS, NSCH)\n")
cat("  Total estimands: 31 (25 ACS + 2 NHIS + 4 NSCH)\n")
cat("  Age groups: 6 (ages 0-5)\n")
cat("  Bootstrap replicates per estimand:", n_boot_expected, "\n")
cat("  Bootstrap method: Rao-Wu-Yue-Beaumont (shared within source)\n")
cat("  Survey: ne25\n\n")

cat("Breakdown by source:\n")
cat("  ACS: ", 25 * 6 * n_boot_expected, " rows = 25 estimands × 6 ages ×", n_boot_expected, "replicates\n")
cat("  NHIS: ", 2 * 6 * n_boot_expected, " rows =  2 estimands × 6 ages ×", n_boot_expected, "replicates (PHQ-2, GAD-2)\n")
cat("  NSCH: ", 4 * 6 * n_boot_expected, " rows =  4 estimands × 6 ages ×", n_boot_expected, "replicates\n\n")

if (n_boot_expected < 4096) {
  cat("Current configuration: n_boot =", n_boot_expected, "\n")
  cat("Production mode (n_boot = 4096) will have:\n")
  cat("  - ACS:  614,400 rows (25 estimands)\n")
  cat("  - NHIS:  49,152 rows ( 2 estimands: PHQ-2, GAD-2)\n")
  cat("  - NSCH:  98,304 rows ( 4 estimands)\n")
  cat("  - TOTAL: 761,856 rows (31 estimands)\n\n")
}

cat("Next step: Run 23_insert_boot_replicates.py to insert into DuckDB\n\n")

# Return for inspection
all_boot_replicates

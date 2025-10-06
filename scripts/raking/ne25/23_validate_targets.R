# Phase 5, Task 5.5: Final Validation
# Perform comprehensive validation on consolidated raking targets
# Checks: completeness, range, consistency, age patterns

library(dplyr)

cat("\n========================================\n")
cat("Phase 5: Final Validation\n")
cat("========================================\n\n")

# 1. Load consolidated estimates
cat("[1] Loading consolidated estimates...\n")

all_estimates <- readRDS("data/raking/ne25/raking_targets_consolidated.rds")

cat("    Loaded:", nrow(all_estimates), "rows\n")
cat("    Columns:", ncol(all_estimates), "\n\n")

# 2. Completeness checks
cat("[2] Completeness Checks:\n")

# Check for missing values in key columns
key_columns <- c("target_id", "survey", "age_years", "estimand", "description",
                 "data_source", "estimator", "estimate")

completeness_results <- data.frame(
  column = key_columns,
  n_missing = sapply(key_columns, function(col) sum(is.na(all_estimates[[col]])))
)

cat("    Missing values by key column:\n")
print(completeness_results)

# Check for expected missing values (Emotional/Behavioral at ages 0-2)
expected_missing <- all_estimates %>%
  dplyr::filter(is.na(estimate)) %>%
  dplyr::select(target_id, age_years, estimand, data_source)

cat("\n    Expected missing values (Emotional/Behavioral ages 0-2):\n")
print(expected_missing)

# Flag any unexpected missing values
unexpected_missing <- all_estimates %>%
  dplyr::filter(is.na(estimate)) %>%
  dplyr::filter(!(estimand == "Emotional/Behavioral Problems" & age_years %in% 0:2))

if (nrow(unexpected_missing) > 0) {
  cat("\n    [ERROR] Unexpected missing values found:\n")
  print(unexpected_missing)
  stop("Validation failed: Unexpected missing values")
} else {
  cat("    [OK] No unexpected missing values\n")
}

cat("\n")

# 3. Range checks
cat("[3] Range Checks:\n")

# Estimates should be proportions (0-1)
range_summary <- all_estimates %>%
  dplyr::filter(!is.na(estimate)) %>%
  dplyr::summarise(
    min_estimate = min(estimate),
    max_estimate = max(estimate),
    mean_estimate = mean(estimate),
    median_estimate = median(estimate)
  )

cat("    Estimate range:\n")
print(range_summary)

# Check for out-of-range values
out_of_range <- all_estimates %>%
  dplyr::filter(!is.na(estimate)) %>%
  dplyr::filter(estimate < 0 | estimate > 1) %>%
  dplyr::select(target_id, age_years, estimand, data_source, estimate)

if (nrow(out_of_range) > 0) {
  cat("\n    [ERROR] Out-of-range estimates (should be 0-1):\n")
  print(out_of_range)
  stop("Validation failed: Out-of-range estimates")
} else {
  cat("    [OK] All estimates are valid proportions (0-1)\n")
}

cat("\n")

# 4. Consistency checks
cat("[4] Consistency Checks:\n")

# Check row counts by data source
row_counts <- all_estimates %>%
  dplyr::group_by(data_source) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    n_estimands = length(unique(estimand)),
    expected_rows = n_estimands * 6,
    .groups = "drop"
  )

cat("    Row counts by data source:\n")
print(row_counts)

# Verify each estimand appears exactly 6 times (once per age)
estimand_counts <- all_estimates %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(n_ages = dplyr::n(), .groups = "drop") %>%
  dplyr::filter(n_ages != 6)

if (nrow(estimand_counts) > 0) {
  cat("\n    [WARN] Some estimands don't appear exactly 6 times:\n")
  print(estimand_counts)
} else {
  cat("    [OK] All estimands appear exactly 6 times (ages 0-5)\n")
}

# Check for duplicate target_ids
duplicate_ids <- all_estimates %>%
  dplyr::group_by(target_id) %>%
  dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
  dplyr::filter(n > 1)

if (nrow(duplicate_ids) > 0) {
  cat("\n    [ERROR] Duplicate target_ids found:\n")
  print(duplicate_ids)
  stop("Validation failed: Duplicate target_ids")
} else {
  cat("    [OK] All target_ids are unique\n")
}

cat("\n")

# 5. Age pattern checks
cat("[5] Age Pattern Checks:\n")

# For each estimand, check if estimates vary sensibly across ages
# (we expect some variation, not identical values for all ages)

age_patterns <- all_estimates %>%
  dplyr::filter(!is.na(estimate)) %>%
  dplyr::group_by(estimand, data_source) %>%
  dplyr::summarise(
    n_ages = dplyr::n(),
    min_est = min(estimate),
    max_est = max(estimate),
    range = max_est - min_est,
    sd = sd(estimate),
    .groups = "drop"
  ) %>%
  dplyr::arrange(range)

cat("    Age variation by estimand (smallest to largest range):\n")
cat("    (First 10 and last 10)\n\n")

cat("    Smallest variation:\n")
print(head(age_patterns, 10))

cat("\n    Largest variation:\n")
print(tail(age_patterns, 10))

# Flag estimands with no variation (suspicious)
no_variation <- age_patterns %>%
  dplyr::filter(range == 0)

if (nrow(no_variation) > 0) {
  cat("\n    [WARN] Some estimands have identical estimates across all ages:\n")
  print(no_variation)
  cat("    This may be expected for some demographics (e.g., race/ethnicity)\n")
} else {
  cat("\n    [OK] All estimands show some variation across ages\n")
}

cat("\n")

# 6. Data source-specific checks
cat("[6] Data Source-Specific Checks:\n")

# ACS: Should have 25 estimands
acs_check <- all_estimates %>%
  dplyr::filter(data_source == "ACS") %>%
  dplyr::summarise(n_estimands = length(unique(estimand)))

cat("    ACS estimands:", acs_check$n_estimands, "(expected: 25)\n")

if (acs_check$n_estimands != 25) {
  cat("    [ERROR] ACS should have 25 estimands\n")
  stop("Validation failed: ACS estimand count")
}

# NHIS: Should have 1 estimand
nhis_check <- all_estimates %>%
  dplyr::filter(data_source == "NHIS") %>%
  dplyr::summarise(n_estimands = length(unique(estimand)))

cat("    NHIS estimands:", nhis_check$n_estimands, "(expected: 1)\n")

if (nhis_check$n_estimands != 1) {
  cat("    [ERROR] NHIS should have 1 estimand\n")
  stop("Validation failed: NHIS estimand count")
}

# NSCH: Should have 4 estimands
nsch_check <- all_estimates %>%
  dplyr::filter(data_source == "NSCH") %>%
  dplyr::summarise(n_estimands = length(unique(estimand)))

cat("    NSCH estimands:", nsch_check$n_estimands, "(expected: 4)\n")

if (nsch_check$n_estimands != 4) {
  cat("    [ERROR] NSCH should have 4 estimands\n")
  stop("Validation failed: NSCH estimand count")
}

cat("    [OK] All data sources have correct estimand counts\n\n")

# 7. Summary statistics by data source
cat("[7] Summary Statistics by Data Source:\n\n")

summary_stats <- all_estimates %>%
  dplyr::filter(!is.na(estimate)) %>%
  dplyr::group_by(data_source) %>%
  dplyr::summarise(
    n_rows = dplyr::n(),
    min_est = min(estimate),
    q25_est = quantile(estimate, 0.25),
    median_est = median(estimate),
    q75_est = quantile(estimate, 0.75),
    max_est = max(estimate),
    mean_est = mean(estimate),
    sd_est = sd(estimate),
    .groups = "drop"
  )

print(summary_stats)

cat("\n")

# 8. Final summary
cat("[8] Final Validation Summary:\n")
cat("    Total rows:", nrow(all_estimates), "\n")
cat("    Total estimands:", length(unique(all_estimates$estimand)), "\n")
cat("    Data sources:", paste(unique(all_estimates$data_source), collapse = ", "), "\n")
cat("    Missing estimates:", sum(is.na(all_estimates$estimate)),
    "(expected: 3, Emotional/Behavioral ages 0-2)\n")
cat("    Estimate range: [",
    round(min(all_estimates$estimate, na.rm = TRUE), 4), ", ",
    round(max(all_estimates$estimate, na.rm = TRUE), 4), "]\n", sep = "")
cat("    All validations passed: YES\n\n")

cat("========================================\n")
cat("Task 5.5 Complete\n")
cat("========================================\n\n")

# Return validation results
list(
  completeness = completeness_results,
  range = range_summary,
  row_counts = row_counts,
  age_patterns = age_patterns,
  summary_stats = summary_stats
)

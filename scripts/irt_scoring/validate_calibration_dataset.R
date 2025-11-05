# =============================================================================
# Validate Calibration Dataset Against Update-KidsightsPublic
# =============================================================================
# Purpose: Compare our new calibration dataset with the original from
#          Update-KidsightsPublic to verify consistency and identify discrepancies
#
# Compares:
#   - Record counts by study (NE20, NE22, USA24)
#   - Item coverage patterns
#   - Data structure and formatting
#   - Spot-check individual records
# =============================================================================

library(duckdb)
library(dplyr)
library(KidsightsPublic)

cat("\n")
cat(strrep("=", 80), "\n")
cat("CALIBRATION DATASET VALIDATION\n")
cat(strrep("=", 80), "\n\n")

# =============================================================================
# Step 1: Load Original Data from KidsightsPublic
# =============================================================================

cat("Step 1: Loading original calibdat from KidsightsPublic package\n")
cat(strrep("-", 80), "\n")

# Load original calibration dataset
data(calibdat, package = "KidsightsPublic")

# Derive study column from ID ranges (same logic as import script)
calibdat_original <- calibdat %>%
  dplyr::mutate(
    study = dplyr::case_when(
      id < 0 ~ "NE22",
      id >= 990000 & id <= 991695 ~ "USA24",
      .default = "NE20"
    )
  )

# Filter to historical studies only (exclude any NE25/NSCH)
calibdat_original <- calibdat_original %>%
  dplyr::filter(study %in% c("NE20", "NE22", "USA24"))

cat(sprintf("  Loaded %d total records from KidsightsPublic\n", nrow(calibdat_original)))

# Study breakdown
original_counts <- calibdat_original %>%
  dplyr::group_by(study) %>%
  dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
  dplyr::arrange(study)

cat("\n  Study breakdown (original):\n")
for (i in 1:nrow(original_counts)) {
  cat(sprintf("    %6s: %6d records\n",
              original_counts$study[i],
              original_counts$n[i]))
}

cat(sprintf("\n  Total items: %d columns\n", ncol(calibdat_original) - 3))
cat("\n")

# =============================================================================
# Step 2: Load New Data from DuckDB
# =============================================================================

cat("Step 2: Loading new calibration dataset from DuckDB\n")
cat(strrep("-", 80), "\n")

db_path <- "data/duckdb/kidsights_local.duckdb"
conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

# Load our new historical calibration data
calibdat_new <- DBI::dbGetQuery(conn,
  "SELECT * FROM historical_calibration_2020_2024")

DBI::dbDisconnect(conn)

cat(sprintf("  Loaded %d total records from DuckDB\n", nrow(calibdat_new)))

# Study breakdown
new_counts <- calibdat_new %>%
  dplyr::group_by(study) %>%
  dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
  dplyr::arrange(study)

cat("\n  Study breakdown (new):\n")
for (i in 1:nrow(new_counts)) {
  cat(sprintf("    %6s: %6d records\n",
              new_counts$study[i],
              new_counts$n[i]))
}

cat(sprintf("\n  Total items: %d columns\n", ncol(calibdat_new) - 3))
cat("\n")

# =============================================================================
# Step 3: Compare Record Counts by Study
# =============================================================================

cat("Step 3: Comparing record counts by study\n")
cat(strrep("-", 80), "\n\n")

# Join counts for comparison
count_comparison <- dplyr::full_join(
  original_counts %>% dplyr::rename(original = n),
  new_counts %>% dplyr::rename(new = n),
  by = "study"
)

count_comparison <- count_comparison %>%
  dplyr::mutate(
    difference = new - original,
    pct_diff = (difference / original) * 100
  )

cat("  Record count comparison:\n\n")
cat(sprintf("  %-10s %10s %10s %10s %10s\n",
            "Study", "Original", "New", "Diff", "% Diff"))
cat(sprintf("  %s\n", strrep("-", 55)))

for (i in 1:nrow(count_comparison)) {
  cat(sprintf("  %-10s %10d %10d %10d %9.1f%%\n",
              count_comparison$study[i],
              count_comparison$original[i],
              count_comparison$new[i],
              count_comparison$difference[i],
              count_comparison$pct_diff[i]))
}

# Check if counts match
if (all(count_comparison$difference == 0, na.rm = TRUE)) {
  cat("\n  [OK] All study record counts match exactly\n")
} else {
  cat("\n  [WARN] Record count discrepancies found\n")
}

cat("\n")

# =============================================================================
# Step 4: Compare Item Coverage
# =============================================================================

cat("Step 4: Comparing item coverage patterns\n")
cat(strrep("-", 80), "\n\n")

# Get item columns (exclude metadata)
metadata_cols <- c("study", "id", "years")

original_items <- setdiff(names(calibdat_original), metadata_cols)
new_items <- setdiff(names(calibdat_new), metadata_cols)

cat(sprintf("  Original dataset items: %d\n", length(original_items)))
cat(sprintf("  New dataset items: %d\n", length(new_items)))

# Find items in original but not in new
missing_items <- setdiff(original_items, new_items)
if (length(missing_items) > 0) {
  cat(sprintf("\n  [WARN] Items in original but missing in new: %d\n",
              length(missing_items)))
  cat("    ", paste(head(missing_items, 10), collapse = ", "), "\n")
  if (length(missing_items) > 10) {
    cat(sprintf("    ... and %d more\n", length(missing_items) - 10))
  }
} else {
  cat("\n  [OK] All original items present in new dataset\n")
}

# Find items in new but not in original
extra_items <- setdiff(new_items, original_items)
if (length(extra_items) > 0) {
  cat(sprintf("\n  [INFO] Items in new but not in original: %d\n",
              length(extra_items)))
  cat("    ", paste(head(extra_items, 10), collapse = ", "), "\n")
  if (length(extra_items) > 10) {
    cat(sprintf("    ... and %d more\n", length(extra_items) - 10))
  }
} else {
  cat("\n  [OK] No extra items in new dataset\n")
}

# Items in common
common_items <- intersect(original_items, new_items)
cat(sprintf("\n  Items in common: %d\n", length(common_items)))

cat("\n")

# =============================================================================
# Step 5: Compare Item Missingness Patterns
# =============================================================================

cat("Step 5: Comparing item missingness patterns\n")
cat(strrep("-", 80), "\n\n")

# Calculate missingness for common items
if (length(common_items) > 0) {

  # Original missingness
  original_missing <- sapply(calibdat_original[common_items],
                             function(x) sum(is.na(x)) / length(x) * 100)

  # New missingness
  new_missing <- sapply(calibdat_new[common_items],
                        function(x) sum(is.na(x)) / length(x) * 100)

  # Calculate differences
  missing_diff <- new_missing - original_missing

  # Summary statistics
  cat("  Missingness comparison (for common items):\n\n")
  cat(sprintf("  Original: %.1f%% - %.1f%% (median: %.1f%%)\n",
              min(original_missing), max(original_missing), median(original_missing)))
  cat(sprintf("  New:      %.1f%% - %.1f%% (median: %.1f%%)\n",
              min(new_missing), max(new_missing), median(new_missing)))

  # Items with significant differences (>5% change in missingness)
  sig_diff_items <- names(missing_diff)[abs(missing_diff) > 5]

  if (length(sig_diff_items) > 0) {
    cat(sprintf("\n  [WARN] Items with >5%% missingness difference: %d\n",
                length(sig_diff_items)))

    # Show top 10 by difference
    top_diffs <- sort(abs(missing_diff), decreasing = TRUE)[1:min(10, length(sig_diff_items))]
    cat("\n  Top differences:\n")
    for (item_name in names(top_diffs)) {
      cat(sprintf("    %10s: Original %.1f%%, New %.1f%%, Diff %+.1f%%\n",
                  item_name,
                  original_missing[item_name],
                  new_missing[item_name],
                  missing_diff[item_name]))
    }
  } else {
    cat("\n  [OK] No significant missingness differences (all <5%)\n")
  }

} else {
  cat("  [SKIP] No common items to compare\n")
}

cat("\n")

# =============================================================================
# Step 6: Spot-Check Individual Records
# =============================================================================

cat("Step 6: Spot-checking individual records\n")
cat(strrep("-", 80), "\n\n")

# Sample 5 random IDs from each study
set.seed(2025)

for (study_name in c("NE20", "NE22", "USA24")) {

  cat(sprintf("  %s spot-check:\n", study_name))

  # Get IDs from both datasets
  original_ids <- calibdat_original %>%
    dplyr::filter(study == study_name) %>%
    dplyr::pull(id)

  new_ids <- calibdat_new %>%
    dplyr::filter(study == study_name) %>%
    dplyr::pull(id)

  # Find common IDs
  common_ids <- intersect(original_ids, new_ids)

  if (length(common_ids) == 0) {
    cat("    [WARN] No common IDs found between datasets\n\n")
    next
  }

  # Sample up to 5 IDs
  sample_ids <- sample(common_ids, min(5, length(common_ids)))

  # Check if data matches for these IDs
  matches <- 0
  mismatches <- 0

  for (check_id in sample_ids) {
    # Get records
    original_rec <- calibdat_original %>%
      dplyr::filter(id == check_id) %>%
      dplyr::select(dplyr::all_of(c("id", "years", common_items[1:10])))  # Check first 10 items

    new_rec <- calibdat_new %>%
      dplyr::filter(id == check_id) %>%
      dplyr::select(dplyr::all_of(c("id", "years", common_items[1:10])))

    # Compare
    if (nrow(original_rec) > 0 && nrow(new_rec) > 0) {
      if (identical(as.data.frame(original_rec), as.data.frame(new_rec))) {
        matches <- matches + 1
      } else {
        mismatches <- mismatches + 1
      }
    }
  }

  cat(sprintf("    Checked %d records: %d matches, %d mismatches\n",
              length(sample_ids), matches, mismatches))

  if (mismatches > 0) {
    cat("    [WARN] Some records do not match exactly\n")
  }

  cat("\n")
}

# =============================================================================
# Step 7: Overall Assessment
# =============================================================================

cat(strrep("=", 80), "\n")
cat("VALIDATION SUMMARY\n")
cat(strrep("=", 80), "\n\n")

# Determine overall status
issues <- c()

if (!all(count_comparison$difference == 0, na.rm = TRUE)) {
  issues <- c(issues, "Record count discrepancies")
}

if (length(missing_items) > 0) {
  issues <- c(issues, sprintf("%d items missing from new dataset", length(missing_items)))
}

if (length(sig_diff_items) > 0) {
  issues <- c(issues, sprintf("%d items with >5%% missingness difference", length(sig_diff_items)))
}

if (length(issues) == 0) {
  cat("[OK] VALIDATION PASSED\n\n")
  cat("The new calibration dataset matches the original KidsightsPublic data\n")
  cat("for historical studies (NE20, NE22, USA24).\n\n")
  cat("Ready for production use.\n")
} else {
  cat("[REVIEW NEEDED] Issues found:\n\n")
  for (issue in issues) {
    cat(sprintf("  - %s\n", issue))
  }
  cat("\nReview discrepancies above before proceeding to production.\n")
}

cat("\n")
cat(strrep("=", 80), "\n\n")

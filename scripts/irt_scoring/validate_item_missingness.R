# =============================================================================
# Validate Item Missingness Patterns in Calibration Dataset
# =============================================================================
# Purpose: Analyze missingness patterns across all studies with special
#          focus on NE25 item coverage
#
# Validates:
#   - Overall missingness patterns across all studies
#   - NE25-specific item coverage
#   - Comparison of missingness by study
#   - Expected vs actual coverage
# =============================================================================

library(duckdb)
library(dplyr)
library(tidyr)

cat("\n")
cat(strrep("=", 80), "\n")
cat("ITEM MISSINGNESS PATTERN VALIDATION\n")
cat(strrep("=", 80), "\n\n")

# =============================================================================
# Step 1: Load Complete Calibration Dataset
# =============================================================================

cat("Step 1: Loading complete calibration dataset\n")
cat(strrep("-", 80), "\n")

db_path <- "data/duckdb/kidsights_local.duckdb"
conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

# Load complete dataset with all studies
calibdat <- DBI::dbGetQuery(conn,
  "SELECT * FROM calibration_dataset_2020_2025")

DBI::dbDisconnect(conn)

cat(sprintf("  Loaded %d records from %d studies\n",
            nrow(calibdat),
            length(unique(calibdat$study))))

# Get item columns
metadata_cols <- c("study", "study_num", "id", "years")
item_cols <- setdiff(names(calibdat), metadata_cols)

cat(sprintf("  Total items: %d\n\n", length(item_cols)))

# =============================================================================
# Step 2: Overall Missingness Patterns
# =============================================================================

cat("Step 2: Analyzing overall missingness patterns\n")
cat(strrep("-", 80), "\n\n")

# Calculate missingness per item across all studies
overall_missing <- sapply(calibdat[item_cols],
                          function(x) sum(is.na(x)) / length(x) * 100)

cat("  Overall item missingness (all studies combined):\n")
cat(sprintf("    Min:    %5.1f%%\n", min(overall_missing)))
cat(sprintf("    Q1:     %5.1f%%\n", quantile(overall_missing, 0.25)))
cat(sprintf("    Median: %5.1f%%\n", median(overall_missing)))
cat(sprintf("    Q3:     %5.1f%%\n", quantile(overall_missing, 0.75)))
cat(sprintf("    Max:    %5.1f%%\n", max(overall_missing)))

# Items with complete data
complete_items <- names(overall_missing)[overall_missing == 0]
cat(sprintf("\n  Items with 0%% missing: %d of %d (%.1f%%)\n",
            length(complete_items),
            length(item_cols),
            (length(complete_items) / length(item_cols)) * 100))

# Items with >95% missing
sparse_items <- names(overall_missing)[overall_missing > 95]
cat(sprintf("  Items with >95%% missing: %d of %d (%.1f%%)\n",
            length(sparse_items),
            length(item_cols),
            (length(sparse_items) / length(item_cols)) * 100))

cat("\n")

# =============================================================================
# Step 3: Missingness by Study
# =============================================================================

cat("Step 3: Analyzing missingness by study\n")
cat(strrep("-", 80), "\n\n")

studies <- sort(unique(calibdat$study))

# Calculate missingness for each study
study_missingness <- data.frame(study = character(),
                                  n_records = integer(),
                                  mean_missing = numeric(),
                                  median_missing = numeric(),
                                  stringsAsFactors = FALSE)

for (study_name in studies) {
  study_data <- calibdat %>% dplyr::filter(study == study_name)
  study_items <- study_data[item_cols]

  item_missing <- sapply(study_items, function(x) sum(is.na(x)) / length(x) * 100)

  study_missingness <- rbind(study_missingness,
                              data.frame(
                                study = study_name,
                                n_records = nrow(study_data),
                                mean_missing = mean(item_missing),
                                median_missing = median(item_missing),
                                stringsAsFactors = FALSE
                              ))
}

cat("  Missingness summary by study:\n\n")
cat(sprintf("  %-10s %10s %15s %15s\n",
            "Study", "Records", "Mean Missing", "Median Missing"))
cat(sprintf("  %s\n", strrep("-", 55)))

for (i in 1:nrow(study_missingness)) {
  cat(sprintf("  %-10s %10d %14.1f%% %14.1f%%\n",
              study_missingness$study[i],
              study_missingness$n_records[i],
              study_missingness$mean_missing[i],
              study_missingness$median_missing[i]))
}

cat("\n")

# =============================================================================
# Step 4: NE25-Specific Item Coverage
# =============================================================================

cat("Step 4: Analyzing NE25 item coverage\n")
cat(strrep("-", 80), "\n\n")

ne25_data <- calibdat %>% dplyr::filter(study == "NE25")

if (nrow(ne25_data) == 0) {
  cat("  [WARN] No NE25 records found in dataset\n\n")
} else {
  cat(sprintf("  NE25 records: %d\n\n", nrow(ne25_data)))

  # Calculate missingness for NE25
  ne25_missing <- sapply(ne25_data[item_cols],
                         function(x) sum(is.na(x)) / length(x) * 100)

  cat("  NE25 item missingness distribution:\n")
  cat(sprintf("    Min:    %5.1f%%\n", min(ne25_missing)))
  cat(sprintf("    Q1:     %5.1f%%\n", quantile(ne25_missing, 0.25)))
  cat(sprintf("    Median: %5.1f%%\n", median(ne25_missing)))
  cat(sprintf("    Q3:     %5.1f%%\n", quantile(ne25_missing, 0.75)))
  cat(sprintf("    Max:    %5.1f%%\n", max(ne25_missing)))

  # Items with substantial coverage in NE25 (<50% missing)
  ne25_covered <- names(ne25_missing)[ne25_missing < 50]
  cat(sprintf("\n  NE25 items with <50%% missing: %d of %d (%.1f%%)\n",
              length(ne25_covered),
              length(item_cols),
              (length(ne25_covered) / length(item_cols)) * 100))

  # Items with good coverage (<20% missing)
  ne25_good <- names(ne25_missing)[ne25_missing < 20]
  cat(sprintf("  NE25 items with <20%% missing: %d of %d (%.1f%%)\n",
              length(ne25_good),
              length(item_cols),
              (length(ne25_good) / length(item_cols)) * 100))

  # Items with complete data
  ne25_complete <- names(ne25_missing)[ne25_missing == 0]
  cat(sprintf("  NE25 items with 0%% missing: %d of %d (%.1f%%)\n",
              length(ne25_complete),
              length(item_cols),
              (length(ne25_complete) / length(item_cols)) * 100))

  # Show top 20 items with best coverage in NE25
  ne25_top <- sort(ne25_missing)[1:min(20, length(ne25_missing))]
  cat("\n  Top 20 items by NE25 coverage (lowest missingness):\n\n")
  cat(sprintf("  %-15s %10s\n", "Item", "Missing"))
  cat(sprintf("  %s\n", strrep("-", 30)))

  for (i in 1:length(ne25_top)) {
    cat(sprintf("  %-15s %9.1f%%\n",
                names(ne25_top)[i],
                ne25_top[i]))
  }
}

cat("\n")

# =============================================================================
# Step 5: Expected vs Actual Coverage
# =============================================================================

cat("Step 5: Validating expected coverage patterns\n")
cat(strrep("-", 80), "\n\n")

# Expected patterns based on study design
cat("  Expected patterns:\n")
cat("    - Historical studies (NE20, NE22, USA24): Broad coverage of development items\n")
cat("    - NE25: Focused coverage matching ne25 lexicon in codebook\n")
cat("    - NSCH: National benchmarking items only\n\n")

# Load codebook to check expected NE25 items
codebook <- jsonlite::fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)

ne25_expected_items <- c()
for (item_id in names(codebook$items)) {
  item <- codebook$items[[item_id]]
  if (!is.null(item$lexicons$ne25) && nchar(item$lexicons$ne25) > 0) {
    ne25_expected_items <- c(ne25_expected_items, toupper(item$lexicons$equate))
  }
}

cat(sprintf("  Expected NE25 items (from codebook): %d\n", length(ne25_expected_items)))

# Check which expected items are in dataset
ne25_expected_in_data <- intersect(ne25_expected_items, item_cols)
cat(sprintf("  Expected items present in dataset: %d of %d (%.1f%%)\n",
            length(ne25_expected_in_data),
            length(ne25_expected_items),
            (length(ne25_expected_in_data) / length(ne25_expected_items)) * 100))

# Check coverage of expected items in NE25 data
if (nrow(ne25_data) > 0 && length(ne25_expected_in_data) > 0) {
  ne25_expected_missing <- sapply(ne25_data[ne25_expected_in_data],
                                   function(x) sum(is.na(x)) / length(x) * 100)

  cat(sprintf("\n  Coverage of expected NE25 items:\n"))
  cat(sprintf("    Items with <50%% missing: %d of %d (%.1f%%)\n",
              sum(ne25_expected_missing < 50),
              length(ne25_expected_missing),
              (sum(ne25_expected_missing < 50) / length(ne25_expected_missing)) * 100))
  cat(sprintf("    Items with <20%% missing: %d of %d (%.1f%%)\n",
              sum(ne25_expected_missing < 20),
              length(ne25_expected_missing),
              (sum(ne25_expected_missing < 20) / length(ne25_expected_missing)) * 100))
  cat(sprintf("    Items with 0%% missing: %d of %d (%.1f%%)\n",
              sum(ne25_expected_missing == 0),
              length(ne25_expected_missing),
              (sum(ne25_expected_missing == 0) / length(ne25_expected_missing)) * 100))
}

cat("\n")

# =============================================================================
# Step 6: Overall Assessment
# =============================================================================

cat(strrep("=", 80), "\n")
cat("MISSINGNESS VALIDATION SUMMARY\n")
cat(strrep("=", 80), "\n\n")

issues <- c()

# Check if NE25 has reasonable coverage
if (nrow(ne25_data) == 0) {
  issues <- c(issues, "No NE25 records in dataset")
} else if (length(ne25_good) < 10) {
  issues <- c(issues, sprintf("Only %d NE25 items with good coverage (<20%% missing)", length(ne25_good)))
}

# Check if overall missingness is reasonable
if (median(overall_missing) > 99) {
  issues <- c(issues, "Extremely high overall missingness (median >99%)")
}

if (length(issues) == 0) {
  cat("[OK] MISSINGNESS VALIDATION PASSED\n\n")
  cat("Missingness patterns are as expected:\n")
  cat(sprintf("  - %d total records across %d studies\n",
              nrow(calibdat), length(unique(calibdat$study))))
  cat(sprintf("  - %d NE25 records with coverage of %d items\n",
              nrow(ne25_data), length(ne25_good)))
  cat("  - High overall missingness expected (different studies measure different items)\n\n")
  cat("Ready for IRT calibration.\n")
} else {
  cat("[REVIEW NEEDED] Issues found:\n\n")
  for (issue in issues) {
    cat(sprintf("  - %s\n", issue))
  }
}

cat("\n")
cat(strrep("=", 80), "\n\n")

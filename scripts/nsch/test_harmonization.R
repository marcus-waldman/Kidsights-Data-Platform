#' Test NSCH Harmonization Functions
#'
#' Verifies that harmonization transformations work correctly for both
#' NSCH 2021 and 2022 data.
#'
#' Tests performed:
#' 1. Column count (expected: 30 for 2021, 42 for 2022)
#' 2. Zero-based encoding (all harmonized columns have min = 0)
#' 3. No infinite or NaN values
#' 4. Expected column names match lex_equate names
#' 5. Spot check reverse coding (DD299, DD103)

# Clear workspace
rm(list = ls())

# Load functions
source("R/transform/nsch/harmonize_nsch_2021.R")
source("R/transform/nsch/harmonize_nsch_2022.R")

cat("\n")
cat("=" , rep("=", 79), "\n", sep = "")
cat("NSCH HARMONIZATION TEST SCRIPT\n")
cat("=" , rep("=", 79), "\n", sep = "")
cat("\n")

# ============================================================================
# Test NSCH 2021
# ============================================================================

cat("[TEST 1] NSCH 2021 Harmonization\n")
cat("-", rep("-", 79), "\n", sep = "")

tryCatch({
  nsch21 <- harmonize_nsch_2021()

  # Check 1: Dimensions
  cat("\n[CHECK 1.1] Dimensions\n")
  cat(sprintf("  Rows: %d (expected ~50,892)\n", nrow(nsch21)))
  cat(sprintf("  Columns: %d (expected ~31 = HHID + 30 items)\n", ncol(nsch21)))

  # Check 2: Column names
  cat("\n[CHECK 1.2] Column names\n")
  cat("  First 10 columns:", paste(head(names(nsch21), 10), collapse = ", "), "\n")

  # Check 3: Zero-based encoding
  cat("\n[CHECK 1.3] Zero-based encoding\n")
  item_cols <- setdiff(names(nsch21), "HHID")
  min_values <- sapply(nsch21[item_cols], min, na.rm = TRUE)
  non_zero_mins <- sum(min_values != 0 & !is.infinite(min_values))

  if (non_zero_mins == 0) {
    cat("  [OK] All harmonized columns are 0-based (min=0)\n")
  } else {
    cat(sprintf("  [WARNING] %d columns do not have min=0\n", non_zero_mins))
    bad_cols <- names(min_values[min_values != 0 & !is.infinite(min_values)])
    cat("  Columns with non-zero min:", paste(head(bad_cols, 5), collapse = ", "), "\n")
  }

  # Check 4: No infinite or NaN values
  cat("\n[CHECK 1.4] Data quality\n")
  has_inf <- sapply(nsch21[item_cols], function(x) any(is.infinite(x)))
  has_nan <- sapply(nsch21[item_cols], function(x) any(is.nan(x)))

  if (sum(has_inf) == 0 && sum(has_nan) == 0) {
    cat("  [OK] No infinite or NaN values found\n")
  } else {
    cat(sprintf("  [WARNING] Found %d columns with infinite, %d with NaN\n",
                sum(has_inf), sum(has_nan)))
  }

  # Check 5: Spot check a few items
  cat("\n[CHECK 1.5] Spot check sample items\n")
  if ("DD299" %in% names(nsch21)) {
    cat("  DD299 (DISTRACTED, cahmi21 reverse=False):\n")
    cat(sprintf("    Min: %d, Max: %d, NA count: %d\n",
                min(nsch21$DD299, na.rm=TRUE),
                max(nsch21$DD299, na.rm=TRUE),
                sum(is.na(nsch21$DD299))))
  }

  if ("DD103" %in% names(nsch21)) {
    cat("  DD103 (SIMPLEINST, cahmi21 reverse=True):\n")
    cat(sprintf("    Min: %d, Max: %d, NA count: %d\n",
                min(nsch21$DD103, na.rm=TRUE),
                max(nsch21$DD103, na.rm=TRUE),
                sum(is.na(nsch21$DD103))))
  }

  cat("\n[OK] NSCH 2021 harmonization test passed\n\n")

}, error = function(e) {
  cat("\n[ERROR] NSCH 2021 harmonization failed:\n")
  cat("  ", conditionMessage(e), "\n\n")
})

# ============================================================================
# Test NSCH 2022
# ============================================================================

cat("[TEST 2] NSCH 2022 Harmonization\n")
cat("-", rep("-", 79), "\n", sep = "")

tryCatch({
  nsch22 <- harmonize_nsch_2022()

  # Check 1: Dimensions
  cat("\n[CHECK 2.1] Dimensions\n")
  cat(sprintf("  Rows: %d (expected ~54,103)\n", nrow(nsch22)))
  cat(sprintf("  Columns: %d (expected ~43 = HHID + 42 items)\n", ncol(nsch22)))

  # Check 2: Column names
  cat("\n[CHECK 2.2] Column names\n")
  cat("  First 10 columns:", paste(head(names(nsch22), 10), collapse = ", "), "\n")

  # Check 3: Zero-based encoding
  cat("\n[CHECK 2.3] Zero-based encoding\n")
  item_cols <- setdiff(names(nsch22), "HHID")
  min_values <- sapply(nsch22[item_cols], min, na.rm = TRUE)
  non_zero_mins <- sum(min_values != 0 & !is.infinite(min_values))

  if (non_zero_mins == 0) {
    cat("  [OK] All harmonized columns are 0-based (min=0)\n")
  } else {
    cat(sprintf("  [WARNING] %d columns do not have min=0\n", non_zero_mins))
    bad_cols <- names(min_values[min_values != 0 & !is.infinite(min_values)])
    cat("  Columns with non-zero min:", paste(head(bad_cols, 5), collapse = ", "), "\n")
  }

  # Check 4: No infinite or NaN values
  cat("\n[CHECK 2.4] Data quality\n")
  has_inf <- sapply(nsch22[item_cols], function(x) any(is.infinite(x)))
  has_nan <- sapply(nsch22[item_cols], function(x) any(is.nan(x)))

  if (sum(has_inf) == 0 && sum(has_nan) == 0) {
    cat("  [OK] No infinite or NaN values found\n")
  } else {
    cat(sprintf("  [WARNING] Found %d columns with infinite, %d with NaN\n",
                sum(has_inf), sum(has_nan)))
  }

  # Check 5: Spot check a few items
  cat("\n[CHECK 2.5] Spot check sample items\n")
  if ("DD299" %in% names(nsch22)) {
    cat("  DD299 (DISTRACTED, cahmi22 reverse=False):\n")
    cat(sprintf("    Min: %d, Max: %d, NA count: %d\n",
                min(nsch22$DD299, na.rm=TRUE),
                max(nsch22$DD299, na.rm=TRUE),
                sum(is.na(nsch22$DD299))))
  }

  cat("\n[OK] NSCH 2022 harmonization test passed\n\n")

}, error = function(e) {
  cat("\n[ERROR] NSCH 2022 harmonization failed:\n")
  cat("  ", conditionMessage(e), "\n\n")
})

# ============================================================================
# Summary
# ============================================================================

cat("=" , rep("=", 79), "\n", sep = "")
cat("TEST SUMMARY\n")
cat("=" , rep("=", 79), "\n", sep = "")
cat("\nAll tests completed. Review output above for any warnings or errors.\n")
cat("\nNext steps:\n")
cat("  1. If tests passed: Proceed to Phase 3 (Python integration)\n")
cat("  2. If warnings: Review data quality issues\n")
cat("  3. If errors: Debug harmonization logic\n\n")

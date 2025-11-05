# =============================================================================
# Validate Calibration Tables
# =============================================================================
# Purpose: Validate study-specific calibration tables
#
# Tests:
#   - All 6 study tables exist
#   - Record counts are reasonable
#   - Age ranges are appropriate
#   - Item coverage is sufficient
#   - No duplicate IDs within studies
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("VALIDATE CALIBRATION TABLES\n")
cat(strrep("=", 80), "\n\n")

# =============================================================================
# Load Dependencies
# =============================================================================

cat("[SETUP] Loading required packages\n")

required_packages <- c("duckdb", "dplyr")

for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Package '%s' is required. Install with: install.packages('%s')",
                 pkg, pkg))
  }
}

library(duckdb)
library(dplyr)

cat("        Packages loaded successfully\n\n")

# =============================================================================
# Connect to Database
# =============================================================================

cat("[SETUP] Connecting to DuckDB database\n")

db_path <- "data/duckdb/kidsights_local.duckdb"

if (!file.exists(db_path)) {
  stop(sprintf("Database not found at: %s", db_path))
}

conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
cat(sprintf("        Connected to: %s\n\n", db_path))

# =============================================================================
# Test 1: Table Existence
# =============================================================================

cat(strrep("=", 80), "\n")
cat("TEST 1: TABLE EXISTENCE\n")
cat(strrep("=", 80), "\n\n")

expected_tables <- c(
  "ne20_calibration",
  "ne22_calibration",
  "ne25_calibration",
  "nsch21_calibration",
  "nsch22_calibration",
  "usa24_calibration"
)

existing_tables <- DBI::dbListTables(conn)

cat("Checking for required calibration tables:\n\n")

all_exist <- TRUE
for (table in expected_tables) {
  exists <- table %in% existing_tables
  status <- ifelse(exists, "[OK]", "[MISSING]")
  cat(sprintf("  %s: %s\n", table, status))
  if (!exists) all_exist <- FALSE
}

cat("\n")
if (all_exist) {
  cat("[OK] TEST 1 PASSED: All calibration tables exist\n\n")
} else {
  cat("[FAIL] TEST 1 FAILED: Some tables are missing\n")
  cat("       Run: scripts/irt_scoring/create_calibration_tables.R\n\n")
  DBI::dbDisconnect(conn)
  stop("Cannot continue validation without all tables")
}

# =============================================================================
# Test 2: Record Counts
# =============================================================================

cat(strrep("=", 80), "\n")
cat("TEST 2: RECORD COUNTS\n")
cat(strrep("=", 80), "\n\n")

expected_counts <- list(
  "ne20_calibration" = c(min = 35000, max = 40000),
  "ne22_calibration" = c(min = 2000, max = 3000),
  "ne25_calibration" = c(min = 3000, max = 5000),
  "nsch21_calibration" = c(min = 40000, max = 60000),
  "nsch22_calibration" = c(min = 40000, max = 60000),
  "usa24_calibration" = c(min = 1500, max = 2000)
)

cat("Record counts by study:\n\n")

counts_ok <- TRUE
total_records <- 0

for (table in expected_tables) {
  count <- DBI::dbGetQuery(conn,
    sprintf("SELECT COUNT(*) as n FROM %s", table))$n

  expected <- expected_counts[[table]]
  in_range <- count >= expected["min"] && count <= expected["max"]
  status <- ifelse(in_range, "[OK]", "[WARN]")

  cat(sprintf("  %s: %s records %s\n", table, format(count, big.mark = ","), status))
  if (!in_range) {
    cat(sprintf("    Expected: %s - %s\n",
                format(expected["min"], big.mark = ","),
                format(expected["max"], big.mark = ",")))
    counts_ok <- FALSE
  }

  total_records <- total_records + count
}

cat(sprintf("\n  Total: %s records\n", format(total_records, big.mark = ",")))

cat("\n")
if (counts_ok) {
  cat("[OK] TEST 2 PASSED: All record counts in expected ranges\n\n")
} else {
  cat("[WARN] TEST 2 WARNING: Some counts outside expected ranges\n\n")
}

# =============================================================================
# Test 3: Age Ranges
# =============================================================================

cat(strrep("=", 80), "\n")
cat("TEST 3: AGE RANGES\n")
cat(strrep("=", 80), "\n\n")

cat("Age distributions by study:\n\n")

ages_ok <- TRUE

for (table in expected_tables) {
  age_summary <- DBI::dbGetQuery(conn,
    sprintf("SELECT MIN(years) as min, AVG(years) as mean, MAX(years) as max FROM %s",
            table))

  cat(sprintf("  %s:\n", table))
  cat(sprintf("    Min: %.2f years\n", age_summary$min))
  cat(sprintf("    Mean: %.2f years\n", age_summary$mean))
  cat(sprintf("    Max: %.2f years\n", age_summary$max))

  # Check for reasonable ranges
  if (age_summary$min < 0 || age_summary$max > 18) {
    cat("    [WARN] Age range outside expected bounds (0-18 years)\n")
    ages_ok <- FALSE
  } else {
    cat("    [OK] Age range appropriate\n")
  }
  cat("\n")
}

if (ages_ok) {
  cat("[OK] TEST 3 PASSED: All age ranges are appropriate\n\n")
} else {
  cat("[WARN] TEST 3 WARNING: Some age ranges outside bounds\n\n")
}

# =============================================================================
# Test 4: Item Coverage
# =============================================================================

cat(strrep("=", 80), "\n")
cat("TEST 4: ITEM COVERAGE\n")
cat(strrep("=", 80), "\n\n")

cat("Item counts by study (columns excluding id, years):\n\n")

coverage_ok <- TRUE

for (table in expected_tables) {
  sample_row <- DBI::dbGetQuery(conn,
    sprintf("SELECT * FROM %s LIMIT 1", table))

  item_cols <- setdiff(names(sample_row), c("id", "years"))
  n_items <- length(item_cols)

  cat(sprintf("  %s: %d items\n", table, n_items))

  # Check for minimum item coverage
  if (n_items < 10) {
    cat("    [WARN] Very few items (<10)\n")
    coverage_ok <- FALSE
  }
}

cat("\n")
if (coverage_ok) {
  cat("[OK] TEST 4 PASSED: All studies have adequate item coverage\n\n")
} else {
  cat("[WARN] TEST 4 WARNING: Some studies have low item coverage\n\n")
}

# =============================================================================
# Test 5: ID Uniqueness Within Studies
# =============================================================================

cat(strrep("=", 80), "\n")
cat("TEST 5: ID UNIQUENESS\n")
cat(strrep("=", 80), "\n\n")

cat("Checking for duplicate IDs within each study:\n\n")

ids_ok <- TRUE

for (table in expected_tables) {
  id_check <- DBI::dbGetQuery(conn,
    sprintf("
      SELECT
        COUNT(*) as n_records,
        COUNT(DISTINCT id) as n_unique_ids
      FROM %s
    ", table))

  has_duplicates <- id_check$n_records != id_check$n_unique_ids
  status <- ifelse(!has_duplicates, "[OK]", "[FAIL]")

  cat(sprintf("  %s: %s\n", table, status))
  cat(sprintf("    Records: %d\n", id_check$n_records))
  cat(sprintf("    Unique IDs: %d\n", id_check$n_unique_ids))

  if (has_duplicates) {
    cat("    [ERROR] Duplicate IDs detected!\n")
    ids_ok <- FALSE
  }
  cat("\n")
}

if (ids_ok) {
  cat("[OK] TEST 5 PASSED: No duplicate IDs within studies\n\n")
} else {
  cat("[FAIL] TEST 5 FAILED: Duplicate IDs found\n\n")
}

# =============================================================================
# Test 6: Export Test
# =============================================================================

cat(strrep("=", 80), "\n")
cat("TEST 6: EXPORT TEST (SMALL SAMPLE)\n")
cat(strrep("=", 80), "\n\n")

cat("Testing export with small NSCH sample (n=10)...\n\n")

tryCatch({
  source("scripts/irt_scoring/export_calibration_dat.R")

  # Create test output directory
  test_output <- "mplus/calibdat_validation_test.dat"

  # Export with tiny sample
  export_calibration_dat(
    output_dat = test_output,
    db_path = db_path,
    nsch_sample_size = 10,
    create_db_view = FALSE
  )

  # Check file exists
  if (file.exists(test_output)) {
    file_size <- file.info(test_output)$size
    file_size_mb <- file_size / (1024^2)

    cat(sprintf("[OK] Export successful\n"))
    cat(sprintf("     File: %s\n", test_output))
    cat(sprintf("     Size: %.2f MB\n", file_size_mb))

    # Read first line to verify format
    first_line <- readLines(test_output, n = 1)
    has_spaces <- grepl(" ", first_line)
    has_dots <- grepl("\\.", first_line)

    cat(sprintf("     Format: Space-delimited=%s, Missing='.'=%s\n",
                ifelse(has_spaces, "YES", "NO"),
                ifelse(has_dots, "YES", "NO")))

    # Clean up test file
    file.remove(test_output)
    cat("     Test file removed\n\n")

    cat("[OK] TEST 6 PASSED: Export function works correctly\n\n")
  } else {
    cat("[FAIL] TEST 6 FAILED: Export file not created\n\n")
  }

}, error = function(e) {
  cat(sprintf("[FAIL] TEST 6 FAILED: %s\n\n", e$message))
})

# =============================================================================
# Disconnect and Summary
# =============================================================================

DBI::dbDisconnect(conn)

cat(strrep("=", 80), "\n")
cat("VALIDATION SUMMARY\n")
cat(strrep("=", 80), "\n\n")

cat("Test Results:\n")
cat(sprintf("  1. Table Existence:      %s\n", ifelse(all_exist, "PASS", "FAIL")))
cat(sprintf("  2. Record Counts:        %s\n", ifelse(counts_ok, "PASS", "WARN")))
cat(sprintf("  3. Age Ranges:           %s\n", ifelse(ages_ok, "PASS", "WARN")))
cat(sprintf("  4. Item Coverage:        %s\n", ifelse(coverage_ok, "PASS", "WARN")))
cat(sprintf("  5. ID Uniqueness:        %s\n", ifelse(ids_ok, "PASS", "FAIL")))
cat(sprintf("  6. Export Test:          %s\n", "SEE ABOVE"))

cat("\n")

if (all_exist && ids_ok) {
  cat("[OK] VALIDATION PASSED: Calibration tables are ready for use\n\n")
  cat("Next steps:\n")
  cat("  1. Export production dataset:\n")
  cat("     source('scripts/irt_scoring/export_calibration_dat.R')\n")
  cat("     export_calibration_dat()\n\n")
  cat("  2. Run Mplus calibration:\n")
  cat("     See: docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md\n\n")
} else {
  cat("[REVIEW NEEDED] Some validation tests failed\n")
  cat("Review the output above and fix issues before proceeding\n\n")
}

cat(strrep("=", 80), "\n\n")

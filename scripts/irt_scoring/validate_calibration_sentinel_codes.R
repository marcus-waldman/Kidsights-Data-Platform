# =============================================================================
# Validate Calibration Tables for Sentinel Missing Codes
# =============================================================================
# Purpose: Check ALL study-specific calibration tables for sentinel missing
#          codes (values >= 90) that should have been converted to NA
#
# This is a CRITICAL safety check before Mplus export to ensure:
#   - Historical data (NE20, NE22, USA24) has no contamination
#   - NSCH transformation helpers worked correctly
#   - NE25 pipeline transformations succeeded
#   - No sentinel codes reach IRT calibration
#
# Usage:
#   source("scripts/irt_scoring/validate_calibration_sentinel_codes.R")
#   validate_calibration_sentinel_codes()
# =============================================================================

#' Validate Calibration Tables for Sentinel Missing Codes
#'
#' @description
#' Checks ALL study-specific calibration tables in DuckDB for sentinel missing
#' codes (values >= 90). This catches contamination from ANY source:
#' historical data imports, NSCH transformations, or NE25 pipeline bugs.
#'
#' @param db_path Character. Path to DuckDB database.
#'   Default: "data/duckdb/kidsights_local.duckdb"
#' @param codebook_path Character. Path to codebook.json.
#'   Default: "codebook/data/codebook.json"
#' @param verbose Logical. Print detailed progress? Default: TRUE
#' @param stop_on_error Logical. Stop if sentinel codes found? Default: TRUE
#'
#' @return Invisible list with validation results for each study
#'
#' @details
#' This function:
#' 1. Connects to DuckDB and loads all 6 study calibration tables
#' 2. Applies validate_no_missing_codes() using equate lexicon
#' 3. Reports violations by study with detailed counts
#' 4. Stops pipeline execution if ANY violations found
#'
#' **Why This Matters:**
#' - Historical data was imported ONCE and never re-validated
#' - NSCH transformation helpers might have bugs
#' - This is the LAST LINE OF DEFENSE before Mplus export
#' - Sentinel codes would contaminate ALL IRT parameters
#'
#' @examples
#' \dontrun{
#' # Run validation (stops on error)
#' validate_calibration_sentinel_codes()
#'
#' # Run validation without stopping (get report)
#' results <- validate_calibration_sentinel_codes(stop_on_error = FALSE)
#' }
#'
#' @export
validate_calibration_sentinel_codes <- function(
    db_path = "data/duckdb/kidsights_local.duckdb",
    codebook_path = "codebook/data/codebook.json",
    verbose = TRUE,
    stop_on_error = TRUE) {

  # ===========================================================================
  # Setup
  # ===========================================================================

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat("VALIDATE CALIBRATION TABLES FOR SENTINEL MISSING CODES\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Load dependencies
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' required. Install with: install.packages('duckdb')")
  }

  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' required. Install with: install.packages('dplyr')")
  }

  library(duckdb)
  library(dplyr)

  # Source validation function
  source("R/utils/validate_no_missing_codes.R")

  # Expected calibration tables
  calibration_tables <- c(
    "ne20_calibration",
    "ne22_calibration",
    "ne25_calibration",
    "nsch21_calibration",
    "nsch22_calibration",
    "usa24_calibration"
  )

  # ===========================================================================
  # Connect to Database
  # ===========================================================================

  if (verbose) cat("[1/3] Connecting to DuckDB database\n")

  if (!file.exists(db_path)) {
    stop(sprintf("Database not found at: %s", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

  if (verbose) {
    cat(sprintf("        Database: %s\n", db_path))
  }

  # Check which tables exist
  existing_tables <- DBI::dbListTables(conn)
  missing_tables <- setdiff(calibration_tables, existing_tables)

  if (length(missing_tables) > 0) {
    DBI::dbDisconnect(conn)
    stop(sprintf("Missing calibration tables: %s\nRun: scripts/irt_scoring/create_calibration_tables.R",
                 paste(missing_tables, collapse = ", ")))
  }

  if (verbose) {
    cat(sprintf("        Tables found: %d\n\n", length(calibration_tables)))
  }

  # ===========================================================================
  # Validate Each Study Table
  # ===========================================================================

  if (verbose) {
    cat("[2/3] Validating study-specific calibration tables\n")
    cat("        Using equate lexicon for item mapping\n")
    cat("        Checking for values >= 90\n\n")
  }

  validation_results <- list()
  all_clean <- TRUE
  total_violations <- 0

  for (table_name in calibration_tables) {
    if (verbose) {
      cat(sprintf("      Validating %s...\n", table_name))
    }

    # Load table
    study_data <- DBI::dbGetQuery(conn, sprintf("SELECT * FROM %s", table_name))

    if (verbose) {
      cat(sprintf("        Loaded %d records, %d columns\n",
                  nrow(study_data), ncol(study_data)))
    }

    # Validate using equate lexicon
    validation_result <- tryCatch({
      validate_no_missing_codes(
        dat = study_data,
        codebook_path = codebook_path,
        lexicon_name = "equate",
        verbose = FALSE,  # Suppress per-item output
        stop_on_error = FALSE  # Don't stop yet - collect all violations
      )

      # If we get here, validation passed
      list(passed = TRUE, violations = NULL)

    }, error = function(e) {
      # Validation failed - parse error message for details
      list(passed = FALSE, violations = e$message)
    }, warning = function(w) {
      # Validation returned warnings
      list(passed = FALSE, violations = w$message)
    })

    validation_results[[table_name]] <- validation_result

    if (!validation_result$passed) {
      all_clean <- FALSE
      total_violations <- total_violations + 1

      if (verbose) {
        cat(sprintf("        [FAIL] Sentinel codes detected\n"))
      }
    } else {
      if (verbose) {
        cat(sprintf("        [OK] No sentinel codes found\n"))
      }
    }

    if (verbose) cat("\n")
  }

  # ===========================================================================
  # Disconnect and Report
  # ===========================================================================

  DBI::dbDisconnect(conn)

  if (verbose) {
    cat("[3/3] Validation summary\n\n")
  }

  # ===========================================================================
  # Handle Results
  # ===========================================================================

  if (all_clean) {
    if (verbose) {
      cat(strrep("=", 80), "\n")
      cat("[OK] VALIDATION PASSED\n")
      cat(strrep("=", 80), "\n\n")
      cat("No sentinel missing codes (>= 90) found in any calibration table.\n")
      cat("All study tables are clean and ready for Mplus export.\n\n")
    }

    return(invisible(validation_results))

  } else {
    # Build comprehensive error report
    error_msg <- sprintf("\n%s\n", strrep("=", 80))
    error_msg <- paste0(error_msg, "[ERROR] VALIDATION FAILED: Sentinel Missing Codes Detected\n")
    error_msg <- paste0(error_msg, sprintf("%s\n\n", strrep("=", 80)))

    error_msg <- paste0(error_msg, sprintf("Found sentinel codes (>= 90) in %d of %d calibration tables:\n\n",
                                           total_violations, length(calibration_tables)))

    for (table_name in names(validation_results)) {
      result <- validation_results[[table_name]]

      if (!result$passed) {
        error_msg <- paste0(error_msg, sprintf("TABLE: %s\n", table_name))
        error_msg <- paste0(error_msg, sprintf("%s\n", strrep("-", 80)))
        error_msg <- paste0(error_msg, result$violations)
        error_msg <- paste0(error_msg, "\n\n")
      }
    }

    error_msg <- paste0(error_msg, "ACTION REQUIRED:\n")
    error_msg <- paste0(error_msg, "1. For NE25: Re-run NE25 pipeline with updated validation\n")
    error_msg <- paste0(error_msg, "2. For NSCH: Fix transformation helpers (recode_nsch_2021.R, recode_nsch_2022.R)\n")
    error_msg <- paste0(error_msg, "3. For Historical: Investigate original data imports\n")
    error_msg <- paste0(error_msg, "4. Re-create affected calibration tables\n")
    error_msg <- paste0(error_msg, "5. Re-run this validation\n\n")

    error_msg <- paste0(error_msg, "DO NOT PROCEED WITH MPLUS EXPORT until all tables are clean.\n")
    error_msg <- paste0(error_msg, "Sentinel codes would contaminate ALL IRT parameters.\n\n")

    if (stop_on_error) {
      stop(error_msg)
    } else {
      warning(error_msg)
      return(invisible(validation_results))
    }
  }
}

# =============================================================================
# Execute if run as script
# =============================================================================

if (!interactive()) {
  validate_calibration_sentinel_codes()
}

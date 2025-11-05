# =============================================================================
# Export Calibration Dataset to Mplus .dat File
# =============================================================================
# Purpose: Combine study-specific calibration tables and export to Mplus format
#          Sampling of NSCH data happens at export time (not storage time)
#
# Input: 6 DuckDB calibration tables:
#   - ne20_calibration, ne22_calibration, usa24_calibration (historical)
#   - ne25_calibration (current study)
#   - nsch21_calibration, nsch22_calibration (national benchmarking)
#
# Output: Mplus .dat file (space-delimited, missing as ".")
# =============================================================================

#' Export Calibration Dataset to Mplus .dat File
#'
#' Combines study-specific calibration tables and exports to Mplus-compatible
#' .dat file format. NSCH data is sampled at export time for flexibility.
#'
#' @param output_dat Character. Path for output .dat file.
#'   Default: "mplus/calibdat.dat"
#' @param db_path Character. Path to DuckDB database file.
#'   Default: "data/duckdb/kidsights_local.duckdb"
#' @param studies Character vector. Which studies to include.
#'   Options: "NE20", "NE22", "NE25", "NSCH21", "NSCH22", "USA24", "ALL"
#'   Default: "ALL"
#' @param nsch_sample_size Integer. Number of records to sample per NSCH year.
#'   Default: 1000
#' @param nsch_sample_seed Integer. Random seed for reproducible NSCH sampling.
#'   Default: 12345
#' @param create_db_view Logical. Create database view for querying?
#'   Default: FALSE
#' @param view_name Character. Name for database view (if create_db_view=TRUE).
#'   Default: "calibration_combined"
#'
#' @return Invisible NULL. Creates .dat file as side effect.
#'
#' @details
#' This function performs the following operations:
#'
#' 1. **Load Study Tables:** Query all 6 calibration tables from DuckDB
#' 2. **Sample NSCH:** Sample nsch_sample_size records from NSCH21/NSCH22
#' 3. **Add Study Codes:** Assign numeric codes (1=NE20, 2=NE22, 3=NE25, etc.)
#' 4. **Combine Studies:** Stack all studies with consistent column structure
#' 5. **Export to Mplus:** Write space-delimited .dat file (missing as ".")
#' 6. **Optional View:** Create database view for SQL queries
#'
#' Study numeric codes:
#' - 1 = NE20 (Nebraska 2020)
#' - 2 = NE22 (Nebraska 2022)
#' - 3 = NE25 (Nebraska 2025)
#' - 5 = NSCH21 (National Survey 2021)
#' - 6 = NSCH22 (National Survey 2022)
#' - 7 = USA24 (National 2024)
#'
#' Output structure: study_num, id, years, {416 items}
#'
#' @examples
#' \dontrun{
#' # Standard production export (NSCH n=1000)
#' source("scripts/irt_scoring/export_calibration_dat.R")
#' export_calibration_dat()
#'
#' # Large sample for DIF analysis (NSCH n=5000)
#' export_calibration_dat(
#'   output_dat = "mplus/calibdat_large.dat",
#'   nsch_sample_size = 5000
#' )
#'
#' # Development/testing (NSCH n=100)
#' export_calibration_dat(
#'   output_dat = "mplus/calibdat_test.dat",
#'   nsch_sample_size = 100
#' )
#'
#' # Create with database view for queries
#' export_calibration_dat(
#'   create_db_view = TRUE,
#'   view_name = "calibration_combined"
#' )
#' }
#'
#' @seealso
#' - \code{scripts/irt_scoring/create_calibration_tables.R} for creating tables
#' - \code{scripts/irt_scoring/import_historical_calibration.R} for historical data
#'
#' @export
export_calibration_dat <- function(
    output_dat = "mplus/calibdat.dat",
    db_path = "data/duckdb/kidsights_local.duckdb",
    studies = "ALL",
    nsch_sample_size = 1000,
    nsch_sample_seed = 12345,
    create_db_view = FALSE,
    view_name = "calibration_combined") {

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("EXPORT CALIBRATION DATASET TO MPLUS .DAT FILE\n")
  cat(strrep("=", 80), "\n\n")

  # Normalize studies input
  if ("ALL" %in% studies) {
    studies <- c("NE20", "NE22", "NE25", "NSCH21", "NSCH22", "USA24")
  }

  cat(sprintf("Configuration:\n"))
  cat(sprintf("  Studies: %s\n", paste(studies, collapse = ", ")))
  cat(sprintf("  NSCH sample size: %d per year\n", nsch_sample_size))
  cat(sprintf("  Output file: %s\n", output_dat))
  cat(sprintf("  Create DB view: %s\n", ifelse(create_db_view, "YES", "NO")))
  cat("\n")

  # ===========================================================================
  # Load Dependencies
  # ===========================================================================

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

  # ===========================================================================
  # Connect to Database
  # ===========================================================================

  cat("[SETUP] Connecting to DuckDB database\n")

  if (!file.exists(db_path)) {
    stop(sprintf("Database not found at: %s", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  cat(sprintf("        Connected to: %s\n\n", db_path))

  # ===========================================================================
  # Load and Combine Study Data
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("LOADING STUDY DATA\n")
  cat(strrep("=", 80), "\n\n")

  combined_data <- list()

  # Study mapping: study name -> (study_num, table_name)
  study_info <- list(
    "NE20" = list(num = 1, table = "ne20_calibration"),
    "NE22" = list(num = 2, table = "ne22_calibration"),
    "NE25" = list(num = 3, table = "ne25_calibration"),
    "NSCH21" = list(num = 5, table = "nsch21_calibration"),
    "NSCH22" = list(num = 6, table = "nsch22_calibration"),
    "USA24" = list(num = 7, table = "usa24_calibration")
  )

  # Set seed for reproducible NSCH sampling
  set.seed(nsch_sample_seed)

  for (study in studies) {
    info <- study_info[[study]]
    table_name <- info$table
    study_num <- info$num

    cat(sprintf("[%s] Loading from %s\n", study, table_name))

    # Check table exists
    tables <- DBI::dbListTables(conn)
    if (!table_name %in% tables) {
      cat(sprintf("      [WARN] Table '%s' not found. Skipping %s.\n\n", table_name, study))
      next
    }

    # Load data (with sampling for NSCH)
    if (study %in% c("NSCH21", "NSCH22")) {
      # Sample NSCH data
      query <- sprintf("
        SELECT * FROM %s
        ORDER BY RANDOM()
        LIMIT %d
      ", table_name, nsch_sample_size)

      study_data <- DBI::dbGetQuery(conn, query)
      cat(sprintf("      Sampled %d records (from full table)\n", nrow(study_data)))
    } else {
      # Load all records for non-NSCH studies
      query <- sprintf("SELECT * FROM %s", table_name)
      study_data <- DBI::dbGetQuery(conn, query)
      cat(sprintf("      Loaded %d records\n", nrow(study_data)))
    }

    # Add study_num column and ensure id is character for consistency
    study_data <- study_data %>%
      dplyr::mutate(
        study_num = study_num,
        id = as.character(id)  # Convert to character (handles both numeric and composite IDs)
      ) %>%
      dplyr::relocate(study_num, id, years)

    combined_data[[study]] <- study_data
    cat("\n")
  }

  # ===========================================================================
  # Combine All Studies
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("COMBINING STUDIES\n")
  cat(strrep("=", 80), "\n\n")

  if (length(combined_data) == 0) {
    stop("No study data loaded. Check that calibration tables exist.")
  }

  cat(sprintf("[1/3] Stacking %d studies\n", length(combined_data)))

  # Get all unique columns across studies
  all_cols <- unique(unlist(lapply(combined_data, names)))
  cat(sprintf("      Total unique columns: %d\n", length(all_cols)))

  # Ensure all studies have same columns (fill missing with NA)
  for (study in names(combined_data)) {
    missing_cols <- setdiff(all_cols, names(combined_data[[study]]))
    if (length(missing_cols) > 0) {
      for (col in missing_cols) {
        combined_data[[study]][[col]] <- NA
      }
    }
    # Reorder columns to match all_cols
    combined_data[[study]] <- combined_data[[study]][, all_cols]
  }

  # Combine using bind_rows
  calibration_combined <- dplyr::bind_rows(combined_data)

  cat(sprintf("\n[2/3] Combined dataset dimensions\n"))
  cat(sprintf("      Records: %d\n", nrow(calibration_combined)))
  cat(sprintf("      Columns: %d (study_num, id, years, %d items)\n",
              ncol(calibration_combined), ncol(calibration_combined) - 3))

  # Study distribution
  study_dist <- table(calibration_combined$study_num)
  cat(sprintf("\n[3/3] Study distribution\n"))
  for (study_num in sort(as.integer(names(study_dist)))) {
    study_name <- names(which(sapply(study_info, function(x) x$num == study_num)))
    cat(sprintf("      %d (%s): %d records (%.1f%%)\n",
                study_num, study_name, study_dist[as.character(study_num)],
                study_dist[as.character(study_num)] / nrow(calibration_combined) * 100))
  }
  cat("\n")

  # ===========================================================================
  # Export to Mplus .dat File
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("EXPORTING TO MPLUS .DAT FILE\n")
  cat(strrep("=", 80), "\n\n")

  # Ensure output directory exists
  output_dir <- dirname(output_dat)
  if (!dir.exists(output_dir)) {
    cat(sprintf("[SETUP] Creating output directory: %s\n", output_dir))
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  cat(sprintf("[1/2] Writing to: %s\n", output_dat))
  cat("      Format: space-delimited, missing as '.'\n")

  # Write with Mplus format
  write.table(calibration_combined,
              file = output_dat,
              row.names = FALSE,
              col.names = FALSE,
              sep = " ",
              na = ".")

  # Check file size
  file_size <- file.info(output_dat)$size
  file_size_mb <- file_size / (1024^2)

  cat(sprintf("\n[2/2] Export complete\n"))
  cat(sprintf("      File size: %.2f MB (%s bytes)\n",
              file_size_mb, format(file_size, big.mark = ",")))
  cat("\n")

  # ===========================================================================
  # Optional: Create Database View
  # ===========================================================================

  if (create_db_view) {
    cat(strrep("=", 80), "\n")
    cat("CREATING DATABASE VIEW\n")
    cat(strrep("=", 80), "\n\n")

    # Reconnect with write access
    DBI::dbDisconnect(conn)
    conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)

    cat(sprintf("[1/2] Creating view: %s\n", view_name))

    # Drop view if exists
    if (view_name %in% DBI::dbListTables(conn)) {
      cat(sprintf("      Dropping existing view '%s'\n", view_name))
      DBI::dbExecute(conn, sprintf("DROP VIEW %s", view_name))
    }

    # Build UNION ALL query
    union_queries <- c()
    for (study in studies) {
      info <- study_info[[study]]
      table_name <- info$table
      study_num <- info$num

      if (table_name %in% DBI::dbListTables(conn)) {
        if (study %in% c("NSCH21", "NSCH22")) {
          # Note: View doesn't sample NSCH, shows all records
          query_part <- sprintf(
            "SELECT %d as study_num, * FROM %s",
            study_num, table_name
          )
        } else {
          query_part <- sprintf(
            "SELECT %d as study_num, * FROM %s",
            study_num, table_name
          )
        }
        union_queries <- c(union_queries, query_part)
      }
    }

    view_query <- sprintf("CREATE VIEW %s AS\n%s",
                          view_name,
                          paste(union_queries, collapse = "\nUNION ALL\n"))

    DBI::dbExecute(conn, view_query)

    cat(sprintf("\n[2/2] View created successfully\n"))
    cat(sprintf("      Query with: SELECT * FROM %s\n", view_name))
    cat(sprintf("      Note: View shows ALL NSCH records (not sampled)\n"))
    cat("\n")
  }

  # ===========================================================================
  # Disconnect and Summary
  # ===========================================================================

  DBI::dbDisconnect(conn)

  cat(strrep("=", 80), "\n")
  cat("EXPORT COMPLETE\n")
  cat(strrep("=", 80), "\n\n")

  cat("Output:\n")
  cat(sprintf("  File: %s (%.2f MB)\n", output_dat, file_size_mb))
  cat(sprintf("  Records: %d\n", nrow(calibration_combined)))
  cat(sprintf("  Studies: %d (%s)\n", length(studies), paste(studies, collapse = ", ")))
  cat(sprintf("  NSCH samples: %d per year (seed: %d)\n",
              nsch_sample_size, nsch_sample_seed))

  if (create_db_view) {
    cat(sprintf("  Database view: %s\n", view_name))
  }

  cat("\nNext steps:\n")
  cat("  1. Test Mplus compatibility: scripts/irt_scoring/test_mplus_compatibility.R\n")
  cat("  2. Create Mplus .inp file: See docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md\n")
  cat("  3. Run Mplus calibration: mplus input.inp\n\n")

  cat("[OK] Calibration dataset exported successfully\n\n")

  invisible(NULL)
}

# =============================================================================
# Run if executed as script
# =============================================================================

if (!interactive()) {
  export_calibration_dat()
}

# =============================================================================
# Create Study-Specific Calibration Tables
# =============================================================================
# Purpose: Create calibration tables for NE25, NSCH 2021, and NSCH 2022
#          Historical studies (NE20, NE22, USA24) use import_historical_calibration.R
#
# Output: 3 DuckDB tables:
#   - ne25_calibration (from ne25_transformed, eligible=TRUE)
#   - nsch21_calibration (all records, age < 6, ≥2 items)
#   - nsch22_calibration (all records, age < 6, ≥2 items)
# =============================================================================

#' Create Study-Specific Calibration Tables
#'
#' Creates calibration tables for NE25, NSCH 2021, and NSCH 2022 studies.
#' Each table stores ALL available data for the study (no sampling).
#' Sampling occurs at export time when creating Mplus .dat files.
#'
#' @param codebook_path Character. Path to codebook.json file.
#'   Default: "codebook/data/codebook.json"
#' @param db_path Character. Path to DuckDB database file.
#'   Default: "data/duckdb/kidsights_local.duckdb"
#' @param studies Character vector. Which studies to create tables for.
#'   Options: "NE25", "NSCH21", "NSCH22", "ALL"
#'   Default: "ALL"
#'
#' @return Invisible NULL. Creates database tables as side effects.
#'
#' @details
#' This function creates study-specific calibration tables:
#'
#' **NE25 Calibration Table:**
#' - Source: ne25_transformed table (pipeline output)
#' - Filter: eligible = TRUE
#' - Records: ~3,500
#' - Structure: id, years, {416 items}
#'
#' **NSCH21 Calibration Table:**
#' - Source: nsch_2021_raw table
#' - Filter: age < 6 years, ≥2 item responses
#' - Records: ~50,000
#' - Structure: id (HHID), years, {30 items}
#' - Uses: recode_nsch_2021() helper function
#'
#' **NSCH22 Calibration Table:**
#' - Source: nsch_2022_raw table
#' - Filter: age < 6 years, ≥2 item responses
#' - Records: ~50,000
#' - Structure: id (HHID), years, {37 items}
#' - Uses: recode_nsch_2022() helper function
#'
#' All tables store complete data. Sampling happens at export time via
#' export_calibration_dat() function.
#'
#' @examples
#' \dontrun{
#' # Create all calibration tables
#' source("scripts/irt_scoring/create_calibration_tables.R")
#' create_calibration_tables()
#'
#' # Create only NE25 table (after new data collection)
#' create_calibration_tables(studies = "NE25")
#'
#' # Create only NSCH tables
#' create_calibration_tables(studies = c("NSCH21", "NSCH22"))
#' }
#'
#' @seealso
#' - \code{scripts/irt_scoring/import_historical_calibration.R} for NE20/NE22/USA24
#' - \code{scripts/irt_scoring/export_calibration_dat.R} for creating .dat files
#' - \code{\link{recode_nsch_2021}} for NSCH 2021 harmonization
#' - \code{\link{recode_nsch_2022}} for NSCH 2022 harmonization
#'
#' @export
create_calibration_tables <- function(
    codebook_path = "codebook/data/codebook.json",
    db_path = "data/duckdb/kidsights_local.duckdb",
    studies = "ALL") {

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("CREATE STUDY-SPECIFIC CALIBRATION TABLES\n")
  cat(strrep("=", 80), "\n\n")

  # Normalize studies input
  if ("ALL" %in% studies) {
    studies <- c("NE25", "NSCH21", "NSCH22")
  }

  cat(sprintf("Studies to create: %s\n\n", paste(studies, collapse = ", ")))

  # ===========================================================================
  # Load Dependencies
  # ===========================================================================

  cat("[SETUP] Loading required packages\n")

  required_packages <- c("duckdb", "dplyr", "jsonlite")

  for (pkg in required_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required. Install with: install.packages('%s')",
                   pkg, pkg))
    }
  }

  library(duckdb)
  library(dplyr)
  library(jsonlite)

  cat("        Packages loaded successfully\n\n")

  # ===========================================================================
  # Connect to Database
  # ===========================================================================

  cat("[SETUP] Connecting to DuckDB database\n")

  if (!file.exists(db_path)) {
    stop(sprintf("Database not found at: %s", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
  cat(sprintf("        Connected to: %s\n\n", db_path))

  # ===========================================================================
  # Create NE25 Calibration Table
  # ===========================================================================

  if ("NE25" %in% studies) {
    cat(strrep("=", 80), "\n")
    cat("NE25 CALIBRATION TABLE\n")
    cat(strrep("=", 80), "\n\n")

    # Check source table exists
    tables <- DBI::dbGetQuery(conn, "SHOW TABLES")
    if (!"ne25_transformed" %in% tables$name) {
      cat("[WARN] ne25_transformed table not found. Skipping NE25.\n")
      cat("       Run NE25 pipeline first: run_ne25_pipeline.R\n\n")
    } else {
      cat("[1/6] Loading NE25 data from ne25_transformed (eligible=TRUE)\n")

      # Query NE25 data
      ne25_query <- "SELECT * FROM ne25_transformed WHERE eligible = TRUE"
      ne25_data <- DBI::dbGetQuery(conn, ne25_query)

      cat(sprintf("      Loaded %d eligible records\n", nrow(ne25_data)))

      cat("\n[2/6] Mapping NE25 variable names to lex_equate\n")

      # Build lexicon mapping: ne25 -> equate
      cb <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

      ne25_to_equate <- list()

      for (item_id in names(cb$items)) {
        item <- cb$items[[item_id]]

        # Check if item has both ne25 and equate lexicons
        if (!is.null(item$lexicons)) {
          ne25_name <- item$lexicons$ne25
          equate_name <- item$lexicons$equate

          # Handle simplifyVector=FALSE (values might be lists)
          if (is.list(ne25_name)) ne25_name <- unlist(ne25_name)
          if (is.list(equate_name)) equate_name <- unlist(equate_name)

          # If both exist and are non-empty, create mapping
          if (!is.null(ne25_name) && !is.null(equate_name) &&
              length(ne25_name) > 0 && length(equate_name) > 0 &&
              ne25_name != "" && equate_name != "") {
            ne25_to_equate[[ne25_name]] <- equate_name
          }
        }
      }

      cat(sprintf("      Found %d variables to map from ne25 to equate\n", length(ne25_to_equate)))

      # Rename columns that exist in dataset
      dataset_cols <- names(ne25_data)
      renamed_count <- 0

      for (ne25_name in names(ne25_to_equate)) {
        equate_name <- ne25_to_equate[[ne25_name]]

        # Check if NE25 column exists in dataset (case-insensitive)
        match_idx <- which(tolower(dataset_cols) == tolower(ne25_name))

        if (length(match_idx) > 0) {
          actual_col <- dataset_cols[match_idx[1]]
          names(ne25_data)[match_idx[1]] <- equate_name
          renamed_count <- renamed_count + 1
        }
      }

      cat(sprintf("      Renamed %d columns to lex_equate format\n", renamed_count))

      cat("\n[3/6] Creating integer IDs and selecting columns\n")

      # Create integer IDs following convention: YYFFFSNNNNNN
      # YY=25, FFF=031 (Nebraska FIPS), S=1 (non-NSCH), N=sequential (6 digits)
      ne25_calibration <- ne25_data %>%
        dplyr::mutate(
          row_num = dplyr::row_number(),
          id = 250311000000 + row_num  # 250311000001, 250311000002, etc.
        ) %>%
        dplyr::select(-row_num) %>%
        dplyr::rename(years = years_old)

      cat(sprintf("      Created integer IDs: 250311000001 to 250311%06d\n", nrow(ne25_data)))

      # Remove metadata columns
      metadata_cols <- c("pid", "record_id", "redcap_event_name", "eligible",
                         "authentic", "survey_date", "child_dob")
      ne25_calibration <- ne25_calibration %>%
        dplyr::select(-dplyr::any_of(metadata_cols)) %>%
        dplyr::relocate(id, years)

      cat(sprintf("      Selected %d columns for calibration\n", ncol(ne25_calibration)))

      cat("\n[4/6] Creating ne25_calibration table\n")

      # Drop table if exists
      table_name <- "ne25_calibration"
      if (table_name %in% DBI::dbListTables(conn)) {
        cat(sprintf("      Dropping existing '%s' table\n", table_name))
        DBI::dbExecute(conn, sprintf("DROP TABLE %s", table_name))
      }

      # Write table
      cat(sprintf("      Inserting %d records\n", nrow(ne25_calibration)))
      DBI::dbWriteTable(conn, table_name, ne25_calibration, overwrite = TRUE)

      cat("\n[5/6] Creating indexes\n")

      # Create indexes
      index_queries <- c(
        sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
        sprintf("CREATE INDEX idx_%s_years ON %s (years)", table_name, table_name)
      )

      for (query in index_queries) {
        tryCatch({
          DBI::dbExecute(conn, query)
          index_name <- sub("CREATE INDEX (\\w+) .*", "\\1", query)
          cat(sprintf("        [OK] %s\n", index_name))
        }, error = function(e) {
          cat(sprintf("        [WARN] Index creation failed: %s\n", e$message))
        })
      }

      cat("\n[6/6] Verifying table\n")

      # Verify
      ne25_count <- DBI::dbGetQuery(conn,
        sprintf("SELECT COUNT(*) as n FROM %s", table_name))$n

      age_summary <- DBI::dbGetQuery(conn,
        sprintf("SELECT MIN(years) as min, AVG(years) as mean, MAX(years) as max FROM %s",
                table_name))

      cat(sprintf("      Records: %d [OK]\n", ne25_count))
      cat(sprintf("      Age range: %.2f - %.2f years (mean: %.2f)\n",
                  age_summary$min, age_summary$max, age_summary$mean))

      cat("\n[OK] NE25 calibration table complete\n\n")
    }
  }

  # ===========================================================================
  # Create NSCH 2021 Calibration Table
  # ===========================================================================

  if ("NSCH21" %in% studies) {
    cat(strrep("=", 80), "\n")
    cat("NSCH 2021 CALIBRATION TABLE\n")
    cat(strrep("=", 80), "\n\n")

    # Check source table exists
    tables <- DBI::dbGetQuery(conn, "SHOW TABLES")
    if (!"nsch_2021_raw" %in% tables$name) {
      cat("[WARN] nsch_2021_raw table not found. Skipping NSCH21.\n")
      cat("       Run NSCH pipeline first: python scripts/nsch/process_all_years.py --years 2021\n\n")
    } else {
      cat("[1/5] Loading and harmonizing NSCH 2021 data\n")

      # Load helper function
      source("scripts/irt_scoring/helpers/recode_nsch_2021.R")

      # Run recode function (returns ALL records)
      nsch21_data <- recode_nsch_2021(
        codebook_path = codebook_path,
        db_path = db_path,
        age_filter_years = 6
      )

      cat("\n[2/5] Creating nsch21_calibration table\n")

      # Drop table if exists
      table_name <- "nsch21_calibration"
      if (table_name %in% DBI::dbListTables(conn)) {
        cat(sprintf("      Dropping existing '%s' table\n", table_name))
        DBI::dbExecute(conn, sprintf("DROP TABLE %s", table_name))
      }

      # Write table
      cat(sprintf("      Inserting %d records\n", nrow(nsch21_data)))
      DBI::dbWriteTable(conn, table_name, nsch21_data, overwrite = TRUE)

      cat("\n[3/5] Creating indexes\n")

      # Create indexes
      index_queries <- c(
        sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
        sprintf("CREATE INDEX idx_%s_years ON %s (years)", table_name, table_name)
      )

      for (query in index_queries) {
        tryCatch({
          DBI::dbExecute(conn, query)
          index_name <- sub("CREATE INDEX (\\w+) .*", "\\1", query)
          cat(sprintf("        [OK] %s\n", index_name))
        }, error = function(e) {
          cat(sprintf("        [WARN] Index creation failed: %s\n", e$message))
        })
      }

      cat("\n[4/5] Verifying table\n")

      # Verify
      nsch21_count <- DBI::dbGetQuery(conn,
        sprintf("SELECT COUNT(*) as n FROM %s", table_name))$n

      age_summary <- DBI::dbGetQuery(conn,
        sprintf("SELECT MIN(years) as min, AVG(years) as mean, MAX(years) as max FROM %s",
                table_name))

      cat(sprintf("      Records: %d [OK]\n", nsch21_count))
      cat(sprintf("      Age range: %.2f - %.2f years (mean: %.2f)\n",
                  age_summary$min, age_summary$max, age_summary$mean))

      cat("\n[5/5] NSCH 2021 calibration table complete\n\n")
    }
  }

  # ===========================================================================
  # Create NSCH 2022 Calibration Table
  # ===========================================================================

  if ("NSCH22" %in% studies) {
    cat(strrep("=", 80), "\n")
    cat("NSCH 2022 CALIBRATION TABLE\n")
    cat(strrep("=", 80), "\n\n")

    # Check source table exists
    tables <- DBI::dbGetQuery(conn, "SHOW TABLES")
    if (!"nsch_2022_raw" %in% tables$name) {
      cat("[WARN] nsch_2022_raw table not found. Skipping NSCH22.\n")
      cat("       Run NSCH pipeline first: python scripts/nsch/process_all_years.py --years 2022\n\n")
    } else {
      cat("[1/5] Loading and harmonizing NSCH 2022 data\n")

      # Load helper function
      source("scripts/irt_scoring/helpers/recode_nsch_2022.R")

      # Run recode function (returns ALL records)
      nsch22_data <- recode_nsch_2022(
        codebook_path = codebook_path,
        db_path = db_path,
        age_filter_years = 6
      )

      cat("\n[2/5] Creating nsch22_calibration table\n")

      # Drop table if exists
      table_name <- "nsch22_calibration"
      if (table_name %in% DBI::dbListTables(conn)) {
        cat(sprintf("      Dropping existing '%s' table\n", table_name))
        DBI::dbExecute(conn, sprintf("DROP TABLE %s", table_name))
      }

      # Write table
      cat(sprintf("      Inserting %d records\n", nrow(nsch22_data)))
      DBI::dbWriteTable(conn, table_name, nsch22_data, overwrite = TRUE)

      cat("\n[3/5] Creating indexes\n")

      # Create indexes
      index_queries <- c(
        sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
        sprintf("CREATE INDEX idx_%s_years ON %s (years)", table_name, table_name)
      )

      for (query in index_queries) {
        tryCatch({
          DBI::dbExecute(conn, query)
          index_name <- sub("CREATE INDEX (\\w+) .*", "\\1", query)
          cat(sprintf("        [OK] %s\n", index_name))
        }, error = function(e) {
          cat(sprintf("        [WARN] Index creation failed: %s\n", e$message))
        })
      }

      cat("\n[4/5] Verifying table\n")

      # Verify
      nsch22_count <- DBI::dbGetQuery(conn,
        sprintf("SELECT COUNT(*) as n FROM %s", table_name))$n

      age_summary <- DBI::dbGetQuery(conn,
        sprintf("SELECT MIN(years) as min, AVG(years) as mean, MAX(years) as max FROM %s",
                table_name))

      cat(sprintf("      Records: %d [OK]\n", nsch22_count))
      cat(sprintf("      Age range: %.2f - %.2f years (mean: %.2f)\n",
                  age_summary$min, age_summary$max, age_summary$mean))

      cat("\n[5/5] NSCH 2022 calibration table complete\n\n")
    }
  }

  # ===========================================================================
  # Disconnect and Summary
  # ===========================================================================

  DBI::dbDisconnect(conn)

  cat(strrep("=", 80), "\n")
  cat("CALIBRATION TABLES CREATION COMPLETE\n")
  cat(strrep("=", 80), "\n\n")

  cat("Created tables:\n")
  for (study in studies) {
    table_name <- tolower(paste0(gsub("NSCH", "nsch", study), "_calibration"))
    cat(sprintf("  - %s\n", table_name))
  }

  cat("\nNext steps:\n")
  cat("  1. Verify tables: Check record counts and age ranges\n")
  cat("  2. Export .dat file: Use export_calibration_dat() function\n")
  cat("  3. Run Mplus calibration: Use exported .dat file\n\n")

  cat("[OK] All requested calibration tables created successfully\n\n")

  invisible(NULL)
}

# =============================================================================
# Run if executed as script
# =============================================================================

if (!interactive()) {
  create_calibration_tables()
}

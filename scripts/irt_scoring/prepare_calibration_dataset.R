# =============================================================================
# Prepare Calibration Dataset for Mplus IRT Recalibration
# =============================================================================
# Purpose: Interactive workflow to create complete calibration dataset combining:
#   - Historical data (NE20, NE22, USA24) from KidsightsPublic package
#   - Current NE25 data from ne25_transformed table
#   - NSCH national benchmarking data (2021, 2022)
#
# Outputs:
#   1. Mplus .dat file (space-delimited, missing as ".")
#   2. DuckDB table: calibration_dataset_2020_2025
#
# Usage:
#   source("scripts/irt_scoring/prepare_calibration_dataset.R")
#   prepare_calibration_dataset()
#
# Interactive prompts will guide through:
#   - NSCH sample size selection
#   - Output file path specification
# =============================================================================

#' Prepare Calibration Dataset for Mplus IRT Recalibration
#'
#' Interactive workflow to create complete Mplus calibration dataset combining
#' historical Nebraska studies (NE20, NE22, USA24), current NE25 data, and
#' national NSCH benchmarking samples (2021, 2022).
#'
#' @param codebook_path Character. Path to codebook.json file.
#'   Default: "codebook/data/codebook.json"
#' @param db_path Character. Path to DuckDB database file.
#'   Default: "data/duckdb/kidsights_local.duckdb"
#'
#' @return Invisible NULL. Creates files and database tables as side effects:
#'   - Mplus .dat file (space-delimited, missing as ".")
#'   - DuckDB table: calibration_dataset_2020_2025
#'
#' @details
#' This interactive workflow performs the following operations:
#'
#' 1. **Load Historical Data**: Import NE20, NE22, USA24 from
#'    historical_calibration_2020_2024 table (41,577 records)
#' 2. **Load NE25 Data**: Extract current study data from ne25_transformed table,
#'    filtered by eligible=TRUE (3,507 records)
#' 3. **Load NSCH Data**: Sample national benchmarking data from NSCH 2021/2022
#'    (user-specified sample size, default 1000 per year)
#' 4. **Harmonize Variables**: Map all items to lex_equate naming convention
#'    using codebook.json lexicon system
#' 5. **Create Study Indicators**: Assign numeric codes (1=NE20, 2=NE22, 3=NE25,
#'    5=NSCH21, 6=NSCH22, 7=USA24)
#' 6. **Combine Data**: Stack all 6 studies with consistent structure
#' 7. **Export to Mplus**: Write space-delimited .dat file with missing as "."
#' 8. **Store in DuckDB**: Create calibration_dataset_2020_2025 table with indexes
#'
#' Interactive prompts guide through:
#' - NSCH sample size selection (default: 1000 per year)
#' - Output file path specification (default: mplus/calibdat.dat)
#'
#' Expected output dimensions:
#' - Records: ~47,000 (varies by NSCH sample size)
#' - Columns: 419 (study_num, id, years, 416 items)
#' - File size: ~38-40 MB
#' - Execution time: ~30 seconds
#'
#' @examples
#' \dontrun{
#' # Interactive mode (recommended)
#' source("scripts/irt_scoring/prepare_calibration_dataset.R")
#' prepare_calibration_dataset()
#'
#' # Non-interactive mode (command line)
#' "C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
#'   --file=scripts/irt_scoring/prepare_calibration_dataset.R
#'
#' # Query resulting database table
#' library(duckdb)
#' conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
#' DBI::dbGetQuery(conn, "
#'   SELECT study_num, COUNT(*) as n
#'   FROM calibration_dataset_2020_2025
#'   GROUP BY study_num
#' ")
#' DBI::dbDisconnect(conn)
#' }
#'
#' @seealso
#' - \code{\link{recode_nsch_2021}} for NSCH 2021 harmonization
#' - \code{\link{recode_nsch_2022}} for NSCH 2022 harmonization
#' - \code{scripts/irt_scoring/import_historical_calibration.R} for one-time
#'   historical data import
#'
#' @export
prepare_calibration_dataset <- function(
    codebook_path = "codebook/data/codebook.json",
    db_path = "data/duckdb/kidsights_local.duckdb") {

  # ===========================================================================
  # Load Dependencies
  # ===========================================================================

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("PREPARE CALIBRATION DATASET FOR MPLUS IRT RECALIBRATION\n")
  cat(strrep("=", 80), "\n\n")

  cat("[SETUP] Loading required packages and helper functions\n")

  required_packages <- c("duckdb", "dplyr", "jsonlite", "stringr")

  for (pkg in required_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required but not installed.\n", pkg),
           sprintf("Install with: install.packages('%s')", pkg))
    }
  }

  library(duckdb)
  library(dplyr)
  library(jsonlite)
  library(stringr)

  # Source helper functions
  source("scripts/irt_scoring/helpers/recode_nsch_2021.R")
  source("scripts/irt_scoring/helpers/recode_nsch_2022.R")

  cat("        Packages and functions loaded\n\n")

  # ===========================================================================
  # Step 1: Load Historical Data (NE20, NE22, USA24)
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 1: LOAD HISTORICAL CALIBRATION DATA\n")
  cat(strrep("=", 80), "\n\n")

  cat("[1/10] Loading historical calibration data from DuckDB\n")

  # Connect to database
  if (!file.exists(db_path)) {
    stop(sprintf("DuckDB database not found at: %s", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

  # Check if historical table exists
  tables <- DBI::dbGetQuery(conn, "SHOW TABLES")
  if (!"historical_calibration_2020_2024" %in% tables$name) {
    DBI::dbDisconnect(conn)
    stop("Table 'historical_calibration_2020_2024' not found.\n",
         "Run scripts/irt_scoring/import_historical_calibration.R first.")
  }

  # Load historical data
  historical_data <- DBI::dbGetQuery(conn,
    "SELECT * FROM historical_calibration_2020_2024")
  DBI::dbDisconnect(conn)

  # Display record counts by study
  study_counts <- table(historical_data$study)
  cat(sprintf("        Loaded %d records from historical_calibration_2020_2024\n",
              nrow(historical_data)))
  cat("\n        Study breakdown:\n")
  for (study_name in names(study_counts)) {
    cat(sprintf("          %s: %d records\n", study_name, study_counts[study_name]))
  }

  cat(sprintf("\n        Items: %d columns\n", ncol(historical_data) - 3))
  cat("\n")

  # ===========================================================================
  # Step 2: Load NE25 Data
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 2: LOAD NE25 DATA\n")
  cat(strrep("=", 80), "\n\n")

  cat("[2/10] Loading NE25 data from ne25_transformed table\n")

  # Load codebook for item mappings
  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found at: %s", codebook_path))
  }
  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Build mapping: ne25 lexicon (lowercase) -> lex_equate (uppercase)
  ne25_to_equate <- list()
  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
    if (!is.null(item$lexicons$ne25) && nchar(item$lexicons$ne25) > 0) {
      ne25_name <- tolower(item$lexicons$ne25)  # Database has lowercase
      equate_name <- item$lexicons$equate
      ne25_to_equate[[ne25_name]] <- equate_name
    }
  }

  cat(sprintf("        Found %d items with ne25 lexicon mappings\n", length(ne25_to_equate)))

  # Query NE25 data
  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

  if (!"ne25_transformed" %in% DBI::dbGetQuery(conn, "SHOW TABLES")$name) {
    DBI::dbDisconnect(conn)
    stop("Table 'ne25_transformed' not found in database")
  }

  ne25_raw <- DBI::dbGetQuery(conn, "SELECT * FROM ne25_transformed WHERE eligible = TRUE")
  DBI::dbDisconnect(conn)

  cat(sprintf("        Loaded %d eligible records\n", nrow(ne25_raw)))

  # Extract and rename items
  ne25_item_cols <- intersect(tolower(names(ne25_raw)), names(ne25_to_equate))

  # Create rename mapping for dplyr (new_name = old_name)
  rename_map <- character()
  for (ne25_col in ne25_item_cols) {
    equate_name <- ne25_to_equate[[ne25_col]]
    rename_map[equate_name] <- ne25_col
  }

  cat(sprintf("        Mapping %d items to lex_equate names\n", length(rename_map)))

  # Build NE25 dataset
  ne25_data <- ne25_raw %>%
    dplyr::select(pid, record_id, years_old, dplyr::any_of(ne25_item_cols)) %>%
    dplyr::rename(!!!rename_map) %>%  # Rename to lex_equate
    dplyr::mutate(
      id = as.numeric(paste0("312025", pid, stringr::str_pad(record_id, 5, "left", "0"))),
      study = "NE25",
      years = years_old
    ) %>%
    dplyr::select(-pid, -record_id, -years_old) %>%
    dplyr::relocate(id, study, years)

  cat(sprintf("        NE25 data prepared: %d records, %d items\n",
              nrow(ne25_data), ncol(ne25_data) - 3))
  cat("\n")

  # ===========================================================================
  # Step 3: NSCH Sample Size Prompt
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 3: NSCH SAMPLE SIZE SELECTION\n")
  cat(strrep("=", 80), "\n\n")

  cat("[3/10] Select NSCH sample size\n\n")
  cat("NSCH data will be sampled to reduce file size and speed up Mplus execution.\n")
  cat("Recommended: 1000 records per year (total: 2000 records)\n")
  cat("Enter sample size per year, or 'all' for complete datasets\n\n")

  nsch_sample_size <- readline(prompt = "NSCH sample size per year (default: 1000): ")

  if (nsch_sample_size == "" || is.na(nsch_sample_size)) {
    nsch_sample_size <- 1000
    cat(sprintf("        Using default: %d records per year\n\n", nsch_sample_size))
  } else if (tolower(nsch_sample_size) %in% c("all", "inf")) {
    nsch_sample_size <- Inf
    cat("        Using all available records\n\n")
  } else {
    nsch_sample_size <- as.numeric(nsch_sample_size)
    if (is.na(nsch_sample_size) || nsch_sample_size <= 0) {
      stop("Invalid sample size. Must be positive number or 'all'")
    }
    cat(sprintf("        Using %d records per year\n\n", nsch_sample_size))
  }

  # ===========================================================================
  # Step 4: Load NSCH 2021 Data
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 4: LOAD NSCH 2021 DATA\n")
  cat(strrep("=", 80), "\n\n")

  cat("[4/10] Loading NSCH 2021 data\n\n")

  # Call recode function (includes all output messages)
  nsch21_full <- recode_nsch_2021(codebook_path = codebook_path, db_path = db_path)

  # Apply sampling if needed
  if (is.finite(nsch_sample_size) && nrow(nsch21_full) > nsch_sample_size) {
    set.seed(2021)  # Reproducible sampling
    nsch21_data <- nsch21_full %>% dplyr::slice_sample(n = nsch_sample_size)
    cat(sprintf("[INFO] Sampled %d of %d NSCH 2021 records\n\n",
                nrow(nsch21_data), nrow(nsch21_full)))
  } else {
    nsch21_data <- nsch21_full
    cat(sprintf("[INFO] Using all %d NSCH 2021 records\n\n", nrow(nsch21_data)))
  }

  # Add study identifier (recode function doesn't create this)
  nsch21_data <- nsch21_data %>% dplyr::mutate(study = "NSCH21")

  # ===========================================================================
  # Step 5: Load NSCH 2022 Data
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 5: LOAD NSCH 2022 DATA\n")
  cat(strrep("=", 80), "\n\n")

  cat("[5/10] Loading NSCH 2022 data\n\n")

  # Call recode function (includes all output messages)
  nsch22_full <- recode_nsch_2022(codebook_path = codebook_path, db_path = db_path)

  # Apply sampling if needed
  if (is.finite(nsch_sample_size) && nrow(nsch22_full) > nsch_sample_size) {
    set.seed(2022)  # Reproducible sampling
    nsch22_data <- nsch22_full %>% dplyr::slice_sample(n = nsch_sample_size)
    cat(sprintf("[INFO] Sampled %d of %d NSCH 2022 records\n\n",
                nrow(nsch22_data), nrow(nsch22_full)))
  } else {
    nsch22_data <- nsch22_full
    cat(sprintf("[INFO] Using all %d NSCH 2022 records\n\n", nrow(nsch22_data)))
  }

  # Add study identifier (recode function doesn't create this)
  nsch22_data <- nsch22_data %>% dplyr::mutate(study = "NSCH22")

  # ===========================================================================
  # Step 6: Combine Datasets & Create Study Indicator
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 6: COMBINE DATASETS & CREATE STUDY INDICATOR\n")
  cat(strrep("=", 80), "\n\n")

  cat("[6/10] Combining all datasets\n")

  # Bind all datasets (dplyr::bind_rows matches by column names)
  calibdat <- dplyr::bind_rows(
    historical_data,
    ne25_data,
    nsch21_data,
    nsch22_data
  )

  cat(sprintf("        Combined %d total records from %d studies\n",
              nrow(calibdat), length(unique(calibdat$study))))

  # Create numeric study indicator
  cat("        Creating numeric study indicator (study_num)\n")
  calibdat <- calibdat %>%
    dplyr::mutate(
      study_num = dplyr::case_when(
        study == "NE20" ~ 1,
        study == "NE22" ~ 2,
        study == "NE25" ~ 3,
        study == "NSCH21" ~ 5,
        study == "NSCH22" ~ 6,
        study == "USA24" ~ 7,
        .default = NA_real_
      )
    )

  # Get item columns (everything except metadata)
  metadata_cols <- c("study", "study_num", "id", "years")
  item_cols <- setdiff(names(calibdat), metadata_cols)

  # Sort item columns alphabetically
  item_cols_sorted <- sort(item_cols)

  # Relocate: metadata first, then items alphabetically
  calibdat <- calibdat %>%
    dplyr::relocate(study, study_num, id, years, dplyr::all_of(item_cols_sorted))

  cat(sprintf("        Final dataset: %d records x %d columns\n",
              nrow(calibdat), ncol(calibdat)))
  cat(sprintf("          Metadata columns: %d\n", length(metadata_cols)))
  cat(sprintf("          Item columns: %d\n", length(item_cols)))

  # Report study breakdown
  cat("\n        Study record counts:\n")
  study_summary <- calibdat %>%
    dplyr::group_by(study, study_num) %>%
    dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
    dplyr::arrange(study_num)

  for (i in 1:nrow(study_summary)) {
    cat(sprintf("          %s (study_num=%d): %d records\n",
                study_summary$study[i],
                study_summary$study_num[i],
                study_summary$n[i]))
  }

  # Calculate overall missingness
  item_data <- calibdat %>% dplyr::select(dplyr::all_of(item_cols_sorted))
  total_cells <- nrow(item_data) * ncol(item_data)
  missing_cells <- sum(is.na(item_data))
  pct_missing <- (missing_cells / total_cells) * 100

  cat(sprintf("\n        Overall item missingness: %.1f%% (%d of %d cells)\n",
              pct_missing, missing_cells, total_cells))

  # Age range
  cat(sprintf("        Age range: %.2f - %.2f years (median: %.2f)\n",
              min(calibdat$years, na.rm = TRUE),
              max(calibdat$years, na.rm = TRUE),
              median(calibdat$years, na.rm = TRUE)))

  cat("\n")

  # ===========================================================================
  # Step 7: Output File Path Prompt
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 7: OUTPUT FILE PATH SPECIFICATION\n")
  cat(strrep("=", 80), "\n\n")

  cat("[7/10] Specify output file path\n\n")
  cat("Calibration dataset will be written to Mplus .dat format.\n")
  cat("Default location: mplus/calibdat.dat\n\n")

  dat_file_path <- readline(prompt = "Output .dat file path (default: mplus/calibdat.dat): ")

  if (dat_file_path == "" || is.na(dat_file_path)) {
    dat_file_path <- "mplus/calibdat.dat"
    cat(sprintf("        Using default: %s\n", dat_file_path))
  } else {
    cat(sprintf("        Using custom path: %s\n", dat_file_path))
  }

  # Validate and create directory if needed
  dat_dir <- dirname(dat_file_path)
  if (!dir.exists(dat_dir)) {
    cat(sprintf("        Creating directory: %s\n", dat_dir))
    dir.create(dat_dir, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(dat_dir)) {
      stop(sprintf("Failed to create directory: %s", dat_dir))
    }
  } else {
    cat(sprintf("        Directory exists: %s\n", dat_dir))
  }

  # Check if file already exists
  if (file.exists(dat_file_path)) {
    cat(sprintf("        [WARN] File already exists and will be overwritten: %s\n", dat_file_path))
  }

  cat("\n")

  # ===========================================================================
  # Step 8: Write Mplus .dat File
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 8: WRITE MPLUS .DAT FILE\n")
  cat(strrep("=", 80), "\n\n")

  cat("[8/10] Writing Mplus .dat file\n")

  # Select columns for Mplus: study_num, id, years, items (alphabetically sorted)
  # Exclude "study" character column - Mplus needs numeric values only
  mplus_cols <- c("study_num", "id", "years", item_cols_sorted)
  mplus_data <- calibdat %>% dplyr::select(dplyr::all_of(mplus_cols))

  cat(sprintf("        Writing %d records x %d columns\n",
              nrow(mplus_data), ncol(mplus_data)))
  cat(sprintf("        Format: space-delimited, no headers, missing = '.'\n"))

  # Write Mplus .dat file
  # Format requirements:
  #   - Space-delimited
  #   - No column headers
  #   - No row names
  #   - Missing values as "."
  #   - Fixed decimal places for consistent formatting
  write.table(mplus_data,
              file = dat_file_path,
              sep = " ",
              na = ".",
              row.names = FALSE,
              col.names = FALSE,
              quote = FALSE)

  # Check file was created and get size
  if (!file.exists(dat_file_path)) {
    stop(sprintf("Failed to create Mplus .dat file: %s", dat_file_path))
  }

  file_size_bytes <- file.info(dat_file_path)$size
  file_size_mb <- file_size_bytes / (1024^2)

  cat(sprintf("        [OK] File written: %s\n", dat_file_path))
  cat(sprintf("        File size: %.2f MB (%s bytes)\n",
              file_size_mb, format(file_size_bytes, big.mark = ",")))

  cat("\n")

  # ===========================================================================
  # Step 9: Insert into DuckDB
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 9: INSERT INTO DUCKDB\n")
  cat(strrep("=", 80), "\n\n")

  cat("[9/10] Creating DuckDB table: calibration_dataset_2020_2025\n")

  # Connect to DuckDB (read_only = FALSE for writing)
  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)

  table_name <- "calibration_dataset_2020_2025"

  # Drop table if exists
  if (table_name %in% DBI::dbListTables(conn)) {
    cat(sprintf("        Dropping existing table: %s\n", table_name))
    DBI::dbExecute(conn, sprintf("DROP TABLE %s", table_name))
  }

  # Insert calibration dataset
  cat(sprintf("        Inserting %d records into %s\n", nrow(calibdat), table_name))
  DBI::dbWriteTable(conn, table_name, calibdat, overwrite = TRUE)

  # Create indexes for faster querying
  cat("        Creating indexes:\n")

  index_queries <- c(
    sprintf("CREATE INDEX idx_%s_study ON %s (study)", table_name, table_name),
    sprintf("CREATE INDEX idx_%s_study_num ON %s (study_num)", table_name, table_name),
    sprintf("CREATE INDEX idx_%s_id ON %s (id)", table_name, table_name),
    sprintf("CREATE INDEX idx_%s_study_id ON %s (study, id)", table_name, table_name)
  )

  for (query in index_queries) {
    tryCatch({
      DBI::dbExecute(conn, query)
      index_name <- sub("CREATE INDEX (\\w+) .*", "\\1", query)
      cat(sprintf("          [OK] %s\n", index_name))
    }, error = function(e) {
      cat(sprintf("          [WARN] Index creation failed: %s\n", e$message))
    })
  }

  # Verify record count
  db_count <- DBI::dbGetQuery(conn,
    sprintf("SELECT COUNT(*) as n FROM %s", table_name))$n

  cat(sprintf("\n        Verification: %d records in database\n", db_count))

  if (db_count != nrow(calibdat)) {
    cat(sprintf("        [WARN] Record count mismatch! Expected: %d, Found: %d\n",
                nrow(calibdat), db_count))
  } else {
    cat("        [OK] Record count matches\n")
  }

  # Disconnect
  DBI::dbDisconnect(conn)
  cat("        Disconnected from database\n")

  cat("\n")

  # ===========================================================================
  # Step 10: Summary Report
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("STEP 10: SUMMARY REPORT\n")
  cat(strrep("=", 80), "\n\n")

  cat("[10/10] Generating summary report\n\n")

  # Final record counts by study
  cat("Study Record Counts:\n")
  cat(strrep("-", 80), "\n")
  study_final <- calibdat %>%
    dplyr::group_by(study, study_num) %>%
    dplyr::summarise(
      n = dplyr::n(),
      pct = (dplyr::n() / nrow(calibdat)) * 100,
      .groups = "drop"
    ) %>%
    dplyr::arrange(study_num)

  total_records <- sum(study_final$n)

  for (i in 1:nrow(study_final)) {
    cat(sprintf("  %6s (study_num=%d): %6d records (%5.1f%%)\n",
                study_final$study[i],
                study_final$study_num[i],
                study_final$n[i],
                study_final$pct[i]))
  }
  cat(sprintf("  %6s              %6d records (100.0%%)\n", "TOTAL", total_records))

  # Item coverage summary
  cat("\n")
  cat("Item Coverage:\n")
  cat(strrep("-", 80), "\n")
  cat(sprintf("  Total items: %d\n", length(item_cols_sorted)))
  cat(sprintf("  Age range: %.2f - %.2f years (median: %.2f)\n",
              min(calibdat$years, na.rm = TRUE),
              max(calibdat$years, na.rm = TRUE),
              median(calibdat$years, na.rm = TRUE)))

  # Calculate item missingness statistics
  item_data_final <- calibdat %>% dplyr::select(dplyr::all_of(item_cols_sorted))
  item_missingness <- sapply(item_data_final, function(x) sum(is.na(x)) / length(x) * 100)

  cat(sprintf("  Item missingness: %.1f%% - %.1f%% (median: %.1f%%)\n",
              min(item_missingness),
              max(item_missingness),
              median(item_missingness)))

  # Count items with complete coverage (0% missing)
  n_complete <- sum(item_missingness == 0)
  cat(sprintf("  Items with complete data: %d of %d (%.1f%%)\n",
              n_complete, length(item_cols_sorted),
              (n_complete / length(item_cols_sorted)) * 100))

  # Output file paths
  cat("\n")
  cat("Output Files:\n")
  cat(strrep("-", 80), "\n")
  cat(sprintf("  Mplus .dat file: %s\n", dat_file_path))
  cat(sprintf("    Size: %.2f MB\n", file_size_mb))
  cat(sprintf("    Format: %d records x %d columns (space-delimited, missing='.')\n",
              nrow(mplus_data), ncol(mplus_data)))
  cat(sprintf("\n  DuckDB table: %s\n", table_name))
  cat(sprintf("    Location: %s\n", db_path))
  cat(sprintf("    Records: %d\n", db_count))
  cat(sprintf("    Indexes: study, study_num, id, (study,id)\n"))

  # Next steps
  cat("\n")
  cat("Next Steps for Mplus IRT Calibration:\n")
  cat(strrep("-", 80), "\n")
  cat("  1. Create Mplus input (.inp) file with:\n")
  cat(sprintf("     - DATA: FILE = \"%s\";\n", dat_file_path))
  cat("     - VARIABLE: NAMES = study_num id years %s;\n",
      paste(head(item_cols_sorted, 3), collapse = " "), "...")
  cat("     - Define IRT model structure (graded response model recommended)\n")
  cat("\n  2. Run Mplus calibration:\n")
  cat("     - Estimate item parameters across all studies\n")
  cat("     - Use study_num as grouping variable if needed\n")
  cat("     - Check for differential item functioning (DIF)\n")
  cat("\n  3. Extract calibrated parameters:\n")
  cat("     - Item discrimination (slope) parameters\n")
  cat("     - Item threshold (difficulty) parameters\n")
  cat("     - Store in codebook IRT parameters section\n")
  cat("\n  4. Score NE25 data using calibrated parameters:\n")
  cat("     - Apply IRT scoring to ne25_transformed items\n")
  cat("     - Generate theta scores for each domain\n")
  cat("     - Update ne25_scored table\n")

  cat("\n")

  # ===========================================================================
  # Completion
  # ===========================================================================

  cat(strrep("=", 80), "\n")
  cat("CALIBRATION DATASET PREPARATION COMPLETE\n")
  cat(strrep("=", 80), "\n\n")

  cat("[OK] Calibration dataset ready for Mplus IRT recalibration\n\n")

  return(invisible(NULL))
}

# =============================================================================
# Execute if run as script (not sourced)
# =============================================================================

if (!interactive()) {
  prepare_calibration_dataset()
}

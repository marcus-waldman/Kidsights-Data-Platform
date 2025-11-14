#' Core NSCH Harmonization Function
#'
#' Harmonizes NSCH data using codebook as single source of truth.
#' Maps study-specific variable names to lex_equate naming convention,
#' recodes missing values, and applies reverse/forward coding transformations.
#'
#' @param year Integer. NSCH year (e.g., 2021, 2022)
#' @param study Character. Study lexicon name (e.g., "cahmi21", "cahmi22")
#' @param db_path Character. Path to DuckDB database file.
#'   Default: "data/duckdb/kidsights_local.duckdb"
#' @param codebook_path Character. Path to codebook.json file.
#'   Default: "codebook/data/codebook.json"
#'
#' @return Data frame with columns:
#'   - HHID: Numeric household ID
#'   - {lex_equate items}: All harmonized items (0-based, reverse coded)
#'
#' @details
#' Transformation logic:
#' 1. Missing value recoding: Uses response_sets from codebook (only substantive values retained)
#' 2. Reverse coding: Checks reverse_by_study.{study}, falls back to reverse default
#' 3. Forward coded: y = y - min(y, na.rm=TRUE)
#' 4. Reverse coded: y = y - min(y, na.rm=TRUE); y = abs(y - max(y, na.rm=TRUE))
#'
#' All harmonized values are 0-based (minimum = 0).
#'
#' @examples
#' \dontrun{
#' # Harmonize NSCH 2021 with CAHMI21 lexicons
#' df <- harmonize_nsch_core(year = 2021, study = "cahmi21")
#'
#' # Harmonize NSCH 2022 with CAHMI22 lexicons
#' df <- harmonize_nsch_core(year = 2022, study = "cahmi22")
#' }
harmonize_nsch_core <- function(year,
                                 study,
                                 db_path = "data/duckdb/kidsights_local.duckdb",
                                 codebook_path = "codebook/data/codebook.json") {

  # Load required libraries
  require(jsonlite)
  require(dplyr)
  require(DBI)
  require(duckdb)

  # Load codebook
  message(sprintf("[1/5] Loading codebook from: %s", codebook_path))
  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Extract items with lexicons for this study
  message(sprintf("[2/5] Extracting items with '%s' lexicons...", study))
  items_to_harmonize <- list()

  for (item_key in names(codebook$items)) {
    item <- codebook$items[[item_key]]
    lexicons <- item$lexicons

    if (!is.null(lexicons) && study %in% names(lexicons)) {
      study_var <- lexicons[[study]]
      equate_var <- lexicons$equate

      if (!is.null(study_var) && !is.null(equate_var)) {
        # Handle array lexicons (e.g., ["CALMDOWNR", "CALMDOWN"])
        if (is.list(study_var)) {
          study_var <- study_var[[1]]  # Use first element
        }

        items_to_harmonize[[length(items_to_harmonize) + 1]] <- list(
          item_key = item_key,
          study_var = study_var,
          equate_var = equate_var
        )
      }
    }
  }

  message(sprintf("  Found %d items with '%s' lexicons", length(items_to_harmonize), study))

  # Load raw NSCH data from DuckDB
  message(sprintf("[3/5] Loading NSCH %d data from database...", year))
  con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  table_name <- sprintf("nsch_%d", year)
  if (!table_name %in% DBI::dbListTables(con)) {
    stop(sprintf("Table '%s' not found in database", table_name))
  }

  nsch_raw <- DBI::dbReadTable(con, table_name)
  message(sprintf("  Loaded %d records from %s", nrow(nsch_raw), table_name))

  # Initialize output data frame with HHID
  message(sprintf("[4/5] Harmonizing %d items...", length(items_to_harmonize)))
  harmonized_df <- data.frame(HHID = nsch_raw$HHID)

  # Track progress
  processed <- 0
  skipped <- 0

  # Process each item
  for (item_info in items_to_harmonize) {
    item_key <- item_info$item_key
    study_var <- item_info$study_var
    equate_var <- item_info$equate_var

    # Check if variable exists in raw data
    if (!study_var %in% names(nsch_raw)) {
      skipped <- skipped + 1
      next
    }

    # Get raw values
    y <- nsch_raw[[study_var]]

    # Step 1: Recode missing values using response_set (codebook-driven)
    item <- codebook$items[[item_key]]
    response_options <- item$content$response_options

    if (!is.null(response_options) && study %in% names(response_options)) {
      response_set_name <- response_options[[study]]

      if (!is.null(response_set_name) && response_set_name %in% names(codebook$response_sets)) {
        response_set <- codebook$response_sets[[response_set_name]]

        # Extract valid values (substantive only)
        valid_values <- sapply(response_set, function(x) as.numeric(x$value))

        # Recode: any value NOT in valid_values → NA
        y <- ifelse(y %in% valid_values, y, NA_real_)
      }
    }

    # Step 2: Get reverse coding flag (study-specific override)
    item_scoring <- item$scoring
    reverse_flag <- NULL

    # Check study-specific override first
    if (!is.null(item_scoring$reverse_by_study) && study %in% names(item_scoring$reverse_by_study)) {
      reverse_flag <- item_scoring$reverse_by_study[[study]]
    }

    # Fall back to default if no study-specific override
    if (is.null(reverse_flag)) {
      reverse_flag <- item_scoring$reverse
      if (is.null(reverse_flag)) {
        reverse_flag <- FALSE
      }
    }

    # Step 3: Apply transformation (both produce 0-based output)
    if (reverse_flag) {
      # Reverse coded: Make 0-based, then reverse
      y <- y - min(y, na.rm = TRUE)
      y <- abs(y - max(y, na.rm = TRUE))
    } else {
      # Forward coded: Just make 0-based
      y <- y - min(y, na.rm = TRUE)
    }

    # Step 4: Store with lex_equate name
    harmonized_df[[equate_var]] <- y
    processed <- processed + 1
  }

  message(sprintf("  Processed: %d items", processed))
  if (skipped > 0) {
    message(sprintf("  Skipped: %d items (not in raw data)", skipped))
  }

  message(sprintf("[5/5] Harmonization complete!"))
  message(sprintf("  Output: %d records, %d columns (HHID + %d items)",
                  nrow(harmonized_df), ncol(harmonized_df), ncol(harmonized_df) - 1))

  return(harmonized_df)
}

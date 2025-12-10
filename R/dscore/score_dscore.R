################################################################################
# GSED D-score Calculation Functions
################################################################################
# Purpose: Production functions for calculating GSED D-scores in NE25 pipeline
# Functions:
#   - score_dscore(): Main scoring function
#   - save_dscore_scores_to_db(): Database persistence helper
# Dependencies: dscore, dplyr, jsonlite, duckdb, DBI
################################################################################

#' Score GSED D-scores for NE25 data
#'
#' @param data Data frame with ne25_transformed structure (must have: pid, record_id,
#'   age_in_days, meets_inclusion, and GSED item columns)
#' @param codebook_path Path to codebook.json file (default: "codebook/data/codebook.json")
#' @param key GSED key for difficulty estimates (default: "gsed2406", most recent)
#' @param verbose Logical, print progress messages (default: TRUE)
#'
#' @return Data frame with columns: pid, record_id, a (age), n (items used),
#'   p (proportion passed), d (D-score), sem (SEM), daz (DAZ)
#'
#' @details
#' Filters to meets_inclusion = TRUE and calculates GSED D-scores using the
#' dscore package. Automatically extracts GSED item mappings from codebook.json.
#'
#' Output columns:
#' - pid, record_id: Participant identifiers
#' - a: Decimal age in years
#' - n: Number of items with valid (0/1) responses
#' - p: Proportion of milestones passed
#' - d: D-score (mean of posterior distribution)
#' - sem: Standard error of measurement
#' - daz: D-score adjusted for age (Z-score)
#'
#' @export
score_dscore <- function(data,
                         codebook_path = "codebook/data/codebook.json",
                         key = "gsed2406",
                         verbose = TRUE) {

  # ===========================================================================
  # 1. VALIDATE INPUT
  # ===========================================================================
  if (verbose) message("Validating input data...")

  # Check required columns
  required_cols <- c("pid", "record_id", "age_in_days", "meets_inclusion")
  missing_cols <- setdiff(required_cols, names(data))

  if (length(missing_cols) > 0) {
    stop(sprintf("Missing required columns: %s", paste(missing_cols, collapse = ", ")))
  }

  # Check codebook exists
  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  # ===========================================================================
  # 2. LOAD GSED MAPPINGS FROM CODEBOOK
  # ===========================================================================
  if (verbose) message("Loading GSED item mappings from codebook...")

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Extract GSED mappings
  gsed_mappings <- list()

  for (item_key in names(codebook$items)) {
    item_data <- codebook$items[[item_key]]

    # Check if item has lexicons field with both gsed and ne25
    if (!is.null(item_data$lexicons) &&
        !is.null(item_data$lexicons$gsed) &&
        !is.null(item_data$lexicons$ne25)) {

      ne25_var <- tolower(item_data$lexicons$ne25)
      gsed_code <- item_data$lexicons$gsed

      gsed_mappings[[gsed_code]] <- ne25_var
    }
  }

  if (length(gsed_mappings) == 0) {
    stop("No GSED item mappings found in codebook")
  }

  if (verbose) {
    message(sprintf("  Found %d GSED item mappings in codebook", length(gsed_mappings)))
  }

  # ===========================================================================
  # 3. FILTER DATA
  # ===========================================================================
  if (verbose) message("Filtering to eligible records (meets_inclusion = TRUE)...")

  n_total <- nrow(data)
  filtered_data <- data %>%
    dplyr::filter(meets_inclusion == TRUE)

  n_filtered <- nrow(filtered_data)

  if (verbose) {
    message(sprintf("  Filtered from %d to %d records (%.1f%%)",
                    n_total, n_filtered, 100 * n_filtered / n_total))
  }

  if (n_filtered == 0) {
    warning("No records meet inclusion criteria")
    return(data.frame(
      pid = character(0),
      record_id = integer(0),
      a = numeric(0),
      n = integer(0),
      p = numeric(0),
      d = numeric(0),
      sem = numeric(0),
      daz = numeric(0)
    ))
  }

  # ===========================================================================
  # 4. SELECT AND RENAME GSED VARIABLES
  # ===========================================================================
  if (verbose) message("Selecting and renaming GSED variables...")

  # Find available GSED variables
  ne25_vars <- unlist(gsed_mappings)
  available_ne25 <- intersect(ne25_vars, names(filtered_data))

  if (length(available_ne25) == 0) {
    stop("No GSED variables found in data")
  }

  # Create rename vector (new_name = old_name for dplyr::rename)
  # Find GSED codes for available ne25 vars
  gsed_codes <- names(gsed_mappings)[match(available_ne25, ne25_vars)]
  rename_vec <- setNames(available_ne25, gsed_codes)

  if (verbose) {
    message(sprintf("  Found %d/%d GSED variables in data",
                    length(available_ne25), length(gsed_mappings)))
  }

  # Select and rename
  dscore_input <- filtered_data %>%
    dplyr::select(pid, record_id, age_in_days, dplyr::all_of(available_ne25)) %>%
    dplyr::rename(!!!rename_vec)

  # Get GSED item columns (exclude identifiers)
  gsed_cols <- setdiff(names(dscore_input), c("pid", "record_id", "age_in_days"))

  # ===========================================================================
  # 5. RUN DSCORE CALCULATION
  # ===========================================================================
  if (verbose) {
    message(sprintf("Running dscore::dscore() with key='%s'...", key))
    message(sprintf("  Input: %d records x %d GSED items", nrow(dscore_input), length(gsed_cols)))
  }

  # Run dscore
  scored_data <- dscore::dscore(
    data = dscore_input,
    items = gsed_cols,
    xname = "age_in_days",
    xunit = "days",
    key = key,
    prepend = c("pid", "record_id"),
    verbose = FALSE
  )

  # ===========================================================================
  # 6. VALIDATE OUTPUT
  # ===========================================================================
  n_scored <- sum(!is.na(scored_data$d))

  if (verbose) {
    message(sprintf("  D-score calculation complete: %d/%d records scored (%.1f%%)",
                    n_scored, nrow(scored_data), 100 * n_scored / nrow(scored_data)))
    message(sprintf("  D-score range: [%.2f, %.2f]",
                    min(scored_data$d, na.rm = TRUE),
                    max(scored_data$d, na.rm = TRUE)))
  }

  return(scored_data)
}


#' Save GSED D-scores to DuckDB database
#'
#' @param scores Data frame returned by score_dscore()
#' @param db_path Path to DuckDB database file
#' @param table_name Name for the database table (default: "ne25_dscore_scores")
#' @param overwrite Logical, overwrite existing table (default: TRUE)
#' @param verbose Logical, print progress messages (default: TRUE)
#'
#' @return Invisible NULL (called for side effect of database insertion)
#'
#' @details
#' Creates indexes on pid and record_id columns for efficient querying.
#' Table structure: pid, record_id, a, n, p, d, sem, daz
#'
#' @export
save_dscore_scores_to_db <- function(scores,
                                     db_path = "data/duckdb/kidsights_local.duckdb",
                                     table_name = "ne25_dscore_scores",
                                     overwrite = TRUE,
                                     verbose = TRUE) {

  if (verbose) {
    message(sprintf("Saving GSED D-scores to database table '%s'...", table_name))
  }

  # Connect to database
  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)

  # Write table
  DBI::dbWriteTable(con, table_name, scores, overwrite = overwrite)

  if (verbose) {
    message(sprintf("  Wrote %d records to '%s'", nrow(scores), table_name))
  }

  # Create indexes
  tryCatch({
    # Index on pid
    pid_index_name <- paste0("idx_", table_name, "_pid")
    DBI::dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS %s ON %s (pid)",
                                pid_index_name, table_name))

    # Index on record_id
    record_id_index_name <- paste0("idx_", table_name, "_record_id")
    DBI::dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS %s ON %s (record_id)",
                                record_id_index_name, table_name))

    if (verbose) {
      message(sprintf("  Created indexes: %s, %s", pid_index_name, record_id_index_name))
    }
  }, error = function(e) {
    warning(sprintf("Failed to create indexes: %s", e$message))
  })

  # Disconnect
  duckdb::dbDisconnect(con, shutdown = TRUE)

  if (verbose) {
    message("  Database save complete")
  }

  invisible(NULL)
}

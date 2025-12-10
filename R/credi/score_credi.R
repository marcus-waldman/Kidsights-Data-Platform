# ==============================================================================
# CREDI Scoring Function for NE25 Pipeline
# ==============================================================================
# Purpose: Compute CREDI developmental scores for children under 4 years old
# Author: CREDI Integration Team
# Date: 2025-12-10
#
# Inputs:
#   - data: Data frame with ne25_transformed data (lowercase column names)
#   - codebook_path: Path to codebook.json (optional)
#   - min_items: Minimum number of items required for scoring (default: 5)
#   - age_cutoff: Maximum age in years for CREDI scoring (default: 4)
#
# Outputs:
#   - Data frame with pid, record_id, and CREDI scores (15 columns):
#     - Domain scores: COG, LANG, MOT, SEM, OVERALL
#     - Z-scores: Z_COG, Z_LANG, Z_MOT, Z_SEM, Z_OVERALL
#     - Standard errors: COG_SE, LANG_SE, MOT_SE, SEM_SE, OVERALL_SE
#
# ==============================================================================

#' Score CREDI Developmental Assessment
#'
#' Computes CREDI (Caregiver Reported Early Development Instruments) scores
#' for children under 4 years old using the credi R package.
#'
#' @param data Data frame with ne25_transformed data (lowercase column names)
#' @param codebook_path Path to codebook.json (default: "codebook/data/codebook.json")
#' @param min_items Minimum number of items required for scoring (default: 5)
#' @param age_cutoff Maximum age in years for CREDI scoring (default: 4)
#' @param verbose Logical, print progress messages (default: TRUE)
#'
#' @return Data frame with pid, record_id, and 15 CREDI score columns
#'
#' @export
score_credi <- function(data,
                        codebook_path = "codebook/data/codebook.json",
                        min_items = 5,
                        age_cutoff = 4,
                        verbose = TRUE) {

  # ============================================================================
  # 1. Validate Inputs
  # ============================================================================
  if (verbose) cat("[INFO] Validating inputs...\n")

  # Check required columns
  required_cols <- c("pid", "record_id", "years_old", "meets_inclusion")
  missing_cols <- setdiff(required_cols, names(data))

  if (length(missing_cols) > 0) {
    stop(sprintf("Missing required columns: %s", paste(missing_cols, collapse = ", ")))
  }

  # Load credi package
  if (!requireNamespace("credi", quietly = TRUE)) {
    stop("credi package not installed. Install with: devtools::install_github('marcus-waldman/credi')")
  }

  # ============================================================================
  # 2. Load CREDI Mappings from Codebook
  # ============================================================================
  if (verbose) cat("[INFO] Loading CREDI mappings from codebook...\n")

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  codebook <- jsonlite::fromJSON(codebook_path)

  # Extract CREDI mappings
  credi_mappings <- list()

  for (item_key in names(codebook$items)) {
    item <- codebook$items[[item_key]]
    if (!is.null(item$lexicons$credi) && !is.null(item$lexicons$ne25)) {
      if (startsWith(item$lexicons$credi, "LF")) {
        credi_mappings[[item$lexicons$credi]] <- tolower(item$lexicons$ne25)
      }
    }
  }

  if (length(credi_mappings) == 0) {
    stop("No CREDI LF mappings found in codebook")
  }

  if (verbose) {
    cat(sprintf("[INFO] Loaded %d CREDI LF item mappings\n", length(credi_mappings)))
  }

  # ============================================================================
  # 3. Filter Data
  # ============================================================================
  if (verbose) cat("[INFO] Filtering data...\n")

  # Filter to children under age cutoff and meets inclusion
  filtered_data <- data %>%
    dplyr::filter(years_old < age_cutoff, meets_inclusion == TRUE)

  if (verbose) {
    cat(sprintf("[INFO] %d records remain after filters (years_old < %d, meets_inclusion = TRUE)\n",
                nrow(filtered_data), age_cutoff))
  }

  if (nrow(filtered_data) == 0) {
    warning("No records remain after filtering")
    return(data.frame())
  }

  # ============================================================================
  # 4. Select and Rename CREDI Variables
  # ============================================================================
  if (verbose) cat("[INFO] Selecting and renaming CREDI variables...\n")

  # Check which variables exist in the data
  credi_codes <- names(credi_mappings)
  ne25_vars <- unlist(credi_mappings)

  available_vars <- intersect(ne25_vars, names(filtered_data))
  missing_vars <- setdiff(ne25_vars, names(filtered_data))

  if (verbose) {
    cat(sprintf("[INFO] %d/%d CREDI variables found in data\n",
                length(available_vars), length(ne25_vars)))
  }

  if (length(available_vars) == 0) {
    stop("No CREDI variables found in data")
  }

  # Create renaming vector (only for available variables)
  available_codes <- credi_codes[credi_mappings %in% available_vars]
  rename_vec <- setNames(available_vars, available_codes)

  # Prepare input for credi::score()
  credi_input <- filtered_data %>%
    dplyr::select(pid, record_id, years_old, dplyr::all_of(available_vars)) %>%
    dplyr::rename(!!!rename_vec) %>%
    dplyr::rename(AGE = years_old) %>%
    dplyr::mutate(ID = 1:dplyr::n()) %>%
    dplyr::select(ID, pid, record_id, AGE, dplyr::everything())

  if (verbose) {
    cat(sprintf("[INFO] Created CREDI input dataframe: %d rows x %d columns\n",
                nrow(credi_input), ncol(credi_input)))
  }

  # ============================================================================
  # 5. Run CREDI Scoring
  # ============================================================================
  if (verbose) {
    cat(sprintf("[INFO] Running CREDI scoring (min_items = %d)...\n", min_items))
  }

  # Prepare data for credi package (only ID, AGE, and LF items)
  credi_for_scoring <- credi_input %>%
    dplyr::select(ID, AGE, dplyr::starts_with("LF"))

  # Run scoring
  scored_result <- credi::score(
    data = credi_for_scoring,
    reverse_code = FALSE,
    interactive = FALSE,
    min_items = min_items
  )

  # Extract the data frame from the result
  if (is.list(scored_result)) {
    if ("data" %in% names(scored_result)) {
      scored_data <- scored_result$data
    } else {
      # Find the data frame element
      df_elements <- sapply(scored_result, is.data.frame)
      if (any(df_elements)) {
        scored_data <- scored_result[[which(df_elements)[1]]]
      } else {
        stop("Could not find data frame in scoring result")
      }
    }
  } else if (is.data.frame(scored_result)) {
    scored_data <- scored_result
  } else {
    stop("Unexpected result type from credi::score()")
  }

  if (verbose) {
    n_scored <- nrow(scored_data)
    n_total <- nrow(credi_input)
    pct_scored <- 100 * n_scored / n_total
    cat(sprintf("[INFO] CREDI scoring complete: %d/%d records scored (%.1f%%)\n",
                n_scored, n_total, pct_scored))
  }

  # ============================================================================
  # 6. Merge Scores Back with Original IDs
  # ============================================================================
  if (verbose) cat("[INFO] Merging CREDI scores with original pid/record_id...\n")

  # Select relevant score columns (exclude LF items and flags for now)
  score_cols <- c("ID", "AGE", "COG", "LANG", "MOT", "SEM", "OVERALL",
                  "Z_COG", "Z_LANG", "Z_MOT", "Z_SEM", "Z_OVERALL",
                  "COG_SE", "LANG_SE", "MOT_SE", "SEM_SE", "OVERALL_SE")

  # Check which columns exist in scored_data
  available_score_cols <- intersect(score_cols, names(scored_data))

  # Merge scores back with pid/record_id
  final_scores <- credi_input %>%
    dplyr::select(ID, pid, record_id) %>%
    dplyr::left_join(
      scored_data %>% dplyr::select(dplyr::all_of(available_score_cols)),
      by = "ID"
    ) %>%
    dplyr::select(-ID, -AGE)  # Remove temporary ID and AGE columns

  if (verbose) {
    cat(sprintf("[INFO] Final dataset: %d rows x %d columns\n",
                nrow(final_scores), ncol(final_scores)))
  }

  return(final_scores)
}


#' Save CREDI Scores to Database
#'
#' Helper function to save CREDI scores to DuckDB database.
#'
#' @param scores Data frame with CREDI scores (output from score_credi())
#' @param db_path Path to DuckDB database
#' @param table_name Name of the table to create (default: "ne25_credi_scores")
#' @param overwrite Logical, overwrite existing table (default: TRUE)
#' @param verbose Logical, print progress messages (default: TRUE)
#'
#' @export
save_credi_scores_to_db <- function(scores,
                                    db_path = "data/duckdb/kidsights_local.duckdb",
                                    table_name = "ne25_credi_scores",
                                    overwrite = TRUE,
                                    verbose = TRUE) {

  if (verbose) cat(sprintf("[INFO] Saving CREDI scores to database table: %s\n", table_name))

  # Connect to database
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)

  # Write table
  DBI::dbWriteTable(con, table_name, scores, overwrite = overwrite)

  # Create indexes
  if (verbose) cat("[INFO] Creating indexes...\n")

  DBI::dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS idx_%s_pid ON %s(pid)", table_name, table_name))
  DBI::dbExecute(con, sprintf("CREATE INDEX IF NOT EXISTS idx_%s_record_id ON %s(record_id)", table_name, table_name))

  # Disconnect
  DBI::dbDisconnect(con, shutdown = TRUE)

  if (verbose) {
    cat(sprintf("[INFO] Saved %d records to %s\n", nrow(scores), table_name))
  }
}

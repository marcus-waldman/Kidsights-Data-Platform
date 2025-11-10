#' Create NE25 Calibration Table
#'
#' @description
#' Creates an optimized ne25_calibration table with only essential columns needed
#' for IRT calibration: id, years, authenticity_weight, and all items with ne25+equate lexicons.
#' This replaces the bloated 667-column version with a streamlined ~279-column table,
#' achieving significant storage reduction by excluding demographics, geography, ACEs, childcare.
#'
#' @param codebook_path Path to codebook.json file
#' @param db_path Path to DuckDB database
#' @param verbose Logical; if TRUE, prints detailed progress messages
#'
#' @return Invisible list with metrics:
#'   - n_records: Number of records in output table
#'   - n_columns: Number of columns in output table
#'   - weight_range: Range of authenticity_weight values
#'
#' @details
#' Workflow:
#' 1. Extracts all items with both ne25 and equate lexicons from codebook.json (~276 items)
#' 2. Queries ne25_transformed with meets_inclusion=TRUE filter (2,831 records)
#' 3. Transforms data:
#'    - Renames items from ne25 lexicon to equate lexicon (uppercase)
#'    - Creates integer IDs (250311000001 to 250311002831)
#'    - Renames years_old → years
#' 4. Creates ne25_calibration table with ~279 columns (id, years, authenticity_weight + ~276 items)
#' 5. Creates indexes on id and years columns
#' 6. Validates output
#'
#' @examples
#' \dontrun{
#' # Standalone execution
#' create_ne25_calibration_table(
#'   codebook_path = "codebook/data/codebook.json",
#'   db_path = "data/duckdb/kidsights_local.duckdb",
#'   verbose = TRUE
#' )
#' }
#'
#' @export
create_ne25_calibration_table <- function(
  codebook_path = "codebook/data/codebook.json",
  db_path = "data/duckdb/kidsights_local.duckdb",
  verbose = TRUE
) {

  # ============================================================================
  # SETUP
  # ============================================================================

  if (verbose) {
    cat("\n")
    cat(stringr::str_dup("=", 80), "\n")
    cat("CREATE NE25 CALIBRATION TABLE\n")
    cat(stringr::str_dup("=", 80), "\n\n")
  }

  # Load required packages
  library(DBI)
  library(duckdb)
  library(jsonlite)
  library(dplyr)
  library(stringr)

  # ============================================================================
  # [1/7] LOAD CODEBOOK
  # ============================================================================

  if (verbose) {
    cat("[1/7] Loading codebook from:", codebook_path, "\n")
  }

  if (!file.exists(codebook_path)) {
    stop("Codebook not found at: ", codebook_path)
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Extract ALL items that have both ne25 and equate lexicons
  # (not just calibration_item == TRUE, which is only a subset)
  ne25_to_equate <- list()
  ne25_names <- character()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
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
      ne25_names <- c(ne25_names, ne25_name)
    }
  }

  if (length(ne25_to_equate) == 0) {
    stop("No items found with both ne25 and equate lexicons")
  }

  n_items <- length(ne25_to_equate)

  if (verbose) {
    cat("      Loaded", n_items, "items from codebook\n")
    # Show sample item names
    sample_items <- head(names(ne25_to_equate), 5)
    cat("      Sample items:", paste(sample_items, collapse = ", "), "\n")
  }

  # ============================================================================
  # [2/7] CONNECT TO DATABASE
  # ============================================================================

  if (verbose) {
    cat("\n[2/7] Connecting to database:", db_path, "\n")
  }

  if (!file.exists(db_path)) {
    stop("Database not found at: ", db_path)
  }

  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)

  # Verify ne25_transformed table exists
  tables <- DBI::dbListTables(con)
  if (!"ne25_transformed" %in% tables) {
    DBI::dbDisconnect(con, shutdown = TRUE)
    stop("ne25_transformed table not found in database")
  }

  # Check required columns exist
  columns <- DBI::dbListFields(con, "ne25_transformed")
  required_cols <- c("record_id", "pid", "years_old", "authenticity_weight", "meets_inclusion")
  missing_cols <- setdiff(required_cols, columns)

  if (length(missing_cols) > 0) {
    DBI::dbDisconnect(con, shutdown = TRUE)
    stop("Required columns missing from ne25_transformed: ",
         paste(missing_cols, collapse = ", "))
  }

  if (verbose) {
    cat("      Verified ne25_transformed table exists\n")
    cat("      Required columns present: meets_inclusion, authenticity_weight, years_old\n")
  }

  # ============================================================================
  # [3/7] QUERY DATA
  # ============================================================================

  if (verbose) {
    cat("\n[3/7] Querying NE25 data with meets_inclusion filter\n")
  }

  # Build SQL query with ne25 lexicon column names
  ne25_item_cols <- paste(ne25_names, collapse = ", ")

  sql_query <- paste0(
    "SELECT record_id, pid, years_old, authenticity_weight, ",
    ne25_item_cols,
    " FROM ne25_transformed WHERE meets_inclusion = TRUE"
  )

  # Execute query
  data <- DBI::dbGetQuery(con, sql_query)

  n_records <- nrow(data)

  if (verbose) {
    cat("      Loaded", n_records, "records (meets_inclusion=TRUE)\n")
  }

  if (n_records == 0) {
    DBI::dbDisconnect(con, shutdown = TRUE)
    stop("No records found with meets_inclusion=TRUE")
  }

  # ============================================================================
  # [4/7] TRANSFORM DATA
  # ============================================================================

  if (verbose) {
    cat("\n[4/7] Transforming data\n")
  }

  # Rename calibration items from ne25 → equate lexicon
  renamed_count <- 0
  dataset_cols <- names(data)

  for (ne25_name in names(ne25_to_equate)) {
    equate_name <- ne25_to_equate[[ne25_name]]

    # Check if ne25 column exists in dataset (case-insensitive match)
    match_idx <- which(tolower(dataset_cols) == tolower(ne25_name))

    if (length(match_idx) > 0) {
      actual_col <- dataset_cols[match_idx[1]]
      names(data)[match_idx[1]] <- equate_name
      dataset_cols[match_idx[1]] <- equate_name  # Update tracking
      renamed_count <- renamed_count + 1
    }
  }

  if (verbose) {
    cat("      Renamed", renamed_count, "items to equate lexicon\n")
  }

  # Create integer IDs: 250311 + row number
  # Format: 250311000001, 250311000002, ... 250311002831
  data <- data %>%
    dplyr::mutate(
      id = 250311000000 + dplyr::row_number()
    )

  # Rename years_old → years
  data <- data %>%
    dplyr::rename(years = years_old)

  # Select final columns: id, years, authenticity_weight + calibration items (now in equate lexicon)
  equate_item_names <- unlist(ne25_to_equate, use.names = FALSE)
  final_cols <- c("id", "years", "authenticity_weight", equate_item_names)

  # Only keep columns that exist in data
  final_cols <- final_cols[final_cols %in% names(data)]

  data <- data %>%
    dplyr::select(dplyr::all_of(final_cols))

  n_columns <- ncol(data)

  if (verbose) {
    cat("      Created integer IDs (250311000001 to ", max(data$id), ")\n", sep = "")
    cat("      Final structure:", n_columns, "columns (id, years, authenticity_weight,",
        n_columns - 3, "items)\n")
  }

  # ============================================================================
  # [5/7] WRITE TO DATABASE
  # ============================================================================

  if (verbose) {
    cat("\n[5/7] Writing to database\n")
  }

  # Drop existing table if it exists
  if ("ne25_calibration" %in% DBI::dbListTables(con)) {
    DBI::dbExecute(con, "DROP TABLE ne25_calibration")
    if (verbose) {
      cat("      Dropped existing ne25_calibration table\n")
    }
  }

  # Write new table
  DBI::dbWriteTable(con, "ne25_calibration", data, overwrite = TRUE)

  if (verbose) {
    cat("      Inserted", n_records, "records with", n_columns, "columns\n")
  }

  # Create indexes
  DBI::dbExecute(con, "CREATE INDEX idx_ne25_calibration_id ON ne25_calibration(id)")
  DBI::dbExecute(con, "CREATE INDEX idx_ne25_calibration_years ON ne25_calibration(years)")

  if (verbose) {
    cat("      Created indexes on id and years\n")
  }

  # ============================================================================
  # [6/7] VALIDATE OUTPUT
  # ============================================================================

  if (verbose) {
    cat("\n[6/7] Validating output\n")
  }

  # Verify record count
  count_check <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM ne25_calibration")$n
  if (count_check != n_records) {
    warning("Record count mismatch: expected ", n_records, ", got ", count_check)
  } else {
    if (verbose) cat("      Record count:", count_check, "[OK]\n")
  }

  # Verify column count
  cols_check <- length(DBI::dbListFields(con, "ne25_calibration"))
  if (cols_check != n_columns) {
    warning("Column count mismatch: expected ", n_columns, ", got ", cols_check)
  } else {
    if (verbose) cat("      Column count:", cols_check, "[OK]\n")
  }

  # Check authenticity_weight range
  weight_stats <- DBI::dbGetQuery(
    con,
    "SELECT MIN(authenticity_weight) as min_wgt, MAX(authenticity_weight) as max_wgt FROM ne25_calibration"
  )

  if (verbose) {
    cat("      Weight range: [", round(weight_stats$min_wgt, 4), ", ",
        round(weight_stats$max_wgt, 4), "] [OK]\n", sep = "")
  }

  # Check age range
  age_stats <- DBI::dbGetQuery(
    con,
    "SELECT MIN(years) as min_age, MAX(years) as max_age FROM ne25_calibration"
  )

  if (verbose) {
    cat("      Age range: [", round(age_stats$min_age, 2), ", ",
        round(age_stats$max_age, 2), "] [OK]\n", sep = "")
  }

  # ============================================================================
  # [7/7] COMPLETE
  # ============================================================================

  if (verbose) {
    cat("\n[7/7] Complete\n")
    cat("      Table: ne25_calibration\n")
    cat("      Size: Optimized (excluded demographics, geography, ACEs, childcare)\n")
    cat("      Records:", n_records, "\n")
    cat("      Columns:", n_columns, "(id, years, authenticity_weight +", n_columns - 3, "items)\n")
  }

  # Disconnect
  DBI::dbDisconnect(con, shutdown = TRUE)

  if (verbose) {
    cat("\n")
    cat(stringr::str_dup("=", 80), "\n\n")
  }

  # Return metrics invisibly
  invisible(list(
    n_records = n_records,
    n_columns = n_columns,
    weight_range = c(weight_stats$min_wgt, weight_stats$max_wgt),
    age_range = c(age_stats$min_age, age_stats$max_age)
  ))
}

# ============================================================================
# STANDALONE EXECUTION
# ============================================================================

# If script is run directly (not sourced), execute the function
if (!interactive()) {
  create_ne25_calibration_table(
    codebook_path = "codebook/data/codebook.json",
    db_path = "data/duckdb/kidsights_local.duckdb",
    verbose = TRUE
  )
}

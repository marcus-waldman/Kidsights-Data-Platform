#' DuckDB Connection Management for Kidsights Data Platform
#'
#' Functions for connecting to and managing the DuckDB database
#' stored on OneDrive

library(duckdb)
library(DBI)

# Default database path
KIDSIGHTS_DB_PATH <- "C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB/kidsights.duckdb"

#' Connect to Kidsights DuckDB database
#'
#' @param db_path Path to DuckDB database file
#' @param read_only Logical, connect in read-only mode
#' @return DuckDB connection object
connect_kidsights_db <- function(db_path = KIDSIGHTS_DB_PATH, read_only = FALSE) {

  # Ensure directory exists
  db_dir <- dirname(db_path)
  if (!dir.exists(db_dir)) {
    dir.create(db_dir, recursive = TRUE)
    message(paste("Created database directory:", db_dir))
  }

  # Create connection
  drv <- duckdb::duckdb()
  con <- DBI::dbConnect(drv, dbdir = db_path, read_only = read_only)

  message(paste("Connected to DuckDB at:", db_path))
  return(con)
}

#' Disconnect from DuckDB and close driver
#'
#' @param con DuckDB connection object
disconnect_kidsights_db <- function(con) {
  if (!is.null(con) && DBI::dbIsValid(con)) {
    DBI::dbDisconnect(con, shutdown = TRUE)
    message("Disconnected from DuckDB")
  }
}

#' Initialize DuckDB schema for NE25 data
#'
#' @param con DuckDB connection
#' @param schema_file Path to SQL schema file
#' @return Logical indicating success
init_ne25_schema <- function(con, schema_file = "schemas/landing/ne25.sql") {

  if (!file.exists(schema_file)) {
    stop(paste("Schema file not found:", schema_file))
  }

  tryCatch({
    # Read and execute schema
    schema_sql <- readLines(schema_file, warn = FALSE)
    schema_sql <- paste(schema_sql, collapse = "\n")

    # Remove comments and empty lines
    schema_sql <- gsub("--.*", "", schema_sql)
    schema_sql <- gsub("\\n\\s*\\n", "\n", schema_sql)

    # Split on semicolons to get individual statements
    statements <- strsplit(schema_sql, ";", fixed = TRUE)[[1]]
    statements <- trimws(statements)
    statements <- statements[nzchar(statements)]

    # Execute each statement
    for (statement in statements) {
      if (nzchar(statement) && !grepl("^\\s*$", statement)) {
        DBI::dbExecute(con, statement)
      }
    }

    message("Successfully initialized NE25 schema")
    return(TRUE)

  }, error = function(e) {
    message(paste("Error initializing schema:", e$message))
    return(FALSE)
  })
}

#' Insert data into NE25 raw table
#'
#' @param con DuckDB connection
#' @param data Data frame to insert
#' @param table_name Target table name
#' @param overwrite Logical, whether to overwrite existing data
#' @return Number of rows inserted
insert_ne25_data <- function(con, data, table_name = "ne25_raw", overwrite = FALSE) {

  if (nrow(data) == 0) {
    message("No data to insert")
    return(0)
  }

  tryCatch({

    # Use dbWriteTable which can create table if it doesn't exist
    DBI::dbWriteTable(con, table_name, data, append = !overwrite, overwrite = overwrite)
    message(paste("Inserted", nrow(data), "rows into", table_name))

    return(nrow(data))

  }, error = function(e) {
    message(paste("Error inserting data:", e$message))
    return(0)
  })
}

#' Upsert data into NE25 tables (insert or update)
#'
#' @param con DuckDB connection
#' @param data Data frame to upsert
#' @param table_name Target table name
#' @param key_cols Key columns for upsert logic
#' @return Number of rows affected
upsert_ne25_data <- function(con, data, table_name, key_cols = c("record_id", "pid", "retrieved_date")) {

  if (nrow(data) == 0) {
    message("No data to upsert")
    return(0)
  }

  tryCatch({

    # Create a temporary table
    temp_table <- paste0("temp_", table_name, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    DBI::dbWriteTable(con, temp_table, data, temporary = TRUE)

    # Build upsert query
    all_cols <- names(data)
    key_cols <- intersect(key_cols, all_cols)
    update_cols <- setdiff(all_cols, key_cols)

    # Generate WHERE clause for matching
    where_clause <- paste(
      paste0("t.", key_cols, " = s.", key_cols),
      collapse = " AND "
    )

    # Generate SET clause for updates
    set_clause <- paste(
      paste0(update_cols, " = s.", update_cols),
      collapse = ", "
    )

    # Perform upsert
    upsert_sql <- paste0("
      INSERT OR REPLACE INTO ", table_name, "
      SELECT * FROM ", temp_table)

    rows_affected <- DBI::dbExecute(con, upsert_sql)

    # Clean up temp table
    DBI::dbExecute(con, paste("DROP TABLE", temp_table))

    message(paste("Upserted", rows_affected, "rows in", table_name))
    return(rows_affected)

  }, error = function(e) {
    message(paste("Error upserting data:", e$message))
    return(0)
  })
}

#' Get data from NE25 tables with optional filtering
#'
#' @param con DuckDB connection
#' @param table_name Table to query
#' @param where_clause Optional WHERE clause
#' @param limit Optional row limit
#' @return Data frame with query results
get_ne25_data <- function(con, table_name, where_clause = NULL, limit = NULL) {

  query <- paste("SELECT * FROM", table_name)

  if (!is.null(where_clause)) {
    query <- paste(query, "WHERE", where_clause)
  }

  if (!is.null(limit)) {
    query <- paste(query, "LIMIT", limit)
  }

  tryCatch({
    result <- DBI::dbGetQuery(con, query)
    message(paste("Retrieved", nrow(result), "rows from", table_name))
    return(result)

  }, error = function(e) {
    message(paste("Error querying data:", e$message))
    return(data.frame())
  })
}

#' Get summary statistics from NE25 database
#'
#' @param con DuckDB connection
#' @return List with summary statistics
get_ne25_summary <- function(con) {

  summary_stats <- list()

  tables <- c("ne25_raw", "ne25_eligibility", "ne25_harmonized")

  for (table in tables) {
    tryCatch({
      count_query <- paste("SELECT COUNT(*) as n FROM", table)
      count_result <- DBI::dbGetQuery(con, count_query)
      summary_stats[[table]] <- count_result$n[1]
    }, error = function(e) {
      summary_stats[[table]] <- 0
    })
  }

  # Get eligibility statistics
  tryCatch({
    eligibility_query <- "
      SELECT
        COUNT(*) as total,
        COUNT(CASE WHEN include = TRUE THEN 1 END) as included,
        ROUND(100.0 * COUNT(CASE WHEN include = TRUE THEN 1 END) / COUNT(*), 1) as inclusion_rate
      FROM ne25_eligibility"

    eligibility_stats <- DBI::dbGetQuery(con, eligibility_query)
    summary_stats[["eligibility"]] <- eligibility_stats

  }, error = function(e) {
    summary_stats[["eligibility"]] <- data.frame(total = 0, included = 0, inclusion_rate = 0)
  })

  # Get project breakdown
  tryCatch({
    project_query <- "
      SELECT
        source_project,
        COUNT(*) as n
      FROM ne25_raw
      GROUP BY source_project
      ORDER BY n DESC"

    project_stats <- DBI::dbGetQuery(con, project_query)
    summary_stats[["projects"]] <- project_stats

  }, error = function(e) {
    summary_stats[["projects"]] <- data.frame(source_project = character(), n = integer())
  })

  return(summary_stats)
}

#' Execute arbitrary SQL query on NE25 database
#'
#' @param con DuckDB connection
#' @param query SQL query string
#' @param params Optional query parameters
#' @return Query results
query_ne25_db <- function(con, query, params = NULL) {

  tryCatch({
    if (!is.null(params)) {
      result <- DBI::dbGetQuery(con, query, params = params)
    } else {
      result <- DBI::dbGetQuery(con, query)
    }
    return(result)

  }, error = function(e) {
    message(paste("Error executing query:", e$message))
    return(data.frame())
  })
}

#' Log pipeline execution to database
#'
#' @param con DuckDB connection
#' @param execution_id Unique execution identifier
#' @param pipeline_type Type of pipeline run
#' @param metrics List of execution metrics
#' @param status Execution status
#' @param error_message Optional error message
log_pipeline_execution <- function(con, execution_id, pipeline_type, metrics, status, error_message = NULL) {

  log_data <- data.frame(
    execution_id = execution_id,
    execution_date = Sys.time(),
    pipeline_type = pipeline_type,
    projects_attempted = paste(metrics$projects_attempted %||% character(), collapse = ","),
    projects_successful = paste(metrics$projects_successful %||% character(), collapse = ","),
    total_records_extracted = metrics$total_records_extracted %||% 0,
    extraction_errors = metrics$extraction_errors %||% "",
    records_processed = metrics$records_processed %||% 0,
    records_eligible = metrics$records_eligible %||% 0,
    records_authentic = metrics$records_authentic %||% 0,
    records_included = metrics$records_included %||% 0,
    extraction_duration_seconds = metrics$extraction_duration %||% 0,
    processing_duration_seconds = metrics$processing_duration %||% 0,
    total_duration_seconds = metrics$total_duration %||% 0,
    status = status,
    error_message = error_message,
    config_version = "1.0.0",
    r_version = paste(R.version$major, R.version$minor, sep = ".")
  )

  insert_ne25_data(con, log_data, "ne25_pipeline_log")
}
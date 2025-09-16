#' Data Dictionary Storage Functions for DuckDB
#'
#' Functions for storing and retrieving REDCap data dictionaries in the database

library(duckdb)
library(DBI)

#' Insert REDCap data dictionary into database
#'
#' @param con DuckDB connection
#' @param dictionary_df REDCap data dictionary data frame
#' @param source_project Project name for tracking source
#' @param overwrite Logical, whether to overwrite existing dictionary for this project
#' @return Number of rows inserted
insert_data_dictionary <- function(con, dictionary_df, source_project, overwrite = FALSE) {

  if (nrow(dictionary_df) == 0) {
    message(paste("No data dictionary to insert for project:", source_project))
    return(0)
  }

  # Add source project metadata
  dictionary_df$source_project <- source_project
  dictionary_df$created_at <- Sys.time()

  tryCatch({

    if (overwrite) {
      # Remove existing dictionary for this project
      delete_sql <- "DELETE FROM ne25_data_dictionary WHERE source_project = ?"
      DBI::dbExecute(con, delete_sql, params = list(source_project))
      message(paste("Cleared existing dictionary for project:", source_project))
    }

    # Insert dictionary data using dbWriteTable for flexibility
    DBI::dbWriteTable(con, "ne25_data_dictionary", dictionary_df, append = TRUE, overwrite = FALSE)
    rows_inserted <- nrow(dictionary_df)
    message(paste("Inserted", rows_inserted, "dictionary fields for project:", source_project))

    return(rows_inserted)

  }, error = function(e) {
    message(paste("Error inserting data dictionary for", source_project, ":", e$message))
    return(0)
  })
}

#' Get data dictionary summary
#'
#' @param con DuckDB connection
#' @param source_project Optional project filter
#' @return Data frame with dictionary summary
get_data_dictionary_summary <- function(con, source_project = NULL) {

  base_query <- "
    SELECT
      source_project,
      pid,
      COUNT(*) as n_fields,
      COUNT(CASE WHEN field_type = 'text' THEN 1 END) as n_text,
      COUNT(CASE WHEN field_type = 'dropdown' THEN 1 END) as n_dropdown,
      COUNT(CASE WHEN field_type = 'radio' THEN 1 END) as n_radio,
      COUNT(CASE WHEN field_type = 'checkbox' THEN 1 END) as n_checkbox,
      COUNT(CASE WHEN field_type = 'yesno' THEN 1 END) as n_yesno,
      COUNT(CASE WHEN required_field = 'y' THEN 1 END) as n_required,
      COUNT(DISTINCT form_name) as n_forms
    FROM ne25_data_dictionary"

  if (!is.null(source_project)) {
    query <- paste(base_query, "WHERE source_project =", shQuote(source_project), "GROUP BY source_project, pid")
  } else {
    query <- paste(base_query, "GROUP BY source_project, pid ORDER BY pid, n_fields DESC")
  }

  tryCatch({
    dictionary_summary <- DBI::dbGetQuery(con, query)
    return(dictionary_summary)

  }, error = function(e) {
    message(paste("Error getting data dictionary summary:", e$message))
    return(data.frame())
  })
}

#' Get complete data dictionary for a project
#'
#' @param con DuckDB connection
#' @param source_project Project name
#' @return Data frame with complete dictionary
get_project_dictionary <- function(con, source_project) {

  query <- "
    SELECT
      field_name,
      form_name,
      section_header,
      field_type,
      field_label,
      select_choices_or_calculations,
      field_note,
      text_validation_type_or_show_slider_number,
      text_validation_min,
      text_validation_max,
      identifier,
      branching_logic,
      required_field,
      custom_alignment,
      question_number,
      matrix_group_name,
      matrix_ranking,
      field_annotation,
      created_at
    FROM ne25_data_dictionary
    WHERE source_project = ?
    ORDER BY form_name, field_name"

  tryCatch({
    project_dict <- DBI::dbGetQuery(con, query, params = list(source_project))
    return(project_dict)

  }, error = function(e) {
    message(paste("Error getting dictionary for", source_project, ":", e$message))
    return(data.frame())
  })
}

#' Get all stored project names
#'
#' @param con DuckDB connection
#' @return Character vector of project names
get_stored_projects <- function(con) {

  query <- "SELECT DISTINCT source_project FROM ne25_data_dictionary ORDER BY source_project"

  tryCatch({
    result <- DBI::dbGetQuery(con, query)
    return(result$source_project)

  }, error = function(e) {
    message(paste("Error getting stored projects:", e$message))
    return(character())
  })
}
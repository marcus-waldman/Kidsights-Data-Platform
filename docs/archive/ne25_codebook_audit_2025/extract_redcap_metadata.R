#!/usr/bin/env Rscript
#' REDCap Metadata Extraction for NE25 Audit
#'
#' Extracts field definitions directly from REDCap API to establish ground truth
#' for value labels and response options. This serves as the source of truth
#' for comparing against codebook definitions and dictionary output.
#'
#' @author Kidsights Data Platform
#' @date 2025-09-18

# Load required packages with explicit namespacing
library(httr)
library(jsonlite)
library(dplyr)
library(stringr)
library(purrr)

# Source project functions for consistency
source("R/extract/ne25.R")

#' Extract and parse REDCap metadata for audit purposes
#'
#' @param project_pid Project ID to extract from (default: 7679)
#' @param output_file Path to save extracted metadata (optional)
#' @return List containing parsed metadata and PS items analysis
extract_redcap_audit_metadata <- function(project_pid = 7679, output_file = NULL) {

  cat("=== REDCap Metadata Extraction Starting ===\n")
  cat("Target project PID:", project_pid, "\n")

  # DEBUG: Load API credentials
  credentials_file <- "C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv"
  cat("Loading credentials from:", credentials_file, "\n")

  if (!file.exists(credentials_file)) {
    stop("ERROR: API credentials file not found: ", credentials_file)
  }

  credentials <- readr::read_csv(credentials_file, show_col_types = FALSE)
  cat("Credentials loaded. Projects available:", nrow(credentials), "\n")

  # DEBUG: Find token for specified project
  project_row <- credentials %>% dplyr::filter(pid == project_pid)

  if (nrow(project_row) == 0) {
    stop("ERROR: No credentials found for project PID ", project_pid)
  }

  api_token <- project_row$api_code[1]
  cat("API token found for PID", project_pid, "(token length:", nchar(api_token), ")\n")

  # DEBUG: Make REDCap API request
  redcap_url <- "https://unmcredcap.unmc.edu/redcap/api/"
  cat("Making API request to:", redcap_url, "\n")

  form_data <- list(
    "token" = api_token,
    "content" = 'metadata',
    "format" = 'json',
    "returnFormat" = 'json'
  )

  tryCatch({
    response <- httr::POST(redcap_url, body = form_data, encode = "form")
    cat("API response status:", httr::status_code(response), "\n")

    if (httr::status_code(response) != 200) {
      stop("REDCap API error: ", httr::status_code(response), " - ", httr::content(response, as = "text"))
    }

    # Parse JSON response
    response_text <- httr::content(response, as = "text", encoding = "UTF-8")
    cat("Response text length:", nchar(response_text), "characters\n")

    metadata_list <- jsonlite::fromJSON(response_text, flatten = TRUE)
    cat("Metadata parsed. Total fields:", nrow(metadata_list), "\n")

  }, error = function(e) {
    stop("ERROR in API request: ", e$message)
  })

  # DEBUG: Convert to data frame and examine structure
  metadata_df <- as.data.frame(metadata_list)
  cat("Metadata columns:", paste(colnames(metadata_df), collapse = ", "), "\n")

  # DEBUG: Focus on ALL fields with response options
  cat("\n=== Analyzing ALL Fields with Response Options ===\n")

  # Get all fields with response options (select_choices_or_calculations)
  fields_with_options <- metadata_df %>%
    dplyr::filter(!is.na(select_choices_or_calculations) &
                  select_choices_or_calculations != "") %>%
    dplyr::select(field_name, field_label, field_type, select_choices_or_calculations,
                  required_field, text_validation_type_or_show_slider_number)

  cat("Total fields with response options found:", nrow(fields_with_options), "\n")

  if (nrow(fields_with_options) > 0) {
    # Analyze field types
    cat("Field types with response options:\n")
    field_types <- fields_with_options %>% dplyr::count(field_type, sort = TRUE)
    print(field_types)

    # Analyze field name patterns
    cat("\nField name patterns (first 2 characters):\n")
    fields_with_options <- fields_with_options %>%
      dplyr::mutate(field_prefix = substr(field_name, 1, 2))

    prefix_counts <- fields_with_options %>%
      dplyr::count(field_prefix, sort = TRUE)
    print(prefix_counts)

    # Show examples from different prefixes
    cat("\nExamples from different field prefixes:\n")
    top_prefixes <- head(prefix_counts$field_prefix, 5)

    for (prefix in top_prefixes) {
      example_field <- fields_with_options %>%
        dplyr::filter(field_prefix == prefix) %>%
        dplyr::slice(1)

      if (nrow(example_field) > 0) {
        cat("\n", prefix, "* fields:\n", sep = "")
        cat("- Example:", example_field$field_name[1], "\n")
        cat("- Label:", example_field$field_label[1], "\n")
        cat("- Type:", example_field$field_type[1], "\n")
        cat("- Options (first 80 chars):", substr(example_field$select_choices_or_calculations[1], 1, 80), "...\n")
      }
    }
  }

  # DEBUG: Parse response options for ALL fields
  cat("\n=== Parsing Response Options for All Fields ===\n")

  all_fields_parsed <- fields_with_options %>%
    dplyr::mutate(
      has_options = !is.na(select_choices_or_calculations) &
                    select_choices_or_calculations != "",
      parsed_options = purrr::map(select_choices_or_calculations, parse_redcap_options)
    )

  # Count fields with successfully parsed options
  fields_with_parsed <- all_fields_parsed %>%
    dplyr::filter(purrr::map_lgl(parsed_options, ~ !is.null(.x) && nrow(.x) > 0))

  cat("Fields with successfully parsed options:", nrow(fields_with_parsed), "\n")

  # Sample parsing results by field prefix
  if (nrow(fields_with_parsed) > 0) {
    cat("\nSample parsing results by prefix:\n")

    for (prefix in head(prefix_counts$field_prefix, 3)) {
      prefix_fields <- fields_with_parsed %>%
        dplyr::filter(field_prefix == prefix) %>%
        dplyr::slice(1)

      if (nrow(prefix_fields) > 0) {
        cat("\n", prefix, "* example (", prefix_fields$field_name[1], "):\n", sep = "")
        parsed_opts <- prefix_fields$parsed_options[[1]]
        if (!is.null(parsed_opts) && nrow(parsed_opts) > 0) {
          cat("Values:", paste(parsed_opts$value, collapse = ", "), "\n")
          cat("Labels:", paste(parsed_opts$label, collapse = " | "), "\n")
        }
      }
    }
  }

  # DEBUG: Save intermediate results
  if (!is.null(output_file)) {
    cat("Saving results to:", output_file, "\n")
    saveRDS(list(
      full_metadata = metadata_df,
      fields_with_options = all_fields_parsed,
      field_prefix_analysis = prefix_counts,
      extraction_timestamp = Sys.time(),
      project_pid = project_pid
    ), output_file)
  }

  # Return comprehensive results
  result <- list(
    metadata = metadata_df,
    fields_with_options = all_fields_parsed,
    prefix_analysis = prefix_counts,
    summary = list(
      total_fields = nrow(metadata_df),
      fields_with_options = nrow(fields_with_options),
      fields_with_parsed_options = nrow(fields_with_parsed),
      unique_prefixes = nrow(prefix_counts),
      extraction_time = Sys.time(),
      project_pid = project_pid
    )
  )

  cat("\n=== REDCap Metadata Extraction Complete ===\n")
  cat("Summary:\n")
  cat("- Total fields extracted:", result$summary$total_fields, "\n")
  cat("- Fields with response options:", result$summary$fields_with_options, "\n")
  cat("- Fields with parsed options:", result$summary$fields_with_parsed_options, "\n")
  cat("- Unique field prefixes:", result$summary$unique_prefixes, "\n")

  return(result)
}

#' Parse REDCap response options from select_choices_or_calculations field
#'
#' REDCap stores options in format: "0, Never | 1, Sometimes | 2, Often | 9, Don't Know"
#'
#' @param options_string Character string from REDCap metadata
#' @return Data frame with value and label columns, or NULL if no options
parse_redcap_options <- function(options_string) {

  # DEBUG: Handle missing or empty options
  if (is.na(options_string) || options_string == "" || is.null(options_string)) {
    return(NULL)
  }

  tryCatch({
    # Split by pipe separator
    option_pairs <- stringr::str_split(options_string, "\\|")[[1]]
    option_pairs <- stringr::str_trim(option_pairs)

    # Parse each pair (value, label)
    parsed_options <- purrr::map_df(option_pairs, function(pair) {
      # Split by first comma
      parts <- stringr::str_split(pair, ",", n = 2)[[1]]

      if (length(parts) == 2) {
        value <- stringr::str_trim(parts[1])
        label <- stringr::str_trim(parts[2])

        return(tibble::tibble(
          value = value,
          label = label
        ))
      } else {
        # Handle malformed options
        return(tibble::tibble(
          value = stringr::str_trim(pair),
          label = stringr::str_trim(pair)
        ))
      }
    })

    return(parsed_options)

  }, error = function(e) {
    warning("Failed to parse options: ", options_string, " - Error: ", e$message)
    return(NULL)
  })
}

# Main execution block
if (!interactive()) {
  cat("Running REDCap metadata extraction...\n")

  # Extract metadata and save results
  output_path <- "scripts/audit/ne25_codebook/data/redcap_metadata.rds"

  metadata_results <- extract_redcap_audit_metadata(
    project_pid = 7679,
    output_file = output_path
  )

  cat("Results saved to:", output_path, "\n")
  cat("Script execution complete.\n")
}
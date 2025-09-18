#' NE25 REDCap Data Extraction Functions
#'
#' Functions for extracting, validating, and preprocessing data from the
#' Nebraska 2025 (NE25) longitudinal study REDCap projects.
#'
#' Based on the original dashboard utils-etl.R functions, adapted for
#' the multi-source ETL architecture.

library(REDCapR)
library(httr)
library(dplyr)
library(purrr)
library(stringr)
library(yaml)

#' Extract NE25 survey responses from REDCap
#'
#' Adapted from download_vet_responses() in the dashboard
#'
#' @param config_path Path to NE25 configuration file
#' @param projects Vector of project names to extract (defaults to all)
#' @param forms Vector of form names to extract (defaults to all configured)
#' @param incremental Logical, whether to perform incremental extraction
#' @return List containing data, dictionary, and extraction metadata
extract_ne25_data <- function(config_path = "config/sources/ne25.yaml",
                              projects = NULL,
                              forms = NULL,
                              incremental = FALSE) {

  # Load configuration
  config <- yaml::read_yaml(config_path)

  # Determine which projects to extract
  if (is.null(projects)) {
    projects <- config$redcap$projects
  }

  # Initialize results
  all_data <- list()
  all_dictionaries <- list()
  extraction_metadata <- list(
    extracted_at = Sys.time(),
    config_file = config_path,
    projects_extracted = character(),
    total_records = 0,
    extraction_errors = list()
  )

  # Extract from each project
  for (project_info in projects) {

    project_name <- project_info$name
    token_env <- project_info$token_env

    tryCatch({

      # Get API token from environment
      api_token <- Sys.getenv(token_env)
      if (api_token == "") {
        stop(paste("API token not found in environment variable:", token_env))
      }

      message(paste("Extracting data from project:", project_name))

      # Extract survey data
      project_data <- extract_redcap_project_data(
        url = config$redcap$url,
        token = api_token,
        forms = forms,
        config = config
      )

      # Extract data dictionary
      project_dict <- extract_redcap_dictionary(
        url = config$redcap$url,
        token = api_token
      )

      # Add project metadata
      project_data <- project_data %>%
        dplyr::mutate(
          retrieved_date = Sys.time(),
          source_project = project_name,
          extraction_id = paste0(project_name, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
        ) %>%
        dplyr::relocate(retrieved_date, source_project, extraction_id)

      # Store results
      all_data[[project_name]] <- project_data
      all_dictionaries[[project_name]] <- project_dict

      # Update metadata
      extraction_metadata$projects_extracted <- c(extraction_metadata$projects_extracted, project_name)
      extraction_metadata$total_records <- extraction_metadata$total_records + nrow(project_data)

      message(paste("Successfully extracted", nrow(project_data), "records from", project_name))

    }, error = function(e) {
      error_msg <- paste("Failed to extract from", project_name, ":", e$message)
      warning(error_msg)
      extraction_metadata$extraction_errors[[project_name]] <- error_msg
    })

    # Rate limiting
    Sys.sleep(1)
  }

  # Combine data from all projects using dashboard's flexible_bind_rows
  if (length(all_data) > 0) {
    message("Combining data from all projects using flexible_bind_rows...")
    combined_data <- flexible_bind_rows(all_data)

    # Use dictionary from first project (like dashboard does)
    combined_dictionary <- all_dictionaries[[1]]
  } else {
    stop("No data was successfully extracted from any project")
  }

  # Apply minimal cleaning (like dashboard)
  cleaned_data <- combined_data %>%
    dplyr::mutate(sq001 = as.character(sq001))  # Ensure ZIP codes are character like dashboard

  return(list(
    data = cleaned_data,
    dictionary = combined_dictionary,
    extraction_metadata = extraction_metadata,
    source_config = config
  ))
}

#' Flexible bind_rows function from dashboard (handles type conflicts automatically)
#'
#' @param ... Data frames to bind or a list of data frames
#' @param .id Optional column name to identify source data frame
#' @return Combined data frame with resolved type conflicts
flexible_bind_rows <- function(..., .id = NULL) {
  # Load required library
  library(dplyr)

  # Get all data frames - handle both multiple arguments and list input
  args <- list(...)

  # If first argument is a list and it's the only argument, use it as the list of data frames
  if (length(args) == 1 && is.list(args[[1]]) && !is.data.frame(args[[1]])) {
    dfs <- args[[1]]
  } else {
    # Otherwise, treat all arguments as individual data frames
    dfs <- args
  }

  # Handle empty input
  if (length(dfs) == 0) {
    return(data.frame())
  }

  # Define data type hierarchy (1 = lowest, 4 = highest)
  type_hierarchy <- function(type) {
    switch(type,
           "logical" = 1,
           "integer" = 2,
           "numeric" = 3,
           "double" = 3,   # treat double same as numeric
           "character" = 4,
           4)  # default to character level for unknown types
  }

  # Function to convert to target type
  convert_to_type <- function(x, target_type) {
    switch(target_type,
           "logical" = as.logical(x),
           "integer" = as.integer(x),
           "numeric" = as.numeric(x),
           "double" = as.numeric(x),
           "character" = as.character(x),
           as.character(x))  # default to character
  }

  # If .id is specified, add it to each data frame
  if (!is.null(.id)) {
    for (i in seq_along(dfs)) {
      dfs[[i]][[.id]] <- i
    }
  }

  # Get all unique column names across all data frames
  all_cols <- unique(unlist(lapply(dfs, names)))

  # For each column, determine the highest type in hierarchy and convert all instances
  for (col in all_cols) {
    # Get the types of this column across all data frames that have it
    col_types <- character()
    df_indices_with_col <- integer()

    for (i in seq_along(dfs)) {
      if (col %in% names(dfs[[i]])) {
        col_types <- c(col_types, class(dfs[[i]][[col]])[1])
        df_indices_with_col <- c(df_indices_with_col, i)
      }
    }

    # Find the highest type in the hierarchy
    hierarchy_levels <- sapply(col_types, type_hierarchy)
    max_hierarchy <- max(hierarchy_levels)

    # Determine the target type
    target_type <- names(which(sapply(c("logical", "integer", "numeric", "character"),
                                      function(t) type_hierarchy(t) == max_hierarchy))[1])

    # If there are conflicts (more than one unique type), convert all instances
    if (length(unique(col_types)) > 1) {
      cat("Converting column '", col, "' from types [",
          paste(unique(col_types), collapse = ", "), "] to '", target_type,
          "' following hierarchy\n", sep = "")

      # Convert to target type in all data frames that have this column
      for (i in df_indices_with_col) {
        dfs[[i]][[col]] <- convert_to_type(dfs[[i]][[col]], target_type)
      }
    }
  }

  # Now use dplyr::bind_rows since all conflicts are resolved
  return(dplyr::bind_rows(dfs))
}

#' Extract data from a single REDCap project
#'
#' @param url REDCap API URL
#' @param token API token
#' @param forms Vector of form names to extract
#' @param config Configuration list
#' @return Data frame with survey responses
extract_redcap_project_data <- function(url, token, forms = NULL, config) {

  # Build REDCap request
  redcap_request <- list(
    redcap_uri = url,
    token = token,
    raw_or_label = "raw",
    raw_or_label_headers = "raw",
    export_checkbox_label = FALSE,
    export_survey_fields = TRUE,
    export_data_access_groups = FALSE
  )

  # Add forms filter if specified
  if (!is.null(forms)) {
    redcap_request$forms <- forms
  }

  # Execute REDCap extraction with retry logic
  max_retries <- config$redcap$rate_limit$retry_attempts %||% 3
  retry_delay <- config$redcap$rate_limit$retry_delay %||% 5

  for (attempt in 1:max_retries) {
    tryCatch({

      result <- REDCapR::redcap_read(
        redcap_uri = redcap_request$redcap_uri,
        token = redcap_request$token,
        raw_or_label = redcap_request$raw_or_label,
        raw_or_label_headers = redcap_request$raw_or_label_headers,
        export_checkbox_label = redcap_request$export_checkbox_label,
        export_survey_fields = redcap_request$export_survey_fields,
        export_data_access_groups = redcap_request$export_data_access_groups,
        forms = redcap_request$forms
      )

      if (result$success) {
        return(result$data)
      } else {
        stop(paste("REDCap API error:", result$outcome_message))
      }

    }, error = function(e) {
      if (attempt == max_retries) {
        stop(paste("Failed after", max_retries, "attempts:", e$message))
      }
      warning(paste("Attempt", attempt, "failed, retrying in", retry_delay, "seconds:", e$message))
      Sys.sleep(retry_delay)
    })
  }
}

#' Extract REDCap data dictionary
#'
#' @param url REDCap API URL
#' @param token API token
#' @return List with field definitions
extract_redcap_dictionary <- function(url, token) {

  # Build metadata request
  form_data <- list(
    "token" = token,
    "content" = 'metadata',
    "format" = 'json',
    "returnFormat" = 'json'
  )

  # Make API request
  response <- httr::POST(url, body = form_data, encode = "form")

  if (httr::status_code(response) != 200) {
    stop(paste("REDCap metadata API error:", httr::status_code(response)))
  }

  # Parse response
  dict_list <- httr::content(response)

  # Convert to named list
  dict_named <- list()
  for (i in 1:length(dict_list)) {
    field_name <- dict_list[[i]]$field_name
    dict_named[[field_name]] <- dict_list[[i]]
  }

  return(dict_named)
}

#' Combine data dictionaries from multiple projects
#'
#' @param dict_list List of data dictionaries
#' @return Combined data dictionary
combine_data_dictionaries <- function(dict_list) {

  if (length(dict_list) == 1) {
    return(dict_list[[1]])
  }

  # Combine all dictionaries
  combined_dict <- list()

  for (project_name in names(dict_list)) {
    project_dict <- dict_list[[project_name]]

    for (field_name in names(project_dict)) {
      if (!field_name %in% names(combined_dict)) {
        combined_dict[[field_name]] <- project_dict[[field_name]]
        # Add source project information
        combined_dict[[field_name]]$source_project <- project_name
      } else {
        # Field exists in multiple projects - add to source list
        if (is.character(combined_dict[[field_name]]$source_project)) {
          combined_dict[[field_name]]$source_project <- c(
            combined_dict[[field_name]]$source_project,
            project_name
          )
        }
      }
    }
  }

  return(combined_dict)
}

#' Apply initial data cleaning to NE25 data
#'
#' Based on the cleaning logic in the original download_vet_responses()
#'
#' @param data Raw REDCap data
#' @param config Configuration list
#' @return Cleaned data frame
clean_ne25_initial <- function(data, config) {

  # Get NE25-specific items that need don't know handling
  ne25_items <- get_ne25_items_from_codebook(config)

  # Convert don't know responses to missing
  dont_know_codes <- config$validation$dont_know_codes %||% c(9, "9")

  cleaned_data <- data %>%
    dplyr::mutate(
      across(
        any_of(ne25_items),
        function(y) {
          ynew <- y
          ynew[abs(as.numeric(y)) %in% abs(as.numeric(dont_know_codes))] <- NA
          return(ynew)
        }
      )
    )

  # Apply reverse coding to specified items
  reverse_items <- config$recoding$reverse_coded_items %||% c("nom054x", "nom052y", "nom056x")

  for (item in reverse_items) {
    if (item %in% names(cleaned_data)) {
      cleaned_data <- cleaned_data %>%
        dplyr::mutate(!!item := abs(!!sym(item) - 4))
    }
  }

  # Ensure sq001 (ZIP code) is character
  if ("sq001" %in% names(cleaned_data)) {
    cleaned_data <- cleaned_data %>%
      dplyr::mutate(sq001 = as.character(sq001))
  }

  return(cleaned_data)
}

#' Validate essential NE25 fields
#'
#' @param data Cleaned data frame
#' @param config Configuration list
#' @return Validated data frame with flags
validate_ne25_essential_fields <- function(data, config) {

  # Essential fields for NE25 processing
  # Note: pid is added programmatically during extraction
  # Note: child_dob doesn't exist - age_in_days is the actual field
  essential_fields <- c(
    "record_id", "age_in_days",
    "sq001", "fq001", "eqstate",
    "eq001", "eq002", "eq003"
  )

  # Check for missing essential fields
  missing_fields <- setdiff(essential_fields, names(data))
  if (length(missing_fields) > 0) {
    warning(paste("Missing essential fields:", paste(missing_fields, collapse = ", ")))
  }

  # Add validation flags
  validated_data <- data %>%
    dplyr::mutate(
      # Essential field completeness
      essential_fields_complete = rowSums(is.na(dplyr::select(., any_of(essential_fields)))) == 0,

      # Record quality indicators
      has_pid = !is.na(pid) & pid != "",
      has_age_in_days = !is.na(age_in_days),
      has_zip_code = !is.na(sq001) & sq001 != "",

      # Validation timestamp
      data_validated_at = Sys.time()
    )

  return(validated_data)
}

#' Get NE25 items from codebook (placeholder)
#'
#' @param config Configuration list
#' @return Vector of NE25 item names
get_ne25_items_from_codebook <- function(config) {
  # This would typically read from a codebook file
  # For now, return common NE25 survey items

  ne25_prefixes <- c("eq", "sq", "cq", "fq", "nom", "kmt")

  # Return placeholder - in production this would read from actual codebook
  return(paste0(rep(ne25_prefixes, each = 50), sprintf("%03d", 1:50)))
}
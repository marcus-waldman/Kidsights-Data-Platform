#' NE25 Main Pipeline Orchestration Script
#'
#' Complete end-to-end pipeline for extracting, processing, and storing
#' NE25 data from REDCap to DuckDB on OneDrive

# Load required libraries
library(dplyr)
library(yaml)

# Source all required functions
source("R/extract/ne25.R")
source("R/harmonize/ne25_eligibility.R")
source("R/harmonize/ne25_transformer.R")
source("R/duckdb/connection.R")

#' Load API credentials from CSV file and set as environment variables
#'
#' @param csv_path Path to CSV file with API credentials
load_api_credentials <- function(csv_path) {

  if (!file.exists(csv_path)) {
    stop(paste("API credentials file not found:", csv_path))
  }

  # Read the CSV file
  api_data <- readr::read_csv(csv_path, show_col_types = FALSE)

  # Validate required columns
  required_cols <- c("project", "pid", "api_code")
  missing_cols <- setdiff(required_cols, names(api_data))
  if (length(missing_cols) > 0) {
    stop(paste("Missing required columns in API file:", paste(missing_cols, collapse = ", ")))
  }

  # Set environment variables for each project
  for (i in 1:nrow(api_data)) {
    pid <- api_data$pid[i]
    api_token <- api_data$api_code[i]
    env_var_name <- paste0("KIDSIGHTS_API_TOKEN_", pid)

    # Set the environment variable properly
    do.call(Sys.setenv, setNames(list(api_token), env_var_name))
    message(paste("Set environment variable:", env_var_name))
  }

  message(paste("Loaded", nrow(api_data), "API credentials"))
}

#' Execute complete NE25 pipeline
#'
#' @param config_path Path to configuration file
#' @param pipeline_type Type of pipeline run ('full', 'incremental', 'test')
#' @param overwrite_existing Logical, whether to overwrite existing data
#' @return List with execution results and metrics
run_ne25_pipeline <- function(config_path = "config/sources/ne25.yaml",
                              pipeline_type = "full",
                              overwrite_existing = FALSE) {

  # Generate execution ID
  execution_id <- paste0("ne25_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  start_time <- Sys.time()

  message("=== Starting NE25 Pipeline ===")
  message(paste("Execution ID:", execution_id))
  message(paste("Pipeline Type:", pipeline_type))
  message(paste("Start Time:", start_time))

  # Initialize results
  results <- list(
    execution_id = execution_id,
    success = FALSE,
    metrics = list(),
    errors = list()
  )

  # Load configuration
  tryCatch({
    config <- yaml::read_yaml(config_path)
    message("Configuration loaded successfully")
  }, error = function(e) {
    stop(paste("Failed to load configuration:", e$message))
  })

  # Connect to database
  con <- NULL
  tryCatch({
    con <- connect_kidsights_db(config$output$database_path)
    init_ne25_schema(con)
    message("Database connection established")
  }, error = function(e) {
    stop(paste("Failed to connect to database:", e$message))
  })

  tryCatch({

    # STEP 1: LOAD API CREDENTIALS AND SET ENVIRONMENT VARIABLES
    message("\n--- Step 1: Loading API Credentials ---")
    load_api_credentials(config$redcap$api_credentials_file)

    # STEP 2: EXTRACT DATA FROM REDCAP
    message("\n--- Step 2: Extracting REDCap Data ---")
    extraction_start <- Sys.time()

    projects_data <- list()
    all_dictionaries <- list()
    extraction_errors <- list()

    for (project_info in config$redcap$projects) {
      project_name <- project_info$name
      message(paste("Extracting from project:", project_name))

      tryCatch({
        # Get API token from environment variable
        api_token <- Sys.getenv(project_info$token_env)
        if (api_token == "") {
          stop(paste("API token not found in environment variable:", project_info$token_env))
        }

        # Extract using REDCapR with individual project tokens
        project_data <- extract_redcap_project_data(
          url = config$redcap$url,
          token = api_token,
          forms = NULL,  # Extract all forms
          config = config
        )

        # Extract data dictionary
        project_dict <- extract_redcap_dictionary(
          url = config$redcap$url,
          token = api_token
        )

        # Add metadata
        project_data <- project_data %>%
          mutate(
            retrieved_date = Sys.time(),
            source_project = project_name,
            extraction_id = execution_id
          )

        projects_data[[project_name]] <- project_data
        all_dictionaries[[project_name]] <- project_dict

        message(paste("  - Extracted", nrow(project_data), "records"))

      }, error = function(e) {
        error_msg <- paste("Failed to extract from", project_name, ":", e$message)
        message(paste("  - ERROR:", error_msg))
        extraction_errors[[project_name]] <- error_msg
      })

      # Rate limiting
      Sys.sleep(1)
    }

    # Combine all project data
    if (length(projects_data) > 0) {
      combined_data <- bind_rows(projects_data)
      combined_dictionary <- combine_data_dictionaries(all_dictionaries)
    } else {
      stop("No data was successfully extracted from any project")
    }

    extraction_time <- as.numeric(Sys.time() - extraction_start)
    message(paste("Extraction completed in", round(extraction_time, 2), "seconds"))
    message(paste("Total records extracted:", nrow(combined_data)))

    # STEP 2: CLEAN AND VALIDATE DATA
    message("\n--- Step 2: Data Cleaning and Validation ---")
    processing_start <- Sys.time()

    # Apply initial cleaning
    cleaned_data <- clean_ne25_initial(combined_data, config)
    validated_data <- validate_ne25_essential_fields(cleaned_data, config)

    message(paste("Data cleaning completed:", nrow(validated_data), "records"))

    # STEP 3: ELIGIBILITY VALIDATION
    message("\n--- Step 3: Eligibility Validation ---")

    eligibility_results <- check_ne25_eligibility(validated_data, combined_dictionary, config)
    data_with_eligibility <- apply_ne25_eligibility(validated_data, eligibility_results)

    # Count eligibility results
    eligibility_counts <- data_with_eligibility %>%
      summarise(
        total = n(),
        eligible = sum(eligible, na.rm = TRUE),
        authentic = sum(authentic, na.rm = TRUE),
        included = sum(include, na.rm = TRUE)
      )

    message(paste("Eligibility validation completed:"))
    message(paste("  - Total participants:", eligibility_counts$total))
    message(paste("  - Eligible:", eligibility_counts$eligible))
    message(paste("  - Authentic:", eligibility_counts$authentic))
    message(paste("  - Included:", eligibility_counts$included))

    # STEP 4: DATA TRANSFORMATION
    message("\n--- Step 4: Data Transformation ---")

    transformed_data <- transform_ne25_data(
      data = data_with_eligibility,
      data_dictionary = combined_dictionary,
      config = config
    )

    processing_time <- as.numeric(Sys.time() - processing_start)
    message(paste("Processing completed in", round(processing_time, 2), "seconds"))

    # STEP 5: LOAD TO DUCKDB
    message("\n--- Step 5: Loading to DuckDB ---")
    loading_start <- Sys.time()

    # Insert raw data
    raw_rows <- upsert_ne25_data(con, validated_data, "ne25_raw",
                                 c("record_id", "pid", "retrieved_date"))

    # Insert eligibility results
    eligibility_rows <- upsert_ne25_data(con, eligibility_results$summary, "ne25_eligibility",
                                         c("record_id", "pid", "retrieved_date"))

    # Insert transformed data
    harmonized_rows <- upsert_ne25_data(con, transformed_data, "ne25_harmonized",
                                        c("record_id", "pid", "retrieved_date"))

    # Insert data dictionary
    dict_df <- convert_dictionary_to_dataframe(combined_dictionary)
    dict_rows <- insert_ne25_data(con, dict_df, "ne25_data_dictionary", overwrite = TRUE)

    loading_time <- as.numeric(Sys.time() - loading_start)
    message(paste("Database loading completed in", round(loading_time, 2), "seconds"))

    # STEP 6: GENERATE SUMMARY
    total_time <- as.numeric(Sys.time() - start_time)
    message("\n--- Pipeline Summary ---")

    summary_stats <- get_ne25_summary(con)
    message(paste("Database records:"))
    message(paste("  - Raw data:", summary_stats$ne25_raw))
    message(paste("  - Eligibility results:", summary_stats$ne25_eligibility))
    message(paste("  - Harmonized data:", summary_stats$ne25_harmonized))

    # Log execution to database
    metrics <- list(
      projects_attempted = names(projects_data),
      projects_successful = names(projects_data),
      total_records_extracted = nrow(combined_data),
      extraction_errors = paste(unlist(extraction_errors), collapse = "; "),
      records_processed = nrow(transformed_data),
      records_eligible = eligibility_counts$eligible,
      records_authentic = eligibility_counts$authentic,
      records_included = eligibility_counts$included,
      extraction_duration = extraction_time,
      processing_duration = processing_time,
      total_duration = total_time
    )

    log_pipeline_execution(con, execution_id, pipeline_type, metrics, "success")

    message(paste("Total pipeline duration:", round(total_time, 2), "seconds"))
    message("=== Pipeline Completed Successfully ===")

    results$success <- TRUE
    results$metrics <- metrics
    results$summary_stats <- summary_stats

  }, error = function(e) {
    error_message <- paste("Pipeline failed:", e$message)
    message(paste("ERROR:", error_message))

    # Log failure to database if connection exists
    if (!is.null(con) && DBI::dbIsValid(con)) {
      log_pipeline_execution(con, execution_id, pipeline_type,
                            list(extraction_errors = error_message),
                            "failed", error_message)
    }

    results$success <- FALSE
    results$errors <- list(main_error = error_message)

  }, finally = {
    # Always disconnect from database
    if (!is.null(con)) {
      disconnect_kidsights_db(con)
    }
  })

  return(results)
}

#' Helper function to convert data dictionary to data frame
#'
#' @param dictionary List-based data dictionary
#' @return Data frame suitable for database insertion
convert_dictionary_to_dataframe <- function(dictionary) {

  if (length(dictionary) == 0) {
    return(data.frame())
  }

  dict_df <- data.frame()

  for (field_name in names(dictionary)) {
    field_info <- dictionary[[field_name]]

    row <- data.frame(
      field_name = field_name,
      form_name = field_info$form_name %||% "",
      section_header = field_info$section_header %||% "",
      field_type = field_info$field_type %||% "",
      field_label = field_info$field_label %||% "",
      select_choices_or_calculations = field_info$select_choices_or_calculations %||% "",
      field_note = field_info$field_note %||% "",
      text_validation_type_or_show_slider_number = field_info$text_validation_type_or_show_slider_number %||% "",
      text_validation_min = field_info$text_validation_min %||% "",
      text_validation_max = field_info$text_validation_max %||% "",
      identifier = field_info$identifier %||% "",
      branching_logic = field_info$branching_logic %||% "",
      required_field = field_info$required_field %||% "",
      custom_alignment = field_info$custom_alignment %||% "",
      question_number = field_info$question_number %||% "",
      matrix_group_name = field_info$matrix_group_name %||% "",
      matrix_ranking = field_info$matrix_ranking %||% "",
      field_annotation = field_info$field_annotation %||% "",
      source_project = field_info$source_project %||% "",
      stringsAsFactors = FALSE
    )

    dict_df <- rbind(dict_df, row)
  }

  return(dict_df)
}

# Quick execution function for interactive use
run_ne25_quick <- function() {
  message("Running NE25 pipeline with default settings...")
  result <- run_ne25_pipeline()

  if (result$success) {
    message("\n✅ Pipeline completed successfully!")
    message("Database location: C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB/kidsights.duckdb")
  } else {
    message("\n❌ Pipeline failed!")
    message("Errors:", paste(unlist(result$errors), collapse = "; "))
  }

  return(result)
}
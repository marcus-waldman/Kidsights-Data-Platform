#' NE25 Pipeline Orchestration
#'
#' Main pipeline function that coordinates the complete NE25 data extraction,
#' processing, and loading workflow.

# Load required libraries
library(dplyr)
library(yaml)
library(REDCapR)

# Source required functions
source("R/extract/ne25.R")
source("R/harmonize/ne25_eligibility.R")
source("R/duckdb/connection.R")
source("R/transform/ne25_transforms.R")
source("R/transform/ne25_metadata.R")
source("R/documentation/generate_data_dictionary.R")

#' Execute the complete NE25 pipeline
#'
#' @param config_path Path to NE25 configuration file
#' @param pipeline_type Type of pipeline run ("full", "incremental", "test")
#' @param overwrite_existing Logical, whether to overwrite existing data
#' @return List with execution results and metrics
run_ne25_pipeline <- function(config_path = "config/sources/ne25.yaml",
                              pipeline_type = "full",
                              overwrite_existing = FALSE) {

  # Generate execution ID
  execution_id <- paste0("ne25_", format(Sys.time(), "%Y%m%d_%H%M%S"))

  message("=== Starting NE25 Pipeline ===")
  message(paste("Execution ID:", execution_id))
  message(paste("Pipeline Type:", pipeline_type))
  message(paste("Start Time:", Sys.time()))

  # Initialize metrics
  metrics <- list(
    execution_id = execution_id,
    pipeline_type = pipeline_type,
    start_time = Sys.time(),
    projects_attempted = character(),
    projects_successful = character(),
    total_records_extracted = 0,
    extraction_errors = list(),
    records_processed = 0,
    records_eligible = 0,
    records_authentic = 0,
    records_included = 0,
    records_transformed = 0,
    extraction_duration = 0,
    processing_duration = 0,
    transformation_duration = 0,
    metadata_generation_duration = 0,
    total_duration = 0
  )

  # Load configuration
  config <- tryCatch({
    yaml::read_yaml(config_path)
  }, error = function(e) {
    stop(paste("Failed to load configuration:", e$message))
  })

  message("Configuration loaded successfully")

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
      metrics$projects_attempted <- c(metrics$projects_attempted, project_name)

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

        # Add metadata and pid (following dashboard pattern)
        project_data <- project_data %>%
          mutate(
            retrieved_date = Sys.time(),
            source_project = project_name,
            extraction_id = execution_id,
            pid = project_info$pid  # Add project ID from config (like dashboard does)
          )

        projects_data[[project_name]] <- project_data
        all_dictionaries[[project_name]] <- project_dict

        message(paste("  - Extracted", nrow(project_data), "records"))
        metrics$projects_successful <- c(metrics$projects_successful, project_name)
        metrics$total_records_extracted <- metrics$total_records_extracted + nrow(project_data)

      }, error = function(e) {
        error_msg <- paste("Failed to extract from", project_name, ":", e$message)
        message(paste("  - ERROR:", error_msg))
        extraction_errors[[project_name]] <- error_msg
        metrics$extraction_errors[[project_name]] <- error_msg
      })

      # Rate limiting
      Sys.sleep(1)
    }

    # Combine all project data using flexible_bind_rows (like dashboard)
    if (length(projects_data) > 0) {
      # Use dashboard's flexible_bind_rows function
      combined_data <- flexible_bind_rows(projects_data)
      # Use dictionary from first project (like dashboard)
      combined_dictionary <- all_dictionaries[[1]]
    } else {
      stop("No data was successfully extracted from any project")
    }

    extraction_time <- as.numeric(Sys.time() - extraction_start)
    metrics$extraction_duration <- extraction_time
    message(paste("Extraction completed in", round(extraction_time, 2), "seconds"))
    message(paste("Total records extracted:", nrow(combined_data)))

    # STEP 3: MINIMAL DATA PROCESSING (like dashboard)
    message("\n--- Step 3: Data Processing ---")
    processing_start <- Sys.time()

    # Use the cleaned data from extraction (already has sq001 as character)
    validated_data <- combined_data

    metrics$records_processed <- nrow(validated_data)
    message(paste("Data processing completed:", nrow(validated_data), "records"))

    # STEP 4: ELIGIBILITY VALIDATION
    message("\n--- Step 4: Eligibility Validation ---")

    # Check eligibility for all records
    eligibility_checks <- check_ne25_eligibility(validated_data, combined_dictionary, config)

    # Apply eligibility flags to the dataset
    eligibility_results <- apply_ne25_eligibility(validated_data, eligibility_checks)

    # Count eligibility metrics
    metrics$records_eligible <- sum(eligibility_results$eligible, na.rm = TRUE)
    metrics$records_authentic <- sum(eligibility_results$authentic, na.rm = TRUE)
    metrics$records_included <- sum(eligibility_results$include, na.rm = TRUE)

    message(paste("Eligibility validation completed:"))
    message(paste("  - Eligible participants:", metrics$records_eligible))
    message(paste("  - Authentic participants:", metrics$records_authentic))
    message(paste("  - Included participants:", metrics$records_included))

    processing_time <- as.numeric(Sys.time() - processing_start)
    metrics$processing_duration <- processing_time

    # STEP 5: STORE RAW DATA IN DUCKDB
    message("\n--- Step 5: Storing Raw Data in DuckDB ---")

    # Insert raw data (use insert_ne25_data to create tables)
    message("Storing raw data...")
    insert_ne25_data(con, validated_data, "ne25_raw", overwrite = overwrite_existing)

    # Insert eligibility results
    message("Storing eligibility results...")
    insert_ne25_data(con, eligibility_results, "ne25_eligibility", overwrite = overwrite_existing)

    # STEP 6: DATA TRANSFORMATION (Dashboard-style)
    message("\n--- Step 6: Data Transformation ---")
    transformation_start <- Sys.time()

    # Apply dashboard-style transformations using recode_it()
    message("Applying dashboard transformations...")
    transformed_data <- recode_it(
      dat = eligibility_results,
      dict = combined_dictionary,
      my_API = NULL,
      what = "all"  # Apply all transformation categories
    )

    message(paste("Transformation completed:", nrow(transformed_data), "records"))
    message(paste("Variables after transformation:", ncol(transformed_data)))

    # Store transformed data
    message("Storing transformed data...")
    insert_transformed_data(
      con = con,
      data = transformed_data,
      transformation_version = "1.0.0",
      overwrite = overwrite_existing
    )

    transformation_time <- as.numeric(Sys.time() - transformation_start)
    metrics$transformation_duration <- transformation_time
    metrics$records_transformed <- nrow(transformed_data)

    message(paste("Data transformation completed in", round(transformation_time, 2), "seconds"))

    # STEP 7: METADATA GENERATION
    message("\n--- Step 7: Generating Variable Metadata ---")
    metadata_start <- Sys.time()

    # Generate comprehensive variable metadata
    message("Creating variable metadata...")
    variable_metadata <- create_variable_metadata(
      dat = transformed_data,
      dict = combined_dictionary,
      my_API = NULL,
      what = "all"
    )

    # Convert metadata to dataframe for database storage
    message("Converting metadata to database format...")
    metadata_df <- metadata_to_dataframe(variable_metadata)

    # Store metadata in database
    message("Storing variable metadata...")
    insert_metadata(con, metadata_df, overwrite = TRUE)

    # Create summary table for reporting
    message("Creating metadata summary...")
    metadata_summary <- create_variable_summary_table(variable_metadata)

    metadata_time <- as.numeric(Sys.time() - metadata_start)
    metrics$metadata_generation_duration <- metadata_time

    message(paste("Metadata generation completed in", round(metadata_time, 2), "seconds"))
    message(paste("Generated metadata for", nrow(metadata_df), "variables"))

    # STEP 8: DATA DICTIONARY GENERATION
    message("\n--- Step 8: Generating Data Dictionary ---")

    # Generate data dictionary from metadata
    dict_path <- generate_pipeline_data_dictionary(con = con, format = "full")

    if (!is.null(dict_path)) {
      message(paste("Data dictionary generated:", dict_path))
    } else {
      message("Data dictionary generation skipped or failed")
    }

    # Calculate final metrics
    metrics$end_time <- Sys.time()
    metrics$total_duration <- as.numeric(metrics$end_time - metrics$start_time)

    # Log pipeline execution
    log_pipeline_execution(
      con = con,
      execution_id = execution_id,
      pipeline_type = pipeline_type,
      metrics = metrics,
      status = "success"
    )

    message(paste("Pipeline completed successfully in", round(metrics$total_duration, 2), "seconds"))

    # Return success result with transformed data summaries
    return(list(
      success = TRUE,
      execution_id = execution_id,
      metrics = metrics,
      raw_data_summary = get_ne25_summary(con),
      transformed_data_summary = get_transformed_summary(con),
      metadata_summary = get_metadata_summary(con),
      data_preview = head(transformed_data, 10),
      variable_summary = head(metadata_summary, 20)
    ))

  }, error = function(e) {
    # Log error
    error_message <- e$message
    message(paste("ERROR: Pipeline failed:", error_message))

    # Try to log the failure
    tryCatch({
      log_pipeline_execution(
        con = con,
        execution_id = execution_id,
        pipeline_type = pipeline_type,
        metrics = metrics,
        status = "failed",
        error_message = error_message
      )
    }, error = function(log_error) {
      message(paste("Error inserting data:", log_error$message))
    })

    # Return failure result
    return(list(
      success = FALSE,
      execution_id = execution_id,
      errors = list(main_error = error_message),
      metrics = metrics
    ))

  }, finally = {
    # Always disconnect from database
    if (!is.null(con)) {
      disconnect_kidsights_db(con)
    }
  })
}

#' Load API credentials from CSV and set environment variables
#'
#' @param csv_path Path to CSV file with API credentials
load_api_credentials <- function(csv_path) {

  if (!file.exists(csv_path)) {
    stop(paste("API credentials file not found:", csv_path))
  }

  # Read the CSV file
  credentials <- read.csv(csv_path, stringsAsFactors = FALSE)

  # Check required columns
  required_cols <- c("project", "pid", "api_code")
  missing_cols <- setdiff(required_cols, names(credentials))
  if (length(missing_cols) > 0) {
    stop(paste("Missing required columns in credentials file:", paste(missing_cols, collapse = ", ")))
  }

  # Set environment variables for each project
  for (i in 1:nrow(credentials)) {
    pid <- credentials$pid[i]
    api_token <- credentials$api_code[i]
    env_var_name <- paste0("KIDSIGHTS_API_TOKEN_", pid)

    # Set the environment variable
    do.call(Sys.setenv, setNames(list(api_token), env_var_name))
    message(paste("Set environment variable:", env_var_name))
  }

  message(paste("Loaded", nrow(credentials), "API credentials"))
}
#' NE25 Pipeline Orchestration
#'
#' Main pipeline function that coordinates the complete NE25 data extraction,
#' processing, and loading workflow.

# Dependency Management: Ensure all required packages are available
source("R/utils/dependency_manager.R")
ensure_database_dependencies(auto_install = TRUE, quiet = FALSE)

# Load required libraries (now guaranteed to be available)
library(dplyr)
library(yaml)
library(REDCapR)
library(arrow)

# Source required functions
source("R/extract/ne25.R")
source("R/harmonize/ne25_eligibility.R")
source("R/transform/ne25_transforms.R")
source("R/documentation/generate_data_dictionary.R")
source("R/documentation/generate_interactive_dictionary.R")

#' Convert REDCap dictionary list to data frame
#'
#' @param dict_list Named list from extract_redcap_dictionary()
#' @return Data frame with dictionary fields
convert_dictionary_to_df <- function(dict_list) {
  if (length(dict_list) == 0) return(data.frame())

  # Convert list to data frame
  dict_rows <- list()
  for (field_name in names(dict_list)) {
    field_info <- dict_list[[field_name]]
    dict_rows[[field_name]] <- data.frame(
      field_name = field_info$field_name %||% field_name,
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
      stringsAsFactors = FALSE
    )
  }
  return(do.call(rbind, dict_rows))
}

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
    interactive_dictionary_duration = 0,
    total_duration = 0
  )

  # Load configuration
  config <- tryCatch({
    yaml::read_yaml(config_path)
  }, error = function(e) {
    stop(paste("Failed to load configuration:", e$message))
  })

  message("Configuration loaded successfully")

  # Codebook no longer needed - CID8 (KMT quality analysis) removed
  message("DEBUG: Codebook loading skipped - CID8 KMT quality analysis removed from pipeline")

  # Initialize database using Python
  message("Initializing database schema using Python...")
  init_result <- system2(
    "python",
    args = c(
      "pipelines/python/init_database.py",
      "--config", config_path,
      "--log-level", "INFO"
    ),
    stdout = TRUE,
    stderr = TRUE
  )

  if (attr(init_result, "status") != 0 && !is.null(attr(init_result, "status"))) {
    stop(paste("Database initialization failed:", paste(init_result, collapse = "\n")))
  }
  message("Database schema initialized successfully")

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
        message("DEBUG: Loading API credential: ", project_info$token_env)
        api_token <- Sys.getenv(project_info$token_env)
        if (api_token == "") {
          stop(paste("API token not found in environment variable:", project_info$token_env))
        }
        message("DEBUG: Token loaded successfully (length: ", nchar(api_token), " characters)")

        # Extract using REDCapR with individual project tokens
        message("DEBUG: Extracting project ", project_name, " from URL: ", config$redcap$url)
        project_data <- extract_redcap_project_data(
          url = config$redcap$url,
          token = api_token,
          forms = NULL,  # Extract all forms
          config = config
        )
        message("DEBUG: Retrieved ", nrow(project_data), " records with ", ncol(project_data), " fields")

        # Extract data dictionary
        project_dict <- extract_redcap_dictionary(
          url = config$redcap$url,
          token = api_token
        )
        message("DEBUG: Dictionary contains ", nrow(project_dict), " field definitions")

        # Add metadata and pid (following dashboard pattern)
        project_data <- project_data %>%
          dplyr::mutate(
            retrieved_date = Sys.time(),
            source_project = project_name,
            extraction_id = execution_id,
            pid = project_info$pid  # Add project ID from config (like dashboard does)
          )

        projects_data[[project_name]] <- project_data
        all_dictionaries[[project_name]] <- project_dict

        message(paste("  - Extracted", nrow(project_data), "records"))
        message(paste("  - Extracted", length(project_dict), "dictionary fields"))
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
    message("DEBUG: Combined data has ", nrow(combined_data), " rows, ", ncol(combined_data), " columns")

    # Use the cleaned data from extraction (already has sq001 as character)
    validated_data <- combined_data
    message("DEBUG: After validation: ", nrow(validated_data), " records remain")

    # DEBUG: Check what columns we have for age calculation
    cat("DEBUG - Available columns in combined_data:\n")
    cat("Total columns:", ncol(combined_data), "\n")
    date_cols <- names(combined_data)[grepl("date|birth|dob|age|year|month|day", names(combined_data), ignore.case = TRUE)]
    cat("Date/age related columns:", paste(date_cols, collapse=", "), "\n")

    metrics$records_processed <- nrow(validated_data)
    message(paste("Data processing completed:", nrow(validated_data), "records"))

    # Cache validated data for debugging
    message("DEBUG: Caching validated data...")
    cache_dir <- "temp/pipeline_cache"
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
    saveRDS(validated_data, file.path(cache_dir, "step2_validated_data.rds"))
    saveRDS(combined_dictionary, file.path(cache_dir, "step2_combined_dictionary.rds"))
    message("DEBUG: Cached validated data (", nrow(validated_data), " records)")

    # STEP 4: ELIGIBILITY VALIDATION
    message("\n--- Step 4: Eligibility Validation ---")
    message("DEBUG: Starting eligibility validation with 8 criteria (CID8 KMT quality removed)")
    message("DEBUG: Validated data dimensions: ", nrow(validated_data), " x ", ncol(validated_data))
    message("DEBUG: Dictionary entries: ", length(combined_dictionary))

    # Check eligibility for all records (simplified - no codebook needed)
    eligibility_checks <- check_ne25_eligibility(validated_data, combined_dictionary)

    message("DEBUG: Eligibility checks completed")
    message("DEBUG: Eligibility summary records: ", nrow(eligibility_checks$summary))

    # Cache eligibility checks for debugging
    message("DEBUG: Caching eligibility checks...")
    saveRDS(eligibility_checks, file.path(cache_dir, "step3_eligibility_checks.rds"))
    message("DEBUG: Cached eligibility checks with ", nrow(eligibility_checks$summary), " records")

    # Apply eligibility flags to the dataset
    message("DEBUG: Applying eligibility flags to dataset...")
    eligibility_results <- apply_ne25_eligibility(validated_data, eligibility_checks)

    # Cache eligibility results for debugging
    message("DEBUG: Caching eligibility results...")
    saveRDS(eligibility_results, file.path(cache_dir, "step4_eligibility_results.rds"))
    message("DEBUG: Cached eligibility results (", nrow(eligibility_results), " records)")

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

    # STEP 5: STORE RAW DATA IN DUCKDB USING PYTHON
    message("\n--- Step 5: Storing Raw Data in DuckDB ---")
    message("DEBUG: Final eligibility results dimensions: ", nrow(eligibility_results), " x ", ncol(eligibility_results))
    message("DEBUG: Eligibility summary:")
    message("DEBUG:   - Records eligible: ", metrics$records_eligible)
    message("DEBUG:   - Records authentic: ", metrics$records_authentic)
    message("DEBUG:   - Records included: ", metrics$records_included)

    # Create temporary directory for CSV exports
    temp_dir <- file.path(tempdir(), "ne25_pipeline")
    dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
    message("DEBUG: Temporary directory created: ", temp_dir)

    # Export raw data to Feather and insert using Python
    message("Storing raw data...")
    raw_feather <- file.path(temp_dir, "ne25_raw.feather")
    message("DEBUG: Writing Feather file to: ", raw_feather)
    # Select only metadata columns for raw table (ne25_raw table has 6 columns only)
    required_cols <- c("record_id", "pid", "redcap_event_name", "retrieved_date", "source_project", "extraction_id")
    available_cols <- names(validated_data)
    missing_cols <- setdiff(required_cols, available_cols)

    if (length(missing_cols) > 0) {
      warning("Missing required metadata columns: ", paste(missing_cols, collapse = ", "))
      message("Available columns: ", paste(head(available_cols, 10), collapse = ", "), "...")
    }

    # Only select columns that exist, add missing ones with default values
    existing_required_cols <- intersect(required_cols, available_cols)

    raw_metadata <- validated_data %>%
      dplyr::select(dplyr::all_of(existing_required_cols))

    # Add missing required columns with default values
    if (!"redcap_event_name" %in% names(raw_metadata)) {
      raw_metadata$redcap_event_name <- "baseline_arm_1"
      message("DEBUG: Added missing redcap_event_name with default value")
    }
    message("DEBUG: Raw metadata has ", ncol(raw_metadata), " columns: ", paste(names(raw_metadata), collapse=", "))
    arrow::write_feather(raw_metadata, raw_feather)
    message("DEBUG: Feather file size: ", round(file.size(raw_feather) / 1024^2, 2), " MB")

    message("DEBUG: Calling Python insert script...")
    raw_result <- system2(
      "python",
      args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", raw_feather,
        "--table-name", "ne25_raw",
        "--data-type", "raw",
        "--config", config_path
      ),
      stdout = TRUE,
      stderr = TRUE
    )
    message("DEBUG: Python script exit code: ", attr(raw_result, "status") %||% 0)

    if (attr(raw_result, "status") != 0 && !is.null(attr(raw_result, "status"))) {
      warning(paste("Raw data insertion had issues:", paste(raw_result, collapse = "\n")))
    } else {
      message("Raw data stored successfully")
    }

    # Insert eligibility results
    message("Storing eligibility results...")
    elig_feather <- file.path(temp_dir, "ne25_eligibility.feather")
    arrow::write_feather(eligibility_results, elig_feather)

    elig_result <- system2(
      "python",
      args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", elig_feather,
        "--table-name", "ne25_eligibility",
        "--data-type", "eligibility",
        "--config", config_path
      ),
      stdout = TRUE,
      stderr = TRUE
    )

    if (attr(elig_result, "status") != 0 && !is.null(attr(elig_result, "status"))) {
      warning(paste("Eligibility data insertion had issues:", paste(elig_result, collapse = "\n")))
    } else {
      message("Eligibility data stored successfully")
    }

    # DISABLED: Project-specific table storage (redundant with university server)
    # Store project-specific raw data by PID
    # message("Storing project-specific raw data by PID...")
    # for (project_name in names(projects_data)) {
    #   project_data <- projects_data[[project_name]]
    #   if (!is.null(project_data) && nrow(project_data) > 0) {
    #     # Get PID from the data
    #     project_pid <- unique(project_data$pid)[1]
    #     table_name <- paste0("ne25_raw_pid", project_pid)
    #
    #     # Export to Feather and insert using Python
    #     project_feather <- file.path(temp_dir, paste0("ne25_raw_pid", project_pid, ".feather"))
    #     arrow::write_feather(project_data, project_feather)
    #
    #     project_result <- system2(
    #       "python",
    #       args = c(
    #         "pipelines/python/insert_raw_data.py",
    #         "--data-file", project_feather,
    #         "--table-name", table_name,
    #         "--data-type", "raw",
    #         "--pid", as.character(project_pid),
    #         "--config", config_path
    #       ),
    #       stdout = TRUE,
    #       stderr = TRUE
    #     )
    #
    #     if (attr(project_result, "status") != 0 && !is.null(attr(project_result, "status"))) {
    #       warning(paste("Project", project_name, "data insertion had issues:", paste(project_result, collapse = "\n")))
    #     } else {
    #       message(paste("  - Stored", nrow(project_data), "records to", table_name, "for project:", project_name))
    #     }
    #   }
    # }
    message("Skipping project-specific table storage (data available on university server)")

    # Store REDCap data dictionaries with PID reference
    message("Storing REDCap data dictionaries...")
    total_dict_fields <- 0
    for (project_name in names(all_dictionaries)) {
      project_dict_list <- all_dictionaries[[project_name]]
      if (!is.null(project_dict_list) && length(project_dict_list) > 0) {

        # Convert dictionary list to data frame
        project_dict_df <- convert_dictionary_to_df(project_dict_list)

        if (nrow(project_dict_df) > 0) {
          # Add PID reference to dictionary
          project_data <- projects_data[[project_name]]
          if (!is.null(project_data) && nrow(project_data) > 0) {
            project_pid <- unique(project_data$pid)[1]
            project_dict_df$pid <- project_pid

            # Export to Feather and insert using Python
            dict_feather <- file.path(temp_dir, paste0("dictionary_pid", project_pid, ".feather"))
            arrow::write_feather(project_dict_df, dict_feather)

            dict_result <- system2(
              "python",
              args = c(
                "pipelines/python/insert_raw_data.py",
                "--data-file", dict_feather,
                "--table-name", "ne25_data_dictionary",
                "--data-type", "dictionary",
                "--pid", as.character(project_pid),
                "--config", config_path
              ),
              stdout = TRUE,
              stderr = TRUE
            )

            if (attr(dict_result, "status") != 0 && !is.null(attr(dict_result, "status"))) {
              warning(paste("Dictionary insertion for PID", project_pid, "had issues:", paste(dict_result, collapse = "\n")))
            } else {
              total_dict_fields <- total_dict_fields + nrow(project_dict_df)
            }
          }
        }
      }
    }
    message(paste("Stored", total_dict_fields, "total dictionary fields from", length(all_dictionaries), "projects"))

    # STEP 6: DATA TRANSFORMATION (Including Geographic Variables)
    message("\n--- Step 6: Data Transformation ---")
    transformation_start <- Sys.time()

    # Apply all transformations including geographic crosswalks (48 derived variables)
    message("Applying all transformations (eligibility, race, education, geographic, etc.)...")
    transformed_data <- recode_it(dat = eligibility_results, dict = combined_dictionary, what = "all")

    message(paste("Transformation completed:", nrow(transformed_data), "records"))
    message(paste("Variables after transformation:", ncol(transformed_data)))

    # Store transformed data using Python
    message("Storing transformed data...")
    transformed_feather <- file.path(temp_dir, "ne25_transformed.feather")
    arrow::write_feather(transformed_data, transformed_feather)

    transformed_result <- system2(
      "python",
      args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", transformed_feather,
        "--table-name", "ne25_transformed",
        "--data-type", "raw",
        "--config", config_path
      ),
      stdout = TRUE,
      stderr = TRUE
    )

    if (attr(transformed_result, "status") != 0 && !is.null(attr(transformed_result, "status"))) {
      warning(paste("Transformed data insertion had issues:", paste(transformed_result, collapse = "\n")))
    } else {
      message("Transformed data stored successfully")
    }

    transformation_time <- as.numeric(Sys.time() - transformation_start)
    metrics$transformation_duration <- transformation_time
    metrics$records_transformed <- nrow(transformed_data)

    message(paste("Data transformation completed in", round(transformation_time, 2), "seconds"))

    # STEP 7: METADATA GENERATION USING PYTHON
    message("\n--- Step 7: Generating Variable Metadata ---")
    metadata_start <- Sys.time()

    # Generate metadata using Python script
    message("Creating variable metadata using Python...")
    metadata_result <- system2(
      "python",
      args = c(
        "pipelines/python/generate_metadata.py",
        "--source-table", "ne25_transformed",
        "--metadata-table", "ne25_metadata",
        "--config", config_path,
        "--derived-config", "config/derived_variables.yaml",
        "--log-level", "INFO"
      ),
      stdout = TRUE,
      stderr = TRUE
    )

    if (attr(metadata_result, "status") != 0 && !is.null(attr(metadata_result, "status"))) {
      warning(paste("Metadata generation had issues:", paste(metadata_result, collapse = "\n")))
      message("Metadata generation completed with warnings")
    } else {
      message("Metadata generation completed successfully")
    }

    metadata_time <- as.numeric(Sys.time() - metadata_start)
    metrics$metadata_generation_duration <- metadata_time

    message(paste("Metadata generation completed in", round(metadata_time, 2), "seconds"))

    # STEP 8: DATA DICTIONARY GENERATION
    message("\n--- Step 8: Generating Data Dictionary ---")

    # Generate data dictionary without database connection
    dict_path <- generate_pipeline_data_dictionary(format = "full")

    if (!is.null(dict_path)) {
      message(paste("Data dictionary generated:", dict_path))
    } else {
      message("Data dictionary generation skipped or failed")
    }

    # STEP 9: INTERACTIVE DICTIONARY GENERATION
    message("\n--- Step 9: Generating Interactive Dictionary ---")
    interactive_dict_start <- Sys.time()

    # Generate interactive Quarto-based data dictionary
    interactive_dict_result <- generate_interactive_dictionary(
      output_dir = "docs/data_dictionary/ne25",
      verbose = TRUE,
      timeout_seconds = 120
    )

    interactive_dict_time <- as.numeric(Sys.time() - interactive_dict_start)
    metrics$interactive_dictionary_duration <- interactive_dict_time

    if (interactive_dict_result$success) {
      message(paste("✅ Interactive dictionary generated successfully:", interactive_dict_result$main_file))
      message(paste("📄 Files generated:", interactive_dict_result$file_count))
      message(paste("⏱️  Render time:", round(interactive_dict_result$duration, 1), "seconds"))
      if (!is.null(interactive_dict_result$json_export)) {
        message(paste("📋 JSON export:", interactive_dict_result$json_export))
      }
    } else {
      message(paste("❌ Interactive dictionary generation failed:", interactive_dict_result$error))
      if (!is.null(interactive_dict_result$suggestion)) {
        message(paste("💡 Suggestion:", interactive_dict_result$suggestion))
      }
    }

    # Calculate final metrics
    metrics$end_time <- Sys.time()
    metrics$total_duration <- as.numeric(metrics$end_time - metrics$start_time)

    # Clean up temporary files
    unlink(temp_dir, recursive = TRUE)

    # Log pipeline execution (simple file logging since we don't have con)
    message(paste("Pipeline execution ID:", execution_id, "completed successfully"))

    message(paste("Pipeline completed successfully in", round(metrics$total_duration, 2), "seconds"))

    # Return success result with local data summaries
    return(list(
      success = TRUE,
      execution_id = execution_id,
      metrics = metrics,
      interactive_dictionary_result = interactive_dict_result,
      data_preview = head(transformed_data, 10),
      total_records = nrow(transformed_data),
      total_variables = ncol(transformed_data)
    ))

  }, error = function(e) {
    # Log error
    error_message <- e$message
    message(paste("ERROR: Pipeline failed:", error_message))

    # Log the failure (simple file logging)
    message(paste("Pipeline execution ID:", execution_id, "failed:", error_message))

    # Return failure result
    return(list(
      success = FALSE,
      execution_id = execution_id,
      errors = list(main_error = error_message),
      metrics = metrics
    ))

  }, finally = {
    # Clean up any remaining temporary files
    if (exists("temp_dir") && dir.exists(temp_dir)) {
      unlink(temp_dir, recursive = TRUE)
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
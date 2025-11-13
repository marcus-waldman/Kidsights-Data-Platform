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
source("R/utils/environment_config.R")

#' Convert REDCap dictionary list to data frame
#'
#' @param dict_list Named list from extract_redcap_dictionary()
#' @return Data frame with dictionary fields
convert_dictionary_to_df <- function(dict_list) {
  if (length(dict_list) == 0) return(data.frame())

  # Helper function to get value or default
  get_or_default <- function(x, default = "") {
    if (is.null(x)) return(default)
    if (length(x) == 0) return(default)
    return(x)
  }

  # Convert list to data frame
  dict_rows <- list()
  for (field_name in names(dict_list)) {
    field_info <- dict_list[[field_name]]
    dict_rows[[field_name]] <- data.frame(
      field_name = get_or_default(field_info$field_name, field_name),
      form_name = get_or_default(field_info$form_name),
      section_header = get_or_default(field_info$section_header),
      field_type = get_or_default(field_info$field_type),
      field_label = get_or_default(field_info$field_label),
      select_choices_or_calculations = get_or_default(field_info$select_choices_or_calculations),
      field_note = get_or_default(field_info$field_note),
      text_validation_type_or_show_slider_number = get_or_default(field_info$text_validation_type_or_show_slider_number),
      text_validation_min = get_or_default(field_info$text_validation_min),
      text_validation_max = get_or_default(field_info$text_validation_max),
      identifier = get_or_default(field_info$identifier),
      branching_logic = get_or_default(field_info$branching_logic),
      required_field = get_or_default(field_info$required_field),
      custom_alignment = get_or_default(field_info$custom_alignment),
      question_number = get_or_default(field_info$question_number),
      matrix_group_name = get_or_default(field_info$matrix_group_name),
      matrix_ranking = get_or_default(field_info$matrix_ranking),
      field_annotation = get_or_default(field_info$field_annotation),
      stringsAsFactors = FALSE
    )
  }
  return(do.call(rbind, dict_rows))
}

#' Execute the complete NE25 pipeline
#'
#' Pipeline Steps:
#'   1. Load API credentials
#'   2. Extract REDCap data
#'   3. Minimal data processing
#'   4. Store raw data in DuckDB
#'   5. Data transformation (geographic variables)
#'   6. Eligibility validation
#'   6.5. Authenticity screening & weighting (NEW)
#'   7. Store transformed data
#'   8. Generate variable metadata
#'   9. Generate data dictionary
#'
#' @param config_path Path to NE25 configuration file
#' @param pipeline_type Type of pipeline run ("full", "incremental", "test")
#' @param overwrite_existing Logical, whether to overwrite existing data
#'
#' @section Options:
#' - `ne25.rebuild_loocv` (default: FALSE): If TRUE, re-runs LOOCV for authenticity
#'   screening (~7 min). If FALSE, uses cached LOOCV distribution (~30 sec).
#'   Set via `options(ne25.rebuild_loocv = TRUE)` before running pipeline.
#'
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
    calibration_table_duration = 0,
    total_duration = 0
  )

  # Load configuration
  config <- tryCatch({
    yaml::read_yaml(config_path)
  }, error = function(e) {
    stop(paste("Failed to load configuration:", e$message))
  })

  message("Configuration loaded successfully")

  # Override REDCap API credentials path from .env if specified
  env_file <- ".env"
  if (file.exists(env_file)) {
    env_lines <- readLines(env_file, warn = FALSE)
    env_lines <- env_lines[!grepl("^\\s*#", env_lines)]
    env_lines <- env_lines[nzchar(trimws(env_lines))]
    redcap_line <- env_lines[grepl("^REDCAP_API_CREDENTIALS_PATH=", env_lines)]
    if (length(redcap_line) > 0) {
      redcap_path <- sub("^REDCAP_API_CREDENTIALS_PATH=", "", redcap_line[1])
      redcap_path <- trimws(gsub("^['\"]|['\"]$", "", redcap_path))
      if (file.exists(redcap_path)) {
        config$redcap$api_credentials_file <- redcap_path
        message("Using REDCap credentials from .env: ", redcap_path)
      }
    }
  }

  # Codebook no longer needed - CID8 (KMT quality analysis) removed
  message("DEBUG: Codebook loading skipped - CID8 KMT quality analysis removed from pipeline")

  # Initialize database using Python
  message("Initializing database schema using Python...")
  python_path <- get_python_path()
  init_result <- system2(
    python_path,
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

    # STEP 4: STORE RAW DATA IN DUCKDB USING PYTHON
    message("\n--- Step 4: Storing Raw Data in DuckDB ---")
    message("DEBUG: Validated data dimensions: ", nrow(validated_data), " x ", ncol(validated_data))

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
      python_path,
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
              python_path,
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

    # STEP 5: DATA TRANSFORMATION (Including Geographic Variables)
    message("\n--- Step 5: Data Transformation ---")
    transformation_start <- Sys.time()

    # Apply all transformations including geographic crosswalks (creates dob_match and other derived variables)
    message("Applying all transformations (race, education, geographic, age, etc.)...")
    transformed_data <- recode_it(dat = validated_data, dict = combined_dictionary, what = "all")

    # CRITICAL: Apply reverse coding for items where higher values = worse performance
    # This affects 5 HRTL self-regulation items and ensures correct IRT calibration
    message("Applying reverse coding to negatively-keyed items...")
    source("R/transform/reverse_code_items.R")
    transformed_data <- reverse_code_items(
      dat = transformed_data,
      codebook_path = "codebook/data/codebook.json",
      lexicon_name = "ne25",
      verbose = TRUE
    )

    message(paste("Transformation completed:", nrow(transformed_data), "records"))
    message(paste("Variables after transformation:", ncol(transformed_data)))

    # Cache transformed data for debugging
    message("DEBUG: Caching transformed data...")
    saveRDS(transformed_data, file.path(cache_dir, "step5_transformed_data.rds"))
    message("DEBUG: Cached transformed data (", nrow(transformed_data), " records)")

    transformation_time <- as.numeric(Sys.time() - transformation_start)
    metrics$transformation_duration <- transformation_time
    message(paste("Data transformation completed in", round(transformation_time, 2), "seconds"))

    # STEP 6: ELIGIBILITY VALIDATION (now runs after transformation, so dob_match exists)
    message("\n--- Step 6: Eligibility Validation ---")
    processing_start <- Sys.time()
    message("DEBUG: Starting eligibility validation with 8 criteria (CID8 KMT quality removed)")
    message("DEBUG: Transformed data dimensions: ", nrow(transformed_data), " x ", ncol(transformed_data))
    message("DEBUG: Dictionary entries: ", length(combined_dictionary))

    # Check eligibility for all records (now includes dob_match from transformation)
    eligibility_checks <- check_ne25_eligibility(transformed_data, combined_dictionary)

    message("DEBUG: Eligibility checks completed")
    message("DEBUG: Eligibility summary records: ", nrow(eligibility_checks$summary))

    # Cache eligibility checks for debugging
    message("DEBUG: Caching eligibility checks...")
    saveRDS(eligibility_checks, file.path(cache_dir, "step6_eligibility_checks.rds"))
    message("DEBUG: Cached eligibility checks with ", nrow(eligibility_checks$summary), " records")

    # Apply eligibility flags to the transformed dataset
    message("DEBUG: Applying eligibility flags to transformed dataset...")
    final_data <- apply_ne25_eligibility(transformed_data, eligibility_checks)

    # Cache final data for debugging
    message("DEBUG: Caching final data...")
    saveRDS(final_data, file.path(cache_dir, "step6_final_data.rds"))
    message("DEBUG: Cached final data (", nrow(final_data), " records)")

    # Count eligibility metrics
    metrics$records_eligible <- sum(final_data$eligible, na.rm = TRUE)
    metrics$records_authentic <- sum(final_data$authentic, na.rm = TRUE)
    metrics$records_included <- sum(final_data$include, na.rm = TRUE)

    message(paste("Eligibility validation completed:"))
    message(paste("  - Eligible participants:", metrics$records_eligible))
    message(paste("  - Authentic participants:", metrics$records_authentic))
    message(paste("  - Included participants:", metrics$records_included))

    processing_time <- as.numeric(Sys.time() - processing_start)
    metrics$processing_duration <- processing_time

    # Store eligibility summary table
    message("Storing eligibility summary...")
    elig_feather <- file.path(temp_dir, "ne25_eligibility.feather")
    arrow::write_feather(eligibility_checks$summary, elig_feather)

    elig_result <- system2(
      python_path,
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
      message("Eligibility summary stored successfully")
    }

    # STEP 6.5: AUTHENTICITY SCREENING & WEIGHTING
    message("\n--- Step 6.5: Authenticity Screening ---")
    authenticity_start <- Sys.time()

    # Source weighting function
    source("scripts/authenticity_screening/08_compute_pipeline_weights.R")

    # Check global option for LOOCV rebuild
    rebuild_loocv <- getOption("ne25.rebuild_loocv", FALSE)
    message(paste("Rebuild LOOCV:", rebuild_loocv))

    # Compute authenticity weights
    message("Computing authenticity weights...")
    final_data <- compute_authenticity_weights(final_data, rebuild_loocv, "results/")

    # Create meets_inclusion column
    message("Creating meets_inclusion column...")
    final_data$meets_inclusion <- (final_data$eligible == TRUE & !is.na(final_data$authenticity_weight))

    # Cache result
    message("DEBUG: Caching authenticity-weighted data...")
    saveRDS(final_data, file.path(cache_dir, "step6.5_authenticity_weights.rds"))
    message("DEBUG: Cached authenticity-weighted data (", nrow(final_data), " records)")

    # Count authenticity metrics
    metrics$records_weighted <- sum(!is.na(final_data$authenticity_weight), na.rm = TRUE)
    metrics$records_meets_inclusion <- sum(final_data$meets_inclusion, na.rm = TRUE)

    message(paste("Authenticity screening completed:"))
    message(paste("  - Participants with weights:", metrics$records_weighted))
    message(paste("  - Participants meeting inclusion:", metrics$records_meets_inclusion))

    authenticity_time <- as.numeric(Sys.time() - authenticity_start)
    metrics$authenticity_duration <- authenticity_time
    message(paste("Authenticity screening completed in", round(authenticity_time, 2), "seconds"))

    # STEP 7: STORE TRANSFORMED DATA WITH ELIGIBILITY FLAGS
    message("\n--- Step 7: Storing Transformed Data ---")
    message("Storing transformed data with eligibility flags...")
    transformed_feather <- file.path(temp_dir, "ne25_transformed.feather")
    arrow::write_feather(final_data, transformed_feather)

    transformed_result <- system2(
      python_path,
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
    metrics$records_transformed <- nrow(final_data)

    # STEP 8: METADATA GENERATION USING PYTHON
    message("\n--- Step 8: Generating Variable Metadata ---")
    metadata_start <- Sys.time()

    # Generate metadata using Python script
    message("Creating variable metadata using Python...")
    metadata_result <- system2(
      python_path,
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

    # STEP 9: DATA DICTIONARY GENERATION
    message("\n--- Step 9: Generating Data Dictionary ---")

    # Generate data dictionary without database connection
    dict_path <- generate_pipeline_data_dictionary(format = "full")

    if (!is.null(dict_path)) {
      message(paste("Data dictionary generated:", dict_path))
    } else {
      message("Data dictionary generation skipped or failed")
    }

    # STEP 10: INTERACTIVE DICTIONARY GENERATION
    message("\n--- Step 10: Generating Interactive Dictionary ---")
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

    # ===========================================================================
    # STEP 11: CREATE NE25 CALIBRATION TABLE
    # ===========================================================================

    message("\n--- Step 11: Creating NE25 Calibration Table ---")
    calibration_start <- Sys.time()

    source("scripts/irt_scoring/create_ne25_calibration_table.R")

    tryCatch({
      create_ne25_calibration_table(
        codebook_path = "codebook/data/codebook.json",
        db_path = "data/duckdb/kidsights_local.duckdb",
        verbose = TRUE
      )
      message("NE25 calibration table created successfully")
    }, error = function(e) {
      warning(paste("Calibration table creation failed:", e$message))
      message("Pipeline will continue, but calibration table is unavailable")
    })

    calibration_time <- as.numeric(Sys.time() - calibration_start)
    metrics$calibration_table_duration <- calibration_time
    message(paste("Calibration table creation completed in",
                  round(calibration_time, 2), "seconds"))

    # Calculate final metrics
    metrics$end_time <- Sys.time()
    metrics$total_duration <- as.numeric(metrics$end_time - metrics$start_time)

    # Clean up temporary files
    unlink(temp_dir, recursive = TRUE)

    # Log pipeline execution (simple file logging since we don't have con)
    message(paste("Pipeline execution ID:", execution_id, "completed successfully"))

    message(paste("Pipeline completed successfully in", round(metrics$total_duration, 2), "seconds"))

    # Show calibration table timing if executed
    if (!is.null(metrics$calibration_table_duration) &&
        metrics$calibration_table_duration > 0) {
      message(paste("  • Calibration table:",
                    round(metrics$calibration_table_duration, 1),
                    "seconds"))
    }

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
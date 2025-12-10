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
source("R/utils/safe_joins.R")

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
#'   5.5. Data validation (detect unexpected data loss)
#'   6. Eligibility validation
#'   6.5. Join manual influential observations (if available)
#'   6.7. Join GSED person-fit scores (if available)
#'   6.8. Create meets_inclusion filter column
#'   6.9. Join calibrated KL divergence weights (if available)
#'   6.10. Mark out-of-state records
#'   7. Store transformed data (with weights if available)
#'   7.5. CREDI developmental scoring (children under 4 years old)
#'   7.6. GSED D-score calculation (all eligible ages)
#'   8. Generate variable metadata
#'   9. Generate data dictionary
#'   10. Generate interactive dictionary
#'
#' @param config_path Path to NE25 configuration file
#' @param pipeline_type Type of pipeline run ("full", "incremental", "test")
#' @param overwrite_existing Logical, whether to overwrite existing data
#'
#' @section Influential Observations:
#' Step 6.5 joins manually-identified influential observations from the
#' `ne25_flagged_observations` database table (if it exists). Influence diagnostics
#' is a MANUAL workflow using Cook's Distance. See: scripts/authenticity_screening/README.md
#'
#' To identify influential observations:
#'   1. Run manual influence diagnostics workflow
#'   2. Save influential observations to database
#'   3. Re-run pipeline to incorporate influential flags
#'
#' @section Calibrated Weights:
#' Step 6.9 optionally joins KL divergence calibrated weights from
#' `data/raking/ne25/ne25_weights/ne25_calibrated_weights_m1.feather` if the file exists.
#' If weights are not available, the pipeline continues normally without them.
#' Weights are joined BEFORE database storage (Step 7) to ensure they are persisted.
#'
#' To generate calibrated weights:
#'   1. Run raking targets pipeline (scripts 25-30b)
#'   2. Run harmonization (script 32)
#'   3. Run weight estimation (script 33)
#'   4. Re-run NE25 pipeline to automatically integrate weights
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
    records_data_quality = 0,
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
    # NOTE: recode_it() already applies reverse coding internally, no need to call it again
    message("Applying all transformations (race, education, geographic, age, etc.)...")
    transformed_data <- recode_it(dat = validated_data, dict = combined_dictionary, what = "all")

    message(paste("Transformation completed:", nrow(transformed_data), "records"))
    message(paste("Variables after transformation:", ncol(transformed_data)))

    # VALIDATION: Check for unexpected data loss during transformation
    message("\n--- Step 5.5: Validating Transformation (Data Quality Check) ---")
    source("R/utils/validate_transformation.R")

    validation_result <- validate_transformation(
      data_before = validated_data,
      data_after = transformed_data,
      max_loss_pct = 10,  # Flag items with >10% data loss
      lexicon_name = "ne25",  # Use NE25 lexicon for missing code identification
      verbose = TRUE,
      stop_on_error = TRUE  # Stop pipeline if critical data loss detected
    )

    # VALIDATION: Check for sentinel missing codes (9, -9, 99, -99)
    message("\n--- Step 5.6: Validating No Missing Codes in Item Responses ---")
    source("R/utils/validate_no_missing_codes.R")

    transformed_data <- validate_no_missing_codes(
      dat = transformed_data,
      lexicon_name = "ne25",
      verbose = TRUE,
      stop_on_error = TRUE  # Stop pipeline if missing codes found
    )

    if (!validation_result$passed) {
      stop("Pipeline halted: Critical data loss detected during transformation. ",
           "Review validation errors above.")
    }

    message("Data validation passed: No unexpected data loss detected")

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
    metrics$records_data_quality <- sum(final_data$data_quality, na.rm = TRUE)

    message(paste("Eligibility validation completed:"))
    message(paste("  - Eligible participants:", metrics$records_eligible))
    message(paste("  - Data quality validated:", metrics$records_data_quality))

    processing_time <- as.numeric(Sys.time() - processing_start)
    metrics$processing_duration <- processing_time

    # STEP 6.1: VALIDATE ITEM COUNTS (Reverse Coding Verification)
    message("\n--- Step 6.1: Validate Item Counts ---")
    source("R/utils/validate_item_counts.R")

    # Filter to eligible participants only for validation
    eligible_data <- final_data %>% dplyr::filter(eligible == TRUE)

    validation_result <- validate_item_counts(
      dat = eligible_data,
      csv_path = "output/ne25/authenticity_screening/manual_screening/incorrectly_coded_items_06Dec2025.csv",
      codebook_path = "codebook/data/codebook.json",
      verbose = TRUE,
      stop_on_error = TRUE  # Stop pipeline if validation fails
    )

    if (!validation_result$passed) {
      stop("Pipeline halted: Item count validation failed. ",
           "Codebook reverse coding may not be applied correctly.")
    }

    message("Item count validation passed: Codebook fixes verified")

    # Store eligibility summary table
    message("\nStoring eligibility summary...")
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

    # STEP 6.5: JOIN MANUAL INFLUENTIAL OBSERVATIONS (IF AVAILABLE)
    message("\n--- Step 6.5: Joining Influential Observations ---")
    influential_start <- Sys.time()

    # Check if ne25_flagged_observations table exists in database
    tryCatch({
      library(DBI)
      library(duckdb)

      con <- DBI::dbConnect(duckdb::duckdb(), dbdir = config$output$database_path, read_only = TRUE)

      # Check if table exists
      table_exists <- DBI::dbExistsTable(con, "ne25_flagged_observations")

      if (table_exists) {
        message("Loading manually identified influential observations from database...")
        influential_obs <- DBI::dbGetQuery(con, "SELECT * FROM ne25_flagged_observations")
        DBI::dbDisconnect(con, shutdown = TRUE)

        # Handle column name variations (recordid vs record_id)
        if ("recordid" %in% names(influential_obs) && !"record_id" %in% names(influential_obs)) {
          influential_obs <- influential_obs %>%
            dplyr::rename(record_id = recordid)
          message("  - Renamed 'recordid' column to 'record_id' for consistency")
        }

        # Create influential flag based on presence in table
        # Note: Table only contains flagged observations, so any match = influential
        influential_ids <- influential_obs %>%
          dplyr::select(pid, record_id) %>%
          dplyr::mutate(influential = TRUE)

        # Join influential observations to final_data
        final_data <- final_data %>%
          dplyr::left_join(
            influential_ids,
            by = c("pid", "record_id")
          ) %>%
          dplyr::mutate(
            influential = dplyr::coalesce(influential, FALSE)
          )

        n_influential <- sum(final_data$influential, na.rm = TRUE)
        message(sprintf("  - Influential observations: %d (%.1f%%)",
                       n_influential, 100 * n_influential / nrow(final_data)))
        metrics$records_influential <- n_influential

      } else {
        message("No influential observations found (ne25_flagged_observations table does not exist)")
        message("  - All observations marked as non-influential")
        message("  - To identify influential observations, run manual influence diagnostics:")
        message("    See: scripts/authenticity_screening/README.md")

        # Create empty influential column
        final_data$influential <- FALSE
        metrics$records_influential <- 0
      }

    }, error = function(e) {
      warning(paste("Failed to load influential observations:", e$message))
      message("  - Continuing without influential observations")
      final_data$influential <- FALSE
      metrics$records_influential <- 0
    })

    # Cache result
    message("DEBUG: Caching influential observations...")
    saveRDS(final_data, file.path(cache_dir, "step6.5_influential_observations.rds"))
    message("DEBUG: Cached influential observations (", nrow(final_data), " records)")

    influential_time <- as.numeric(Sys.time() - influential_start)
    metrics$influential_duration <- influential_time
    message(paste("Influential observations joining completed in", round(influential_time, 2), "seconds"))

    # STEP 6.7: JOIN GSED PERSON-FIT SCORES AND TOO-FEW-ITEMS FLAGS
    message("\n--- Step 6.7: Joining GSED Scores and Item Insufficiency Flags ---")
    person_scores_start <- Sys.time()

    tryCatch({
      library(DBI)
      library(duckdb)

      con <- DBI::dbConnect(duckdb::duckdb(), dbdir = config$output$database_path, read_only = TRUE)

      # ===== TABLE 1: GSED Person-Fit Scores =====
      gsed_table_exists <- DBI::dbExistsTable(con, "ne25_kidsights_gsed_pf_scores_2022_scale")

      if (gsed_table_exists) {
        message("Loading GSED person-fit scores from database...")
        gsed_scores <- DBI::dbGetQuery(con, "SELECT * FROM ne25_kidsights_gsed_pf_scores_2022_scale")

        # Join GSED scores to final_data (exclude year, fips, state - already in final_data)
        final_data <- final_data %>%
          safe_left_join(
            gsed_scores %>% dplyr::select(pid, record_id, dplyr::starts_with("kidsights_"), dplyr::starts_with("general_"), dplyr::starts_with("feeding_"), dplyr::starts_with("externalizing_"), dplyr::starts_with("internalizing_"), dplyr::starts_with("sleeping_"), dplyr::starts_with("social_")),
            by_vars = c("pid", "record_id")
          )

        n_gsed <- sum(!is.na(final_data$kidsights_2022), na.rm = TRUE)
        message(sprintf("  - Records with GSED scores: %d (%.1f%%)",
                       n_gsed, 100 * n_gsed / nrow(final_data)))

      } else {
        message("  - GSED scores table not found (skipping)")
      }

      # ===== TABLE 2: Too-Few-Items Flags =====
      too_few_table_exists <- DBI::dbExistsTable(con, "ne25_too_few_items")

      if (too_few_table_exists) {
        message("Loading too-few-items flags from database...")
        too_few <- DBI::dbGetQuery(con, "SELECT * FROM ne25_too_few_items")

        # Join too-few-items flags to final_data (exclude year, fips, state - already in final_data)
        final_data <- final_data %>%
          safe_left_join(
            too_few %>% dplyr::select(pid, record_id, too_few_item_responses, n_kidsight_psychosocial_responses, exclusion_reason),
            by_vars = c("pid", "record_id")
          )

        n_too_few <- sum(final_data$too_few_item_responses == TRUE, na.rm = TRUE)
        message(sprintf("  - Records with too few items: %d (%.1f%%)",
                       n_too_few, 100 * n_too_few / nrow(final_data)))

      } else {
        message("  - Too-few-items table not found (skipping)")
      }

      DBI::dbDisconnect(con, shutdown = TRUE)

    }, error = function(e) {
      warning(paste("Failed to load person-fit tables:", e$message))
      message("  - Continuing without GSED scores and item flags")
    })

    # Cache result
    message("DEBUG: Caching after person-fit joins...")
    saveRDS(final_data, file.path(cache_dir, "step6.7_person_fit_joins.rds"))
    message("DEBUG: Cached person-fit data (", nrow(final_data), " records)")

    person_scores_time <- as.numeric(Sys.time() - person_scores_start)
    metrics$person_scores_duration <- person_scores_time
    message(paste("Person-fit joins completed in", round(person_scores_time, 2), "seconds"))

    # STEP 6.8: CREATE MEETS_INCLUSION COLUMN
    message("\n--- Step 6.8: Creating meets_inclusion Column ---")
    inclusion_start <- Sys.time()

    # Define meets_inclusion as: eligible=TRUE & influential=FALSE & too_few_item_responses=FALSE
    # Note: too_few_item_responses is NA for most records (not TRUE), so we treat NA as FALSE
    # Ensure influential column exists (create if missing)
    if (!"influential" %in% names(final_data)) {
      message("  - WARNING: influential column not found, creating with all FALSE")
      final_data$influential <- FALSE
    }

    final_data <- final_data %>%
      dplyr::mutate(
        meets_inclusion = (eligible == TRUE) &
                         (influential == FALSE | is.na(influential)) &
                         (dplyr::coalesce(too_few_item_responses, FALSE) == FALSE)
      )

    n_meets_inclusion <- sum(final_data$meets_inclusion, na.rm = TRUE)
    message(sprintf("  - Records meeting inclusion criteria: %d (%.1f%%)",
                   n_meets_inclusion, 100 * n_meets_inclusion / nrow(final_data)))

    # Breakdown of exclusions
    n_ineligible <- sum(final_data$eligible == FALSE, na.rm = TRUE)
    n_influential_only <- sum(final_data$eligible == TRUE & final_data$influential == TRUE, na.rm = TRUE)
    n_too_few_only <- sum(final_data$eligible == TRUE & final_data$influential == FALSE &
                          dplyr::coalesce(final_data$too_few_item_responses, FALSE) == TRUE, na.rm = TRUE)

    message("  Exclusion breakdown:")
    message(sprintf("    - Ineligible: %d", n_ineligible))
    message(sprintf("    - Influential: %d", n_influential_only))
    message(sprintf("    - Too few item responses: %d", n_too_few_only))

    metrics$records_meets_inclusion <- n_meets_inclusion

    inclusion_time <- as.numeric(Sys.time() - inclusion_start)
    metrics$inclusion_duration <- inclusion_time
    message(paste("meets_inclusion column created in", round(inclusion_time, 2), "seconds"))

    # STEP 6.9: OPTIONAL - JOIN CALIBRATED WEIGHTS IF AVAILABLE
    # NOTE: Must be done BEFORE Step 7 (database storage) so weights are included in database
    message("\n--- Step 6.9: Checking for Calibrated Weights ---")
    weights_file <- "data/raking/ne25/ne25_weights/ne25_calibrated_weights_m1.feather"

    if (file.exists(weights_file)) {
      message("Found calibrated weights file. Attempting to join...")

      tryCatch({
        # Load weights
        weights_data <- arrow::read_feather(weights_file)

        # Extract weight column and join key
        weights_to_join <- weights_data %>%
          dplyr::select(pid, record_id, calibrated_weight)

        message(sprintf("  - Loaded %d weight records", nrow(weights_to_join)))

        # Join to final_data via (pid, record_id)
        n_before <- nrow(final_data)
        final_data <- final_data %>%
          dplyr::left_join(
            weights_to_join,
            by = c("pid", "record_id"),
            relationship = "one-to-one"
          )

        n_matched <- sum(!is.na(final_data$calibrated_weight))
        message(sprintf("  - Matched weights to %d records (%.1f%% of %d total)",
                       n_matched, 100 * n_matched / n_before, n_before))

        if (n_matched < n_before) {
          message(sprintf("  - WARNING: %d records have no matching weight", n_before - n_matched))
        }

        message("  ✓ Calibrated weights successfully joined to transformed data")

      }, error = function(e) {
        message(paste("  ✗ Error joining weights:", e$message))
        message("  Continuing without weights")
      })
    } else {
      message("  - No calibrated weights file found. Continuing without weights.")
      message(sprintf("    Expected location: %s", weights_file))
      message("    To generate weights, run scripts 25-33 in the raking pipeline.")
    }

    # STEP 6.10: BANDAID FIX - Mark out-of-state records (meets_inclusion=T but no weight)
    message("\n--- Step 6.10: Marking Out-of-State Records ---")

    # If meets_inclusion=T but calibrated_weight is NA, set out_of_state=T and meets_inclusion=F
    final_data <- final_data %>%
      dplyr::mutate(
        out_of_state = dplyr::case_when(
          meets_inclusion == TRUE & is.na(calibrated_weight) ~ TRUE,
          TRUE ~ FALSE
        ),
        meets_inclusion = dplyr::case_when(
          out_of_state == TRUE ~ FALSE,
          TRUE ~ meets_inclusion
        )
      )

    n_out_of_state <- sum(final_data$out_of_state, na.rm = TRUE)
    if (n_out_of_state > 0) {
      message(sprintf("  - Marked %d records as out-of-state (meets_inclusion=T but no weight)", n_out_of_state))
      n_meets_inclusion_updated <- sum(final_data$meets_inclusion, na.rm = TRUE)
      message(sprintf("  - Updated meets_inclusion: %d records (%.1f%%)",
                     n_meets_inclusion_updated, 100 * n_meets_inclusion_updated / nrow(final_data)))
    } else {
      message("  - No out-of-state records detected")
    }

    # STEP 7: STORE TRANSFORMED DATA WITH ELIGIBILITY FLAGS (AND WEIGHTS IF AVAILABLE)
    message("\n--- Step 7: Storing Transformed Data ---")
    message("Storing transformed data with eligibility flags and calibrated weights...")
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

    # ===========================================================================
    # STEP 7.5: CREDI SCORING (FOR CHILDREN UNDER 4 YEARS OLD)
    # ===========================================================================
    message("\n--- Step 7.5: CREDI Developmental Scoring ---")
    credi_start <- Sys.time()

    # Source CREDI scoring function
    tryCatch({
      source("R/credi/score_credi.R")

      # Run CREDI scoring
      message("Computing CREDI developmental scores for children under 4 years old...")
      credi_scores <- score_credi(
        data = final_data,
        codebook_path = "codebook/data/codebook.json",
        min_items = 5,
        age_cutoff = 4,
        verbose = TRUE
      )

      # Save to database
      if (nrow(credi_scores) > 0) {
        message(sprintf("CREDI scoring complete. Saving %d records to database...", nrow(credi_scores)))

        save_credi_scores_to_db(
          scores = credi_scores,
          db_path = "data/duckdb/kidsights_local.duckdb",
          table_name = "ne25_credi_scores",
          overwrite = TRUE,
          verbose = TRUE
        )

        metrics$credi_records_scored <- sum(!is.na(credi_scores$OVERALL))
        metrics$credi_records_attempted <- nrow(credi_scores)
      } else {
        message("No records eligible for CREDI scoring (no children under 4 years old)")
        metrics$credi_records_scored <- 0
        metrics$credi_records_attempted <- 0
      }

    }, error = function(e) {
      warning(paste("CREDI scoring failed:", e$message))
      warning("Continuing pipeline without CREDI scores")
      metrics$credi_records_scored <- 0
      metrics$credi_records_attempted <- 0
    })

    credi_end <- Sys.time()
    credi_time <- as.numeric(difftime(credi_end, credi_start, units = "secs"))
    metrics$credi_scoring_duration <- credi_time
    message(paste("CREDI scoring completed in", round(credi_time, 2), "seconds"))

    # ===========================================================================
    # STEP 7.6: GSED D-SCORE CALCULATION (ALL ELIGIBLE AGES)
    # ===========================================================================
    message("\n--- Step 7.6: GSED D-score Calculation ---")
    dscore_start <- Sys.time()

    # Source GSED D-score function
    tryCatch({
      source("R/dscore/score_dscore.R")

      # Run GSED D-score calculation
      message("Computing GSED D-scores for all eligible children...")
      dscore_scores <- score_dscore(
        data = final_data,
        codebook_path = "codebook/data/codebook.json",
        key = "gsed2406",
        verbose = TRUE
      )

      # Save to database
      if (nrow(dscore_scores) > 0) {
        message(sprintf("GSED D-score calculation complete. Saving %d records to database...", nrow(dscore_scores)))

        save_dscore_scores_to_db(
          scores = dscore_scores,
          db_path = "data/duckdb/kidsights_local.duckdb",
          table_name = "ne25_dscore_scores",
          overwrite = TRUE,
          verbose = TRUE
        )

        metrics$dscore_records_scored <- sum(!is.na(dscore_scores$d))
        metrics$dscore_records_attempted <- nrow(dscore_scores)
      } else {
        message("No records eligible for GSED D-score calculation")
        metrics$dscore_records_scored <- 0
        metrics$dscore_records_attempted <- 0
      }

    }, error = function(e) {
      warning(paste("GSED D-score calculation failed:", e$message))
      warning("Continuing pipeline without GSED D-scores")
      metrics$dscore_records_scored <- 0
      metrics$dscore_records_attempted <- 0
    })

    dscore_end <- Sys.time()
    dscore_time <- as.numeric(difftime(dscore_end, dscore_start, units = "secs"))
    metrics$dscore_scoring_duration <- dscore_time
    message(paste("GSED D-score calculation completed in", round(dscore_time, 2), "seconds"))

    # ===========================================================================
    # STEP 7.7: HRTL SCORING (FULL PIPELINE: EXTRACT -> RASCH -> IMPUTE -> SCORE)
    # ===========================================================================
    message("\n--- Step 7.7: HRTL Scoring Pipeline ---")
    hrtl_start <- Sys.time()

    tryCatch({
      # Step 7.7a: Extract domain datasets and derive DailyAct_22
      message("\n  [7.7a] Extracting domain datasets...")
      source("scripts/hrtl/01_extract_domain_datasets.R")

      # Step 7.7b: Fit Rasch models for each domain
      message("\n  [7.7b] Fitting Rasch models...")
      source("scripts/hrtl/02_fit_rasch_models.R")

      # Step 7.7c: Impute missing values using Rasch EAP scores
      message("\n  [7.7c] Imputing missing values...")
      source("scripts/hrtl/03_impute_missing_values.R")

      # Step 7.7d: Score HRTL domains using CAHMI thresholds
      # Uses validated scoring logic from 04_score_hrtl.R (produces correct percentages)
      message("\n  [7.7d] Scoring HRTL domains...")
      source("scripts/hrtl/04_score_hrtl.R")

      # Extract results from the script's global variables
      hrtl_results <- list(
        domain_scores = dplyr::bind_rows(lapply(names(domain_results), function(domain) {
          domain_results[[domain]]$coded_data %>%
            dplyr::mutate(
              domain = domain,
              classification = status,
              avg_code = avg_score
            ) %>%
            dplyr::select(pid, record_id, domain, avg_code, classification, years_old)
        })),
        hrtl_overall = hrtl_data %>%
          dplyr::select(pid, record_id, n_on_track, n_needs_support, hrtl)
      )

      # Save domain scores to database
      if (nrow(hrtl_results$domain_scores) > 0) {
        message(sprintf("HRTL scoring complete. Saving %d domain score records to database...", nrow(hrtl_results$domain_scores)))

        # =========================================================================
        # NE25 DATA QUALITY MASKING (Issue #15)
        # https://github.com/anthropics/kidsights/issues/15
        #
        # Motor Development domain excluded due to 93% missing data in NE25:
        # - DrawFace, DrawPerson, BounceBall items are age-routed and largely missing
        # - Imputation on 93% missing data produces unreliable estimates
        # - Overall HRTL marked NA because it requires all 5 domains
        # =========================================================================
        message("\n[NE25 Data Quality] Masking Motor Development and overall HRTL (Issue #15)")

        # Mask Motor Development classification as NA
        hrtl_results$domain_scores <- hrtl_results$domain_scores %>%
          dplyr::mutate(
            classification = dplyr::if_else(
              domain == "Motor Development",
              NA_character_,
              classification
            ),
            avg_code = dplyr::if_else(
              domain == "Motor Development",
              NA_real_,
              avg_code
            )
          )

        # Mark overall HRTL as NA (incomplete without Motor Development)
        hrtl_results$hrtl_overall <- hrtl_results$hrtl_overall %>%
          dplyr::mutate(hrtl = NA)

        message("  - Motor Development: classification masked as NA")
        message("  - Overall HRTL: marked as NA (requires all 5 domains)")

        # Save to database directly
        hrtl_con <- duckdb::dbConnect(duckdb::duckdb(),
                                      dbdir = "data/duckdb/kidsights_local.duckdb",
                                      read_only = FALSE)

        tryCatch({
          # Save domain scores
          DBI::dbWriteTable(hrtl_con, "ne25_hrtl_domain_scores", hrtl_results$domain_scores,
                           overwrite = TRUE, append = FALSE)
          message(sprintf("[OK] Saved %d domain score records", nrow(hrtl_results$domain_scores)))

          # Create index
          DBI::dbExecute(hrtl_con,
            "CREATE INDEX IF NOT EXISTS idx_ne25_hrtl_domain_scores_pid
             ON ne25_hrtl_domain_scores (pid, record_id, domain)")

          # Save overall HRTL
          DBI::dbWriteTable(hrtl_con, "ne25_hrtl_overall", hrtl_results$hrtl_overall,
                           overwrite = TRUE, append = FALSE)
          message(sprintf("[OK] Saved %d overall HRTL records", nrow(hrtl_results$hrtl_overall)))

          # Create index
          DBI::dbExecute(hrtl_con,
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_ne25_hrtl_overall_pid
             ON ne25_hrtl_overall (pid, record_id)")

        }, finally = {
          duckdb::dbDisconnect(hrtl_con, shutdown = TRUE)
        })

        # Calculate metrics (exclude Motor Development from scored count)
        n_children_scored <- length(unique(hrtl_results$domain_scores$pid[
          !is.na(hrtl_results$domain_scores$avg_code) &
          hrtl_results$domain_scores$domain != "Motor Development"
        ]))
        metrics$hrtl_records_attempted <- length(unique(hrtl_results$hrtl_overall$pid))
        metrics$hrtl_records_scored <- n_children_scored

        message(sprintf("\nHRTL Domain Classification Summary:"))
        for (domain in unique(hrtl_results$domain_scores$domain)) {
          domain_data <- hrtl_results$domain_scores %>%
            dplyr::filter(domain == !!domain)
          if (domain == "Motor Development") {
            message(sprintf("  %s: MASKED (NE25 data quality issue)", domain))
          } else {
            on_track <- sum(domain_data$classification == "On-Track", na.rm = TRUE)
            n_domain <- sum(!is.na(domain_data$classification))
            pct <- 100 * on_track / n_domain
            message(sprintf("  %s: %d/%d on-track (%.1f%%)", domain, on_track, n_domain, pct))
          }
        }
      } else {
        message("No records eligible for HRTL scoring (no children ages 3-5)")
        metrics$hrtl_records_scored <- 0
        metrics$hrtl_records_attempted <- 0
      }

    }, error = function(e) {
      warning(paste("HRTL scoring failed:", e$message))
      warning("Continuing pipeline without HRTL scores")
      metrics$hrtl_records_scored <- 0
      metrics$hrtl_records_attempted <- 0
    })

    hrtl_end <- Sys.time()
    hrtl_time <- as.numeric(difftime(hrtl_end, hrtl_start, units = "secs"))
    metrics$hrtl_scoring_duration <- hrtl_time
    message(paste("HRTL scoring completed in", round(hrtl_time, 2), "seconds"))

    # ===========================================================================
    # STEP 7.8: JOIN HRTL DOMAIN SCORES INTO FINAL_DATA
    # ===========================================================================
    message("\n--- Step 7.8: Joining HRTL Domain Scores ---")
    hrtl_join_start <- Sys.time()

    # HRTL scores are now available in database tables:
    # - ne25_hrtl_domain_scores: 4 domains × ~1,886 children = ~7,544 records
    # - ne25_hrtl_overall: Summary stats per child (1,886 records)
    # These tables are indexed by pid + record_id for efficient querying
    message("  - HRTL domain and overall scores saved to database tables")
    message("  - Access via: SELECT * FROM ne25_hrtl_domain_scores WHERE pid = ? AND record_id = ?")
    message("  - Tables indexed on (pid, record_id, domain) for efficient lookups")

    hrtl_join_time <- as.numeric(Sys.time() - hrtl_join_start)
    message(paste("HRTL join completed in", round(hrtl_join_time, 2), "seconds"))

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
    # STEP 11: CREATE NE25 CALIBRATION TABLE (REMOVED)
    # ===========================================================================
    #
    # NOTE: This step was removed to establish single source of truth.
    #
    # OLD ARCHITECTURE (confusing):
    #   - NE25 Pipeline → ne25_transformed → ne25_calibration (intermediate table)
    #   - Calibration Pipeline → reads ne25_calibration
    #
    # NEW ARCHITECTURE (clean):
    #   - NE25 Pipeline → ne25_transformed (stops here)
    #   - Calibration Pipeline → reads ne25_transformed directly
    #
    # The calibration_dataset_long table is now the ONLY calibration table,
    # created by scripts/irt_scoring/create_calibration_long.R
    # ===========================================================================

    message("\n--- Step 11: NE25 Calibration Table (skipped - handled by calibration pipeline) ---")
    metrics$calibration_table_duration <- 0

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
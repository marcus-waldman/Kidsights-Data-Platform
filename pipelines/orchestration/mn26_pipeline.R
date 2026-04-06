#' MN26 Pipeline Orchestration
#'
#' Main pipeline function that coordinates the complete MN26 data extraction,
#' pivot (wide-to-long for multi-child households), transformation, eligibility
#' validation, and database loading workflow.
#'
#' Pipeline Steps:
#'   1. Load API credentials
#'   2. Extract REDCap data + dictionary
#'   3. Wide-to-long pivot (multi-child → 1 row per child)
#'   4. Store raw data (wide + long) in DuckDB
#'   5. Data transformation (recode_it with MN26 field names)
#'   6. Eligibility validation (4 criteria)
#'   7. Create meets_inclusion filter
#'   8. Kidsights developmental scoring (KidsightsPublic package)
#'   9. Store transformed data in DuckDB
#'   10. Store data dictionary

# Load required libraries
library(dplyr)
library(yaml)
library(arrow)
library(KidsightsPublic)  # CmdStan MAP scoring (score_kidsights, score_psychosocial)

# Source required functions
source("R/extract/mn26.R")
source("R/transform/mn26_pivot.R")
source("R/transform/mn26_transforms.R")
source("R/harmonize/mn26_eligibility.R")
source("R/utils/environment_config.R")
source("R/utils/safe_joins.R")

#' Execute the complete MN26 pipeline
#'
#' @param config_path Path to MN26 configuration file
#' @param credentials_path Path to API credentials CSV (overrides config/env)
#' @param skip_database Logical, skip database storage (useful for testing)
#' @return List with execution results and metrics
run_mn26_pipeline <- function(config_path = "config/sources/mn26.yaml",
                              credentials_path = NULL,
                              skip_database = FALSE) {

  execution_id <- paste0("mn26_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  pipeline_start <- Sys.time()

  message("\n========================================")
  message("MN26 Pipeline")
  message("========================================")
  message("Execution ID: ", execution_id)
  message("Start Time:   ", pipeline_start)

  # Load configuration
  config <- yaml::read_yaml(config_path)
  message("[OK] Configuration loaded")

  # Initialize metrics
  metrics <- list(
    execution_id = execution_id,
    start_time = pipeline_start,
    n_extracted = 0,
    n_pivoted = 0,
    n_child1 = 0,
    n_child2 = 0,
    n_eligible = 0,
    n_meets_inclusion = 0,
    step_durations = list()
  )

  tryCatch({

    # ==================================================================
    # STEP 1: LOAD API CREDENTIALS
    # ==================================================================
    message("\n--- Step 1: Loading API Credentials ---")
    step_start <- Sys.time()

    creds <- load_mn26_credentials(csv_path = credentials_path, config = config)

    metrics$step_durations$credentials <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 2: EXTRACT DATA + DICTIONARY FROM REDCAP
    # ==================================================================
    message("\n--- Step 2: Extracting REDCap Data ---")
    step_start <- Sys.time()

    extraction <- extract_mn26_data(
      credentials = creds,
      redcap_url = config$redcap$url,
      timeout = config$redcap$timeout
    )

    raw_wide <- extraction$data
    dictionary <- extraction$dictionary
    dictionary_full <- extraction$dictionary_full

    metrics$n_extracted <- nrow(raw_wide)
    metrics$step_durations$extraction <- as.numeric(Sys.time() - step_start)
    message(sprintf("  Extracted: %d records, %d columns", nrow(raw_wide), ncol(raw_wide)))

    # Ensure sq001 (ZIP) is character
    if ("sq001" %in% names(raw_wide)) {
      raw_wide$sq001 <- as.character(raw_wide$sq001)
    }

    # ==================================================================
    # STEP 3: WIDE-TO-LONG PIVOT
    # ==================================================================
    message("\n--- Step 3: Wide-to-Long Pivot ---")
    step_start <- Sys.time()

    raw_long <- pivot_mn26_wide_to_long(raw_wide)

    metrics$n_pivoted <- nrow(raw_long)
    metrics$n_child1 <- sum(raw_long$child_num == 1)
    metrics$n_child2 <- sum(raw_long$child_num == 2)
    metrics$step_durations$pivot <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 4: STORE RAW DATA IN DUCKDB
    # ==================================================================
    if (!skip_database) {
      message("\n--- Step 4: Storing Raw Data ---")
      step_start <- Sys.time()

      temp_dir <- file.path(tempdir(), "mn26_pipeline")
      dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

      python_path <- get_python_path()
      db_path <- config$output$database_path

      # 4a: Store wide format (audit trail)
      wide_feather <- file.path(temp_dir, "mn26_raw_wide.feather")
      wide_meta <- raw_wide %>%
        dplyr::select(record_id, pid, dplyr::any_of(c(
          "redcap_event_name", "retrieved_date", "source_project", "extraction_id"
        )))
      arrow::write_feather(wide_meta, wide_feather)

      system2(python_path, args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", wide_feather,
        "--table-name", "mn26_raw_wide",
        "--data-type", "raw",
        "--config", config_path
      ), stdout = TRUE, stderr = TRUE)
      message("  [OK] mn26_raw_wide stored (", nrow(wide_meta), " rows)")

      # 4b: Store long format (post-pivot)
      long_feather <- file.path(temp_dir, "mn26_raw.feather")
      long_meta <- raw_long %>%
        dplyr::select(record_id, pid, child_num, dplyr::any_of(c(
          "redcap_event_name", "retrieved_date", "source_project", "extraction_id"
        )))
      arrow::write_feather(long_meta, long_feather)

      system2(python_path, args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", long_feather,
        "--table-name", "mn26_raw",
        "--data-type", "raw",
        "--config", config_path
      ), stdout = TRUE, stderr = TRUE)
      message("  [OK] mn26_raw stored (", nrow(long_meta), " rows)")

      metrics$step_durations$store_raw <- as.numeric(Sys.time() - step_start)
    } else {
      message("\n--- Step 4: SKIPPED (skip_database=TRUE) ---")
    }

    # ==================================================================
    # STEP 5: DATA TRANSFORMATION
    # ==================================================================
    message("\n--- Step 5: Data Transformation ---")
    step_start <- Sys.time()

    # Apply transforms using MN26-specific recode_it
    # Note: recode_it uses the dictionary for value labels (dictionary-driven)
    transformed_data <- recode_it(
      dat = raw_long,
      dict = dictionary_full,  # Use full dict (includes @HIDDEN fields for value_labels)
      what = "all"
    )

    metrics$step_durations$transformation <- as.numeric(Sys.time() - step_start)
    message(sprintf("  Transformed: %d records, %d columns",
                    nrow(transformed_data), ncol(transformed_data)))

    # ==================================================================
    # STEP 6: ELIGIBILITY VALIDATION
    # ==================================================================
    message("\n--- Step 6: Eligibility Validation ---")
    step_start <- Sys.time()

    transformed_data <- check_mn26_eligibility(transformed_data)
    metrics$n_eligible <- sum(transformed_data$eligible, na.rm = TRUE)

    metrics$step_durations$eligibility <- as.numeric(Sys.time() - step_start)

    # ==================================================================
    # STEP 7: CREATE MEETS_INCLUSION FILTER
    # ==================================================================
    message("\n--- Step 7: Inclusion Filter ---")

    transformed_data <- apply_mn26_inclusion(transformed_data)
    metrics$n_meets_inclusion <- sum(transformed_data$meets_inclusion, na.rm = TRUE)

    # ==================================================================
    # STEP 8: KIDSIGHTS DEVELOPMENTAL SCORING
    # ==================================================================
    message("\n--- Step 8: Kidsights Developmental Scoring ---")
    step_start <- Sys.time()

    tryCatch({
      kidsights_scores <- KidsightsPublic::score_kidsights(
        transformed_data,
        id_cols = c("pid", "record_id", "child_num"),
        min_responses = 5
      )

      # Join theta back to transformed data
      transformed_data <- transformed_data %>%
        safe_left_join(
          kidsights_scores %>% dplyr::rename(kidsights_theta = theta),
          by_vars = c("pid", "record_id", "child_num")
        )

      n_scored <- sum(!is.na(transformed_data$kidsights_theta))
      message(sprintf("  Scored: %d of %d children", n_scored, nrow(transformed_data)))
      metrics$n_kidsights_scored <- n_scored
    }, error = function(e) {
      message("  [WARN] Kidsights scoring failed: ", e$message)
      transformed_data$kidsights_theta <<- NA_real_
      metrics$n_kidsights_scored <<- 0
    })

    metrics$step_durations$kidsights_scoring <- as.numeric(Sys.time() - step_start)

    # NOTE: Psychosocial domain scoring (score_psychosocial) is NOT included
    # for MN26 — psychosocial items are NE25-specific.

    # ==================================================================
    # STEP 9: STORE TRANSFORMED DATA IN DUCKDB
    # ==================================================================
    if (!skip_database) {
      message("\n--- Step 9: Storing Transformed Data ---")
      step_start <- Sys.time()

      transformed_feather <- file.path(temp_dir, "mn26_transformed.feather")
      arrow::write_feather(transformed_data, transformed_feather)

      system2(python_path, args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", transformed_feather,
        "--table-name", "mn26_transformed",
        "--data-type", "raw",
        "--config", config_path
      ), stdout = TRUE, stderr = TRUE)
      message("  [OK] mn26_transformed stored (", nrow(transformed_data), " rows)")

      metrics$step_durations$store_transformed <- as.numeric(Sys.time() - step_start)
    } else {
      message("\n--- Step 9: SKIPPED (skip_database=TRUE) ---")
    }

    # ==================================================================
    # STEP 10: STORE DATA DICTIONARY
    # ==================================================================
    if (!skip_database) {
      message("\n--- Step 10: Storing Data Dictionary ---")

      dict_df <- dictionary_to_dataframe(dictionary_full)
      dict_feather <- file.path(temp_dir, "mn26_data_dictionary.feather")
      arrow::write_feather(dict_df, dict_feather)

      system2(python_path, args = c(
        "pipelines/python/insert_raw_data.py",
        "--data-file", dict_feather,
        "--table-name", "mn26_data_dictionary",
        "--data-type", "raw",
        "--config", config_path
      ), stdout = TRUE, stderr = TRUE)
      message("  [OK] mn26_data_dictionary stored (", nrow(dict_df), " fields)")
    }

  }, error = function(e) {
    message("\n[ERROR] Pipeline failed: ", e$message)
    metrics$error <- e$message
  })

  # ==================================================================
  # SUMMARY
  # ==================================================================
  metrics$total_duration <- as.numeric(Sys.time() - pipeline_start)

  message("\n========================================")
  message("MN26 Pipeline Complete")
  message("========================================")
  message(sprintf("  Records extracted:    %d", metrics$n_extracted))
  message(sprintf("  Records after pivot:  %d (child 1: %d, child 2: %d)",
                  metrics$n_pivoted, metrics$n_child1, metrics$n_child2))
  message(sprintf("  Eligible:             %d", metrics$n_eligible))
  message(sprintf("  Meets inclusion:      %d", metrics$n_meets_inclusion))
  message(sprintf("  Kidsights scored:     %d", if (is.null(metrics$n_kidsights_scored)) 0 else metrics$n_kidsights_scored))
  message(sprintf("  Total duration:       %.1f seconds", metrics$total_duration))
  message("========================================\n")

  return(list(
    metrics = metrics,
    data = transformed_data,
    raw_wide = raw_wide,
    raw_long = raw_long,
    dictionary = dictionary,
    dictionary_full = dictionary_full
  ))
}

#!/usr/bin/env Rscript
#' ACS Data Pipeline - R Orchestration Script
#'
#' @description
#' Main R orchestration pipeline for ACS data processing.
#' Loads raw IPUMS ACS data, validates quality, and writes processed output.
#'
#' **IMPORTANT**: This pipeline does NOT perform transformations or harmonization.
#' It validates raw IPUMS data and passes it through unchanged.
#'
#' @section Workflow:
#' 1. Parse command-line arguments (state, year_range)
#' 2. Load raw Feather data from Python extraction
#' 3. Validate data quality (filters, variables, weights)
#' 4. Write validated data to processed.feather
#' 5. Generate validation report
#' 6. Log pipeline execution
#'
#' @section Usage:
#' ```bash
#' "C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
#'   --file=pipelines/orchestration/run_acs_pipeline.R \
#'   --args state=nebraska year_range=2019-2023
#' ```
#'
#' @section Command-line Arguments:
#' - state: State name (required, e.g., "nebraska")
#' - year_range: Year range (required, e.g., "2019-2023")
#' - state_fip: State FIPS code (optional, for validation)
#' - verbose: Print detailed messages (optional, default: TRUE)
#'
#' @section Output:
#' - data/acs/{state}/{year_range}/processed.feather: Validated data
#' - data/acs/{state}/{year_range}/validation_report.txt: Validation report
#'
#' @section Required Packages:
#' - arrow: For Feather file I/O
#' - dplyr: For data manipulation
#'
#' @author Kidsights Data Platform
#' @date 2025-09-30

# Suppress warnings for cleaner output
options(warn = 1)

# ============================================================================
# Parse Command-Line Arguments
# ============================================================================

#' Parse command-line arguments
#'
#' @return Named list with arguments
parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)

  if (length(args) == 0) {
    stop(
      "No arguments provided.\n\n",
      "Usage:\n",
      '  "C:\\Program Files\\R\\R-4.5.1\\bin\\R.exe" --slave --no-restore \\\n',
      "    --file=pipelines/orchestration/run_acs_pipeline.R \\\n",
      "    --args state=nebraska year_range=2019-2023\n"
    )
  }

  # Parse key=value arguments
  parsed_args <- list()

  for (arg in args) {
    parts <- strsplit(arg, "=", fixed = TRUE)[[1]]

    if (length(parts) == 2) {
      key <- trimws(parts[1])
      value <- trimws(parts[2])
      parsed_args[[key]] <- value
    } else {
      warning(sprintf("Ignoring malformed argument: %s", arg))
    }
  }

  # Validate required arguments
  required_args <- c("state", "year_range")
  missing_args <- setdiff(required_args, names(parsed_args))

  if (length(missing_args) > 0) {
    stop(sprintf(
      "Missing required arguments: %s\n\nRequired: state, year_range",
      paste(missing_args, collapse = ", ")
    ))
  }

  # Set defaults for optional arguments
  if (is.null(parsed_args$verbose)) {
    parsed_args$verbose <- "TRUE"
  }

  # Convert verbose to logical
  parsed_args$verbose <- as.logical(parsed_args$verbose)

  # Convert state_fip to integer if provided
  if (!is.null(parsed_args$state_fip)) {
    parsed_args$state_fip <- as.integer(parsed_args$state_fip)
  }

  return(parsed_args)
}


# ============================================================================
# Pipeline Logging Functions
# ============================================================================

#' Print section header
print_section <- function(title, char = "=") {
  width <- 70
  message(paste(rep(char, width), collapse = ""))
  message(title)
  message(paste(rep(char, width), collapse = ""))
}

#' Print step message
print_step <- function(step_num, total_steps, description) {
  message(sprintf("\n[Step %d/%d] %s", step_num, total_steps, description))
  message(paste(rep("-", 70), collapse = ""))
}

#' Print success message
print_success <- function(msg) {
  message(sprintf("✓ %s", msg))
}

#' Print error message
print_error <- function(msg) {
  message(sprintf("✗ ERROR: %s", msg))
}


# ============================================================================
# Main Pipeline Function
# ============================================================================

main <- function() {

  # Start pipeline
  start_time <- Sys.time()

  print_section("ACS DATA PIPELINE - R ORCHESTRATION")
  message(sprintf("Started: %s\n", start_time))

  # Parse arguments
  args <- parse_args()

  state <- args$state
  year_range <- args$year_range
  state_fip <- args$state_fip
  verbose <- args$verbose

  message(sprintf("State: %s", state))
  message(sprintf("Year Range: %s", year_range))
  if (!is.null(state_fip)) {
    message(sprintf("State FIP: %s", state_fip))
  }
  message(sprintf("Verbose: %s\n", verbose))

  total_steps <- 6
  current_step <- 0

  tryCatch({

    # ========================================================================
    # Step 1: Source R Modules
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Source R Modules")

    source("R/load/acs/load_acs_data.R")
    message("  ✓ Sourced: R/load/acs/load_acs_data.R")

    source("R/utils/acs/validate_acs_raw.R")
    message("  ✓ Sourced: R/utils/acs/validate_acs_raw.R")

    print_success("R modules loaded")


    # ========================================================================
    # Step 2: Load Raw Feather Data
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Load Raw Feather Data")

    # Load data using our loading function
    data <- load_acs_feather(
      state = state,
      year_range = year_range,
      add_metadata = TRUE,
      validate = TRUE
    )

    message(sprintf("  Records: %s", format(nrow(data), big.mark = ",")))
    message(sprintf("  Variables: %s", ncol(data)))

    print_success("Raw data loaded successfully")


    # ========================================================================
    # Step 3: Validate Data Quality
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Validate Data Quality")

    # Run comprehensive validation
    validation <- validate_acs_raw_data(
      data = data,
      state_fip = state_fip,
      state = state,
      year_range = year_range,
      expected_ages = 0:5,
      verbose = verbose
    )

    if (validation$overall_passed) {
      print_success("All validation checks passed")
    } else {
      message(sprintf(
        "⚠ WARNING: %d of %d validation checks failed",
        validation$n_failed,
        validation$n_checks
      ))
      message("See validation report for details")
    }


    # ========================================================================
    # Step 4: Write Validation Report
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Write Validation Report")

    # Create output directory
    output_dir <- file.path("data", "acs", state, year_range)
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

    # Write validation report to file
    report_path <- file.path(output_dir, "validation_report.txt")

    sink(report_path)
    print_validation_report(validation)
    sink()

    message(sprintf("  Report written to: %s", report_path))
    print_success("Validation report saved")


    # ========================================================================
    # Step 5: Write Processed Data
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Write Processed Data")

    # Note: "Processed" data is identical to raw data at this stage
    # (no transformations applied). This step validates and standardizes output.

    processed_path <- file.path(output_dir, "processed.feather")

    # Remove metadata columns before writing (keep raw IPUMS variables only)
    data_to_write <- data
    metadata_cols <- c("state", "year_range", "extract_date")
    cols_to_remove <- intersect(metadata_cols, names(data_to_write))

    if (length(cols_to_remove) > 0) {
      data_to_write <- data_to_write[, !(names(data_to_write) %in% cols_to_remove)]
      message(sprintf("  Removed metadata columns: %s", paste(cols_to_remove, collapse = ", ")))
    }

    # Write to Feather format using arrow package
    arrow::write_feather(data_to_write, processed_path)

    # Get file size
    file_size_mb <- file.size(processed_path) / (1024^2)

    message(sprintf("  File: %s", processed_path))
    message(sprintf("  Size: %.2f MB", file_size_mb))
    message(sprintf("  Records: %s", format(nrow(data_to_write), big.mark = ",")))
    message(sprintf("  Variables: %s", ncol(data_to_write)))

    print_success("Processed data written")


    # ========================================================================
    # Step 6: Pipeline Summary
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Pipeline Summary")

    end_time <- Sys.time()
    elapsed <- difftime(end_time, start_time, units = "secs")

    message(sprintf("State: %s", state))
    message(sprintf("Year Range: %s", year_range))
    message(sprintf("Records Processed: %s", format(nrow(data), big.mark = ",")))
    message(sprintf("Variables: %s", ncol(data_to_write)))
    message(sprintf("Validation Status: %s", if (validation$overall_passed) "PASS" else "FAIL"))
    message(sprintf("Output File: %s", processed_path))
    message(sprintf("Validation Report: %s", report_path))
    message(sprintf("Elapsed Time: %.2f seconds", elapsed))


    # ========================================================================
    # Final Status
    # ========================================================================
    message("\n")
    print_section("PIPELINE COMPLETE", "=")

    if (validation$overall_passed) {
      print_success("All checks passed - data ready for database insertion")
      return(0)
    } else {
      message("⚠ Pipeline completed with validation warnings")
      message("Review validation report before database insertion")
      return(1)
    }

  }, error = function(e) {

    # Error handling
    message("\n")
    print_section("PIPELINE FAILED", "=")
    print_error(conditionMessage(e))
    message("\nStack trace:")
    print(traceback())

    return(1)
  })
}

# ============================================================================
# Execute Pipeline
# ============================================================================

# Run main function and capture exit code
exit_code <- main()

# Exit with appropriate code
quit(status = exit_code, save = "no")

#!/usr/bin/env Rscript
#' NHIS Data Pipeline - R Orchestration Script
#'
#' @description
#' Main R orchestration pipeline for NHIS data processing.
#' Loads raw IPUMS NHIS data, validates quality, and writes processed output.
#'
#' **IMPORTANT**: This pipeline does NOT perform transformations or harmonization.
#' It validates raw IPUMS data and passes it through unchanged.
#'
#' @section Workflow:
#' 1. Parse command-line arguments (year_range)
#' 2. Load raw Feather data from Python extraction
#' 3. Validate data quality (variables, years, weights, survey design)
#' 4. Write validated data to processed.feather
#' 5. Generate validation report
#' 6. Log pipeline execution
#'
#' @section Usage:
#' ```bash
#' "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" \
#'   pipelines/orchestration/run_nhis_pipeline.R \
#'   --year-range 2019-2024
#' ```
#'
#' @section Command-line Arguments:
#' - --year-range: Year range (required, e.g., "2019-2024")
#' - --verbose: Print detailed messages (optional, default: TRUE)
#'
#' @section Output:
#' - data/nhis/{year_range}/processed.feather: Validated data
#' - data/nhis/{year_range}/validation_report.txt: Validation report
#'
#' @section Required Packages:
#' - arrow: For Feather file I/O
#' - dplyr: For data manipulation
#'
#' @author Kidsights Data Platform
#' @date 2025-10-03

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
      '  "C:\\Program Files\\R\\R-4.5.1\\bin\\Rscript.exe" \\\n',
      "    pipelines/orchestration/run_nhis_pipeline.R \\\n",
      "    --year-range 2019-2024\n"
    )
  }

  # Parse arguments
  parsed_args <- list()

  for (i in seq_along(args)) {
    arg <- args[i]

    if (arg == "--year-range") {
      if (i + 1 <= length(args)) {
        parsed_args$year_range <- args[i + 1]
      }
    } else if (arg == "--verbose") {
      parsed_args$verbose <- TRUE
    }
  }

  # Validate required arguments
  if (is.null(parsed_args$year_range)) {
    stop("Missing required argument: --year-range\n\nExample: --year-range 2019-2024")
  }

  # Set defaults for optional arguments
  if (is.null(parsed_args$verbose)) {
    parsed_args$verbose <- TRUE
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

  print_section("NHIS DATA PIPELINE - R ORCHESTRATION")
  message(sprintf("Started: %s\n", start_time))

  # Parse arguments
  args <- parse_args()

  year_range <- args$year_range
  verbose <- args$verbose

  message(sprintf("Year Range: %s", year_range))
  message(sprintf("Verbose: %s\n", verbose))

  # Parse expected years from year_range (e.g., "2019-2024" -> 2019:2024)
  year_parts <- strsplit(year_range, "-")[[1]]
  if (length(year_parts) == 2) {
    expected_years <- as.integer(year_parts[1]):as.integer(year_parts[2])
  } else {
    expected_years <- 2019:2024  # Default
  }

  total_steps <- 6
  current_step <- 0

  tryCatch({

    # ========================================================================
    # Step 1: Source R Modules
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Source R Modules")

    source("R/load/nhis/load_nhis_data.R")
    message("  ✓ Sourced: R/load/nhis/load_nhis_data.R")

    source("R/utils/nhis/validate_nhis_raw.R")
    message("  ✓ Sourced: R/utils/nhis/validate_nhis_raw.R")

    print_success("R modules loaded")


    # ========================================================================
    # Step 2: Load Raw Feather Data
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Load Raw Feather Data")

    # Load data using our loading function
    data <- load_nhis_feather(
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
    validation <- validate_nhis_raw_data(
      data = data,
      year_range = year_range,
      expected_years = expected_years,
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
    output_dir <- file.path("data", "nhis", year_range)
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
    metadata_cols <- c("year_range", "loaded_at")
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

    message(sprintf("Year Range: %s", year_range))
    message(sprintf("Expected Years: %s", paste(range(expected_years), collapse = "-")))
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

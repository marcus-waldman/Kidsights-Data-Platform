#!/usr/bin/env Rscript
#' NSCH Data Pipeline - R Orchestration Script
#'
#' @description
#' Main R orchestration pipeline for NSCH data processing.
#' Loads raw NSCH data from SPSS conversion, validates quality, and writes processed output.
#'
#' **IMPORTANT**: This pipeline does NOT perform transformations or harmonization.
#' It validates raw NSCH data and passes it through unchanged.
#'
#' @section Workflow:
#' 1. Parse command-line arguments (year)
#' 2. Load raw Feather data from SPSS conversion
#' 3. Load metadata JSON file
#' 4. Validate data quality (7 validation checks)
#' 5. Write validated data to processed.feather
#' 6. Generate validation report
#' 7. Log pipeline execution
#'
#' @section Usage:
#' ```bash
#' "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" \
#'   pipelines/orchestration/run_nsch_pipeline.R \
#'   --year 2023
#' ```
#'
#' @section Command-line Arguments:
#' - --year: Survey year (required, 2016-2023)
#' - --verbose: Print detailed messages (optional, default: TRUE)
#'
#' @section Output:
#' - data/nsch/{year}/processed.feather: Validated data
#' - data/nsch/{year}/validation_report.txt: Validation report
#'
#' @section Required Packages:
#' - arrow: For Feather file I/O
#' - jsonlite: For metadata JSON parsing
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
      "    pipelines/orchestration/run_nsch_pipeline.R \\\n",
      "    --year 2023\n"
    )
  }

  # Parse arguments
  parsed_args <- list()

  for (i in seq_along(args)) {
    arg <- args[i]

    if (arg == "--year") {
      if (i + 1 <= length(args)) {
        parsed_args$year <- as.integer(args[i + 1])
      }
    } else if (arg == "--verbose") {
      parsed_args$verbose <- TRUE
    }
  }

  # Validate required arguments
  if (is.null(parsed_args$year)) {
    stop("Missing required argument: --year\n\nExample: --year 2023")
  }

  # Validate year range
  if (parsed_args$year < 2016 || parsed_args$year > 2023) {
    stop(sprintf("Invalid year: %d. Must be 2016-2023.", parsed_args$year))
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
# Validation Report Generator
# ============================================================================

#' Print validation report
#'
#' @param validation Validation results from validate_nsch_data()
print_validation_report <- function(validation) {
  cat(strrep("=", 70), "\n")
  cat("NSCH DATA VALIDATION REPORT\n")
  cat(strrep("=", 70), "\n\n")

  cat("OVERALL SUMMARY\n")
  cat(strrep("-", 70), "\n")
  cat(sprintf("Status: %s\n", if (validation$all_passed) "PASS" else "FAIL"))
  cat(sprintf("Checks Passed: %d/%d\n", validation$passed_count, validation$total_count))
  cat(sprintf("Summary: %s\n\n", validation$summary))

  cat("CHECK DETAILS\n")
  cat(strrep("-", 70), "\n")

  for (check_name in names(validation$checks)) {
    check <- validation$checks[[check_name]]
    status_symbol <- if (check$passed) "✓" else "✗"
    status_text <- if (check$passed) "PASS" else "FAIL"

    cat(sprintf("%s [%s] %s: %s\n",
                status_symbol,
                status_text,
                check_name,
                check$message))
  }

  cat("\n", strrep("=", 70), "\n")
}


# ============================================================================
# Main Pipeline Function
# ============================================================================

main <- function() {

  # Start pipeline
  start_time <- Sys.time()

  print_section("NSCH DATA PIPELINE - R ORCHESTRATION")
  message(sprintf("Started: %s\n", start_time))

  # Parse arguments
  args <- parse_args()

  year <- args$year
  verbose <- args$verbose

  message(sprintf("Year: %d", year))
  message(sprintf("Verbose: %s\n", verbose))

  total_steps <- 7
  current_step <- 0

  tryCatch({

    # ========================================================================
    # Step 1: Source R Modules
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Source R Modules")

    source("R/load/nsch/load_nsch_data.R")
    message("  ✓ Sourced: R/load/nsch/load_nsch_data.R")

    source("R/utils/nsch/validate_nsch_raw.R")
    message("  ✓ Sourced: R/utils/nsch/validate_nsch_raw.R")

    print_success("R modules loaded")


    # ========================================================================
    # Step 2: Load Raw Feather Data
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Load Raw Feather Data")

    # Load data using our loading function
    data <- load_nsch_year(year)

    message(sprintf("  Records: %s", format(nrow(data), big.mark = ",")))
    message(sprintf("  Variables: %s", ncol(data)))

    print_success("Raw data loaded successfully")


    # ========================================================================
    # Step 3: Load Metadata
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Load Metadata")

    # Load metadata JSON
    metadata <- load_nsch_metadata(year)

    message(sprintf("  File: %s", metadata$file_name))
    message(sprintf("  Records: %s", format(metadata$record_count, big.mark = ",")))
    message(sprintf("  Variables: %d", metadata$variable_count))
    message(sprintf("  Variables with value labels: %d",
                    length(metadata$value_labels)))

    print_success("Metadata loaded successfully")


    # ========================================================================
    # Step 4: Validate Data Quality
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Validate Data Quality")

    # Run comprehensive validation (7 checks)
    validation <- validate_nsch_data(
      data = data,
      metadata = metadata
    )

    if (validation$all_passed) {
      print_success("All validation checks passed")
    } else {
      message(sprintf(
        "⚠ WARNING: %d of %d validation checks failed",
        validation$total_count - validation$passed_count,
        validation$total_count
      ))
      message("See validation report for details")
    }


    # ========================================================================
    # Step 5: Write Validation Report
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Write Validation Report")

    # Create output directory (should already exist, but ensure)
    output_dir <- file.path("data", "nsch", year)
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

    # Write validation report to file
    report_path <- file.path(output_dir, "validation_report.txt")

    sink(report_path)
    print_validation_report(validation)
    sink()

    message(sprintf("  Report written to: %s", report_path))
    print_success("Validation report saved")


    # ========================================================================
    # Step 6: Write Processed Data
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Write Processed Data")

    # Note: "Processed" data is identical to raw data at this stage
    # (no transformations applied). This step validates and standardizes output.

    processed_path <- file.path(output_dir, "processed.feather")

    # Write to Feather format using arrow package
    arrow::write_feather(data, processed_path)

    # Get file size
    file_size_mb <- file.size(processed_path) / (1024^2)

    message(sprintf("  File: %s", processed_path))
    message(sprintf("  Size: %.2f MB", file_size_mb))
    message(sprintf("  Records: %s", format(nrow(data), big.mark = ",")))
    message(sprintf("  Variables: %s", ncol(data)))

    print_success("Processed data written")


    # ========================================================================
    # Step 7: Pipeline Summary
    # ========================================================================
    current_step <- current_step + 1
    print_step(current_step, total_steps, "Pipeline Summary")

    end_time <- Sys.time()
    elapsed <- difftime(end_time, start_time, units = "secs")

    message(sprintf("Year: %d", year))
    message(sprintf("Records Processed: %s", format(nrow(data), big.mark = ",")))
    message(sprintf("Variables: %s", ncol(data)))
    message(sprintf("Validation Status: %s", if (validation$all_passed) "PASS" else "FAIL"))
    message(sprintf("Output File: %s", processed_path))
    message(sprintf("Validation Report: %s", report_path))
    message(sprintf("Elapsed Time: %.2f seconds", elapsed))


    # ========================================================================
    # Final Status
    # ========================================================================
    message("\n")
    print_section("PIPELINE COMPLETE", "=")

    if (validation$all_passed) {
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

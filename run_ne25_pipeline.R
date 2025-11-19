#!/usr/bin/env Rscript

#' Main Execution Script for NE25 Kidsights Pipeline
#'
#' Simple script to run the complete end-to-end NE25 data pipeline
#' from REDCap extraction to DuckDB storage in local repository.
#'
#' Usage:
#'   source("run_ne25_pipeline.R")
#'   # or from command line: Rscript run_ne25_pipeline.R

# Set working directory to script location if running from command line
if (!interactive()) {
  script_dir <- dirname(normalizePath(commandArgs(trailingOnly = FALSE)[4]))
  setwd(script_dir)
}

# Clear environment and ensure dependencies
rm(list = ls())

# Dependency Management: Check and install required packages
source("R/utils/dependency_manager.R")
ensure_database_dependencies(auto_install = TRUE, quiet = FALSE)

# Load environment configuration for Python paths
source("R/utils/environment_config.R")

# Load safe join utilities
source("R/utils/safe_joins.R")

cat("===========================================\n")
cat("   Kidsights NE25 Data Pipeline\n")
cat("===========================================\n")
cat(paste("Start Time:", Sys.time()), "\n")
cat(paste("Working Directory:", getwd()), "\n")
cat("\n")

# Source the main pipeline orchestration
tryCatch({
  source("pipelines/orchestration/ne25_pipeline.R")
  cat("✅ Pipeline functions loaded successfully\n")
}, error = function(e) {
  cat("❌ Failed to load pipeline functions:\n")
  cat(paste("Error:", e$message), "\n")
  stop("Pipeline setup failed")
})

# Run the pipeline
cat("\n🚀 Starting NE25 pipeline execution...\n\n")

pipeline_result <- tryCatch({

  # Execute the main pipeline
  run_ne25_pipeline(
    config_path = "config/sources/ne25.yaml",
    pipeline_type = "full",
    overwrite_existing = FALSE
  )

}, error = function(e) {
  cat("❌ Pipeline execution failed:\n")
  cat(paste("Error:", e$message), "\n")
  list(success = FALSE, errors = list(main_error = e$message))
})

# Display results
cat("\n===========================================\n")
cat("   Pipeline Execution Summary\n")
cat("===========================================\n")

if (pipeline_result$success) {
  cat("✅ STATUS: SUCCESS\n\n")

  if (!is.null(pipeline_result$metrics)) {
    metrics <- pipeline_result$metrics
    cat("📊 EXTRACTION METRICS:\n")
    cat(paste("  • Projects processed:", length(metrics$projects_successful)), "\n")
    cat(paste("  • Total records extracted:", metrics$total_records_extracted), "\n")
    cat(paste("  • Extraction time:", round(metrics$extraction_duration, 1), "seconds"), "\n")

    cat("\n🎯 PROCESSING METRICS:\n")
    cat(paste("  • Records processed:", metrics$records_processed), "\n")
    cat(paste("  • Eligible participants:", metrics$records_eligible), "\n")
    cat(paste("  • Authentic participants:", metrics$records_authentic), "\n")
    cat(paste("  • Included participants:", metrics$records_included), "\n")
    cat(paste("  • Processing time:", round(metrics$processing_duration, 1), "seconds"), "\n")

    cat("\n⏱️ TOTAL EXECUTION TIME:", round(metrics$total_duration, 1), "seconds\n")
  }

  if (!is.null(pipeline_result$summary_stats)) {
    stats <- pipeline_result$summary_stats
    cat("\n💾 DATABASE SUMMARY:\n")
    cat(paste("  • Raw data records:", stats$ne25_raw), "\n")
    cat(paste("  • Eligibility records:", stats$ne25_eligibility), "\n")
    cat(paste("  • Harmonized records:", stats$ne25_harmonized), "\n")
  }

  cat("\n📁 DATABASE LOCATION:\n")
  cat("  data/duckdb/kidsights_local.duckdb (local repository database)\n")

  cat("\n🎉 Pipeline completed successfully!\n")
  cat("You can now access your data in DuckDB for analysis.\n")

} else {
  cat("❌ STATUS: FAILED\n\n")

  if (!is.null(pipeline_result$errors)) {
    cat("🚨 ERRORS:\n")
    for (error_name in names(pipeline_result$errors)) {
      cat(paste("  •", error_name, ":", pipeline_result$errors[[error_name]]), "\n")
    }
  }

  cat("\n💡 TROUBLESHOOTING TIPS:\n")
  cat("  1. Check your internet connection\n")
  cat("  2. Verify REDCap API tokens are valid\n")
  cat("  3. Ensure OneDrive folder exists and is accessible\n")
  cat("  4. Run setup script: source('scripts/setup/init_ne25_pipeline.R')\n")
  cat("  5. Check the pipeline log for detailed error messages\n")
}

cat("\n===========================================\n")
cat(paste("End Time:", Sys.time()), "\n")
cat("===========================================\n")

# Return result invisibly for programmatic use
invisible(pipeline_result)
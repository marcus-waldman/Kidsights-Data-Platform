#!/usr/bin/env Rscript
#
# NE25 Validation Report Generator
#
# Purpose: Generate comprehensive markdown report from validation results
#
# Author: Kidsights Data Platform
# Date: September 17, 2025
# Version: 1.0

# ==============================================================================
# PACKAGE INSTALLATION AND LOADING
# ==============================================================================

required_packages <- c("jsonlite", "dplyr", "tibble", "stringr", "purrr", "glue", "knitr")

install_and_load <- function(packages) {
  for (pkg in packages) {
    if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
      cat("Installing package:", pkg, "\n")
      install.packages(pkg, dependencies = TRUE, repos = "https://cran.rstudio.com/")
      library(pkg, character.only = TRUE)
      cat("Successfully installed and loaded:", pkg, "\n")
    } else {
      cat("Package already available:", pkg, "\n")
    }
  }
}

install_and_load(required_packages)

# ==============================================================================
# REPORT GENERATION
# ==============================================================================

generate_ne25_validation_report <- function(validation_results_path = "scripts/codebook/ne25_validation_results.rds",
                                           output_path = "docs/codebook/ne25_validation_report.md") {

  # Load validation results
  if (!file.exists(validation_results_path)) {
    stop(glue("Validation results not found at: {validation_results_path}"))
  }

  results <- readRDS(validation_results_path)

  # Create output directory if needed
  output_dir <- dirname(output_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  # Generate report content
  report_lines <- c(
    "# NE25 Codebook Validation Report",
    "",
    glue("**Generated:** {Sys.time()}"),
    glue("**Script:** validate_ne25_codebook.R"),
    "",
    "## Executive Summary",
    "",
    glue("This report validates that all items marked as NE25 in the codebook actually exist in the NE25 dictionary (actual REDCap data collection)."),
    "",
    "### Key Findings",
    "",
    glue("- **Total NE25 Items:** {results$summary$total_items}"),
    glue("- **Items Found in Data:** {results$summary$found_items} ({round(results$summary$found_items/results$summary$total_items*100, 1)}%)"),
    glue("- **Items Missing from Data:** {results$summary$missing_items} ({round(results$summary$missing_items/results$summary$total_items*100, 1)}%)"),
    glue("- **Items with NE25 IRT Parameters:** {results$summary$items_with_irt} ({round(results$summary$items_with_irt/results$summary$total_items*100, 1)}%)"),
    glue("- **Items with NE22 IRT Parameters:** {results$summary$items_with_ne22_irt} ({round(results$summary$items_with_ne22_irt/results$summary$total_items*100, 1)}%)"),
    glue("- **Items with NE25 Response Options:** {results$summary$items_with_response} ({round(results$summary$items_with_response/results$summary$total_items*100, 1)}%)"),
    "",
    "### Status",
    if (results$summary$missing_items == 0) {
      c("✅ **VALIDATION PASSED:** All codebook items exist in actual data collection",
        "",
        "No phantom items detected. The codebook accurately reflects NE25 data collection.")
    } else {
      c("⚠️ **VALIDATION ISSUES:** Some codebook items not found in data",
        "",
        glue("{results$summary$missing_items} items claim NE25 participation but are not present in the actual REDCap data."))
    },
    "",
    "## Detailed Analysis",
    "",
    "### IRT Parameter Status",
    "",
    glue("- **Empty NE25 IRT blocks:** {results$summary$total_items - results$summary$items_with_irt} items"),
    glue("- **Available NE22 IRT data:** {results$summary$items_with_ne22_irt} items could potentially have parameters copied"),
    "",
    "### Response Options Coverage",
    "",
    glue("- **Items with NE25 response mappings:** {results$summary$items_with_response}"),
    glue("- **Items missing response mappings:** {results$summary$total_items - results$summary$items_with_response}"),
    ""
  )

  # Add missing items section if any
  if (results$summary$missing_items > 0) {
    report_lines <- c(report_lines,
      "## Missing Items (Not Found in NE25 Data)",
      "",
      "The following items are marked as NE25 in the codebook but do not exist in the actual REDCap data:",
      ""
    )

    missing_items <- results$validation_results[sapply(results$validation_results, function(x) !x$field_exists)]

    for (item_id in names(missing_items)) {
      item <- missing_items[[item_id]]
      report_lines <- c(report_lines,
        glue("### {item_id}"),
        glue("- **Field:** {item$ne25_field}"),
        glue("- **Question:** {substr(item$question, 1, 200)}..."),
        glue("- **Status:** MISSING FROM DATA"),
        ""
      )
    }
  }

  # Add IRT parameter analysis
  report_lines <- c(report_lines,
    "## IRT Parameter Analysis",
    "",
    "### Items with NE22 but not NE25 IRT Parameters",
    "",
    "These items have psychometric parameters from NE22 that could potentially be copied:",
    ""
  )

  # Find items with NE22 but not NE25 IRT
  irt_candidates <- results$validation_results[sapply(results$validation_results, function(x) x$has_ne22_irt && !x$has_ne25_irt)]

  if (length(irt_candidates) > 0) {
    report_lines <- c(report_lines,
      glue("**Count:** {length(irt_candidates)} items"),
      ""
    )

    # Show first 10 as examples
    for (item_id in names(irt_candidates)[1:min(10, length(irt_candidates))]) {
      item <- irt_candidates[[item_id]]
      report_lines <- c(report_lines,
        glue("- {item_id} ({item$ne25_field})")
      )
    }

    if (length(irt_candidates) > 10) {
      report_lines <- c(report_lines,
        glue("- ... and {length(irt_candidates) - 10} more items")
      )
    }
  } else {
    report_lines <- c(report_lines, "No items found with this pattern.")
  }

  # Add recommendations
  report_lines <- c(report_lines,
    "",
    "## Recommendations",
    "",
    if (results$summary$missing_items > 0) {
      c("### 1. Remove Invalid NE25 Assignments",
        "",
        glue("Run `update_ne25_codebook.R` to remove {results$summary$missing_items} invalid NE25 assignments from the codebook."),
        "")
    } else {
      c("### 1. Data Integrity",
        "",
        "✅ No action needed - all NE25 assignments are valid.",
        "")
    },
    "### 2. IRT Parameters",
    "",
    if (results$summary$items_with_ne22_irt > results$summary$items_with_irt) {
      glue("Consider copying NE22 IRT parameters to {results$summary$items_with_ne22_irt - results$summary$items_with_irt} NE25 items that currently lack psychometric data.")
    } else {
      "NE25 IRT parameter coverage is complete."
    },
    "",
    "### 3. Response Options",
    "",
    if (results$summary$items_with_response < results$summary$total_items) {
      glue("Review {results$summary$total_items - results$summary$items_with_response} items missing NE25 response option mappings.")
    } else {
      "Response option coverage is complete."
    },
    "",
    "## Technical Details",
    "",
    glue("- **Codebook Version:** {results$ne25_items[[1]]$studies %||% 'Unknown'}"),
    glue("- **Dictionary Fields:** {length(results$dict_fields)} unique fields"),
    glue("- **Validation Date:** {Sys.time()}"),
    glue("- **Validation Script:** validate_ne25_codebook.R v1.0"),
    ""
  )

  # Write report
  writeLines(report_lines, output_path)
  cat(glue("✓ Validation report generated: {output_path}\n"))

  return(output_path)
}

# ==============================================================================
# SCRIPT EXECUTION
# ==============================================================================

if (sys.nframe() == 0) {
  cat("Generating NE25 validation report...\n\n")

  validation_results_path <- "scripts/codebook/ne25_validation_results.rds"

  if (!file.exists(validation_results_path)) {
    cat("Validation results not found. Running validation first...\n")
    source("scripts/codebook/validate_ne25_codebook.R")
  }

  report_path <- generate_ne25_validation_report()

  cat(glue("\n✓ Report complete: {report_path}\n"))
  cat("You can now view the detailed validation report.\n")
}
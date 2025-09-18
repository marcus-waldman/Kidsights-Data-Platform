#!/usr/bin/env Rscript
#
# NE25 Response Options Fix Script
#
# Purpose: Add missing response_options.ne25 references for PS items
#          to enable proper recoding functionality
#
# Author: Kidsights Data Platform
# Date: September 17, 2025
# Version: 1.0

# ==============================================================================
# PACKAGE INSTALLATION AND LOADING
# ==============================================================================

# Required packages
required_packages <- c("jsonlite", "dplyr", "tibble", "stringr", "purrr", "glue", "lubridate")

# Function to install and load packages
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

# Install and load all required packages
cat("=== Installing and loading required packages ===\n")
install_and_load(required_packages)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Create backup of codebook with timestamp
#' @param codebook_path Path to original codebook
#' @param backup_dir Directory for backup
create_backup <- function(codebook_path, backup_dir = "codebook/data") {
  if (!dir.exists(backup_dir)) {
    dir.create(backup_dir, recursive = TRUE)
  }

  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  backup_filename <- glue("codebook_pre_response_fix_{timestamp}.json")
  backup_path <- file.path(backup_dir, backup_filename)

  file.copy(codebook_path, backup_path)
  cat(glue("✓ Backup created: {backup_path}\n"))
  return(backup_path)
}

#' Add response_options.ne25 to PS items
#' @param item_data Single item data from codebook
#' @param item_id Item identifier for logging
add_ps_response_options <- function(item_data, item_id) {
  modified <- FALSE

  # Only process PS items that have NE25 in studies list
  if (str_starts(item_id, "PS") && "NE25" %in% (item_data$studies %||% character(0))) {

    # Initialize content structure if needed
    if (!"content" %in% names(item_data)) {
      item_data$content <- list()
    }

    # Initialize response_options if needed
    if (!"response_options" %in% names(item_data$content)) {
      item_data$content$response_options <- list()
    }

    # Add ne25 response option if missing
    if (!"ne25" %in% names(item_data$content$response_options)) {
      item_data$content$response_options$ne25 <- "ps_frequency"
      modified <- TRUE
      cat(glue("  ✓ {item_id}: Added ne25 response_options = 'ps_frequency'\n"))
    } else {
      cat(glue("  - {item_id}: Already has ne25 response_options\n"))
    }
  }

  return(list(item_data = item_data, modified = modified))
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

#' Fix missing response options for PS items in NE25
#' @param codebook_path Path to codebook.json
fix_ne25_response_options <- function(codebook_path = "codebook/data/codebook.json") {

  cat("=== NE25 Response Options Fix ===\n\n")

  # Check if file exists
  if (!file.exists(codebook_path)) {
    stop(glue("ERROR: Codebook not found at: {codebook_path}"))
  }

  # Create backup
  backup_path <- create_backup(codebook_path)

  # Load codebook
  cat("Loading codebook...\n")
  codebook_data <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Update metadata
  original_version <- codebook_data$metadata$version %||% "unknown"
  codebook_data$metadata$version <- "2.7.1"
  codebook_data$metadata$last_response_fix <- as.character(Sys.time())
  codebook_data$metadata$previous_version <- original_version
  codebook_data$metadata$response_fix_backup <- basename(backup_path)

  # Initialize counters
  ps_items_checked <- 0
  ps_items_modified <- 0
  total_items <- length(codebook_data$items)

  cat(glue("\nProcessing {total_items} items...\n"))

  # Process each item
  for (item_id in names(codebook_data$items)) {
    if (str_starts(item_id, "PS")) {
      ps_items_checked <- ps_items_checked + 1

      # Check if item has NE25
      if ("NE25" %in% (codebook_data$items[[item_id]]$studies %||% character(0))) {
        update_result <- add_ps_response_options(codebook_data$items[[item_id]], item_id)
        codebook_data$items[[item_id]] <- update_result$item_data

        if (update_result$modified) {
          ps_items_modified <- ps_items_modified + 1
        }
      }
    }
  }

  # Generate summary
  cat("\n=== FIX SUMMARY ===\n")
  cat(glue("Total items processed: {total_items}\n"))
  cat(glue("PS items checked: {ps_items_checked}\n"))
  cat(glue("PS items modified: {ps_items_modified}\n"))
  cat(glue("Backup created: {basename(backup_path)}\n"))
  cat(glue("Version: {original_version} -> 2.7.1\n"))

  # Save updated codebook
  cat("\nSaving updated codebook...\n")

  # Write with proper formatting
  updated_json <- jsonlite::toJSON(codebook_data,
                                  auto_unbox = TRUE,
                                  pretty = TRUE,
                                  null = "null")

  writeLines(updated_json, codebook_path)
  cat(glue("✓ Updated codebook saved to: {codebook_path}\n"))

  # Create fix log
  log_path <- "scripts/codebook/response_fix_log.txt"
  log_content <- c(
    glue("NE25 Response Options Fix Log"),
    glue("Date: {Sys.time()}"),
    glue("Script: fix_ne25_response_options.R"),
    "",
    glue("SUMMARY:"),
    glue("- Total items: {total_items}"),
    glue("- PS items checked: {ps_items_checked}"),
    glue("- PS items modified: {ps_items_modified}"),
    glue("- Backup: {backup_path}"),
    glue("- Version: {original_version} -> 2.7.1"),
    "",
    glue("CHANGES MADE:"),
    glue("- Added response_options.ne25 = 'ps_frequency' to PS items"),
    glue("- Ensures compatibility with recoding functions"),
    glue("- Links PS items to existing ps_frequency response set")
  )

  writeLines(log_content, log_path)
  cat(glue("✓ Fix log saved to: {log_path}\n"))

  # Validation check
  cat("\nValidating fix...\n")
  updated_codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  ps_with_ne25_response <- 0
  for (item_id in names(updated_codebook$items)) {
    if (str_starts(item_id, "PS") && "NE25" %in% (updated_codebook$items[[item_id]]$studies %||% character(0))) {
      if ("content" %in% names(updated_codebook$items[[item_id]]) &&
          "response_options" %in% names(updated_codebook$items[[item_id]]$content) &&
          "ne25" %in% names(updated_codebook$items[[item_id]]$content$response_options)) {
        ps_with_ne25_response <- ps_with_ne25_response + 1
      }
    }
  }

  cat(glue("✓ Validation: {ps_with_ne25_response} PS items now have ne25 response_options\n"))

  return(list(
    items_modified = ps_items_modified,
    backup_path = backup_path,
    validation_count = ps_with_ne25_response
  ))
}

# ==============================================================================
# SCRIPT EXECUTION
# ==============================================================================

# Check if this script is being run directly
if (sys.nframe() == 0) {
  # Define file path
  codebook_path <- "codebook/data/codebook.json"

  cat("Starting NE25 response options fix...\n\n")

  # Run fix
  fix_results <- fix_ne25_response_options(codebook_path)

  cat("\n=== FIX COMPLETE ===\n")
  cat(glue("Modified {fix_results$items_modified} PS items\n"))
  cat(glue("Validation: {fix_results$validation_count} PS items have response options\n"))
  cat("Codebook updated with version 2.7.1\n")
  cat("Ready for recoding operations!\n\n")
}
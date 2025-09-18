#!/usr/bin/env Rscript
#
# NE25 Codebook Update Script
#
# Purpose: Update codebook.json based on validation results from validate_ne25_codebook.R
#          Removes invalid NE25 assignments and cleans up dependent fields
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
  backup_filename <- glue("codebook_pre_ne25_audit_{timestamp}.json")
  backup_path <- file.path(backup_dir, backup_filename)

  file.copy(codebook_path, backup_path)
  cat(glue("✓ Backup created: {backup_path}\n"))
  return(backup_path)
}

#' Remove NE25 from studies list and clean up dependent fields
#' @param item_data Single item data from codebook
#' @param item_id Item identifier for logging
remove_ne25_from_item <- function(item_data, item_id) {
  modified <- FALSE
  changes <- character(0)

  # Remove NE25 from studies list
  if ("studies" %in% names(item_data) && "NE25" %in% item_data$studies) {
    item_data$studies <- item_data$studies[item_data$studies != "NE25"]
    modified <- TRUE
    changes <- c(changes, "removed from studies list")
  }

  # Remove NE25 lexicon entry
  if ("lexicons" %in% names(item_data) && "ne25" %in% names(item_data$lexicons)) {
    item_data$lexicons$ne25 <- NULL
    modified <- TRUE
    changes <- c(changes, "removed ne25 lexicon")
  }

  # Remove NE25 IRT parameters
  if ("psychometric" %in% names(item_data) &&
      "irt_parameters" %in% names(item_data$psychometric) &&
      "NE25" %in% names(item_data$psychometric$irt_parameters)) {
    item_data$psychometric$irt_parameters$NE25 <- NULL
    modified <- TRUE
    changes <- c(changes, "removed NE25 IRT parameters")
  }

  # Remove NE25 response options
  if ("content" %in% names(item_data) &&
      "response_options" %in% names(item_data$content) &&
      "ne25" %in% names(item_data$content$response_options)) {
    item_data$content$response_options$ne25 <- NULL
    modified <- TRUE
    changes <- c(changes, "removed ne25 response options")
  }

  # Update domain study assignments (remove NE25 from domain studies)
  if ("domains" %in% names(item_data)) {
    for (domain_name in names(item_data$domains)) {
      domain <- item_data$domains[[domain_name]]
      if ("studies" %in% names(domain) && "NE25" %in% domain$studies) {
        domain$studies <- domain$studies[domain$studies != "NE25"]
        item_data$domains[[domain_name]]$studies <- domain$studies
        modified <- TRUE
        changes <- c(changes, glue("removed NE25 from {domain_name} domain"))
      }
    }
  }

  if (modified) {
    cat(glue("  ✓ {item_id}: {paste(changes, collapse = ', ')}\n"))
  }

  return(list(item_data = item_data, modified = modified, changes = changes))
}

#' Copy NE22 IRT parameters to NE25 (optional function)
#' @param item_data Single item data from codebook
#' @param item_id Item identifier for logging
copy_ne22_to_ne25_irt <- function(item_data, item_id) {
  if ("psychometric" %in% names(item_data) &&
      "irt_parameters" %in% names(item_data$psychometric)) {

    irt_params <- item_data$psychometric$irt_parameters

    # Check if NE22 has parameters and NE25 doesn't
    has_ne22 <- "NE22" %in% names(irt_params) &&
                (length(irt_params$NE22$loadings %||% numeric(0)) > 0 ||
                 length(irt_params$NE22$thresholds %||% numeric(0)) > 0)

    has_ne25 <- "NE25" %in% names(irt_params) &&
                (length(irt_params$NE25$loadings %||% numeric(0)) > 0 ||
                 length(irt_params$NE25$thresholds %||% numeric(0)) > 0)

    if (has_ne22 && !has_ne25) {
      # Copy NE22 parameters to NE25
      ne22_params <- irt_params$NE22

      # Add note about parameter source
      ne25_params <- ne22_params
      ne25_params$notes <- "Parameters copied from NE22 study"
      ne25_params$parameter_source <- "NE22"
      ne25_params$copied_date <- as.character(Sys.Date())

      item_data$psychometric$irt_parameters$NE25 <- ne25_params

      cat(glue("  ✓ {item_id}: Copied NE22 IRT parameters to NE25\n"))
      return(list(item_data = item_data, modified = TRUE))
    }
  }

  return(list(item_data = item_data, modified = FALSE))
}

# ==============================================================================
# MAIN UPDATE FUNCTION
# ==============================================================================

#' Update codebook based on validation results
#' @param codebook_path Path to codebook.json
#' @param validation_results_path Path to validation results RDS file
#' @param copy_irt_params Whether to copy NE22 IRT parameters to NE25
update_ne25_codebook <- function(codebook_path,
                                validation_results_path = "scripts/codebook/ne25_validation_results.rds",
                                copy_irt_params = FALSE) {

  cat("=== NE25 Codebook Update ===\n\n")

  # Load validation results
  if (!file.exists(validation_results_path)) {
    stop(glue("ERROR: Validation results not found at: {validation_results_path}\n"))
    cat("Please run validate_ne25_codebook.R first.\n")
  }

  validation_results <- readRDS(validation_results_path)
  cat(glue("✓ Loaded validation results from: {validation_results_path}\n"))

  # Create backup
  backup_path <- create_backup(codebook_path)

  # Load codebook
  cat("Loading codebook...\n")
  codebook_data <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Update metadata
  original_version <- codebook_data$metadata$version %||% "unknown"
  codebook_data$metadata$version <- "2.7"
  codebook_data$metadata$last_ne25_audit <- as.character(Sys.time())
  codebook_data$metadata$previous_version <- original_version
  codebook_data$metadata$audit_backup <- basename(backup_path)

  # Initialize counters
  total_items <- length(validation_results$validation_results)
  items_modified <- 0
  items_removed <- 0
  irt_params_copied <- 0

  cat(glue("\nProcessing {total_items} NE25 items...\n"))

  # Process each validation result
  for (item_id in names(validation_results$validation_results)) {
    result <- validation_results$validation_results[[item_id]]

    # Only process items that were marked as invalid (not found in dictionary)
    if (!result$field_exists) {
      cat(glue("Processing invalid item: {item_id} (field: {result$ne25_field})\n"))

      if (item_id %in% names(codebook_data$items)) {
        # Remove NE25 from this item
        update_result <- remove_ne25_from_item(codebook_data$items[[item_id]], item_id)
        codebook_data$items[[item_id]] <- update_result$item_data

        if (update_result$modified) {
          items_modified <- items_modified + 1

          # Check if item should be completely removed (no studies left)
          remaining_studies <- codebook_data$items[[item_id]]$studies %||% character(0)
          if (length(remaining_studies) == 0) {
            codebook_data$items[[item_id]] <- NULL
            items_removed <- items_removed + 1
            cat(glue("  ⚠️  {item_id}: Removed entirely (no remaining studies)\n"))
          }
        }
      }
    } else if (copy_irt_params && result$field_exists && !result$has_ne25_irt && result$has_ne22_irt) {
      # Optionally copy NE22 parameters to valid NE25 items
      irt_result <- copy_ne22_to_ne25_irt(codebook_data$items[[item_id]], item_id)
      if (irt_result$modified) {
        codebook_data$items[[item_id]] <- irt_result$item_data
        irt_params_copied <- irt_params_copied + 1
      }
    }
  }

  # Generate update summary
  cat("\n=== UPDATE SUMMARY ===\n")
  cat(glue("Total NE25 items processed: {total_items}\n"))
  cat(glue("Items with invalid fields: {validation_results$summary$missing_items}\n"))
  cat(glue("Items modified: {items_modified}\n"))
  cat(glue("Items removed entirely: {items_removed}\n"))
  if (copy_irt_params) {
    cat(glue("IRT parameters copied from NE22: {irt_params_copied}\n"))
  }
  cat(glue("Backup created: {basename(backup_path)}\n"))

  # Save updated codebook
  cat("\nSaving updated codebook...\n")

  # Write with proper formatting
  updated_json <- jsonlite::toJSON(codebook_data,
                                  auto_unbox = TRUE,
                                  pretty = TRUE,
                                  null = "null")

  writeLines(updated_json, codebook_path)
  cat(glue("✓ Updated codebook saved to: {codebook_path}\n"))

  # Create update log
  log_path <- "scripts/codebook/ne25_update_log.txt"
  log_content <- c(
    glue("NE25 Codebook Update Log"),
    glue("Date: {Sys.time()}"),
    glue("Script: update_ne25_codebook.R"),
    "",
    glue("SUMMARY:"),
    glue("- Total items processed: {total_items}"),
    glue("- Items modified: {items_modified}"),
    glue("- Items removed: {items_removed}"),
    if (copy_irt_params) glue("- IRT parameters copied: {irt_params_copied}") else NULL,
    glue("- Backup: {backup_path}"),
    glue("- Version: {original_version} -> 2.7"),
    "",
    glue("VALIDATION RESULTS:"),
    glue("- Items found in dictionary: {validation_results$summary$found_items}"),
    glue("- Items missing from dictionary: {validation_results$summary$missing_items}"),
    glue("- Items with NE25 IRT: {validation_results$summary$items_with_irt}"),
    glue("- Items with NE22 IRT: {validation_results$summary$items_with_ne22_irt}")
  )

  writeLines(log_content, log_path)
  cat(glue("✓ Update log saved to: {log_path}\n"))

  return(list(
    items_modified = items_modified,
    items_removed = items_removed,
    irt_params_copied = irt_params_copied,
    backup_path = backup_path
  ))
}

# ==============================================================================
# SCRIPT EXECUTION
# ==============================================================================

# Check if this script is being run directly
if (sys.nframe() == 0) {
  # Define file paths
  codebook_path <- "codebook/data/codebook.json"
  validation_results_path <- "scripts/codebook/ne25_validation_results.rds"

  # Check if validation results exist
  if (!file.exists(validation_results_path)) {
    cat("ERROR: Validation results not found. Running validation first...\n\n")
    source("scripts/codebook/validate_ne25_codebook.R")
  }

  # Ask user about copying IRT parameters
  cat("\nWould you like to copy NE22 IRT parameters to NE25 items? (y/n): ")
  copy_irt <- tolower(readline()) %in% c("y", "yes", "1", "true")

  if (copy_irt) {
    cat("✓ Will copy NE22 IRT parameters to NE25 where applicable\n")
  } else {
    cat("✓ Will not copy IRT parameters\n")
  }

  cat("\n")

  # Run update
  cat("Starting NE25 codebook update...\n\n")
  update_results <- update_ne25_codebook(codebook_path,
                                       validation_results_path,
                                       copy_irt_params = copy_irt)

  cat("\n=== UPDATE COMPLETE ===\n")
  cat("Updated codebook saved with version 2.7\n")
  cat("Backup and logs created in scripts/codebook/\n")
  cat("Ready for use!\n\n")
}
#!/usr/bin/env Rscript
#
# NE25 Codebook Validation Script
#
# Purpose: Validate that all items marked as NE25 in codebook.json actually
#          exist in the ne25_dictionary.json (actual REDCap data)
#
# Author: Kidsights Data Platform
# Date: September 17, 2025
# Version: 1.0

# ==============================================================================
# PACKAGE INSTALLATION AND LOADING
# ==============================================================================

# Required packages
required_packages <- c("jsonlite", "dplyr", "tibble", "stringr", "purrr", "glue")

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

#' Load and validate JSON file
#' @param file_path Path to JSON file
#' @param description Description for error messages
load_json_safely <- function(file_path, description) {
  if (!file.exists(file_path)) {
    stop(glue("ERROR: {description} not found at: {file_path}"))
  }

  tryCatch({
    data <- jsonlite::fromJSON(file_path, simplifyVector = FALSE)
    cat(glue("✓ Successfully loaded {description}\n"))
    return(data)
  }, error = function(e) {
    stop(glue("ERROR: Failed to parse {description}: {e$message}"))
  })
}

#' Extract all unique field names from NE25 dictionary
#' @param dict_data NE25 dictionary data
extract_dict_fields <- function(dict_data) {
  if (!"raw_variables" %in% names(dict_data) ||
      !"data" %in% names(dict_data$raw_variables)) {
    stop("ERROR: Invalid dictionary structure - missing raw_variables$data")
  }

  # Extract field names and convert to lowercase for case-insensitive comparison
  field_names <- purrr::map_chr(dict_data$raw_variables$data, ~ .x$field_name)
  unique_fields <- unique(tolower(field_names))

  cat(glue("✓ Extracted {length(unique_fields)} unique fields from dictionary\n"))
  return(unique_fields)
}

#' Extract NE25 items from codebook
#' @param codebook_data Codebook data
extract_ne25_items <- function(codebook_data) {
  if (!"items" %in% names(codebook_data)) {
    stop("ERROR: Invalid codebook structure - missing items")
  }

  ne25_items <- list()

  for (item_id in names(codebook_data$items)) {
    item_data <- codebook_data$items[[item_id]]

    # Check if NE25 is in studies list
    if ("NE25" %in% (item_data$studies %||% character(0))) {
      # Extract NE25 field mapping
      ne25_field <- NULL
      if ("lexicons" %in% names(item_data) &&
          "ne25" %in% names(item_data$lexicons)) {
        ne25_field <- item_data$lexicons$ne25
      }

      # Extract question text
      question <- "N/A"
      if ("content" %in% names(item_data) &&
          "stems" %in% names(item_data$content)) {
        stems <- item_data$content$stems
        question <- stems$combined %||% stems$ne25 %||% "N/A"
        if (nchar(question) > 100) {
          question <- paste0(substr(question, 1, 100), "...")
        }
      }

      # Check IRT parameters
      has_ne25_irt <- FALSE
      has_ne22_irt <- FALSE

      if ("psychometric" %in% names(item_data) &&
          "irt_parameters" %in% names(item_data$psychometric)) {
        irt_params <- item_data$psychometric$irt_parameters

        # Check NE25 IRT parameters
        if ("NE25" %in% names(irt_params)) {
          ne25_irt <- irt_params$NE25
          has_ne25_irt <- length(ne25_irt$loadings %||% numeric(0)) > 0 ||
                          length(ne25_irt$thresholds %||% numeric(0)) > 0
        }

        # Check NE22 IRT parameters
        if ("NE22" %in% names(irt_params)) {
          ne22_irt <- irt_params$NE22
          has_ne22_irt <- length(ne22_irt$loadings %||% numeric(0)) > 0 ||
                         length(ne22_irt$thresholds %||% numeric(0)) > 0
        }
      }

      # Check response options
      has_ne25_response <- FALSE
      if ("content" %in% names(item_data) &&
          "response_options" %in% names(item_data$content)) {
        has_ne25_response <- "ne25" %in% names(item_data$content$response_options)
      }

      ne25_items[[item_id]] <- list(
        item_id = item_id,
        ne25_field = ne25_field,
        question = question,
        studies = item_data$studies %||% character(0),
        has_ne25_irt = has_ne25_irt,
        has_ne22_irt = has_ne22_irt,
        has_ne25_response = has_ne25_response
      )
    }
  }

  cat(glue("✓ Found {length(ne25_items)} items marked as NE25 in codebook\n"))
  return(ne25_items)
}

# ==============================================================================
# MAIN VALIDATION FUNCTION
# ==============================================================================

#' Perform comprehensive validation of NE25 codebook items
#' @param codebook_path Path to codebook.json
#' @param dictionary_path Path to ne25_dictionary.json
validate_ne25_codebook <- function(codebook_path, dictionary_path) {

  cat("=== NE25 Codebook Validation ===\n\n")

  # Load data files
  cat("Loading data files...\n")
  codebook_data <- load_json_safely(codebook_path, "Codebook")
  dictionary_data <- load_json_safely(dictionary_path, "NE25 Dictionary")

  # Extract fields and items
  cat("\nExtracting data structures...\n")
  dict_fields <- extract_dict_fields(dictionary_data)
  ne25_items <- extract_ne25_items(codebook_data)

  # Perform validation
  cat("\nPerforming validation...\n")

  validation_results <- list()
  found_items <- 0
  missing_items <- 0
  items_with_irt <- 0
  items_with_ne22_irt <- 0
  items_with_response <- 0

  for (item_id in names(ne25_items)) {
    item <- ne25_items[[item_id]]

    # Check if field exists in dictionary
    field_exists <- FALSE
    if (!is.null(item$ne25_field)) {
      field_exists <- tolower(item$ne25_field) %in% dict_fields
    }

    if (field_exists) {
      found_items <- found_items + 1
    } else {
      missing_items <- missing_items + 1
    }

    # Count IRT and response options
    if (item$has_ne25_irt) items_with_irt <- items_with_irt + 1
    if (item$has_ne22_irt) items_with_ne22_irt <- items_with_ne22_irt + 1
    if (item$has_ne25_response) items_with_response <- items_with_response + 1

    # Store validation result
    validation_results[[item_id]] <- list(
      item_id = item_id,
      ne25_field = item$ne25_field %||% "MISSING",
      field_exists = field_exists,
      question = item$question,
      has_ne25_irt = item$has_ne25_irt,
      has_ne22_irt = item$has_ne22_irt,
      has_ne25_response = item$has_ne25_response,
      status = if (field_exists) "VALID" else "INVALID"
    )
  }

  # Generate summary
  cat("\n=== VALIDATION SUMMARY ===\n")
  cat(glue("Total NE25 items in codebook: {length(ne25_items)}\n"))
  cat(glue("Items found in dictionary: {found_items} ({round(found_items/length(ne25_items)*100, 1)}%)\n"))
  cat(glue("Items NOT found in dictionary: {missing_items} ({round(missing_items/length(ne25_items)*100, 1)}%)\n"))
  cat(glue("Items with NE25 IRT parameters: {items_with_irt} ({round(items_with_irt/length(ne25_items)*100, 1)}%)\n"))
  cat(glue("Items with NE22 IRT parameters: {items_with_ne22_irt} ({round(items_with_ne22_irt/length(ne25_items)*100, 1)}%)\n"))
  cat(glue("Items with NE25 response options: {items_with_response} ({round(items_with_response/length(ne25_items)*100, 1)}%)\n"))

  # Report issues
  if (missing_items > 0) {
    cat("\n=== MISSING ITEMS (Field not in dictionary) ===\n")
    for (item_id in names(validation_results)) {
      result <- validation_results[[item_id]]
      if (!result$field_exists) {
        cat(glue("❌ {item_id}: {result$ne25_field} - {substr(result$question, 1, 80)}...\n"))
      }
    }
  } else {
    cat("\n✅ All NE25 items found in dictionary - No phantom items detected!\n")
  }

  # Return results for further processing
  return(list(
    summary = list(
      total_items = length(ne25_items),
      found_items = found_items,
      missing_items = missing_items,
      items_with_irt = items_with_irt,
      items_with_ne22_irt = items_with_ne22_irt,
      items_with_response = items_with_response
    ),
    validation_results = validation_results,
    dict_fields = dict_fields,
    ne25_items = ne25_items
  ))
}

# ==============================================================================
# SCRIPT EXECUTION
# ==============================================================================

# Define file paths
codebook_path <- "codebook/data/codebook.json"
dictionary_path <- "docs/data_dictionary/ne25/ne25_dictionary.json"

# Check if files exist
if (!file.exists(codebook_path)) {
  stop(glue("ERROR: Codebook not found at: {codebook_path}"))
}
if (!file.exists(dictionary_path)) {
  stop(glue("ERROR: Dictionary not found at: {dictionary_path}"))
}

# Run validation
cat("Starting NE25 codebook validation...\n\n")
validation_results <- validate_ne25_codebook(codebook_path, dictionary_path)

cat("\n=== VALIDATION COMPLETE ===\n")
cat("Results stored in 'validation_results' variable\n")
cat("Use validation_results$summary for summary statistics\n")
cat("Use validation_results$validation_results for detailed item results\n\n")

# Save results for use by update script
saveRDS(validation_results, "scripts/codebook/ne25_validation_results.rds")
cat("✓ Validation results saved to: scripts/codebook/ne25_validation_results.rds\n")
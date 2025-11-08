#!/usr/bin/env Rscript
#' Codebook Response Sets Extraction for NE25 Audit
#'
#' Extracts expected response values and labels from the codebook system
#' for NE25 study items. This represents what the pipeline expects items
#' to have based on the response_sets definitions.
#'
#' @author Kidsights Data Platform
#' @date 2025-09-18

# Load required packages with explicit namespacing
library(dplyr)
library(stringr)
library(purrr)
library(tibble)

# Source codebook functions
source("R/codebook/load_codebook.R")
source("R/codebook/extract_codebook.R")

#' Extract codebook response sets for NE25 audit
#'
#' @param codebook_path Path to codebook JSON file
#' @param output_file Path to save extracted responses (optional)
#' @return List containing response sets and lexicon mapping
extract_codebook_audit_responses <- function(codebook_path = "codebook/data/codebook.json",
                                           output_file = NULL) {

  cat("=== Codebook Response Sets Extraction Starting ===\n")
  cat("Loading codebook from:", codebook_path, "\n")

  # DEBUG: Load codebook
  if (!file.exists(codebook_path)) {
    stop("ERROR: Codebook file not found: ", codebook_path)
  }

  tryCatch({
    codebook <- load_codebook(codebook_path, validate = FALSE)
    cat("Codebook loaded successfully. Version:", codebook$metadata$version, "\n")
    cat("Total items in codebook:", length(codebook$items), "\n")

  }, error = function(e) {
    stop("ERROR loading codebook: ", e$message)
  })

  # DEBUG: Extract NE25 response sets
  cat("\n=== Extracting NE25 Response Sets ===\n")

  tryCatch({
    ne25_responses <- codebook_extract_response_sets(codebook, study = "NE25")
    cat("Response sets extracted. Total rows:", nrow(ne25_responses), "\n")

    if (nrow(ne25_responses) == 0) {
      warning("WARNING: No response sets found for NE25 study")
      return(NULL)
    }

    # DEBUG: Analyze response sets structure
    cat("Response sets columns:", paste(colnames(ne25_responses), collapse = ", "), "\n")

    response_set_summary <- ne25_responses %>%
      dplyr::count(response_set, sort = TRUE)
    cat("Unique response sets found:", nrow(response_set_summary), "\n")
    print(response_set_summary)

  }, error = function(e) {
    stop("ERROR extracting response sets: ", e$message)
  })

  # DEBUG: Extract lexicon crosswalk for NE25 mapping
  cat("\n=== Extracting Lexicon Crosswalk ===\n")

  tryCatch({
    crosswalk <- codebook_extract_lexicon_crosswalk(codebook)
    cat("Lexicon crosswalk extracted. Total items:", nrow(crosswalk), "\n")

    # Focus on items with NE25 mappings
    ne25_crosswalk <- crosswalk %>%
      dplyr::filter(!is.na(ne25)) %>%
      dplyr::select(lex_equate, equate, ne25)

    cat("Items with NE25 mappings:", nrow(ne25_crosswalk), "\n")

  }, error = function(e) {
    stop("ERROR extracting crosswalk: ", e$message)
  })

  # DEBUG: Join response sets with lexicon mapping
  cat("\n=== Joining Response Sets with Lexicon Mapping ===\n")

  codebook_with_mapping <- ne25_responses %>%
    safe_left_join(ne25_crosswalk, by_vars = "lex_equate") %>%
    dplyr::mutate(
      # Handle case differences - convert to lowercase for matching
      ne25_var = tolower(ne25),
      # Add debugging flags
      has_ne25_mapping = !is.na(ne25),
      has_response_set = !is.na(response_set)
    )

  cat("Total response records with mapping:", nrow(codebook_with_mapping), "\n")

  # DEBUG: Analyze ALL items by response set type
  cat("\n=== Analyzing ALL Items by Response Set Type ===\n")

  # Get comprehensive analysis across all response set types
  all_items_analysis <- codebook_with_mapping %>%
    dplyr::arrange(response_set, ne25_var, value)

  cat("Total item response records found:", nrow(all_items_analysis), "\n")

  # Count unique items across all response sets
  unique_items_total <- all_items_analysis %>%
    dplyr::distinct(lex_equate, ne25_var) %>%
    nrow()

  cat("Unique items with NE25 mappings:", unique_items_total, "\n")

  # Analyze by response set type
  response_set_breakdown <- all_items_analysis %>%
    dplyr::group_by(response_set) %>%
    dplyr::summarise(
      total_records = dplyr::n(),
      unique_items = dplyr::n_distinct(lex_equate),
      unique_values = dplyr::n_distinct(value),
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(total_records))

  cat("\nResponse set breakdown:\n")
  print(response_set_breakdown)

  # Show examples from each response set type
  cat("\n=== Examples from Each Response Set Type ===\n")
  for (rs_type in unique(response_set_breakdown$response_set)) {
    if (!is.na(rs_type)) {
      cat("\n", rs_type, ":\n", sep = "")

      # Get first item of this response set type
      example_item <- all_items_analysis %>%
        dplyr::filter(response_set == rs_type) %>%
        dplyr::slice(1)

      if (nrow(example_item) > 0) {
        cat("- Example item:", example_item$ne25_var[1], "(", example_item$lex_equate[1], ")\n")

        # Show all values for this item
        item_values <- all_items_analysis %>%
          dplyr::filter(lex_equate == example_item$lex_equate[1]) %>%
          dplyr::select(value, label, missing) %>%
          dplyr::arrange(value)

        cat("- Values:", paste(item_values$value, collapse = ", "), "\n")
        cat("- Labels:", paste(item_values$label, collapse = " | "), "\n")
      }
    }
  }

  # DEBUG: Check for items without NE25 mappings
  cat("\n=== Checking for Missing NE25 Mappings ===\n")

  items_without_mapping <- ne25_responses %>%
    safe_left_join(ne25_crosswalk, by_vars = "lex_equate") %>%
    dplyr::filter(is.na(ne25)) %>%
    dplyr::distinct(lex_equate) %>%
    nrow()

  cat("Items with response sets but no NE25 mapping:", items_without_mapping, "\n")

  # DEBUG: Save results if requested
  if (!is.null(output_file)) {
    cat("Saving results to:", output_file, "\n")
    saveRDS(list(
      ne25_responses = ne25_responses,
      crosswalk = ne25_crosswalk,
      responses_with_mapping = codebook_with_mapping,
      all_items_analysis = all_items_analysis,
      response_set_breakdown = response_set_breakdown,
      extraction_timestamp = Sys.time()
    ), output_file)
  }

  # Prepare final result
  result <- list(
    responses = ne25_responses,
    crosswalk = ne25_crosswalk,
    responses_with_mapping = codebook_with_mapping,
    all_items = all_items_analysis,
    response_set_breakdown = response_set_breakdown,
    summary = list(
      total_response_records = nrow(ne25_responses),
      unique_response_sets = length(unique(ne25_responses$response_set)),
      items_with_ne25_mapping = nrow(ne25_crosswalk),
      unique_items_total = unique_items_total,
      total_item_records = nrow(all_items_analysis),
      extraction_time = Sys.time()
    )
  )

  cat("\n=== Codebook Response Sets Extraction Complete ===\n")
  cat("Summary:\n")
  cat("- Total response records:", result$summary$total_response_records, "\n")
  cat("- Unique response sets:", result$summary$unique_response_sets, "\n")
  cat("- Items with NE25 mapping:", result$summary$items_with_ne25_mapping, "\n")
  cat("- Unique items total:", result$summary$unique_items_total, "\n")
  cat("- Total item records:", result$summary$total_item_records, "\n")

  return(result)
}

#' Validate response set structure for all item types
#'
#' Check that items have expected response structure by response set type
#'
#' @param all_items_data All items from codebook extraction
#' @return List with validation results by response set type
validate_response_set_structure <- function(all_items_data) {

  cat("\n=== Validating Response Set Structure for All Items ===\n")

  # Define expected structures for each response set type
  expected_structures <- list(
    "ps_frequency_ne25" = list(
      values = c("0", "1", "2", "9"),
      labels_count = 4,
      description = "PS frequency scale"
    ),
    "standard_binary_ne25" = list(
      values = c("0", "1", "9"),
      labels_count = 3,
      description = "Standard binary with missing"
    ),
    "likert_5_frequency_ne25" = list(
      values = c("1", "2", "3", "4", "5", "9"),
      labels_count = 6,
      description = "5-point Likert with missing"
    ),
    "likert_4_skill_ne25" = list(
      values = c("1", "2", "3", "4", "9"),
      labels_count = 5,
      description = "4-point skill scale with missing"
    )
  )

  validation_results <- list()

  # Validate each response set type
  for (rs_type in names(expected_structures)) {
    cat("\nValidating", rs_type, ":", expected_structures[[rs_type]]$description, "\n")

    # Get items of this response set type
    rs_items <- all_items_data %>%
      dplyr::filter(response_set == rs_type) %>%
      dplyr::distinct(lex_equate)

    cat("Items to validate:", nrow(rs_items), "\n")

    if (nrow(rs_items) > 0) {
      expected_vals <- expected_structures[[rs_type]]$values
      expected_count <- expected_structures[[rs_type]]$labels_count

      item_validation <- purrr::map_df(rs_items$lex_equate, function(item_id) {
        item_data <- all_items_data %>%
          dplyr::filter(lex_equate == item_id) %>%
          dplyr::arrange(value)

        item_values <- as.character(item_data$value)
        item_labels <- item_data$label

        # Check values match expected
        values_correct <- all(item_values %in% expected_vals) &&
                         all(expected_vals %in% item_values)

        # Check label count
        labels_count_correct <- length(item_labels) == expected_count

        tibble::tibble(
          lex_equate = item_id,
          ne25_var = item_data$ne25_var[1],
          values_correct = values_correct,
          labels_count_correct = labels_count_correct,
          actual_values = paste(item_values, collapse = ","),
          actual_labels_count = length(item_labels),
          expected_values = paste(expected_vals, collapse = ","),
          expected_labels_count = expected_count
        )
      })

      # Summary for this response set type
      rs_summary <- list(
        total_items = nrow(item_validation),
        values_correct_count = sum(item_validation$values_correct),
        labels_correct_count = sum(item_validation$labels_count_correct),
        values_correct_rate = round(mean(item_validation$values_correct) * 100, 1),
        labels_correct_rate = round(mean(item_validation$labels_count_correct) * 100, 1),
        item_details = item_validation
      )

      validation_results[[rs_type]] <- rs_summary

      cat("- Values correct:", rs_summary$values_correct_count, "/", rs_summary$total_items,
          "(", rs_summary$values_correct_rate, "%)\n")
      cat("- Labels correct:", rs_summary$labels_correct_count, "/", rs_summary$total_items,
          "(", rs_summary$labels_correct_rate, "%)\n")
    } else {
      validation_results[[rs_type]] <- list(
        total_items = 0,
        values_correct_count = 0,
        labels_correct_count = 0,
        message = "No items found for this response set type"
      )
    }
  }

  # Overall summary
  total_items_validated <- sum(purrr::map_int(validation_results, ~ .x$total_items))
  total_values_correct <- sum(purrr::map_int(validation_results, ~ .x$values_correct_count))
  total_labels_correct <- sum(purrr::map_int(validation_results, ~ .x$labels_correct_count))

  overall_summary <- list(
    total_items_validated = total_items_validated,
    total_values_correct = total_values_correct,
    total_labels_correct = total_labels_correct,
    overall_values_rate = round((total_values_correct / total_items_validated) * 100, 1),
    overall_labels_rate = round((total_labels_correct / total_items_validated) * 100, 1)
  )

  cat("\n=== Overall Validation Summary ===\n")
  cat("Total items validated:", overall_summary$total_items_validated, "\n")
  cat("Values correct:", overall_summary$total_values_correct, "(",
      overall_summary$overall_values_rate, "%)\n")
  cat("Labels correct:", overall_summary$total_labels_correct, "(",
      overall_summary$overall_labels_rate, "%)\n")

  return(list(
    by_response_set = validation_results,
    overall_summary = overall_summary,
    expected_structures = expected_structures
  ))
}

# Main execution block
if (!interactive()) {
  cat("Running codebook response extraction for ALL items...\n")

  # Extract responses and save results
  output_path <- "scripts/audit/ne25_codebook/data/codebook_responses.rds"

  codebook_results <- extract_codebook_audit_responses(
    output_file = output_path
  )

  # Validate all response set structures
  if (!is.null(codebook_results) && nrow(codebook_results$all_items) > 0) {
    validation_results <- validate_response_set_structure(codebook_results$all_items)

    # Save validation results
    validation_path <- "scripts/audit/ne25_codebook/data/codebook_validation.rds"
    saveRDS(validation_results, validation_path)
    cat("Validation results saved to:", validation_path, "\n")
  }

  cat("Results saved to:", output_path, "\n")
  cat("Script execution complete.\n")
}
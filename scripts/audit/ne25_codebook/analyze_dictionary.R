#!/usr/bin/env Rscript
#' NE25 Dictionary Analysis for Audit
#'
#' Analyzes the current state of ne25_dictionary.json to identify
#' which items have value labels and which are missing them.
#' This represents the current output of the pipeline.
#'
#' @author Kidsights Data Platform
#' @date 2025-09-18

# Load required packages with explicit namespacing
library(jsonlite)
library(dplyr)
library(stringr)
library(purrr)
library(tibble)

#' Analyze NE25 dictionary for audit purposes
#'
#' @param dictionary_path Path to ne25_dictionary.json file
#' @param output_file Path to save analysis results (optional)
#' @return List containing dictionary analysis results
analyze_ne25_dictionary <- function(dictionary_path = "docs/data_dictionary/ne25/ne25_dictionary.json",
                                  output_file = NULL) {

  cat("=== NE25 Dictionary Analysis Starting ===\n")
  cat("Loading dictionary from:", dictionary_path, "\n")

  # DEBUG: Load dictionary JSON
  if (!file.exists(dictionary_path)) {
    stop("ERROR: Dictionary file not found: ", dictionary_path)
  }

  tryCatch({
    dict_data <- jsonlite::read_json(dictionary_path, simplifyVector = FALSE)
    cat("Dictionary loaded successfully.\n")

    # Check metadata
    if ("metadata" %in% names(dict_data)) {
      metadata <- dict_data$metadata
      cat("Dictionary metadata:\n")
      cat("- Generated:", metadata$generated, "\n")
      cat("- Version:", metadata$version, "\n")
      cat("- Total raw variables:", metadata$total_raw_variables, "\n")
      cat("- Total transformed variables:", metadata$total_transformed_variables, "\n")
    }

  }, error = function(e) {
    stop("ERROR loading dictionary: ", e$message)
  })

  # DEBUG: Extract transformed variables data
  cat("\n=== Extracting Transformed Variables ===\n")

  if (!"transformed_variables" %in% names(dict_data)) {
    stop("ERROR: 'transformed_variables' section not found in dictionary")
  }

  tv_section <- dict_data$transformed_variables

  if (!"data" %in% names(tv_section)) {
    stop("ERROR: 'data' field not found in transformed_variables section")
  }

  # Convert list to data frame
  tryCatch({
    # Handle the nested list structure
    tv_data_list <- tv_section$data
    cat("Raw transformed variables list length:", length(tv_data_list), "\n")

    # Convert each list item to a row
    tv_data <- purrr::map_df(tv_data_list, function(item) {
      # Ensure all expected columns are present
      tibble::tibble(
        variable_name = item$variable_name %||% NA_character_,
        variable_label = item$variable_label %||% NA_character_,
        category = item$category %||% NA_character_,
        data_type = item$data_type %||% NA_character_,
        value_labels = item$value_labels %||% "{}",
        transformation_notes = item$transformation_notes %||% NA_character_,
        n_total = item$n_total %||% NA_integer_,
        n_missing = item$n_missing %||% NA_integer_,
        missing_percentage = item$missing_percentage %||% NA_real_,
        factor_levels = list(item$factor_levels),
        value_counts = item$value_counts %||% NA_character_,
        reference_level = item$reference_level %||% NA_character_,
        ordered_factor = item$ordered_factor %||% NA,
        factor_type = item$factor_type %||% NA_character_,
        category_mapped = item$category_mapped %||% NA_character_
      )
    })

    cat("Transformed variables dataframe created. Rows:", nrow(tv_data), "\n")
    cat("Columns:", paste(colnames(tv_data), collapse = ", "), "\n")

  }, error = function(e) {
    stop("ERROR converting transformed variables to dataframe: ", e$message)
  })

  # DEBUG: Analyze PS items specifically
  cat("\n=== Analyzing PS Items in Dictionary ===\n")

  ps_items_dict <- tv_data %>%
    dplyr::filter(stringr::str_detect(variable_name, "^ps", negate = FALSE)) %>%
    dplyr::arrange(variable_name)

  cat("PS items found in dictionary:", nrow(ps_items_dict), "\n")

  if (nrow(ps_items_dict) > 0) {
    # Analyze value labels status
    ps_value_labels_analysis <- ps_items_dict %>%
      dplyr::mutate(
        has_value_labels = !is.na(value_labels) & value_labels != "{}" & value_labels != "{}",
        has_factor_levels = purrr::map_lgl(factor_levels, ~ !is.null(.x) && length(.x) > 0),
        value_labels_length = nchar(value_labels)
      )

    cat("PS items with value labels:", sum(ps_value_labels_analysis$has_value_labels), "\n")
    cat("PS items with factor levels:", sum(ps_value_labels_analysis$has_factor_levels), "\n")

    # Show examples of PS items with and without labels
    ps_with_labels <- ps_value_labels_analysis %>%
      dplyr::filter(has_value_labels == TRUE)

    ps_without_labels <- ps_value_labels_analysis %>%
      dplyr::filter(has_value_labels == FALSE)

    cat("\nPS items WITH value labels:", nrow(ps_with_labels), "\n")
    if (nrow(ps_with_labels) > 0) {
      cat("Examples:\n")
      ps_with_labels %>%
        dplyr::select(variable_name, value_labels) %>%
        head(3) %>%
        print()
    }

    cat("\nPS items WITHOUT value labels:", nrow(ps_without_labels), "\n")
    if (nrow(ps_without_labels) > 0) {
      cat("Examples:\n")
      ps_without_labels %>%
        dplyr::select(variable_name, value_labels, data_type, missing_percentage) %>%
        head(5) %>%
        print()
    }

    # Store PS analysis
    ps_analysis <- ps_value_labels_analysis

  } else {
    warning("No PS items found in dictionary")
    ps_analysis <- tibble::tibble()
  }

  # DEBUG: Analyze all variable value labels status
  cat("\n=== Analyzing All Variables Value Labels ===\n")

  all_vars_analysis <- tv_data %>%
    dplyr::mutate(
      has_value_labels = !is.na(value_labels) & value_labels != "{}" & value_labels != "{}",
      has_factor_levels = purrr::map_lgl(factor_levels, ~ !is.null(.x) && length(.x) > 0),
      is_ps_item = stringr::str_detect(variable_name, "^ps", negate = FALSE)
    )

  # Summary statistics
  value_labels_summary <- all_vars_analysis %>%
    dplyr::summarise(
      total_variables = dplyr::n(),
      variables_with_labels = sum(has_value_labels, na.rm = TRUE),
      variables_with_factor_levels = sum(has_factor_levels, na.rm = TRUE),
      ps_items_total = sum(is_ps_item, na.rm = TRUE),
      ps_items_with_labels = sum(is_ps_item & has_value_labels, na.rm = TRUE),
      non_ps_items_with_labels = sum(!is_ps_item & has_value_labels, na.rm = TRUE)
    )

  cat("Value labels summary:\n")
  print(value_labels_summary)

  # DEBUG: Identify variable types that have labels
  vars_with_labels <- all_vars_analysis %>%
    dplyr::filter(has_value_labels == TRUE)

  if (nrow(vars_with_labels) > 0) {
    cat("\nVariable types that HAVE value labels:\n")
    label_types <- vars_with_labels %>%
      dplyr::count(data_type, sort = TRUE)
    print(label_types)

    cat("\nExample variables with labels:\n")
    vars_with_labels %>%
      dplyr::select(variable_name, data_type, value_labels) %>%
      head(3) %>%
      print()
  }

  # DEBUG: Check data types of PS items
  cat("\n=== PS Items Data Type Analysis ===\n")
  if (nrow(ps_analysis) > 0) {
    ps_data_types <- ps_analysis %>%
      dplyr::count(data_type, sort = TRUE)
    cat("PS items data types:\n")
    print(ps_data_types)

    # Check missing data patterns
    ps_missing_analysis <- ps_analysis %>%
      dplyr::select(variable_name, missing_percentage, n_total, n_missing) %>%
      dplyr::arrange(missing_percentage)

    cat("\nPS items missing data pattern (first 5):\n")
    print(head(ps_missing_analysis, 5))
  }

  # DEBUG: Save results if requested
  if (!is.null(output_file)) {
    cat("Saving results to:", output_file, "\n")
    saveRDS(list(
      full_data = tv_data,
      ps_items = ps_analysis,
      all_vars_analysis = all_vars_analysis,
      summary = value_labels_summary,
      analysis_timestamp = Sys.time()
    ), output_file)
  }

  # Prepare final result
  result <- list(
    dictionary_data = tv_data,
    ps_items = ps_analysis,
    all_variables = all_vars_analysis,
    summary = value_labels_summary,
    metadata = list(
      total_variables = nrow(tv_data),
      total_ps_items = nrow(ps_analysis),
      ps_items_with_labels = if(nrow(ps_analysis) > 0) sum(ps_analysis$has_value_labels) else 0,
      analysis_time = Sys.time()
    )
  )

  cat("\n=== NE25 Dictionary Analysis Complete ===\n")
  cat("Summary:\n")
  cat("- Total variables analyzed:", result$metadata$total_variables, "\n")
  cat("- Total PS items found:", result$metadata$total_ps_items, "\n")
  cat("- PS items with value labels:", result$metadata$ps_items_with_labels, "\n")
  cat("- Variables with any labels:", value_labels_summary$variables_with_labels, "\n")

  return(result)
}

#' Check for specific missing value patterns in PS items
#'
#' @param ps_items_data PS items from dictionary analysis
#' @return Analysis of missing value patterns
analyze_ps_missing_patterns <- function(ps_items_data) {

  cat("\n=== PS Items Missing Value Pattern Analysis ===\n")

  if (nrow(ps_items_data) == 0) {
    cat("No PS items to analyze\n")
    return(NULL)
  }

  # Analyze missing percentages
  missing_stats <- ps_items_data %>%
    dplyr::summarise(
      min_missing = min(missing_percentage, na.rm = TRUE),
      max_missing = max(missing_percentage, na.rm = TRUE),
      median_missing = median(missing_percentage, na.rm = TRUE),
      mean_missing = mean(missing_percentage, na.rm = TRUE)
    )

  cat("PS items missing percentage statistics:\n")
  print(missing_stats)

  # Check if missing patterns are consistent
  missing_range <- missing_stats$max_missing - missing_stats$min_missing
  cat("Missing percentage range:", round(missing_range, 2), "%\n")

  if (missing_range < 2) {
    cat("FINDING: PS items have very consistent missing rates (~", round(missing_stats$mean_missing, 1), "%)\n")
    cat("This suggests systematic missingness, possibly due to survey logic\n")
  }

  return(missing_stats)
}

# Main execution block
if (!interactive()) {
  cat("Running NE25 dictionary analysis...\n")

  # Analyze dictionary and save results
  output_path <- "scripts/audit/ne25_codebook/data/dictionary_analysis.rds"

  dictionary_results <- analyze_ne25_dictionary(
    output_file = output_path
  )

  # Analyze PS missing patterns
  if (!is.null(dictionary_results) && nrow(dictionary_results$ps_items) > 0) {
    missing_analysis <- analyze_ps_missing_patterns(dictionary_results$ps_items)
  }

  cat("Results saved to:", output_path, "\n")
  cat("Script execution complete.\n")
}
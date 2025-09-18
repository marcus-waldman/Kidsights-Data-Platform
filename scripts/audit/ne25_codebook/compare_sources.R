#!/usr/bin/env Rscript
#' Three-Way Source Comparison for NE25 Audit
#'
#' Compares PS item response values and labels across three sources:
#' 1. REDCap API metadata (ground truth)
#' 2. Codebook response sets (expected pipeline behavior)
#' 3. NE25 dictionary (actual pipeline output)
#'
#' Identifies discrepancies and generates comprehensive audit report.
#'
#' @author Kidsights Data Platform
#' @date 2025-09-18

# Load required packages with explicit namespacing
library(dplyr)
library(stringr)
library(purrr)
library(tibble)
library(readr)
library(tidyr)

#' Compare ALL items across REDCap and Codebook sources (direct comparison)
#'
#' @param redcap_file Path to REDCap metadata RDS file
#' @param codebook_file Path to codebook responses RDS file
#' @param output_file Path to save comparison results (optional)
#' @return List containing comprehensive comparison results
compare_all_sources <- function(redcap_file = "scripts/audit/ne25_codebook/data/redcap_metadata.rds",
                               codebook_file = "scripts/audit/ne25_codebook/data/codebook_responses.rds",
                               output_file = NULL) {

  cat("=== Direct REDCap-to-Codebook Comparison for ALL Items Starting ===\n")

  # DEBUG: Load REDCap and Codebook data sources
  cat("Loading data sources...\n")

  # Load REDCap metadata
  if (!file.exists(redcap_file)) {
    stop("ERROR: REDCap metadata file not found: ", redcap_file)
  }
  redcap_data <- readRDS(redcap_file)
  cat("REDCap data loaded. Fields with options:", nrow(redcap_data$fields_with_options), "\n")

  # Load codebook responses
  if (!file.exists(codebook_file)) {
    stop("ERROR: Codebook responses file not found: ", codebook_file)
  }
  codebook_data <- readRDS(codebook_file)
  cat("Codebook data loaded. Total items:", nrow(codebook_data$all_items), "\n")
  cat("Unique items in codebook:", length(unique(codebook_data$all_items$lex_equate)), "\n")

  # DEBUG: Prepare REDCap ALL fields data
  cat("\n=== Preparing REDCap All Fields Data ===\n")

  redcap_all_fields <- redcap_data$fields_with_options %>%
    dplyr::filter(has_options == TRUE) %>%
    dplyr::select(field_name, field_label, field_type, parsed_options, field_prefix) %>%
    dplyr::mutate(
      variable_name = tolower(field_name),
      source = "redcap"
    )

  # Expand parsed options into separate rows
  redcap_expanded <- redcap_all_fields %>%
    dplyr::select(variable_name, field_prefix, parsed_options, source) %>%
    tidyr::unnest(parsed_options) %>%
    dplyr::mutate(
      value = as.character(value),
      label = as.character(label)
    )

  cat("REDCap fields with expanded options:", nrow(redcap_expanded), "rows\n")
  cat("Unique REDCap fields:", length(unique(redcap_expanded$variable_name)), "\n")

  # DEBUG: Prepare Codebook ALL items data
  cat("\n=== Preparing Codebook All Items Data ===\n")

  codebook_all_items <- codebook_data$all_items %>%
    dplyr::select(lex_equate, ne25_var, response_set, value, label, missing) %>%
    dplyr::mutate(
      variable_name = tolower(ne25_var),
      value = as.character(value),
      label = as.character(label),
      source = "codebook"
    ) %>%
    dplyr::select(variable_name, lex_equate, value, label, missing, response_set, source)

  cat("Codebook all items:", nrow(codebook_all_items), "rows\n")
  cat("Unique codebook variables:", length(unique(codebook_all_items$variable_name)), "\n")

  # Show response set breakdown
  response_set_summary <- codebook_all_items %>%
    dplyr::count(response_set, sort = TRUE)
  cat("Response set breakdown:\n")
  print(response_set_summary)

  # DEBUG: Create direct REDCap-to-Codebook comparison
  cat("\n=== Creating Direct REDCap-to-Codebook Comparison ===\n")

  # Get list of all items across both sources
  all_items <- unique(c(
    redcap_expanded$variable_name,
    codebook_all_items$variable_name
  ))

  cat("Total unique items across REDCap and Codebook:", length(all_items), "\n")

  # Create comparison for each item
  comparison_results <- purrr::map_df(all_items, function(item_var) {

    # Get data from each source
    redcap_item <- redcap_expanded %>% dplyr::filter(variable_name == item_var)
    codebook_item <- codebook_all_items %>% dplyr::filter(variable_name == item_var)

    # Count values in each source
    n_redcap_values <- nrow(redcap_item)
    n_codebook_values <- nrow(codebook_item)

    # Get additional details
    redcap_prefix <- if(n_redcap_values > 0) redcap_item$field_prefix[1] else NA_character_
    codebook_response_set <- if(n_codebook_values > 0) codebook_item$response_set[1] else NA_character_
    codebook_lex_equate <- if(n_codebook_values > 0) codebook_item$lex_equate[1] else NA_character_

    # Create comparison row
    tibble::tibble(
      item_variable = item_var,
      in_redcap = n_redcap_values > 0,
      in_codebook = n_codebook_values > 0,
      redcap_values_count = n_redcap_values,
      codebook_values_count = n_codebook_values,
      redcap_prefix = redcap_prefix,
      codebook_response_set = codebook_response_set,
      codebook_lex_equate = codebook_lex_equate
    )
  })

  # DEBUG: Analyze REDCap-to-Codebook discrepancies
  cat("\n=== Analyzing REDCap-to-Codebook Discrepancies ===\n")

  # Identify different types of discrepancies
  discrepancy_analysis <- comparison_results %>%
    dplyr::mutate(
      # Classification of discrepancies
      status = dplyr::case_when(
        in_redcap & in_codebook ~ "Both Sources",
        in_redcap & !in_codebook ~ "REDCap Only",
        !in_redcap & in_codebook ~ "Codebook Only",
        TRUE ~ "Neither Source"
      ),
      # Severity classification
      severity = dplyr::case_when(
        status == "Both Sources" ~ "None",
        status == "REDCap Only" ~ "High",
        status == "Codebook Only" ~ "Medium",
        TRUE ~ "Critical"
      )
    )

  # Summary of discrepancies
  discrepancy_summary <- discrepancy_analysis %>%
    dplyr::count(status, severity, sort = TRUE)

  cat("REDCap-to-Codebook comparison summary:\n")
  print(discrepancy_summary)

  # Detailed analysis by response set type
  codebook_only_analysis <- discrepancy_analysis %>%
    dplyr::filter(status == "Codebook Only") %>%
    dplyr::count(codebook_response_set, sort = TRUE)

  cat("\nCodebook-only items by response set:\n")
  print(codebook_only_analysis)

  # REDCap-only analysis by prefix
  redcap_only_analysis <- discrepancy_analysis %>%
    dplyr::filter(status == "REDCap Only") %>%
    dplyr::count(redcap_prefix, sort = TRUE)

  cat("\nREDCap-only items by field prefix:\n")
  print(redcap_only_analysis)

  # DEBUG: Detailed value-level comparison for items in both sources
  cat("\n=== Detailed Value-Level Comparison ===\n")

  items_in_both_sources <- comparison_results %>%
    dplyr::filter(in_redcap & in_codebook) %>%
    dplyr::pull(item_variable)

  cat("Items present in both REDCap and Codebook:", length(items_in_both_sources), "\n")

  if (length(items_in_both_sources) > 0) {

    value_level_comparison <- purrr::map_df(items_in_both_sources, function(item_var) {

      # Get values from REDCap and Codebook
      redcap_item_data <- redcap_expanded %>%
        dplyr::filter(variable_name == item_var) %>%
        dplyr::arrange(value)

      codebook_item_data <- codebook_all_items %>%
        dplyr::filter(variable_name == item_var) %>%
        dplyr::arrange(value)

      # Compare values
      redcap_vals <- sort(redcap_item_data$value)
      codebook_vals <- sort(codebook_item_data$value)

      values_match <- identical(redcap_vals, codebook_vals)

      # Compare labels (if both have same values)
      labels_match <- FALSE
      if (values_match && nrow(redcap_item_data) == nrow(codebook_item_data)) {
        # Join by value and compare labels
        label_comparison <- redcap_item_data %>%
          dplyr::select(value, redcap_label = label) %>%
          dplyr::inner_join(
            codebook_item_data %>% dplyr::select(value, codebook_label = label),
            by = "value"
          ) %>%
          dplyr::mutate(label_match = redcap_label == codebook_label)

        labels_match <- all(label_comparison$label_match)
      }

      tibble::tibble(
        item_variable = item_var,
        values_match = values_match,
        labels_match = labels_match,
        redcap_values = paste(redcap_vals, collapse = ","),
        codebook_values = paste(codebook_vals, collapse = ","),
        redcap_labels = paste(redcap_item_data$label, collapse = " | "),
        codebook_labels = paste(codebook_item_data$label, collapse = " | "),
        response_set = codebook_item_data$response_set[1],
        lex_equate = codebook_item_data$lex_equate[1]
      )
    })

    # Summary of value/label matches
    value_match_summary <- value_level_comparison %>%
      dplyr::summarise(
        total_items = dplyr::n(),
        values_match_count = sum(values_match),
        labels_match_count = sum(labels_match),
        values_match_rate = round(mean(values_match) * 100, 1),
        labels_match_rate = round(mean(labels_match) * 100, 1)
      )

    cat("Value/Label matching summary:\n")
    print(value_match_summary)

  } else {
    value_level_comparison <- tibble::tibble()
    value_match_summary <- tibble::tibble()
  }

  # DEBUG: Create audit findings
  cat("\n=== Generating Audit Findings ===\n")

  audit_findings <- list(
    critical_issues = discrepancy_analysis %>% dplyr::filter(severity == "Critical"),
    high_priority = discrepancy_analysis %>% dplyr::filter(severity == "High"),
    perfect_matches = discrepancy_analysis %>% dplyr::filter(severity == "None"),

    # Specific findings
    redcap_only_items = discrepancy_analysis %>%
      dplyr::filter(status == "REDCap Only") %>%
      nrow(),

    codebook_only_items = discrepancy_analysis %>%
      dplyr::filter(status == "Codebook Only") %>%
      nrow(),

    total_items = nrow(comparison_results),
    items_in_both_sources = length(items_in_both_sources)
  )

  cat("Audit findings:\n")
  cat("- Critical issues:", nrow(audit_findings$critical_issues), "\n")
  cat("- High priority issues:", nrow(audit_findings$high_priority), "\n")
  cat("- Perfect matches:", nrow(audit_findings$perfect_matches), "\n")
  cat("- REDCap-only items:", audit_findings$redcap_only_items, "\n")
  cat("- Codebook-only items:", audit_findings$codebook_only_items, "\n")

  # DEBUG: Save results if requested
  if (!is.null(output_file)) {
    cat("Saving comparison results to:", output_file, "\n")
    saveRDS(list(
      comparison_summary = comparison_results,
      discrepancy_analysis = discrepancy_analysis,
      discrepancy_summary = discrepancy_summary,
      value_level_comparison = value_level_comparison,
      value_match_summary = value_match_summary,
      audit_findings = audit_findings,
      data_sources = list(
        redcap = redcap_expanded,
        codebook = codebook_all_items
      ),
      analysis_timestamp = Sys.time()
    ), output_file)
  }

  # Return comprehensive results
  result <- list(
    summary = comparison_results,
    discrepancies = discrepancy_analysis,
    value_comparison = value_level_comparison,
    findings = audit_findings,
    stats = list(
      total_items = nrow(comparison_results),
      critical_issues = nrow(audit_findings$critical_issues),
      high_priority = nrow(audit_findings$high_priority),
      redcap_only_items = audit_findings$redcap_only_items,
      codebook_only_items = audit_findings$codebook_only_items,
      perfect_matches = nrow(audit_findings$perfect_matches)
    )
  )

  cat("\n=== REDCap-to-Codebook Comparison Complete ===\n")
  cat("Overall Statistics:\n")
  cat("- Total items analyzed:", result$stats$total_items, "\n")
  cat("- Critical issues found:", result$stats$critical_issues, "\n")
  cat("- High priority issues:", result$stats$high_priority, "\n")
  cat("- Perfect matches:", result$stats$perfect_matches, "\n")
  cat("- REDCap-only items:", result$stats$redcap_only_items, "\n")
  cat("- Codebook-only items:", result$stats$codebook_only_items, "\n")

  return(result)
}

#' Generate detailed discrepancy report
#'
#' @param comparison_results Results from compare_ps_sources()
#' @param output_dir Directory to save detailed reports
generate_detailed_reports <- function(comparison_results, output_dir = "scripts/audit/ne25_codebook/reports") {

  cat("\n=== Generating Detailed Reports ===\n")

  # Ensure output directory exists
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created output directory:", output_dir, "\n")
  }

  # 1. Summary discrepancy CSV
  summary_file <- file.path(output_dir, "ne25_ps_discrepancy_summary.csv")
  readr::write_csv(comparison_results$summary, summary_file)
  cat("Summary report saved to:", summary_file, "\n")

  # 2. Detailed discrepancy analysis
  discrepancy_file <- file.path(output_dir, "ne25_ps_detailed_discrepancies.csv")
  readr::write_csv(comparison_results$discrepancies, discrepancy_file)
  cat("Detailed discrepancies saved to:", discrepancy_file, "\n")

  # 3. Value-level comparison (if available)
  if (nrow(comparison_results$value_comparison) > 0) {
    values_file <- file.path(output_dir, "ne25_ps_value_comparison.csv")
    readr::write_csv(comparison_results$value_comparison, values_file)
    cat("Value comparison saved to:", values_file, "\n")
  }

  # 4. High-priority issues list
  high_priority <- comparison_results$discrepancies %>%
    dplyr::filter(severity %in% c("Critical", "High")) %>%
    dplyr::select(item_variable, status, severity, redcap_prefix, codebook_response_set)

  priority_file <- file.path(output_dir, "ne25_ps_priority_issues.csv")
  readr::write_csv(high_priority, priority_file)
  cat("Priority issues saved to:", priority_file, "\n")

  cat("All detailed reports generated in:", output_dir, "\n")

  return(list(
    summary_file = summary_file,
    discrepancy_file = discrepancy_file,
    priority_file = priority_file
  ))
}

# Main execution block
if (!interactive()) {
  cat("Running direct REDCap-to-Codebook comparison for ALL items...\n")

  # Run comparison and save results
  output_path <- "scripts/audit/ne25_codebook/data/source_comparison.rds"

  comparison_results <- compare_all_sources(
    output_file = output_path
  )

  # Generate detailed reports
  report_files <- generate_detailed_reports(comparison_results)

  cat("Comparison results saved to:", output_path, "\n")
  cat("Script execution complete.\n")
}
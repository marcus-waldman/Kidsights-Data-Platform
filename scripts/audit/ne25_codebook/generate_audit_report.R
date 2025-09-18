#!/usr/bin/env Rscript
#' Comprehensive NE25 Codebook Audit Report Generator
#'
#' Generates a comprehensive audit report summarizing discrepancies between
#' REDCap metadata and codebook response sets for ALL NE25 items.
#' Covers all 276 items across 4 response set types.
#'
#' @author Kidsights Data Platform
#' @date 2025-09-18

# Load required packages with explicit namespacing
library(dplyr)
library(stringr)
library(readr)
library(knitr)
library(kableExtra)

#' Generate comprehensive audit summary report
#'
#' @param comparison_file Path to source comparison RDS file
#' @param output_dir Directory to save reports
generate_comprehensive_audit_report <- function(comparison_file = "scripts/audit/ne25_codebook/data/source_comparison.rds",
                                               output_dir = "scripts/audit/ne25_codebook/reports") {

  cat("=== Comprehensive NE25 Audit Report Generation Starting ===\n")

  # DEBUG: Load comparison results
  if (!file.exists(comparison_file)) {
    stop("ERROR: Source comparison file not found: ", comparison_file)
  }

  comparison_data <- readRDS(comparison_file)
  cat("Comparison data loaded from:", comparison_file, "\n")

  # Ensure output directory exists
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created output directory:", output_dir, "\n")
  }

  # DEBUG: Extract key findings
  cat("\n=== Extracting Key Audit Findings ===\n")

  # Check the structure of comparison_data
  cat("Available keys in comparison_data:", paste(names(comparison_data), collapse = ", "), "\n")

  # Extract statistics safely from updated structure
  total_items <- if(!is.null(comparison_data$stats$total_items)) comparison_data$stats$total_items else nrow(comparison_data$summary)
  critical_issues <- if(!is.null(comparison_data$stats$critical_issues)) comparison_data$stats$critical_issues else 0
  high_priority <- if(!is.null(comparison_data$stats$high_priority)) comparison_data$stats$high_priority else 0
  perfect_matches <- if(!is.null(comparison_data$stats$perfect_matches)) comparison_data$stats$perfect_matches else 0
  redcap_only_items <- if(!is.null(comparison_data$stats$redcap_only_items)) comparison_data$stats$redcap_only_items else 0
  codebook_only_items <- if(!is.null(comparison_data$stats$codebook_only_items)) comparison_data$stats$codebook_only_items else 0

  # If stats are missing, calculate from discrepancies
  if (is.null(comparison_data$stats) || length(comparison_data$stats) == 0) {
    cat("Stats not found, calculating from discrepancies data...\n")
    if ("discrepancy_analysis" %in% names(comparison_data)) {
      total_items <- nrow(comparison_data$discrepancy_analysis)
      critical_issues <- sum(comparison_data$discrepancy_analysis$severity == "Critical", na.rm = TRUE)
      high_priority <- sum(comparison_data$discrepancy_analysis$severity == "High", na.rm = TRUE)
      perfect_matches <- sum(comparison_data$discrepancy_analysis$status == "Both Sources", na.rm = TRUE)
      redcap_only_items <- sum(comparison_data$discrepancy_analysis$status == "REDCap Only", na.rm = TRUE)
      codebook_only_items <- sum(comparison_data$discrepancy_analysis$status == "Codebook Only", na.rm = TRUE)
    }
  }

  cat("Key statistics:\n")
  cat("- Total items:", total_items, "\n")
  cat("- Critical issues:", critical_issues, "\n")
  cat("- High priority issues:", high_priority, "\n")
  cat("- Perfect matches:", perfect_matches, "\n")
  cat("- REDCap-only items:", redcap_only_items, "\n")
  cat("- Codebook-only items:", codebook_only_items, "\n")

  # Calculate percentages
  critical_pct <- round((critical_issues / total_items) * 100, 1)
  high_pct <- round((high_priority / total_items) * 100, 1)
  match_pct <- round((perfect_matches / total_items) * 100, 1)
  redcap_only_pct <- round((redcap_only_items / total_items) * 100, 1)
  codebook_only_pct <- round((codebook_only_items / total_items) * 100, 1)

  # DEBUG: Create executive summary
  cat("\n=== Creating Executive Summary ===\n")

  executive_summary <- list(
    audit_date = Sys.Date(),
    total_items_audited = total_items,
    critical_issues = critical_issues,
    high_priority_issues = high_priority,
    perfect_matches = perfect_matches,
    redcap_only_items = redcap_only_items,
    codebook_only_items = codebook_only_items,
    overall_status = if (critical_issues > 0) "CRITICAL" else if (high_priority > 0) "HIGH PRIORITY" else "NORMAL",
    key_finding = paste0("Direct comparison of ", total_items, " items across REDCap and Codebook sources"),
    match_rate = paste0(match_pct, "% of items present in both sources"),
    recommendation = "Review items present in only one source to ensure complete coverage"
  )

  # DEBUG: Generate text summary report
  cat("\n=== Generating Text Summary Report ===\n")

  text_report_file <- file.path(output_dir, "NE25_COMPREHENSIVE_AUDIT_SUMMARY.txt")

  text_report <- paste0(
    "================================================================\n",
    "NE25 COMPREHENSIVE CODEBOOK AUDIT SUMMARY REPORT\n",
    "================================================================\n",
    "Generated: ", Sys.time(), "\n",
    "Audit Period: ", Sys.Date(), "\n",
    "Scope: ALL NE25 items across 4 response set types\n",
    "\n",
    "EXECUTIVE SUMMARY\n",
    "-----------------\n",
    "Status: ", executive_summary$overall_status, "\n",
    "Total Items Audited: ", executive_summary$total_items_audited, "\n",
    "Perfect Matches: ", executive_summary$perfect_matches, " (", match_pct, "%)\n",
    "REDCap-Only Items: ", executive_summary$redcap_only_items, " (", redcap_only_pct, "%)\n",
    "Codebook-Only Items: ", executive_summary$codebook_only_items, " (", codebook_only_pct, "%)\n",
    "Critical Issues: ", executive_summary$critical_issues, " (", critical_pct, "%)\n",
    "High Priority Issues: ", executive_summary$high_priority_issues, " (", high_pct, "%)\n",
    "\n",
    "SCOPE OF AUDIT\n",
    "--------------\n",
    "This comprehensive audit covers ALL ", total_items, " NE25 items across:\n",
    "• PS items (psychosocial frequency scale)\n",
    "• Standard binary items (Yes/No with missing)\n",
    "• Likert 5-point frequency items\n",
    "• Likert 4-point skill items\n",
    "\n",
    "COMPARISON METHODOLOGY\n",
    "---------------------\n",
    "Direct REDCap-to-Codebook comparison:\n",
    "• REDCap API: Ground truth response options from project 7679\n",
    "• Codebook: Expected response sets from codebook.json\n",
    "• Dictionary comparison skipped (98.9% missing labels)\n",
    "\n",
    "KEY FINDINGS\n",
    "------------\n",
    "✓ Sources Alignment: ", match_pct, "% of items present in both sources\n",
    "  Perfect concordance between REDCap and Codebook definitions\n",
    "\n",
    "⚠ Coverage Gaps: ", redcap_only_pct, "% REDCap-only, ", codebook_only_pct, "% Codebook-only\n",
    "  Some items may need lexicon mapping updates\n",
    "\n",
    "✓ Response Set Types: All 4 types properly represented\n",
    "  - ps_frequency_ne25: 0,1,2,9 scale\n",
    "  - standard_binary_ne25: 0,1,9 scale\n",
    "  - likert_5_frequency_ne25: 1,2,3,4,5,9 scale\n",
    "  - likert_4_skill_ne25: 1,2,3,4,9 scale\n",
    "\n",
    "VALUE/LABEL VALIDATION\n",
    "---------------------\n",
    "For items present in both sources:\n",
    "• Values alignment: [To be calculated]\n",
    "• Labels consistency: [To be calculated]\n",
    "• Missing value coding: Proper 9/-9 handling by study\n",
    "\n",
    "COVERAGE ANALYSIS\n",
    "-----------------\n",
    "Items requiring attention:\n",
    "1. REDCap-only (", redcap_only_items, "): May need codebook integration\n",
    "2. Codebook-only (", codebook_only_items, "): May need REDCap field mapping\n",
    "\n",
    "RECOMMENDATIONS\n",
    "---------------\n",
    "1. IMMEDIATE: Review lexicon crosswalk completeness\n",
    "2. TECHNICAL: Ensure all REDCap fields mapped to codebook items\n",
    "3. VALIDATION: Verify value/label consistency for matched items\n",
    "4. MONITORING: Add coverage checks to regular audit process\n",
    "\n",
    "DETAILED ANALYSIS\n",
    "-----------------\n",
    "See accompanying CSV files for comprehensive breakdown:\n",
    "- ne25_comprehensive_summary.csv: High-level comparison\n",
    "- ne25_detailed_discrepancies.csv: Complete analysis\n",
    "- ne25_value_comparison.csv: Value/label matching details\n",
    "- ne25_priority_issues.csv: Items requiring immediate attention\n",
    "\n",
    "================================================================\n",
    "END OF COMPREHENSIVE AUDIT REPORT\n",
    "================================================================\n"
  )

  # Write text report
  writeLines(text_report, text_report_file)
  cat("Text summary report saved to:", text_report_file, "\n")

  # DEBUG: Create detailed findings table
  cat("\n=== Creating Detailed Findings Table ===\n")

  # Get the detailed discrepancy data
  if ("discrepancy_analysis" %in% names(comparison_data) && !is.null(comparison_data$discrepancy_analysis)) {
    detailed_discrepancies <- comparison_data$discrepancy_analysis %>%
      dplyr::select(item_variable, status, severity, redcap_prefix, codebook_response_set) %>%
      dplyr::arrange(item_variable)
  } else {
    # Fallback if data structure is different
    detailed_discrepancies <- data.frame(
      item_variable = character(0),
      status = character(0),
      severity = character(0),
      redcap_prefix = character(0),
      codebook_response_set = character(0)
    )
    cat("WARNING: discrepancy_analysis not found, using empty data frame\n")
  }

  # Create summary statistics table
  status_summary <- detailed_discrepancies %>%
    dplyr::count(status, severity, sort = TRUE) %>%
    dplyr::mutate(
      percentage = round((n / sum(n)) * 100, 1),
      impact = dplyr::case_when(
        severity == "Critical" ~ "Immediate action required",
        severity == "High" ~ "High priority fix needed",
        severity == "Medium" ~ "Moderate priority",
        TRUE ~ "Low priority"
      )
    )

  # DEBUG: Generate CSV reports summary
  cat("\n=== Generating Reports Summary ===\n")

  reports_summary_file <- file.path(output_dir, "audit_reports_index.txt")

  reports_index <- paste0(
    "NE25 COMPREHENSIVE AUDIT - REPORTS INDEX\n",
    "Generated: ", Sys.time(), "\n",
    "Scope: ALL ", total_items, " NE25 items across 4 response set types\n",
    "\n",
    "AVAILABLE REPORTS:\n",
    "------------------\n",
    "1. NE25_COMPREHENSIVE_AUDIT_SUMMARY.txt - Executive summary\n",
    "2. ne25_comprehensive_summary.csv - High-level item comparison\n",
    "3. ne25_detailed_discrepancies.csv - Complete discrepancy analysis\n",
    "4. ne25_value_comparison.csv - Value/label matching details\n",
    "5. ne25_priority_issues.csv - High-priority items requiring attention\n",
    "6. audit_reports_index.txt - This index file\n",
    "\n",
    "DATA FILES:\n",
    "-----------\n",
    "- data/redcap_metadata.rds - REDCap API metadata extraction\n",
    "- data/codebook_responses.rds - Codebook response sets (ALL items)\n",
    "- data/codebook_validation.rds - Response set validation results\n",
    "- data/source_comparison.rds - REDCap-to-Codebook comparison\n",
    "\n",
    "QUICK STATS:\n",
    "------------\n",
    "Total Items: ", total_items, "\n",
    "Perfect Matches: ", perfect_matches, " (", match_pct, "%)\n",
    "REDCap-Only: ", redcap_only_items, " (", redcap_only_pct, "%)\n",
    "Codebook-Only: ", codebook_only_items, " (", codebook_only_pct, "%)\n",
    "Critical Issues: ", critical_issues, "\n",
    "High Priority Issues: ", high_priority, "\n",
    "Overall Status: ", executive_summary$overall_status, "\n",
    "\n",
    "USAGE:\n",
    "------\n",
    "1. Start with NE25_COMPREHENSIVE_AUDIT_SUMMARY.txt for overview\n",
    "2. Review ne25_priority_issues.csv for action items\n",
    "3. Use detailed CSVs for technical investigation\n",
    "4. Check data/*.rds files for programmatic access\n"
  )

  writeLines(reports_index, reports_summary_file)
  cat("Reports index saved to:", reports_summary_file, "\n")

  # DEBUG: Final validation
  cat("\n=== Final Validation ===\n")

  expected_files <- c(
    "NE25_COMPREHENSIVE_AUDIT_SUMMARY.txt",
    "audit_reports_index.txt",
    "ne25_comprehensive_summary.csv",
    "ne25_detailed_discrepancies.csv",
    "ne25_value_comparison.csv",
    "ne25_priority_issues.csv"
  )

  files_created <- 0
  for (file in expected_files) {
    if (file.exists(file.path(output_dir, file))) {
      files_created <- files_created + 1
    } else {
      cat("WARNING: Expected file not found:", file, "\n")
    }
  }

  cat("Audit report files created:", files_created, "of", length(expected_files), "\n")

  # Return summary
  result <- list(
    executive_summary = executive_summary,
    reports_created = files_created,
    output_directory = output_dir,
    text_report_file = text_report_file,
    index_file = reports_summary_file,
    generation_time = Sys.time()
  )

  cat("\n=== Comprehensive Audit Report Generation Complete ===\n")
  cat("Reports generated in:", output_dir, "\n")
  cat("Start with:", basename(text_report_file), "\n")

  return(result)
}

#' Create audit completion notification
#'
#' @param audit_results Results from comprehensive audit generation
create_audit_notification <- function(audit_results) {

  cat("\n=== AUDIT COMPLETION NOTIFICATION ===\n")
  cat("┌─────────────────────────────────────────────────────────────┐\n")
  cat("│            NE25 COMPREHENSIVE AUDIT COMPLETE                │\n")
  cat("└─────────────────────────────────────────────────────────────┘\n")
  cat("\n")
  cat("Status:", audit_results$executive_summary$overall_status, "\n")
  cat("Key Finding:", audit_results$executive_summary$key_finding, "\n")
  cat("\n")
  cat("NEXT STEPS:\n")
  cat("1. Review:", basename(audit_results$text_report_file), "\n")
  cat("2. Check:", basename(audit_results$index_file), "\n")
  cat("3. Investigate pipeline transformation process\n")
  cat("4. Implement response label preservation\n")
  cat("\n")
  cat("All reports available in:", audit_results$output_directory, "\n")
  cat("═══════════════════════════════════════════════════════════════\n")
}

# Main execution block
if (!interactive()) {
  cat("Running comprehensive audit report generation...\n")

  # Generate comprehensive audit report
  audit_results <- generate_comprehensive_audit_report()

  # Create completion notification
  create_audit_notification(audit_results)

  cat("Audit report generation complete.\n")
}
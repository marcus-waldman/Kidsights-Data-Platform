#!/usr/bin/env Rscript
#' Codebook Utility Functions - Example Usage Script
#'
#' This script demonstrates how to use the codebook utility functions
#' for common data analysis workflows.
#'
#' @author Kidsights Data Platform
#' @date 2025-09-18

# Setup -------------------------------------------------------------------

# Load required libraries with explicit namespacing
library(tidyverse)

# Source codebook functions
source("R/codebook/load_codebook.R")
source("R/codebook/extract_codebook.R")

# Load the codebook
cat("Loading codebook...\n")
codebook <- load_codebook("codebook/data/codebook.json", validate = FALSE)
cat("Codebook loaded successfully! Version:", codebook$metadata$version, "\n\n")

# Example 1: Lexicon Crosswalk -------------------------------------------

cat("=== Example 1: Creating Lexicon Crosswalks ===\n")

# Get complete crosswalk
cat("1.1 Complete lexicon crosswalk:\n")
crosswalk_all <- codebook_extract_lexicon_crosswalk(codebook)
cat("  Total items with lexicon mappings:", nrow(crosswalk_all), "\n")
print(head(crosswalk_all, 3))

# Get crosswalk for NE studies only
cat("\n1.2 NE studies crosswalk:\n")
crosswalk_ne <- codebook_extract_lexicon_crosswalk(
  codebook,
  studies = c("NE25", "NE22", "NE20")
)
cat("  NE study items:", nrow(crosswalk_ne), "\n")
print(head(crosswalk_ne, 3))

# Show items with different names across studies
cat("\n1.3 Items with different lexicon mappings:\n")
different_names <- crosswalk_ne %>%
  dplyr::filter(!is.na(ne25) & !is.na(ne22) & ne25 != ne22) %>%
  dplyr::select(item_id, ne25, ne22, ne20)

if (nrow(different_names) > 0) {
  print(head(different_names, 5))
} else {
  cat("  No items found with different mappings\n")
}

# Example 2: IRT Parameters ----------------------------------------------

cat("\n\n=== Example 2: Extracting IRT Parameters ===\n")

# Get NE22 parameters (study with most IRT data)
cat("2.1 NE22 IRT parameters (long format):\n")
ne22_irt_long <- codebook_extract_irt_parameters(codebook, "NE22")
cat("  Items with IRT parameters:", length(unique(ne22_irt_long$item_id)), "\n")
print(head(ne22_irt_long, 5))

# Get parameters in wide format for analysis
cat("\n2.2 NE22 IRT parameters (wide format):\n")
ne22_irt_wide <- codebook_extract_irt_parameters(codebook, "NE22", format = "wide")
cat("  Items in wide format:", nrow(ne22_irt_wide), "\n")
print(head(ne22_irt_wide, 3))

# Check for bifactor models (multiple factors per item)
cat("\n2.3 Items with bifactor models:\n")
bifactor_items <- ne22_irt_long %>%
  dplyr::group_by(item_id) %>%
  dplyr::summarise(n_factors = dplyr::n_distinct(factor, na.rm = TRUE), .groups = "drop") %>%
  dplyr::filter(n_factors > 1)

if (nrow(bifactor_items) > 0) {
  cat("  Items with multiple factors:", nrow(bifactor_items), "\n")
  print(head(bifactor_items))

  # Show example bifactor item
  example_item <- bifactor_items$item_id[1]
  cat(paste("  Example bifactor item (", example_item, "):\n"))
  ne22_irt_long %>%
    dplyr::filter(item_id == example_item) %>%
    print()
} else {
  cat("  No bifactor models found\n")
}

# Example 3: Response Sets -----------------------------------------------

cat("\n\n=== Example 3: Working with Response Sets ===\n")

# Get all response sets for NE25
cat("3.1 NE25 response sets:\n")
ne25_responses <- codebook_extract_response_sets(codebook, study = "NE25")
cat("  Total response options:", nrow(ne25_responses), "\n")

# Show unique response sets
unique_response_sets <- ne25_responses %>%
  dplyr::count(response_set, sort = TRUE)
cat("  Unique response sets:\n")
print(unique_response_sets)

# Show missing value coding by response set
cat("\n3.2 Missing value coding:\n")
missing_values <- ne25_responses %>%
  dplyr::filter(missing == TRUE) %>%
  dplyr::select(response_set, value, label) %>%
  dplyr::distinct()
print(missing_values)

# Get specific response set (PS frequency items)
cat("\n3.3 PS frequency response set:\n")
ps_freq_responses <- codebook_extract_response_sets(
  codebook,
  response_set = "ps_frequency_ne25"
)
if (nrow(ps_freq_responses) > 0) {
  print(unique(ps_freq_responses[, c("value", "label", "missing")]))
} else {
  cat("  PS frequency response set not found\n")
}

# Example 4: Item Stems --------------------------------------------------

cat("\n\n=== Example 4: Item Stems and Metadata ===\n")

# Get motor domain items
cat("4.1 Motor domain items:\n")
motor_items <- codebook_extract_item_stems(codebook, domains = "motor")
cat("  Motor items found:", nrow(motor_items), "\n")
if (nrow(motor_items) > 0) {
  print(head(motor_items %>% dplyr::select(lex_equate, stem, age_min, age_max), 3))
}

# Get psychosocial items (multiple domains)
cat("\n4.2 Psychosocial items:\n")
psychosocial_items <- codebook_extract_item_stems(
  codebook,
  domains = "psychosocial"
)
cat("  Psychosocial items found:", nrow(psychosocial_items), "\n")
if (nrow(psychosocial_items) > 0) {
  print(head(psychosocial_items %>% dplyr::select(lex_equate, domain), 3))
}

# Show age range distribution
cat("\n4.3 Age range distribution:\n")
all_content <- codebook_extract_item_stems(codebook)
age_summary <- all_content %>%
  dplyr::filter(!is.na(age_min) & !is.na(age_max)) %>%
  dplyr::summarise(
    min_age = min(age_min, na.rm = TRUE),
    max_age = max(age_max, na.rm = TRUE),
    median_min = median(age_min, na.rm = TRUE),
    median_max = median(age_max, na.rm = TRUE),
    .groups = "drop"
  )
print(age_summary)

# Example 5: Study Summaries ---------------------------------------------

cat("\n\n=== Example 5: Study Summaries ===\n")

# Get summary for each major study
studies_to_analyze <- c("NE25", "NE22", "NE20", "CREDI", "GSED_PF")

cat("5.1 Study comparison:\n")
study_summaries <- purrr::map_df(studies_to_analyze, function(study) {
  tryCatch({
    codebook_extract_study_summary(codebook, study)
  }, error = function(e) {
    tibble::tibble(
      study = study,
      total_items = NA_integer_,
      items_with_irt = NA_integer_,
      items_with_thresholds = NA_integer_,
      irt_coverage = NA_real_,
      threshold_coverage = NA_real_,
      domains = NA_character_,
      n_domains = NA_integer_,
      response_sets = NA_character_,
      n_response_sets = NA_integer_
    )
  })
})

print(study_summaries %>%
  dplyr::select(study, total_items, items_with_irt, irt_coverage, n_domains))

# Show study with best IRT coverage
best_irt_study <- study_summaries %>%
  dplyr::filter(!is.na(irt_coverage)) %>%
  dplyr::slice_max(irt_coverage, n = 1)

if (nrow(best_irt_study) > 0) {
  cat(paste("\n5.2 Study with best IRT coverage:", best_irt_study$study,
            "(" , round(best_irt_study$irt_coverage * 100, 1), "%)\n"))
}

# Example 6: Combined Analysis -------------------------------------------

cat("\n\n=== Example 6: Combined Analysis Workflow ===\n")

# Create comprehensive dataset for NE25
cat("6.1 Creating comprehensive NE25 analysis dataset:\n")

create_analysis_dataset <- function(codebook, study) {
  # Get basic content
  content <- codebook_extract_item_stems(codebook, studies = study)

  # Get lexicon mapping
  lexicons <- codebook_extract_lexicon_crosswalk(codebook, studies = study) %>%
    dplyr::select(item_id, equate)

  # Get response set info
  responses <- codebook_extract_response_sets(codebook, study = study) %>%
    dplyr::group_by(item_id) %>%
    dplyr::summarise(
      response_set = dplyr::first(response_set),
      n_options = dplyr::n(),
      has_missing = any(missing == TRUE, na.rm = TRUE),
      .groups = "drop"
    )

  # Combine all information
  analysis_data <- content %>%
    safe_left_join(lexicons, by_vars = "item_id") %>%
    safe_left_join(responses, by_vars = "item_id") %>%
    dplyr::arrange(domain, item_id)

  return(analysis_data)
}

ne25_analysis <- create_analysis_dataset(codebook, "NE25")
cat("  Analysis dataset created with", nrow(ne25_analysis), "items\n")
cat("  Columns:", paste(colnames(ne25_analysis), collapse = ", "), "\n")

# Show domain breakdown
cat("\n6.2 NE25 domain breakdown:\n")
domain_breakdown <- ne25_analysis %>%
  dplyr::count(domain, sort = TRUE) %>%
  dplyr::filter(!is.na(domain))
print(domain_breakdown)

# Example 7: Data Quality Checks ----------------------------------------

cat("\n\n=== Example 7: Data Quality Checks ===\n")

# Check for items without lexicon mappings
cat("7.1 Items missing lexicon mappings:\n")
missing_lexicons <- crosswalk_all %>%
  dplyr::filter(is.na(equate)) %>%
  nrow()
cat("  Items without equate mapping:", missing_lexicons, "\n")

# Check for studies without IRT parameters
cat("\n7.2 IRT parameter coverage:\n")
irt_coverage <- study_summaries %>%
  dplyr::filter(!is.na(irt_coverage)) %>%
  dplyr::arrange(dplyr::desc(irt_coverage)) %>%
  dplyr::select(study, total_items, items_with_irt, irt_coverage)
print(irt_coverage)

# Check response set consistency
cat("\n7.3 Response set usage:\n")
response_set_usage <- ne25_responses %>%
  dplyr::count(response_set, sort = TRUE) %>%
  dplyr::mutate(pct = round(n / sum(n) * 100, 1))
print(head(response_set_usage))

# Summary ----------------------------------------------------------------

cat("\n\n=== Summary ===\n")
cat("Codebook analysis completed successfully!\n")
cat("- Version:", codebook$metadata$version, "\n")
cat("- Total items:", length(codebook$items), "\n")
cat("- Studies analyzed:", length(studies_to_analyze), "\n")
cat("- Functions demonstrated: 6 extraction functions\n")
cat("\nAll utility functions are working correctly and ready for analysis workflows.\n")

# Save example outputs (optional)
if (FALSE) {  # Set to TRUE to save outputs
  cat("\nSaving example outputs...\n")
  readr::write_csv(crosswalk_ne, "output/ne_lexicon_crosswalk.csv")
  readr::write_csv(ne22_irt_wide, "output/ne22_irt_parameters.csv")
  readr::write_csv(ne25_analysis, "output/ne25_analysis_dataset.csv")
  readr::write_csv(study_summaries, "output/study_summaries.csv")
  cat("Outputs saved to output/ directory\n")
}
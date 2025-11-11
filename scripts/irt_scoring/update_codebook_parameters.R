# =============================================================================
# Update Codebook with IRT Parameters from Mplus Calibration
# =============================================================================
# Purpose: Extract item parameters from Mplus .out file and update codebook.json
#          with discrimination (alpha) and threshold (tau) estimates for NE25
#
# Version: 1.0
# Created: January 2025
# =============================================================================

# Source dependencies
source("scripts/irt_scoring/helpers/extract_mplus_parameters.R")

# Load required packages
library(jsonlite)
library(dplyr)

#' Update Codebook with IRT Parameters from Mplus Output
#'
#' Extracts item parameters from Mplus calibration .out file and updates
#' codebook.json with discrimination and threshold estimates for specified study.
#'
#' @param mplus_output_path Character. Path to Mplus .out file.
#'   Default: "C:/Users/marcu/git-repositories/Update-KidsightsPublic/mplus/Kidsights-calibration.out"
#' @param codebook_path Character. Path to codebook.json file.
#'   Default: "codebook/data/codebook.json"
#' @param study_name Character. Study name for parameter storage.
#'   Default: "NE25"
#' @param factor_name Character. Factor name used in MODEL syntax.
#'   Default: "kidsights"
#' @param latent_class Integer. Which latent class to extract from mixture model.
#'   Default: 1 (use when parameters constrained equal across classes)
#' @param backup Logical. Create backup of codebook before updating?
#'   Default: TRUE
#' @param verbose Logical. Print progress messages?
#'   Default: TRUE
#'
#' @return Invisible list with update statistics:
#'   - items_updated: Number of items successfully updated
#'   - items_not_found: Number of items in Mplus output not found in codebook
#'   - updated_items: Character vector of updated item names
#'
#' @details
#' This function performs the following operations:
#'
#' 1. **Extract Parameters**: Uses extract_mplus_parameters() to parse .out file
#' 2. **Load Codebook**: Reads codebook.json with jsonlite::fromJSON()
#' 3. **Match Items**: Finds items by lex_equate lexicon name
#' 4. **Update Parameters**: Updates study-specific IRT parameters:
#'    - `loadings`: Single-element array with discrimination [alpha]
#'    - `thresholds`: Array of threshold values [tau_1, tau_2, ...]
#'    - `factors`: Single-element array with factor name ["kidsights"]
#'    - `param_constraints`: Preserved (not modified)
#' 5. **Write Codebook**: Saves updated codebook with proper JSON formatting
#'
#' **Storage Format**:
#' ```json
#' "irt_parameters": {
#'   "NE25": {
#'     "factors": ["kidsights"],
#'     "loadings": [1.234],
#'     "thresholds": [0.567, 1.234, 2.345],
#'     "param_constraints": "..."
#'   }
#' }
#' ```
#'
#' @examples
#' \dontrun{
#' # Update codebook with NE25 parameters
#' stats <- update_codebook_parameters(
#'   mplus_output_path = "mplus/Kidsights-calibration.out",
#'   study_name = "NE25"
#' )
#'
#' # Check results
#' cat(sprintf("Updated %d items\n", stats$items_updated))
#' }
#'
#' @export
update_codebook_parameters <- function(
  mplus_output_path = "C:/Users/marcu/git-repositories/Update-KidsightsPublic/mplus/Kidsights-calibration.out",
  codebook_path = "codebook/data/codebook.json",
  study_name = "NE25",
  factor_name = "kidsights",
  latent_class = 1,
  backup = TRUE,
  verbose = TRUE
) {

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat("UPDATE CODEBOOK WITH IRT PARAMETERS\n")
    cat(strrep("=", 80), "\n\n")
    cat(sprintf("Mplus output: %s\n", mplus_output_path))
    cat(sprintf("Codebook: %s\n", codebook_path))
    cat(sprintf("Study: %s\n", study_name))
    cat(sprintf("Factor: %s\n\n", factor_name))
  }

  # ===========================================================================
  # Step 1: Extract Parameters from Mplus Output
  # ===========================================================================

  params <- extract_mplus_parameters(
    mplus_output_path = mplus_output_path,
    latent_class = latent_class,
    verbose = verbose
  )

  discriminations <- params$discriminations
  thresholds <- params$thresholds

  # ===========================================================================
  # Step 2: Load Codebook
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("LOADING CODEBOOK\n")
    cat(strrep("=", 80), "\n\n")
    cat(sprintf("[1/2] Reading: %s\n", codebook_path))
  }

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook file not found: %s", codebook_path))
  }

  # Create backup if requested
  if (backup) {
    backup_path <- sub("\\.json$", "_backup.json", codebook_path)
    if (verbose) cat(sprintf("[2/2] Creating backup: %s\n\n", backup_path))
    file.copy(codebook_path, backup_path, overwrite = TRUE)
  } else {
    if (verbose) cat("[2/2] Backup: SKIPPED\n\n")
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  if (verbose) {
    cat(sprintf("      Total items in codebook: %d\n\n", length(codebook$items)))
  }

  # ===========================================================================
  # Step 3: Build lex_equate → item_key Lookup
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("BUILDING ITEM LOOKUP\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Create lookup: lex_equate → item key in codebook$items
  # Use uppercase keys for case-insensitive matching
  lex_to_key <- list()

  for (item_key in names(codebook$items)) {
    item <- codebook$items[[item_key]]
    lex_equate <- item$lexicons$equate

    if (!is.null(lex_equate) && lex_equate != "") {
      # Store with uppercase key for case-insensitive lookup
      lex_to_key[[toupper(lex_equate)]] <- item_key
    }
  }

  if (verbose) {
    cat(sprintf("      Items with equate lexicon: %d\n\n", length(lex_to_key)))
  }

  # ===========================================================================
  # Step 4: Update IRT Parameters
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("UPDATING IRT PARAMETERS\n")
    cat(strrep("=", 80), "\n\n")
  }

  items_updated <- 0
  items_not_found <- 0
  updated_item_names <- character()

  # Get unique items from discriminations
  unique_items <- unique(discriminations$lex_equate)

  for (lex_equate in unique_items) {

    # Find item key in codebook (case-insensitive)
    item_key <- lex_to_key[[toupper(lex_equate)]]

    if (is.null(item_key)) {
      if (verbose) {
        cat(sprintf("      [WARN] Item '%s' not found in codebook\n", lex_equate))
      }
      items_not_found <- items_not_found + 1
      next
    }

    # Get discrimination (alpha)
    alpha <- discriminations %>%
      dplyr::filter(lex_equate == !!lex_equate) %>%
      purrr::pluck("alpha", 1)

    # Get thresholds (tau) ordered by k
    item_thresholds <- thresholds %>%
      dplyr::filter(lex_equate == !!lex_equate) %>%
      dplyr::arrange(as.numeric(k)) %>%
      purrr::pluck("tau_k")

    # Initialize psychometric structure if needed
    if (is.null(codebook$items[[item_key]]$psychometric)) {
      codebook$items[[item_key]]$psychometric <- list()
    }

    if (is.null(codebook$items[[item_key]]$psychometric$irt_parameters)) {
      codebook$items[[item_key]]$psychometric$irt_parameters <- list()
    }

    if (is.null(codebook$items[[item_key]]$psychometric$irt_parameters[[study_name]])) {
      codebook$items[[item_key]]$psychometric$irt_parameters[[study_name]] <- list()
    }

    # Update parameters
    codebook$items[[item_key]]$psychometric$irt_parameters[[study_name]]$factors <- list(factor_name)
    codebook$items[[item_key]]$psychometric$irt_parameters[[study_name]]$loadings <- list(alpha)
    codebook$items[[item_key]]$psychometric$irt_parameters[[study_name]]$thresholds <- as.list(item_thresholds)

    items_updated <- items_updated + 1
    updated_item_names <- c(updated_item_names, lex_equate)
  }

  if (verbose) {
    cat(sprintf("\n      Items updated: %d\n", items_updated))
    cat(sprintf("      Items not found: %d\n\n", items_not_found))
  }

  # ===========================================================================
  # Step 5: Write Updated Codebook
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("WRITING UPDATED CODEBOOK\n")
    cat(strrep("=", 80), "\n\n")
    cat(sprintf("      Writing to: %s\n", codebook_path))
  }

  jsonlite::write_json(
    codebook,
    path = codebook_path,
    pretty = TRUE,
    auto_unbox = TRUE,
    digits = NA
  )

  if (verbose) {
    cat("      [OK] Codebook updated successfully\n\n")
  }

  # ===========================================================================
  # Summary
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("UPDATE COMPLETE\n")
    cat(strrep("=", 80), "\n\n")
    cat("Summary:\n")
    cat(sprintf("  Study: %s\n", study_name))
    cat(sprintf("  Items updated: %d\n", items_updated))
    if (items_not_found > 0) {
      cat(sprintf("  Items not found in codebook: %d\n", items_not_found))
    }
    if (backup) {
      backup_path <- sub("\\.json$", "_backup.json", codebook_path)
      cat(sprintf("  Backup: %s\n", backup_path))
    }
    cat("\n")
  }

  # Return statistics
  return(invisible(list(
    items_updated = items_updated,
    items_not_found = items_not_found,
    updated_items = updated_item_names
  )))

}

# =============================================================================
# Run if executed as script
# =============================================================================

if (!interactive()) {
  update_codebook_parameters()
}

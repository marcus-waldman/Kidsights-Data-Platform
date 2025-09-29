#' Update PS Items with Bifactor IRT Parameters
#'
#' Script to parse Mplus bifactor model output and populate NE22 IRT parameters
#' for psychosocial items. Includes proper threshold transformation (negate and reverse).

library(jsonlite)
library(stringr)

#' Parse Mplus bifactor model output
#'
#' @param mplus_path Path to Mplus output file
#' @return List with parsed factor loadings and thresholds
parse_mplus_bifactor <- function(mplus_path = "temp/archive_2025/bifactor5e.txt") {

  cat("=== Parsing Mplus Bifactor Model Output ===\n")
  cat("Loading Mplus output from:", mplus_path, "\n")

  # Read Mplus output
  mplus_lines <- readLines(mplus_path)

  cat("Found", length(mplus_lines), "lines in Mplus output\n")

  # Initialize storage
  factor_loadings <- list()
  thresholds <- list()

  # Define factor names
  factors <- c("eat", "sle", "soc", "int", "ext", "gen")

  cat("\nParsing factor loadings...\n")

  # Parse factor loadings
  for (factor in factors) {
    # Pattern: factor BY ps###*loading
    pattern <- paste0(factor, "\\s+BY\\s+(ps\\d+)\\*([\\d\\.\\-]+)")
    matches <- str_match_all(mplus_lines, pattern)

    for (line_matches in matches) {
      if (nrow(line_matches) > 0) {
        for (i in 1:nrow(line_matches)) {
          item <- line_matches[i, 2]  # ps###
          loading <- as.numeric(line_matches[i, 3])

          # Initialize item if not exists
          if (is.null(factor_loadings[[item]])) {
            factor_loadings[[item]] <- list()
          }

          # Store factor loading
          factor_loadings[[item]][[factor]] <- loading
          cat("Found", factor, "loading for", item, ":", loading, "\n")
        }
      }
    }
  }

  cat("\nParsing thresholds...\n")

  # Parse thresholds
  # Pattern: [ ps###$N*value ]
  threshold_pattern <- "\\[\\s+(ps\\d+)\\$(\\d+)\\*([\\d\\.\\-]+)\\s*\\]"
  threshold_matches <- str_match_all(paste(mplus_lines, collapse = "\n"), threshold_pattern)

  for (line_matches in threshold_matches) {
    if (nrow(line_matches) > 0) {
      for (i in 1:nrow(line_matches)) {
        item <- line_matches[i, 2]      # ps###
        threshold_num <- as.numeric(line_matches[i, 3])  # threshold number
        threshold_val <- as.numeric(line_matches[i, 4])  # threshold value

        # Initialize item if not exists
        if (is.null(thresholds[[item]])) {
          thresholds[[item]] <- list()
        }

        # Store threshold
        thresholds[[item]][[paste0("t", threshold_num)]] <- threshold_val
        cat("Found threshold", threshold_num, "for", item, ":", threshold_val, "\n")
      }
    }
  }

  cat("\nParsing complete.\n")
  cat("Items with factor loadings:", length(factor_loadings), "\n")
  cat("Items with thresholds:", length(thresholds), "\n")

  return(list(
    factor_loadings = factor_loadings,
    thresholds = thresholds
  ))
}

#' Transform thresholds to array format
#'
#' @param threshold_list List of thresholds for an item
#' @return Numeric vector of transformed thresholds in order
transform_thresholds <- function(threshold_list) {

  if (length(threshold_list) == 0) {
    return(numeric(0))
  }

  # Extract threshold values in order (t1, t2, t3, ...)
  threshold_names <- names(threshold_list)
  threshold_order <- order(as.numeric(str_extract(threshold_names, "\\d+")))
  ordered_thresholds <- unlist(threshold_list)[threshold_order]

  # Transform: negate values and sort to ensure increasing order
  negated_thresholds <- -ordered_thresholds

  # Sort to ensure threshold[1] < threshold[2] < threshold[3], etc.
  sorted_thresholds <- sort(negated_thresholds)

  return(sorted_thresholds)
}

#' Convert factor loadings to factors and loadings arrays
#'
#' @param factor_loading_list List of factor loadings for an item
#' @return List with factors and loadings arrays
convert_factor_loadings <- function(factor_loading_list) {

  if (length(factor_loading_list) == 0) {
    return(list(factors = list(), loadings = list()))
  }

  # Extract factors and loadings
  factors <- names(factor_loading_list)
  loadings <- unlist(factor_loading_list)

  # Order: general factor first, then specific factors
  factor_order <- c("gen", setdiff(factors, "gen"))
  factor_order <- factor_order[factor_order %in% factors]

  ordered_loadings <- loadings[factor_order]

  return(list(
    factors = as.list(factor_order),
    loadings = as.list(ordered_loadings)
  ))
}

#' Update codebook with bifactor IRT parameters
#'
#' @param codebook_path Path to codebook JSON
#' @param mplus_data Parsed Mplus data
#' @return Updated codebook object
update_codebook_with_bifactor_irt <- function(codebook_path = "codebook/data/codebook.json",
                                              mplus_data) {

  cat("Loading codebook from:", codebook_path, "\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  cat("Codebook loaded with", length(codebook$items), "items\n")

  # Track updates
  updated_count <- 0
  changed_study_count <- 0

  # Process each item in the parsed data
  for (ps_item in names(mplus_data$factor_loadings)) {

    # Find corresponding item in codebook
    found_item <- FALSE
    codebook_item_id <- NULL

    for (id in names(codebook$items)) {
      item <- codebook$items[[id]]
      if (!is.null(item$lexicons$equate) &&
          toupper(item$lexicons$equate) == toupper(ps_item)) {
        found_item <- TRUE
        codebook_item_id <- id
        break
      }
    }

    if (found_item) {
      cat("\nProcessing", ps_item, "(", codebook_item_id, ")\n")

      # Convert factor loadings
      factor_data <- convert_factor_loadings(mplus_data$factor_loadings[[ps_item]])

      # Transform thresholds
      threshold_data <- transform_thresholds(mplus_data$thresholds[[ps_item]])

      # Check if GSED_PF exists and change to NE22
      if (!is.null(codebook$items[[codebook_item_id]]$psychometric$irt_parameters$GSED_PF)) {
        # Remove GSED_PF and add NE22
        codebook$items[[codebook_item_id]]$psychometric$irt_parameters$GSED_PF <- NULL
        changed_study_count <- changed_study_count + 1
        cat("  Changed GSED_PF to NE22\n")
      }

      # Update NE22 IRT parameters
      codebook$items[[codebook_item_id]]$psychometric$irt_parameters$NE22 <- list(
        factors = factor_data$factors,
        loadings = factor_data$loadings,
        thresholds = threshold_data,
        constraints = list()
      )

      cat("  Factors:", paste(factor_data$factors, collapse = ", "), "\n")
      cat("  Loadings:", paste(sprintf("%.5f", unlist(factor_data$loadings)), collapse = ", "), "\n")
      cat("  Thresholds:", paste(sprintf("%.5f", unlist(threshold_data)), collapse = ", "), "\n")

      updated_count <- updated_count + 1

    } else {
      cat("⚠ Item", ps_item, "not found in codebook\n")
    }
  }

  cat("\nUpdate Summary:\n")
  cat("- PS items updated with bifactor IRT parameters:", updated_count, "\n")
  cat("- Items changed from GSED_PF to NE22:", changed_study_count, "\n")

  return(codebook)
}

#' Main function to update PS items with bifactor IRT parameters
#'
#' @param mplus_path Path to Mplus bifactor output
#' @param codebook_path Path to codebook JSON
#' @param output_path Path to save updated codebook (defaults to input path)
update_ps_bifactor_irt <- function(mplus_path = "temp/archive_2025/bifactor5e.txt",
                                   codebook_path = "codebook/data/codebook.json",
                                   output_path = NULL) {

  if (is.null(output_path)) {
    output_path <- codebook_path
  }

  cat("=== Updating PS Items with Bifactor IRT Parameters ===\n")

  # Step 1: Parse Mplus output
  mplus_data <- parse_mplus_bifactor(mplus_path)

  # Step 2: Update codebook
  updated_codebook <- update_codebook_with_bifactor_irt(codebook_path, mplus_data)

  # Step 3: Save updated codebook
  cat("\nSaving updated codebook to:", output_path, "\n")

  # Update metadata
  updated_codebook$metadata$generated_date <- as.character(Sys.time())
  updated_codebook$metadata$version <- "2.6"  # Increment version for bifactor IRT

  # Write JSON with proper formatting
  json_output <- toJSON(updated_codebook, pretty = TRUE, auto_unbox = TRUE)
  write(json_output, output_path)

  cat("Bifactor IRT parameter update complete!\n")

  return(output_path)
}

#' Verify bifactor IRT updates
#'
#' @param codebook_path Path to codebook JSON
verify_bifactor_irt_updates <- function(codebook_path = "codebook/data/codebook.json") {

  cat("=== Verifying Bifactor IRT Updates ===\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  ps_items_with_ne22 <- 0
  gsed_pf_remaining <- 0

  # Sample items for verification
  sample_items <- c("PS004", "PS033", "PS002", "PS049")

  cat("\nSample item verification:\n")

  for (id in names(codebook$items)) {
    item <- codebook$items[[id]]
    equate_id <- item$lexicons$equate

    if (!is.null(equate_id) && startsWith(equate_id, "PS")) {

      # Check for NE22 IRT parameters
      if (!is.null(item$psychometric$irt_parameters$NE22)) {
        ps_items_with_ne22 <- ps_items_with_ne22 + 1
      }

      # Check for remaining GSED_PF
      if (!is.null(item$psychometric$irt_parameters$GSED_PF)) {
        gsed_pf_remaining <- gsed_pf_remaining + 1
      }

      # Detailed verification for sample items
      if (equate_id %in% sample_items) {
        cat("\n", equate_id, ":\n")

        if (!is.null(item$psychometric$irt_parameters$NE22)) {
          ne22_params <- item$psychometric$irt_parameters$NE22
          cat("  Factors:", paste(ne22_params$factors, collapse = ", "), "\n")
          cat("  Loadings:", paste(sprintf("%.5f", unlist(ne22_params$loadings)), collapse = ", "), "\n")
          cat("  Thresholds:", paste(sprintf("%.5f", unlist(ne22_params$thresholds)), collapse = ", "), "\n")
          cat("  ✓ NE22 parameters populated\n")
        } else {
          cat("  ✗ No NE22 parameters found\n")
        }

        if (!is.null(item$psychometric$irt_parameters$GSED_PF)) {
          cat("  ⚠ GSED_PF still present\n")
        } else {
          cat("  ✓ GSED_PF removed\n")
        }
      }
    }
  }

  cat("\nOverall Summary:\n")
  cat("- PS items with NE22 IRT parameters:", ps_items_with_ne22, "\n")
  cat("- PS items with remaining GSED_PF:", gsed_pf_remaining, "\n")

  cat("\nVerification complete.\n")
}

# If running as script, execute main function
if (!interactive()) {
  update_ps_bifactor_irt()
  verify_bifactor_irt_updates()
}
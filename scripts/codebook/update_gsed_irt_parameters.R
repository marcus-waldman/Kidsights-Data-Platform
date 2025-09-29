#' Update GSED IRT Parameters in Codebook
#'
#' Script to add IRT parameter estimates from GSED calibrations to the codebook JSON
#' Parameters come from dscore::builtin_itembank with Rasch model:
#' - All items have unit loading (1.0)
#' - Threshold transformation: threshold = -tau
#' - Multiple calibrations per item (gsed2406, gsed2212, gsed1912, 293_0, gcdg, dutch)
#'
#' Structure: GSED → calibration_key → parameters

library(jsonlite)
library(dplyr)

#' Load GSED parameters from dscore package
#'
#' @return Data frame with GSED item parameters
load_gsed_parameters <- function() {

  cat("Loading GSED parameter estimates from dscore::builtin_itembank\n")

  if (!require("dscore", quietly = TRUE)) {
    cat("Installing dscore package...\n")
    install.packages("dscore")
    library(dscore)
  }

  # Load the built-in itembank
  itembank <- dscore::builtin_itembank

  cat("Found", nrow(itembank), "parameter estimates\n")
  cat("Unique items:", length(unique(itembank$item)), "\n")
  cat("Calibration keys:", paste(unique(itembank$key), collapse = ", "), "\n")

  return(itembank)
}

#' Transform GSED Rasch parameters
#'
#' @param tau Difficulty parameter from dscore
#' @param key Calibration key
#' @return List with factors, loadings, and thresholds
transform_gsed_params <- function(tau, key) {

  # Rasch model: unit loading
  loading <- 1.0

  # Transform threshold: -tau
  threshold <- -tau

  # Create description based on key
  description <- paste0("GSED calibration: ", key)

  return(list(
    factors = list("gsed"),
    loadings = list(loading),
    thresholds = list(threshold),
    constraints = list(),
    model_type = "rasch",
    description = description
  ))
}

#' Update codebook with GSED IRT parameters
#'
#' @param codebook_path Path to codebook JSON
#' @param gsed_params GSED parameters data frame from dscore
#' @return Updated codebook object
update_codebook_with_gsed <- function(codebook_path = "codebook/data/codebook.json",
                                      gsed_params) {

  cat("Loading codebook from:", codebook_path, "\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  cat("Codebook loaded with", length(codebook$items), "items\n")

  # Track updates
  updated_items <- 0
  total_calibrations <- 0
  not_found_items <- character(0)

  # Get unique GSED items
  unique_gsed_items <- unique(gsed_params$item)
  cat("Processing", length(unique_gsed_items), "unique GSED items from itembank\n")

  # Process each GSED item
  for (gsed_item_code in unique_gsed_items) {

    # Get all calibrations for this item
    item_calibrations <- gsed_params %>%
      dplyr::filter(item == gsed_item_code)

    # Find matching item in codebook by GSED lexicon
    found_item <- FALSE

    for (codebook_item_id in names(codebook$items)) {
      item <- codebook$items[[codebook_item_id]]

      # Check if this item has the matching GSED lexicon
      if (!is.null(item$lexicons$gsed) && item$lexicons$gsed == gsed_item_code) {

        # Validate that this item includes GSED in its studies
        if (!"GSED" %in% item$studies) {
          cat("Warning: Item", codebook_item_id, "(", gsed_item_code, ") does not include GSED in studies\n")
          found_item <- TRUE
          break
        }

        # Initialize GSED IRT parameters - replace any existing structure
        # This removes the template structure (factors: [], loadings: [], etc.)
        codebook$items[[codebook_item_id]]$psychometric$irt_parameters$GSED <- list()

        # Add each calibration as a separate key
        for (i in 1:nrow(item_calibrations)) {
          calibration_key <- item_calibrations$key[i]
          tau_value <- item_calibrations$tau[i]

          # Transform parameters
          calibration_params <- transform_gsed_params(tau_value, calibration_key)

          # Store under calibration key
          codebook$items[[codebook_item_id]]$psychometric$irt_parameters$GSED[[calibration_key]] <- calibration_params

          total_calibrations <- total_calibrations + 1
        }

        cat("Updated", codebook_item_id, "(GSED:", gsed_item_code, ") -", nrow(item_calibrations), "calibrations\n")

        updated_items <- updated_items + 1
        found_item <- TRUE
        break
      }
    }

    if (!found_item) {
      not_found_items <- c(not_found_items, gsed_item_code)
    }
  }

  cat("\nUpdate Summary:\n")
  cat("- GSED items updated:", updated_items, "\n")
  cat("- Total calibrations added:", total_calibrations, "\n")
  cat("- Average calibrations per item:", round(total_calibrations / updated_items, 2), "\n")
  cat("- Items not found in codebook:", length(not_found_items), "\n")

  if (length(not_found_items) > 0 && length(not_found_items) <= 20) {
    cat("Items not found:", paste(not_found_items, collapse = ", "), "\n")
  } else if (length(not_found_items) > 20) {
    cat("Items not found (first 20):", paste(head(not_found_items, 20), collapse = ", "), "\n")
    cat("... and", length(not_found_items) - 20, "more\n")
  }

  return(codebook)
}

#' Main function to update GSED IRT parameters
#'
#' @param codebook_path Path to codebook JSON
#' @param output_path Path to save updated codebook (defaults to input path)
update_gsed_irt_parameters <- function(codebook_path = "codebook/data/codebook.json",
                                       output_path = NULL) {

  if (is.null(output_path)) {
    output_path <- codebook_path
  }

  cat("=== Updating GSED IRT Parameters ===\n")

  # Step 1: Load GSED parameters from dscore
  gsed_params <- load_gsed_parameters()

  # Step 2: Update codebook
  updated_codebook <- update_codebook_with_gsed(codebook_path, gsed_params)

  # Step 3: Save updated codebook
  cat("\nSaving updated codebook to:", output_path, "\n")

  # Update metadata
  updated_codebook$metadata$generated_date <- as.character(Sys.time())
  updated_codebook$metadata$version <- "3.0"  # Increment version for GSED parameters
  updated_codebook$metadata$previous_version <- "2.9"
  updated_codebook$metadata$gsed_parameters_added <- as.character(Sys.time())
  updated_codebook$metadata$gsed_source <- "dscore::builtin_itembank"

  # Write JSON with proper formatting
  json_output <- toJSON(updated_codebook, pretty = TRUE, auto_unbox = TRUE)
  write(json_output, output_path)

  cat("GSED IRT parameter update complete!\n")

  return(output_path)
}

#' Verify GSED IRT updates
#'
#' @param codebook_path Path to codebook JSON
verify_gsed_irt_updates <- function(codebook_path = "codebook/data/codebook.json") {

  cat("=== Verifying GSED IRT Updates ===\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  gsed_items_count <- 0
  calibration_counts <- list()
  multi_calibration_items <- 0

  # Sample items for verification
  sample_codes <- c("cromoc009", "cromoc005", "croclc007")

  cat("\nSample item verification:\n")

  for (id in names(codebook$items)) {
    item <- codebook$items[[id]]
    gsed_code <- item$lexicons$gsed

    if (!is.null(gsed_code)) {

      # Check for GSED IRT parameters
      if (!is.null(item$psychometric$irt_parameters$GSED)) {
        gsed_items_count <- gsed_items_count + 1

        # Count calibrations for this item
        n_calibrations <- length(item$psychometric$irt_parameters$GSED)

        if (n_calibrations > 1) {
          multi_calibration_items <- multi_calibration_items + 1
        }

        # Track calibration distribution
        cal_key <- as.character(n_calibrations)
        if (is.null(calibration_counts[[cal_key]])) {
          calibration_counts[[cal_key]] <- 0
        }
        calibration_counts[[cal_key]] <- calibration_counts[[cal_key]] + 1
      }

      # Detailed verification for sample items
      if (gsed_code %in% sample_codes) {
        cat("\n", gsed_code, "(", id, "):\n")

        if (!is.null(item$psychometric$irt_parameters$GSED)) {
          gsed_cals <- item$psychometric$irt_parameters$GSED

          for (cal_key in names(gsed_cals)) {
            cal <- gsed_cals[[cal_key]]
            cat("  ", cal_key, ": loading=", unlist(cal$loadings),
                ", threshold=", sprintf("%.3f", unlist(cal$thresholds)), "\n", sep = "")
          }
        }
      }
    }
  }

  cat("\nOverall Summary:\n")
  cat("- GSED items with parameters:", gsed_items_count, "\n")
  cat("- Items with multiple calibrations:", multi_calibration_items, "\n")

  cat("\nCalibration count distribution:\n")
  for (n_cal in sort(as.numeric(names(calibration_counts)))) {
    cat("  ", n_cal, "calibration(s):", calibration_counts[[as.character(n_cal)]], "items\n")
  }

  cat("\nExpected values:\n")
  cat("- GSED items in codebook: ~132\n")
  cat("- Most items have 3 calibrations (gsed2406, gsed2212, gsed1912)\n")

  cat("\nVerification complete.\n")
}

# If running as script, execute main function
if (!interactive()) {
  update_gsed_irt_parameters()
  verify_gsed_irt_updates()
}
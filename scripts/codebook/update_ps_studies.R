#' Update PS Items Studies and Reverse Coding
#'
#' Script to correct the studies field for psychosocial items and set
#' reverse coding for PS033. All PS items except PS033 should show
#' studies as ["NE25", "NE22", "NE20"]. PS033 should only show
#' ["NE22", "NE20"] and have reverse=true.

library(jsonlite)

#' Update PS items with correct studies and reverse coding
#'
#' @param codebook_path Path to codebook JSON file
#' @param output_path Path to save updated codebook (defaults to input path)
#' @return Path to updated codebook
update_ps_studies <- function(codebook_path = "codebook/data/codebook.json",
                             output_path = NULL) {

  if (is.null(output_path)) {
    output_path <- codebook_path
  }

  cat("=== Updating PS Items Studies and Reverse Coding ===\n")
  cat("Loading codebook from:", codebook_path, "\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  cat("Codebook loaded with", length(codebook$items), "items\n")

  # Track updates
  updated_studies_count <- 0
  updated_reverse_count <- 0

  # Process each item
  for (id in names(codebook$items)) {
    item <- codebook$items[[id]]
    equate_id <- item$lexicons$equate

    # Check if this is a PS item
    if (!is.null(equate_id) && length(equate_id) > 0 && startsWith(equate_id, "PS")) {

      if (equate_id == "PS033") {
        # PS033 special case: NE22, NE20 only and reverse=true
        codebook$items[[id]]$studies <- list("NE22", "NE20")
        codebook$items[[id]]$scoring$reverse <- TRUE

        # Update domain studies to match
        if (!is.null(codebook$items[[id]]$domains$kidsights)) {
          codebook$items[[id]]$domains$kidsights$studies <- list("NE22", "NE20")
        }

        cat("Updated PS033 with studies: NE22, NE20 and reverse: TRUE\n")
        updated_studies_count <- updated_studies_count + 1
        updated_reverse_count <- updated_reverse_count + 1

      } else {
        # All other PS items: NE25, NE22, NE20
        codebook$items[[id]]$studies <- list("NE25", "NE22", "NE20")

        # Update domain studies to match
        if (!is.null(codebook$items[[id]]$domains$kidsights)) {
          codebook$items[[id]]$domains$kidsights$studies <- list("NE25", "NE22", "NE20")
        }

        cat("Updated", equate_id, "with studies: NE25, NE22, NE20\n")
        updated_studies_count <- updated_studies_count + 1
      }
    }
  }

  cat("\nUpdate Summary:\n")
  cat("- PS items with updated studies:", updated_studies_count, "\n")
  cat("- PS items with updated reverse coding:", updated_reverse_count, "\n")

  # Update metadata
  cat("\nUpdating metadata to version 2.5\n")
  codebook$metadata$version <- "2.5"
  codebook$metadata$generated_date <- as.character(Sys.time())

  # Save updated codebook
  cat("Saving updated codebook to:", output_path, "\n")
  json_output <- toJSON(codebook, pretty = TRUE, auto_unbox = TRUE)
  write(json_output, output_path)

  cat("PS studies and reverse coding update complete!\n")
  return(output_path)
}

#' Verify PS items updates
#'
#' @param codebook_path Path to codebook JSON file
verify_ps_updates <- function(codebook_path = "codebook/data/codebook.json") {

  cat("=== Verifying PS Items Updates ===\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  ps_items <- list()
  ps033_found <- FALSE

  # Check all PS items
  for (id in names(codebook$items)) {
    item <- codebook$items[[id]]
    equate_id <- item$lexicons$equate

    if (!is.null(equate_id) && length(equate_id) > 0 && startsWith(equate_id, "PS")) {
      studies <- paste(item$studies, collapse = ", ")
      reverse <- item$scoring$reverse

      if (equate_id == "PS033") {
        ps033_found <- TRUE
        cat("PS033 - Studies:", studies, "Reverse:", reverse, "\n")

        # Verify PS033 expectations
        expected_studies <- c("NE22", "NE20")
        actual_studies <- unlist(item$studies)
        if (setequal(actual_studies, expected_studies) && reverse == TRUE) {
          cat("✓ PS033 correctly configured\n")
        } else {
          cat("✗ PS033 incorrectly configured\n")
        }
      } else {
        # Sample a few other PS items for verification
        if (length(ps_items) < 3) {
          ps_items[[equate_id]] <- list(studies = studies, reverse = reverse)
        }
      }
    }
  }

  cat("\nSample PS items verification:\n")
  for (item_id in names(ps_items)) {
    item_info <- ps_items[[item_id]]
    cat(item_id, "- Studies:", item_info$studies, "Reverse:", item_info$reverse, "\n")

    # Verify other PS items expectations
    expected_studies <- c("NE25", "NE22", "NE20")
    actual_studies <- unlist(strsplit(item_info$studies, ", "))
    if (setequal(actual_studies, expected_studies) && item_info$reverse == FALSE) {
      cat("✓", item_id, "correctly configured\n")
    } else {
      cat("✗", item_id, "incorrectly configured\n")
    }
  }

  if (!ps033_found) {
    cat("⚠ PS033 not found in codebook\n")
  }

  cat("\nVerification complete.\n")
}

# If running as script, execute main function
if (!interactive()) {
  update_ps_studies()
  verify_ps_updates()
}
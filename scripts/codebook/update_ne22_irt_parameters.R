#' Update NE22 IRT Parameters in Codebook
#'
#' Script to add IRT parameter estimates from NE22 study to the codebook JSON
#' Parameters come from ne22_kidsights-parameter-vlaues.csv with:
#' - a1 = loading parameter
#' - d1, d2, d3, etc. = threshold parameters (ordered by suffix)
#' - Unidimensional model with factor "kidsights"

library(tidyverse)
library(jsonlite)

#' Load and process NE22 parameter CSV
#'
#' @param csv_path Path to the CSV file
#' @return Data frame with structured parameters by item
load_ne22_parameters <- function(csv_path = "temp/archive_2025/ne22_kidsights-parameter-vlaues.csv") {

  cat("Loading NE22 parameter estimates from:", csv_path, "\n")

  # Read CSV file
  params_raw <- read_csv(csv_path, show_col_types = FALSE)

  cat("Found", nrow(params_raw), "parameter estimates\n")

  # Process parameters by item
  params_structured <- params_raw %>%
    group_by(item) %>%
    summarise(
      # Extract loading (a1 parameter)
      loading = {
        a_vals <- value[name == "a1"]
        if (length(a_vals) > 0) a_vals[1] else NA_real_
      },

      # Extract thresholds (d1, d2, d3, etc.) in order
      thresholds = list({
        d_rows <- which(str_starts(name, "d"))
        if (length(d_rows) > 0) {
          d_data <- data.frame(
            name = name[d_rows],
            value = value[d_rows],
            stringsAsFactors = FALSE
          )
          # Sort by numeric suffix (d1, d2, d3, etc.)
          d_data$threshold_order <- as.numeric(str_extract(d_data$name, "\\d+"))
          d_data <- d_data[order(d_data$threshold_order), ]
          d_data$value
        } else {
          numeric(0)
        }
      }),

      # Count parameters for validation
      n_loadings = sum(str_starts(name, "a")),
      n_thresholds = sum(str_starts(name, "d")),

      .groups = "drop"
    )

  cat("Processed parameters for", nrow(params_structured), "unique items\n")

  return(params_structured)
}

#' Update codebook with NE22 IRT parameters
#'
#' @param codebook_path Path to codebook JSON
#' @param ne22_params Structured NE22 parameters data frame
#' @return Updated codebook object
update_codebook_with_ne22 <- function(codebook_path = "codebook/data/codebook.json",
                                      ne22_params) {

  cat("Loading codebook from:", codebook_path, "\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  cat("Codebook loaded with", length(codebook$items), "items\n")

  # Track updates
  updated_count <- 0
  not_found_items <- character(0)

  # Process each NE22 parameter item (using kidsight lexicon)
  for (i in 1:nrow(ne22_params)) {
    kidsight_item_id <- ne22_params$item[i]
    loading_val <- ne22_params$loading[i]
    threshold_vals <- ne22_params$thresholds[[i]]

    # Find matching item in codebook by kidsight lexicon
    found_item <- FALSE

    for (codebook_item_id in names(codebook$items)) {
      item <- codebook$items[[codebook_item_id]]

      # Check if this item has the matching kidsight lexicon
      if (!is.null(item$lexicons$kidsight) && item$lexicons$kidsight == kidsight_item_id) {

        # Validate that this item includes NE22 in its studies
        if (!"NE22" %in% item$studies) {
          cat("Warning: Item", codebook_item_id, "(", kidsight_item_id, ") does not include NE22 in studies:", paste(item$studies, collapse = ", "), "\n")
          found_item <- TRUE  # Mark as found but skip update
          break
        }

        # Update NE22 IRT parameters
        if (is.null(item$psychometric$irt_parameters$NE22)) {
          cat("Warning: Item", codebook_item_id, "missing NE22 IRT parameter structure\n")
          next
        }

        # Update parameters
        codebook$items[[codebook_item_id]]$psychometric$irt_parameters$NE22$factors <- list("kidsights")
        codebook$items[[codebook_item_id]]$psychometric$irt_parameters$NE22$loadings <- list(loading_val)
        codebook$items[[codebook_item_id]]$psychometric$irt_parameters$NE22$thresholds <- as.list(threshold_vals)

        cat("Updated", codebook_item_id, "(Kidsight:", kidsight_item_id, ") - Loading:", loading_val,
            "Thresholds:", length(threshold_vals), "\n")

        updated_count <- updated_count + 1
        found_item <- TRUE
        break
      }
    }

    if (!found_item) {
      not_found_items <- c(not_found_items, kidsight_item_id)
    }
  }

  cat("\nUpdate Summary:\n")
  cat("- Items updated:", updated_count, "\n")
  cat("- Items not found in codebook:", length(not_found_items), "\n")

  if (length(not_found_items) > 0) {
    cat("Items not found:", paste(head(not_found_items, 10), collapse = ", "), "\n")
    if (length(not_found_items) > 10) {
      cat("... and", length(not_found_items) - 10, "more\n")
    }
  }

  return(codebook)
}

#' Main function to update NE22 IRT parameters
#'
#' @param csv_path Path to NE22 parameter CSV
#' @param codebook_path Path to codebook JSON
#' @param output_path Path to save updated codebook (defaults to input path)
update_ne22_irt_parameters <- function(csv_path = "temp/archive_2025/ne22_kidsights-parameter-vlaues.csv",
                                       codebook_path = "codebook/data/codebook.json",
                                       output_path = NULL) {

  if (is.null(output_path)) {
    output_path <- codebook_path
  }

  cat("=== Updating NE22 IRT Parameters ===\n")

  # Step 1: Load and process parameters
  ne22_params <- load_ne22_parameters(csv_path)

  # Step 2: Update codebook
  updated_codebook <- update_codebook_with_ne22(codebook_path, ne22_params)

  # Step 3: Save updated codebook
  cat("\nSaving updated codebook to:", output_path, "\n")

  # Update metadata
  updated_codebook$metadata$generated_date <- as.character(Sys.time())
  updated_codebook$metadata$version <- "2.1"  # Increment version for NE22 parameters

  # Write JSON with proper formatting
  json_output <- toJSON(updated_codebook, pretty = TRUE, auto_unbox = TRUE)
  write(json_output, output_path)

  cat("NE22 IRT parameter update complete!\n")

  return(output_path)
}

# If running as script, execute main function
if (!interactive()) {
  update_ne22_irt_parameters()
}
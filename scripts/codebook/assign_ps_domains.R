#' Assign Kidsights Domains to Psychosocial Items
#'
#' Script to assign multiple domains to PS items based on bifactor model results
#' from psychosocial-items CSV. Each column with value '1' indicates the item
#' belongs to that specific psychosocial domain.

library(tidyverse)
library(jsonlite)

#' Load and process psychosocial domain assignments from CSV
#'
#' @param csv_path Path to the psychosocial items CSV file
#' @return Data frame with domain assignments
load_ps_domain_assignments <- function(csv_path = "tmp/psychosocial-items - Sheet1.csv") {

  cat("Loading psychosocial domain assignments from:", csv_path, "\n")

  # Read CSV file
  ps_data <- read_csv(csv_path, show_col_types = FALSE)

  cat("Found", nrow(ps_data), "PS items with domain assignments\n")

  # Define domain mappings
  domain_mappings <- list(
    gen = "psychosocial_problems_general",
    eat = "psychosocial_problems_feeding",
    sle = "psychosocial_problems_sleeping",
    soc = "psychosocial_problems_socialemotional",
    int = "psychosocial_problems_internalizing",
    ext = "psychosocial_problems_externalizing"
  )

  # Process each row to create domain assignments
  ps_assignments <- list()

  for (i in 1:nrow(ps_data)) {
    row <- ps_data[i, ]
    assigned_domains <- character(0)

    # Check each domain column
    for (col in names(domain_mappings)) {
      if (!is.na(row[[col]]) && row[[col]] == 1) {
        assigned_domains <- c(assigned_domains, domain_mappings[[col]])
      }
    }

    ps_assignments[[i]] <- list(
      Item = row$Item,
      Stem = row$Stem,
      domains = assigned_domains
    )
  }

  # Convert to data frame
  ps_assignments <- tibble(
    Item = sapply(ps_assignments, function(x) x$Item),
    Stem = sapply(ps_assignments, function(x) x$Stem),
    domains = lapply(ps_assignments, function(x) x$domains)
  )

  cat("Processed domain assignments for", nrow(ps_assignments), "items\n")

  return(ps_assignments)
}

#' Update codebook with psychosocial domain assignments
#'
#' @param codebook_path Path to codebook JSON
#' @param ps_assignments Data frame with PS domain assignments
#' @return Updated codebook object
update_codebook_with_ps_domains <- function(codebook_path = "codebook/data/codebook.json",
                                           ps_assignments) {

  cat("Loading codebook from:", codebook_path, "\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  cat("Codebook loaded with", length(codebook$items), "items\n")

  # Track updates
  updated_count <- 0
  added_count <- 0

  # Process each PS item assignment
  for (i in 1:nrow(ps_assignments)) {
    ps_item_id <- ps_assignments$Item[i]
    ps_stem <- ps_assignments$Stem[i]
    ps_domains <- ps_assignments$domains[[i]]

    # Find if item exists in codebook
    found_item <- FALSE
    codebook_item_id <- NULL

    for (id in names(codebook$items)) {
      item <- codebook$items[[id]]
      if (!is.null(item$lexicons$equate) && item$lexicons$equate == ps_item_id) {
        found_item <- TRUE
        codebook_item_id <- id
        break
      }
    }

    if (found_item) {
      # Update existing item
      if (length(ps_domains) == 0) {
        # No domains assigned - keep current or set to empty
        cat("Item", ps_item_id, "(", codebook_item_id, ") has no domain assignments\n")
      } else if (length(ps_domains) == 1) {
        # Single domain - use string value
        codebook$items[[codebook_item_id]]$domains$kidsights$value <- ps_domains[1]
        cat("Updated", ps_item_id, "(", codebook_item_id, ") with single domain:", ps_domains[1], "\n")
      } else {
        # Multiple domains - use array
        codebook$items[[codebook_item_id]]$domains$kidsights$value <- as.list(ps_domains)
        cat("Updated", ps_item_id, "(", codebook_item_id, ") with", length(ps_domains), "domains:", paste(ps_domains, collapse = ", "), "\n")
      }
      updated_count <- updated_count + 1

    } else {
      # Add new item
      new_id <- max(sapply(codebook$items, function(x) x$id), na.rm = TRUE) + 1

      new_item <- list(
        id = as.integer(new_id),
        studies = list("GSED_PF"),

        lexicons = list(
          equate = ps_item_id,
          ne25 = ps_item_id
        ),

        domains = list(
          kidsights = list(
            value = if (length(ps_domains) == 0) {
              character(0)
            } else if (length(ps_domains) == 1) {
              ps_domains[1]
            } else {
              as.list(ps_domains)
            },
            studies = list("GSED_PF")
          )
        ),

        age_range = list(
          min_months = 0,
          max_months = 60,
          note = "Early childhood developmental assessment"
        ),

        content = list(
          stems = list(
            combined = ps_stem
          ),
          response_options = list(
            gsed_pf = "ps_frequency"
          )
        ),

        scoring = list(
          reverse = FALSE,
          equate_group = "GSED_PF"
        ),

        psychometric = list(
          calibration_item = FALSE,
          irt_parameters = list(
            GSED_PF = list(
              factors = list(),
              loadings = list(),
              thresholds = list(),
              constraints = list()
            )
          )
        ),

        metadata = list(
          tier_followup = NA,
          item_order = NA,
          last_modified = as.character(Sys.Date()),
          type = "psychosocial",
          notes = "Added from bifactor domain assignment"
        )
      )

      codebook$items[[ps_item_id]] <- new_item

      if (length(ps_domains) == 0) {
        cat("Added new item", ps_item_id, "with no domain assignments\n")
      } else {
        cat("Added new item", ps_item_id, "with", length(ps_domains), "domains:", paste(ps_domains, collapse = ", "), "\n")
      }
      added_count <- added_count + 1
    }
  }

  cat("\nUpdate Summary:\n")
  cat("- Existing items updated:", updated_count, "\n")
  cat("- New items added:", added_count, "\n")

  return(codebook)
}

#' Main function to assign PS domains
#'
#' @param csv_path Path to psychosocial items CSV
#' @param codebook_path Path to codebook JSON
#' @param output_path Path to save updated codebook (defaults to input path)
assign_ps_domains <- function(csv_path = "tmp/psychosocial-items - Sheet1.csv",
                             codebook_path = "codebook/data/codebook.json",
                             output_path = NULL) {

  if (is.null(output_path)) {
    output_path <- codebook_path
  }

  cat("=== Assigning Psychosocial Domains ===\n")

  # Step 1: Load domain assignments
  ps_assignments <- load_ps_domain_assignments(csv_path)

  # Step 2: Update codebook
  updated_codebook <- update_codebook_with_ps_domains(codebook_path, ps_assignments)

  # Step 3: Save updated codebook
  cat("\nSaving updated codebook to:", output_path, "\n")

  # Update metadata
  updated_codebook$metadata$generated_date <- as.character(Sys.time())
  updated_codebook$metadata$version <- "2.4"  # Increment version for PS domain assignments

  # Write JSON with proper formatting
  json_output <- toJSON(updated_codebook, pretty = TRUE, auto_unbox = TRUE)
  write(json_output, output_path)

  cat("PS domain assignment complete!\n")

  return(output_path)
}

# If running as script, execute main function
if (!interactive()) {
  assign_ps_domains()
}
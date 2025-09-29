#' Update CREDI IRT Parameters in Codebook
#'
#' Script to add IRT parameter estimates from CREDI study to the codebook JSON
#' Parameters come from data/credi-mest_df.csv with two scoring procedures:
#' - Short Form (SF): 62 items, unidimensional model with factor "credi_overall"
#' - Long Form (LF): 117 items, multidimensional model with factors mot, cog, lang, sem
#'
#' Parameter transformations:
#' - SF threshold = -delta / alpha (converts difficulty to threshold)
#' - LF threshold = -tau (simple negation)
#' - SF loading = alpha (discrimination)
#' - LF loadings = MOT, COG, LANG, SEM (non-zero values only)

library(jsonlite)

#' Load and process CREDI parameter CSV
#'
#' @param csv_path Path to the CSV file
#' @return Data frame with structured parameters by item
load_credi_parameters <- function(csv_path = "data/credi-mest_df.csv") {

  cat("Loading CREDI parameter estimates from:", csv_path, "\n")

  if (!require("readr", quietly = TRUE)) {
    install.packages("readr")
    library(readr)
  }

  # Read CSV file
  params_raw <- readr::read_csv(csv_path, show_col_types = FALSE)

  cat("Found", nrow(params_raw), "CREDI items with parameters\n")

  return(params_raw)
}

#' Transform Long Form parameters
#'
#' @param tau Difficulty parameter from CSV
#' @param mot MOT factor loading
#' @param cog COG factor loading
#' @param lang LANG factor loading
#' @param sem SEM factor loading
#' @return List with factors, loadings, and thresholds
transform_long_form_params <- function(tau, mot, cog, lang, sem) {

  # Collect non-zero factor loadings
  factor_names <- c("mot", "cog", "lang", "sem")
  factor_loadings <- c(mot, cog, lang, sem)

  # Keep only non-zero loadings
  non_zero_idx <- factor_loadings != 0

  if (sum(non_zero_idx) == 0) {
    # No factors - this shouldn't happen but handle gracefully
    return(list(
      factors = list(),
      loadings = list(),
      thresholds = list(),
      constraints = list()
    ))
  }

  selected_factors <- factor_names[non_zero_idx]
  selected_loadings <- factor_loadings[non_zero_idx]

  # Transform threshold: -tau
  threshold <- -tau

  return(list(
    factors = as.list(selected_factors),
    loadings = as.list(selected_loadings),
    thresholds = list(threshold),
    constraints = list(),
    model_type = "multidimensional",
    description = "CREDI-LF scoring (117-item, 4 factors: mot, cog, lang, sem)"
  ))
}

#' Transform Short Form parameters
#'
#' @param alpha Discrimination parameter from CSV
#' @param delta Difficulty parameter from CSV
#' @return List with factors, loadings, and thresholds
transform_short_form_params <- function(alpha, delta) {

  if (is.na(alpha) || is.na(delta)) {
    return(NULL)
  }

  # Transform threshold: -delta / alpha
  threshold <- -delta / alpha

  return(list(
    factors = list("credi_overall"),
    loadings = list(alpha),
    thresholds = list(threshold),
    constraints = list(),
    model_type = "unidimensional",
    description = "CREDI-SF scoring (62-item)"
  ))
}

#' Update codebook with CREDI IRT parameters
#'
#' @param codebook_path Path to codebook JSON
#' @param credi_params CREDI parameters data frame
#' @return Updated codebook object
update_codebook_with_credi <- function(codebook_path = "codebook/data/codebook.json",
                                       credi_params) {

  cat("Loading codebook from:", codebook_path, "\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  cat("Codebook loaded with", length(codebook$items), "items\n")

  # Track updates
  updated_count <- 0
  sf_count <- 0
  lf_count <- 0
  not_found_items <- character(0)

  # Process each CREDI parameter item
  for (i in 1:nrow(credi_params)) {
    credi_code <- credi_params$CREDI_code[i]

    # Skip items without CREDI codes
    if (is.na(credi_code)) {
      next
    }

    # Find matching item in codebook by CREDI lexicon
    found_item <- FALSE

    for (codebook_item_id in names(codebook$items)) {
      item <- codebook$items[[codebook_item_id]]

      # Check if this item has the matching CREDI lexicon
      if (!is.null(item$lexicons$credi) && item$lexicons$credi == credi_code) {

        # Validate that this item includes CREDI in its studies
        if (!"CREDI" %in% item$studies) {
          cat("Warning: Item", codebook_item_id, "(", credi_code, ") does not include CREDI in studies\n")
          found_item <- TRUE
          break
        }

        # Initialize CREDI IRT parameters if not present
        if (is.null(item$psychometric$irt_parameters$CREDI)) {
          codebook$items[[codebook_item_id]]$psychometric$irt_parameters$CREDI <- list()
        }

        # Process Long Form parameters (all items have these)
        lf_params <- transform_long_form_params(
          tau = credi_params$tau[i],
          mot = credi_params$MOT[i],
          cog = credi_params$COG[i],
          lang = credi_params$LANG[i],
          sem = credi_params$SEM[i]
        )

        codebook$items[[codebook_item_id]]$psychometric$irt_parameters$CREDI$long_form <- lf_params
        lf_count <- lf_count + 1

        # Process Short Form parameters (only if ShortForm == TRUE)
        if (credi_params$ShortForm[i]) {
          sf_params <- transform_short_form_params(
            alpha = credi_params$alpha[i],
            delta = credi_params$delta[i]
          )

          if (!is.null(sf_params)) {
            codebook$items[[codebook_item_id]]$psychometric$irt_parameters$CREDI$short_form <- sf_params
            sf_count <- sf_count + 1
          }
        }

        cat("Updated", codebook_item_id, "(CREDI:", credi_code, ")")
        if (credi_params$ShortForm[i]) {
          cat(" - SF + LF")
        } else {
          cat(" - LF only")
        }
        cat("\n")

        updated_count <- updated_count + 1
        found_item <- TRUE
        break
      }
    }

    if (!found_item && !is.na(credi_code)) {
      not_found_items <- c(not_found_items, credi_code)
    }
  }

  cat("\nUpdate Summary:\n")
  cat("- Items updated with CREDI IRT parameters:", updated_count, "\n")
  cat("- Items with Short Form (SF) parameters:", sf_count, "\n")
  cat("- Items with Long Form (LF) parameters:", lf_count, "\n")
  cat("- Items not found in codebook:", length(not_found_items), "\n")

  if (length(not_found_items) > 0) {
    cat("Items not found:", paste(head(not_found_items, 10), collapse = ", "), "\n")
    if (length(not_found_items) > 10) {
      cat("... and", length(not_found_items) - 10, "more\n")
    }
  }

  return(codebook)
}

#' Main function to update CREDI IRT parameters
#'
#' @param csv_path Path to CREDI parameter CSV
#' @param codebook_path Path to codebook JSON
#' @param output_path Path to save updated codebook (defaults to input path)
update_credi_irt_parameters <- function(csv_path = "data/credi-mest_df.csv",
                                        codebook_path = "codebook/data/codebook.json",
                                        output_path = NULL) {

  if (is.null(output_path)) {
    output_path <- codebook_path
  }

  cat("=== Updating CREDI IRT Parameters ===\n")

  # Step 1: Load and process parameters
  credi_params <- load_credi_parameters(csv_path)

  # Step 2: Update codebook
  updated_codebook <- update_codebook_with_credi(codebook_path, credi_params)

  # Step 3: Save updated codebook
  cat("\nSaving updated codebook to:", output_path, "\n")

  # Update metadata
  updated_codebook$metadata$generated_date <- as.character(Sys.time())
  updated_codebook$metadata$version <- "2.9"  # Increment version for CREDI parameters
  updated_codebook$metadata$previous_version <- "2.8.0"
  updated_codebook$metadata$credi_parameters_added <- as.character(Sys.time())

  # Write JSON with proper formatting
  json_output <- toJSON(updated_codebook, pretty = TRUE, auto_unbox = TRUE)
  write(json_output, output_path)

  cat("CREDI IRT parameter update complete!\n")

  return(output_path)
}

#' Verify CREDI IRT updates
#'
#' @param codebook_path Path to codebook JSON
verify_credi_irt_updates <- function(codebook_path = "codebook/data/codebook.json") {

  cat("=== Verifying CREDI IRT Updates ===\n")

  # Load codebook
  codebook <- fromJSON(codebook_path, simplifyVector = FALSE)

  credi_items_with_lf <- 0
  credi_items_with_sf <- 0
  multi_factor_items <- 0

  # Sample items for verification
  sample_codes <- c("LF4", "LF5", "LF19")

  cat("\nSample item verification:\n")

  for (id in names(codebook$items)) {
    item <- codebook$items[[id]]
    credi_code <- item$lexicons$credi

    if (!is.null(credi_code)) {

      # Check for CREDI IRT parameters
      if (!is.null(item$psychometric$irt_parameters$CREDI)) {

        # Check for Long Form
        if (!is.null(item$psychometric$irt_parameters$CREDI$long_form)) {
          credi_items_with_lf <- credi_items_with_lf + 1

          # Check for multi-factor
          lf <- item$psychometric$irt_parameters$CREDI$long_form
          if (length(lf$factors) > 1) {
            multi_factor_items <- multi_factor_items + 1
          }
        }

        # Check for Short Form
        if (!is.null(item$psychometric$irt_parameters$CREDI$short_form)) {
          credi_items_with_sf <- credi_items_with_sf + 1
        }
      }

      # Detailed verification for sample items
      if (credi_code %in% sample_codes) {
        cat("\n", credi_code, "(", id, "):\n")

        if (!is.null(item$psychometric$irt_parameters$CREDI$long_form)) {
          lf <- item$psychometric$irt_parameters$CREDI$long_form
          cat("  LF Factors:", paste(lf$factors, collapse = ", "), "\n")
          cat("  LF Loadings:", paste(sprintf("%.3f", unlist(lf$loadings)), collapse = ", "), "\n")
          cat("  LF Threshold:", sprintf("%.3f", unlist(lf$thresholds)), "\n")
        }

        if (!is.null(item$psychometric$irt_parameters$CREDI$short_form)) {
          sf <- item$psychometric$irt_parameters$CREDI$short_form
          cat("  SF Factor:", paste(sf$factors, collapse = ", "), "\n")
          cat("  SF Loading:", sprintf("%.3f", unlist(sf$loadings)), "\n")
          cat("  SF Threshold:", sprintf("%.3f", unlist(sf$thresholds)), "\n")
        }
      }
    }
  }

  cat("\nOverall Summary:\n")
  cat("- CREDI items with Long Form parameters:", credi_items_with_lf, "\n")
  cat("- CREDI items with Short Form parameters:", credi_items_with_sf, "\n")
  cat("- CREDI items with multiple factors:", multi_factor_items, "\n")

  cat("\nExpected values:\n")
  cat("- LF parameters: 117 items (all CREDI items)\n")
  cat("- SF parameters: 62 items (ShortForm=TRUE)\n")
  cat("- Multi-factor items: ~5 items\n")

  cat("\nVerification complete.\n")
}

# If running as script, execute main function
if (!interactive()) {
  update_credi_irt_parameters()
  verify_credi_irt_updates()
}
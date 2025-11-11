# =============================================================================
# Build Equate Table from Codebook
# =============================================================================
# Purpose: Extract jid and lex_equate mapping from codebook JSON
#          Compatible with write_syntax2 requirements
#
# Version: 1.0
# Created: November 2025
# =============================================================================

# Load required packages
library(dplyr)
library(purrr)
library(tibble)

#' Build Equate Table from Codebook JSON
#'
#' Extracts item ID (jid) and equate lexicon mapping from codebook.json
#' Returns data frame compatible with write_syntax2 function requirements.
#'
#' @param codebook_path Path to codebook.json file (default: "codebook/data/codebook.json")
#' @param verbose Logical, print progress messages (default: TRUE)
#'
#' @return Data frame with columns:
#'   - jid: Item ID (numeric, from codebook$items[[x]]$id)
#'   - lex_equate: Equate lexicon name (character, from codebook$items[[x]]$lexicons$equate)
#'   - lex_kidsights: Kidsights lexicon name (character, from codebook$items[[x]]$lexicons$kidsights)
#'
#' @details
#' The equate lexicon provides harmonized item names across studies (NE20, NE22, NE25, USA24, NSCH).
#' Items without an equate lexicon are excluded from the output (not used in calibration).
#'
#' @examples
#' # Load equate table
#' equate <- build_equate_table_from_codebook()
#'
#' # Check structure
#' head(equate)
#' #>   jid lex_equate lex_kidsights
#' #>   26  AA4        C020
#' #>   27  AA102      C023
#' #>   28  AA104      C026
#'
#' @export
build_equate_table_from_codebook <- function(
  codebook_path = "codebook/data/codebook.json",
  verbose = TRUE
) {

  if (verbose) {
    cat("\n", strrep("=", 70), "\n")
    cat("BUILDING EQUATE TABLE FROM CODEBOOK\n")
    cat(strrep("=", 70), "\n\n")
  }

  # Load codebook
  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook file not found: %s", codebook_path))
  }

  if (verbose) cat("Loading codebook...\n")
  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Extract items
  if (is.null(codebook$items) || length(codebook$items) == 0) {
    stop("Codebook does not contain 'items' field or it is empty")
  }

  if (verbose) {
    cat(sprintf("  Total items in codebook: %d\n\n", length(codebook$items)))
  }

  # Build equate table
  if (verbose) cat("Extracting jid and lexicons...\n")

  equate <- purrr::map_df(codebook$items, function(item) {

    # Extract jid (required)
    jid <- item$id
    if (is.null(jid)) {
      warning(sprintf("Item missing 'id' field, skipping: %s", item$item_name %||% "unknown"))
      return(NULL)
    }

    # Extract lexicons
    lex_equate <- item$lexicons$equate %||% NA_character_
    lex_kidsights <- item$lexicons$kidsights %||% NA_character_

    # Return tibble row
    tibble::tibble(
      jid = as.numeric(jid),
      lex_equate = as.character(lex_equate),
      lex_kidsights = as.character(lex_kidsights)
    )

  })

  # Filter out items without equate lexicon
  equate_original_count <- nrow(equate)
  equate <- equate[!is.na(equate$lex_equate) & equate$lex_equate != "", ]

  if (verbose) {
    cat(sprintf("  Items with jid: %d\n", equate_original_count))
    cat(sprintf("  Items with equate lexicon: %d\n", nrow(equate)))
    cat(sprintf("  Items excluded (no equate): %d\n\n", equate_original_count - nrow(equate)))
  }

  # Validate jid uniqueness
  if (any(duplicated(equate$jid))) {
    dup_jids <- equate$jid[duplicated(equate$jid)]
    warning(sprintf("Duplicate jid values found: %s", paste(dup_jids, collapse = ", ")))
  }

  # Validate lex_equate uniqueness
  if (any(duplicated(equate$lex_equate))) {
    dup_equate <- equate$lex_equate[duplicated(equate$lex_equate)]
    warning(sprintf("Duplicate lex_equate values found: %s", paste(dup_equate, collapse = ", ")))
  }

  # Sort by jid
  equate <- equate %>% dplyr::arrange(jid)

  if (verbose) {
    cat("[OK] Equate table built successfully\n")
    cat(sprintf("     Rows: %d\n", nrow(equate)))
    cat(sprintf("     JID range: %d to %d\n", min(equate$jid), max(equate$jid)))
    cat("\nFirst 5 items:\n")
    print(head(equate, 5))
    cat("\n")
  }

  return(equate)

}


#' Build Codebook DataFrame for write_syntax2
#'
#' Creates codebook_df structure required by write_syntax2 function.
#' Combines equate table with param_constraints from codebook.
#'
#' @param codebook Codebook list (from jsonlite::fromJSON)
#' @param equate Equate table (from build_equate_table_from_codebook)
#' @param scale_name Scale name to filter items (optional, NULL = all items)
#' @param instrument_filter Instrument name to filter items (default: "Kidsights Measurement Tool")
#'   Set to NULL to include all instruments
#'
#' @return Data frame with columns:
#'   - jid: Item ID (numeric)
#'   - lex_equate: Equate lexicon name (character)
#'   - param_constraints: Constraint specification (character, may be NA)
#'   - alpha_start: Discrimination starting value from NE25 (numeric, may be NA)
#'   - tau_start: Threshold starting values from NE25 (list of numeric vectors, may be NA)
#'
#' @examples
#' codebook <- jsonlite::fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)
#' equate <- build_equate_table_from_codebook()
#' codebook_df <- build_codebook_df(codebook, equate, scale_name = "kidsights")
#'
#' @export
build_codebook_df <- function(
  codebook,
  equate,
  scale_name = NULL,
  instrument_filter = "Kidsights Measurement Tool"
) {

  # Start with equate table
  codebook_df <- equate %>%
    dplyr::select(jid, lex_equate)

  # Build case-insensitive lookup: uppercase(lex_equate) → item_id
  equate_to_item_id <- list()
  for (item_id in names(codebook$items)) {
    lex_equate <- codebook$items[[item_id]]$lexicons$equate
    if (!is.null(lex_equate) && lex_equate != "") {
      equate_to_item_id[[toupper(lex_equate)]] <- item_id
    }
  }

  # Add param_constraints from codebook
  param_constraints_vec <- sapply(codebook_df$lex_equate, function(eq_name) {

    # Find item in codebook by equate name (case-insensitive)
    item_id <- equate_to_item_id[[toupper(eq_name)]]

    if (is.null(item_id)) {
      return(NA_character_)
    }

    item <- codebook$items[[item_id]]

    if (is.null(item)) {
      return(NA_character_)
    }

    # Extract param_constraints - check multiple locations in priority order:
    # 1. psychometric$param_constraints (top level, preferred)
    # 2. irt_parameters$NE25$param_constraints (nested, study-specific)
    # 3. Fall back to old "constraints" field name

    constraints <- item$psychometric$param_constraints

    if (is.null(constraints) || length(constraints) == 0) {
      constraints <- item$psychometric$irt_parameters$NE25$param_constraints
    }

    if (is.null(constraints) || length(constraints) == 0) {
      constraints <- item$psychometric$irt_parameters$NE25$constraints
    }

    # If still no constraints found, return NA
    if (is.null(constraints) || length(constraints) == 0) {
      return(NA_character_)
    }

    return(as.character(constraints))

  })

  codebook_df$param_constraints <- param_constraints_vec

  # ===========================================================================
  # Extract NE25 Parameter Starting Values
  # ===========================================================================

  # Extract discrimination (alpha) starting values
  alpha_start_vec <- sapply(codebook_df$lex_equate, function(eq_name) {

    # Find item in codebook by equate name (case-insensitive)
    item_id <- equate_to_item_id[[toupper(eq_name)]]

    if (is.null(item_id)) {
      return(NA_real_)
    }

    item <- codebook$items[[item_id]]

    if (is.null(item)) {
      return(NA_real_)
    }

    # Extract NE25 discrimination (first element of loadings array)
    loadings <- item$psychometric$irt_parameters$NE25$loadings

    if (is.null(loadings) || length(loadings) == 0) {
      return(NA_real_)
    }

    return(as.numeric(loadings[[1]]))

  })

  codebook_df$alpha_start <- alpha_start_vec

  # Extract threshold (tau) starting values as list column
  tau_start_list <- lapply(codebook_df$lex_equate, function(eq_name) {

    # Find item in codebook by equate name (case-insensitive)
    item_id <- equate_to_item_id[[toupper(eq_name)]]

    if (is.null(item_id)) {
      return(NA_real_)
    }

    item <- codebook$items[[item_id]]

    if (is.null(item)) {
      return(NA_real_)
    }

    # Extract NE25 thresholds (array of threshold values)
    thresholds <- item$psychometric$irt_parameters$NE25$thresholds

    if (is.null(thresholds) || length(thresholds) == 0) {
      return(NA_real_)
    }

    # Convert to numeric vector
    return(as.numeric(unlist(thresholds)))

  })

  codebook_df$tau_start <- tau_start_list

  # Filter by instrument if specified
  if (!is.null(instrument_filter)) {

    # Determine which items belong to the specified instrument
    items_in_instrument <- sapply(codebook_df$lex_equate, function(eq_name) {

      # Find item in codebook (case-insensitive)
      item_id <- equate_to_item_id[[toupper(eq_name)]]

      if (is.null(item_id)) {
        return(FALSE)
      }

      item <- codebook$items[[item_id]]

      if (is.null(item)) {
        return(FALSE)
      }

      # Check if instrument matches
      if (!is.null(item$instruments)) {
        return(instrument_filter %in% unlist(item$instruments))
      }

      return(FALSE)
    })

    # Filter codebook_df
    codebook_df <- codebook_df[items_in_instrument, ]
  }

  # Filter by scale if specified (future enhancement)
  if (!is.null(scale_name)) {
    # TODO: Add scale filtering logic based on codebook scale metadata
    # For now, instrument filter handles this
  }

  return(codebook_df)

}

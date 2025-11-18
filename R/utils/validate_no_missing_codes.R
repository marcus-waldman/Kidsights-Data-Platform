#' Validate No Sentinel Missing Codes in Item Responses
#'
#' @description
#' Checks transformed data for sentinel missing value codes (9, -9, 99, -99) that
#' should have been converted to NA. Throws an error if any are found, preventing
#' contaminated data from reaching downstream analyses or calibration datasets.
#'
#' @param dat Data frame containing transformed item responses
#' @param codebook_path Path to codebook.json file. Default: "codebook/data/codebook.json"
#' @param lexicon_name Which lexicon to use for variable name mapping (e.g., "ne25", "ne20")
#' @param verbose Logical. Print detailed progress messages? Default: TRUE
#' @param stop_on_error Logical. Stop execution if missing codes found? Default: TRUE
#'
#' @return Data frame (unchanged if validation passes)
#'
#' @details
#' This function performs a final safety check after all transformations to ensure
#' no sentinel missing value codes remain in item responses. It:
#'
#' 1. Loads the codebook to identify which variables are items (have calibration_item=TRUE or lexicons)
#' 2. Scans each item for common sentinel missing codes: 9, -9, 99, -99
#' 3. Reports any items with remaining missing codes
#' 4. Optionally stops execution with detailed error message
#'
#' **Why This Matters:**
#' - Missing codes like 9 ("Prefer not to answer") should NEVER reach IRT calibration
#' - These values would be treated as substantive responses, contaminating theta estimates
#' - This validation ensures codebook-based missing code conversion is working correctly
#'
#' @examples
#' \dontrun{
#' # Validate NE25 transformed data
#' ne25_clean <- validate_no_missing_codes(ne25_transformed, lexicon_name = "ne25")
#'
#' # Validate without stopping (just warnings)
#' ne25_check <- validate_no_missing_codes(ne25_transformed,
#'                                         lexicon_name = "ne25",
#'                                         stop_on_error = FALSE)
#' }
#'
#' @export
validate_no_missing_codes <- function(dat,
                                       codebook_path = "codebook/data/codebook.json",
                                       lexicon_name = "ne25",
                                       verbose = TRUE,
                                       stop_on_error = TRUE) {

  if (verbose) cat("\n=== Validating No Sentinel Missing Codes ===\n\n")

  # Load codebook
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required. Install with: install.packages('jsonlite')")
  }

  if (!file.exists(codebook_path)) {
    warning(sprintf("Codebook not found at: %s. Skipping missing code validation.", codebook_path))
    return(dat)
  }

  cb <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  if (verbose) cat(sprintf("[1/3] Loaded codebook from: %s\n", codebook_path))

  # Identify item variables from codebook
  item_vars <- character(0)

  for (item_id in names(cb$items)) {
    tryCatch({
      item <- cb$items[[item_id]]

      # Check if item has lexicons
      if (is.null(item$lexicons)) {
        next
      }

      # Check if the specified lexicon exists
      if (!lexicon_name %in% names(item$lexicons)) {
        next
      }

      var_name <- item$lexicons[[lexicon_name]]

      # With simplifyVector=FALSE, var_name might be a list
      if (is.list(var_name)) {
        var_name <- unlist(var_name)
      }

      # Skip if no variable name
      if (is.null(var_name) || var_name == "" || length(var_name) == 0) {
        next
      }

      item_vars <- c(item_vars, tolower(var_name))
    }, error = function(e) {
      # Skip items that cause errors
    })
  }

  if (verbose) {
    cat(sprintf("[2/3] Identified %d item variables from codebook\n", length(item_vars)))
  }

  # Sentinel missing codes to check for
  sentinel_codes <- c(9, -9, 99, -99)

  # Find which item variables exist in dataset (case-insensitive)
  dataset_names <- names(dat)
  dataset_names_lower <- tolower(dataset_names)

  items_to_check <- character(0)
  var_mapping <- list()  # lowercase_var -> actual_dataset_var

  for (item_var in item_vars) {
    match_idx <- which(dataset_names_lower == tolower(item_var))
    if (length(match_idx) > 0) {
      actual_var <- dataset_names[match_idx[1]]
      items_to_check <- c(items_to_check, actual_var)
      var_mapping[[tolower(item_var)]] <- actual_var
    }
  }

  if (length(items_to_check) == 0) {
    if (verbose) {
      cat("[3/3] No item variables found in dataset for validation\n")
    }
    return(dat)
  }

  if (verbose) {
    cat(sprintf("[3/3] Checking %d item variables for sentinel missing codes\n", length(items_to_check)))
  }

  # Check each item for sentinel codes
  violations <- list()

  for (item_var in items_to_check) {
    values <- dat[[item_var]]

    # Skip if all NA
    if (all(is.na(values))) next

    # Check for each sentinel code
    for (code in sentinel_codes) {
      if (any(values == code, na.rm = TRUE)) {
        n_violations <- sum(values == code, na.rm = TRUE)

        if (is.null(violations[[item_var]])) {
          violations[[item_var]] <- list()
        }

        violations[[item_var]][[as.character(code)]] <- n_violations
      }
    }
  }

  # Report results
  if (length(violations) == 0) {
    if (verbose) {
      cat("\n[OK] No sentinel missing codes found in any item responses\n")
      cat(sprintf("      Checked %d items for codes: %s\n",
                  length(items_to_check),
                  paste(sentinel_codes, collapse = ", ")))
    }
    return(dat)
  } else {
    # Build detailed error message
    error_msg <- sprintf("\n[ERROR] Found sentinel missing codes in %d items:\n\n", length(violations))

    for (item_var in names(violations)) {
      codes_found <- violations[[item_var]]
      error_msg <- paste0(error_msg, sprintf("  %s:\n", item_var))

      for (code in names(codes_found)) {
        n <- codes_found[[code]]
        error_msg <- paste0(error_msg, sprintf("    - Value %s: %d occurrences\n", code, n))
      }
    }

    error_msg <- paste0(error_msg, "\nThese values should have been converted to NA during transformation.\n")
    error_msg <- paste0(error_msg, "Check that validate_item_responses() is working correctly.\n")

    if (stop_on_error) {
      stop(error_msg)
    } else {
      warning(error_msg)
      return(dat)
    }
  }
}

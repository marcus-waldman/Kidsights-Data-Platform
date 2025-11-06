#' Validate Item Responses Against Codebook
#'
#' Sets invalid response values to NA based on codebook response_sets definitions.
#' This ensures only valid response options are retained in the transformed data.
#'
#' @param dat Data frame containing item responses
#' @param codebook_path Path to codebook.json file. Default: "codebook/data/codebook.json"
#' @param lexicon_name Which lexicon to use for variable name mapping (e.g., "ne25", "ne20")
#' @param verbose Logical. Print detailed progress messages? Default: TRUE
#'
#' @return Data frame with invalid responses set to NA
#'
#' @details
#' This function:
#' 1. Loads the codebook and extracts valid response values from response_sets
#' 2. Maps codebook item IDs to dataset variable names using specified lexicon
#' 3. For each item, identifies values not in the valid response set
#' 4. Sets invalid values to NA (preserving already-missing values)
#'
#' **Important:** This includes missing value codes marked with `missing: true` in
#' the response_set (e.g., -9 for "Don't Know"). Only values completely undefined
#' in the codebook are set to NA.
#'
#' Example: If codebook defines {0, 1, 2, -9} where -9 is marked as missing,
#' then value=9 would be set to NA, but value=-9 would be retained.
#'
#' @examples
#' \dontrun{
#' # Validate NE25 items
#' ne25_data <- validate_item_responses(ne25_raw, lexicon_name = "ne25")
#'
#' # Validate NE20 items silently
#' ne20_data <- validate_item_responses(ne20_raw, lexicon_name = "ne20", verbose = FALSE)
#' }
#'
#' @export
validate_item_responses <- function(dat,
                                     codebook_path = "codebook/data/codebook.json",
                                     lexicon_name = "ne25",
                                     verbose = TRUE) {

  if (verbose) cat("\n=== Validating Item Responses Against Codebook ===\n\n")

  # Load codebook
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required. Install with: install.packages('jsonlite')")
  }

  if (!file.exists(codebook_path)) {
    warning(sprintf("Codebook not found at: %s. Skipping response validation.", codebook_path))
    return(dat)
  }

  cb <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  if (verbose) cat(sprintf("[1/4] Loaded codebook from: %s\n", codebook_path))

  # Build lookup: item variable name -> valid response values
  valid_responses <- list()

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

      # Get response set reference
      response_ref <- NULL

      # Try to find response_options for this lexicon
      # Check that content exists and is a list
      if (!is.null(item$content) && is.list(item$content)) {
        if (!is.null(item$content$response_options) && is.list(item$content$response_options)) {
          # Try exact lexicon match first
          if (lexicon_name %in% names(item$content$response_options)) {
            response_ref <- item$content$response_options[[lexicon_name]]
          } else if ("ne25" %in% names(item$content$response_options)) {
            response_ref <- item$content$response_options$ne25
          } else if ("ne22" %in% names(item$content$response_options)) {
            response_ref <- item$content$response_options$ne22
          } else if ("ne20" %in% names(item$content$response_options)) {
            response_ref <- item$content$response_options$ne20
          }
        }
      }

      # Extract valid values from response_sets (including missing codes)
      # With simplifyVector=FALSE, scalar values might be single-element lists
      if (!is.null(response_ref)) {
        # Convert to character if it's a list
        response_ref_char <- if (is.list(response_ref)) unlist(response_ref) else response_ref

        if (length(response_ref_char) == 1 &&
            is.character(response_ref_char) &&
            response_ref_char %in% names(cb$response_sets)) {

          response_set <- cb$response_sets[[response_ref_char]]

          # Extract ALL values (including those marked as missing)
          # We want to keep -9 if it's defined, but remove 9 if it's not defined
          valid_vals <- sapply(response_set, function(opt) {
            # With simplifyVector=FALSE, opt$value might be a list
            val <- if (is.list(opt$value)) opt$value[[1]] else opt$value
            as.numeric(val)
          })

          valid_responses[[var_name]] <- sort(unique(valid_vals))
        }
      }
    }, error = function(e) {
      # Skip items that cause errors
      if (verbose) {
        cat(sprintf("      Warning: Skipping item %s due to error: %s\n", item_id, e$message))
      }
    })
  }

  if (verbose) {
    cat(sprintf("[2/4] Extracted valid responses for %d items from codebook\n", length(valid_responses)))
  }

  # Find which variables exist in dataset (case-insensitive)
  dataset_names <- names(dat)
  vars_to_validate <- character(0)
  var_mapping <- list()  # codebook_var -> actual_dataset_var

  for (var_expected in names(valid_responses)) {
    # Try exact match first
    if (var_expected %in% dataset_names) {
      vars_to_validate <- c(vars_to_validate, var_expected)
      var_mapping[[var_expected]] <- var_expected
    } else {
      # Try case-insensitive match
      match_idx <- which(tolower(dataset_names) == tolower(var_expected))
      if (length(match_idx) > 0) {
        actual_var <- dataset_names[match_idx[1]]
        vars_to_validate <- c(vars_to_validate, actual_var)
        var_mapping[[var_expected]] <- actual_var
      }
    }
  }

  if (length(vars_to_validate) == 0) {
    if (verbose) {
      cat(sprintf("[3/4] No variables found in dataset for validation\n"))
    }
    return(dat)
  }

  if (verbose) {
    cat(sprintf("[3/4] Found %d variables in dataset to validate\n", length(vars_to_validate)))
  }

  # Validate responses and set invalid values to NA
  dat_validated <- dat
  n_invalid_total <- 0
  n_items_with_invalid <- 0

  for (var_expected in names(var_mapping)) {
    actual_var <- var_mapping[[var_expected]]
    valid_vals <- valid_responses[[var_expected]]

    original_values <- dat_validated[[actual_var]]

    # Skip if all NA
    if (all(is.na(original_values))) next

    # Find invalid values (not in valid set and not already NA)
    invalid_mask <- !is.na(original_values) & !(original_values %in% valid_vals)
    n_invalid <- sum(invalid_mask)

    if (n_invalid > 0) {
      # Set invalid values to NA
      dat_validated[[actual_var]][invalid_mask] <- NA

      n_invalid_total <- n_invalid_total + n_invalid
      n_items_with_invalid <- n_items_with_invalid + 1

      if (verbose && n_items_with_invalid <= 10) {
        # Show first 10 items with issues
        invalid_values <- unique(original_values[invalid_mask])
        cat(sprintf("      - %s: %d invalid values set to NA (values: %s, valid: %s)\n",
                    actual_var,
                    n_invalid,
                    paste(head(sort(invalid_values), 5), collapse = ","),
                    paste(head(valid_vals, 5), collapse = ",")))
      }
    }
  }

  if (verbose) {
    cat(sprintf("[4/4] Response validation complete\n"))
    cat(sprintf("      Items with invalid values: %d / %d\n", n_items_with_invalid, length(vars_to_validate)))
    cat(sprintf("      Total invalid values set to NA: %d\n", n_invalid_total))

    if (n_items_with_invalid > 10) {
      cat(sprintf("      (showing first 10 items, %d more items had invalid values)\n", n_items_with_invalid - 10))
    }
    cat("\n")
  }

  return(dat_validated)
}

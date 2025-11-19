#' Reverse-Code Items Based on Codebook
#'
#' Applies reverse coding to items marked with scoring.reverse = TRUE in the codebook.
#' Uses the formula: max(x, na.rm=TRUE) - x, which converts high values to low and vice versa.
#'
#' @param dat Data frame containing item responses
#' @param codebook_path Path to codebook.json file. Default: "codebook/data/codebook.json"
#' @param lexicon_name Which lexicon to use for variable name mapping (e.g., "ne25", "ne20")
#' @param verbose Logical. Print detailed progress messages? Default: TRUE
#'
#' @return Data frame with reverse-coded items transformed
#'
#' @details
#' This function:
#' 1. Loads the codebook and identifies items with scoring.reverse = TRUE
#' 2. Maps codebook item IDs to dataset variable names using specified lexicon
#' 3. Applies reverse coding: new_value = max(original_values) - original_value
#' 4. Preserves NA values and only transforms non-missing responses
#'
#' Example: If responses are 1=Yes, 2=No, reverse coding converts:
#'   - 1 (Yes) -> max(2) - 1 = 1 (now means "low")
#'   - 2 (No)  -> max(2) - 2 = 0 (now means "high")
#'
#' This ensures all items point in the same direction for IRT calibration.
#'
#' @examples
#' \dontrun{
#' # Reverse-code NE25 items
#' ne25_data <- reverse_code_items(ne25_raw, lexicon_name = "ne25")
#'
#' # Reverse-code NE20 items
#' ne20_data <- reverse_code_items(ne20_raw, lexicon_name = "ne20", verbose = FALSE)
#' }
#'
#' @export
reverse_code_items <- function(dat,
                                codebook_path = "codebook/data/codebook.json",
                                lexicon_name = "ne25",
                                verbose = TRUE) {

  if (verbose) cat("\n=== Reverse-Coding Items from Codebook ===\n\n")

  # Load codebook
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required. Install with: install.packages('jsonlite')")
  }

  if (!file.exists(codebook_path)) {
    warning(sprintf("Codebook not found at: %s. Skipping reverse coding.", codebook_path))
    return(dat)
  }

  cb <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  if (verbose) cat(sprintf("[1/5] Loaded codebook from: %s\n", codebook_path))

  # Find reverse-coded items with specified lexicon
  reverse_items <- sapply(cb$items, function(item) {
    has_reverse <- FALSE
    has_lexicon <- FALSE

    # Check for reverse flag (priority order):
    # 1. Study-specific: reverse_coded.{lexicon_name} = TRUE
    if ("reverse_coded" %in% names(item) && !is.null(item$reverse_coded)) {
      if (lexicon_name %in% names(item$reverse_coded)) {
        has_reverse <- (item$reverse_coded[[lexicon_name]] == TRUE || item$reverse_coded[[lexicon_name]] == "TRUE")
      }
    }

    # 2. Global fallback: scoring.reverse = TRUE (applies to all studies)
    if (!has_reverse && "scoring" %in% names(item) && !is.null(item$scoring)) {
      if ("reverse" %in% names(item$scoring)) {
        has_reverse <- (item$scoring$reverse == TRUE || item$scoring$reverse == "TRUE")
      }
    }

    # Check for lexicon mapping
    if ("lexicons" %in% names(item) && !is.null(item$lexicons)) {
      has_lexicon <- lexicon_name %in% names(item$lexicons)
    }

    return(has_reverse && has_lexicon)
  })

  reverse_item_ids <- names(cb$items)[reverse_items]

  if (length(reverse_item_ids) == 0) {
    if (verbose) cat(sprintf("[2/5] No reverse-coded items found for lexicon '%s'\n", lexicon_name))
    return(dat)
  }

  if (verbose) {
    cat(sprintf("[2/5] Found %d reverse-coded items in codebook\n", length(reverse_item_ids)))
  }

  # Map codebook IDs to dataset variable names using lexicon
  var_mapping <- sapply(reverse_item_ids, function(item_id) {
    item <- cb$items[[item_id]]
    if (lexicon_name %in% names(item$lexicons)) {
      lexicon_value <- item$lexicons[[lexicon_name]]
      if (!is.null(lexicon_value) && lexicon_value != "") {
        return(lexicon_value)
      }
    }
    return(NA)
  })

  # Remove NAs
  var_mapping <- var_mapping[!is.na(var_mapping)]

  if (verbose) {
    cat(sprintf("[3/5] Mapped %d items to dataset variables\n", length(var_mapping)))
  }

  # Find which variables actually exist in the dataset (case-insensitive matching)
  # Match codebook variable names (potentially uppercase) to dataset names (potentially lowercase)
  dataset_names <- names(dat)
  vars_to_reverse <- character(0)

  for (var_expected in var_mapping) {
    # Try exact match first
    if (var_expected %in% dataset_names) {
      vars_to_reverse <- c(vars_to_reverse, var_expected)
    } else {
      # Try case-insensitive match
      match_idx <- which(tolower(dataset_names) == tolower(var_expected))
      if (length(match_idx) > 0) {
        # Use the actual dataset variable name (correct case)
        vars_to_reverse <- c(vars_to_reverse, dataset_names[match_idx[1]])
      }
    }
  }

  if (length(vars_to_reverse) == 0) {
    if (verbose) {
      cat(sprintf("[3/5] No reverse-coded variables found in dataset\n"))
      cat("        Variables expected but not found:\n")
      missing_vars <- setdiff(var_mapping, names(dat))
      for (i in 1:min(5, length(missing_vars))) {
        cat(sprintf("          - %s\n", missing_vars[i]))
      }
    }
    return(dat)
  }

  if (verbose) {
    cat(sprintf("[3/5] Found %d variables to reverse-code\n", length(vars_to_reverse)))
    if (length(vars_to_reverse) <= 10) {
      cat("        Variables:\n")
      for (var in vars_to_reverse) {
        cat(sprintf("          - %s\n", var))
      }
    }
  }

  # Extract valid response values for each item from codebook
  # This prevents missing codes (e.g., 9) from inflating max_val calculation
  if (verbose) cat("[4/5] Extracting valid response values from codebook\n")

  valid_responses <- list()

  for (item_id in names(cb$items)) {
    tryCatch({
      item <- cb$items[[item_id]]

      # Get variable name for this lexicon
      if (is.null(item$lexicons) || !lexicon_name %in% names(item$lexicons)) {
        next
      }

      var_name <- item$lexicons[[lexicon_name]]
      if (is.list(var_name)) var_name <- unlist(var_name)
      if (is.null(var_name) || var_name == "" || length(var_name) == 0) {
        next
      }

      # Store lowercase version for case-insensitive lookup
      var_name <- tolower(var_name)

      # Get response_set reference
      response_ref <- NULL

      if (!is.null(item$content) && is.list(item$content)) {
        if (!is.null(item$content$response_options) && is.list(item$content$response_options)) {
          if (lexicon_name %in% names(item$content$response_options)) {
            response_ref <- item$content$response_options[[lexicon_name]]
          }
        }
      }

      # Extract valid values from response_set
      if (!is.null(response_ref)) {
        response_ref_char <- if (is.list(response_ref)) unlist(response_ref) else response_ref

        if (length(response_ref_char) == 1 && is.character(response_ref_char)) {
          if (grepl("^\\$ref:", response_ref_char)) {
            response_ref_char <- sub("^\\$ref:", "", response_ref_char)
          }

          if (response_ref_char %in% names(cb$response_sets)) {
            response_set <- cb$response_sets[[response_ref_char]]

            # Extract ONLY substantive values (exclude missing codes)
            # Missing codes are marked with "missing": true in response_set options
            valid_vals <- sapply(response_set, function(opt) {
              # Check if this is a missing code
              is_missing <- !is.null(opt$missing) && (opt$missing == TRUE || opt$missing == "true")

              if (is_missing) {
                return(NA)  # Exclude missing codes from valid set
              }

              val <- if (is.list(opt$value)) opt$value[[1]] else opt$value
              as.numeric(val)
            })

            # Remove NAs (missing codes were marked as NA above)
            valid_vals <- valid_vals[!is.na(valid_vals)]

            if (length(valid_vals) > 0) {
              valid_responses[[var_name]] <- sort(unique(valid_vals))
            }
          }
        }
      }
    }, error = function(e) {
      # Skip items that cause errors
    })
  }

  if (verbose) {
    cat(sprintf("        Extracted valid responses for %d items\n", length(valid_responses)))
  }

  # Apply reverse coding: new_value = max(valid_values) - original
  # This preserves the scale range while flipping direction
  if (verbose) cat("[5/5] Applying reverse coding transformations\n")

  dat_reversed <- dat

  for (var in vars_to_reverse) {
    original_values <- dat[[var]]

    # Skip if all NA
    if (all(is.na(original_values))) next

    # Get valid response values for this variable
    valid_vals <- valid_responses[[var]]

    if (is.null(valid_vals) || length(valid_vals) == 0) {
      # Fallback: use max of all non-NA values (old behavior)
      max_val <- max(original_values, na.rm = TRUE)
      if (verbose) {
        cat(sprintf("        Warning: %s has no valid response set, using max(all values) = %.0f\n",
                    var, max_val))
      }
    } else {
      # Use max of valid response values only (excludes missing codes)
      max_val <- max(valid_vals)
    }

    # Reverse code: max - x
    # Only reverse values that are in the valid set (or all values if no valid set)
    if (!is.null(valid_vals) && length(valid_vals) > 0) {
      # Set values outside valid range to NA first
      dat_reversed[[var]] <- ifelse(
        is.na(original_values) | !(original_values %in% valid_vals),
        NA,  # Preserve NAs and invalidate out-of-range values
        max_val - original_values  # Reverse valid values only
      )
    } else {
      # Fallback: reverse all non-NA values
      dat_reversed[[var]] <- ifelse(
        is.na(original_values),
        NA,
        max_val - original_values
      )
    }
  }

  if (verbose) {
    cat(sprintf("\n[OK] Reverse coding complete for %d variables\n\n", length(vars_to_reverse)))
  }

  return(dat_reversed)
}

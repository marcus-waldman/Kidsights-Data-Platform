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

  cb <- jsonlite::fromJSON(codebook_path)

  if (verbose) cat(sprintf("[1/4] Loaded codebook from: %s\n", codebook_path))

  # Find reverse-coded items with specified lexicon
  reverse_items <- sapply(cb$items, function(item) {
    has_reverse <- FALSE
    has_lexicon <- FALSE

    # Check for reverse flag
    if ("scoring" %in% names(item) && !is.null(item$scoring)) {
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
    if (verbose) cat(sprintf("[2/4] No reverse-coded items found for lexicon '%s'\n", lexicon_name))
    return(dat)
  }

  if (verbose) {
    cat(sprintf("[2/4] Found %d reverse-coded items in codebook\n", length(reverse_item_ids)))
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
    cat(sprintf("[3/4] Mapped %d items to dataset variables\n", length(var_mapping)))
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
      cat(sprintf("[4/4] No reverse-coded variables found in dataset\n"))
      cat("        Variables expected but not found:\n")
      missing_vars <- setdiff(var_mapping, names(dat))
      for (i in 1:min(5, length(missing_vars))) {
        cat(sprintf("          - %s\n", missing_vars[i]))
      }
    }
    return(dat)
  }

  if (verbose) {
    cat(sprintf("[4/4] Reverse-coding %d variables in dataset\n", length(vars_to_reverse)))
    if (length(vars_to_reverse) <= 10) {
      cat("        Variables:\n")
      for (var in vars_to_reverse) {
        cat(sprintf("          - %s\n", var))
      }
    }
  }

  # Apply reverse coding: new_value = max(original) - original
  # This preserves the scale range while flipping direction
  dat_reversed <- dat

  for (var in vars_to_reverse) {
    original_values <- dat[[var]]

    # Skip if all NA
    if (all(is.na(original_values))) next

    # Calculate max of non-NA values
    max_val <- max(original_values, na.rm = TRUE)

    # Reverse code: max - x
    dat_reversed[[var]] <- ifelse(
      is.na(original_values),
      NA,  # Preserve NAs
      max_val - original_values  # Reverse non-NA values
    )
  }

  if (verbose) {
    cat(sprintf("\n[OK] Reverse coding complete for %d variables\n\n", length(vars_to_reverse)))
  }

  return(dat_reversed)
}

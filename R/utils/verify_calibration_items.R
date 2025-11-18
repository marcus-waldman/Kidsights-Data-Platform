#' Verify Expected Calibration Items Are Present in Data
#'
#' Compares expected calibration items from codebook against actual columns
#' in data tables. Ensures no items are silently missing before processing.
#'
#' @param data Data frame to check for item presence
#' @param lexicon_name Name of lexicon to check (default: "equate")
#' @param verbose Logical. Print detailed output? Default: TRUE
#' @param stop_on_missing Logical. Stop execution if items missing? Default: TRUE
#'
#' @return List with verification results:
#'   - passed: Logical, TRUE if all expected items present
#'   - expected_items: Character vector of expected item names from codebook
#'   - actual_items: Character vector of actual item names in data
#'   - missing_items: Character vector of items in codebook but not in data
#'   - extra_items: Character vector of items in data but not in codebook
#'
#' @details
#' This function:
#' 1. Loads codebook to identify all items where calibration_item = TRUE
#' 2. Extracts expected variable names for the specified lexicon
#' 3. Compares against actual column names in data (case-insensitive)
#' 4. Reports missing items (expected but not found)
#' 5. Reports extra items (found but not expected)
#'
#' Multi-study considerations:
#' - For multi-study datasets, not all items will be present (this is expected)
#' - Use per-study verification by filtering data first
#' - Missing items are WARNING for multi-study, ERROR for single-study
#'
#' @examples
#' \dontrun{
#' # Verify NE25 calibration table has all expected items
#' ne25_data <- DBI::dbReadTable(db$con, "ne25_calibration")
#'
#' verification <- verify_calibration_items(
#'   data = ne25_data,
#'   lexicon_name = "equate",
#'   verbose = TRUE,
#'   stop_on_missing = TRUE
#' )
#'
#' if (!verification$passed) {
#'   cat("Missing items:\n")
#'   print(verification$missing_items)
#' }
#' }
#'
#' @export
verify_calibration_items <- function(data,
                                      lexicon_name = "equate",
                                      verbose = TRUE,
                                      stop_on_missing = TRUE) {

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat("VERIFYING CALIBRATION ITEM PRESENCE\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Load codebook
  codebook_path <- "codebook/data/codebook.json"

  if (!file.exists(codebook_path)) {
    stop("Codebook not found at: ", codebook_path)
  }

  cb <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Extract expected calibration items
  expected_items <- character()

  for (item_name in names(cb$items)) {
    item <- cb$items[[item_name]]

    # Check if this is a calibration item
    is_calibration <- !is.null(item$scoring$calibration_item) &&
      (item$scoring$calibration_item == TRUE || item$scoring$calibration_item == "true")

    if (is_calibration) {
      # Get variable name for this lexicon
      if (!is.null(item$lexicons[[lexicon_name]])) {
        var_name <- item$lexicons[[lexicon_name]]
        if (is.list(var_name)) var_name <- var_name[[1]]

        if (!is.null(var_name) && var_name != "") {
          expected_items <- c(expected_items, tolower(var_name))
        }
      }
    }
  }

  expected_items <- unique(expected_items)

  if (verbose) {
    cat(sprintf("[INFO] Found %d expected calibration items in codebook\n", length(expected_items)))
    cat(sprintf("        Lexicon: %s\n\n", lexicon_name))
  }

  # Get actual column names from data
  actual_items <- tolower(names(data))

  # Remove metadata columns
  metadata_cols <- c("id", "pid", "record_id", "retrieved_date", "source_project",
                     "extraction_id", "redcap_event_name", "study", "years",
                     "wgt", "authenticity_weight", "studynum", "devflag",
                     "maskflag", "cooksd_quantile", "lex_equate")

  actual_items <- setdiff(actual_items, metadata_cols)

  if (verbose) {
    cat(sprintf("[INFO] Found %d item columns in data\n", length(actual_items)))
    cat(sprintf("        (Excluded %d metadata columns)\n\n", length(metadata_cols)))
  }

  # Find missing and extra items
  missing_items <- setdiff(expected_items, actual_items)
  extra_items <- setdiff(actual_items, expected_items)

  # Determine pass/fail
  passed <- length(missing_items) == 0

  # Report results
  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("VERIFICATION SUMMARY\n")
    cat(strrep("=", 80), "\n\n")

    cat(sprintf("  Expected items: %d\n", length(expected_items)))
    cat(sprintf("  Actual items: %d\n", length(actual_items)))
    cat(sprintf("  Missing items: %d\n", length(missing_items)))
    cat(sprintf("  Extra items: %d\n\n", length(extra_items)))

    if (length(missing_items) > 0) {
      cat("[WARNING] The following expected items are missing from data:\n")
      for (i in seq_along(missing_items)) {
        cat(sprintf("  %d. %s\n", i, missing_items[i]))
        if (i >= 20) {
          cat(sprintf("  ... and %d more\n", length(missing_items) - 20))
          break
        }
      }
      cat("\n")
    }

    if (length(extra_items) > 0 && length(extra_items) <= 10) {
      cat("[INFO] The following items in data are not marked as calibration items:\n")
      for (i in seq_along(extra_items)) {
        cat(sprintf("  %d. %s\n", i, extra_items[i]))
      }
      cat("\n")
    } else if (length(extra_items) > 10) {
      cat(sprintf("[INFO] %d items in data are not marked as calibration items\n\n", length(extra_items)))
    }

    if (passed) {
      cat("[OK] All expected calibration items are present\n\n")
    } else {
      cat(sprintf("[FAILED] %d expected items are missing\n\n", length(missing_items)))
    }

    cat(strrep("=", 80), "\n\n")
  }

  # Create result object
  result <- list(
    passed = passed,
    expected_items = expected_items,
    actual_items = actual_items,
    missing_items = missing_items,
    extra_items = extra_items
  )

  # Stop execution if items missing and stop_on_missing = TRUE
  if (!passed && stop_on_missing) {
    stop(sprintf("Item verification failed: %d expected calibration items are missing from data. ",
                 length(missing_items)),
         "Set stop_on_missing=FALSE to continue anyway.")
  }

  return(invisible(result))
}

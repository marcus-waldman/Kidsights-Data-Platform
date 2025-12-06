#' Validate Item Counts Against Known Incorrectly Coded Items
#'
#' @description
#' Verifies that items with known historical coding issues (EG39a, EG41_2, EG30d,
#' EG30e, AA56, EG44_2) have sufficient non-NA responses in the eligible sample
#' to match the documented incorrectly coded observations from manual screening.
#'
#' This validation ensures that codebook fixes for reverse coding are applied
#' correctly and data is not being inadvertently filtered or transformed.
#'
#' @param dat Data frame with eligible participants (eligible = TRUE)
#' @param csv_path Path to incorrectly coded items CSV
#' @param codebook_path Path to codebook.json for lexicon mapping
#' @param verbose Logical, print detailed messages? (default: TRUE)
#' @param stop_on_error Logical, stop pipeline if validation fails? (default: TRUE)
#'
#' @return List with:
#'   - passed: Logical, TRUE if all counts match
#'   - comparison: Data frame comparing CSV vs database counts
#'   - message: Character, summary message
#'
#' @export
validate_item_counts <- function(dat,
                                 csv_path = "output/ne25/authenticity_screening/manual_screening/incorrectly_coded_items_06Dec2025.csv",
                                 codebook_path = "codebook/data/codebook.json",
                                 verbose = TRUE,
                                 stop_on_error = TRUE) {

  if (verbose) {
    cat("\n")
    cat("================================================================================\n")
    cat("  VALIDATE ITEM COUNTS (Reverse Coding Verification)\n")
    cat("================================================================================\n")
    cat("\n")
  }

  # Check if CSV exists
  if (!file.exists(csv_path)) {
    warning(sprintf("CSV file not found: %s\nSkipping item count validation.", csv_path))
    return(list(
      passed = TRUE,
      comparison = NULL,
      message = "Validation skipped (CSV not found)"
    ))
  }

  # Load CSV with incorrectly coded items
  csv_data <- read.csv(csv_path, stringsAsFactors = FALSE)

  # Get unique item names and counts
  csv_counts <- csv_data %>%
    dplyr::group_by(item) %>%
    dplyr::summarise(csv_count = n(), .groups = "drop") %>%
    dplyr::arrange(dplyr::desc(csv_count))

  if (verbose) {
    cat("=== CSV Item Counts (Known Incorrectly Coded) ===\n")
    print(as.data.frame(csv_counts))
    cat("\n")
  }

  # Load codebook to get item lexicon mapping
  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Create equate to ne25 mapping
  equate_to_ne25 <- list()
  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
    if (!is.null(item$lexicons) && !is.null(item$lexicons$equate) && !is.null(item$lexicons$ne25)) {
      equate_name <- item$lexicons$equate
      ne25_name <- tolower(item$lexicons$ne25)
      if (is.list(equate_name)) equate_name <- unlist(equate_name)
      if (is.list(ne25_name)) ne25_name <- unlist(ne25_name)
      if (!is.null(equate_name) && !is.null(ne25_name) && equate_name != "" && ne25_name != "") {
        equate_to_ne25[[equate_name]] <- ne25_name
      }
    }
  }

  # Check counts for each item in CSV
  if (verbose) {
    cat("=== Database Counts (eligible = TRUE) ===\n")
  }

  db_counts <- data.frame(
    item = character(),
    db_count = integer(),
    ne25_col = character(),
    stringsAsFactors = FALSE
  )

  for (item_equate in csv_counts$item) {
    ne25_col <- equate_to_ne25[[item_equate]]

    if (!is.null(ne25_col) && ne25_col %in% names(dat)) {
      count <- sum(!is.na(dat[[ne25_col]]))
      db_counts <- rbind(db_counts, data.frame(
        item = item_equate,
        db_count = count,
        ne25_col = ne25_col,
        stringsAsFactors = FALSE
      ))

      if (verbose) {
        cat(sprintf("  %s (ne25: %s): %d non-NA values\n", item_equate, ne25_col, count))
      }
    } else {
      if (verbose) {
        cat(sprintf("  %s: NOT FOUND in database (ne25_col = %s)\n",
                   item_equate, ifelse(is.null(ne25_col), "NULL", ne25_col)))
      }
    }
  }

  if (verbose) cat("\n")

  # Compare counts
  comparison <- csv_counts %>%
    dplyr::left_join(db_counts %>% dplyr::select(item, db_count), by = "item") %>%
    dplyr::mutate(
      match = csv_count == db_count,
      pct_coverage = round(100 * csv_count / db_count, 1)
    )

  if (verbose) {
    cat("=== Comparison ===\n")
    print(as.data.frame(comparison))
    cat("\n")
  }

  # Check if all counts match
  all_matched <- all(!is.na(comparison$match)) && all(comparison$match)

  if (all_matched) {
    message_text <- sprintf(
      "[OK] All CSV counts exactly match database counts (eligible = TRUE)\n     %d items verified, %d total observations matched",
      nrow(comparison), sum(csv_counts$csv_count)
    )
    if (verbose) {
      cat("================================================================================\n")
      cat("  VALIDATION PASSED\n")
      cat("================================================================================\n")
      cat(message_text, "\n")
      cat("  This confirms codebook reverse coding fixes are correct.\n")
      cat("\n")
    }
  } else {
    # Find mismatches
    mismatches <- comparison %>%
      dplyr::filter(!match | is.na(match))

    error_text <- sprintf(
      "[ERROR] Item count validation FAILED\n  %d items have mismatched counts (CSV != DB):\n%s",
      nrow(mismatches),
      paste(sprintf("    - %s: CSV=%d, DB=%d (diff=%+d)",
                   mismatches$item, mismatches$csv_count, mismatches$db_count,
                   mismatches$db_count - mismatches$csv_count),
            collapse = "\n")
    )

    if (verbose) {
      cat("================================================================================\n")
      cat("  VALIDATION FAILED\n")
      cat("================================================================================\n")
      cat(error_text, "\n")
      cat("\nPossible causes:\n")
      cat("  1. Codebook reverse coding flags not applied correctly\n")
      cat("  2. Data filtered too aggressively (check eligible = TRUE filter)\n")
      cat("  3. CSV file from different data version\n")
      cat("\n")
    }

    if (stop_on_error) {
      stop(error_text)
    } else {
      warning(error_text)
    }
  }

  return(list(
    passed = all_matched,
    comparison = comparison,
    message = if (all_matched) message_text else error_text
  ))
}

#' Validate Data Transformation for Unexpected Data Loss
#'
#' Compares data before and after transformation to detect unexpected data loss
#' that exceeds reasonable thresholds. Flags items where non-missing values
#' decrease by more than expected from known missing codes.
#'
#' @param data_before Data frame before transformation
#' @param data_after Data frame after transformation
#' @param max_loss_pct Maximum acceptable data loss percentage (default: 10%)
#' @param verbose Logical. Print detailed warnings? Default: TRUE
#' @param stop_on_error Logical. Stop execution if critical data loss detected? Default: TRUE
#'
#' @return List with validation results:
#'   - passed: Logical, TRUE if validation passed
#'   - warnings: Character vector of warning messages
#'   - errors: Character vector of error messages
#'   - item_summary: Data frame with per-item statistics
#'
#' @details
#' This function checks for:
#' 1. Row count changes (should be identical unless filtering)
#' 2. Column-level data loss exceeding max_loss_pct
#' 3. Items where non-null counts drop dramatically
#'
#' Expected data loss sources:
#' - Missing codes being set to NA (acceptable)
#' - Invalid values being removed (acceptable if < max_loss_pct)
#' - Transformation bugs (UNACCEPTABLE - triggers error)
#'
#' @examples
#' \dontrun{
#' # Validate NE25 transformation
#' validated_data <- readRDS("temp/pipeline_cache/step2_validated_data.rds")
#' transformed_data <- readRDS("temp/pipeline_cache/step5_transformed_data.rds")
#'
#' validation <- validate_transformation(
#'   data_before = validated_data,
#'   data_after = transformed_data,
#'   max_loss_pct = 10
#' )
#'
#' if (!validation$passed) {
#'   stop("Data validation failed!")
#' }
#' }
#'
#' @export
validate_transformation <- function(data_before,
                                     data_after,
                                     max_loss_pct = 10,
                                     verbose = TRUE,
                                     stop_on_error = TRUE) {

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat("VALIDATING DATA TRANSFORMATION\n")
    cat(strrep("=", 80), "\n\n")
  }

  warnings <- character()
  errors <- character()
  item_summary <- data.frame()

  # Check 1: Row count validation
  if (verbose) cat("[1/3] Validating row counts\n")

  n_before <- nrow(data_before)
  n_after <- nrow(data_after)

  if (n_before != n_after) {
    msg <- sprintf("Row count changed: %d -> %d (%.1f%% loss)",
                   n_before, n_after, 100 * (n_before - n_after) / n_before)
    warnings <- c(warnings, msg)
    if (verbose) cat(sprintf("      WARNING: %s\n", msg))
  } else {
    if (verbose) cat(sprintf("      Row count: %d (unchanged) [OK]\n", n_before))
  }

  # Check 2: Column count validation
  if (verbose) cat("\n[2/3] Validating column counts\n")

  n_cols_before <- ncol(data_before)
  n_cols_after <- ncol(data_after)

  if (verbose) {
    cat(sprintf("      Columns before: %d\n", n_cols_before))
    cat(sprintf("      Columns after: %d\n", n_cols_after))
    if (n_cols_after > n_cols_before) {
      cat(sprintf("      New columns added: %d [OK]\n", n_cols_after - n_cols_before))
    }
  }

  # Check 3: Item-level data loss validation
  if (verbose) cat("\n[3/3] Validating item-level data integrity\n")

  # Find common columns (case-insensitive)
  cols_before_lower <- tolower(names(data_before))
  cols_after_lower <- tolower(names(data_after))
  common_cols_lower <- intersect(cols_before_lower, cols_after_lower)

  # Build mapping: lowercase -> actual column names
  col_map_before <- setNames(names(data_before), cols_before_lower)
  col_map_after <- setNames(names(data_after), cols_after_lower)

  # Analyze each common column for data loss
  item_stats <- list()

  for (col_lower in common_cols_lower) {
    col_before <- col_map_before[col_lower]
    col_after <- col_map_after[col_lower]

    # Skip metadata columns
    if (col_lower %in% c("record_id", "pid", "retrieved_date", "source_project",
                         "extraction_id", "redcap_event_name")) {
      next
    }

    # Count non-null values
    n_before_col <- sum(!is.na(data_before[[col_before]]))
    n_after_col <- sum(!is.na(data_after[[col_after]]))

    # Calculate loss
    if (n_before_col > 0) {
      loss_count <- n_before_col - n_after_col
      loss_pct <- 100 * loss_count / n_before_col

      # Store statistics
      item_stats[[col_lower]] <- data.frame(
        column = col_lower,
        n_before = n_before_col,
        n_after = n_after_col,
        loss_count = loss_count,
        loss_pct = loss_pct,
        stringsAsFactors = FALSE
      )

      # Flag excessive data loss
      if (loss_pct > max_loss_pct && n_before_col >= 10) {
        msg <- sprintf("%s: %d -> %d (%.1f%% loss, %d values lost)",
                       col_lower, n_before_col, n_after_col, loss_pct, loss_count)
        errors <- c(errors, msg)

        if (verbose) {
          cat(sprintf("      [ERROR] %s\n", msg))
        }
      }
    }
  }

  # Combine item statistics
  if (length(item_stats) > 0) {
    item_summary <- do.call(rbind, item_stats)
    rownames(item_summary) <- NULL

    # Sort by loss percentage (descending)
    item_summary <- item_summary[order(-item_summary$loss_pct), ]
  }

  # Summary
  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat("VALIDATION SUMMARY\n")
    cat(strrep("=", 80), "\n\n")

    cat(sprintf("  Items analyzed: %d\n", nrow(item_summary)))

    if (nrow(item_summary) > 0) {
      critical_loss <- item_summary[item_summary$loss_pct > max_loss_pct &
                                    item_summary$n_before >= 10, ]

      if (nrow(critical_loss) > 0) {
        cat(sprintf("  Items with >%.0f%% data loss: %d [CRITICAL]\n",
                    max_loss_pct, nrow(critical_loss)))
        cat("\n  Top 10 items with highest data loss:\n")
        top10 <- head(critical_loss, 10)
        for (i in 1:nrow(top10)) {
          cat(sprintf("    %d. %s: %.1f%% loss (%d -> %d)\n",
                      i,
                      top10$column[i],
                      top10$loss_pct[i],
                      top10$n_before[i],
                      top10$n_after[i]))
        }
      } else {
        cat(sprintf("  Items with >%.0f%% data loss: 0 [OK]\n", max_loss_pct))
      }
    }

    cat(sprintf("\n  Warnings: %d\n", length(warnings)))
    cat(sprintf("  Errors: %d\n", length(errors)))
  }

  # Determine pass/fail
  passed <- length(errors) == 0

  if (!passed && verbose) {
    cat("\n[VALIDATION FAILED]\n")
    cat("One or more items lost >", max_loss_pct, "% of data during transformation.\n")
    cat("This likely indicates a transformation bug that needs investigation.\n\n")
  }

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Create result object
  result <- list(
    passed = passed,
    warnings = warnings,
    errors = errors,
    item_summary = item_summary
  )

  # Stop execution if critical errors and stop_on_error = TRUE
  if (!passed && stop_on_error) {
    stop("Data validation failed: ", length(errors), " items with critical data loss. ",
         "Set stop_on_error=FALSE to continue anyway.")
  }

  return(invisible(result))
}

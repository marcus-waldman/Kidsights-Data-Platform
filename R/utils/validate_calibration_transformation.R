#' Validate Calibration Data Transformation for Unexpected Data Loss
#'
#' Compares calibration data before and after transformation to detect unexpected
#' data loss that exceeds reasonable thresholds. Designed for multi-study IRT
#' calibration datasets where different studies contribute different item sets.
#'
#' @param data_before Data frame before transformation
#' @param data_after Data frame after transformation
#' @param step_name Name of the transformation step (for reporting)
#' @param max_loss_pct Maximum acceptable data loss percentage (default: 10%)
#' @param lexicon_name Name of lexicon to use for missing code identification (default: "equate")
#' @param study_column Name of study column for per-study breakdown (default: "study")
#' @param verbose Logical. Print detailed output? Default: TRUE
#' @param stop_on_error Logical. Stop execution if critical data loss detected? Default: TRUE
#'
#' @return List with validation results:
#'   - passed: Logical, TRUE if validation passed
#'   - warnings: Character vector of warning messages
#'   - errors: Character vector of error messages
#'   - item_summary: Data frame with per-item statistics
#'   - study_summary: Data frame with per-study statistics (if study_column provided)
#'
#' @details
#' This function checks for:
#' 1. Row count changes (should be identical unless filtering)
#' 2. Column-level data loss exceeding max_loss_pct
#' 3. Items where non-null counts drop dramatically
#' 4. Per-study data integrity (optional)
#'
#' Expected data loss sources:
#' - Missing codes being set to NA (acceptable)
#' - Invalid values being removed (acceptable if < max_loss_pct)
#' - Transformation bugs (UNACCEPTABLE - triggers error)
#'
#' Multi-study considerations:
#' - Not all items present in all studies (this is expected)
#' - Different missing code conventions across studies (9, 99, -9)
#' - Variable item coverage by study (NE25: 276 items, NSCH21: 28 items)
#'
#' @examples
#' \dontrun{
#' # Validate wide format creation in IRT calibration pipeline
#' historical_data <- readRDS("temp/historical_calibration_data.rds")
#' calibration_wide <- DBI::dbReadTable(db$con, "calibration_dataset_2020_2025")
#'
#' validation <- validate_calibration_transformation(
#'   data_before = historical_data,
#'   data_after = calibration_wide,
#'   step_name = "wide_format_creation",
#'   max_loss_pct = 10,
#'   lexicon_name = "equate"
#' )
#'
#' if (!validation$passed) {
#'   stop("Calibration data validation failed!")
#' }
#' }
#'
#' @export
validate_calibration_transformation <- function(data_before,
                                                 data_after,
                                                 step_name = "transformation",
                                                 max_loss_pct = 10,
                                                 lexicon_name = "equate",
                                                 study_column = "study",
                                                 verbose = TRUE,
                                                 stop_on_error = TRUE) {

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat(sprintf("VALIDATING CALIBRATION DATA TRANSFORMATION: %s\n", toupper(step_name)))
    cat(strrep("=", 80), "\n\n")
  }

  warnings <- character()
  errors <- character()
  item_summary <- data.frame()
  study_summary <- data.frame()

  # Load codebook to identify missing codes
  codebook_path <- "codebook/data/codebook.json"
  missing_code_map <- list()

  if (file.exists(codebook_path)) {
    cb <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

    # Extract missing codes for each item
    for (item_name in names(cb$items)) {
      item <- cb$items[[item_name]]

      # Get variable name for this lexicon
      if (!is.null(item$lexicons[[lexicon_name]])) {
        var_name <- item$lexicons[[lexicon_name]]
        if (is.list(var_name)) var_name <- var_name[[1]]
        var_name_lower <- tolower(var_name)

        # Get response set reference
        response_ref <- item$content$response_options[[lexicon_name]]
        if (is.list(response_ref)) response_ref <- response_ref[[1]]

        if (!is.null(response_ref)) {
          # Get response set (response_ref is already the direct key name)
          response_set <- cb$response_sets[[response_ref]]

          if (!is.null(response_set)) {
            # Extract values marked as missing
            missing_vals <- c()
            for (opt in response_set) {
              val <- if (is.list(opt$value)) opt$value[[1]] else opt$value
              is_missing <- !is.null(opt$missing) && (opt$missing == TRUE || opt$missing == "true")

              if (is_missing) {
                missing_vals <- c(missing_vals, as.numeric(val))
              }
            }

            if (length(missing_vals) > 0) {
              missing_code_map[[var_name_lower]] <- missing_vals
            }
          }
        }
      }
    }

    if (verbose && length(missing_code_map) > 0) {
      cat(sprintf("[INFO] Loaded missing codes for %d items from codebook\n", length(missing_code_map)))
      cat("        Validation will exclude missing codes from baseline counts\n\n")
    }
  }

  # Check 1: Row count validation
  if (verbose) cat("[1/4] Validating row counts\n")

  n_before <- nrow(data_before)
  n_after <- nrow(data_after)

  if (n_before != n_after) {
    loss_pct <- 100 * (n_before - n_after) / n_before
    msg <- sprintf("Row count changed: %d -> %d (%.1f%% loss)",
                   n_before, n_after, loss_pct)

    # Flag as error if >5% row loss
    if (abs(loss_pct) > 5) {
      errors <- c(errors, msg)
      if (verbose) cat(sprintf("      ERROR: %s\n", msg))
    } else {
      warnings <- c(warnings, msg)
      if (verbose) cat(sprintf("      WARNING: %s\n", msg))
    }
  } else {
    if (verbose) cat(sprintf("      Row count: %d (unchanged) [OK]\n", n_before))
  }

  # Check 2: Column count validation
  if (verbose) cat("\n[2/4] Validating column counts\n")

  n_cols_before <- ncol(data_before)
  n_cols_after <- ncol(data_after)

  if (verbose) {
    cat(sprintf("      Columns before: %d\n", n_cols_before))
    cat(sprintf("      Columns after: %d\n", n_cols_after))
    if (n_cols_after > n_cols_before) {
      cat(sprintf("      New columns added: %d [OK]\n", n_cols_after - n_cols_before))
    } else if (n_cols_after < n_cols_before) {
      cat(sprintf("      Columns removed: %d\n", n_cols_before - n_cols_after))
    }
  }

  # Check 3: Item-level data loss validation
  if (verbose) cat("\n[3/4] Validating item-level data integrity\n")

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
    if (col_lower %in% c("id", "pid", "record_id", "retrieved_date", "source_project",
                         "extraction_id", "redcap_event_name", "study", "years",
                         "wgt", "authenticity_weight", "studynum", "devflag",
                         "maskflag", "cooksd_quantile", "lex_equate")) {
      next
    }

    # Count non-null values
    # For n_before, exclude values that are marked as missing codes in codebook
    before_values <- data_before[[col_before]]

    if (col_lower %in% names(missing_code_map)) {
      # Exclude missing codes from before count
      missing_codes <- missing_code_map[[col_lower]]
      n_before_col <- sum(!is.na(before_values) & !(before_values %in% missing_codes))
    } else {
      # No missing codes defined, count all non-NA
      n_before_col <- sum(!is.na(before_values))
    }

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

  # Check 4: Per-study breakdown (optional)
  if (verbose) cat("\n[4/4] Validating per-study data integrity\n")

  if (study_column %in% names(data_before) && study_column %in% names(data_after)) {
    studies <- unique(c(data_before[[study_column]], data_after[[study_column]]))
    studies <- studies[!is.na(studies)]

    study_stats <- list()

    for (study in studies) {
      # Count records by study
      n_before_study <- sum(data_before[[study_column]] == study, na.rm = TRUE)
      n_after_study <- sum(data_after[[study_column]] == study, na.rm = TRUE)

      if (n_before_study > 0) {
        loss_count_study <- n_before_study - n_after_study
        loss_pct_study <- 100 * loss_count_study / n_before_study

        study_stats[[study]] <- data.frame(
          study = study,
          n_before = n_before_study,
          n_after = n_after_study,
          loss_count = loss_count_study,
          loss_pct = loss_pct_study,
          stringsAsFactors = FALSE
        )

        if (verbose) {
          if (abs(loss_pct_study) < 1) {
            cat(sprintf("      %s: %d records (%.1f%% change) [OK]\n",
                        study, n_after_study, loss_pct_study))
          } else {
            cat(sprintf("      %s: %d -> %d (%.1f%% loss)\n",
                        study, n_before_study, n_after_study, loss_pct_study))
          }
        }

        # Flag if study loses >5% of records
        if (loss_pct_study > 5) {
          msg <- sprintf("Study %s lost %.1f%% of records (%d -> %d)",
                         study, loss_pct_study, n_before_study, n_after_study)
          warnings <- c(warnings, msg)
        }
      }
    }

    if (length(study_stats) > 0) {
      study_summary <- do.call(rbind, study_stats)
      rownames(study_summary) <- NULL
    }
  } else {
    if (verbose) {
      cat(sprintf("      Study column '%s' not found in data - skipping per-study validation\n",
                  study_column))
    }
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
    cat(sprintf("One or more items lost > %d%% of data during %s.\n",
                max_loss_pct, step_name))
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
    item_summary = item_summary,
    study_summary = study_summary
  )

  # Stop execution if critical errors and stop_on_error = TRUE
  if (!passed && stop_on_error) {
    stop(sprintf("Calibration data validation failed for '%s': %d items with critical data loss. ",
                 step_name, length(errors)),
         "Set stop_on_error=FALSE to continue anyway.")
  }

  return(invisible(result))
}

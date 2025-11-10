#' Validate Calibration Data Quality
#'
#' Performs automated quality checks on IRT calibration data and generates
#' a comprehensive flag report for data quality issues.
#'
#' @param db_path Path to DuckDB database. Default: "data/duckdb/kidsights_local.duckdb"
#' @param codebook_path Path to codebook JSON file. Default: "codebook/data/codebook.json"
#' @param output_path Path for CSV flag report. Default: "docs/irt_scoring/quality_flags.csv"
#' @param verbose Logical. Print progress messages? Default: TRUE
#'
#' @return Data frame with quality flags (invisibly)
#'
#' @details
#' This function detects 3 types of data quality issues:
#'
#' **FLAG 1: Category Mismatch**
#' - Fewer observed categories than expected (ceiling/floor effects)
#' - Different observed categories than expected (invalid values)
#'
#' **FLAG 2: Negative Age-Response Correlation**
#' - Correlation between age and item response is negative
#' - Suggests developmental regression (usually unexpected)
#'
#' **FLAG 3: Non-Sequential Response Values**
#' - Response values have gaps (e.g., {0,1,9} instead of {0,1,2})
#' - Detects undocumented missing codes
#'
#' @examples
#' \dontrun{
#' # Run validation and generate report
#' flags <- validate_calibration_quality()
#'
#' # Custom output location
#' flags <- validate_calibration_quality(
#'   output_path = "reports/quality_check_2025.csv"
#' )
#' }
#'
#' @export
validate_calibration_quality <- function(
    db_path = "data/duckdb/kidsights_local.duckdb",
    codebook_path = "codebook/data/codebook.json",
    output_path = "docs/irt_scoring/quality_flags.csv",
    verbose = TRUE) {

  # ===========================================================================
  # Setup
  # ===========================================================================

  if (verbose) {
    cat("\n")
    cat(strrep("=", 80), "\n")
    cat("CALIBRATION DATA QUALITY VALIDATION\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Load required packages
  required_packages <- c("duckdb", "DBI", "dplyr", "tidyr", "jsonlite", "purrr")

  if (verbose) cat("[SETUP] Loading required packages\n")

  for (pkg in required_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required. Install with: install.packages('%s')",
                   pkg, pkg))
    }
  }

  library(duckdb)
  library(dplyr)
  library(tidyr)
  library(jsonlite)
  library(purrr)

  if (verbose) cat("        Packages loaded successfully\n\n")

  # ===========================================================================
  # Load Data
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("LOADING DATA\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Load codebook
  if (verbose) cat("[1/3] Loading codebook from:", codebook_path, "\n")

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found at: %s", codebook_path))
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  if (verbose) {
    cat(sprintf("      Items: %d\n", length(codebook$items)))
    cat(sprintf("      Response sets: %d\n\n", length(codebook$response_sets)))
  }

  # Load calibration data
  if (verbose) cat("[2/3] Connecting to DuckDB:", db_path, "\n")

  if (!file.exists(db_path)) {
    stop(sprintf("Database not found at: %s", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

  # Check if combined table exists
  tables <- DBI::dbListTables(conn)

  if (!"calibration_dataset_2020_2025_restructured" %in% tables) {
    DBI::dbDisconnect(conn)
    stop("Table 'calibration_dataset_2020_2025_restructured' not found. Run calibration pipeline first.")
  }

  if (verbose) cat("      Loading calibration_dataset_2020_2025_restructured table\n")

  calibration_data <- DBI::dbGetQuery(conn, "
    SELECT *
    FROM calibration_dataset_2020_2025_restructured
  ")

  DBI::dbDisconnect(conn)

  if (verbose) {
    cat(sprintf("      Records: %d\n", nrow(calibration_data)))
    cat(sprintf("      Columns: %d\n\n", ncol(calibration_data)))
  }

  # Extract item columns (exclude metadata)
  metadata_cols <- c("study_num", "id", "years", "study")
  item_cols <- setdiff(names(calibration_data), metadata_cols)

  if (verbose) {
    cat("[3/3] Data loading complete\n")
    cat(sprintf("      Items to validate: %d\n", length(item_cols)))
    cat(sprintf("      Studies: %s\n\n", paste(unique(calibration_data$study), collapse = ", ")))
  }

  # ===========================================================================
  # Extract Expected Response Categories from Codebook
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("EXTRACTING EXPECTED RESPONSE CATEGORIES\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Build lookup table: item_id (lex_equate) -> expected_values
  expected_categories <- list()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]

    # Get lex_equate name
    if (!is.null(item$lexicons$equate)) {
      equate_name <- item$lexicons$equate

      # Get response set reference
      # Try ne25 first, then fall back to other studies
      response_ref <- NULL

      if (!is.null(item$content$response_options$ne25)) {
        response_ref <- item$content$response_options$ne25
      } else if (!is.null(item$content$response_options$ne22)) {
        response_ref <- item$content$response_options$ne22
      } else if (!is.null(item$content$response_options$ne20)) {
        response_ref <- item$content$response_options$ne20
      }

      # Extract values from response_sets
      # Check if response_ref is a valid reference (single string, not a multi-option string)
      if (!is.null(response_ref) &&
          length(response_ref) == 1 &&
          is.character(response_ref) &&
          response_ref %in% names(codebook$response_sets)) {

        response_set <- codebook$response_sets[[response_ref]]

        # Extract numeric values
        values <- sapply(response_set, function(opt) {
          as.numeric(opt$value)
        })

        # Exclude missing value codes (-9, 99, etc.) if marked as missing
        non_missing_values <- sapply(seq_along(response_set), function(i) {
          opt <- response_set[[i]]
          is_missing <- !is.null(opt$missing) && opt$missing == TRUE
          if (!is_missing) {
            return(as.numeric(opt$value))
          } else {
            return(NA)
          }
        })

        non_missing_values <- non_missing_values[!is.na(non_missing_values)]

        expected_categories[[equate_name]] <- sort(non_missing_values)
      }
    }
  }

  if (verbose) {
    cat(sprintf("[OK] Extracted expected categories for %d items\n\n", length(expected_categories)))
  }

  # ===========================================================================
  # Extract Instrument Mapping from Codebook
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("EXTRACTING INSTRUMENT MAPPING\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Build lookup table: item_id (lex_equate) -> instruments array
  instrument_lookup <- list()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]

    # Get lex_equate name
    if (!is.null(item$lexicons$equate)) {
      equate_name <- item$lexicons$equate

      # Get instruments array
      if (!is.null(item$instruments) && length(item$instruments) > 0) {
        instrument_lookup[[equate_name]] <- unlist(item$instruments)
      }
    }
  }

  # Count items by instrument
  kidsights_items <- names(instrument_lookup)[
    sapply(instrument_lookup, function(x) "Kidsights Measurement Tool" %in% x)
  ]

  gsed_pf_items <- names(instrument_lookup)[
    sapply(instrument_lookup, function(x) "GSED-PF" %in% x)
  ]

  if (verbose) {
    cat(sprintf("[OK] Extracted instruments for %d items\n", length(instrument_lookup)))
    cat(sprintf("      Kidsights Measurement Tool items: %d\n", length(kidsights_items)))
    cat(sprintf("      GSED-PF items: %d\n\n", length(gsed_pf_items)))
  }

  # ===========================================================================
  # Initialize Flags Data Frame
  # ===========================================================================

  flags <- data.frame(
    item_id = character(),
    study = character(),
    flag_type = character(),
    flag_severity = character(),
    observed_categories = character(),
    expected_categories = character(),
    correlation_value = numeric(),
    n_responses = integer(),
    pct_missing = numeric(),
    description = character(),
    stringsAsFactors = FALSE
  )

  # ===========================================================================
  # FLAG 1: Category Mismatch Detection
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("FLAG 1: CATEGORY MISMATCH DETECTION\n")
    cat(strrep("=", 80), "\n\n")
  }

  flag1_count <- 0

  for (item in item_cols) {
    # Skip if no expected categories defined
    if (!item %in% names(expected_categories)) {
      next
    }

    expected_vals <- expected_categories[[item]]

    # Check each study separately
    for (study_name in unique(calibration_data$study)) {
      study_data <- calibration_data %>%
        dplyr::filter(study == study_name) %>%
        dplyr::pull(!!item)

      # Remove NAs
      study_data_clean <- study_data[!is.na(study_data)]

      if (length(study_data_clean) == 0) {
        next  # No data for this study-item combination
      }

      observed_vals <- sort(unique(study_data_clean))

      # Check for mismatch
      fewer_categories <- all(observed_vals %in% expected_vals) && length(observed_vals) < length(expected_vals)
      different_categories <- !all(observed_vals %in% expected_vals)

      if (fewer_categories || different_categories) {
        flag_type_detail <- if (different_categories) {
          "CATEGORY_MISMATCH_INVALID"
        } else {
          "CATEGORY_MISMATCH_FEWER"
        }

        flag_severity <- if (different_categories) "ERROR" else "WARNING"

        description <- if (different_categories) {
          sprintf("Invalid values detected: %s (expected: %s)",
                  paste(setdiff(observed_vals, expected_vals), collapse = ","),
                  paste(expected_vals, collapse = ","))
        } else {
          sprintf("Fewer categories observed (%d/%d): %s (expected: %s)",
                  length(observed_vals), length(expected_vals),
                  paste(observed_vals, collapse = ","),
                  paste(expected_vals, collapse = ","))
        }

        flags <- rbind(flags, data.frame(
          item_id = item,
          study = study_name,
          flag_type = flag_type_detail,
          flag_severity = flag_severity,
          observed_categories = paste(observed_vals, collapse = ","),
          expected_categories = paste(expected_vals, collapse = ","),
          correlation_value = NA,
          n_responses = length(study_data_clean),
          pct_missing = sum(is.na(study_data)) / length(study_data) * 100,
          description = description,
          stringsAsFactors = FALSE
        ))

        flag1_count <- flag1_count + 1
      }
    }
  }

  if (verbose) {
    cat(sprintf("[FLAG 1] Detected %d category mismatches\n\n", flag1_count))
  }

  # ===========================================================================
  # FLAG 2: Negative Age-Response Correlation
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("FLAG 2: NEGATIVE AGE-RESPONSE CORRELATION\n")
    cat("         (Kidsights Measurement Tool items only)\n")
    cat(strrep("=", 80), "\n\n")
  }

  flag2_count <- 0

  for (item in item_cols) {
    # FILTER: Only check age-gradient for Kidsights Measurement Tool items
    item_instruments <- instrument_lookup[[item]]

    if (is.null(item_instruments) ||
        !("Kidsights Measurement Tool" %in% item_instruments)) {
      next  # Skip GSED-PF and other non-developmental items
    }

    for (study_name in unique(calibration_data$study)) {
      study_data <- calibration_data %>%
        dplyr::filter(study == study_name) %>%
        dplyr::select(years, !!item)

      # Remove NAs
      study_data_clean <- study_data[!is.na(study_data[[item]]), ]

      if (nrow(study_data_clean) < 10) {
        next  # Need at least 10 observations for correlation
      }

      # Calculate correlation
      cor_value <- cor(study_data_clean$years, study_data_clean[[item]], method = "pearson")

      if (!is.na(cor_value) && cor_value < 0) {
        flags <- rbind(flags, data.frame(
          item_id = item,
          study = study_name,
          flag_type = "NEGATIVE_CORRELATION",
          flag_severity = "WARNING",
          observed_categories = NA,
          expected_categories = NA,
          correlation_value = cor_value,
          n_responses = nrow(study_data_clean),
          pct_missing = sum(is.na(study_data[[item]])) / nrow(study_data) * 100,
          description = sprintf("Negative correlation (r = %.3f): Older children score lower", cor_value),
          stringsAsFactors = FALSE
        ))

        flag2_count <- flag2_count + 1
      }
    }
  }

  if (verbose) {
    cat(sprintf("[FLAG 2] Detected %d negative correlations\n\n", flag2_count))
  }

  # ===========================================================================
  # FLAG 3: Non-Sequential Response Values
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("FLAG 3: NON-SEQUENTIAL RESPONSE VALUES\n")
    cat(strrep("=", 80), "\n\n")
  }

  flag3_count <- 0

  for (item in item_cols) {
    for (study_name in unique(calibration_data$study)) {
      study_data <- calibration_data %>%
        dplyr::filter(study == study_name) %>%
        dplyr::pull(!!item)

      # Remove NAs
      study_data_clean <- study_data[!is.na(study_data)]

      if (length(study_data_clean) == 0) {
        next
      }

      observed_vals <- sort(unique(study_data_clean))

      # Check if sequential: diff(sorted values) should all be 1
      if (length(observed_vals) > 1) {
        diffs <- diff(observed_vals)
        is_sequential <- all(diffs == 1)

        if (!is_sequential) {
          flags <- rbind(flags, data.frame(
            item_id = item,
            study = study_name,
            flag_type = "NON_SEQUENTIAL",
            flag_severity = "WARNING",
            observed_categories = paste(observed_vals, collapse = ","),
            expected_categories = NA,
            correlation_value = NA,
            n_responses = length(study_data_clean),
            pct_missing = sum(is.na(study_data)) / length(study_data) * 100,
            description = sprintf("Non-sequential values: %s (gaps: %s)",
                                  paste(observed_vals, collapse = ","),
                                  paste(diffs, collapse = ",")),
            stringsAsFactors = FALSE
          ))

          flag3_count <- flag3_count + 1
        }
      }
    }
  }

  if (verbose) {
    cat(sprintf("[FLAG 3] Detected %d non-sequential value patterns\n\n", flag3_count))
  }

  # ===========================================================================
  # Export Results
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("EXPORTING RESULTS\n")
    cat(strrep("=", 80), "\n\n")
  }

  # Create output directory if needed
  output_dir <- dirname(output_path)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    if (verbose) cat(sprintf("[INFO] Created directory: %s\n", output_dir))
  }

  # Write CSV
  write.csv(flags, output_path, row.names = FALSE)

  if (verbose) {
    cat(sprintf("[OK] Quality flags exported to: %s\n", output_path))
    cat(sprintf("     Total flags: %d\n", nrow(flags)))
    cat(sprintf("     - Category mismatches: %d\n", flag1_count))
    cat(sprintf("     - Negative correlations: %d\n", flag2_count))
    cat(sprintf("     - Non-sequential values: %d\n\n", flag3_count))
  }

  # ===========================================================================
  # Summary
  # ===========================================================================

  if (verbose) {
    cat(strrep("=", 80), "\n")
    cat("VALIDATION COMPLETE\n")
    cat(strrep("=", 80), "\n\n")

    if (nrow(flags) > 0) {
      cat("Top 10 Flagged Items:\n")
      top_flags <- flags %>%
        dplyr::group_by(item_id) %>%
        dplyr::summarise(
          flag_count = dplyr::n(),
          studies_affected = paste(unique(study), collapse = ", "),
          .groups = "drop"
        ) %>%
        dplyr::arrange(dplyr::desc(flag_count)) %>%
        dplyr::slice(1:10)

      print(top_flags, n = 10)
      cat("\n")
    } else {
      cat("[OK] No quality flags detected! Data looks clean.\n\n")
    }

    cat("Next steps:\n")
    cat("  1. Review flags: ", output_path, "\n")
    cat("  2. Generate interactive report: docs/irt_scoring/calibration_quality_report.qmd\n")
    cat("  3. Investigate flagged items and consult data team\n\n")
  }

  invisible(flags)
}

# ============================================================================
# STANDALONE EXECUTION
# ============================================================================

# If script is run directly (not sourced), execute the function
if (!interactive()) {
  validate_calibration_quality(
    db_path = "data/duckdb/kidsights_local.duckdb",
    codebook_path = "codebook/data/codebook.json",
    output_path = "docs/irt_scoring/quality_flags.csv",
    verbose = TRUE
  )
}

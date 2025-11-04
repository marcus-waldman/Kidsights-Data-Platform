# =============================================================================
# Mplus Dataset Preparation Functions
# =============================================================================
# Purpose: Extract and prepare datasets for Mplus IRT calibration
#          Handles item extraction, sample filtering, variable naming
#
# Usage: Called by prepare_mplus_calibration.R or standalone
# Version: 1.0
# Created: January 4, 2025
# =============================================================================

#' Extract Items for Calibration
#'
#' Main function to extract items from database for Mplus calibration
#' Orchestrates: connection -> filtering -> item extraction -> naming -> sorting
#'
#' @param scale_name Scale identifier ("kidsights" or "psychosocial")
#' @param sample_filters Named list of filter conditions (e.g., list(eligible = TRUE, authentic = TRUE))
#' @param age_range Optional age range in months: c(min, max)
#' @param codebook_path Path to codebook.json
#' @param db_path Path to DuckDB database
#' @return Data frame with items ready for Mplus (columns sorted alphabetically)
#' @export
extract_items_for_calibration <- function(scale_name,
                                          sample_filters = NULL,
                                          age_range = NULL,
                                          codebook_path = "codebook/data/codebook.json",
                                          db_path = "data/duckdb/kidsights_local.duckdb") {

  cat("\n", strrep("=", 70), "\n")
  cat("EXTRACTING ITEMS FOR MPLUS CALIBRATION\n")
  cat(strrep("=", 70), "\n\n")

  cat(sprintf("Scale: %s\n", scale_name))
  if (!is.null(sample_filters)) {
    cat(sprintf("Sample filters: %s\n", paste(names(sample_filters), "=", sample_filters, collapse = ", ")))
  }
  if (!is.null(age_range)) {
    cat(sprintf("Age range: %d to %d months\n", age_range[1], age_range[2]))
  }
  cat("\n")

  # ---------------------------------------------------------------------------
  # Step 1: Get item names from codebook
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 1: GET ITEM NAMES FROM CODEBOOK\n")
  cat(strrep("-", 70), "\n\n")

  item_info <- get_items_from_codebook(scale_name, codebook_path)

  cat(sprintf("Found %d items for %s scale\n", length(item_info$items), scale_name))
  cat(sprintf("Calibration study: %s\n", item_info$calibration_study))
  cat(sprintf("Naming convention: %s\n", item_info$naming_convention))
  cat("\n")

  # ---------------------------------------------------------------------------
  # Step 2: Connect to database and load data
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 2: LOAD DATA FROM DATABASE\n")
  cat(strrep("-", 70), "\n\n")

  if (!file.exists(db_path)) {
    stop(sprintf("Database not found: %s", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  cat(sprintf("[OK] Connected to database: %s\n", db_path))

  # Load transformed data (original responses with derived variables, not imputed)
  query <- "SELECT * FROM ne25_transformed"
  data <- DBI::dbGetQuery(conn, query)
  DBI::dbDisconnect(conn)

  cat(sprintf("[OK] Loaded %d records from ne25_transformed\n\n", nrow(data)))

  # ---------------------------------------------------------------------------
  # Step 3: Apply sample filters
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 3: APPLY SAMPLE FILTERS\n")
  cat(strrep("-", 70), "\n\n")

  data_filtered <- apply_sample_filters(data, sample_filters, age_range)

  cat(sprintf("Records after filtering: %d (%.1f%% of original)\n\n",
              nrow(data_filtered), 100 * nrow(data_filtered) / nrow(data)))

  # ---------------------------------------------------------------------------
  # Step 4: Map database columns to correct naming convention
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 4: MAP DATABASE COLUMNS TO NAMING CONVENTION\n")
  cat(strrep("-", 70), "\n\n")

  if (scale_name == "kidsights") {
    # Map database columns to lex_equate (uppercase)
    item_mapping <- map_database_to_lexequate(item_info$items, codebook_path)
  } else if (scale_name == "psychosocial") {
    # Standardize to lowercase
    item_mapping <- standardize_ps_names(item_info$items)
  } else {
    stop(sprintf("Unknown scale: %s", scale_name))
  }

  cat(sprintf("Mapped %d items to %s naming convention\n\n",
              length(item_mapping), item_info$naming_convention))

  # ---------------------------------------------------------------------------
  # Step 5: Extract items and sort alphabetically
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 5: EXTRACT ITEMS AND SORT ALPHABETICALLY\n")
  cat(strrep("-", 70), "\n\n")

  # Extract key identifier columns (use only those that exist)
  id_cols_requested <- c("study_id", "pid", "record_id")
  id_cols <- id_cols_requested[id_cols_requested %in% names(data_filtered)]

  if (length(id_cols) == 0) {
    cat("[WARN] No identifier columns found, using row numbers\n")
    id_data <- data.frame(row_num = 1:nrow(data_filtered))
  } else {
    id_data <- data_filtered[, id_cols, drop = FALSE]
    cat(sprintf("Identifier columns: %s\n", paste(id_cols, collapse = ", ")))
  }

  # Extract items using mapping
  item_data <- extract_mapped_items(data_filtered, item_mapping)

  # Sort items alphabetically
  item_data_sorted <- sort_items_alphabetically(item_data)

  # Combine identifiers + sorted items
  calibration_data <- cbind(id_data, item_data_sorted)

  cat(sprintf("[OK] Extracted %d items\n", ncol(item_data_sorted)))
  cat(sprintf("[OK] Items sorted alphabetically\n"))
  cat(sprintf("     First 5 items: %s\n",
              paste(head(names(item_data_sorted), 5), collapse = ", ")))
  cat(sprintf("     Last 5 items: %s\n\n",
              paste(tail(names(item_data_sorted), 5), collapse = ", ")))

  # ---------------------------------------------------------------------------
  # Step 6: Report missing data patterns
  # ---------------------------------------------------------------------------

  cat(strrep("-", 70), "\n")
  cat("STEP 6: MISSING DATA SUMMARY\n")
  cat(strrep("-", 70), "\n\n")

  missing_counts <- colSums(is.na(item_data_sorted))
  missing_pct <- 100 * missing_counts / nrow(calibration_data)

  cat(sprintf("Missing data across %d items:\n", ncol(item_data_sorted)))
  cat(sprintf("  Min: %.1f%%\n", min(missing_pct)))
  cat(sprintf("  Median: %.1f%%\n", median(missing_pct)))
  cat(sprintf("  Max: %.1f%%\n", max(missing_pct)))
  cat(sprintf("  Mean: %.1f%%\n\n", mean(missing_pct)))

  # Report items with high missingness (>20%)
  high_missing <- missing_pct[missing_pct > 20]
  if (length(high_missing) > 0) {
    cat(sprintf("[WARN] %d items with >20%% missing:\n", length(high_missing)))
    for (item in names(high_missing)) {
      cat(sprintf("  %s: %.1f%% missing\n", item, high_missing[item]))
    }
    cat("\n")
  }

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------

  cat(strrep("=", 70), "\n")
  cat("EXTRACTION COMPLETE\n")
  cat(strrep("=", 70), "\n\n")

  cat("Summary:\n")
  cat(sprintf("  Scale: %s\n", scale_name))
  cat(sprintf("  Records: %d\n", nrow(calibration_data)))
  cat(sprintf("  Items: %d\n", ncol(item_data_sorted)))
  cat(sprintf("  Columns: %d (identifiers + items)\n", ncol(calibration_data)))
  cat("\n")

  return(calibration_data)
}

#' Apply Sample Filters
#'
#' Apply user-specified filters to dataset
#' Common filters: eligible, authentic, age ranges, study-specific criteria
#'
#' @param data Data frame to filter
#' @param filters Named list of filter conditions
#' @param age_range Optional age range in months: c(min, max)
#' @return Filtered data frame
#' @export
apply_sample_filters <- function(data, filters = NULL, age_range = NULL) {

  cat("Applying sample filters...\n")

  original_n <- nrow(data)
  data_filtered <- data

  # Apply named filters
  if (!is.null(filters)) {
    for (filter_name in names(filters)) {
      filter_value <- filters[[filter_name]]

      if (!filter_name %in% names(data_filtered)) {
        cat(sprintf("[WARN] Filter variable '%s' not found in data\n", filter_name))
        next
      }

      # Apply filter
      before_n <- nrow(data_filtered)
      data_filtered <- data_filtered[data_filtered[[filter_name]] == filter_value, ]
      after_n <- nrow(data_filtered)

      cat(sprintf("  %s = %s: %d -> %d records (removed %d)\n",
                  filter_name, filter_value, before_n, after_n, before_n - after_n))
    }
  }

  # Apply age range filter
  if (!is.null(age_range)) {
    if ("age_in_months" %in% names(data_filtered)) {
      before_n <- nrow(data_filtered)
      data_filtered <- data_filtered[
        data_filtered$age_in_months >= age_range[1] &
        data_filtered$age_in_months <= age_range[2],
      ]
      after_n <- nrow(data_filtered)

      cat(sprintf("  age_in_months in [%d, %d]: %d -> %d records (removed %d)\n",
                  age_range[1], age_range[2], before_n, after_n, before_n - after_n))
    } else {
      cat("[WARN] age_in_months column not found, skipping age filter\n")
    }
  }

  if (is.null(filters) && is.null(age_range)) {
    cat("  No filters specified, using full dataset\n")
  }

  cat(sprintf("\n[OK] Final sample: %d records (%.1f%% of original)\n",
              nrow(data_filtered), 100 * nrow(data_filtered) / original_n))

  return(data_filtered)
}

#' Get Items from Codebook
#'
#' Retrieve item names for specified scale from codebook
#' Returns items with IRT parameters for the calibration study
#'
#' @param scale_name Scale identifier ("kidsights" or "psychosocial")
#' @param codebook_path Path to codebook.json
#' @return List with items, calibration_study, naming_convention
#' @export
get_items_from_codebook <- function(scale_name, codebook_path = "codebook/data/codebook.json") {

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  items <- character(0)
  calibration_study <- NULL
  naming_convention <- NULL

  if (scale_name == "kidsights") {
    # Extract items with lex_equate and NE22 calibration
    calibration_study <- "NE22"
    naming_convention <- "lex_equate (uppercase)"

    for (item_name in names(codebook$items)) {
      item <- codebook$items[[item_name]]

      # Check if item has lex_equate lexicon
      if ("lexicons" %in% names(item) && "equate" %in% names(item$lexicons)) {
        lex_equate <- item$lexicons$equate

        # Check if item has IRT parameters for NE22
        if ("psychometric" %in% names(item) &&
            "irt_parameters" %in% names(item$psychometric) &&
            calibration_study %in% names(item$psychometric$irt_parameters)) {

          items <- c(items, lex_equate)
        }
      }
    }

  } else if (scale_name == "psychosocial") {
    # Extract psychosocial items (ps001-ps049)
    calibration_study <- "NE22"
    naming_convention <- "lowercase (ps###)"

    for (item_name in names(codebook$items)) {
      item <- codebook$items[[item_name]]

      # Check if item has ne25 lexicon starting with "ps"
      if ("lexicons" %in% names(item) && "ne25" %in% names(item$lexicons)) {
        ne25_name <- item$lexicons$ne25

        if (grepl("^ps[0-9]{3}$", ne25_name)) {
          # Check if item has IRT parameters for NE22
          if ("psychometric" %in% names(item) &&
              "irt_parameters" %in% names(item$psychometric) &&
              calibration_study %in% names(item$psychometric$irt_parameters)) {

            items <- c(items, ne25_name)
          }
        }
      }
    }

  } else {
    stop(sprintf("Unknown scale: %s", scale_name))
  }

  if (length(items) == 0) {
    stop(sprintf("No items found for scale '%s' with calibration study '%s'",
                 scale_name, calibration_study))
  }

  return(list(
    items = items,
    calibration_study = calibration_study,
    naming_convention = naming_convention
  ))
}

#' Map Database Columns to lex_equate
#'
#' Create mapping from database column names (ne25 lexicon) to lex_equate names
#' Used for Kidsights items (uppercase naming)
#'
#' @param lex_equate_items Character vector of lex_equate item names (e.g., "AA4", "AA5")
#' @param codebook_path Path to codebook.json
#' @return Named character vector: names = lex_equate, values = database columns
#' @export
map_database_to_lexequate <- function(lex_equate_items, codebook_path = "codebook/data/codebook.json") {

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  mapping <- character(0)

  for (lex_equate_name in lex_equate_items) {
    # Find item in codebook
    found <- FALSE

    for (item_name in names(codebook$items)) {
      item <- codebook$items[[item_name]]

      if ("lexicons" %in% names(item) && "equate" %in% names(item$lexicons)) {
        if (item$lexicons$equate == lex_equate_name) {
          # Get ne25 lexicon as database column name
          if ("ne25" %in% names(item$lexicons)) {
            db_col <- item$lexicons$ne25
            mapping[lex_equate_name] <- db_col
            found <- TRUE
            break
          }
        }
      }
    }

    if (!found) {
      cat(sprintf("[WARN] No database mapping found for lex_equate item: %s\n", lex_equate_name))
    }
  }

  cat(sprintf("[OK] Mapped %d/%d items to database columns\n", length(mapping), length(lex_equate_items)))

  return(mapping)
}

#' Standardize Psychosocial Names
#'
#' Ensure psychosocial items use lowercase naming (ps001-ps049)
#' Database already uses lowercase for psychosocial items
#'
#' @param ps_items Character vector of psychosocial item names
#' @return Named character vector: names = lowercase, values = database columns (same)
#' @export
standardize_ps_names <- function(ps_items) {

  # For psychosocial items, database columns are already lowercase
  # Create identity mapping
  mapping <- ps_items
  names(mapping) <- ps_items

  cat(sprintf("[OK] Using lowercase naming for %d psychosocial items\n", length(mapping)))

  return(mapping)
}

#' Extract Mapped Items
#'
#' Extract items from data using name mapping
#' Renames columns to target naming convention
#'
#' @param data Data frame with database column names
#' @param item_mapping Named character vector (names = target, values = database columns)
#' @return Data frame with renamed items
#' @export
extract_mapped_items <- function(data, item_mapping) {

  item_data <- data.frame(matrix(NA, nrow = nrow(data), ncol = length(item_mapping)))
  names(item_data) <- names(item_mapping)

  for (target_name in names(item_mapping)) {
    db_col <- item_mapping[target_name]

    if (db_col %in% names(data)) {
      item_data[[target_name]] <- data[[db_col]]
    } else {
      cat(sprintf("[WARN] Database column '%s' not found for item '%s'\n", db_col, target_name))
    }
  }

  return(item_data)
}

#' Sort Items Alphabetically
#'
#' Sort item columns alphabetically for consistency in Mplus
#' Maintains data integrity (row order preserved)
#'
#' @param item_data Data frame with items
#' @return Data frame with columns sorted alphabetically
#' @export
sort_items_alphabetically <- function(item_data) {

  sorted_names <- sort(names(item_data))
  item_data_sorted <- item_data[, sorted_names, drop = FALSE]

  return(item_data_sorted)
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

# # Extract Kidsights items for calibration
# kidsights_data <- extract_items_for_calibration(
#   scale_name = "kidsights",
#   sample_filters = list(eligible = TRUE, authentic = TRUE),
#   age_range = c(0, 72),  # 0-72 months
#   codebook_path = "codebook/data/codebook.json",
#   db_path = "data/duckdb/kidsights_local.duckdb"
# )
#
# # Extract psychosocial items for calibration
# psychosocial_data <- extract_items_for_calibration(
#   scale_name = "psychosocial",
#   sample_filters = list(eligible = TRUE, authentic = TRUE),
#   age_range = NULL,  # No age restriction
#   codebook_path = "codebook/data/codebook.json",
#   db_path = "data/duckdb/kidsights_local.duckdb"
# )

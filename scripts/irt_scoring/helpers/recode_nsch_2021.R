#' Recode NSCH 2021 Data for Kidsights Calibration
#'
#' Harmonizes NSCH 2021 national benchmarking data to match Kidsights item structure.
#' Maps CAHMI 2021 variable names to lex_equate naming convention using codebook.json.
#'
#' @param codebook_path Character. Path to codebook.json file.
#'   Default: "codebook/data/codebook.json"
#' @param db_path Character. Path to DuckDB database file.
#'   Default: "data/duckdb/kidsights_local.duckdb"
#' @param age_filter_years Numeric. Maximum age in years to include (default: 6).
#'   NSCH calibration typically uses children < 6 years old.
#'
#' @return Data frame with columns:
#'   - id: Numeric HHID (original NSCH household ID)
#'   - years: Child age in years (calculated from birth date)
#'   - {lex_equate items}: All Kidsights items with CAHMI21 mappings (uppercase)
#'
#' @details
#' This function performs the following transformations:
#' 1. Loads NSCH 2021 data from DuckDB table `nsch_2021`
#' 2. Maps CAHMI21 variable names to lex_equate names via codebook
#' 3. Calculates child age in years from birth month/year
#' 4. Handles reverse-coded items (scales items so higher = more developed)
#' 5. Filters to children < age_filter_years and with at least 2 item responses
#' 6. Returns ALL filtered records (no sampling - use for calibration table creation)
#'
#' Reverse coding logic:
#' - Most items are reverse-coded (e.g., Yes=1, No=2 → Yes=0, No=1)
#' - Forward-coded items: DISTRACTED, COUNTTO, TEMPER, NEWACTIVITY
#'   (higher values already indicate more severe/advanced)
#'
#' @examples
#' \dontrun{
#' # Load NSCH 2021 data for calibration
#' nsch21 <- recode_nsch_2021(
#'   codebook_path = "codebook/data/codebook.json",
#'   db_path = "data/duckdb/kidsights_local.duckdb"
#' )
#'
#' # Check output structure
#' cat(sprintf("Records: %d, Items: %d\n", nrow(nsch21), ncol(nsch21) - 3))
#' }
#'
#' @export
recode_nsch_2021 <- function(codebook_path = "codebook/data/codebook.json",
                              db_path = "data/duckdb/kidsights_local.duckdb",
                              age_filter_years = 6) {

  # ============================================================================
  # Load Dependencies
  # ============================================================================

  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' is required. Install with: install.packages('duckdb')")
  }
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required. Install with: install.packages('dplyr')")
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required. Install with: install.packages('jsonlite')")
  }
  if (!requireNamespace("stringr", quietly = TRUE)) {
    stop("Package 'stringr' is required. Install with: install.packages('stringr')")
  }

  # Load libraries for use in function
  library(dplyr)
  library(stringr)

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("RECODE NSCH 2021 DATA FOR KIDSIGHTS CALIBRATION\n")
  cat(strrep("=", 80), "\n\n")

  # ============================================================================
  # Load Codebook and Extract CAHMI21 Mappings
  # ============================================================================

  cat("[1/7] Loading codebook from:", codebook_path, "\n")

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found at: %s", codebook_path))
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Extract items with cahmi21 lexicon
  cahmi21_mappings <- list()
  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
    cahmi21_val <- item$lexicons$cahmi21

    if (!is.null(cahmi21_val)) {
      equate_name <- item$lexicons$equate

      # Handle both single values and arrays
      if (is.list(cahmi21_val) && length(cahmi21_val) > 0) {
        # Array lexicon (historical naming variations across NSCH years)
        # Use LAST element (most recent naming convention for NSCH 2021)
        cahmi21_val <- cahmi21_val[[length(cahmi21_val)]]
      }

      # Map the variable name to equate name
      if (is.character(cahmi21_val) && nchar(cahmi21_val) > 0) {
        cahmi21_mappings[[cahmi21_val]] <- equate_name
      }
    }
  }

  cat(sprintf("      Found %d items with cahmi21 lexicon mappings\n", length(cahmi21_mappings)))

  if (length(cahmi21_mappings) == 0) {
    stop("No items with cahmi21 lexicon found in codebook")
  }

  # Get CAHMI21 variable names (all uppercase in NSCH data)
  cahmi21_vars <- toupper(names(cahmi21_mappings))

  # ============================================================================
  # Load NSCH 2021 Data from DuckDB
  # ============================================================================

  cat("[2/7] Loading NSCH 2021 data from DuckDB:", db_path, "\n")

  if (!file.exists(db_path)) {
    stop(sprintf("DuckDB database not found at: %s", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

  # Check table exists
  tables <- DBI::dbGetQuery(conn, "SHOW TABLES")
  if (!"nsch_2021" %in% tables$name) {
    DBI::dbDisconnect(conn)
    stop("Table 'nsch_2021' not found in database")
  }

  # Check if harmonized columns already exist (Phase 3 optimization)
  all_cols <- DBI::dbGetQuery(conn, "SELECT * FROM nsch_2021 LIMIT 0")
  all_col_names <- names(all_cols)

  # Get lex_equate names from codebook
  lex_equate_names <- unique(unlist(cahmi21_mappings))
  available_harmonized <- intersect(lex_equate_names, all_col_names)

  use_preharmonized <- length(available_harmonized) >= 25  # At least 25/29 items harmonized

  if (use_preharmonized) {
    cat("      [FAST PATH] Using pre-harmonized columns from database\n")
    cat(sprintf("      %d/%d harmonized columns found\n",
                length(available_harmonized), length(lex_equate_names)))

    # Load harmonized columns directly (much faster)
    select_cols <- c("HHID", "YEAR", "BIRTH_YR", "BIRTH_MO", "SC_AGE_YEARS", available_harmonized)
    query <- sprintf("SELECT %s FROM nsch_2021", paste(select_cols, collapse = ", "))

    nsch21 <- DBI::dbGetQuery(conn, query)
    DBI::dbDisconnect(conn)

  } else {
    cat("      [SLOW PATH] Pre-harmonized columns not available, transforming on-demand\n")
    cat("      (Run harmonization pipeline to enable fast path)\n")

    # Select only needed columns (age vars + items that exist in both codebook and data)
    # First check which cahmi21 variables exist in the NSCH data
    available_cahmi21_vars <- intersect(cahmi21_vars, toupper(all_col_names))

    cat(sprintf("      %d/%d cahmi21 variables found in NSCH 2021 data\n",
                length(available_cahmi21_vars), length(cahmi21_vars)))

    if (length(available_cahmi21_vars) == 0) {
      DBI::dbDisconnect(conn)
      stop("No cahmi21 variables found in NSCH 2021 data")
    }

    # Build query with specific columns (include HHID for unique identifier)
    select_cols <- c("HHID", "YEAR", "BIRTH_YR", "BIRTH_MO", "SC_AGE_YEARS", available_cahmi21_vars)
    query <- sprintf("SELECT %s FROM nsch_2021", paste(select_cols, collapse = ", "))

    nsch21 <- DBI::dbGetQuery(conn, query)
    DBI::dbDisconnect(conn)
  }

  cat(sprintf("      Loaded %d records with %d columns\n", nrow(nsch21), ncol(nsch21)))

  # ============================================================================
  # Calculate Child Age in Years
  # ============================================================================

  cat("[3/7] Calculating child age in years\n")

  nsch21 <- nsch21 %>%
    dplyr::mutate(
      # Calculate age from birth date (assume survey date = Sept 15 of survey year)
      admin_date = as.Date(paste0(YEAR, "-09-15")),
      birth_date = as.Date(paste0(BIRTH_YR, "-",
                                   stringr::str_pad(BIRTH_MO, width = 2, side = "left", pad = "0"),
                                   "-15")),
      days = as.integer(admin_date - birth_date),
      years = days / 365.25
    ) %>%
    dplyr::mutate(
      # Clean up age calculation (handle missing/implausible values)
      years = dplyr::case_when(
        is.na(years) ~ SC_AGE_YEARS + 0.5,  # If missing, use reported age + 0.5
        years < SC_AGE_YEARS ~ SC_AGE_YEARS,  # If calculated < reported, use reported
        floor(years) > SC_AGE_YEARS ~ SC_AGE_YEARS + 1 - 1e-3,  # If calculated > reported+1, cap
        .default = years
      )
    )

  # ============================================================================
  # Filter to Age Range and Select Columns
  # ============================================================================

  cat(sprintf("[4/7] Filtering to children < %d years old\n", age_filter_years))

  if (use_preharmonized) {
    nsch21_filtered <- nsch21 %>%
      dplyr::filter(SC_AGE_YEARS < age_filter_years) %>%
      dplyr::select(HHID, years, SC_AGE_YEARS, dplyr::any_of(available_harmonized))
  } else {
    nsch21_filtered <- nsch21 %>%
      dplyr::filter(SC_AGE_YEARS < age_filter_years) %>%
      dplyr::select(HHID, years, SC_AGE_YEARS, dplyr::any_of(available_cahmi21_vars))
  }

  cat(sprintf("      %d records remain after age filter\n", nrow(nsch21_filtered)))

  # ============================================================================
  # Handle Reverse-Coded Items (Using Codebook as Single Source of Truth)
  # ============================================================================

  if (use_preharmonized) {
    cat("[5/7] Skipping transformation (using pre-harmonized columns)\n")
  } else {
    cat("[5/7] Determining coding direction from codebook\n")

  # Build reverse/forward lists from codebook instead of hardcoding
  forwardly_coded21 <- character(0)
  reverse_coded21 <- character(0)

  for (cahmi_var in available_cahmi21_vars) {
    # Find this variable in codebook
    should_reverse <- NA

    for (item_id in names(codebook$items)) {
      item <- codebook$items[[item_id]]

      if (!is.null(item$lexicons$cahmi21) && item$lexicons$cahmi21 == cahmi_var) {
        should_reverse <- item$scoring$reverse
        if (is.null(should_reverse)) {
          # Default to reverse coding if not specified (conservative approach)
          should_reverse <- TRUE
          cat(sprintf("        [WARN] No scoring.reverse for %s, defaulting to reverse\n", cahmi_var))
        }
        break
      }
    }

    # Categorize based on codebook specification
    if (is.na(should_reverse)) {
      cat(sprintf("        [WARN] %s not found in codebook, defaulting to reverse\n", cahmi_var))
      reverse_coded21 <- c(reverse_coded21, cahmi_var)
    } else if (should_reverse) {
      reverse_coded21 <- c(reverse_coded21, cahmi_var)
    } else {
      forwardly_coded21 <- c(forwardly_coded21, cahmi_var)
    }
  }

  cat(sprintf("      Reverse-coding %d items (per codebook)\n", length(reverse_coded21)))
  cat(sprintf("      Forward-coding %d items (per codebook)\n", length(forwardly_coded21)))

  # Recode NSCH missing codes (>= 90) to NA BEFORE reverse/forward coding
  # NSCH uses variable-specific missing codes in the 90-99 range:
  #   90 = Not applicable (some variables)
  #   94 = Data not ascertained
  #   95 = Refused
  #   96 = Not applicable
  #   97 = Don't know
  #   98 = Missing
  #   99 = Missing (some variables, e.g., ONEWORD)
  # Conservative approach: recode ALL values >= 90 to prevent contamination
  cat("      Recoding NSCH missing codes (>= 90) to NA\n")
  nsch21_filtered <- nsch21_filtered %>%
    dplyr::mutate(
      dplyr::across(dplyr::any_of(available_cahmi21_vars),
                    function(x) dplyr::case_when(
                      x >= 90 ~ NA_real_,
                      .default = x
                    ))
    )

  # Apply reverse/forward coding
  # Reverse: max - x (so Yes=1 becomes max=2, 2-1=1; No=2 becomes 2-2=0)
  # Forward: x - min (so min value becomes 0)
  nsch21_filtered <- nsch21_filtered %>%
    dplyr::mutate(
      dplyr::across(dplyr::any_of(reverse_coded21),
                    function(x) abs(x - max(x, na.rm = TRUE))),
      dplyr::across(dplyr::any_of(forwardly_coded21),
                    function(x) x - min(x, na.rm = TRUE))
    )
  }  # End of slow path transformation

  # ============================================================================
  # Filter to Records with Sufficient Data
  # ============================================================================

  cat("[6/7] Filtering to records with at least 2 item responses\n")

  # Count non-missing items per record
  item_cols_for_filtering <- if (use_preharmonized) available_harmonized else available_cahmi21_vars

  item_counts <- nsch21_filtered %>%
    dplyr::select(dplyr::any_of(item_cols_for_filtering)) %>%
    apply(1, function(x) sum(!is.na(x)))

  ids_keep <- which(item_counts > 1)
  nsch21_filtered <- nsch21_filtered[ids_keep, ]

  cat(sprintf("      %d records remain with sufficient data\n", nrow(nsch21_filtered)))

  # Remove records with missing age
  nsch21_filtered <- nsch21_filtered %>% dplyr::filter(!is.na(years))

  cat(sprintf("      %d records remain after removing missing age\n", nrow(nsch21_filtered)))

  # ============================================================================
  # Map CAHMI21 Names to lex_equate Names (Slow Path Only)
  # ============================================================================

  if (use_preharmonized) {
    cat("[7/7] Skipping variable renaming (already using lex_equate names)\n")
  } else {
    cat("[7/7] Mapping CAHMI21 variable names to lex_equate\n")

    # Create named vector for renaming: new_name = old_name (dplyr::rename format)
    # Swap: lex_equate (new name) = cahmi21 (old name)
    rename_mapping <- character()
    for (cahmi_var in available_cahmi21_vars) {
      # cahmi21 lexicon values in codebook are uppercase, matching database columns
      if (cahmi_var %in% names(cahmi21_mappings)) {
        lex_equate_name <- cahmi21_mappings[[cahmi_var]]
        rename_mapping[lex_equate_name] <- cahmi_var  # new_name = old_name
      }
    }

    cat(sprintf("      Mapping %d variables to lex_equate names\n", length(rename_mapping)))
  }

  # Create integer IDs following convention: YYFFFSNNNNNN
  # YY=21, FFF=999 (national), S=0 (NSCH), N=sequential (6 digits)
  if (use_preharmonized) {
    nsch21_final <- nsch21_filtered %>%
      dplyr::mutate(
        row_num = dplyr::row_number(),
        id = 219990000000 + row_num  # 219990000001, 219990000002, etc.
      ) %>%
      dplyr::select(-row_num, -HHID) %>%
      dplyr::relocate(id, years) %>%
      dplyr::select(-SC_AGE_YEARS)
  } else {
    nsch21_final <- nsch21_filtered %>%
      dplyr::mutate(
        row_num = dplyr::row_number(),
        id = 219990000000 + row_num  # 219990000001, 219990000002, etc.
      ) %>%
      dplyr::select(-row_num, -HHID) %>%
      dplyr::rename(!!!rename_mapping) %>%
      dplyr::relocate(id, years) %>%
      dplyr::select(-SC_AGE_YEARS)
  }

  # ============================================================================
  # Summary and Return
  # ============================================================================

  cat("\n")
  cat(strrep("-", 80), "\n")
  cat("NSCH 2021 Recoding Complete\n")
  cat(strrep("-", 80), "\n")
  cat(sprintf("Final records:    %d\n", nrow(nsch21_final)))
  cat(sprintf("Kidsights items:  %d\n", ncol(nsch21_final) - 2))  # id, years
  cat(sprintf("Age range:        %.2f - %.2f years\n",
              min(nsch21_final$years, na.rm = TRUE),
              max(nsch21_final$years, na.rm = TRUE)))

  # Calculate missingness per item
  item_cols <- setdiff(names(nsch21_final), c("id", "years"))
  missingness <- sapply(nsch21_final[, item_cols], function(x) sum(is.na(x)) / length(x) * 100)

  cat(sprintf("Item missingness: %.1f%% - %.1f%% (median: %.1f%%)\n",
              min(missingness), max(missingness), median(missingness)))
  cat("\n")

  return(nsch21_final)
}

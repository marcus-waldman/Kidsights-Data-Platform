#' Recode NSCH 2022 Data for Kidsights Calibration
#'
#' Harmonizes NSCH 2022 national benchmarking data to match Kidsights item structure.
#' Maps CAHMI 2022 variable names to lex_equate naming convention using codebook.json.
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
#'   - {lex_equate items}: All Kidsights items with CAHMI22 mappings (uppercase)
#'
#' @details
#' This function performs the following transformations:
#' 1. Loads NSCH 2022 data from DuckDB table `nsch_2022_raw`
#' 2. Maps CAHMI22 variable names to lex_equate names via codebook
#' 3. Calculates child age in years from birth month/year
#' 4. Handles reverse-coded items (scales items so higher = more developed)
#' 5. Filters to children < age_filter_years and with at least 2 item responses
#' 6. Returns ALL filtered records (no sampling - use for calibration table creation)
#'
#' Reverse coding logic:
#' - Most items are reverse-coded (e.g., Yes=1, No=2 → Yes=0, No=1)
#' - Forward-coded items (NSCH 2022 specific):
#'   BOUNCEABALL, DISTRACTED, COUNTTO_R, TEMPER_R, CALMDOWN_R,
#'   DRAWACIRCLE, DRAWAFACE, DRAWAPERSON, RHYMEWORD_R, WAITFORTURN
#'   (higher values already indicate more severe/advanced)
#'
#' @examples
#' \dontrun{
#' # Load NSCH 2022 data for calibration
#' nsch22 <- recode_nsch_2022(
#'   codebook_path = "codebook/data/codebook.json",
#'   db_path = "data/duckdb/kidsights_local.duckdb"
#' )
#'
#' # Check output structure
#' cat(sprintf("Records: %d, Items: %d\n", nrow(nsch22), ncol(nsch22) - 3))
#' }
#'
#' @export
recode_nsch_2022 <- function(codebook_path = "codebook/data/codebook.json",
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
  cat("RECODE NSCH 2022 DATA FOR KIDSIGHTS CALIBRATION\n")
  cat(strrep("=", 80), "\n\n")

  # ============================================================================
  # Load Codebook and Extract CAHMI22 Mappings
  # ============================================================================

  cat("[1/7] Loading codebook from:", codebook_path, "\n")

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found at: %s", codebook_path))
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Extract items with cahmi22 lexicon
  cahmi22_mappings <- list()
  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]
    if (!is.null(item$lexicons$cahmi22) && nchar(item$lexicons$cahmi22) > 0) {
      cahmi22_mappings[[item$lexicons$cahmi22]] <- item$lexicons$equate
    }
  }

  cat(sprintf("      Found %d items with cahmi22 lexicon mappings\n", length(cahmi22_mappings)))

  if (length(cahmi22_mappings) == 0) {
    stop("No items with cahmi22 lexicon found in codebook")
  }

  # Get CAHMI22 variable names (all uppercase in NSCH data)
  cahmi22_vars <- toupper(names(cahmi22_mappings))

  # ============================================================================
  # Load NSCH 2022 Data from DuckDB
  # ============================================================================

  cat("[2/7] Loading NSCH 2022 data from DuckDB:", db_path, "\n")

  if (!file.exists(db_path)) {
    stop(sprintf("DuckDB database not found at: %s", db_path))
  }

  conn <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

  # Check table exists
  tables <- DBI::dbGetQuery(conn, "SHOW TABLES")
  if (!"nsch_2022_raw" %in% tables$name) {
    DBI::dbDisconnect(conn)
    stop("Table 'nsch_2022_raw' not found in database")
  }

  # Select only needed columns (age vars + items that exist in both codebook and data)
  # First check which cahmi22 variables exist in the NSCH data
  all_cols <- DBI::dbGetQuery(conn, "SELECT * FROM nsch_2022_raw LIMIT 0")
  available_cahmi22_vars <- intersect(cahmi22_vars, toupper(names(all_cols)))

  cat(sprintf("      %d/%d cahmi22 variables found in NSCH 2022 data\n",
              length(available_cahmi22_vars), length(cahmi22_vars)))

  if (length(available_cahmi22_vars) == 0) {
    DBI::dbDisconnect(conn)
    stop("No cahmi22 variables found in NSCH 2022 data")
  }

  # Build query with specific columns (include HHID for unique identifier)
  select_cols <- c("HHID", "YEAR", "BIRTH_YR", "BIRTH_MO", "SC_AGE_YEARS", available_cahmi22_vars)
  query <- sprintf("SELECT %s FROM nsch_2022_raw", paste(select_cols, collapse = ", "))

  nsch22 <- DBI::dbGetQuery(conn, query)
  DBI::dbDisconnect(conn)

  cat(sprintf("      Loaded %d records with %d columns\n", nrow(nsch22), ncol(nsch22)))

  # ============================================================================
  # Calculate Child Age in Years
  # ============================================================================

  cat("[3/7] Calculating child age in years\n")

  nsch22 <- nsch22 %>%
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

  nsch22_filtered <- nsch22 %>%
    dplyr::filter(SC_AGE_YEARS < age_filter_years) %>%
    dplyr::select(HHID, years, SC_AGE_YEARS, dplyr::any_of(available_cahmi22_vars))

  cat(sprintf("      %d records remain after age filter\n", nrow(nsch22_filtered)))

  # ============================================================================
  # Handle Reverse-Coded Items
  # ============================================================================

  cat("[5/7] Handling reverse-coded items\n")

  # Forward-coded items for NSCH 2022 (different from 2021!)
  forwardly_coded22 <- c("BOUNCEABALL", "DISTRACTED", "COUNTTO_R", "TEMPER_R",
                          "CALMDOWN_R", "DRAWACIRCLE", "DRAWAFACE", "DRAWAPERSON",
                          "RHYMEWORD_R", "WAITFORTURN")
  forwardly_coded22 <- intersect(forwardly_coded22, available_cahmi22_vars)

  # All other items are reverse-coded
  reverse_coded22 <- setdiff(available_cahmi22_vars, forwardly_coded22)

  cat(sprintf("      Reverse-coding %d items\n", length(reverse_coded22)))
  cat(sprintf("      Forward-coding %d items\n", length(forwardly_coded22)))

  # Apply reverse/forward coding
  # Reverse: max - x (so Yes=1 becomes max=2, 2-1=1; No=2 becomes 2-2=0)
  # Forward: x - min (so min value becomes 0)
  nsch22_filtered <- nsch22_filtered %>%
    dplyr::mutate(
      dplyr::across(dplyr::any_of(reverse_coded22),
                    function(x) abs(x - max(x, na.rm = TRUE))),
      dplyr::across(dplyr::any_of(forwardly_coded22),
                    function(x) x - min(x, na.rm = TRUE))
    )

  # ============================================================================
  # Filter to Records with Sufficient Data
  # ============================================================================

  cat("[6/7] Filtering to records with at least 2 item responses\n")

  # Count non-missing items per record
  item_counts <- nsch22_filtered %>%
    dplyr::select(dplyr::any_of(available_cahmi22_vars)) %>%
    apply(1, function(x) sum(!is.na(x)))

  ids_keep <- which(item_counts > 1)
  nsch22_filtered <- nsch22_filtered[ids_keep, ]

  cat(sprintf("      %d records remain with sufficient data\n", nrow(nsch22_filtered)))

  # Remove records with missing age
  nsch22_filtered <- nsch22_filtered %>% dplyr::filter(!is.na(years))

  cat(sprintf("      %d records remain after removing missing age\n", nrow(nsch22_filtered)))

  # ============================================================================
  # Map CAHMI22 Names to lex_equate Names
  # ============================================================================

  cat("[7/7] Mapping CAHMI22 variable names to lex_equate\n")

  # Create named vector for renaming: new_name = old_name (dplyr::rename format)
  # Swap: lex_equate (new name) = cahmi22 (old name)
  rename_mapping <- character()
  for (cahmi_var in available_cahmi22_vars) {
    # cahmi22 lexicon values in codebook are uppercase, matching database columns
    if (cahmi_var %in% names(cahmi22_mappings)) {
      lex_equate_name <- cahmi22_mappings[[cahmi_var]]
      rename_mapping[lex_equate_name] <- cahmi_var  # new_name = old_name
    }
  }

  cat(sprintf("      Mapping %d variables to lex_equate names\n", length(rename_mapping)))

  # Create integer IDs following convention: YYFFFSNNNNNN
  # YY=22, FFF=999 (national), S=0 (NSCH), N=sequential (6 digits)
  nsch22_final <- nsch22_filtered %>%
    dplyr::mutate(
      row_num = dplyr::row_number(),
      id = 229990000000 + row_num  # 229990000001, 229990000002, etc.
    ) %>%
    dplyr::select(-row_num, -HHID) %>%
    dplyr::rename(!!!rename_mapping) %>%
    dplyr::relocate(id, years) %>%
    dplyr::select(-SC_AGE_YEARS)

  # ============================================================================
  # Summary and Return
  # ============================================================================

  cat("\n")
  cat(strrep("-", 80), "\n")
  cat("NSCH 2022 Recoding Complete\n")
  cat(strrep("-", 80), "\n")
  cat(sprintf("Final records:    %d\n", nrow(nsch22_final)))
  cat(sprintf("Kidsights items:  %d\n", ncol(nsch22_final) - 2))  # id, years
  cat(sprintf("Age range:        %.2f - %.2f years\n",
              min(nsch22_final$years, na.rm = TRUE),
              max(nsch22_final$years, na.rm = TRUE)))

  # Calculate missingness per item
  item_cols <- setdiff(names(nsch22_final), c("id", "years"))
  missingness <- sapply(nsch22_final[, item_cols], function(x) sum(is.na(x)) / length(x) * 100)

  cat(sprintf("Item missingness: %.1f%% - %.1f%% (median: %.1f%%)\n",
              min(missingness), max(missingness), median(missingness)))
  cat("\n")

  return(nsch22_final)
}

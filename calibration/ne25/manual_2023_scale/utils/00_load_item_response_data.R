#!/usr/bin/env Rscript

#' Load Item Response Data for Stage 1 Cleaning (Reverse Coding Verification)
#'
#' This script loads the NE25 transformed dataset from DuckDB and prepares it
#' for Mplus analysis in Stage 1 of the item and person cleaning protocol.
#'
#' PIPELINE INTEGRATION:
#'   - This runs BEFORE authenticity screening (Step 6.5) and calibration table (Step 11)
#'   - Uses eligible = TRUE filter only (basic eligibility, no authenticity requirement)
#'   - Cleaning results update codebook, then entire pipeline re-runs from Step 5
#'   - Allows automated integration into NE25 pipeline as early quality gate
#'
#' Data Source:
#'   - ne25_transformed table (full NE25 dataset)
#'   - Filtered to eligible = TRUE (basic eligibility criteria)
#'   - All calibration items extracted from codebook
#'
#' Item Naming Strategy:
#'   - Extraction: Uses ne25 lexicon (lowercase database column names, e.g., "dd101")
#'   - Output: Renamed to equate lexicon (standardized cross-study names, e.g., "DD101")
#'   - Metadata: Contains both equate_name (primary) and ne25_name (for database mapping)
#'
#' Outputs:
#'   - data/temp/stage1_wide.rds: Wide format data (person × item matrix, equate names)
#'       * Filtered to participants with >= 5 valid responses
#'   - data/temp/stage1_item_metadata.rds: Item metadata (equate_name, ne25_name, dimension, domain)
#'   - data/temp/stage1_person_data.rds: Person-level data with covariates
#'       * Identifiers: pid, recordid (renamed from record_id for Mplus compatibility)
#'       * Age: age_in_days, years
#'       * Demographics: female, raceG
#'       * SES: educ_a1, educ_mom, income, fpl
#'       * Family: family_size
#'   - data/temp/stage1_exclusions.rds: Exclusion log for audit trail
#'       * Fields: pid, recordid, n_responses, exclusion_stage, exclusion_reason, exclusion_date
#'       * Tracks participants excluded at Stage 0 (insufficient responses)
#'       * Will accumulate exclusions from Stages 1-3 for complete audit trail
#'
#' Usage:
#'   source("scripts/authenticity_screening/manual_screening/00_load_item_response_data.R")
#'   data <- load_stage1_data()

library(dplyr)
library(tidyr)
library(DBI)
library(duckdb)

# Load utilities
source("R/utils/safe_joins.R")

#' Load Stage 1 Item Response Data
#'
#' @param db_path Path to DuckDB database
#' @param codebook_path Path to codebook.json
#' @param output_dir Directory to save prepared data
#' @return List with wide_data, item_metadata, and person_data
load_stage1_data <- function(db_path = "data/duckdb/kidsights_local.duckdb",
                              codebook_path = "codebook/data/codebook.json",
                              output_dir = "calibration/ne25/manual_2023_scale/data") {

  cat("\n")
  cat("================================================================================\n")
  cat("  LOAD ITEM RESPONSE DATA FOR STAGE 1 CLEANING\n")
  cat("================================================================================\n")
  cat("\n")

  # ==========================================================================
  # STEP 1: CONNECT TO DATABASE
  # ==========================================================================

  cat("=== STEP 1: CONNECT TO DATABASE ===\n\n")

  if (!file.exists(db_path)) {
    stop(sprintf("Database not found: %s", db_path))
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  cat(sprintf("[Connected] %s\n\n", db_path))

  # ==========================================================================
  # STEP 2: LOAD NE25 TRANSFORMED TABLE
  # ==========================================================================

  cat("=== STEP 2: LOAD NE25 TRANSFORMED TABLE ===\n\n")

  # Query ne25_transformed table with eligible filter
  # This table contains:
  #   - pid, record_id: Unique participant identifiers (composite key)
  #   - age_in_days: Age in days
  #   - All raw item responses (lowercase column names)
  #   - eligible: Basic eligibility (CID2-5: consent, caregiver, age 0-6, Nebraska)
  #
  # Filter: eligible = TRUE only
  #   - Includes participants who passed basic eligibility criteria
  #   - Does NOT require authenticity weight (runs before authenticity screening)
  #   - Expected N ≈ 3,507 participants
  #
  # Exclusion: Filter out flagged observations
  #   - Uses ne25_flagged_observations table for influential/problematic records
  #   - Flags include: high latent regression influence, poor person fit

  query <- "SELECT * FROM ne25_transformed WHERE eligible = TRUE"
  transformed_data <- DBI::dbGetQuery(con, query)

  # Load flagged observations to exclude
  flagged_obs <- tryCatch(
    DBI::dbGetQuery(con, "SELECT DISTINCT pid, recordid FROM ne25_flagged_observations"),
    error = function(e) {
      cat("[Warning] Could not load flagged observations table (may not exist yet)\n")
      data.frame(pid = integer(), recordid = integer())
    }
  )

  # Create composite id (pid_recordid) for unique identification
  transformed_data <- transformed_data %>%
    dplyr::mutate(id = paste0(pid, "_", record_id))

  # Filter out flagged observations
  n_before_flagged <- nrow(transformed_data)
  if (nrow(flagged_obs) > 0) {
    # Create matching key for filtering
    flagged_obs <- flagged_obs %>%
      dplyr::mutate(is_flagged = TRUE)

    transformed_data <- transformed_data %>%
      dplyr::left_join(flagged_obs, by = c("pid", "record_id" = "recordid")) %>%
      dplyr::filter(is.na(is_flagged)) %>%
      dplyr::select(-is_flagged)
  }
  n_flagged <- n_before_flagged - nrow(transformed_data)

  cat(sprintf("[Loaded] ne25_transformed table\n"))
  cat(sprintf("  Participants: %d (eligible = TRUE)\n", n_before_flagged))
  if (n_flagged > 0) {
    cat(sprintf("  Flagged observations excluded: %d\n", n_flagged))
    cat(sprintf("  Final sample: %d\n", nrow(transformed_data)))
  }
  cat(sprintf("  Columns: %d (identifiers + items + derived variables)\n", ncol(transformed_data)))
  cat(sprintf("  Age range: %.1f to %.1f days (%.2f to %.2f years)\n",
              min(transformed_data$age_in_days, na.rm = TRUE),
              max(transformed_data$age_in_days, na.rm = TRUE),
              min(transformed_data$age_in_days, na.rm = TRUE) / 365.25,
              max(transformed_data$age_in_days, na.rm = TRUE) / 365.25))
  cat("\n")

  # ==========================================================================
  # STEP 3: LOAD CODEBOOK TO EXTRACT DOMAIN ASSIGNMENTS
  # ==========================================================================

  cat("=== STEP 3: LOAD CODEBOOK FOR DOMAIN ASSIGNMENTS ===\n\n")

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  cat(sprintf("[Loaded] Codebook: %d items\n\n", length(codebook$items)))

  # Extract item metadata (matching logic from 00_prepare_cv_data.R)
  item_metadata_list <- list()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]

    # Skip if no lexicons or no equate/ne25 names
    if (is.null(item$lexicons) || is.null(item$lexicons$equate) || is.null(item$lexicons$ne25)) {
      next
    }

    # Extract both equate (standardized) and ne25 (database) names
    equate_name <- item$lexicons$equate
    ne25_name <- item$lexicons$ne25

    if (is.list(equate_name)) equate_name <- unlist(equate_name)
    if (is.list(ne25_name)) ne25_name <- unlist(ne25_name)

    if (is.null(equate_name) || length(equate_name) == 0 || equate_name == "" ||
        is.null(ne25_name) || length(ne25_name) == 0 || ne25_name == "") {
      next
    }

    # Get domain assignment
    domain_value <- NA
    if (!is.null(item$domains) && !is.null(item$domains$kidsights)) {
      domain_value <- item$domains$kidsights$value
      if (is.list(domain_value)) domain_value <- unlist(domain_value)
    }

    if (is.na(domain_value) || length(domain_value) == 0 || domain_value == "") {
      next
    }

    # Map domain to dimension
    # Dimension 1: Psychosocial/Behavioral (psychosocial_problems_general, socemo)
    # Dimension 2: Developmental Skills (motor, coglan)
    dimension <- if (domain_value %in% c("psychosocial_problems_general", "socemo")) {
      1L
    } else if (domain_value %in% c("motor", "coglan")) {
      2L
    } else {
      NA_integer_
    }

    # Skip items without valid dimension
    if (is.na(dimension)) {
      next
    }

    # Get response set information
    n_categories <- NA
    if (!is.null(item$content) && !is.null(item$content$response_options)) {
      if ("ne25" %in% names(item$content$response_options)) {
        resp_ref <- item$content$response_options$ne25
        if (is.list(resp_ref)) resp_ref <- unlist(resp_ref)

        if (!is.null(resp_ref) && length(resp_ref) == 1) {
          if (grepl("^\\$ref:", resp_ref)) {
            resp_ref <- sub("^\\$ref:", "", resp_ref)
          }

          if (resp_ref %in% names(codebook$response_sets)) {
            response_set <- codebook$response_sets[[resp_ref]]
            valid_categories <- sapply(response_set, function(opt) {
              val <- if (is.list(opt$value)) opt$value[[1]] else opt$value
              as.numeric(val)
            })
            n_categories <- sum(valid_categories >= 0)
          }
        }
      }
    }

    # Store metadata
    # Use equate_name as primary identifier, keep ne25_name for database mapping
    item_metadata_list[[equate_name]] <- data.frame(
      equate_name = equate_name,           # Primary ID: standardized name (e.g., "DD101")
      ne25_name = tolower(ne25_name),      # Database column name (lowercase)
      item_id = item_id,                   # Original codebook ID
      dimension = dimension,
      domain = domain_value,
      n_categories = n_categories,
      stringsAsFactors = FALSE
    )
  }

  # Combine metadata
  item_metadata <- dplyr::bind_rows(item_metadata_list)

  # NOTE: phq2_total is now in person_data (not item_data)
  # It's a person-level composite score, so it belongs with demographics/covariates

  cat(sprintf("[Extracted] Item metadata: %d calibration items\n", nrow(item_metadata)))
  cat(sprintf("  - Dimension 1 (Psychosocial/Behavioral): %d items\n",
              sum(item_metadata$dimension == 1, na.rm = TRUE)))
  cat(sprintf("  - Dimension 2 (Developmental Skills): %d items\n",
              sum(item_metadata$dimension == 2, na.rm = TRUE)))
  cat("\n")

  # ==========================================================================
  # STEP 4: FILTER TO ITEMS PRESENT IN TRANSFORMED DATA
  # ==========================================================================

  cat("=== STEP 4: ALIGN ITEMS WITH TRANSFORMED DATA ===\n\n")

  # Get item column names from transformed_data
  # Exclude person-level identifiers and derived variables
  # Person columns: pid, record_id, age_in_days, authenticity_weight,
  #                 eligible, authentic, meets_inclusion, etc.
  # We want only raw item response columns (lowercase, from REDCap)

  # Get all derived and metadata column names to exclude
  # NOTE: We keep phq2_total for depression screening analysis
  phq_gad_to_exclude <- grep("^(phq|gad)", names(transformed_data), value = TRUE)
  phq_gad_to_exclude <- setdiff(phq_gad_to_exclude, "phq2_total")  # Keep phq2_total

  excluded_cols <- c(
    "pid", "record_id", "age_in_days", "authenticity_weight",
    "eligible", "authentic", "meets_inclusion",
    # Derived variables from Step 5 (add common prefixes)
    grep("^(female|male|raceG|educ_|income|fpl|family_size|childcare_|cc_|parent_|child_ace)",
         names(transformed_data), value = TRUE),
    phq_gad_to_exclude  # PHQ/GAD variables except phq2_total
  )

  item_cols <- setdiff(names(transformed_data), excluded_cols)

  cat(sprintf("[Transformed data] %d potential item columns found\n", length(item_cols)))

  # Filter item_metadata to only items present in transformed_data
  # Match using ne25_name (database column names are lowercase)
  item_metadata_filtered <- item_metadata %>%
    dplyr::filter(ne25_name %in% item_cols)

  cat(sprintf("[Matched] %d items have metadata\n", nrow(item_metadata_filtered)))

  missing_metadata <- setdiff(item_cols, item_metadata_filtered$ne25_name)
  if (length(missing_metadata) > 0) {
    cat(sprintf("[Warning] %d items in transformed data lack metadata (will be excluded):\n",
                length(missing_metadata)))
    cat(sprintf("  %s\n", paste(head(missing_metadata, 10), collapse = ", ")))
    if (length(missing_metadata) > 10) {
      cat(sprintf("  ... and %d more\n", length(missing_metadata) - 10))
    }
  }

  # Final item list: ne25 names for extraction from database
  final_ne25_cols <- item_metadata_filtered$ne25_name

  cat(sprintf("\n[Final] %d items with complete metadata\n", length(final_ne25_cols)))
  cat(sprintf("  - Dimension 1: %d items\n",
              sum(item_metadata_filtered$dimension == 1)))
  cat(sprintf("  - Dimension 2: %d items\n",
              sum(item_metadata_filtered$dimension == 2)))
  cat("\n")

  # ==========================================================================
  # STEP 5: PREPARE WIDE FORMAT DATA
  # ==========================================================================

  cat("=== STEP 5: PREPARE WIDE FORMAT DATA ===\n\n")

  # Extract person-level data with covariates
  # Covariates needed for Stage 3 cleaning (multivariate regression: factor_scores ~ age + sex + covariates)
  # Note: authenticity_weight may not exist yet (this runs before authenticity screening)

  # Base columns to extract
  person_cols_to_extract <- c(
    # Identifiers (Mplus requires: pid + recordid, no underscores)
    "pid", "record_id", "age_in_days",
    # Demographics (core predictors for Stage 3)
    "female",           # Sex (binary: TRUE/FALSE)
    "raceG",           # Race/ethnicity (categorical)
    # Socioeconomic status
    "educ_a1",         # Education level (respondent)
    "educ_mom",        # Mother's education
    "income",          # Household income
    "fpl",             # Federal poverty level percentage
    # Family structure
    "family_size",     # Household size
    # Mental health screening
    "phq2_total"       # PHQ-2 depression screening (0-6 scale)
  )

  # Check which columns actually exist (some may be missing in early pipeline runs)
  available_person_cols <- intersect(person_cols_to_extract, names(transformed_data))
  missing_person_cols <- setdiff(person_cols_to_extract, names(transformed_data))

  if (length(missing_person_cols) > 0) {
    cat(sprintf("[Warning] %d expected person-level columns not found in data:\n",
                length(missing_person_cols)))
    cat(sprintf("  %s\n", paste(missing_person_cols, collapse = ", ")))
    cat("  These may be derived variables not yet created in pipeline\n\n")
  }

  person_data <- transformed_data %>%
    dplyr::select(dplyr::all_of(available_person_cols)) %>%
    dplyr::mutate(years = age_in_days / 365.25) %>%  # Convert to years for Mplus
    dplyr::rename(recordid = record_id)  # Mplus doesn't allow underscores in variable names

  cat(sprintf("[Person data] Extracted %d person-level columns\n", ncol(person_data)))
  cat(sprintf("  Identifiers: pid, recordid (renamed from record_id)\n"))
  cat(sprintf("  Age: age_in_days, years\n"))
  cat(sprintf("  Covariates: %d available\n", length(available_person_cols) - 3))  # -3 for id cols (pid, recordid, age_in_days)

  # Create name mapping: ne25_name → equate_name
  # Why dual naming?
  #   - ne25 names: Lowercase database column names (how data is stored)
  #   - equate names: Standardized cross-study identifiers (DD101, EG16, etc.)
  #   - Mplus models and codebook updates use equate names for consistency
  name_mapping <- item_metadata_filtered %>%
    dplyr::select(ne25_name, equate_name)

  # Extract item responses using ne25 names (database column names)
  wide_data_ne25 <- transformed_data %>%
    dplyr::select(pid, record_id, dplyr::all_of(final_ne25_cols))

  # Rename columns from ne25 → equate (standardized names)
  # Create named vector for rename: c("new_name" = "old_name")
  # Example: c("DD101" = "dd101", "DD102" = "dd102", ...)
  rename_vec <- setNames(name_mapping$ne25_name, name_mapping$equate_name)

  wide_data <- wide_data_ne25 %>%
    dplyr::rename(dplyr::all_of(rename_vec)) %>%
    dplyr::rename(recordid = record_id)  # Mplus doesn't allow underscores

  cat(sprintf("[Name mapping] Renamed %d items from ne25 → equate lexicon\n",
              length(rename_vec)))
  cat(sprintf("  Example: %s → %s\n",
              name_mapping$ne25_name[1], name_mapping$equate_name[1]))

  cat(sprintf("[Wide data] %d participants × %d items\n",
              nrow(wide_data), ncol(wide_data) - 2))  # -2 for id columns (pid, recordid)

  # Compute missingness statistics (item-level)
  item_missingness <- wide_data %>%
    dplyr::select(-pid, -recordid) %>%
    dplyr::summarise(dplyr::across(dplyr::everything(), ~mean(is.na(.)))) %>%
    tidyr::pivot_longer(dplyr::everything(), names_to = "item_name", values_to = "pct_missing")

  cat(sprintf("  Missing data: %.1f%% overall\n",
              100 * mean(item_missingness$pct_missing)))
  cat(sprintf("  Items with >50%% missing: %d\n",
              sum(item_missingness$pct_missing > 0.5)))
  cat(sprintf("  Items with >75%% missing: %d\n",
              sum(item_missingness$pct_missing > 0.75)))
  cat("\n")

  # ==========================================================================
  # STEP 5.5: FILTER PARTICIPANTS WITH INSUFFICIENT RESPONSES
  # ==========================================================================

  cat("=== STEP 5.5: FILTER BY RESPONSE COUNT ===\n\n")

  # Count valid (non-NA) responses per person
  response_counts <- wide_data %>%
    dplyr::mutate(
      n_responses = rowSums(!is.na(dplyr::select(., -pid, -recordid)))
    ) %>%
    dplyr::select(pid, recordid, n_responses)

  # Apply minimum response threshold (>= 5 valid responses)
  min_responses <- 5
  insufficient_responses <- response_counts %>%
    dplyr::filter(n_responses < min_responses)

  cat(sprintf("Minimum response threshold: %d valid items\n", min_responses))
  cat(sprintf("  Participants with < %d responses: %d (%.1f%%)\n",
              min_responses,
              nrow(insufficient_responses),
              100 * nrow(insufficient_responses) / nrow(wide_data)))
  cat(sprintf("  Response count distribution:\n"))
  cat(sprintf("    0 responses: %d\n", sum(response_counts$n_responses == 0)))
  cat(sprintf("    1-4 responses: %d\n", sum(response_counts$n_responses >= 1 & response_counts$n_responses < 5)))
  cat(sprintf("    5+ responses: %d (retained)\n", sum(response_counts$n_responses >= 5)))
  cat("\n")

  # Create exclusion log for participants with insufficient responses
  if (nrow(insufficient_responses) > 0) {
    exclusions_insufficient <- insufficient_responses %>%
      dplyr::mutate(
        exclusion_stage = "Stage 0: Data Loading",
        exclusion_reason = sprintf("Insufficient responses (n=%d, threshold=%d)",
                                   n_responses, min_responses),
        exclusion_date = Sys.Date()
      ) %>%
      dplyr::select(pid, recordid, n_responses,
                   exclusion_stage, exclusion_reason, exclusion_date)

    cat(sprintf("[Exclusion log] Created for %d participants with insufficient responses\n",
                nrow(exclusions_insufficient)))
  } else {
    # Empty exclusion log if no one filtered
    exclusions_insufficient <- data.frame(
      pid = integer(),
      recordid = integer(),
      n_responses = integer(),
      exclusion_stage = character(),
      exclusion_reason = character(),
      exclusion_date = as.Date(character()),
      stringsAsFactors = FALSE
    )
    cat("[Exclusion log] No participants excluded at this stage\n")
  }
  cat("\n")

  # Filter wide_data and person_data to >= 5 responses
  # Create composite key for filtering (pid + recordid uniquely identifies participants)
  keep_keys <- response_counts %>%
    dplyr::filter(n_responses >= min_responses) %>%
    dplyr::mutate(composite_key = paste(pid, recordid, sep = "_"))

  wide_data_filtered <- wide_data %>%
    dplyr::mutate(composite_key = paste(pid, recordid, sep = "_")) %>%
    dplyr::filter(composite_key %in% keep_keys$composite_key) %>%
    dplyr::select(-composite_key)

  person_data_filtered <- person_data %>%
    dplyr::mutate(composite_key = paste(pid, recordid, sep = "_")) %>%
    dplyr::filter(composite_key %in% keep_keys$composite_key) %>%
    dplyr::select(-composite_key)

  cat(sprintf("[Filtered] %d participants retained (>= %d responses)\n",
              nrow(wide_data_filtered), min_responses))
  cat(sprintf("[Filtered] %d participants excluded\n\n",
              nrow(wide_data) - nrow(wide_data_filtered)))

  # Update wide_data and person_data references
  wide_data <- wide_data_filtered
  person_data <- person_data_filtered

  # ==========================================================================
  # STEP 6: SAVE OUTPUTS
  # ==========================================================================

  cat("=== STEP 6: SAVE OUTPUTS ===\n\n")

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  wide_file <- file.path(output_dir, "stage1_wide.rds")
  metadata_file <- file.path(output_dir, "stage1_item_metadata.rds")
  person_file <- file.path(output_dir, "stage1_person_data.rds")
  exclusions_file <- file.path(output_dir, "stage1_exclusions.rds")

  saveRDS(wide_data, wide_file)
  saveRDS(item_metadata_filtered, metadata_file)
  saveRDS(person_data, person_file)
  saveRDS(exclusions_insufficient, exclusions_file)

  cat(sprintf("[Saved] Wide data: %s\n", wide_file))
  cat(sprintf("[Saved] Item metadata: %s\n", metadata_file))
  cat(sprintf("[Saved] Person data: %s\n", person_file))
  cat(sprintf("[Saved] Exclusion log: %s (%d excluded)\n",
              exclusions_file, nrow(exclusions_insufficient)))
  cat("\n")

  # ==========================================================================
  # SUMMARY
  # ==========================================================================

  cat("================================================================================\n")
  cat("  DATA LOADING COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  cat("Summary:\n")
  cat(sprintf("  Source: ne25_transformed (eligible = TRUE only)\n"))
  cat(sprintf("  Participants: %d (after >= 5 response filter)\n", nrow(wide_data)))
  cat(sprintf("  Excluded: %d (insufficient responses)\n", nrow(exclusions_insufficient)))
  cat(sprintf("  Items: %d with complete metadata (equate lexicon)\n", ncol(wide_data) - 1))
  cat(sprintf("    - Psychosocial/Behavioral: %d items\n",
              sum(item_metadata_filtered$dimension == 1)))
  cat(sprintf("    - Developmental Skills: %d items\n",
              sum(item_metadata_filtered$dimension == 2)))
  cat(sprintf("  Age range: %.2f to %.2f years\n",
              min(person_data$years, na.rm = TRUE),
              max(person_data$years, na.rm = TRUE)))
  cat(sprintf("  Person-level data: %d columns (2 IDs + 2 age + %d covariates)\n",
              ncol(person_data), ncol(person_data) - 4))
  cat(sprintf("  Item naming: Extracted as ne25 (database), renamed to equate (standardized)\n"))
  cat("\n")

  cat("Exclusion Tracking:\n")
  cat(sprintf("  Exclusion log saved with %d entries\n", nrow(exclusions_insufficient)))
  cat(sprintf("  Fields: pid, recordid, n_responses, exclusion_stage, exclusion_reason, exclusion_date\n"))
  cat(sprintf("  This log will accumulate across Stages 1-3 for full audit trail\n"))
  cat("\n")

  cat("Pipeline Integration:\n")
  cat("  This runs BEFORE authenticity screening (Step 6.5) and calibration table (Step 11)\n")
  cat("  Uses only basic eligibility filter (eligible = TRUE)\n")
  cat("  Cleaning results will update codebook and flow through entire pipeline\n")
  cat("\n")

  cat("Ready for Stage 1 Cleaning:\n")
  cat("  Model 1a: Generate Mplus input file with equal loadings within domain\n")
  cat("  Stage 3 (later): Person covariates available for multivariate regression\n")
  cat("\n")

  return(list(
    wide_data = wide_data,
    item_metadata = item_metadata_filtered,
    person_data = person_data,
    exclusions = exclusions_insufficient
  ))
}


# ============================================================================
# MAIN EXECUTION (when sourced directly or called interactively)
# ============================================================================

if (!interactive()) {
  cat("\n")
  cat("################################################################################\n")
  cat("#                                                                              #\n")
  cat("#     LOAD ITEM RESPONSE DATA FOR STAGE 1 CLEANING                            #\n")
  cat("#                                                                              #\n")
  cat("################################################################################\n")
  cat("\n")

  stage1_data <- load_stage1_data()

  cat("\n")
  cat("[DONE] Data loading complete\n")
  cat("\n")
}

#!/usr/bin/env Rscript

#' Prepare Data for σ_sum_w Cross-Validation
#'
#' This script extracts and formats data from the NE25 pipeline for the
#' cross-validation workflow. It creates M_data (response-level) and J_data
#' (item-level metadata) in the format expected by run_cv_workflow.R.
#'
#' Inclusion criteria:
#'   - eligible = TRUE (pass CID2-5: consent, caregiver, child age, Nebraska)
#'   - Includes both authentic and inauthentic participants (CID6, CID7 failures)
#'   - Expected N ≈ 3,507 participants (2,635 authentic + 872 inauthentic)
#'
#' Data sources:
#'   - M_data: From ne25_transformed table (eligible participants)
#'   - J_data: From codebook.json item metadata
#'
#' Outputs:
#'   - data/temp/cv_M_data.rds: Response data (person_id, item_id, response, age)
#'       * NOTE: 'person_id' is artificial (1:N) representing unique (pid, record_id) pairs
#'   - data/temp/cv_J_data.rds: Item metadata (item_id, K, dimension)
#'   - data/temp/cv_person_map.rds: Mapping from person_id back to original (pid, record_id)
#'
#' Usage:
#'   source("scripts/authenticity_screening/in_development/00_prepare_cv_data.R")
#'   cv_data <- prepare_cv_data()

library(dplyr)
library(tidyr)
library(duckdb)

# Load safe_left_join utility
source("R/utils/safe_joins.R")

#' Prepare CV Data from Database
#'
#' @param db_path Path to DuckDB database
#' @param codebook_path Path to codebook.json
#' @param output_dir Directory to save prepared data
#' @return List with M_data and J_data
prepare_cv_data <- function(db_path = "data/duckdb/kidsights_local.duckdb",
                             codebook_path = "codebook/data/codebook.json",
                             output_dir = "data/temp") {

  cat("\n")
  cat("================================================================================\n")
  cat("  PREPARE DATA FOR σ_sum_w CROSS-VALIDATION\n")
  cat("================================================================================\n")
  cat("\n")

  # ==========================================================================
  # STEP 1: LOAD CODEBOOK ITEM METADATA
  # ==========================================================================

  cat("=== STEP 1: LOAD CODEBOOK ===\n\n")

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  cat(sprintf("[Loaded] Codebook: %d items\n\n", length(codebook$items)))

  # ==========================================================================
  # STEP 2: EXTRACT ITEM METADATA (J_data)
  # ==========================================================================

  cat("=== STEP 2: EXTRACT ITEM METADATA ===\n\n")

  # Build J_data from codebook (matching 01_prepare_data.R logic)
  J_data_list <- list()

  for (item_id in names(codebook$items)) {
    item <- codebook$items[[item_id]]

    # Skip if no lexicons or no equate/ne25 names (not a calibration item)
    if (is.null(item$lexicons) || is.null(item$lexicons$equate) || is.null(item$lexicons$ne25)) {
      next
    }

    equate_name <- item$lexicons$equate
    ne25_name <- item$lexicons$ne25
    if (is.list(equate_name)) equate_name <- unlist(equate_name)
    if (is.list(ne25_name)) ne25_name <- unlist(ne25_name)

    if (is.null(equate_name) || length(equate_name) == 0 || equate_name == "" ||
        is.null(ne25_name) || length(ne25_name) == 0 || ne25_name == "") {
      next
    }

    # Get response set to determine K
    n_categories <- NA
    if (!is.null(item$content) && !is.null(item$content$response_options)) {
      if ("ne25" %in% names(item$content$response_options)) {
        resp_ref <- item$content$response_options$ne25
        if (is.list(resp_ref)) resp_ref <- unlist(resp_ref)

        if (!is.null(resp_ref) && length(resp_ref) == 1) {
          # Strip $ref: prefix
          if (grepl("^\\$ref:", resp_ref)) {
            resp_ref <- sub("^\\$ref:", "", resp_ref)
          }

          if (resp_ref %in% names(codebook$response_sets)) {
            response_set <- codebook$response_sets[[resp_ref]]

            # Count non-missing categories
            valid_categories <- sapply(response_set, function(opt) {
              val <- if (is.list(opt$value)) opt$value[[1]] else opt$value
              as.numeric(val)
            })
            n_categories <- sum(valid_categories >= 0)
          }
        }
      }
    }

    # Skip items without valid response set
    if (is.na(n_categories) || n_categories < 2) {
      next
    }

    # Extract domain.kidsights.value (matching line 87-92 of 01_prepare_data.R)
    domain_value <- NA
    if (!is.null(item$domains) && !is.null(item$domains$kidsights)) {
      domain_value <- item$domains$kidsights$value
      if (is.list(domain_value)) domain_value <- unlist(domain_value)
    }

    # Skip items without domain assignment
    if (is.na(domain_value) || length(domain_value) == 0 || domain_value == "") {
      next
    }

    # Create dimension indicator
    # 1 = psychosocial/behavioral problems (psychosocial_problems_general, socemo)
    # 2 = developmental skills (motor, coglan)
    dimension <- if (domain_value %in% c("psychosocial_problems_general", "socemo")) {
      1L
    } else if (domain_value %in% c("motor", "coglan")) {
      2L
    } else {
      NA_integer_  # Unknown domain - will be filtered out
    }

    J_data_list[[equate_name]] <- data.frame(
      item_id = equate_name,  # Use equate name as item_id
      original_item_id = item_id,
      ne25_name = tolower(ne25_name),  # NE25 uses lowercase
      K = n_categories,
      dimension = dimension,
      domain_value = domain_value,
      stringsAsFactors = FALSE
    )
  }

  # Combine and filter
  J_data <- dplyr::bind_rows(J_data_list) %>%
    dplyr::filter(!is.na(dimension))

  cat(sprintf("[Extracted] J_data: %d calibration items\n", nrow(J_data)))
  cat(sprintf("  - Dimension 1 (Psychosocial/Behavioral): %d items\n",
              sum(J_data$dimension == 1)))
  cat(sprintf("  - Dimension 2 (Developmental Skills): %d items\n",
              sum(J_data$dimension == 2)))
  cat("\n")

  # ==========================================================================
  # STEP 3: CONNECT TO DATABASE
  # ==========================================================================

  cat("=== STEP 3: CONNECT TO DATABASE ===\n\n")

  if (!file.exists(db_path)) {
    stop(sprintf("Database not found: %s", db_path))
  }

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  cat(sprintf("[Connected] %s\n\n", db_path))

  # ==========================================================================
  # STEP 4: EXTRACT RESPONSE DATA (M_data)
  # ==========================================================================

  cat("=== STEP 4: EXTRACT RESPONSE DATA ===\n\n")

  # Query ne25_transformed
  # Filter: eligible = TRUE only (pass CID2-5: consent, caregiver, child age, Nebraska)
  # Includes both authentic and inauthentic participants (CID6, CID7 failures)
  cat("[Source] ne25_transformed table\n")
  cat("[Filter] eligible = TRUE (basic eligibility: CID2-5)\n")
  cat("         Includes all authenticity patterns (CID6, CID7 pass/fail)\n\n")

  query <- "SELECT *, age_in_days / 365.25 AS age_years
           FROM ne25_transformed
           WHERE eligible = TRUE"

  ne25_data <- DBI::dbGetQuery(con, query)

  # Report authenticity breakdown
  n_total <- nrow(ne25_data)
  n_authentic <- sum(ne25_data$authentic == TRUE, na.rm = TRUE)
  n_inauthentic <- sum(ne25_data$authentic == FALSE, na.rm = TRUE)

  cat(sprintf("[Loaded] %d participants\n", n_total))
  cat(sprintf("  - Authentic (pass CID6 & CID7): %d (%.1f%%)\n",
              n_authentic, 100 * n_authentic / n_total))
  cat(sprintf("  - Inauthentic (fail CID6 or CID7): %d (%.1f%%)\n",
              n_inauthentic, 100 * n_inauthentic / n_total))

  # Get NE25 column names from item metadata
  ne25_columns <- J_data$ne25_name

  # Check which columns exist in the data
  existing_cols <- ne25_columns[ne25_columns %in% names(ne25_data)]
  missing_cols <- ne25_columns[!ne25_columns %in% names(ne25_data)]

  cat(sprintf("[Items] Found %d / %d items in database\n", length(existing_cols), length(ne25_columns)))
  if (length(missing_cols) > 0) {
    cat(sprintf("[Warning] %d items missing from database\n", length(missing_cols)))
  }

  # Filter item metadata to only existing columns
  J_data <- J_data %>%
    dplyr::filter(ne25_name %in% existing_cols)

  cat(sprintf("[Using] %d items for analysis\n\n", nrow(J_data)))

  # Extract item columns + metadata
  ne25_items <- ne25_data %>%
    dplyr::select(pid, record_id, age_years, dplyr::all_of(J_data$ne25_name))

  # Convert to long format and filter to people with at least one valid response
  # NOTE: Some eligible participants may have all NA responses and will be excluded
  ne25_long <- ne25_items %>%
    tidyr::pivot_longer(
      cols = dplyr::all_of(J_data$ne25_name),
      names_to = "ne25_name",
      values_to = "response"
    ) %>%
    dplyr::filter(!is.na(response))  # Remove missing responses

  cat(sprintf("[Response filtering] Started with %d eligible participants\n",
              nrow(ne25_data)))

  # Get unique (pid, record_id) combinations that have at least one response
  persons_with_data <- ne25_long %>%
    dplyr::select(pid, record_id) %>%
    dplyr::distinct()

  cat(sprintf("[Response filtering] %d have at least one valid response\n",
              nrow(persons_with_data)))
  cat(sprintf("                     %d excluded (all NA responses)\n\n",
              nrow(ne25_data) - nrow(persons_with_data)))

  # Create unique person identifier (pid + record_id combination)
  # CRITICAL: pid alone does NOT uniquely identify participants!
  # Only include people with actual response data
  person_lookup <- persons_with_data %>%
    dplyr::select(pid, record_id) %>%
    dplyr::distinct() %>%
    dplyr::arrange(pid, record_id) %>%
    dplyr::mutate(person_id = dplyr::row_number())

  n_unique_persons <- nrow(person_lookup)
  n_unique_pids <- length(unique(person_lookup$pid))

  cat(sprintf("[Person IDs] Created %d unique person_ids from %d participants with data\n",
              n_unique_persons, n_unique_persons))
  cat(sprintf("  - Original unique PIDs: %d\n", n_unique_pids))
  cat(sprintf("  - Mean responses per PID: %.1f\n\n", n_unique_persons / n_unique_pids))

  # Convert to M_data format
  # NOTE: Final M_data uses person_id (1:N) as unique identifier (NOT renamed)
  M_data <- ne25_long %>%
    safe_left_join(
      J_data %>% dplyr::select(ne25_name, item_id),
      by_vars = "ne25_name"
    ) %>%
    safe_left_join(
      person_lookup,
      by_vars = c("pid", "record_id")  # Join on BOTH to get unique person_id
    ) %>%
    safe_left_join(
      ne25_items %>% dplyr::select(pid, record_id, age_years),
      by_vars = c("pid", "record_id")
    ) %>%
    dplyr::select(person_id, item_id, response, age = age_years)  # Keep as person_id

  # Validate person_id mapping
  if (any(is.na(M_data$person_id))) {
    stop("ERROR: Some observations failed to get person_id assignment. Check pid+record_id join.")
  }

  if (length(unique(M_data$person_id)) != n_unique_persons) {
    stop(sprintf("ERROR: M_data has %d unique person_ids but person_lookup has %d",
                 length(unique(M_data$person_id)), n_unique_persons))
  }

  cat(sprintf("\n[M_data] Response-level data:\n"))
  cat(sprintf("  - %d unique persons (consecutive IDs 1:%d)\n",
              length(unique(M_data$person_id)), max(M_data$person_id)))
  cat(sprintf("  - %d total observations\n", nrow(M_data)))
  cat(sprintf("  - %d unique items\n", length(unique(M_data$item_id))))
  cat(sprintf("  - Age range: %.2f to %.2f years\n",
              min(M_data$age), max(M_data$age)))
  cat(sprintf("  - Responses per person: mean=%.1f, median=%.0f\n",
              mean(table(M_data$pid)), median(table(M_data$pid))))
  cat("\n")

  # ==========================================================================
  # STEP 5: ALIGN J_data WITH AVAILABLE ITEMS
  # ==========================================================================

  cat("=== STEP 5: ALIGN ITEM METADATA ===\n\n")

  # Only keep J_data for items that exist in M_data
  items_in_data <- unique(M_data$item_id)
  J_data <- J_data %>%
    dplyr::filter(item_id %in% items_in_data)

  cat(sprintf("[Aligned] J_data: %d items with responses\n", nrow(J_data)))
  cat(sprintf("  - Dimension 1 (Psychosocial/Behavioral): %d items\n",
              sum(J_data$dimension == 1)))
  cat(sprintf("  - Dimension 2 (Developmental Skills): %d items\n",
              sum(J_data$dimension == 2)))
  cat("\n")

  # ==========================================================================
  # STEP 6: RECODE ITEM IDs TO CONSECUTIVE INTEGERS
  # ==========================================================================

  cat("=== STEP 6: RECODE ITEM IDs ===\n\n")

  # Stan requires item_id to be 1:J (consecutive integers)
  # Currently, J_data$item_id = equate name (e.g., "DD101")
  # Create mapping: equate name → integer 1:J
  item_map <- data.frame(
    equate_name = J_data$item_id,  # equate name (e.g., "DD101")
    item_id_int = 1:nrow(J_data),   # integer 1:J
    stringsAsFactors = FALSE
  )

  # Update M_data with integer item_id
  M_data <- M_data %>%
    safe_left_join(
      item_map,
      by_vars = c("item_id" = "equate_name")
    ) %>%
    dplyr::select(person_id, item_id = item_id_int, response, age)

  # Update J_data with integer item_id
  J_data_final <- item_map %>%
    dplyr::left_join(J_data, by = c("equate_name" = "item_id")) %>%
    dplyr::select(
      item_id = item_id_int,
      original_item_id = equate_name,
      K, dimension, domain_value
    )

  J_data <- J_data_final

  cat(sprintf("[Recoded] item_id: 1 to %d\n", max(J_data$item_id)))
  cat(sprintf("[Mapping] Saved as J_data$original_item_id\n\n"))

  # ==========================================================================
  # STEP 7: VALIDATION
  # ==========================================================================

  cat("=== STEP 7: VALIDATION ===\n\n")

  # Check for missing item_id in M_data
  missing_items <- setdiff(M_data$item_id, J_data$item_id)
  if (length(missing_items) > 0) {
    stop(sprintf("M_data contains %d item_ids not in J_data", length(missing_items)))
  }

  # Check for responses outside valid range
  M_data_with_K <- M_data %>%
    dplyr::left_join(J_data %>% dplyr::select(item_id, K), by = "item_id")

  invalid_responses <- M_data_with_K %>%
    dplyr::filter(response < 0 | response >= K)

  if (nrow(invalid_responses) > 0) {
    warning(sprintf("%d responses are outside valid range [0, K-1]", nrow(invalid_responses)))
    cat("[Validation] Removing invalid responses...\n")
    M_data <- M_data %>%
      dplyr::anti_join(invalid_responses %>% dplyr::select(pid, item_id),
                       by = c("pid", "item_id"))
  }

  cat(sprintf("[OK] All item_ids in M_data exist in J_data\n"))
  cat(sprintf("[OK] All responses in valid range [0, K-1]\n"))
  cat(sprintf("[OK] Final M_data: %d observations\n\n", nrow(M_data)))

  # ==========================================================================
  # STEP 8: SAVE OUTPUTS
  # ==========================================================================

  cat("=== STEP 8: SAVE OUTPUTS ===\n\n")

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  M_data_file <- file.path(output_dir, "cv_M_data.rds")
  J_data_file <- file.path(output_dir, "cv_J_data.rds")
  item_map_file <- file.path(output_dir, "cv_item_map.rds")
  person_map_file <- file.path(output_dir, "cv_person_map.rds")

  saveRDS(M_data, M_data_file)
  saveRDS(J_data, J_data_file)
  saveRDS(item_map, item_map_file)
  saveRDS(person_lookup, person_map_file)

  cat(sprintf("[Saved] M_data: %s\n", M_data_file))
  cat(sprintf("[Saved] J_data: %s\n", J_data_file))
  cat(sprintf("[Saved] Item mapping: %s\n", item_map_file))
  cat(sprintf("[Saved] Person mapping: %s\n", person_map_file))
  cat("\n")

  # ==========================================================================
  # SUMMARY
  # ==========================================================================

  cat("================================================================================\n")
  cat("  DATA PREPARATION COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  cat("Ready for CV workflow:\n")
  cat("  source(\"scripts/authenticity_screening/in_development/run_cv_workflow.R\")\n")
  cat("  \n")
  cat("  M_data <- readRDS(\"data/temp/cv_M_data.rds\")\n")
  cat("  J_data <- readRDS(\"data/temp/cv_J_data.rds\")\n")
  cat("  \n")
  cat("  results <- run_complete_cv_workflow(\n")
  cat("    M_data = M_data,\n")
  cat("    J_data = J_data\n")
  cat("  )\n")
  cat("\n")

  return(list(
    M_data = M_data,
    J_data = J_data,
    item_map = item_map,
    person_map = person_lookup
  ))
}


# ============================================================================
# MAIN EXECUTION (when sourced directly)
# ============================================================================

if (!interactive()) {
  cat("\n")
  cat("################################################################################\n")
  cat("#                                                                              #\n")
  cat("#     PREPARE DATA FOR σ_sum_w CROSS-VALIDATION                                #\n")
  cat("#                                                                              #\n")
  cat("################################################################################\n")
  cat("\n")

  cv_data <- prepare_cv_data()

  cat("\n")
  cat("[DONE] Data preparation complete\n")
  cat("\n")
}

################################################################################
# HRTL Item-Level Threshold Scoring (Production)
################################################################################

#' Score HRTL for NE25 Pipeline (Step 7.7)
#'
#' @description
#' Complete HRTL scoring workflow for pipeline integration.
#' Loads imputed item data and CAHMI item-level thresholds, scores children on
#' HRTL domains, and returns domain and overall classifications.
#'
#' WARNING: Motor Development domain excluded due to data quality issues
#' (93% missing DrawFace/DrawPerson/BounceBall items in NE25).
#' See: https://github.com/anthropics/kidsights/issues/15
#'
#' @param data Data frame with child records (must include pid, record_id, years_old, and all CAHMI items)
#' @param thresholds_path Path to RDS file with CAHMI item-level thresholds
#' @param domain_datasets_path Path to RDS file with domain item mappings
#' @param verbose Logical, if TRUE print progress messages
#'
#' @return List with:
#'   - domain_scores: Tibble with domain-level classifications (4 domains, Motor excluded)
#'   - hrtl_overall: Tibble with overall HRTL classification (marked as NA - incomplete)
#'
#' @details
#' Scoring algorithm:
#' 1. Filter to ages 3-5 years (HRTL target age range)
#' 2. For each domain (Early Learning, Social-Emotional, Self-Regulation, Health):
#'    a. Apply age-specific item-level thresholds
#'    b. Code responses: 1=Needs Support, 2=Emerging, 3=On-Track
#'    c. Average codes within domain
#'    d. Classify domain: >=2.5=On-Track, >=1.5=Emerging, <1.5=Needs Support
#' 3. Determine overall HRTL: Would require >=4 domains On-Track + 0 domains Needs Support
#'    (Not computed due to Motor Development exclusion)
#'
#' @export
score_hrtl <- function(data,
                       imputed_data_path = "scripts/hrtl/hrtl_data_imputed_allages.rds",
                       thresholds_path = "scripts/hrtl/hrtl_conversion_tables.rds",
                       domain_datasets_path = "scripts/hrtl/hrtl_domain_datasets.rds",
                       verbose = TRUE) {

  if (verbose) {
    message("=== HRTL Scoring - Step 7.7 (Item-Level Thresholds with Rasch Imputation) ===\n")
  }

  # ==============================================================================
  # 1. LOAD IMPUTED DATA, THRESHOLDS, AND DOMAIN MAPPINGS
  # ==============================================================================
  if (verbose) {
    message("1. Loading Rasch-imputed data and CAHMI item-level thresholds...\n")
  }

  tryCatch({
    imputed_data_list <- readRDS(imputed_data_path)
    conversion_tables <- readRDS(thresholds_path)
    domain_datasets <- readRDS(domain_datasets_path)

    if (verbose) {
      message(sprintf("  [OK] Loaded imputed data (%d domains)\n", length(imputed_data_list)))
      message(sprintf("  [OK] Loaded conversion tables (%d domains)\n", length(conversion_tables)))
      message(sprintf("  [OK] Loaded domain datasets (%d domains)\n", length(domain_datasets)))
    }

  }, error = function(e) {
    stop(sprintf("Failed to load HRTL reference data: %s", e$message))
  })

  # ==============================================================================
  # 2. CREATE DOMAIN-TO-ITEMS MAPPING (Motor Development EXCLUDED)
  # ==============================================================================
  domain_item_map <- list(
    "Early Learning Skills" = domain_datasets[["Early Learning Skills"]]$variables,
    "Social-Emotional Development" = domain_datasets[["Social-Emotional Development"]]$variables,
    "Self-Regulation" = domain_datasets[["Self-Regulation"]]$variables,
    "Health" = domain_datasets[["Health"]]$variables
  )

  # Extract thresholds from conversion tables
  thresholds_list <- lapply(conversion_tables, function(ct) ct$cahmi_thresholds)

  # ==============================================================================
  # 3. SCORE CHILDREN USING ITEM-LEVEL THRESHOLDS
  # ==============================================================================
  if (verbose) {
    message("2. Running HRTL item-level threshold scoring...\n")
  }

  tryCatch({
    # Source the item-level scoring function
    source("R/hrtl/score_hrtl_itemlevel.R")

    # Score children using Rasch-imputed data and CAHMI thresholds
    results <- score_hrtl_itemlevel(
      data = data,
      imputed_data_list = imputed_data_list,
      thresholds_list = thresholds_list,
      domain_datasets = domain_datasets,
      domain_item_map = domain_item_map,
      verbose = verbose
    )

    return(results)

  }, error = function(e) {
    stop(sprintf("HRTL scoring failed: %s", e$message))
  })
}


#' Save HRTL Scores to Database
#'
#' @export
save_hrtl_scores_to_db <- function(domain_scores, hrtl_overall,
                                  db_path, table_prefix = "ne25_hrtl",
                                  overwrite = TRUE, verbose = TRUE) {

  con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)

  tryCatch({
    # Save domain scores
    table_name <- sprintf("%s_domain_scores", table_prefix)
    DBI::dbWriteTable(con, table_name, domain_scores,
                     overwrite = overwrite, append = FALSE)

    if (verbose) {
      message(sprintf("[OK] Saved %d domain score records", nrow(domain_scores)))
    }

    # Create index
    DBI::dbExecute(con, sprintf(
      "CREATE INDEX IF NOT EXISTS idx_%s_domain_scores_pid
       ON %s (pid, record_id, domain)",
      table_prefix, table_name
    ))

    # Save overall HRTL
    table_name <- sprintf("%s_overall", table_prefix)
    DBI::dbWriteTable(con, table_name, hrtl_overall,
                     overwrite = overwrite, append = FALSE)

    if (verbose) {
      message(sprintf("[OK] Saved %d overall HRTL records", nrow(hrtl_overall)))
    }

    # Create index
    DBI::dbExecute(con, sprintf(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_%s_overall_pid
       ON %s (pid, record_id)",
      table_prefix, table_name
    ))

    invisible(TRUE)

  }, error = function(e) {
    warning(sprintf("Database write failed: %s", e$message))
    invisible(FALSE)

  }, finally = {
    duckdb::dbDisconnect(con, shutdown = TRUE)
  })
}

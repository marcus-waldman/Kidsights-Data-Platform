################################################################################
# HRTL Item-Level Threshold Scoring (Production)
################################################################################
# Scores children on HRTL domains using CAHMI item-level thresholds:
# 1. Code each item based on age-specific threshold
# 2. Average codes across items in domain
# 3. Classify domain based on average code
# 4. Determine overall HRTL status (≥4 domains on-track, 0 domains needs-support)
################################################################################

#' Score HRTL Domains Using Item-Level Thresholds
#'
#' @description
#' Scores children on HRTL domains using CAHMI item-level thresholds.
#' Requires imputed item data (missing values already filled).
#'
#' @param data Data frame with child records (must include pid, record_id, years_old)
#' @param imputed_data_list List of domain-specific imputed item data
#' @param domain_datasets List with domain item mappings (from hrtl_domain_datasets.rds)
#' @param thresholds_list List of domain-specific CAHMI thresholds
#' @param domain_item_map List mapping domain names to item variable names
#' @param verbose Logical, if TRUE print progress messages
#'
#' @return List with:
#'   - domain_scores: Tibble with domain-level classifications
#'   - hrtl_overall: Tibble with overall HRTL classification
#'
#' @export
score_hrtl_itemlevel <- function(data, imputed_data_list, thresholds_list,
                                domain_datasets, domain_item_map, verbose = TRUE) {

  if (verbose) {
    message("=== HRTL Item-Level Threshold Scoring ===\n")
    message(sprintf("Total input records: %d", nrow(data)))
  }

  # Filter to HRTL age range (3-5 years)
  data_hrtl <- data %>%
    dplyr::filter(!is.na(years_old), years_old >= 3, years_old < 6) %>%
    dplyr::mutate(age_years = floor(years_old))

  if (verbose) {
    message(sprintf("HRTL-eligible (ages 3-5): %d\n", nrow(data_hrtl)))
  }

  if (nrow(data_hrtl) == 0) {
    message("[WARN] No children in HRTL age range (3-5 years)")
    return(list(
      domain_scores = data.frame(),
      hrtl_overall = data.frame()
    ))
  }

  # NOTE: Motor Development excluded due to data quality issues
  # See: https://github.com/anthropics/kidsights/issues/XXX
  # NE25 Motor items 93% missing for DrawFace/DrawPerson/BounceBall
  domains <- c("Early Learning Skills", "Social-Emotional Development",
               "Self-Regulation", "Health")

  # Score each domain
  domain_scores_list <- list()

  for (domain in domains) {
    if (verbose) {
      message(sprintf("Scoring %s...", domain))
    }

    imputed_items <- imputed_data_list[[domain]]
    thresholds <- thresholds_list[[domain]]
    domain_items <- domain_item_map[[domain]]

    if (is.null(imputed_items) || is.null(thresholds)) {
      if (verbose) {
        message(sprintf("  [SKIP] Missing imputed data or thresholds\n"))
      }
      next
    }

    # Match imputed data to children in HRTL age range
    # Get pid/record_id from domain_datasets (they were filtered to create imputed data)
    domain_data_full <- domain_datasets[[domain]]$data

    if (is.null(domain_data_full)) {
      message(sprintf("    [ERROR] Cannot get pid/record_id mapping for %s\n", domain))
      next
    }

    # Create mapping of pid+record_id to row numbers in the original domain data
    domain_pids <- domain_data_full %>%
      dplyr::select(pid, record_id) %>%
      dplyr::mutate(row_in_domain_data = dplyr::row_number())

    # Start with child identifiers
    domain_result <- data_hrtl %>%
      dplyr::select(pid, record_id, years_old, age_years)

    # For each child in HRTL age range, find their row in the domain data
    # Then extract imputed items from that row
    domain_result <- domain_result %>%
      dplyr::left_join(
        domain_pids,
        by = c("pid", "record_id")
      )

    # Extract imputed items using row positions in domain data
    imputed_hrtl <- imputed_items[domain_result$row_in_domain_data, ]
    # Reset row names for safety
    rownames(imputed_hrtl) <- NULL

    # Initialize item codes (will be 1=Needs Support, 2=Emerging, 3=On-Track)
    item_codes <- data.frame(matrix(NA, nrow = nrow(domain_result), ncol = length(domain_items)))
    colnames(item_codes) <- domain_items

    # Create mapping from NE25 items to CAHMI codes
    ne25_to_cahmi <- setNames(domain_datasets[[domain]]$cahmi_codes,
                              domain_datasets[[domain]]$variables)

    # Code each item based on age-specific thresholds
    for (item in domain_items) {
      if (!(item %in% colnames(imputed_hrtl))) {
        if (verbose) {
          message(sprintf("    [WARN] Item %s not found in imputed data\n", item))
        }
        next
      }

      item_responses <- imputed_hrtl[[item]]

      # Get CAHMI code for this item
      cahmi_code <- ne25_to_cahmi[[item]]
      if (is.na(cahmi_code)) {
        if (verbose) {
          message(sprintf("    [WARN] CAHMI code not found for item %s\n", item))
        }
        next
      }

      # Get age-specific thresholds for this item
      # Match by CAHMI code (case-insensitive, remove suffix and underscores)
      item_thresholds <- thresholds %>%
        dplyr::filter(tolower(gsub("_22$|_", "", var_cahmi)) == tolower(gsub("_", "", cahmi_code)))

      if (nrow(item_thresholds) == 0) {
        if (verbose) {
          message(sprintf("    [WARN] No thresholds found for item %s\n", item))
        }
        next
      }

      # Code each child's response
      item_codes[[item]] <- sapply(seq_len(nrow(domain_result)), function(i) {
        response <- item_responses[i]
        age <- domain_result$age_years[i]

        # Get threshold for this age
        age_threshold <- item_thresholds %>%
          dplyr::filter(SC_AGE_YEARS == age)

        if (nrow(age_threshold) == 0) {
          # Fallback to any available threshold if age not found
          age_threshold <- item_thresholds %>% dplyr::slice(1)
        }

        on_track <- age_threshold$on_track[1]
        emerging <- age_threshold$emerging[1]

        # Code the response
        if (is.na(response)) {
          NA_real_
        } else if (response >= on_track) {
          3  # On-Track
        } else if (response >= emerging) {
          2  # Emerging
        } else {
          1  # Needs Support
        }
      })
    }

    # Compute domain average code
    domain_result <- domain_result %>%
      dplyr::mutate(
        n_items = length(domain_items),
        n_responses = rowSums(!is.na(item_codes)),
        avg_code = rowMeans(item_codes, na.rm = TRUE)
      ) %>%
      dplyr::mutate(
        classification = dplyr::case_when(
          is.na(avg_code) ~ "Unable to score",
          avg_code >= 2.5 ~ "On-Track",
          avg_code >= 1.5 ~ "Emerging",
          TRUE ~ "Needs Support"
        ),
        domain = domain
      ) %>%
      dplyr::select(pid, record_id, domain, n_items, n_responses, avg_code, classification, years_old)

    domain_scores_list[[domain]] <- domain_result

    if (verbose) {
      n_scored <- sum(!is.na(domain_result$avg_code))
      message(sprintf("  [OK] Scored %d children\n", n_scored))
    }
  }

  # Combine domain scores
  domain_scores <- dplyr::bind_rows(domain_scores_list)

  # Calculate overall HRTL classification
  # NOTE: Motor Development excluded, so HRTL is incomplete
  # Requirements with 4 domains: ≥4 on-track AND 0 needs-support (all must be on-track)
  hrtl_overall <- domain_scores %>%
    dplyr::group_by(pid, record_id) %>%
    dplyr::summarise(
      n_on_track = sum(classification == "On-Track", na.rm = TRUE),
      n_emerging = sum(classification == "Emerging", na.rm = TRUE),
      n_needs_support = sum(classification == "Needs Support", na.rm = TRUE),
      n_unable = sum(classification == "Unable to score", na.rm = TRUE),
      # Mark HRTL as NA due to Motor Development exclusion
      hrtl = NA,
      .groups = "drop"
    )

  if (verbose) {
    message("\n[WARNING] Overall HRTL classification marked as NA (missing)")
    message("Reason: Motor Development domain excluded due to data quality issues")
    message("        (93% of NE25 records missing DrawFace, DrawPerson, BounceBall items)")
    message("\nDomain scores available for:\n")
    for (d in unique(domain_scores$domain)) {
      n_scored <- sum(!is.na(domain_scores$avg_code[domain_scores$domain == d]))
      message(sprintf("  %s: %d children scored", d, n_scored))
    }
    message()
  }

  return(list(
    domain_scores = domain_scores,
    hrtl_overall = hrtl_overall
  ))
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

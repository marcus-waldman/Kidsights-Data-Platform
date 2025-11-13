#' Aggregate HRTL Items into Domain Scores
#'
#' @description
#' Computes domain-level scores by averaging item responses within each of the 5 HRTL domains:
#' - Early Learning Skills
#' - Health
#' - Motor Development
#' - Self-Regulation
#' - Social-Emotional Development
#'
#' Then classifies each domain using standard HRTL cutoffs:
#' - On-Track: mean >= 2.5
#' - Emerging: mean >= 2.0 (but < 2.5)
#' - Needs-Support: mean < 2.0
#'
#' @param dat Data frame containing HRTL item responses
#' @param lexicon Character. Which lexicon to use for variable names. Default: "equate"
#' @param codebook_path Character. Path to codebook.json. Default: "codebook/data/codebook.json"
#' @param verbose Logical. Print diagnostic messages? Default: TRUE
#'
#' @return Data frame with original data plus domain columns:
#'   - hrtl_early_learning: Domain mean score (0-4 scale)
#'   - hrtl_early_learning_class: Classification (On-Track/Emerging/Needs-Support)
#'   - hrtl_health: Domain mean score
#'   - hrtl_health_class: Classification
#'   - hrtl_motor: Domain mean score
#'   - hrtl_motor_class: Classification
#'   - hrtl_self_regulation: Domain mean score
#'   - hrtl_self_regulation_class: Classification
#'   - hrtl_social_emotional: Domain mean score
#'   - hrtl_social_emotional_class: Classification
#'   - hrtl_n_items_valid: Number of non-missing items (out of 27)
#'   - hrtl_n_domains_valid: Number of domains with at least 1 valid item
#'
#' @details
#' **Averaging Strategy:**
#' Uses simple mean with `na.rm = TRUE` to handle missing items. This means:
#' - If a child has 3/4 items in Motor Development, mean is based on those 3 items
#' - If a child has 0 items in a domain, domain score is NA
#'
#' **Known Limitations (see GitHub Issue #9):**
#' - Motor Development: Only 1/4 items available for ages 3-5 (DD207)
#' - Early Learning: 6/9 items available for ages 3-5
#' - Social-Emotional: 4/6 items available for ages 3-5
#'
#' These limitations are due to age-based routing in NE25 data collection.
#'
#' **Domain Cutoffs (HRTL Standard):**
#' - On-Track: >= 2.5
#' - Emerging: >= 2.0 and < 2.5
#' - Needs-Support: < 2.0
#'
#' @examples
#' \dontrun{
#' # Load data
#' library(DBI)
#' library(duckdb)
#' con <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
#' dat <- dbGetQuery(con, "SELECT * FROM ne25_calibration WHERE years BETWEEN 3 AND 5")
#' dbDisconnect(con)
#'
#' # Aggregate domains
#' dat_domains <- aggregate_domains(dat, lexicon = "equate")
#'
#' # Check domain distributions
#' table(dat_domains$hrtl_self_regulation_class, useNA = "ifany")
#' summary(dat_domains$hrtl_motor)  # Will show high NA rate due to missing items
#' }
#'
#' @export
aggregate_domains <- function(dat,
                              lexicon = "equate",
                              codebook_path = "codebook/data/codebook.json",
                              verbose = TRUE) {

  if (verbose) {
    cat("\n=== Aggregating HRTL Items into Domain Scores ===\n\n")
  }

  # Load HRTL metadata
  source("R/hrtl/load_hrtl_codebook.R")
  hrtl_meta <- load_hrtl_codebook(
    codebook_path = codebook_path,
    lexicon = lexicon,
    verbose = FALSE  # Suppress metadata loading messages
  )

  if (verbose) {
    cat(sprintf("[1/4] Loaded metadata for %d HRTL items\n", nrow(hrtl_meta)))
  }

  # Define domain name mappings (for clean variable names)
  domain_mapping <- c(
    "Early Learning Skills" = "early_learning",
    "Health" = "health",
    "Motor Development" = "motor",
    "Self-Regulation" = "self_regulation",
    "Social-Emotional Development" = "social_emotional"
  )

  # Initialize output data frame
  dat_aggregated <- dat

  # Count valid items per child
  all_items <- hrtl_meta$var_name[hrtl_meta$var_name %in% names(dat)]
  dat_aggregated$hrtl_n_items_valid <- rowSums(!is.na(dat[, all_items, drop = FALSE]))

  if (verbose) {
    cat(sprintf("[2/4] Found %d/%d HRTL items in dataset\n",
                length(all_items), nrow(hrtl_meta)))
  }

  # Aggregate each domain
  domain_stats <- list()

  if (verbose) {
    cat("[3/4] Computing domain scores...\n")
  }

  for (domain_name in names(domain_mapping)) {
    domain_short <- domain_mapping[[domain_name]]

    # Get items for this domain
    domain_items <- hrtl_meta$var_name[hrtl_meta$domain == domain_name]
    available_items <- domain_items[domain_items %in% names(dat)]

    if (length(available_items) == 0) {
      # No items available for this domain
      dat_aggregated[[paste0("hrtl_", domain_short)]] <- NA_real_
      dat_aggregated[[paste0("hrtl_", domain_short, "_class")]] <- NA_character_

      if (verbose) {
        cat(sprintf("      - %s: 0/%d items available (all NA)\n",
                    domain_name, length(domain_items)))
      }
      next
    }

    # Compute domain mean (average of available items)
    domain_scores <- rowMeans(dat[, available_items, drop = FALSE], na.rm = TRUE)

    # Handle cases where all items are NA (rowMeans returns NaN)
    domain_scores[is.nan(domain_scores)] <- NA_real_

    # Classify domain
    domain_class <- ifelse(
      is.na(domain_scores),
      NA_character_,
      ifelse(
        domain_scores >= 2.5,
        "On-Track",
        ifelse(
          domain_scores >= 2.0,
          "Emerging",
          "Needs-Support"
        )
      )
    )

    # Add to data
    dat_aggregated[[paste0("hrtl_", domain_short)]] <- domain_scores
    dat_aggregated[[paste0("hrtl_", domain_short, "_class")]] <- domain_class

    # Store stats
    domain_stats[[domain_name]] <- list(
      total_items = length(domain_items),
      available_items = length(available_items),
      n_valid = sum(!is.na(domain_scores)),
      mean_score = mean(domain_scores, na.rm = TRUE),
      n_on_track = sum(domain_class == "On-Track", na.rm = TRUE),
      n_emerging = sum(domain_class == "Emerging", na.rm = TRUE),
      n_needs_support = sum(domain_class == "Needs-Support", na.rm = TRUE)
    )

    if (verbose) {
      stats <- domain_stats[[domain_name]]
      cat(sprintf("      - %s: %d/%d items | mean=%.2f | n_valid=%d\n",
                  domain_name,
                  stats$available_items,
                  stats$total_items,
                  stats$mean_score,
                  stats$n_valid))
    }
  }

  # Count valid domains per child
  domain_cols <- paste0("hrtl_", domain_mapping)
  dat_aggregated$hrtl_n_domains_valid <- rowSums(!is.na(dat_aggregated[, domain_cols, drop = FALSE]))

  if (verbose) {
    cat("[4/4] Aggregation complete\n")
    cat(sprintf("      - Added %d domain score columns\n", length(domain_mapping) * 2))
    cat(sprintf("      - Added 2 summary columns (n_items_valid, n_domains_valid)\n"))
    cat("\n")
    cat("Domain Classifications:\n")
    for (domain_name in names(domain_mapping)) {
      stats <- domain_stats[[domain_name]]
      if (!is.null(stats)) {
        cat(sprintf("  %s:\n", domain_name))
        cat(sprintf("    On-Track: %d (%.1f%%)\n",
                    stats$n_on_track,
                    100 * stats$n_on_track / stats$n_valid))
        cat(sprintf("    Emerging: %d (%.1f%%)\n",
                    stats$n_emerging,
                    100 * stats$n_emerging / stats$n_valid))
        cat(sprintf("    Needs-Support: %d (%.1f%%)\n",
                    stats$n_needs_support,
                    100 * stats$n_needs_support / stats$n_valid))
      }
    }
    cat("\n")
  }

  return(dat_aggregated)
}

#' Load HRTL Codebook Metadata
#'
#' @description
#' Extracts HRTL-specific metadata from codebook.json including:
#' - 27 HRTL items with equate lexicon names
#' - Domain classifications (5 domains)
#' - Age-specific thresholds for ages 3, 4, and 5
#'
#' @param codebook_path Path to codebook.json file. Default: "codebook/data/codebook.json"
#' @param lexicon Which lexicon to use for variable names. Default: "equate" (for calibration table)
#' @param verbose Logical. Print diagnostic messages? Default: TRUE
#'
#' @return Data frame with columns:
#'   - item_id: Codebook item ID (e.g., "EG25a")
#'   - var_name: Variable name in specified lexicon (e.g., "EG25a" for equate)
#'   - domain: HRTL domain (Early Learning Skills, Social-Emotional Development,
#'             Self-Regulation, Motor Development, Health)
#'   - threshold_3_on_track: On-track threshold for age 3
#'   - threshold_3_emerging: Emerging threshold for age 3
#'   - threshold_4_on_track: On-track threshold for age 4
#'   - threshold_4_emerging: Emerging threshold for age 4
#'   - threshold_5_on_track: On-track threshold for age 5
#'   - threshold_5_emerging: Emerging threshold for age 5
#'
#' @details
#' This function serves as the single source of truth for HRTL scoring metadata.
#' All downstream scoring functions (classify_items, aggregate_domains, score_hrtl)
#' rely on this function to ensure consistency.
#'
#' The function filters for items with:
#' 1. `domains.hrtl22` field present in codebook
#' 2. `hrtl_thresholds.years` structure with age-specific cutoffs
#' 3. Specified lexicon mapping (equate, ne25, ne20, etc.)
#'
#' @examples
#' \dontrun{
#' # Load HRTL metadata with equate lexicon (for calibration table)
#' hrtl_meta <- load_hrtl_codebook(lexicon = "equate")
#'
#' # Load with ne25 lexicon (for transformed table)
#' hrtl_meta <- load_hrtl_codebook(lexicon = "ne25")
#'
#' # Check domain distribution
#' table(hrtl_meta$domain)
#' }
#'
#' @export
load_hrtl_codebook <- function(codebook_path = "codebook/data/codebook.json",
                                lexicon = "equate",
                                verbose = TRUE) {

  if (verbose) {
    cat("\n=== Loading HRTL Codebook Metadata ===\n\n")
  }

  # Load codebook
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' required. Install with: install.packages('jsonlite')")
  }

  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  cb <- jsonlite::fromJSON(codebook_path)

  if (verbose) {
    cat(sprintf("[1/3] Loaded codebook from: %s\n", codebook_path))
  }

  # Extract HRTL items
  hrtl_items <- list()

  for (item_id in names(cb$items)) {
    item <- cb$items[[item_id]]

    # Check if item has hrtl22 domain
    if (!is.null(item$domains) && "hrtl22" %in% names(item$domains)) {

      # Check if item has thresholds
      if (!is.null(item$hrtl_thresholds) && !is.null(item$hrtl_thresholds$years)) {

        # Check if item has specified lexicon
        if (!is.null(item$lexicons) && lexicon %in% names(item$lexicons)) {

          var_name <- item$lexicons[[lexicon]]

          # Handle array lexicons (e.g., cahmi22: ["CALMDOWN_R", "CALMDOWNR"])
          if (is.list(var_name) || length(var_name) > 1) {
            var_name <- var_name[[1]]  # Use first variant
          }

          domain <- item$domains$hrtl22
          thresholds <- item$hrtl_thresholds$years

          hrtl_items[[item_id]] <- data.frame(
            item_id = item_id,
            var_name = var_name,
            domain = domain,
            threshold_3_on_track = as.numeric(thresholds$`3`$on_track),
            threshold_3_emerging = as.numeric(thresholds$`3`$emerging),
            threshold_4_on_track = as.numeric(thresholds$`4`$on_track),
            threshold_4_emerging = as.numeric(thresholds$`4`$emerging),
            threshold_5_on_track = as.numeric(thresholds$`5`$on_track),
            threshold_5_emerging = as.numeric(thresholds$`5`$emerging),
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }

  # Combine into data frame
  if (length(hrtl_items) == 0) {
    stop(sprintf("No HRTL items found with lexicon '%s'", lexicon))
  }

  hrtl_meta <- dplyr::bind_rows(hrtl_items)

  if (verbose) {
    cat(sprintf("[2/3] Extracted %d HRTL items\n", nrow(hrtl_meta)))
    cat("[3/3] Domain distribution:\n")
    domain_counts <- table(hrtl_meta$domain)
    for (domain_name in names(domain_counts)) {
      cat(sprintf("      - %s: %d items\n", domain_name, domain_counts[[domain_name]]))
    }
    cat("\n")
  }

  # Sort by domain and item_id
  hrtl_meta <- hrtl_meta[order(hrtl_meta$domain, hrtl_meta$item_id), ]
  rownames(hrtl_meta) <- NULL

  return(hrtl_meta)
}

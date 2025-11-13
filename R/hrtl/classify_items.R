#' Classify HRTL Items Using Age-Specific Thresholds
#'
#' @description
#' Applies age-specific thresholds to classify each HRTL item response as:
#' - "On-Track": Meets or exceeds on-track threshold for child's age
#' - "Emerging": Meets emerging threshold but below on-track threshold
#' - "Needs-Support": Below emerging threshold
#'
#' @param dat Data frame containing item responses and child ages
#' @param age_var Character. Name of age variable (must be numeric, ages 3-5). Default: "years"
#' @param lexicon Character. Which lexicon to use for variable names. Default: "equate"
#' @param codebook_path Character. Path to codebook.json. Default: "codebook/data/codebook.json"
#' @param verbose Logical. Print diagnostic messages? Default: TRUE
#'
#' @return Data frame with original data plus classification columns:
#'   - {item}_class: Classification ("On-Track", "Emerging", "Needs-Support", or NA)
#'   - One column per HRTL item (27 total)
#'
#' @details
#' Classification logic per item and age:
#' 1. Extract age-specific thresholds (on_track, emerging) from codebook
#' 2. For each child:
#'    - If response >= on_track threshold → "On-Track"
#'    - Else if response >= emerging threshold → "Emerging"
#'    - Else → "Needs-Support"
#'    - If response is NA → NA
#'
#' Age handling:
#' - Ages rounded to nearest integer (floor or round)
#' - Ages <3 use age 3 thresholds
#' - Ages >5 use age 5 thresholds
#' - Non-integer ages (e.g., 3.5) use floor value (3)
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
#' # Classify items
#' dat_classified <- classify_items(dat, age_var = "years", lexicon = "equate")
#'
#' # Check classifications for one item
#' table(dat_classified$EG25a_class, useNA = "ifany")
#' }
#'
#' @export
classify_items <- function(dat,
                           age_var = "years",
                           lexicon = "equate",
                           codebook_path = "codebook/data/codebook.json",
                           verbose = TRUE) {

  if (verbose) {
    cat("\n=== Classifying HRTL Items with Age-Specific Thresholds ===\n\n")
  }

  # Load HRTL metadata
  source("R/hrtl/load_hrtl_codebook.R")
  hrtl_meta <- load_hrtl_codebook(
    codebook_path = codebook_path,
    lexicon = lexicon,
    verbose = verbose
  )

  if (verbose) {
    cat(sprintf("[1/4] Loaded metadata for %d HRTL items\n", nrow(hrtl_meta)))
  }

  # Check age variable exists
  if (!age_var %in% names(dat)) {
    stop(sprintf("Age variable '%s' not found in data", age_var))
  }

  # Create age bins (3, 4, 5)
  dat$age_bin <- floor(dat[[age_var]])
  dat$age_bin <- pmin(5, pmax(3, dat$age_bin))  # Clamp to [3, 5]

  if (verbose) {
    cat(sprintf("[2/4] Created age bins (3-5) from '%s'\n", age_var))
    age_table <- table(dat$age_bin)
    for (age in names(age_table)) {
      cat(sprintf("      - Age %s: %d children\n", age, age_table[[age]]))
    }
  }

  # Initialize classification columns
  dat_classified <- dat
  n_items_classified <- 0
  n_items_missing <- 0

  if (verbose) {
    cat("[3/4] Classifying items...\n")
  }

  # Classify each item
  for (i in 1:nrow(hrtl_meta)) {
    item_row <- hrtl_meta[i, ]
    var_name <- item_row$var_name
    class_var <- paste0(var_name, "_class")

    # Check if item exists in data
    if (!var_name %in% names(dat)) {
      if (verbose && i <= 5) {
        cat(sprintf("      - %s: NOT FOUND in data (skipped)\n", var_name))
      }
      n_items_missing <- n_items_missing + 1
      dat_classified[[class_var]] <- NA_character_
      next
    }

    # Initialize classification vector
    classifications <- rep(NA_character_, nrow(dat))

    # Classify by age
    for (age in c(3, 4, 5)) {
      age_mask <- dat$age_bin == age

      # Get thresholds for this age
      on_track_col <- paste0("threshold_", age, "_on_track")
      emerging_col <- paste0("threshold_", age, "_emerging")

      on_track_thresh <- item_row[[on_track_col]]
      emerging_thresh <- item_row[[emerging_col]]

      # Get responses for this age group
      responses <- dat[[var_name]][age_mask]

      # Classify
      age_classifications <- ifelse(
        is.na(responses),
        NA_character_,
        ifelse(
          responses >= on_track_thresh,
          "On-Track",
          ifelse(
            responses >= emerging_thresh,
            "Emerging",
            "Needs-Support"
          )
        )
      )

      # Assign to main classification vector
      classifications[age_mask] <- age_classifications
    }

    # Add to data
    dat_classified[[class_var]] <- classifications
    n_items_classified <- n_items_classified + 1
  }

  # Remove temporary age_bin column
  dat_classified$age_bin <- NULL

  if (verbose) {
    cat(sprintf("[4/4] Classification complete\n"))
    cat(sprintf("      - Items classified: %d\n", n_items_classified))
    cat(sprintf("      - Items not found in data: %d\n", n_items_missing))
    cat(sprintf("      - New columns added: %d (_class suffix)\n\n", n_items_classified))
  }

  return(dat_classified)
}

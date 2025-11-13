#' Score HRTL "Ready for Learning" Classification
#'
#' @description
#' Applies the complete HRTL (Healthy & Ready to Learn) scoring framework:
#' 1. Aggregates 27 items into 5 domain scores
#' 2. Classifies each domain (On-Track/Emerging/Needs-Support)
#' 3. Determines overall "Ready for Learning" status
#'
#' **HRTL Classification Logic:**
#' A child is "Ready for Learning" if:
#' - At least 4 out of 5 domains are "On-Track" AND
#' - Zero domains are "Needs-Support"
#'
#' @param dat Data frame containing HRTL item responses
#' @param age_var Character. Name of age variable (numeric, ages 3-5). Default: "years"
#' @param lexicon Character. Which lexicon to use for variable names. Default: "equate"
#' @param codebook_path Character. Path to codebook.json. Default: "codebook/data/codebook.json"
#' @param verbose Logical. Print diagnostic messages? Default: TRUE
#'
#' @return Data frame with original data plus:
#'   - All domain score columns from aggregate_domains()
#'   - hrtl_n_on_track: Number of domains classified as On-Track (0-5)
#'   - hrtl_n_emerging: Number of domains classified as Emerging (0-5)
#'   - hrtl_n_needs_support: Number of domains classified as Needs-Support (0-5)
#'   - hrtl_ready_for_learning: Logical. TRUE if child meets HRTL criteria
#'   - hrtl_classification: Character. "Ready", "Not Ready", or "Insufficient Data"
#'
#' @details
#' **Classification Categories:**
#' - **"Ready"**: ≥4 domains On-Track AND 0 domains Needs-Support
#' - **"Not Ready"**: Does not meet Ready criteria but has valid domain scores
#' - **"Insufficient Data"**: <3 domains with valid scores
#'
#' **Known Limitations (GitHub Issue #9):**
#' - Motor Development: Only 1/4 items available for ages 3-5
#' - Early Learning: 6/9 items available for ages 3-5
#' - Social-Emotional: 4/6 items available for ages 3-5
#'
#' Due to age-based routing in NE25, some domains may have reduced reliability.
#' Results should be interpreted cautiously, especially for Motor Development.
#'
#' **Interim Approach:**
#' This implementation uses simple averaging with `na.rm=TRUE` to handle
#' missing items. Future versions may incorporate IRT-based scoring or
#' NE25-specific norms.
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
#' # Score HRTL
#' dat_hrtl <- score_hrtl(dat, age_var = "years", lexicon = "equate")
#'
#' # Check results
#' table(dat_hrtl$hrtl_classification, useNA = "ifany")
#' table(dat_hrtl$hrtl_ready_for_learning, useNA = "ifany")
#'
#' # Summary by age
#' library(dplyr)
#' dat_hrtl %>%
#'   group_by(floor(years)) %>%
#'   summarise(
#'     n = n(),
#'     pct_ready = 100 * mean(hrtl_ready_for_learning, na.rm = TRUE)
#'   )
#' }
#'
#' @export
score_hrtl <- function(dat,
                       age_var = "years",
                       lexicon = "equate",
                       codebook_path = "codebook/data/codebook.json",
                       verbose = TRUE) {

  if (verbose) {
    cat("\n")
    cat(stringr::str_dup("=", 80), "\n")
    cat("HRTL (HEALTHY & READY TO LEARN) SCORING\n")
    cat(stringr::str_dup("=", 80), "\n\n")
  }

  # Step 1: Aggregate domains
  if (verbose) {
    cat("Step 1: Aggregating items into domain scores...\n")
  }

  source("R/hrtl/aggregate_domains.R")
  dat_scored <- aggregate_domains(
    dat = dat,
    lexicon = lexicon,
    codebook_path = codebook_path,
    verbose = verbose
  )

  # Step 2: Count domain classifications
  if (verbose) {
    cat("\n")
    cat(stringr::str_dup("-", 80), "\n")
    cat("Step 2: Applying HRTL classification logic...\n\n")
  }

  domain_class_cols <- c(
    "hrtl_early_learning_class",
    "hrtl_health_class",
    "hrtl_motor_class",
    "hrtl_self_regulation_class",
    "hrtl_social_emotional_class"
  )

  # Count On-Track domains
  dat_scored$hrtl_n_on_track <- rowSums(
    dat_scored[, domain_class_cols, drop = FALSE] == "On-Track",
    na.rm = TRUE
  )

  # Count Emerging domains
  dat_scored$hrtl_n_emerging <- rowSums(
    dat_scored[, domain_class_cols, drop = FALSE] == "Emerging",
    na.rm = TRUE
  )

  # Count Needs-Support domains
  dat_scored$hrtl_n_needs_support <- rowSums(
    dat_scored[, domain_class_cols, drop = FALSE] == "Needs-Support",
    na.rm = TRUE
  )

  # Step 3: Apply HRTL classification logic
  # Ready for Learning: (n_on_track >= 4) AND (n_needs_support == 0)
  dat_scored$hrtl_ready_for_learning <- (
    dat_scored$hrtl_n_on_track >= 4 &
    dat_scored$hrtl_n_needs_support == 0
  )

  # Create categorical classification
  # Insufficient data: fewer than 3 valid domains
  n_valid_domains <- (
    dat_scored$hrtl_n_on_track +
    dat_scored$hrtl_n_emerging +
    dat_scored$hrtl_n_needs_support
  )

  dat_scored$hrtl_classification <- ifelse(
    n_valid_domains < 3,
    "Insufficient Data",
    ifelse(
      dat_scored$hrtl_ready_for_learning,
      "Ready",
      "Not Ready"
    )
  )

  # Handle NA cases
  dat_scored$hrtl_classification[is.na(dat_scored$hrtl_ready_for_learning)] <- "Insufficient Data"

  # Step 4: Summary statistics
  if (verbose) {
    cat("HRTL Classification Results:\n")
    cat(stringr::str_dup("-", 80), "\n\n")

    # Overall classification
    class_table <- table(dat_scored$hrtl_classification, useNA = "ifany")
    cat("Overall Classifications:\n")
    for (i in seq_along(class_table)) {
      class_name <- names(class_table)[i]
      count <- as.numeric(class_table[i])
      pct <- 100 * count / nrow(dat_scored)
      cat(sprintf("  %-20s: %5d (%.1f%%)\n", class_name, count, pct))
    }

    cat("\n")

    # Distribution of On-Track domains
    cat("Distribution of On-Track Domains:\n")
    on_track_table <- table(dat_scored$hrtl_n_on_track)
    for (i in seq_along(on_track_table)) {
      n_domains <- names(on_track_table)[i]
      count <- as.numeric(on_track_table[i])
      pct <- 100 * count / nrow(dat_scored)
      cat(sprintf("  %s domains On-Track: %5d (%.1f%%)\n", n_domains, count, pct))
    }

    cat("\n")

    # Distribution of Needs-Support domains
    cat("Distribution of Needs-Support Domains:\n")
    needs_table <- table(dat_scored$hrtl_n_needs_support)
    for (i in seq_along(needs_table)) {
      n_domains <- names(needs_table)[i]
      count <- as.numeric(needs_table[i])
      pct <- 100 * count / nrow(dat_scored)
      cat(sprintf("  %s domains Needs-Support: %5d (%.1f%%)\n", n_domains, count, pct))
    }

    cat("\n")
    cat(stringr::str_dup("=", 80), "\n")
    cat("[SUCCESS] HRTL scoring complete\n")
    cat(sprintf("Added %d new columns to dataset\n", 5))  # 3 counts + ready + classification
    cat(stringr::str_dup("=", 80), "\n\n")
  }

  return(dat_scored)
}

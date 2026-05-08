# ==============================================================================
# MN26 Eligibility & Inclusion (NORC analytic-sample aligned)
# ==============================================================================
# The substantive sample-defining work happens upstream:
#   - apply_norc_replace_records()  pre-pivot (R/harmonize/mn26_norc_sample.R)
#   - apply_norc_sample()           pre-pivot
#   - norc_elig_screen()            pre-pivot — produces HH-level
#                                                 solo_kid_elig / youngest_kid_elig
#                                                 / oldest_kid_elig / elig_kids
#                                                 / elig_type / screener_complete
#                                                 / eligible (HH-level)
#   - pivot_mn26_wide_to_long()     overrides `eligible` to per-child:
#                                     child_num=1 → solo|youngest
#                                     child_num=2 → oldest
#   - compute_mn26_survey_completion()  post-pivot (R/transform/mn26_survey_completion.R)
#
# This file hosts the thin, post-pivot wrappers that the orchestrator calls:
#   - check_mn26_eligibility()  validates that per-child `eligible` is present
#                               and reports criterion breakdowns.
#   - apply_mn26_inclusion()    creates `meets_inclusion = eligible & survey_complete`,
#                               which is the analytic-sample flag matching NORC's
#                               `survey_completes` count.
# ==============================================================================

library(dplyr)


#' Validate / summarise per-child MN26 eligibility (NORC analytic sample)
#'
#' Asserts that the upstream NORC pipeline has already populated `eligible`
#' (per-child) and the supporting HH-level flags. Reports a breakdown by
#' eligibility scenario (`elig_type`) for traceability.
#'
#' Required columns (added pre-pivot by norc_elig_screen + propagated by
#' pivot_mn26_wide_to_long):
#'   eligible, elig_type, elig_kids, screener_complete,
#'   solo_kid_elig, youngest_kid_elig, oldest_kid_elig
#'
#' @param data Post-pivot data frame
#' @param verbose Print summary (default TRUE)
#' @return Data frame unchanged (eligibility was set upstream)
check_mn26_eligibility <- function(data, verbose = TRUE) {

  required <- c("eligible", "elig_type", "elig_kids", "screener_complete",
                "solo_kid_elig", "youngest_kid_elig", "oldest_kid_elig")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop("check_mn26_eligibility: missing NORC eligibility columns: ",
         paste(missing, collapse = ", "),
         "\nEnsure norc_elig_screen() ran on raw_wide before pivot.")
  }

  if (verbose) {
    n_total       <- nrow(data)
    n_eligible    <- sum(data$eligible %in% TRUE)
    n_screener_ok <- sum(data$screener_complete %in% TRUE)
    message("MN26 eligibility (NORC 4-scenario, per child)...")
    message("  Total rows:        ", n_total)
    message("  Screener complete: ", n_screener_ok)
    message("  Eligible:          ", n_eligible,
            " (", round(100 * n_eligible / n_total, 1), "%)")

    # Per-child breakdown by elig_type
    type_by_child <- data %>%
      dplyr::filter(.data$eligible %in% TRUE) %>%
      dplyr::count(.data$child_num, .data$elig_type, name = "n")
    if (nrow(type_by_child) > 0) {
      message("  Eligible breakdown (child_num × elig_type):")
      for (i in seq_len(nrow(type_by_child))) {
        message(sprintf("    child %s, scenario %s: %d",
                        type_by_child$child_num[i],
                        type_by_child$elig_type[i],
                        type_by_child$n[i]))
      }
    }
  }

  return(data)
}


#' Apply MN26 inclusion filter (NORC analytic sample)
#'
#' Creates the canonical `meets_inclusion` flag:
#'
#'   meets_inclusion = eligible & survey_complete
#'
#' This matches NORC's `# HHs completing the survey` count in
#' `norc_summary$summary_rates` (norc_summarise.R::norc_rates).
#'
#' @param data Data frame with `eligible` (per child) and `survey_complete` (HH)
#' @param verbose Print summary (default TRUE)
#' @return data with `meets_inclusion` column added
apply_mn26_inclusion <- function(data, verbose = TRUE) {

  if (!"eligible" %in% names(data)) {
    stop("apply_mn26_inclusion: `eligible` column missing")
  }
  if (!"survey_complete" %in% names(data)) {
    stop("apply_mn26_inclusion: `survey_complete` column missing ",
         "(run compute_mn26_survey_completion first)")
  }

  data <- data %>%
    dplyr::mutate(
      meets_inclusion = .data$eligible %in% TRUE & .data$survey_complete %in% TRUE
    )

  if (verbose) {
    n_included <- sum(data$meets_inclusion, na.rm = TRUE)
    message("  meets_inclusion (eligible & survey_complete): ",
            n_included, " of ", nrow(data))
  }

  return(data)
}

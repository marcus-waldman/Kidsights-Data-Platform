# ==============================================================================
# MN26 Survey Completion (NORC-aligned)
# ==============================================================================
# Computes per-household survey-completion status using NORC's instrument map.
# Mirrors `calculate_survey_completion()` from kidsights-norc/origin/norc_shared
# (progress-monitoring/mn26/monitoring_report.R) and the survey-complete rule
# from `norc_survey_complete()` in norc_summarise.R:
#
#   survey_complete = eligible & last_module_complete %in% c("Follow-up","Compensation")
#
# Intended call site: AFTER the wide-to-long pivot, BEFORE inclusion filtering.
# Module completion fields are household-level, so both child rows of a HH
# share the same last_module_complete and survey_complete value.
# ==============================================================================

library(dplyr)


#' Compute MN26 survey completion (NORC-aligned)
#'
#' Builds `last_module_complete` per row using NORC's instrument order, then
#' derives `survey_complete = eligible & last_module_complete %in%
#' c("Follow-up", "Compensation")`. Module 6 is collapsed across age-band
#' sub-instruments (any one == 2 → module complete).
#'
#' Required REDCap completion-flag columns (a subset may be absent depending
#' on the pull; they are handled gracefully):
#'   - consent_doc_complete
#'   - eligibility_form_norc_complete
#'   - module_2_family_information_complete
#'   - module_3_child_information_complete
#'   - module_6_*_complete (child 1 age bands; pattern excludes _2_complete)
#'   - nsch_questions_complete
#'   - child_information_2_954c_complete
#'   - module_6_*_2_complete (child 2 age bands)
#'   - nsch_questions_2_complete
#'   - module_9_compensation_information_complete
#'   - module_8_followup_information_complete
#'
#' @param data Data frame (post-pivot) with `eligible` already populated
#' @param survey_complete_modules Character vector of module labels that
#'   constitute "completed survey" (default `c("Follow-up","Compensation")`)
#' @param verbose Print summary (default TRUE)
#' @return data with `last_module_complete` and `survey_complete` columns added
compute_mn26_survey_completion <- function(data,
                                           survey_complete_modules = c("Follow-up", "Compensation"),
                                           verbose = TRUE) {

  if (!"eligible" %in% names(data)) {
    stop("compute_mn26_survey_completion requires `eligible` column ",
         "(run norc_elig_screen pre-pivot, then the pivot)")
  }

  is_complete <- function(x) !is.na(x) & x == 2

  # Module 6 child 1: any age-band sub-instrument complete
  m6_c1_cols <- grep(
    "^module_6_(?!.*_2_complete).*_complete$",
    names(data), value = TRUE, perl = TRUE
  )
  if (length(m6_c1_cols) > 0) {
    data$m6_c1_complete <- apply(
      data[, m6_c1_cols, drop = FALSE], 1,
      function(x) ifelse(any(x == 2, na.rm = TRUE), 2, NA_real_)
    )
  } else {
    data$m6_c1_complete <- NA_real_
  }

  # Module 6 child 2: any age-band sub-instrument complete
  m6_c2_cols <- grep("^module_6_.*_2_complete$", names(data), value = TRUE)
  if (length(m6_c2_cols) > 0) {
    data$m6_c2_complete <- apply(
      data[, m6_c2_cols, drop = FALSE], 1,
      function(x) ifelse(any(x == 2, na.rm = TRUE), 2, NA_real_)
    )
  } else {
    data$m6_c2_complete <- NA_real_
  }

  # Walk the instruments in NORC's order; the last one with status 2 is the
  # "last completed module"
  ordered <- list(
    list(col = "consent_doc_complete",                       label = "Consent"),
    list(col = "eligibility_form_norc_complete",             label = "Eligibility"),
    list(col = "module_2_family_information_complete",       label = "Family Info"),
    list(col = "module_3_child_information_complete",        label = "Child Info"),
    list(col = "m6_c1_complete",                             label = "Module 6 (C1)"),
    list(col = "nsch_questions_complete",                    label = "NSCH (C1)"),
    list(col = "child_information_2_954c_complete",          label = "Child Info 2"),
    list(col = "m6_c2_complete",                             label = "Module 6 (C2)"),
    list(col = "nsch_questions_2_complete",                  label = "NSCH (C2)"),
    list(col = "module_9_compensation_information_complete", label = "Compensation"),
    list(col = "module_8_followup_information_complete",     label = "Follow-up")
  )

  n <- nrow(data)
  last_module <- rep(NA_character_, n)
  for (item in ordered) {
    if (item$col %in% names(data)) {
      done <- is_complete(data[[item$col]])
      last_module[done] <- item$label
    }
  }
  data$last_module_complete <- last_module

  data$survey_complete <- (data$eligible %in% TRUE) &
                          (data$last_module_complete %in% survey_complete_modules)

  if (verbose) {
    n_eligible        <- sum(data$eligible %in% TRUE)
    n_with_last_mod   <- sum(!is.na(data$last_module_complete))
    n_survey_complete <- sum(data$survey_complete, na.rm = TRUE)
    message("MN26 survey completion (NORC-aligned)...")
    message("  Rows:                 ", n)
    message("  Has last_module:      ", n_with_last_mod)
    message("  Eligible:             ", n_eligible)
    message("  Survey complete:      ", n_survey_complete,
            " (eligible & last_module in {",
            paste(survey_complete_modules, collapse = ", "), "})")
  }

  return(data)
}

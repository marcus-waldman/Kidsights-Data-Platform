# ==============================================================================
# MN26 NORC Analytic Sample Definition
# ==============================================================================
# Ports NORC's authoritative analytic-sample logic from:
#   kidsights-norc/origin/norc_shared : progress-monitoring/mn26/utils/norc_summarise.R
#   (author: Matt Gunther, NORC; commits fc08769 + 8d591cb)
#
# Three pre-pivot, household-level operations applied to raw_wide:
#
#   1. apply_norc_replace_records(raw_wide, id_xwalk_path, reissue_pid)
#        Dedupe returning respondents. Project 8792 reissues fresh URLs/record_ids
#        to participants who closed the survey early. The id_xwalk crosswalk maps
#        every record_id to its P_SUID (one P_SUID per person across all reissues).
#        Drops superseded records and unused 8792 record_ids.
#
#   2. apply_norc_sample(raw_wide)
#        filter(!smoke_case | !in_scope) — drops smoke (test) cases that are
#        also in the sample frame. Retains out-of-scope cases (no P_SUID,
#        flagged undeliverable by NCOA after frame draw) so the sampled-frame
#        denominator stays equal to the original frame size.
#
#   3. norc_elig_screen(raw_wide)
#        4-scenario household eligibility (elig_type ∈ {"1","2","3a","3b"}):
#          Scenario 1: 1 child u6 (MN-born, age <=2191 days, parent/guardian)
#          Scenario 2: >1 child u6, exactly 1 MN-born; youngest MN-born qualifies
#          Scenario 3a: >1 child u6, >1 MN-born; youngest qualifies
#          Scenario 3b: >1 child u6, >1 MN-born; next-youngest qualifies
#        Outputs household-level flags consumed downstream by the pivot to derive
#        per-child `eligible`.
# ==============================================================================

library(dplyr)
library(purrr)


#' Load and dedupe a NORC id_xwalk RDS file
#'
#' Reads NORC's P_SUID crosswalk and prepares it for joining to REDCap data.
#' The on-disk file uses uppercase `PID` and integer types; REDCap pulls use
#' lowercase `pid` as character. We coerce here so downstream joins on
#' (pid, record_id) succeed without type mismatches.
#'
#' @param id_xwalk_path Path to id_xwalk.rds
#' @return Data frame with columns P_SUID, P_PIN, survey_link, pid (chr),
#'   smoke_case (lgl), record_id (int)
load_norc_id_xwalk <- function(id_xwalk_path) {
  if (!file.exists(id_xwalk_path)) {
    stop("NORC id_xwalk file not found: ", id_xwalk_path)
  }
  xwalk <- readRDS(id_xwalk_path)
  required <- c("P_SUID", "P_PIN", "survey_link", "PID", "smoke_case", "record_id")
  missing <- setdiff(required, names(xwalk))
  if (length(missing) > 0) {
    stop("id_xwalk missing required columns: ", paste(missing, collapse = ", "))
  }
  xwalk <- xwalk %>%
    dplyr::rename(pid = PID) %>%
    dplyr::mutate(
      pid = as.character(pid),
      record_id = as.integer(record_id)
    )
  return(xwalk)
}


#' Replace records expired by a fresh URL reissue (NORC project 8792)
#'
#' When a respondent closes the survey before saving, NORC issues them a fresh
#' URL and record_id from the reissue project (default pid 8792). The new
#' record_id is added to id_xwalk under the same P_SUID. This function:
#'
#'   1. Joins id_xwalk to raw_wide on (pid, record_id).
#'   2. Identifies "active" reissues: rows in the reissue project with a
#'      non-NA consent_date_n (the participant has come back and consented).
#'   3. For respondents who consented on multiple reissues, keeps only the
#'      latest consent.
#'   4. Drops superseded records: any row with a P_SUID also held by an active
#'      reissue but a different record_id (i.e., the older expired record).
#'   5. Drops unused reissue records: any row in the reissue project whose
#'      P_SUID has not yet activated a reissue.
#'
#' Adds columns to raw_wide: P_SUID, P_PIN, survey_link, smoke_case, in_scope.
#' `in_scope` is computed at runtime as !is.na(P_SUID); rows missing from the
#' frame (e.g., NCOA-undeliverable after frame draw) get FALSE and are still
#' retained so the sample-frame denominator is preserved.
#'
#' @param raw_wide Wide REDCap data frame (one row per HH-record)
#' @param id_xwalk_path Path to id_xwalk.rds
#' @param reissue_pid REDCap project id used for reissued URLs (default 8792)
#' @param verbose Print summary lines (default TRUE)
#' @return Augmented raw_wide with id_xwalk columns and dedup applied
apply_norc_replace_records <- function(raw_wide,
                                       id_xwalk_path,
                                       reissue_pid = 8792,
                                       verbose = TRUE) {

  if (verbose) message("Applying NORC replace_records dedup...")

  if (!"pid" %in% names(raw_wide)) {
    stop("raw_wide must have a 'pid' column before apply_norc_replace_records()")
  }
  if (!"record_id" %in% names(raw_wide)) {
    stop("raw_wide must have a 'record_id' column before apply_norc_replace_records()")
  }
  if (!"consent_date_n" %in% names(raw_wide)) {
    stop("raw_wide must include 'consent_date_n' for reissue dedup logic")
  }
  if (!"survey_link" %in% names(raw_wide)) {
    # Mirror NORC: production-report.R:198 joins id_xwalk on (record_id, survey_link)
    # to resolve cases where the same record_id has multiple xwalk entries
    # (different survey URLs issued to the same respondent).
    stop("raw_wide must include 'survey_link' for NORC xwalk join ",
         "(mirrors kidsights-norc:norc_shared production-report.R:197-201)")
  }

  reissue_pid_chr <- as.character(reissue_pid)

  xwalk <- load_norc_id_xwalk(id_xwalk_path)

  # Coerce raw_wide's pid/record_id to match xwalk types for the join
  raw_wide <- raw_wide %>%
    dplyr::mutate(
      pid = as.character(pid),
      record_id = as.integer(record_id)
    )

  # Step A — Identify active reissues (consented rows in the reissue project).
  # Join on (record_id, survey_link) per NORC; using (pid, record_id) would
  # inflate when xwalk has multiple survey_links per (pid, record_id).
  reissue_consented <- raw_wide %>%
    dplyr::filter(pid == reissue_pid_chr, !is.na(consent_date_n)) %>%
    dplyr::select(pid, record_id, survey_link, consent_date_n) %>%
    dplyr::left_join(xwalk %>% dplyr::select(record_id, survey_link, P_SUID),
                     by = c("record_id", "survey_link")) %>%
    dplyr::filter(!is.na(P_SUID))

  # If a P_SUID activated multiple reissue record_ids, keep the latest consent
  if (nrow(reissue_consented) > 0) {
    reissue_consented <- reissue_consented %>%
      dplyr::group_by(P_SUID) %>%
      dplyr::filter(consent_date_n == max(consent_date_n, na.rm = TRUE)) %>%
      dplyr::ungroup()
  }
  active_reissue_suids    <- reissue_consented$P_SUID
  active_reissue_recordids <- reissue_consented$record_id

  # Step B — Augment raw_wide with id_xwalk columns. Join on (record_id,
  # survey_link) per NORC production-report.R:198 — survey_link is unique per
  # REDCap submission and selects the one xwalk row that matches the data
  # even when the original xwalk has multiple survey_links per (pid, record_id).
  augmented <- raw_wide %>%
    dplyr::left_join(
      xwalk %>% dplyr::select(record_id, survey_link, P_SUID, P_PIN, smoke_case),
      by = c("record_id", "survey_link")
    ) %>%
    dplyr::mutate(in_scope = !is.na(P_SUID))

  n_in <- nrow(augmented)

  # Step C — Drop superseded records: P_SUID has an active reissue, this is
  # NOT the chosen reissue record
  drop_superseded <- !is.na(augmented$P_SUID) &
    augmented$P_SUID %in% active_reissue_suids &
    !augmented$record_id %in% active_reissue_recordids
  augmented <- augmented[!drop_superseded, , drop = FALSE]

  # Step D — Drop unused reissue records: in the reissue project, P_SUID never
  # activated (no consent yet)
  drop_unused_reissue <- augmented$pid == reissue_pid_chr &
    (is.na(augmented$P_SUID) | !augmented$P_SUID %in% active_reissue_suids)
  augmented <- augmented[!drop_unused_reissue, , drop = FALSE]

  if (verbose) {
    message("  Input rows:           ", n_in)
    message("  Active reissues:      ", length(active_reissue_suids))
    message("  Superseded dropped:   ", sum(drop_superseded))
    message("  Unused 8792 dropped:  ", sum(drop_unused_reissue))
    message("  Output rows:          ", nrow(augmented))
    message("  In-scope (P_SUID):    ", sum(augmented$in_scope, na.rm = TRUE))
    message("  Out-of-scope:         ", sum(!augmented$in_scope, na.rm = TRUE))
  }

  return(augmented)
}


#' Drop in-scope smoke cases; retain out-of-scope cases
#'
#' Direct port of NORC's `norc_sample()`: filter(!smoke_case | !in_scope).
#' Equivalent: drop only rows where smoke_case = TRUE AND in_scope = TRUE.
#' Out-of-scope cases (no P_SUID; smoke_case will be NA) are retained so the
#' denominator equals the original sample-frame size.
#'
#' @param raw_wide Augmented raw_wide from apply_norc_replace_records()
#' @param verbose Print summary (default TRUE)
#' @return Filtered raw_wide
apply_norc_sample <- function(raw_wide, verbose = TRUE) {

  if (!all(c("smoke_case", "in_scope") %in% names(raw_wide))) {
    stop("apply_norc_sample requires `smoke_case` and `in_scope` columns; ",
         "run apply_norc_replace_records() first")
  }

  n_in <- nrow(raw_wide)
  smoke <- raw_wide$smoke_case %in% TRUE  # NA-safe: NA → FALSE
  in_sc <- raw_wide$in_scope  %in% TRUE
  drop <- smoke & in_sc

  out <- raw_wide[!drop, , drop = FALSE]

  if (verbose) {
    message("Applying NORC sample filter (drop smoke & in_scope)...")
    message("  Input rows:    ", n_in)
    message("  Smoke dropped: ", sum(drop))
    message("  Output rows:   ", nrow(out))
  }
  return(out)
}


#' NORC 4-scenario household eligibility screen
#'
#' Direct port of `norc_elig_screen()` from norc_summarise.R. Computes
#' household-level eligibility using the NORC eligibility form variables.
#'
#' Required input columns:
#'   - dob_n, dob_c2_n, consent_date_n (date sanity check)
#'   - age_in_days_n, age_in_days_c2_n (child ages in days)
#'   - kids_u6_n (number of children under 6 in HH)
#'   - mn_birth_c1_n (1 if youngest child MN-born, 0 otherwise)
#'   - mn_birth_c2_n (number of older children MN-born, when kids_u6_n > 1)
#'   - parent_guardian_c1_n, parent_guardian_c2_n (1 = respondent is parent/guardian)
#'   - eligibility_form_norc_complete (REDCap completion flag, 0/1/2)
#'
#' Adds columns to raw_wide:
#'   - mn_kids: number of MN-born under-6 children (0/1/>1)
#'   - solo_kid_elig, youngest_kid_elig, oldest_kid_elig: per-slot eligibility flags
#'   - elig_kids: count of eligible children in HH (0/1/2)
#'   - elig_type: scenario classifier ("1", "2", "3a", "3b", or NA)
#'   - screener_complete: TRUE if eligibility_form_norc_complete != 0
#'   - eligible: TRUE if any elig_type matched AND screener_complete
#'
#' Note: child age cap is 2191 days (~6 years) — admits the full 0-5.99-yr
#' band. Differs from earlier draft (1825 days).
#'
#' @param raw_wide Data frame from apply_norc_sample()
#' @param age_max_days Numeric, maximum age in days (default 2191)
#' @param verbose Print summary (default TRUE)
#' @return raw_wide with HH-level eligibility columns added
norc_elig_screen <- function(raw_wide, age_max_days = 2191, verbose = TRUE) {

  required <- c("dob_n", "dob_c2_n", "consent_date_n",
                "age_in_days_n", "age_in_days_c2_n",
                "kids_u6_n", "mn_birth_c1_n", "mn_birth_c2_n",
                "parent_guardian_c1_n", "parent_guardian_c2_n",
                "eligibility_form_norc_complete")
  missing <- setdiff(required, names(raw_wide))
  if (length(missing) > 0) {
    stop("norc_elig_screen requires the following columns from REDCap: ",
         paste(missing, collapse = ", "))
  }

  out <- raw_wide %>%
    dplyr::mutate(
      # DOB sanity: nullify ages whose DOB is after consent (data error)
      age_in_days_n = dplyr::if_else(
        !is.na(dob_n) & !is.na(consent_date_n) & dob_n <= consent_date_n,
        age_in_days_n,
        NA_real_
      ),
      age_in_days_c2_n = dplyr::if_else(
        !is.na(dob_c2_n) & !is.na(consent_date_n) & dob_c2_n <= consent_date_n,
        age_in_days_c2_n,
        NA_real_
      ),
      mn_kids = dplyr::case_when(
        kids_u6_n == 0                            ~ 0,
        kids_u6_n == 1 & mn_birth_c1_n == 0       ~ 0,
        kids_u6_n == 1 & mn_birth_c1_n == 1       ~ 1,
        kids_u6_n  > 1                            ~ as.numeric(mn_birth_c2_n),
        TRUE                                      ~ NA_real_
      ),
      solo_kid_elig = dplyr::case_when(
        mn_kids == 1 ~ age_in_days_n <= age_max_days & parent_guardian_c1_n == 1
      ),
      youngest_kid_elig = dplyr::case_when(
        mn_kids > 1 ~ age_in_days_n <= age_max_days & parent_guardian_c1_n == 1
      ),
      oldest_kid_elig = dplyr::case_when(
        mn_kids > 1 ~ age_in_days_c2_n <= age_max_days & parent_guardian_c2_n == 1
      ),
      elig_kids = dplyr::case_when(
        solo_kid_elig %in% TRUE                                       ~ 1,
        youngest_kid_elig %in% TRUE & !(oldest_kid_elig %in% TRUE)    ~ 1,
        oldest_kid_elig   %in% TRUE & !(youngest_kid_elig %in% TRUE)  ~ 1,
        youngest_kid_elig %in% TRUE & oldest_kid_elig %in% TRUE       ~ 2,
        TRUE                                                          ~ 0
      ),
      elig_type = dplyr::case_when(
        kids_u6_n == 1 &
          mn_birth_c1_n == 1 &
          age_in_days_n <= age_max_days &
          parent_guardian_c1_n == 1                ~ "1",
        kids_u6_n  > 1 &
          mn_birth_c2_n == 1 &
          age_in_days_n <= age_max_days &
          parent_guardian_c1_n == 1                ~ "2",
        kids_u6_n  > 1 &
          mn_birth_c2_n  > 1 &
          age_in_days_n <= age_max_days &
          parent_guardian_c1_n == 1                ~ "3a",
        kids_u6_n  > 1 &
          mn_birth_c2_n  > 1 &
          age_in_days_c2_n <= age_max_days &
          parent_guardian_c2_n == 1                ~ "3b",
        TRUE                                       ~ NA_character_
      ),
      screener_complete = !is.na(eligibility_form_norc_complete) &
                          eligibility_form_norc_complete != 0,
      eligible = !is.na(elig_type) & screener_complete
    )

  if (verbose) {
    n <- nrow(out)
    message("NORC elig_screen (HH-level)...")
    message("  Households:        ", n)
    message("  Screener complete: ", sum(out$screener_complete, na.rm = TRUE))
    message("  Eligible HHs:      ", sum(out$eligible, na.rm = TRUE),
            " (", round(100 * sum(out$eligible, na.rm = TRUE) / n, 1), "%)")
    type_tab <- table(out$elig_type, useNA = "ifany")
    message("  By scenario:")
    for (i in seq_along(type_tab)) {
      nm <- names(type_tab)[i]
      message("    ", if (is.na(nm)) "<NA>" else nm, ": ", type_tab[i])
    }
    message("  elig_kids distribution:")
    ek_tab <- table(out$elig_kids, useNA = "ifany")
    for (i in seq_along(ek_tab)) {
      nm <- names(ek_tab)[i]
      message("    ", if (is.na(nm)) "<NA>" else nm, ": ", ek_tab[i])
    }
  }

  return(out)
}

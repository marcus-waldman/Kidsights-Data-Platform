# ==============================================================================
# MN26 Eligibility Validation (NORC Production-Aligned)
# ==============================================================================
# Evaluates eligibility per child row (post-pivot, 1 row per child).
#
# NORC production design: NORC pre-screens participants for caregiver age,
# primary caregiver status, and Minnesota residency BEFORE routing them to
# REDCap. As a result, the legacy NE25 eligibility form fields (eq002, eq003,
# mn_eqstate) are not collected in the NORC production REDCap projects.
#
# Required criteria (always checked — columns reliably present):
#   1. Informed consent (eq001 == 1)
#   2. Child age 0-5 years (age_in_days_n <= 1825)
#
# Optional criteria (checked if columns exist — legacy test projects):
#   3. Parent age >= 19 (eq003 == 1)
#   4. Primary caregiver (eq002 == 1)
#   5. Minnesota residence (mn_eqstate == 1)
#
# See: kidsights-norc commit 4d97629 "Restructure monitoring output per
# NORC feedback" which dropped screener_status/eligibility outputs entirely.
# ==============================================================================

library(dplyr)

#' Check MN26 eligibility criteria (NORC production-aligned)
#'
#' Applies required criteria (consent + child age) plus any legacy criteria
#' whose columns are present in the data. NORC pre-screening assumed for
#' caregiver age, primary caregiver status, and MN residence when those
#' legacy fields are absent.
#'
#' @param data Data frame (post-pivot, 1 row per child)
#' @param verbose Logical, print summary (default TRUE)
#' @return Data frame with eligibility columns added
check_mn26_eligibility <- function(data, verbose = TRUE) {

  if (verbose) message("Checking MN26 eligibility (NORC production-aligned)...")

  cols <- names(data)
  has_eq001      <- "eq001"         %in% cols
  has_age        <- "age_in_days_n" %in% cols
  has_eq002      <- "eq002"         %in% cols
  has_eq003      <- "eq003"         %in% cols
  has_mn_state   <- "mn_eqstate"    %in% cols

  # --- Required criteria -----------------------------------------------------

  if (!has_eq001) {
    stop("Required column 'eq001' (informed consent) not found in data.")
  }
  if (!has_age) {
    stop("Required column 'age_in_days_n' not found in data.")
  }

  elig_df <- data %>%
    dplyr::mutate(
      pass_consent = !is.na(eq001) & eq001 == 1,
      pass_child_age = !is.na(age_in_days_n) & age_in_days_n <= 1825
    )

  # --- Optional legacy criteria (only if columns exist) ---------------------

  if (has_eq003) {
    elig_df$pass_parent_age <- !is.na(elig_df$eq003) & elig_df$eq003 == 1
  } else {
    # NORC pre-screened — assume pass
    elig_df$pass_parent_age <- NA
  }

  if (has_eq002) {
    elig_df$pass_primary_caregiver <- !is.na(elig_df$eq002) & elig_df$eq002 == 1
  } else {
    elig_df$pass_primary_caregiver <- NA
  }

  if (has_mn_state) {
    elig_df$pass_minnesota_residence <- !is.na(elig_df$mn_eqstate) & elig_df$mn_eqstate == 1
  } else {
    elig_df$pass_minnesota_residence <- NA
  }

  # --- Overall eligibility ---------------------------------------------------
  # Pass if all REQUIRED criteria pass AND any present legacy criteria pass.
  # Legacy criteria with missing columns contribute NA and are ignored via
  # `| is.na(...)` — which counts them as effectively TRUE for NORC
  # pre-screening.

  elig_df <- elig_df %>%
    dplyr::mutate(
      eligible = pass_consent &
                 pass_child_age &
                 (pass_parent_age | is.na(pass_parent_age)) &
                 (pass_primary_caregiver | is.na(pass_primary_caregiver)) &
                 (pass_minnesota_residence | is.na(pass_minnesota_residence)),

      # Exclusion reason (first failing required/present criterion)
      exclusion_reason = dplyr::case_when(
        eligible ~ NA_character_,
        !pass_consent ~ "No informed consent",
        !pass_child_age ~ "Child age > 5 years or missing",
        has_eq003 & !pass_parent_age %in% TRUE ~ "Parent age < 19 or missing",
        has_eq002 & !pass_primary_caregiver %in% TRUE ~ "Not primary caregiver or missing",
        has_mn_state & !pass_minnesota_residence %in% TRUE ~ "Not Minnesota resident or missing",
        TRUE ~ "Unknown"
      )
    )

  # --- Verbose summary -------------------------------------------------------

  if (verbose) {
    n_total <- nrow(elig_df)
    n_eligible <- sum(elig_df$eligible, na.rm = TRUE)
    message("  Total children:      ", n_total)
    message("  Eligible:            ", n_eligible,
            " (", round(100 * n_eligible / n_total, 1), "%)")
    message("  Criterion breakdown:")
    message("    Consent (eq001):         ", sum(elig_df$pass_consent, na.rm = TRUE),
            " [required]")
    message("    Child age (<=5yr):       ", sum(elig_df$pass_child_age, na.rm = TRUE),
            " [required]")
    message("    Parent age (eq003):      ",
            if (has_eq003) sum(elig_df$pass_parent_age, na.rm = TRUE) else "column absent",
            if (has_eq003) " [applied]" else " [NORC pre-screened, skipped]")
    message("    Primary CG (eq002):      ",
            if (has_eq002) sum(elig_df$pass_primary_caregiver, na.rm = TRUE) else "column absent",
            if (has_eq002) " [applied]" else " [NORC pre-screened, skipped]")
    message("    MN residence (mn_eqstate): ",
            if (has_mn_state) sum(elig_df$pass_minnesota_residence, na.rm = TRUE) else "column absent",
            if (has_mn_state) " [applied]" else " [NORC pre-screened, skipped]")
  }

  return(elig_df)
}

#' Apply MN26 eligibility flags
#'
#' Creates meets_inclusion filter column. For MN26, meets_inclusion = eligible
#' (no authenticity/influence screening yet).
#'
#' @param data Data frame with eligibility columns from check_mn26_eligibility()
#' @param verbose Logical, print summary (default TRUE)
#' @return Data frame with meets_inclusion column
apply_mn26_inclusion <- function(data, verbose = TRUE) {

  data <- data %>%
    dplyr::mutate(
      meets_inclusion = eligible
    )

  if (verbose) {
    n_included <- sum(data$meets_inclusion, na.rm = TRUE)
    message("  Meets inclusion: ", n_included, " of ", nrow(data))
  }

  return(data)
}

# ==============================================================================
# MN26 Eligibility Validation (4 Criteria)
# ==============================================================================
# Evaluates eligibility per child row (post-pivot, 1 row per child).
# Ported from kidsights-norc monitoring logic.
#
# Criteria:
#   1. Parent age >= 19 (eq003 == 1)
#   2. Child age 0-5 years (age_in_days_n <= 1825)
#   3. Primary caregiver (eq002 == 1)
#   4. Minnesota residence (mn_eqstate == 1)
# ==============================================================================

library(dplyr)

#' Check MN26 eligibility criteria
#'
#' @param data Data frame (post-pivot, 1 row per child)
#' @param verbose Logical, print summary (default TRUE)
#' @return Data frame with eligibility columns added
check_mn26_eligibility <- function(data, verbose = TRUE) {

  if (verbose) message("Checking MN26 eligibility (4 criteria)...")

  elig_df <- data %>%
    dplyr::mutate(
      # Criterion 1: Parent/caregiver age >= 19
      pass_parent_age = !is.na(eq003) & eq003 == 1,

      # Criterion 2: Child age 0-5 years (1825 days)
      pass_child_age = !is.na(age_in_days_n) & age_in_days_n <= 1825,

      # Criterion 3: Respondent is primary caregiver
      pass_primary_caregiver = !is.na(eq002) & eq002 == 1,

      # Criterion 4: Lives in Minnesota
      pass_minnesota_residence = !is.na(mn_eqstate) & mn_eqstate == 1,

      # Overall eligibility (all 4 must be TRUE)
      eligible = pass_parent_age & pass_child_age &
                 pass_primary_caregiver & pass_minnesota_residence,

      # Exclusion reason (first failing criterion)
      exclusion_reason = dplyr::case_when(
        eligible ~ NA_character_,
        !pass_parent_age ~ "Parent age < 19 or missing",
        !pass_child_age ~ "Child age > 5 years or missing",
        !pass_primary_caregiver ~ "Not primary caregiver or missing",
        !pass_minnesota_residence ~ "Not Minnesota resident or missing",
        TRUE ~ "Unknown"
      )
    )

  if (verbose) {
    n_total <- nrow(elig_df)
    n_eligible <- sum(elig_df$eligible, na.rm = TRUE)
    message("  Total children: ", n_total)
    message("  Eligible: ", n_eligible, " (", round(100 * n_eligible / n_total, 1), "%)")
    message("  Criterion breakdown:")
    message("    Parent age:      ", sum(elig_df$pass_parent_age, na.rm = TRUE))
    message("    Child age:       ", sum(elig_df$pass_child_age, na.rm = TRUE))
    message("    Primary CG:      ", sum(elig_df$pass_primary_caregiver, na.rm = TRUE))
    message("    MN residence:    ", sum(elig_df$pass_minnesota_residence, na.rm = TRUE))
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

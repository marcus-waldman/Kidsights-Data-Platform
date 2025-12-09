# Mental Health Scoring Functions
# PHQ-2 and GAD-2 total score computation for NHIS data
#
# Created: December 2025
# Purpose: Score depression (PHQ-2) and anxiety (GAD-2) screening instruments
#          for use in covariance pipeline Block 2 (Parental Mental Health)

#' Recode NHIS Mental Health Items (IPUMS codes → 0-3)
#'
#' @param x Numeric vector: Raw NHIS variable values
#' @return Numeric vector: 0-3 scale (NA for 7/8/9 missing codes)
#'
#' @details
#' IPUMS/NHIS coding:
#'   0 = Not at all
#'   1 = Several days
#'   2 = More than half the days
#'   3 = Nearly every day
#'   7 = Unknown-refused
#'   8 = Not ascertained
#'   9 = Don't know
#'
#' @examples
#' recode_nhis_mh_item(c(0, 1, 2, 3, 7, 8, 9))
#' # Returns: 0 1 2 3 NA NA NA
recode_nhis_mh_item <- function(x) {
  dplyr::if_else(x >= 0 & x <= 3, x, NA_real_)
}

#' Score PHQ-2 Depression Total (0-6 scale)
#'
#' @param phqintr Numeric: Little interest or pleasure item (0-3, NA for missing)
#' @param phqdep Numeric: Feeling down, depressed, or hopeless item (0-3, NA for missing)
#' @return Numeric: PHQ-2 total score (0-6) or NA if any item missing
#'
#' @details
#' PHQ-2 is a brief depression screening instrument with 2 items:
#'   1. Little interest or pleasure in doing things
#'   2. Feeling down, depressed, or hopeless
#'
#' Total score range: 0-6
#' Clinical cutoff: ≥3 indicates positive screen for depression
#'
#' Conservative missing data handling: If either item is missing, return NA
#' (no partial scoring)
#'
#' @references
#' Kroenke K, Spitzer RL, Williams JB. The Patient Health Questionnaire-2:
#' validity of a two-item depression screener. Med Care. 2003;41(11):1284-92.
#'
#' @examples
#' score_phq2_total(0, 0)  # Returns 0 (no symptoms)
#' score_phq2_total(3, 3)  # Returns 6 (maximum severity)
#' score_phq2_total(2, NA) # Returns NA (missing data)
score_phq2_total <- function(phqintr, phqdep) {
  dplyr::if_else(
    !is.na(phqintr) & !is.na(phqdep),
    phqintr + phqdep,
    NA_real_
  )
}

#' Score GAD-2 Anxiety Total (0-6 scale)
#'
#' @param gadanx Numeric: Feeling nervous, anxious, or on edge item (0-3, NA for missing)
#' @param gadworctrl Numeric: Not being able to stop or control worrying item (0-3, NA for missing)
#' @return Numeric: GAD-2 total score (0-6) or NA if any item missing
#'
#' @details
#' GAD-2 is a brief anxiety screening instrument with 2 items:
#'   1. Feeling nervous, anxious, or on edge
#'   2. Not being able to stop or control worrying
#'
#' Total score range: 0-6
#' Clinical cutoff: ≥3 indicates positive screen for anxiety
#'
#' Conservative missing data handling: If either item is missing, return NA
#' (no partial scoring)
#'
#' @references
#' Kroenke K, Spitzer RL, Williams JB, Monahan PO, Löwe B. Anxiety disorders
#' in primary care: prevalence, impairment, comorbidity, and detection.
#' Ann Intern Med. 2007;146(5):317-25.
#'
#' @examples
#' score_gad2_total(0, 0)  # Returns 0 (no symptoms)
#' score_gad2_total(3, 3)  # Returns 6 (maximum severity)
#' score_gad2_total(2, NA) # Returns NA (missing data)
score_gad2_total <- function(gadanx, gadworctrl) {
  dplyr::if_else(
    !is.na(gadanx) & !is.na(gadworctrl),
    gadanx + gadworctrl,
    NA_real_
  )
}

#' Classify PHQ-2 Positive Screen (Binary)
#'
#' @param phq2_total Numeric: PHQ-2 total score (0-6)
#' @return Integer: 1 if positive screen (≥3), 0 if negative, NA if missing
#'
#' @details
#' Applies clinical cutoff of ≥3 for positive depression screen
#' Used in raking targets pipeline (not covariance pipeline)
#'
#' @examples
#' classify_phq2_positive(c(0, 1, 2, 3, 4, 5, 6, NA))
#' # Returns: 0 0 0 1 1 1 1 NA
classify_phq2_positive <- function(phq2_total) {
  dplyr::case_when(
    is.na(phq2_total) ~ NA_integer_,
    phq2_total >= 3 ~ 1L,
    TRUE ~ 0L
  )
}

#' Classify GAD-2 Positive Screen (Binary)
#'
#' @param gad2_total Numeric: GAD-2 total score (0-6)
#' @return Integer: 1 if positive screen (≥3), 0 if negative, NA if missing
#'
#' @details
#' Applies clinical cutoff of ≥3 for positive anxiety screen
#' Used in raking targets pipeline (not covariance pipeline)
#'
#' @examples
#' classify_gad2_positive(c(0, 1, 2, 3, 4, 5, 6, NA))
#' # Returns: 0 0 0 1 1 1 1 NA
classify_gad2_positive <- function(gad2_total) {
  dplyr::case_when(
    is.na(gad2_total) ~ NA_integer_,
    gad2_total >= 3 ~ 1L,
    TRUE ~ 0L
  )
}

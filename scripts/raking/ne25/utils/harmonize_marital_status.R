# Marital Status Harmonization Utility
# Converts marital status across ACS, NHIS, and NSCH to binary "married" indicator

#' Convert ACS Marital Status to Binary Married Indicator
#'
#' ACS MARST variable (1-6, 9) represents marital status of householder/parent.
#' This function creates binary indicator: 1 = Married, spouse present; 0 = otherwise
#'
#' @param MARST ACS marital status variable
#'        (1=Married, spouse present, 2=Married, spouse absent, 3=Separated,
#'         4=Divorced, 5=Widowed, 6=Never married/Single, 9=Missing)
#' @return Integer vector (0/1) or NA for missing (MARST == 9)
#'
#' @details
#' Classification: Only MARST == 1 (Married, spouse present) coded as 1.
#' All other valid codes (2-6) coded as 0. Missing (9) coded as NA.
harmonize_acs_marital <- function(MARST) {
  dplyr::case_when(
    MARST == 9 ~ NA_integer_,          # Missing
    MARST == 1 ~ 1L,                   # Married, spouse present
    MARST %in% 2:6 ~ 0L,               # All other valid codes
    TRUE ~ NA_integer_
  )
}

#' Convert NHIS Marital Status to Binary Married Indicator
#'
#' NHIS parental marital status (typically PAR1MARST or similar variable).
#' Creates binary indicator: 1 = Married; 0 = otherwise
#'
#' @param marital_status NHIS marital status variable
#'        Expected coding: 1=Married, 2=Widowed, 3=Divorced, 4=Separated, 5=Never married,
#'        (exact coding may vary by NHIS year - verify from documentation)
#' @return Integer vector (0/1) or NA for missing
#'
#' @details
#' Conservative approach: Only marital_status == 1 (Married) coded as 1.
#' All other codes (2-5) and missing coded as 0 or NA respectively.
harmonize_nhis_marital <- function(marital_status) {
  dplyr::case_when(
    is.na(marital_status) ~ NA_integer_,   # Missing
    marital_status == 1 ~ 1L,              # Married
    TRUE ~ 0L                              # All others (widowed, divorced, separated, never married)
  )
}

#' Convert NSCH Marital Status to Binary Married Indicator
#'
#' NSCH adult marital status (typically A1_MARITAL or similar categorical variable).
#' Creates binary indicator: 1 = Married; 0 = otherwise
#'
#' @param marital_cat Character vector of marital status categories
#'        Expected: "Married", "Divorced", "Separated", "Widowed", "Never married", etc.
#' @return Integer vector (0/1) or NA for missing
#'
#' @details
#' Conservative approach: Only "Married" (with or without spouse present) coded as 1.
harmonize_nsch_marital <- function(marital_cat) {
  dplyr::case_when(
    is.na(marital_cat) ~ NA_integer_,
    stringr::str_detect(marital_cat, "(?i)married") ~ 1L,  # Case-insensitive match for "Married"
    TRUE ~ 0L                                              # All others
  )
}

#' Convert Numeric NSCH Marital Code to Binary
#'
#' Alternative function if NSCH uses numeric marital codes.
#'
#' @param marital_code Numeric vector (1=Married, 2=Divorced, 3=Separated, 4=Widowed, 5=Never married)
#' @return Integer vector (0/1) or NA for missing
harmonize_nsch_marital_numeric <- function(marital_code) {
  dplyr::case_when(
    is.na(marital_code) ~ NA_integer_,
    marital_code == 1 ~ 1L,            # Married
    marital_code %in% 2:5 ~ 0L,        # Divorced, Separated, Widowed, Never married
    TRUE ~ NA_integer_
  )
}

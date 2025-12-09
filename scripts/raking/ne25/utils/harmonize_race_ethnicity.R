# Race/Ethnicity Harmonization Utility
# Converts race/ethnicity coding across ACS, NHIS, and NSCH to 4-category scheme
# Categories: White NH, Black, Hispanic, Other

#' Harmonize Race/Ethnicity from ACS
#'
#' @param RACE ACS RACE variable (1=White, 2=Black, 3=AIAN, 4=Asian, 5=NHPI, 6=Some other, 7-9=Multi/Other)
#' @param HISPAN ACS HISPAN variable (0=Non-Hispanic, 1-4=Hispanic subgroups, 9=Missing)
#' @return Character vector with categories: "White NH", "Black", "Hispanic", "Other"
harmonize_acs_race <- function(RACE, HISPAN) {
  dplyr::case_when(
    # Hispanic takes priority (any Hispanic origin coded 1-4)
    HISPAN >= 1 & HISPAN <= 4 ~ "Hispanic",
    # White non-Hispanic
    RACE == 1 & HISPAN == 0 ~ "White NH",
    # Black non-Hispanic
    RACE == 2 & HISPAN == 0 ~ "Black",
    # All other combinations: AIAN, Asian, NHPI, mixed race, etc.
    TRUE ~ "Other"
  )
}

#' Harmonize Race/Ethnicity from NHIS
#'
#' @param RACENEW NHIS race variable (100=White, 200=Black, 300=AIAN, 400=Asian, 500=NHPI, 600=Multi/Other)
#' @param HISPETH NHIS Hispanic ethnicity variable
#'        Coding scheme 1: 10=Non-Hispanic, 20-27=Hispanic subgroups
#'        Coding scheme 2: 10=Non-Hispanic, 20+=Hispanic (various codes), 60+=Puerto Rico/Other
#' @return Character vector with categories: "White NH", "Black", "Hispanic", "Other"
harmonize_nhis_race <- function(RACENEW, HISPETH) {
  dplyr::case_when(
    # Hispanic takes priority (any Hispanic ethnicity code >= 20, excluding 93=unknown)
    HISPETH >= 20 & HISPETH != 93 ~ "Hispanic",
    # White non-Hispanic
    RACENEW == 100 & HISPETH == 10 ~ "White NH",
    # Black non-Hispanic
    RACENEW == 200 & HISPETH == 10 ~ "Black",
    # All other combinations (including HISPETH=93/missing)
    TRUE ~ "Other"
  )
}

#' Harmonize Race/Ethnicity from NSCH
#'
#' @param race4 NSCH race4_* variable (categorical, assuming 1=White NH, 2=Black, 3=Hispanic, 4=Other)
#'              This is based on NSCH using IPUMS-style race4 categories (2016-2023)
#' @return Character vector with categories: "White NH", "Black", "Hispanic", "Other"
harmonize_nsch_race <- function(race4) {
  dplyr::case_when(
    # Direct mapping (NSCH race4 already in desired 4-category format)
    race4 == 1 ~ "White NH",
    race4 == 2 ~ "Black",
    race4 == 3 ~ "Hispanic",
    race4 == 4 ~ "Other",
    # Missing/unknown
    TRUE ~ NA_character_
  )
}

#' Create Dummy-Coded Race/Ethnicity Variables
#'
#' @param race_harmonized Character vector of harmonized race categories
#' @return Data frame with 3 dummy variables (white_nh, black, hispanic)
#'         Note: "Other" is reference category (omitted)
create_race_dummies <- function(race_harmonized) {
  data.frame(
    white_nh = as.integer(race_harmonized == "White NH"),
    black = as.integer(race_harmonized == "Black"),
    hispanic = as.integer(race_harmonized == "Hispanic")
  )
}

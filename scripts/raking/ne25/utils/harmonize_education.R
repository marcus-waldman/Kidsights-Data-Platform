# Education Harmonization Utility
# Converts education variables across ACS, NHIS, and NSCH to years-of-schooling proxy (2-20)
# Uses Mincerian wage equation approach: years of education as continuous covariate

#' Convert ACS Education to Years of Schooling
#'
#' ACS EDUC_MOM variable (0-13) represents parent/householder education attainment.
#' This function converts to continuous years-of-schooling proxy for use in KL divergence weighting.
#'
#' @param EDUC_MOM ACS education variable (0=N/A, 1=Nursery-Grade 4, ..., 13=Doctorate)
#' @return Numeric vector with years of schooling (2-20) or NA for missing/not applicable
#'
#' @details
#' Mappings (midpoints for grouped categories):
#'  0 → NA (N/A)
#'  1 → 2 (Nursery-Grade 4: midpoint ~2)
#'  2 → 6.5 (Grade 5-8: midpoint 6.5)
#'  3 → 9 (Grade 9)
#'  4 → 10 (Grade 10)
#'  5 → 11 (Grade 11)
#'  6 → 11.5 (Grade 12 no diploma)
#'  7 → 12 (HS graduate/GED)
#'  8 → 13 (Some college, no degree)
#'  9 → 14 (Associate's degree)
#'  10 → 16 (Bachelor's degree)
#'  11 → 18 (Master's degree)
#'  12 → 18.5 (Professional degree beyond bachelor's)
#'  13 → 20 (Doctorate degree)
harmonize_acs_education <- function(EDUC_MOM) {
  dplyr::case_when(
    EDUC_MOM == 0 ~ NA_real_,          # N/A
    EDUC_MOM == 1 ~ 2,                 # Nursery-Grade 4
    EDUC_MOM == 2 ~ 6.5,               # Grade 5-8
    EDUC_MOM == 3 ~ 9,                 # Grade 9
    EDUC_MOM == 4 ~ 10,                # Grade 10
    EDUC_MOM == 5 ~ 11,                # Grade 11
    EDUC_MOM == 6 ~ 11.5,              # Grade 12 no diploma
    EDUC_MOM == 7 ~ 12,                # HS graduate/GED
    EDUC_MOM == 8 ~ 13,                # Some college
    EDUC_MOM == 9 ~ 14,                # Associate's degree
    EDUC_MOM == 10 ~ 16,               # Bachelor's degree
    EDUC_MOM == 11 ~ 18,               # Master's degree
    EDUC_MOM == 12 ~ 18.5,             # Professional degree
    EDUC_MOM == 13 ~ 20,               # Doctorate degree
    TRUE ~ NA_real_
  )
}

#' Convert NHIS Education to Years of Schooling
#'
#' NHIS EDUCPARENT variable (1-9) represents parental education attainment.
#' Note: NHIS collapses "Less than HS" into single category (unlike ACS 1-6 granularity).
#'
#' @param EDUCPARENT NHIS parental education variable
#'        (1=Less than HS, 2=HS/GED, 3=Some college, 4=Bachelor's, 5=Master's,
#'         6=Professional, 7=Doctorate, 8=Unknown, 9=Not in universe)
#' @return Numeric vector with years of schooling (10-20) or NA for missing
#'
#' @details
#' Mappings:
#'  1 → 10 (Less than HS: assigned midpoint 10)
#'  2 → 12 (HS graduate/GED)
#'  3 → 13 (Some college)
#'  4 → 16 (Bachelor's)
#'  5 → 18 (Master's)
#'  6 → 18.5 (Professional)
#'  7 → 20 (Doctorate)
#'  8, 9 → NA (Unknown/NIU)
harmonize_nhis_education <- function(EDUCPARENT) {
  dplyr::case_when(
    EDUCPARENT %in% c(8, 9) ~ NA_real_, # Unknown/Not in Universe
    EDUCPARENT == 1 ~ 10,               # Less than HS (midpoint)
    EDUCPARENT == 2 ~ 12,               # HS graduate/GED
    EDUCPARENT == 3 ~ 13,               # Some college
    EDUCPARENT == 4 ~ 16,               # Bachelor's
    EDUCPARENT == 5 ~ 18,               # Master's
    EDUCPARENT == 6 ~ 18.5,             # Professional beyond bachelor's
    EDUCPARENT == 7 ~ 20,               # Doctorate
    TRUE ~ NA_real_
  )
}

#' Convert NSCH Education to Years of Schooling
#'
#' NSCH education is typically provided as categorical variable (AdultEduc or similar).
#' This function converts categorical education to years-of-schooling proxy.
#'
#' @param educ_cat Character vector of education categories
#'        Expected: "Less than HS", "HS graduate", "Some college", "Associate's",
#'        "Bachelor's", "Master's", "Professional", "Doctorate"
#'        or numeric codes if using AdultEduc_* variables
#' @return Numeric vector with years of schooling (10-20) or NA for missing
#'
#' @details
#' Mappings match NHIS for consistency where possible:
#'  "Less than HS" → 10
#'  "HS graduate" → 12
#'  "Some college" → 13
#'  "Associate's" → 14
#'  "Bachelor's" → 16
#'  "Master's" → 18
#'  "Professional" → 18.5
#'  "Doctorate" → 20
harmonize_nsch_education <- function(educ_cat) {
  dplyr::case_when(
    educ_cat == "Less than HS" ~ 10,
    educ_cat == "HS graduate" ~ 12,
    educ_cat == "Some college" ~ 13,
    educ_cat == "Associate's" ~ 14,
    educ_cat == "Associate's degree" ~ 14,
    educ_cat == "Bachelor's" ~ 16,
    educ_cat == "Bachelor's degree" ~ 16,
    educ_cat == "Master's" ~ 18,
    educ_cat == "Master's degree" ~ 18,
    educ_cat == "Professional" ~ 18.5,
    educ_cat == "Professional school" ~ 18.5,
    educ_cat == "Doctorate" ~ 20,
    educ_cat == "Doctorate degree" ~ 20,
    TRUE ~ NA_real_
  )
}

#' Convert Numeric NSCH Education Code to Years
#'
#' Alternative function if NSCH uses numeric education codes (e.g., 1-8)
#' instead of character labels.
#'
#' @param educ_code Numeric vector (1=Less than HS, 2=HS, 3=Some college, etc.)
#' @return Numeric vector with years of schooling or NA
harmonize_nsch_education_numeric <- function(educ_code) {
  dplyr::case_when(
    educ_code == 1 ~ 10,    # Less than HS
    educ_code == 2 ~ 12,    # HS graduate
    educ_code == 3 ~ 13,    # Some college
    educ_code == 4 ~ 14,    # Associate's
    educ_code == 5 ~ 16,    # Bachelor's
    educ_code == 6 ~ 18,    # Master's
    educ_code == 7 ~ 18.5,  # Professional
    educ_code == 8 ~ 20,    # Doctorate
    TRUE ~ NA_real_
  )
}

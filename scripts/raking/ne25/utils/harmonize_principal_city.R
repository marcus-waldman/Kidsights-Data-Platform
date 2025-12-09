# ==============================================================================
# Principal City Harmonization Utility
# ==============================================================================
#
# Purpose: Create harmonized principal_city indicator across ACS, NHIS, NSCH
#
# Definitions:
#   - Principal city: Resides in the principal/central city of a metro area
#   - Coding: 1 = Yes (principal city), 0 = No (non-principal city/non-metro)
#
# Author: Claude Code
# Created: 2025-12-09
# ==============================================================================

#' Harmonize ACS METRO to principal_city indicator
#'
#' @param metro ACS METRO variable
#'   0 = Not in metro area
#'   1 = Not in principal city (metro, but not central city)
#'   2 = In principal city (central city of metro area)
#'   3 = Central city status indeterminable
#'   4 = Blank/Missing
#'
#' @return Binary indicator: 1 = principal city, 0 = not principal city
harmonize_acs_principal_city <- function(metro) {
  dplyr::case_when(
    metro == 2 ~ 1L,        # Principal city
    metro %in% c(0, 1, 3, 4) ~ 0L,  # Not in principal city (includes indeterminable/missing)
    TRUE ~ 0L
  )
}

#' Harmonize NHIS METRO to principal_city indicator
#'
#' @param metro NHIS METRO variable (character)
#'   "010" = MSA, principal city
#'   "020" = MSA, not principal city
#'   "030" = Not MSA
#'   "997" = Refused
#'   "998" = Not ascertained
#'   "999" = Don't know
#'
#' @return Binary indicator: 1 = principal city, 0 = not principal city, NA = missing
harmonize_nhis_principal_city <- function(metro) {
  dplyr::case_when(
    metro == "010" ~ 1L,     # Principal city
    metro %in% c("020", "030") ~ 0L,  # Not principal city (MSA non-central or non-MSA)
    metro %in% c("997", "998", "999") ~ NA_integer_,  # Missing
    TRUE ~ NA_integer_
  )
}

#' Harmonize NSCH MPC_YN to principal_city indicator
#'
#' @param mpc_yn NSCH MPC_YN variable (Metropolitan principal city - Yes/No)
#'   1 = Yes (in principal city)
#'   2 = No (not in principal city)
#'   96 = Missing
#'
#' @return Binary indicator: 1 = principal city, 0 = not principal city, NA = missing
harmonize_nsch_principal_city <- function(mpc_yn) {
  dplyr::case_when(
    mpc_yn == 1 ~ 1L,        # Principal city
    mpc_yn == 2 ~ 0L,        # Not in principal city
    mpc_yn == 96 ~ NA_integer_,  # Missing
    is.na(mpc_yn) ~ NA_integer_,
    TRUE ~ NA_integer_
  )
}

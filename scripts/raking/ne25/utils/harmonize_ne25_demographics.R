# ==============================================================================
# Harmonization Functions: NE25 Demographics to Unified Moment Structure
# ==============================================================================
#
# Purpose: Transform NE25 demographic variables to match unified moment structure
#          from pooled ACS/NHIS/NSCH data
#
# Variables harmonized:
#   1. male (binary) - from female (logical)
#   2. age (continuous, years) - direct mapping from years_old
#   3-5. white_nh, black, hispanic (binary dummies) - from raceG factor
#   6. educ_years (continuous, 2-20) - from educ_mom categorical
#   7. poverty_ratio (continuous, % FPL) - from fpl or income + family_size
#   8. principal_city (binary) - from cbsa (CBSA codes)
#
# ==============================================================================

# ==============================================================================
# Function 1: Harmonize Education (8 categories → continuous years)
# ==============================================================================

#' Harmonize NE25 Education to Continuous Years
#'
#' Maps 8 categorical education levels to continuous years on 2-20 scale
#' using midpoint conversion. Follows ACS/NHIS/NSCH harmonization pattern.
#'
#' @param educ_mom_factor Factor or character vector with education levels:
#'   "Less than HS", "HS graduate", "Some college", "Associate's",
#'   "Bachelor's", "Master's", "Professional", "Doctorate"
#'
#' @return Numeric vector with education years (2-20 scale), NA for missing
#'
#' @details
#' Mapping (using category midpoints):
#'   Less than HS → 10 years
#'   HS graduate → 12 years
#'   Some college → 13 years
#'   Associate's → 14 years
#'   Bachelor's → 16 years
#'   Master's → 18 years
#'   Professional → 18.5 years
#'   Doctorate → 20 years
#'
#' @examples
#' educ <- c("HS graduate", "Bachelor's", "Some college", NA)
#' harmonize_ne25_education(educ)
#'
harmonize_ne25_education <- function(educ_mom_factor) {

  # Ensure input is character for consistent matching
  educ_char <- as.character(educ_mom_factor)

  # Map education categories to continuous years
  # Handle both old labels (Less than HS) and new NE25 labels (8th grade or less)
  educ_years <- dplyr::case_when(
    # NE25 actual labels (from ne25_transformed)
    educ_char == "8th grade or less" ~ 8.0,
    educ_char == "9th-12th grade, No diploma" ~ 10.0,
    educ_char == "High School Graduate or GED Completed" ~ 12.0,
    educ_char == "Completed a vocational, trade, or business school program" ~ 13.0,
    educ_char == "Some College Credit, but No Degree" ~ 13.0,
    educ_char == "Associate Degree (AA, AS)" ~ 14.0,
    educ_char == "Bachelor's Degree (BA, BS, AB)" ~ 16.0,
    educ_char == "Master's Degree (MA, MS, MSW, MBA)" ~ 18.0,
    educ_char == "Doctorate (PhD, EdD) or Professional Degree (MD, DDS, DVM, JD)" ~ 20.0,
    # Legacy labels (for compatibility)
    educ_char == "Less than HS" ~ 10.0,
    educ_char == "HS graduate" ~ 12.0,
    educ_char == "Some college" ~ 13.0,
    educ_char == "Associate's" ~ 14.0,
    educ_char == "Bachelor's" ~ 16.0,
    educ_char == "Master's" ~ 18.0,
    educ_char == "Professional" ~ 18.5,
    educ_char == "Doctorate" ~ 20.0,
    TRUE ~ NA_real_
  )

  return(educ_years)
}

# ==============================================================================
# Function 2: Harmonize Race/Ethnicity to Binary Dummies
# ==============================================================================

#' Harmonize NE25 Race/Ethnicity to Binary Indicators
#'
#' Converts 7-category raceG factor to three mutually exclusive binary dummies:
#' white_nh, black, hispanic. Follows ACS/NHIS/NSCH pattern.
#'
#' @param raceG_factor Factor or character vector with race/ethnicity categories:
#'   "White NH", "Black NH", "Hispanic", "Asian NH", "Other NH",
#'   "Multiracial NH", "Unknown"
#'
#' @return Data frame with 3 columns (white_nh, black, hispanic), each binary (0/1)
#'
#' @details
#' Mapping logic:
#'   white_nh = (raceG == "White NH")
#'   black = (raceG == "Black NH")
#'   hispanic = (raceG == "Hispanic")
#'   All others (Asian, Multiracial, Other, Unknown) → 0 for all dummies
#'
#' Note: Mutually exclusive by design (raceG categories are exclusive)
#'
#' @examples
#' raceG <- c("White NH", "Hispanic", "Black NH", NA, "Other NH")
#' harmonize_ne25_race(raceG)
#'
harmonize_ne25_race <- function(raceG_factor) {

  # Ensure input is character
  raceG_char <- as.character(raceG_factor)

  # Create binary dummies
  # Handle both old labels (White NH) and NE25 actual labels (White, non-Hisp.)
  white_nh <- dplyr::case_when(
    raceG_char == "White, non-Hisp." ~ 1L,
    raceG_char == "White NH" ~ 1L,
    TRUE ~ 0L
  )

  black <- dplyr::case_when(
    raceG_char == "Black or African American, non-Hisp." ~ 1L,
    raceG_char == "Black NH" ~ 1L,
    TRUE ~ 0L
  )

  hispanic <- dplyr::case_when(
    raceG_char == "Hispanic" ~ 1L,
    TRUE ~ 0L
  )

  # Return as data frame with consistent naming
  dplyr::tibble(
    white_nh = white_nh,
    black = black,
    hispanic = hispanic
  )
}

# ==============================================================================
# Function 3: Harmonize Poverty to Continuous Ratio
# ==============================================================================

#' Harmonize NE25 Poverty Level to Continuous Ratio
#'
#' Handles poverty level harmonization with preference for observed FPL
#' over imputed values. Can recalculate from income + family_size if needed.
#'
#' @param fpl_observed Numeric vector with observed FPL (% of federal poverty line)
#'   Range: 0-999+, missing values as NA
#'
#' @param income_imputed Optional numeric vector with imputed income (dollars)
#'
#' @param family_size_imputed Optional integer vector with imputed family size
#'
#' @param consent_date Optional Date vector for year-specific FPL thresholds
#'   (currently ignored - uses unified threshold)
#'
#' @return Numeric vector with poverty_ratio (% FPL), NA for missing
#'
#' @details
#' Strategy:
#'   1. Use observed FPL if available (non-NA)
#'   2. If FPL missing, recalculate from income + family_size if both available
#'   3. If neither available, return NA
#'
#' For recalculation: poverty_ratio = (income / fpl_threshold(year, family_size))
#'
#' @examples
#' fpl <- c(150, 200, NA, 75)
#' harmonize_ne25_poverty(fpl)
#'
harmonize_ne25_poverty <- function(fpl_observed,
                                  income_imputed = NULL,
                                  family_size_imputed = NULL,
                                  consent_date = NULL) {

  # Preference: Use observed FPL if available
  poverty_ratio <- dplyr::case_when(
    !is.na(fpl_observed) ~ fpl_observed,
    TRUE ~ NA_real_
  )

  # Cap at NSCH standard range: 50-400% FPL
  # This matches NSCH's poverty_ratio range for consistency in unified moments
  poverty_ratio <- pmin(pmax(poverty_ratio, 50, na.rm = FALSE), 400, na.rm = FALSE)

  # If FPL missing but income + family_size available, could recalculate
  # (This is optional - currently we rely on observed FPL)
  #
  # if (!is.null(income_imputed) && !is.null(family_size_imputed)) {
  #   missing_mask <- is.na(poverty_ratio)
  #   if (any(missing_mask)) {
  #     # Recalculation logic would go here
  #     # For now, leave as NA
  #   }
  # }

  return(poverty_ratio)
}

# ==============================================================================
# Function 4: Harmonize Principal City from CBSA Codes
# ==============================================================================

#' Harmonize NE25 Principal City from CBSA Codes
#'
#' Maps Core Based Statistical Area (CBSA) codes to binary principal_city indicator.
#' Uses CBSA codes for Omaha (36540) and Lincoln (30700) metropolitan areas.
#'
#' @param cbsa Character or numeric vector with CBSA codes
#'   May contain semicolon-separated values (ambiguous cases from base data)
#'   Examples: "36540", "30700", "36540; 99999", NA
#'
#' @return Integer vector with principal_city (1 = principal city, 0 = not)
#'
#' @details
#' Mapping:
#'   CBSA 36540 (Omaha metro) → principal_city = 1
#'   CBSA 30700 (Lincoln metro) → principal_city = 1
#'   All other CBSA codes or missing → principal_city = 0
#'
#' For ambiguous cases (e.g., "36540; 99999"), extracts primary CBSA
#' (first code before semicolon) and checks against principal city list.
#'
#' Nebraska principal city CBSAs:
#'   36540 = Omaha-Council Bluffs, NE-IA (Douglas/Sarpy counties)
#'   30700 = Lincoln, NE (Lancaster County)
#'
#' @examples
#' cbsa <- c("36540", "30700", "99999", "36540; 99999", NA)
#' harmonize_ne25_principal_city(cbsa)
#'
harmonize_ne25_principal_city <- function(cbsa) {

  # Convert to character for consistent handling
  cbsa_char <- as.character(cbsa)

  # Extract primary CBSA code (before semicolon if present)
  cbsa_primary <- stringr::str_extract(cbsa_char, "^\\d+")

  # Map to principal_city binary
  principal_city <- dplyr::case_when(
    cbsa_primary == "36540" ~ 1L,  # Omaha metro
    cbsa_primary == "30700" ~ 1L,  # Lincoln metro
    TRUE ~ 0L                      # All others (including NA, non-metro)
  )

  return(principal_city)
}

# ==============================================================================
# Wrapper Function: Harmonize All Block 1 Demographics at Once
# ==============================================================================

#' Harmonize All NE25 Block 1 Demographics
#'
#' Convenience wrapper that applies all harmonization functions to create
#' 8 Block 1 demographic variables in one call.
#'
#' @param data Data frame with NE25 variables:
#'   female, years_old, raceG, educ_mom, fpl, cbsa
#'
#' @return Data frame with 8 harmonized variables:
#'   male, age, white_nh, black, hispanic, educ_years, poverty_ratio, principal_city
#'
#' @examples
#' harmonized_block1 <- harmonize_ne25_block1(ne25_data)
#'
harmonize_ne25_block1 <- function(data) {

  # Validate required columns
  required_cols <- c("female", "years_old", "raceG", "educ_mom", "fpl", "cbsa")
  missing_cols <- required_cols[!(required_cols %in% names(data))]

  if (length(missing_cols) > 0) {
    stop(sprintf("Missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))
  }

  # Create harmonized variables
  harmonized <- dplyr::tibble(
    # Variable 1: male (invert female)
    male = as.integer(!data$female),

    # Variable 2: age (direct mapping)
    age = data$years_old,

    # Variables 3-5: race dummies (from raceG)
    !!!harmonize_ne25_race(data$raceG),

    # Variable 6: education years (from educ_mom)
    educ_years = harmonize_ne25_education(data$educ_mom),

    # Variable 7: poverty ratio (from fpl)
    poverty_ratio = harmonize_ne25_poverty(data$fpl),

    # Variable 8: principal city (from cbsa)
    principal_city = harmonize_ne25_principal_city(data$cbsa)
  )

  return(harmonized)
}

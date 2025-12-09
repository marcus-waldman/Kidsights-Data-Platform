# ==============================================================================
# Utility: harmonize_puma.R
# Purpose: Harmonize PUMA (Public Use Microdata Area) codes to binary dummies
#
# Overview:
#   - Extract first PUMA from semicolon-delimited strings (NE25 format)
#   - Convert zero-padded strings ("00100") to numeric codes (100) for matching ACS
#   - Create 14 binary dummy variables (one per Nebraska PUMA)
#   - Handle missing values (NA propagates to all dummies)
#
# Function: harmonize_puma(puma_vector)
#   Input: Vector of PUMA codes (numeric from ACS or character from NE25)
#   Output: Tibble with 14 binary columns (puma_100, puma_200, ..., puma_904)
#
# ==============================================================================

harmonize_puma <- function(puma_vector) {
  # List of all Nebraska PUMA codes
  puma_codes <- c(100, 200, 300, 400, 500, 600, 701, 702, 801, 802, 901, 902, 903, 904)

  # Handle input: if character (from NE25), convert to numeric
  puma_numeric <- puma_vector

  # If input is character (from NE25 preprocessing)
  if (is.character(puma_numeric)) {
    puma_numeric <- as.integer(puma_numeric)
  }

  # Create a list to hold all columns
  col_list <- list()

  for (code in puma_codes) {
    col_name <- sprintf("puma_%d", code)
    # Create binary indicator: 1 if matches PUMA code, 0 otherwise, NA if input is NA
    dummy <- as.integer(puma_numeric == code)
    # Propagate NA values: if input was NA, set dummy to NA
    dummy[is.na(puma_numeric)] <- NA_integer_
    col_list[[col_name]] <- dummy
  }

  # Convert list to tibble
  result <- dplyr::as_tibble(col_list)

  return(result)
}

# Missing Value Recoding Utility
# Converts sentinel missing value codes to NA before transformations.
# Extracted from R/transform/ne25_transforms.R — study-agnostic.
#
# Common missing codes: 99 (Prefer not to answer), 9 (Don't know),
# -99, 999, -999, 9999, -9999

recode_missing <- function(x, missing_codes = c(99, -99, 999, -999, 9999, -9999, 9)) {
  if (is.null(x) || length(x) == 0) {
    return(x)
  }

  # Convert character representation of numbers to numeric
  if (is.character(x)) {
    x_numeric <- suppressWarnings(as.numeric(x))
    if (!all(is.na(x_numeric[!is.na(x)]))) {
      x <- x_numeric
    }
  }

  x[x %in% missing_codes] <- NA
  return(x)
}

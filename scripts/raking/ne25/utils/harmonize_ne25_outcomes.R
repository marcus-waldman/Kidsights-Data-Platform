# ==============================================================================
# Harmonization Functions: NE25 Outcomes to Unified Moment Structure
# ==============================================================================
#
# Purpose: Transform NE25 mental health and child outcome variables to match
#          unified moment structure from NHIS/NSCH data
#
# Variables harmonized:
#   Block 2 (Mental Health - NHIS pattern, ~55% missingness expected):
#     9. phq2_total (0-6) - from observed total or sum of imputed items
#     10. gad2_total (0-6) - from observed total or sum of imputed items
#
#   Block 3 (Child Outcomes - NSCH pattern, ~15% missingness expected):
#     11. child_ace_1 (binary) - child_ace_total == 1
#     12. child_ace_2plus (binary) - child_ace_total >= 2
#     13. excellent_health (binary) - mmi100 == 0 (excellent)
#
# ==============================================================================

# ==============================================================================
# Function 1: Harmonize Mental Health (PHQ-2 & GAD-2 Totals)
# ==============================================================================

#' Harmonize NE25 Mental Health Scores
#'
#' Creates PHQ-2 and GAD-2 total scores with preference for observed totals
#' over sum of imputed items. Returns both scores in a data frame.
#'
#' @param phq2_total_observed Optional numeric vector with observed PHQ-2 total (0-6)
#'
#' @param phq2_interest_imputed Optional numeric vector with imputed PHQ-2 interest item (0-3)
#'
#' @param phq2_depressed_imputed Optional numeric vector with imputed PHQ-2 depressed item (0-3)
#'
#' @param gad2_total_observed Optional numeric vector with observed GAD-2 total (0-6)
#'
#' @param gad2_nervous_imputed Optional numeric vector with imputed GAD-2 nervous item (0-3)
#'
#' @param gad2_worry_imputed Optional numeric vector with imputed GAD-2 worry item (0-3)
#'
#' @return Data frame with 2 columns:
#'   phq2_total (integer, 0-6 or NA)
#'   gad2_total (integer, 0-6 or NA)
#'
#' @details
#' PHQ-2 scoring:
#'   - Observed total: Use directly if available
#'   - Imputed items: Sum of 2 items (interest + depressed), each 0-3
#'   - Missing: Return NA
#'
#' GAD-2 scoring:
#'   - Observed total: Use directly if available
#'   - Imputed items: Sum of 2 items (nervous + worry), each 0-3
#'   - Missing: Return NA
#'
#' Expected missingness: ~55% (matches NHIS pattern where mental health
#' questions only asked in 2019, 2022 NHIS years, and NE25 may have sparse coverage)
#'
#' @examples
#' phq2_scores <- harmonize_ne25_mental_health(
#'   phq2_total_observed = c(NA, 4, NA),
#'   phq2_interest_imputed = c(1, NA, 2),
#'   phq2_depressed_imputed = c(1, NA, 1),
#'   gad2_total_observed = c(3, NA, NA),
#'   gad2_nervous_imputed = c(NA, 2, 0),
#'   gad2_worry_imputed = c(NA, 1, 0)
#' )
#'
harmonize_ne25_mental_health <- function(phq2_total_observed = NULL,
                                         phq2_interest_imputed = NULL,
                                         phq2_depressed_imputed = NULL,
                                         gad2_total_observed = NULL,
                                         gad2_nervous_imputed = NULL,
                                         gad2_worry_imputed = NULL) {

  # Determine length of result vector from first non-NULL argument
  n <- max(
    if (!is.null(phq2_total_observed)) length(phq2_total_observed) else 0,
    if (!is.null(phq2_interest_imputed)) length(phq2_interest_imputed) else 0,
    if (!is.null(phq2_depressed_imputed)) length(phq2_depressed_imputed) else 0,
    if (!is.null(gad2_total_observed)) length(gad2_total_observed) else 0,
    if (!is.null(gad2_nervous_imputed)) length(gad2_nervous_imputed) else 0,
    if (!is.null(gad2_worry_imputed)) length(gad2_worry_imputed) else 0
  )

  # Initialize to NULL (will be filled with provided values)
  phq2 <- NULL
  gad2 <- NULL

  # PHQ-2 total: prefer observed, fallback to sum of imputed items
  if (!is.null(phq2_total_observed)) {
    phq2 <- phq2_total_observed
  } else if (!is.null(phq2_interest_imputed) && !is.null(phq2_depressed_imputed)) {
    phq2 <- phq2_interest_imputed + phq2_depressed_imputed
  } else {
    phq2 <- rep(NA_integer_, n)
  }

  # GAD-2 total: prefer observed, fallback to sum of imputed items
  if (!is.null(gad2_total_observed)) {
    gad2 <- gad2_total_observed
  } else if (!is.null(gad2_nervous_imputed) && !is.null(gad2_worry_imputed)) {
    gad2 <- gad2_nervous_imputed + gad2_worry_imputed
  } else {
    gad2 <- rep(NA_integer_, n)
  }

  # Ensure numeric type and convert to integer
  phq2 <- as.integer(phq2)
  gad2 <- as.integer(gad2)

  # Return as data frame
  dplyr::tibble(
    phq2_total = phq2,
    gad2_total = gad2
  )
}

# ==============================================================================
# Function 2: Harmonize Child ACE Total to Binary Categories
# ==============================================================================

#' Harmonize Child ACE Total to Binary Categories
#'
#' Converts continuous child_ace_total (0-8) to two mutually exclusive binary
#' categories: 1 ACE vs 2+ ACEs. Matches unified moment structure.
#'
#' @param child_ace_total Integer vector with child ACE total (0-8)
#'   0 = no ACEs, 1 = 1 ACE, 2-8 = 2+ ACEs
#'
#' @return Data frame with 2 columns:
#'   child_ace_1 (integer, 0/1) - binary indicator for exactly 1 ACE
#'   child_ace_2plus (integer, 0/1) - binary indicator for 2+ ACEs
#'   (mutually exclusive by design)
#'
#' @details
#' Mapping:
#'   child_ace_1 = (child_ace_total == 1)
#'   child_ace_2plus = (child_ace_total >= 2)
#'   0 ACEs → both variables = 0
#'   Missing child_ace_total → both variables = NA
#'
#' Note: This transformation loses granularity (cannot distinguish 2 vs 3 vs 4+ ACEs)
#' but matches the unified moment structure created from NSCH data.
#'
#' Expected missingness: ~15% (children without complete ACE data)
#'
#' @examples
#' child_aces <- c(0, 1, 2, 5, NA)
#' harmonize_ne25_child_aces(child_aces)
#'
harmonize_ne25_child_aces <- function(child_ace_total) {

  # Create binary categories
  child_ace_1 <- dplyr::case_when(
    child_ace_total == 1 ~ 1L,
    TRUE ~ 0L
  )

  child_ace_2plus <- dplyr::case_when(
    child_ace_total >= 2 ~ 1L,
    TRUE ~ 0L
  )

  # Handle missing values: set both to NA if original is NA
  na_mask <- is.na(child_ace_total)
  child_ace_1[na_mask] <- NA_integer_
  child_ace_2plus[na_mask] <- NA_integer_

  # Return as data frame
  dplyr::tibble(
    child_ace_1 = child_ace_1,
    child_ace_2plus = child_ace_2plus
  )
}

# ==============================================================================
# Function 3: Harmonize Health Status to Excellent/Not Excellent
# ==============================================================================

#' Harmonize NE25 Child Health Status to Binary Excellent Indicator
#'
#' Converts 5-point child health rating (mmi100) to binary excellent_health indicator
#' where 1 = excellent health, 0 = very good/good/fair/poor
#'
#' @param mmi100 Integer vector with child MMI health status (0-4):
#'   0 = Excellent
#'   1 = Very Good
#'   2 = Good
#'   3 = Fair
#'   4 = Poor
#'   NA = Missing
#'
#' @return Integer vector with excellent_health (1/0 or NA)
#'
#' @details
#' Simple binary transformation:
#'   mmi100 == 0 (Excellent) → excellent_health = 1
#'   mmi100 %in% 1:4 (all others) → excellent_health = 0
#'   NA → NA
#'
#' Expected missingness: Very low (~<2%), most children have health rating
#'
#' @examples
#' health <- c(0, 1, 2, 3, 4, NA)
#' harmonize_ne25_excellent_health(health)
#'
harmonize_ne25_excellent_health <- function(mmi100) {

  # Convert to binary excellent indicator
  excellent_health <- dplyr::case_when(
    mmi100 == 0 ~ 1L,         # Excellent
    mmi100 %in% 1:4 ~ 0L,     # Very Good, Good, Fair, Poor
    TRUE ~ NA_integer_        # Missing
  )

  return(excellent_health)
}

# ==============================================================================
# Wrapper Function: Harmonize All Block 2 & Block 3 Outcomes at Once
# ==============================================================================

#' Harmonize All NE25 Blocks 2-3 Outcomes
#'
#' Convenience wrapper that applies all outcome harmonization functions
#' to create 5 outcome variables (2 mental health + 3 child outcomes).
#'
#' @param data Data frame with NE25 outcome variables:
#'   - Block 2: phq2_total (obs), phq2_interest (imp), phq2_depressed (imp),
#'              gad2_total (obs), gad2_nervous (imp), gad2_worry (imp)
#'   - Block 3: child_ace_total, mmi100
#'
#' @return Data frame with 5 harmonized variables:
#'   phq2_total, gad2_total, child_ace_1, child_ace_2plus, excellent_health
#'
#' @examples
#' harmonized_outcomes <- harmonize_ne25_outcomes(ne25_data)
#'
harmonize_ne25_outcomes <- function(data) {

  # Block 2: Mental health (flexible - can accept various combinations of columns)
  block2 <- dplyr::tibble(
    phq2_total = NA_integer_,
    gad2_total = NA_integer_
  )

  # Try to create PHQ-2 from observed or imputed
  if (!is.null(data$phq2_total)) {
    block2$phq2_total <- as.integer(data$phq2_total)
  } else if (!is.null(data$phq2_interest) && !is.null(data$phq2_depressed)) {
    block2$phq2_total <- data$phq2_interest + data$phq2_depressed
  }

  # Try to create GAD-2 from observed or imputed
  if (!is.null(data$gad2_total)) {
    block2$gad2_total <- as.integer(data$gad2_total)
  } else if (!is.null(data$gad2_nervous) && !is.null(data$gad2_worry)) {
    block2$gad2_total <- data$gad2_nervous + data$gad2_worry
  }

  # Block 3: Child outcomes
  block3 <- dplyr::tibble()

  # Child ACEs
  if (!is.null(data$child_ace_total)) {
    block3 <- dplyr::bind_cols(
      block3,
      harmonize_ne25_child_aces(data$child_ace_total)
    )
  }

  # Health status
  if (!is.null(data$mmi100)) {
    block3 <- dplyr::bind_cols(
      block3,
      dplyr::tibble(excellent_health = harmonize_ne25_excellent_health(data$mmi100))
    )
  }

  # Combine blocks
  dplyr::bind_cols(block2, block3)
}

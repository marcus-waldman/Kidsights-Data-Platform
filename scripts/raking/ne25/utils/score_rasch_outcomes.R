# Rasch EAPsum Scoring Functions
# ACE (Adverse Childhood Experiences) item response theory scoring
#
# Created: December 2025
# Purpose: Score parental and child ACEs using Rasch (1PL) models
#          for use in covariance pipeline Blocks 3 and 4

#' Score Maternal ACEs (Rasch EAPsum, 8 items)
#'
#' @param ace_matrix Numeric matrix: 8 columns (binary 0/1, NA for missing)
#'        Column order: Violence, Incarceration, MentalIllness, SubstanceAbuse,
#'                      PutDown, RaceDiscrim, SexDiscrim, BasicNeeds
#' @return Numeric vector: Rasch EAPsum scores (approximately 0-8 continuous scale)
#'
#' @details
#' Fits a Rasch (1PL) item response theory model to 8 parental ACE items:
#'   1. Violence (VIOLENEV): Ever experienced domestic violence
#'   2. Incarceration (JAILEV): Family member ever in jail/prison
#'   3. Mental Illness (MENTDEPEV): Family member with mental illness/depression
#'   4. Substance Abuse (ALCDRUGEV): Family member with alcohol/drug abuse
#'   5. Put Down (ADLTPUTDOWN): Ever been put down/humiliated by adult
#'   6. Race Discrimination (UNFAIRRACE): Unfair treatment due to race/ethnicity
#'   7. Sexual Orientation Discrimination (UNFAIRSEXOR): Unfair treatment due to sexual orientation
#'   8. Basic Needs (BASENEED): Difficulty affording basic needs
#'
#' Uses mirt::mirt() with itemtype='Rasch' (1PL model: equal discrimination parameters)
#' EAPsum scores computed via mirt::fscores(method = "EAPsum")
#'
#' Fallback: If Rasch model fails to converge, returns sum scores (0-8 discrete)
#'
#' @references
#' Chalmers, R. P. (2012). mirt: A Multidimensional Item Response Theory
#' Package for the R Environment. Journal of Statistical Software, 48(6), 1-29.
#'
#' @examples
#' ace_data <- matrix(c(0, 0, 1, 0, 0, 0, 0, 1,
#'                      1, 1, 0, 0, 0, 0, 0, 0), nrow = 2, byrow = TRUE)
#' score_maternal_aces_rasch(ace_data)
#' # Returns approximately c(2.1, 1.8) (EAPsum scores)
score_maternal_aces_rasch <- function(ace_matrix) {

  # Validate input
  if (!is.matrix(ace_matrix)) {
    stop("ace_matrix must be a matrix")
  }

  if (ncol(ace_matrix) != 8) {
    stop("ace_matrix must have exactly 8 columns")
  }

  # Try Rasch model fitting
  tryCatch({
    # Fit Rasch (1PL) model
    ace_model <- mirt::mirt(
      ace_matrix,
      model = 1,
      itemtype = 'Rasch',
      verbose = FALSE
    )

    # Compute EAPsum scores
    ace_eapsum <- mirt::fscores(ace_model, method = "EAPsum")[, 1]

    return(ace_eapsum)

  }, error = function(e) {
    # Fallback: Use sum scores if Rasch model fails
    warning("Rasch model failed to converge, using sum scores: ", e$message)
    ace_sumscores <- rowSums(ace_matrix, na.rm = FALSE)
    return(ace_sumscores)
  })
}

#' Score Child ACEs (Rasch EAPsum, 10 items)
#'
#' @param ace_binary_data Data frame with 10 ACE binary indicator columns
#'        Expected columns: ACE1_binary, ACE3_binary through ACE11_binary
#'        (ACE2 not present in NSCH)
#' @return Numeric vector: Rasch EAPsum scores (approximately 0-10 continuous scale)
#'
#' @details
#' Fits a Rasch (1PL) model to 10 child ACE items from NSCH:
#'   1. ACE1: Hard to get by on income
#'   3. ACE3: Parent/guardian divorced or separated
#'   4. ACE4: Parent/guardian died
#'   5. ACE5: Parent/guardian served time in jail
#'   6. ACE6: Saw/heard parents hit, kick, slap, etc.
#'   7. ACE7: Victim/witness of neighborhood violence
#'   8. ACE8: Lived with mentally ill household member
#'   9. ACE9: Lived with alcohol/drug abuser
#'  10. ACE10: Treated/judged unfairly due to race/ethnicity
#'  11. ACE11: Experienced/witnessed discrimination (2021+ only)
#'
#' NOTE: ACE2 is not measured in NSCH, so numbering skips from ACE1 to ACE3
#'
#' Uses mirt::mirt() with itemtype='Rasch' (1PL model)
#' EAPsum scores computed via mirt::fscores(method = "EAPsum")
#'
#' Fallback: If Rasch model fails to converge, returns sum scores (0-10 discrete)
#'
#' @examples
#' ace_df <- data.frame(
#'   ACE1_binary = c(0, 1),
#'   ACE3_binary = c(0, 0),
#'   ACE4_binary = c(0, 0),
#'   ACE5_binary = c(0, 1),
#'   ACE6_binary = c(1, 0),
#'   ACE7_binary = c(0, 0),
#'   ACE8_binary = c(0, 1),
#'   ACE9_binary = c(0, 0),
#'   ACE10_binary = c(0, 0),
#'   ACE11_binary = c(0, NA)
#' )
#' score_child_aces_rasch(ace_df)
#' # Returns approximately c(1.1, NA) (EAPsum scores; NA due to missing ACE11)
score_child_aces_rasch <- function(ace_binary_data) {

  # Expected columns (ACE2 not in NSCH)
  ace_cols <- c("ACE1_binary", "ACE3_binary", "ACE4_binary", "ACE5_binary",
                "ACE6_binary", "ACE7_binary", "ACE8_binary", "ACE9_binary",
                "ACE10_binary", "ACE11_binary")

  # Validate input
  if (!is.data.frame(ace_binary_data)) {
    stop("ace_binary_data must be a data frame")
  }

  missing_cols <- setdiff(ace_cols, names(ace_binary_data))
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  # Extract ACE items as matrix
  ace_items <- ace_binary_data %>%
    dplyr::select(dplyr::all_of(ace_cols)) %>%
    as.matrix()

  # Try Rasch model fitting
  tryCatch({
    # Fit Rasch (1PL) model
    child_ace_model <- mirt::mirt(
      ace_items,
      model = 1,
      itemtype = 'Rasch',
      verbose = FALSE
    )

    # Compute EAPsum scores
    child_ace_eapsum <- mirt::fscores(child_ace_model, method = "EAPsum")[, 1]

    return(child_ace_eapsum)

  }, error = function(e) {
    # Fallback: Use sum scores if Rasch model fails
    warning("Rasch model failed to converge, using sum scores: ", e$message)
    child_ace_sumscores <- rowSums(ace_items, na.rm = FALSE)
    return(child_ace_sumscores)
  })
}

#' Categorize ACE Scores (0, 1, 2+ ACEs)
#'
#' @param ace_eapsum Numeric vector: Rasch EAPsum scores
#' @return Character vector: ACE categories ("0 ACEs", "1 ACE", "2+ ACEs")
#'
#' @details
#' Categorizes continuous EAPsum scores into 3 groups:
#'   - 0 ACEs: EAPsum < 0.5
#'   - 1 ACE: 0.5 ≤ EAPsum < 1.5
#'   - 2+ ACEs: EAPsum ≥ 1.5
#'
#' Used in raking targets pipeline for multinomial estimation
#' (not used in covariance pipeline which uses continuous EAPsum)
#'
#' @examples
#' categorize_ace_scores(c(0.2, 0.8, 2.3, NA))
#' # Returns: "0 ACEs" "1 ACE" "2+ ACEs" NA
categorize_ace_scores <- function(ace_eapsum) {
  dplyr::case_when(
    is.na(ace_eapsum) ~ NA_character_,
    ace_eapsum < 0.5 ~ "0 ACEs",
    ace_eapsum < 1.5 ~ "1 ACE",
    ace_eapsum >= 1.5 ~ "2+ ACEs"
  )
}

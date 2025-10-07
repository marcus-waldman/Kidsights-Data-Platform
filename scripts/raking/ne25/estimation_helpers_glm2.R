# Raking Targets Estimation - Helper Functions (glm2 Version)
# Purpose: Reusable functions for computing population estimates using glm2
# Author: Kidsights Data Platform
# Date: January 2025
# Refactored from: estimation_helpers.R (survey package version)

library(glm2)
library(nnet)
library(dplyr)

# Source centralized configuration
source("config/bootstrap_config.R")

# ============================================================================
# Function 1: Binary GLM Estimation with glm2
# ============================================================================

#' Fit binary GLM with age x year interaction using glm2
#'
#' @param data Data frame with outcome, predictors, and weights
#' @param formula Formula for binary outcome (e.g., I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR)
#' @param weights_col Name of column containing weights (character string)
#' @param predict_year Year to predict for (default: 2023)
#' @param ages Ages to predict for (default: 0:5)
#' @return Data frame with age and predicted probability
#'
#' @examples
#' result <- fit_glm2_estimates(
#'   data = acs_data,
#'   formula = I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
#'   weights_col = "PERWT",
#'   predict_year = 2023,
#'   ages = 0:5
#' )
fit_glm2_estimates <- function(data, formula, weights_col,
                                predict_year = 2023, ages = 0:5) {

  # Extract weights from data
  if (!weights_col %in% names(data)) {
    stop("Weight column '", weights_col, "' not found in data")
  }

  # Get weight vector explicitly
  # Note: We add weights as a column to avoid scoping issues with glm2
  data_with_wts <- data
  data_with_wts$.fit_weights <- data[[weights_col]]

  # Fit binary logistic regression using glm2
  model <- glm2::glm2(
    formula = formula,
    data = data_with_wts,
    weights = .fit_weights,
    family = binomial()
  )

  # Create prediction data matching the types in original data
  newdata <- data.frame(AGE = as.numeric(ages))

  # Add MULTYEAR with matching type
  if ("MULTYEAR" %in% all.vars(formula)) {
    if (is.factor(data$MULTYEAR)) {
      newdata$MULTYEAR <- factor(predict_year, levels = levels(data$MULTYEAR))
    } else {
      newdata$MULTYEAR <- as.numeric(predict_year)
    }
  }

  # Get predictions
  predictions <- predict(model, newdata = newdata, type = "response")

  # Return results
  result <- data.frame(
    age = ages,
    estimate = as.numeric(predictions)
  )

  return(result)
}

# ============================================================================
# Function 2: Multinomial Logistic Regression Estimation
# ============================================================================

#' Fit multinomial logistic regression using nnet::multinom
#'
#' @param data Data frame with categorical outcome, predictors, and weights
#' @param formula Formula for multinomial outcome (e.g., fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR)
#' @param weights_col Name of column containing weights (character string)
#' @param predict_year Year to predict for (default: 2023)
#' @param ages Ages to predict for (default: 0:5)
#' @return Data frame with age, category, and predicted probability (sums to 1.0 within age)
#'
#' @examples
#' # FPL example
#' result <- fit_multinom_estimates(
#'   data = acs_data,
#'   formula = fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
#'   weights_col = "PERWT",
#'   predict_year = 2023,
#'   ages = 0:5
#' )
fit_multinom_estimates <- function(data, formula, weights_col,
                                   predict_year = 2023, ages = 0:5) {

  # Extract weights from data
  if (!weights_col %in% names(data)) {
    stop("Weight column '", weights_col, "' not found in data")
  }

  # Get weight vector explicitly
  # Note: We add weights as a column to avoid scoping issues
  data_with_wts <- data
  data_with_wts$.fit_weights <- data[[weights_col]]

  # Fit multinomial logistic regression
  model <- nnet::multinom(
    formula = formula,
    data = data_with_wts,
    weights = .fit_weights,
    trace = FALSE  # Suppress iteration output
  )

  # Create prediction data
  newdata <- data.frame(AGE = as.numeric(ages))

  # Add MULTYEAR if in formula
  if ("MULTYEAR" %in% all.vars(formula)) {
    if (is.factor(data$MULTYEAR)) {
      newdata$MULTYEAR <- factor(predict_year, levels = levels(data$MULTYEAR))
    } else {
      newdata$MULTYEAR <- as.numeric(predict_year)
    }
  }

  # Get predicted probabilities
  # multinom returns matrix (n_ages x n_categories) or vector if 2 categories
  predictions <- predict(model, newdata = newdata, type = "probs")

  # Handle case where predictions is a vector (2 categories only)
  if (is.vector(predictions)) {
    # For 2 categories, multinom returns vector of probabilities for second category
    # Need to construct full matrix
    predictions <- cbind(1 - predictions, predictions)
    colnames(predictions) <- model$lev
  }

  # Get category names
  categories <- colnames(predictions)

  # Create long-format result
  result <- data.frame(
    age = rep(ages, each = length(categories)),
    category = rep(categories, times = length(ages)),
    estimate = as.vector(t(predictions))  # Transpose to get (age1_cat1, age1_cat2, ..., age2_cat1, ...)
  )

  return(result)
}

# ============================================================================
# Function 3: Validation Functions
# ============================================================================

#' Validate binary proportion estimates
#'
#' @param estimates Data frame with 'estimate' column
#' @param estimand_name Name of estimand for messages
#' @return Logical indicating if validation passed
validate_binary_estimates <- function(estimates, estimand_name = "Unknown") {

  cat("\n[VALIDATE]", estimand_name, "\n")

  valid <- TRUE

  # Check 1: All estimates between 0 and 1
  if (any(estimates$estimate < 0 | estimates$estimate > 1, na.rm = TRUE)) {
    cat("  [FAIL] Estimates outside [0, 1] range\n")
    valid <- FALSE
  } else {
    cat("  [OK] All estimates in [0, 1] range\n")
  }

  # Check 2: No missing values
  if (any(is.na(estimates$estimate))) {
    cat("  [WARN] Missing values present:", sum(is.na(estimates$estimate)), "rows\n")
  } else {
    cat("  [OK] No missing values\n")
  }

  # Check 3: Reasonable variation (if estimates should vary by age)
  if (nrow(estimates) > 1) {
    range_val <- max(estimates$estimate, na.rm = TRUE) - min(estimates$estimate, na.rm = TRUE)
    cat("  [INFO] Range of estimates:", round(range_val, 4), "\n")
  }

  return(valid)
}

#' Validate multinomial estimates (should sum to 1 within each age)
#'
#' @param estimates Data frame with 'age', 'category', 'estimate' columns
#' @param estimand_name Name of estimand for messages
#' @return Logical indicating if validation passed
validate_multinomial_estimates <- function(estimates, estimand_name = "Unknown") {

  cat("\n[VALIDATE]", estimand_name, "\n")

  valid <- TRUE

  # Check 1: Sum to 1 within each age
  sums_by_age <- estimates %>%
    dplyr::group_by(age) %>%
    dplyr::summarise(total = sum(estimate, na.rm = TRUE), .groups = "drop")

  if (any(abs(sums_by_age$total - 1.0) > 0.001, na.rm = TRUE)) {
    cat("  [FAIL] Probabilities don't sum to 1.0 within ages\n")
    print(sums_by_age)
    valid <- FALSE
  } else {
    cat("  [OK] Probabilities sum to 1.0 within each age\n")
  }

  # Check 2: All estimates between 0 and 1
  if (any(estimates$estimate < 0 | estimates$estimate > 1, na.rm = TRUE)) {
    cat("  [FAIL] Estimates outside [0, 1] range\n")
    valid <- FALSE
  } else {
    cat("  [OK] All estimates in [0, 1] range\n")
  }

  # Check 3: No missing values
  if (any(is.na(estimates$estimate))) {
    cat("  [WARN] Missing values present:", sum(is.na(estimates$estimate)), "rows\n")
  } else {
    cat("  [OK] No missing values\n")
  }

  return(valid)
}

# ============================================================================
# Function 4: Missing Data Filter (CRITICAL for IPUMS data)
# ============================================================================

#' Apply defensive missing data filters for IPUMS ACS variables
#'
#' @param data Data frame with IPUMS variables
#' @param for_children Logical - if TRUE, skip EDUC/MARST filters (default TRUE)
#' @return Filtered data frame with missing codes removed
filter_acs_missing <- function(data, for_children = TRUE) {

  data_clean <- data
  n_original <- nrow(data)

  # SEX: Remove 9 (Missing)
  if ("SEX" %in% names(data)) {
    data_clean <- data_clean %>% dplyr::filter(SEX %in% c(1, 2))
  }

  # HISPAN: Remove 9 (Not Reported), keep 0-4
  if ("HISPAN" %in% names(data)) {
    data_clean <- data_clean %>% dplyr::filter(HISPAN %in% 0:4)
  }

  # RACE: Remove missing codes
  if ("RACE" %in% names(data)) {
    data_clean <- data_clean %>%
      dplyr::filter(RACE %in% 1:9, !(RACE %in% c(363, 380, 996, 997)))
  }

  # POVERTY: Keep 0-501 (0 may mean N/A for children, which is valid)
  if ("POVERTY" %in% names(data)) {
    data_clean <- data_clean %>% dplyr::filter(POVERTY >= 0 & POVERTY <= 501)
  }

  # EDUC/MARST: Only filter for adults (skip for children)
  if (!for_children) {
    # EDUC: Remove 999 (Missing), 001 (N/A), 000 (N/A)
    if ("EDUC" %in% names(data)) {
      data_clean <- data_clean %>% dplyr::filter(EDUC >= 2 & EDUC <= 998)
    }

    # MARST: Remove 9 (Blank/missing)
    if ("MARST" %in% names(data)) {
      data_clean <- data_clean %>% dplyr::filter(MARST %in% 1:6)
    }
  }

  n_removed <- n_original - nrow(data_clean)
  if (n_removed > 0) {
    cat("[INFO] Removed", n_removed, "records with missing/invalid codes\n")
    cat("[INFO] Remaining:", nrow(data_clean), "records\n")
  }

  return(data_clean)
}

# ============================================================================
# LOAD MESSAGE
# ============================================================================

cat("[OK] Estimation helper functions (glm2 version) loaded\n")
cat("  - fit_glm2_estimates() - Binary GLM with glm2\n")
cat("  - fit_multinom_estimates() - Multinomial logistic with nnet\n")
cat("  - validate_binary_estimates()\n")
cat("  - validate_multinomial_estimates()\n")
cat("  - filter_acs_missing()\n")

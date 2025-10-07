# Raking Targets Estimation - Helper Functions
# Purpose: Reusable functions for computing population estimates
# Author: Kidsights Data Platform
# Date: 2025-10-05

library(dplyr)
library(survey)

# ============================================================================
# Function 1: Binary GLM Estimation (ACS/NHIS)
# ============================================================================

#' Fit survey-weighted binary GLM with age x year interaction
#'
#' @param design Survey design object (svydesign)
#' @param formula Formula for binary outcome (e.g., I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR)
#' @param predict_year Year to predict for (default: 2023)
#' @param ages Ages to predict for (default: 0:5)
#' @return Data frame with age and predicted probability
fit_glm_estimates <- function(design, formula, predict_year = 2023, ages = 0:5) {

  # Fit survey-weighted logistic regression
  model <- survey::svyglm(
    formula = formula,
    design = design,
    family = quasibinomial()
  )

  # Get the data types from the design object
  survey_data <- design$variables

  # Create prediction data matching the types in survey data
  newdata <- data.frame(
    AGE = as.numeric(ages)
  )

  # Add MULTYEAR with matching type
  if ("MULTYEAR" %in% names(survey_data)) {
    if (is.factor(survey_data$MULTYEAR)) {
      newdata$MULTYEAR <- factor(predict_year, levels = levels(survey_data$MULTYEAR))
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
# Function 2: Multinomial Estimation (Multi-category outcomes)
# ============================================================================

#' Fit survey-weighted multinomial logit
#'
#' @param design Survey design object
#' @param outcome_var Name of categorical outcome variable (as string)
#' @param predict_year Year to predict for (default: 2023)
#' @param ages Ages to predict for (default: 0:5)
#' @return Data frame with age, category, and predicted probability
fit_multinomial_estimates <- function(design, outcome_var, predict_year = 2023, ages = 0:5) {
  
  # Extract data from design object
  survey_data <- design$variables
  
  # Check if outcome exists
  if (!outcome_var %in% names(survey_data)) {
    stop(paste("Outcome variable", outcome_var, "not found in data"))
  }
  
  # Fit survey-weighted multinomial model (intercept-only for now)
  formula_str <- paste0(outcome_var, " ~ 1")
  
  model <- survey::svymultinom(
    formula = as.formula(formula_str),
    design = design,
    trace = FALSE
  )
  
  # Get predicted probabilities (these will be constant across ages for intercept-only model)
  predictions <- predict(model, type = "probs")
  
  # For intercept-only model, predictions are the same for all ages
  # If predictions is a vector, it's already the probabilities for each category
  if (is.vector(predictions)) {
    probs <- predictions
  } else {
    # If it's a matrix (shouldn't be for intercept-only), take first row
    probs <- predictions[1, ]
  }
  
  # Create result data frame
  categories <- names(probs)
  result <- expand.grid(
    age = ages,
    category = categories,
    stringsAsFactors = FALSE
  )
  result$estimate <- rep(probs, each = length(ages))
  
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

cat("[OK] Estimation helper functions loaded\n")
cat("  - fit_glm_estimates()\n")
cat("  - fit_multinomial_estimates()\n")
cat("  - validate_binary_estimates()\n")
cat("  - validate_multinomial_estimates()\n")
cat("  - filter_acs_missing()\n")

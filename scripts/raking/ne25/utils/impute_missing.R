# ==============================================================================
# CART Imputation Utility for Missing Data
# ==============================================================================
#
# Purpose: Single imputation using CART (Classification and Regression Trees)
#          via mice package for covariance matrix computation
#
# Strategy: Create one imputed dataset per source to maximize sample size
#           while preserving covariance structure
#
# Author: Claude Code
# Created: 2025-12-09
# ==============================================================================

#' Impute missing values using CART imputation
#'
#' @param data Data frame with missing values
#' @param vars Character vector of variable names to include in imputation
#' @param weight_var Character, name of weight variable (excluded from imputation)
#' @param seed Integer, random seed for reproducibility
#' @param m Integer, number of imputations (default = 1 for single imputation)
#' @param maxit Integer, maximum iterations (default = 5)
#'
#' @return Data frame with imputed values
#'
#' @examples
#' imputed_data <- impute_cart(nhis_design,
#'                              vars = c("phq2_total", "gad2_total"),
#'                              weight_var = "survey_weight",
#'                              seed = 12345)
impute_cart <- function(data, vars, weight_var = "survey_weight", seed = 12345, m = 1, maxit = 5) {

  # Load mice package
  if (!require(mice, quietly = TRUE)) {
    stop("mice package required. Install with: install.packages('mice')")
  }

  cat(sprintf("  [Imputation] Using CART with seed = %d\n", seed))

  # Extract variables for imputation (exclude weight)
  impute_data <- data[, c(vars, weight_var), drop = FALSE]

  # Count missing values before imputation
  missing_counts <- colSums(is.na(impute_data[, vars, drop = FALSE]))
  total_missing <- sum(missing_counts)

  if (total_missing == 0) {
    cat("  [Imputation] No missing values - skipping imputation\n")
    return(data)
  }

  cat(sprintf("  [Imputation] Missing values by variable:\n"))
  for (v in vars) {
    if (missing_counts[v] > 0) {
      pct <- missing_counts[v] / nrow(impute_data) * 100
      cat(sprintf("    %s: %d (%.1f%%)\n", v, missing_counts[v], pct))
    }
  }

  # Set seed for reproducibility
  set.seed(seed)

  # Configure mice for CART imputation
  # method = "cart" for all variables with missing data
  method_vec <- rep("", length(vars) + 1)
  names(method_vec) <- c(vars, weight_var)
  for (v in vars) {
    if (missing_counts[v] > 0) {
      method_vec[v] <- "cart"
    }
  }
  method_vec[weight_var] <- ""  # Don't impute weights

  # Create predictor matrix (all variables predict all others, except weight)
  pred_matrix <- matrix(1, nrow = length(vars) + 1, ncol = length(vars) + 1)
  rownames(pred_matrix) <- c(vars, weight_var)
  colnames(pred_matrix) <- c(vars, weight_var)
  diag(pred_matrix) <- 0
  pred_matrix[weight_var, ] <- 0  # Weight doesn't predict
  pred_matrix[, weight_var] <- 0  # Weight is not predicted

  # Run mice imputation
  cat(sprintf("  [Imputation] Running CART imputation (m=%d, maxit=%d)...\n", m, maxit))

  # Suppress mice output
  mice_out <- suppressMessages(
    mice::mice(impute_data,
               m = m,
               method = method_vec,
               predictorMatrix = pred_matrix,
               maxit = maxit,
               seed = seed,
               printFlag = FALSE)
  )

  # Extract first (and only) imputed dataset
  imputed_data <- mice::complete(mice_out, action = 1)

  # Verify no missing values remain
  remaining_missing <- sum(is.na(imputed_data[, vars]))
  if (remaining_missing > 0) {
    warning(sprintf("  [Imputation] %d missing values remain after imputation", remaining_missing))
  } else {
    cat(sprintf("  [Imputation] ✓ All missing values imputed (n=%d)\n", total_missing))
  }

  # Replace imputed variables in original data
  data_imputed <- data
  data_imputed[, vars] <- imputed_data[, vars]

  return(data_imputed)
}

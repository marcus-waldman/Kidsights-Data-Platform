# =============================================================================
# Covariate Preparation Functions for IRT Scoring
# =============================================================================
# Purpose: Prepare standard covariate sets for latent regression in MAP estimation
# Usage: Called by scoring scripts (01_score_kidsights.R, 02_score_psychosocial.R)
# Version: 1.0
# Created: January 4, 2025
#
# Standard Covariate Set:
# - Main effects: age_years, female, educ_mom, fpl, primary_ruca
# - Age interactions: age_years × each main effect
# - Developmental scales only: log(age_years + 1)
# =============================================================================

#' Derive Age in Years from Age in Days
#'
#' Converts age_in_days to age_years using standard conversion (365.25 days/year)
#'
#' @param data Data frame containing age_in_days column
#' @return Data frame with age_years column added
#' @export
derive_age_years <- function(data) {
  if (!"age_in_days" %in% names(data)) {
    stop("Column 'age_in_days' not found in data")
  }

  # Convert to years (accounting for leap years)
  data$age_years <- data$age_in_days / 365.25

  # Validate result
  if (any(is.na(data$age_years[!is.na(data$age_in_days)]))) {
    warning("Some age_years values are NA despite non-missing age_in_days")
  }

  cat("[OK] Derived age_years from age_in_days\n")
  cat(sprintf("    Range: %.2f to %.2f years\n",
              min(data$age_years, na.rm = TRUE),
              max(data$age_years, na.rm = TRUE)))

  return(data)
}

#' Create Age Interaction Terms
#'
#' Creates interaction terms between age_years and other covariates
#' Allows covariate effects to vary by child age
#'
#' @param data Data frame containing age_years and covariate columns
#' @param covariates Character vector of covariate names to interact with age
#' @return Data frame with interaction columns added (named age_X_covariate)
#' @export
create_age_interactions <- function(data, covariates) {
  if (!"age_years" %in% names(data)) {
    stop("Column 'age_years' not found in data. Run derive_age_years() first.")
  }

  # Check all covariates exist
  missing_covs <- setdiff(covariates, names(data))
  if (length(missing_covs) > 0) {
    stop(sprintf("Covariates not found in data: %s",
                 paste(missing_covs, collapse = ", ")))
  }

  # Create interaction terms
  n_interactions <- 0
  for (cov in covariates) {
    interaction_name <- paste0("age_X_", cov)
    data[[interaction_name]] <- data$age_years * data[[cov]]
    n_interactions <- n_interactions + 1
  }

  cat(sprintf("[OK] Created %d age interaction terms\n", n_interactions))
  cat(sprintf("    Variables: %s\n",
              paste(paste0("age_X_", covariates), collapse = ", ")))

  return(data)
}

#' Add Developmental Terms for Normative Scales
#'
#' Adds log(age + 1) transformation to capture nonlinear developmental trends
#' Only used for developmental scales (e.g., Kidsights), not psychosocial scales
#'
#' @param data Data frame containing age_years column
#' @return Data frame with log_age_plus_1 column added
#' @export
add_developmental_terms <- function(data) {
  if (!"age_years" %in% names(data)) {
    stop("Column 'age_years' not found in data. Run derive_age_years() first.")
  }

  # Log transformation (adding 1 to handle age=0)
  data$log_age_plus_1 <- log(data$age_years + 1)

  # Validate result
  if (any(is.infinite(data$log_age_plus_1) | is.nan(data$log_age_plus_1))) {
    warning("Some log_age_plus_1 values are Inf or NaN")
  }

  cat("[OK] Added developmental term: log(age_years + 1)\n")
  cat(sprintf("    Range: %.3f to %.3f\n",
              min(data$log_age_plus_1, na.rm = TRUE),
              max(data$log_age_plus_1, na.rm = TRUE)))

  return(data)
}

#' Get Standard Covariate Set for Latent Regression
#'
#' Main function to prepare complete covariate set according to configuration
#' Reads from irt_scoring_config.yaml and prepares all necessary variables
#'
#' @param data Data frame from completed imputation dataset
#' @param config List from irt_scoring_config.yaml (loaded via yaml::read_yaml)
#' @param scale_name Character string indicating which scale ("kidsights", "psychosocial", etc.)
#' @return List with two elements:
#'   - data: Data frame with all covariate columns added
#'   - formula_terms: Character vector of covariate names for latent regression formula
#' @export
get_standard_covariates <- function(data, config, scale_name) {

  cat("\n", strrep("=", 60), "\n")
  cat("PREPARING STANDARD COVARIATES FOR LATENT REGRESSION\n")
  cat(strrep("=", 60), "\n\n")

  # Extract configuration
  scale_config <- config$scales[[scale_name]]
  if (is.null(scale_config)) {
    stop(sprintf("Scale '%s' not found in configuration", scale_name))
  }

  # Check if scale uses standard covariates
  if (!scale_config$use_standard_covariates) {
    cat("[INFO] Scale does not use standard covariates\n")
    cat("[INFO] Using custom covariates only\n")
    return(list(
      data = data,
      formula_terms = scale_config$custom_covariates
    ))
  }

  # Step 1: Derive age_years
  cat("Step 1: Deriving age_years from age_in_days...\n")
  data <- derive_age_years(data)

  # Step 2: Get main effects from config
  main_effects <- config$standard_covariates$main_effects
  cat("\nStep 2: Main effects from configuration:\n")
  cat(sprintf("    %s\n", paste(main_effects, collapse = ", ")))

  # Verify main effects exist (except age_years which we just created)
  required_vars <- setdiff(main_effects, "age_years")
  missing_vars <- setdiff(required_vars, names(data))
  if (length(missing_vars) > 0) {
    stop(sprintf("Required covariate(s) not found in data: %s\n",
                 paste(missing_vars, collapse = ", ")))
  }

  # Step 3: Create age interactions
  interaction_covs <- config$standard_covariates$age_interactions
  cat("\nStep 3: Creating age interaction terms...\n")
  data <- create_age_interactions(data, interaction_covs)

  # Build formula terms list
  formula_terms <- c(
    main_effects,
    paste0("age_X_", interaction_covs)
  )

  # Step 4: Add developmental terms if needed
  if (scale_config$developmental_scale) {
    cat("\nStep 4: Adding developmental term (log transformation)...\n")
    cat(sprintf("    Scale '%s' is a normative developmental scale\n", scale_name))
    data <- add_developmental_terms(data)
    formula_terms <- c(formula_terms, "log_age_plus_1")
  } else {
    cat("\nStep 4: Skipping developmental term\n")
    cat(sprintf("    Scale '%s' is not a developmental scale\n", scale_name))
  }

  # Step 5: Add any custom covariates
  if (length(scale_config$custom_covariates) > 0) {
    cat("\nStep 5: Adding custom covariates...\n")
    cat(sprintf("    %s\n", paste(scale_config$custom_covariates, collapse = ", ")))
    formula_terms <- c(formula_terms, scale_config$custom_covariates)

    # Verify custom covariates exist
    missing_custom <- setdiff(scale_config$custom_covariates, names(data))
    if (length(missing_custom) > 0) {
      stop(sprintf("Custom covariate(s) not found: %s",
                   paste(missing_custom, collapse = ", ")))
    }
  } else {
    cat("\nStep 5: No custom covariates specified\n")
  }

  # Summary
  cat("\n", strrep("-", 60), "\n")
  cat("COVARIATE PREPARATION COMPLETE\n")
  cat(strrep("-", 60), "\n")
  cat(sprintf("Total covariates: %d\n", length(formula_terms)))
  cat(sprintf("Formula terms: %s\n", paste(formula_terms, collapse = " + ")))
  cat("\n")

  # Check for missing values in covariates
  n_complete_cases <- sum(complete.cases(data[, formula_terms]))
  n_total <- nrow(data)
  pct_complete <- 100 * n_complete_cases / n_total

  cat(sprintf("Complete cases: %d / %d (%.1f%%)\n",
              n_complete_cases, n_total, pct_complete))

  if (pct_complete < 95) {
    warning(sprintf("Only %.1f%% of cases have complete covariate data", pct_complete))
    cat("[WARN] Consider checking for missing data in covariates\n")
  }

  cat(strrep("=", 60), "\n\n")

  return(list(
    data = data,
    formula_terms = formula_terms
  ))
}

#' Validate Covariate Data Quality
#'
#' Performs diagnostic checks on covariate data before scoring
#' Useful for catching data issues early
#'
#' @param data Data frame with covariates
#' @param covariate_names Character vector of covariate column names
#' @return Invisible list with validation results
#' @export
validate_covariate_data <- function(data, covariate_names) {

  cat("\n", strrep("=", 60), "\n")
  cat("COVARIATE DATA VALIDATION\n")
  cat(strrep("=", 60), "\n\n")

  results <- list()

  for (cov in covariate_names) {
    cat(sprintf("Checking: %s\n", cov))

    # Missing values
    n_missing <- sum(is.na(data[[cov]]))
    pct_missing <- 100 * n_missing / nrow(data)
    cat(sprintf("  Missing: %d (%.1f%%)\n", n_missing, pct_missing))

    # Infinite or NaN values
    if (is.numeric(data[[cov]])) {
      n_inf <- sum(is.infinite(data[[cov]]), na.rm = TRUE)
      n_nan <- sum(is.nan(data[[cov]]), na.rm = TRUE)

      if (n_inf > 0 || n_nan > 0) {
        warning(sprintf("%s has %d Inf and %d NaN values", cov, n_inf, n_nan))
      }

      # Range
      range_vals <- range(data[[cov]], na.rm = TRUE)
      cat(sprintf("  Range: [%.3f, %.3f]\n", range_vals[1], range_vals[2]))
    }

    cat("\n")

    results[[cov]] <- list(
      n_missing = n_missing,
      pct_missing = pct_missing
    )
  }

  cat(strrep("=", 60), "\n\n")

  invisible(results)
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

# library(yaml)
#
# # Load configuration
# config <- yaml::read_yaml("config/irt_scoring/irt_scoring_config.yaml")
#
# # Load completed dataset (from imputation m=1)
# # This would typically come from imputation helper functions
# data <- get_completed_dataset(imputation_m = 1, study_id = "ne25")
#
# # Prepare covariates for Kidsights scoring
# cov_result <- get_standard_covariates(
#   data = data,
#   config = config,
#   scale_name = "kidsights"
# )
#
# # Extract prepared data and formula terms
# data_with_covs <- cov_result$data
# formula_terms <- cov_result$formula_terms
#
# # Validate covariate quality
# validate_covariate_data(data_with_covs, formula_terms)
#
# # Now ready for MAP scoring with latent regression:
# # theta ~ age_years + female + educ_mom + fpl + primary_ruca +
# #         age_X_female + age_X_educ_mom + age_X_fpl + age_X_primary_ruca +
# #         log_age_plus_1

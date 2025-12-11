# Model fitting utilities for survey-weighted criterion validity analysis
# Helper functions for criterion validity report

#' Fit Survey-Weighted Model on Multiple Imputations
#'
#' Fit a single criterion model across all M imputations with survey weights
#'
#' @param imp_obj mice imputation object from mice::mice()
#' @param outcome Character, name of outcome variable
#' @param criterion Character, name of criterion variable
#' @param weight_var Character, name of weight variable. Default: "calibrated_weight"
#' @return List of M fitted survey::svyglm() models
#'
#' @details
#' Model specification: outcome ~ log(years_old + 1) + female*years_old + criterion*years_old
#' Uses survey::svydesign() with provided weights and no clustering (ids = ~1)
#'
#' @export
fit_criterion_model <- function(imp_obj, outcome, criterion, weight_var = "calibrated_weight") {
  # Get number of imputations
  M <- imp_obj$m

  # Build formula with appropriate transformations for each criterion
  # FPL: log-transform for interpretability
  # educ4_a1: use as-is (factor conversion happens in data before model fitting)
  # Others: use as-is
  criterion_term <- switch(criterion,
    "fpl" = "log(fpl + 1)",
    "educ4_a1" = "educ4_a1",  # Already converted to factor in data
    criterion  # Default: use as-is
  )

  formula_str <- sprintf(
    "%s ~ log(years_old + 1) + female*years_old + %s*years_old",
    outcome, criterion_term
  )
  formula_obj <- as.formula(formula_str)

  # Fit model on each imputation
  model_list <- lapply(1:M, function(m) {
    # Extract completed dataset for imputation m
    dat_m <- mice::complete(imp_obj, action = m)

    # Note: educ4_a1 is already a factor from imputation with Bachelor's as reference

    # Create survey design
    design_m <- survey::svydesign(
      ids = ~1,                    # No clustering (SRS)
      weights = as.formula(paste0("~", weight_var)),
      data = dat_m
    )

    # Fit weighted regression
    model_m <- survey::svyglm(
      formula = formula_obj,
      design = design_m,
      family = stats::gaussian()
    )

    return(model_m)
  })

  # Add metadata
  attr(model_list, "outcome") <- outcome
  attr(model_list, "criterion") <- criterion
  attr(model_list, "M") <- M
  attr(model_list, "formula") <- formula_str

  return(model_list)
}


#' Fit All Criterion Models
#'
#' Fit models for all criterion variables × outcomes combinations
#'
#' @param imp_obj mice imputation object
#' @param outcomes Character vector of outcome variable names
#' @param criteria Character vector of criterion variable names
#' @param weight_var Character, name of weight variable. Default: "calibrated_weight"
#' @return Named list of model lists (one entry per outcome-criterion pair)
#'
#' @details
#' Creates all combinations of outcomes × criteria (e.g., 2 outcomes × 4 criteria = 8 models).
#' Each element is a list of M fitted models suitable for pool_mi_results().
#'
#' @export
fit_all_models <- function(imp_obj, outcomes, criteria, weight_var = "calibrated_weight") {
  # Initialize storage
  all_models <- list()

  # Loop over all combinations
  for (outcome in outcomes) {
    for (criterion in criteria) {
      # Create unique key for this combination
      model_key <- paste0(outcome, "_", criterion)

      cat(sprintf("Fitting models: %s ~ %s\n", outcome, criterion))

      # Fit model across M imputations
      model_list <- fit_criterion_model(
        imp_obj = imp_obj,
        outcome = outcome,
        criterion = criterion,
        weight_var = weight_var
      )

      # Store in results
      all_models[[model_key]] <- model_list
    }
  }

  cat(sprintf("\n[OK] Fitted %d model combinations across M=%d imputations\n",
              length(all_models), imp_obj$m))

  return(all_models)
}


#' Pool All Criterion Models
#'
#' Apply Rubin's rules to all fitted models
#'
#' @param all_models Output from fit_all_models()
#' @param pooling_fn Pooling function to use. Default: pool_mi_results
#' @return Named list of pooled results (one entry per outcome-criterion pair)
#'
#' @export
pool_all_models <- function(all_models, pooling_fn = pool_mi_results) {
  # Source pooling utilities if not already loaded
  if (!exists("pool_mi_results", mode = "function")) {
    source(file.path("reports", "ne25", "helpers", "pooling_utilities.R"))
  }

  pooled_results <- lapply(all_models, function(model_list) {
    pooling_fn(model_list)
  })

  return(pooled_results)
}


#' Extract Model Fit Statistics
#'
#' Extract R², Adjusted R², and N from a single imputation
#' (used for summary table; fit stats are not pooled across imputations)
#'
#' @param model_list List of M fitted models from fit_criterion_model()
#' @param use_imputation Which imputation to extract fit stats from. Default: 1
#' @return Named list with r_squared, adj_r_squared, n
#'
#' @export
extract_fit_stats <- function(model_list, use_imputation = 1) {
  model_m <- model_list[[use_imputation]]

  # Get sample size
  n <- nrow(model_m$survey.design$variables)

  # Calculate R² for survey models
  # For svyglm, we need to calculate manually
  # R² = 1 - (Residual Deviance / Null Deviance)

  # Get deviances
  null_dev <- model_m$null.deviance
  resid_dev <- model_m$deviance

  # Calculate R² (pseudo R² for weighted regression)
  if (!is.null(null_dev) && !is.null(resid_dev) && null_dev > 0) {
    r2 <- 1 - (resid_dev / null_dev)
  } else {
    r2 <- NA
  }

  # Calculate adjusted R²
  # Adj R² = 1 - [(1-R²)(n-1)/(n-p-1)] where p = number of predictors
  p <- length(coef(model_m)) - 1  # Subtract 1 for intercept
  if (!is.na(r2) && n > p + 1) {
    adj_r2 <- 1 - ((1 - r2) * (n - 1) / (n - p - 1))
  } else {
    adj_r2 <- NA
  }

  return(list(
    r_squared = r2,
    adj_r_squared = adj_r2,
    n = n
  ))
}


#' Create Fit Statistics Summary Table
#'
#' Extract fit statistics for all models into a summary table
#'
#' @param all_models Output from fit_all_models()
#' @param outcomes Character vector of outcome names (for organization)
#' @param criteria Character vector of criterion names (for organization)
#' @return data.frame with columns: Outcome, Criterion, R², Adj. R², N
#'
#' @export
create_fit_summary_table <- function(all_models, outcomes, criteria) {
  # Initialize storage
  fit_rows <- list()
  idx <- 1

  # Loop over all combinations
  for (outcome in outcomes) {
    for (criterion in criteria) {
      model_key <- paste0(outcome, "_", criterion)
      model_list <- all_models[[model_key]]

      # Extract fit stats from first imputation
      fit_stats <- extract_fit_stats(model_list, use_imputation = 1)

      # Create row
      fit_rows[[idx]] <- data.frame(
        Outcome = outcome,
        Criterion = criterion,
        R2 = fit_stats$r_squared,
        Adj_R2 = fit_stats$adj_r_squared,
        N = fit_stats$n,
        stringsAsFactors = FALSE
      )
      idx <- idx + 1
    }
  }

  # Combine into data.frame
  fit_df <- do.call(rbind, fit_rows)

  # Format column names
  colnames(fit_df) <- c("Outcome", "Criterion", "R²", "Adjusted R²", "N")

  return(fit_df)
}


#' Get Criterion Label
#'
#' Convert criterion variable name to readable label
#'
#' @param criterion Character, criterion variable name
#' @return Character, formatted label
#'
#' @export
get_criterion_label <- function(criterion) {
  labels <- c(
    "fpl" = "Family Poverty Line (FPL)",
    "educ4_a1" = "Maternal Education",
    "urban_pct" = "Urbanicity (%)",
    "phq2_total" = "Maternal Depression (PHQ-2)"
  )

  # Return label if exists, otherwise return original
  if (criterion %in% names(labels)) {
    return(labels[[criterion]])
  } else {
    return(criterion)
  }
}


#' Get Outcome Label
#'
#' Convert outcome variable name to readable label
#'
#' @param outcome Character, outcome variable name
#' @return Character, formatted label
#'
#' @export
get_outcome_label <- function(outcome) {
  labels <- c(
    "kidsights_2022" = "Kidsights 2022 Overall",
    "general_gsed_pf_2022" = "General GSED-PF 2022"
  )

  # Return label if exists, otherwise return original
  if (outcome %in% names(labels)) {
    return(labels[[outcome]])
  } else {
    return(outcome)
  }
}

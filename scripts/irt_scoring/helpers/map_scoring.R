# =============================================================================
# MAP Scoring Wrapper Functions for IRT Scoring
# =============================================================================
# Purpose: Interface with IRTScoring package for MAP estimation with latent regression
# Usage: Called by scoring scripts (01_score_kidsights.R, 02_score_psychosocial.R)
# Version: 1.0
# Created: January 4, 2025
#
# Key Functions:
# - load_irt_parameters_from_codebook() - Extract IRT parameters from codebook.json
# - prepare_item_responses() - Format item response data for scoring
# - score_unidimensional_map() - MAP estimation for unidimensional models
# - score_bifactor_map() - MAP estimation for bifactor models
# =============================================================================

#' Load IRT Parameters from Codebook
#'
#' Extracts IRT parameters for specified scale from codebook.json
#' Converts from codebook format to format needed by IRTScoring
#'
#' @param codebook_path Path to codebook.json file
#' @param scale_config Scale configuration from irt_scoring_config.yaml
#' @return List with IRT parameter matrices for IRTScoring package
#' @export
load_irt_parameters_from_codebook <- function(codebook_path, scale_config) {

  cat("\n", strrep("=", 60), "\n")
  cat("LOADING IRT PARAMETERS FROM CODEBOOK\n")
  cat(strrep("=", 60), "\n\n")

  # Load codebook
  if (!file.exists(codebook_path)) {
    stop(sprintf("Codebook not found: %s", codebook_path))
  }

  cat(sprintf("Reading codebook: %s\n", codebook_path))
  codebook <- jsonlite::fromJSON(codebook_path, simplifyVector = FALSE)

  # Get calibration study
  calib_study <- scale_config$calibration_study
  cat(sprintf("Calibration study: %s\n", calib_study))
  cat(sprintf("Model type: %s\n", scale_config$model_type))

  # Get items
  if (scale_config$items_source == "codebook") {
    # Extract from codebook using lexicon
    lexicon_name <- scale_config$lexicon
    cat(sprintf("Extracting items using lexicon: %s\n", lexicon_name))

    # Filter items by study
    items_list <- list()
    for (item in codebook$items) {
      # Check if item exists in calibration study
      if (calib_study %in% item$studies) {
        # Get lexicon name
        lex_name <- item$lexicons[[lexicon_name]]
        if (!is.null(lex_name)) {
          items_list[[lex_name]] <- item
        }
      }
    }

    item_names <- names(items_list)
    cat(sprintf("Found %d items with IRT parameters\n", length(item_names)))

  } else {
    # Use explicit item list from config
    item_names <- scale_config$items
    cat(sprintf("Using explicit item list: %d items\n", length(item_names)))

    # Get items from codebook by matching lexicon
    items_list <- list()
    for (item in codebook$items) {
      # Match by lexicon (for PS items, match against 'kidsight' or 'equate' lexicon)
      for (lex_key in names(item$lexicons)) {
        lex_val <- item$lexicons[[lex_key]]
        if (lex_val %in% item_names) {
          items_list[[lex_val]] <- item
          break
        }
      }
    }
  }

  # Extract IRT parameters
  cat("\nExtracting IRT parameters...\n")

  # Initialize parameter matrices
  n_items <- length(item_names)

  if (scale_config$model_type == "unidimensional") {
    # Unidimensional: single loading per item, multiple thresholds
    loadings <- numeric(n_items)
    thresholds_list <- list()

    for (i in seq_along(item_names)) {
      item_name <- item_names[i]
      item <- items_list[[item_name]]

      # Get IRT parameters for calibration study
      irt_params <- item$psychometric$irt_parameters[[calib_study]]

      if (is.null(irt_params)) {
        stop(sprintf("No IRT parameters found for item %s in study %s",
                     item_name, calib_study))
      }

      # Extract loading (first element, assuming unidimensional)
      loadings[i] <- irt_params$loadings[[1]]

      # Extract thresholds
      thresholds_list[[i]] <- unlist(irt_params$thresholds)
    }

    cat(sprintf("  Loadings: %d items\n", length(loadings)))
    cat(sprintf("  Loadings range: [%.3f, %.3f]\n",
                min(loadings), max(loadings)))

    params <- list(
      item_names = item_names,
      loadings = loadings,
      thresholds = thresholds_list,
      model_type = "unidimensional"
    )

  } else if (scale_config$model_type == "bifactor") {
    # Bifactor: multiple loadings per item, multiple thresholds
    factors <- scale_config$factors
    n_factors <- length(factors)

    cat(sprintf("  Factors: %s\n", paste(factors, collapse = ", ")))

    loadings_matrix <- matrix(NA, nrow = n_items, ncol = n_factors)
    colnames(loadings_matrix) <- factors
    rownames(loadings_matrix) <- item_names

    thresholds_list <- list()

    for (i in seq_along(item_names)) {
      item_name <- item_names[i]
      item <- items_list[[item_name]]

      # Get IRT parameters for calibration study
      irt_params <- item$psychometric$irt_parameters[[calib_study]]

      if (is.null(irt_params)) {
        stop(sprintf("No IRT parameters found for item %s in study %s",
                     item_name, calib_study))
      }

      # Extract loadings (should match number of factors for this item)
      item_factors <- unlist(irt_params$factors)
      item_loadings <- unlist(irt_params$loadings)

      # Match factor names to columns
      for (j in seq_along(item_factors)) {
        factor_name <- item_factors[j]
        factor_idx <- which(factors == factor_name)
        if (length(factor_idx) > 0) {
          loadings_matrix[i, factor_idx] <- item_loadings[j]
        }
      }

      # Extract thresholds
      thresholds_list[[i]] <- unlist(irt_params$thresholds)
    }

    cat(sprintf("  Loadings matrix: %d items × %d factors\n",
                nrow(loadings_matrix), ncol(loadings_matrix)))

    params <- list(
      item_names = item_names,
      loadings = loadings_matrix,
      thresholds = thresholds_list,
      factors = factors,
      model_type = "bifactor"
    )

  } else {
    stop(sprintf("Model type '%s' not supported", scale_config$model_type))
  }

  cat("\n[OK] IRT parameters loaded successfully\n")
  cat(strrep("=", 60), "\n\n")

  return(params)
}

#' Prepare Item Response Data for Scoring
#'
#' Extracts and formats item responses from completed dataset
#' Ensures items are in correct order matching IRT parameter matrices
#'
#' @param data Data frame with item response columns
#' @param item_names Character vector of item names in correct order
#' @param scale_config Scale configuration from irt_scoring_config.yaml
#' @return Matrix of item responses (rows = persons, cols = items)
#' @export
prepare_item_responses <- function(data, item_names, scale_config) {

  cat("\n", strrep("=", 60), "\n")
  cat("PREPARING ITEM RESPONSE DATA\n")
  cat(strrep("=", 60), "\n\n")

  # Check if all items exist in data
  missing_items <- setdiff(item_names, names(data))
  if (length(missing_items) > 0) {
    stop(sprintf("Items not found in data: %s",
                 paste(missing_items, collapse = ", ")))
  }

  # Extract item columns in correct order
  item_matrix <- as.matrix(data[, item_names])

  cat(sprintf("Items: %d\n", ncol(item_matrix)))
  cat(sprintf("Persons: %d\n", nrow(item_matrix)))

  # Check for missing responses
  n_total <- nrow(item_matrix) * ncol(item_matrix)
  n_missing <- sum(is.na(item_matrix))
  pct_missing <- 100 * n_missing / n_total

  cat(sprintf("Missing responses: %d / %d (%.2f%%)\n",
              n_missing, n_total, pct_missing))

  # Pattern of missingness
  n_complete_cases <- sum(complete.cases(item_matrix))
  pct_complete <- 100 * n_complete_cases / nrow(item_matrix)

  cat(sprintf("Complete cases: %d / %d (%.1f%%)\n",
              n_complete_cases, nrow(item_matrix), pct_complete))

  if (pct_complete < 50) {
    warning(sprintf("Only %.1f%% of cases have complete item responses", pct_complete))
  }

  cat("\n[OK] Item response data prepared\n")
  cat(strrep("=", 60), "\n\n")

  return(item_matrix)
}

#' Score Unidimensional Model with MAP Estimation
#'
#' Wrapper for IRTScoring package MAP estimation (unidimensional models)
#' Includes latent regression with covariates
#'
#' @param item_responses Matrix of item responses (persons × items)
#' @param irt_params List with IRT parameters from load_irt_parameters_from_codebook()
#' @param covariates Data frame with covariate columns for latent regression
#' @param formula_terms Character vector of covariate names for regression formula
#' @return Data frame with theta (MAP estimate) and se (standard error) columns
#' @export
score_unidimensional_map <- function(item_responses, irt_params, covariates, formula_terms) {

  cat("\n", strrep("=", 60), "\n")
  cat("MAP SCORING: UNIDIMENSIONAL MODEL\n")
  cat(strrep("=", 60), "\n\n")

  # Check if IRTScoring package is available
  if (!requireNamespace("IRTScoring", quietly = TRUE)) {
    stop(paste(
      "IRTScoring package not installed.",
      "Install from: https://github.com/marcus-waldman/IRTScoring",
      sep = "\n"
    ))
  }

  # TODO: This is a placeholder for actual IRTScoring function call
  # The exact function name and syntax will depend on IRTScoring package implementation

  cat("Attempting to call IRTScoring::map_estimate_latent_regression()...\n\n")

  # Check if function exists
  if (!exists("map_estimate_latent_regression", where = asNamespace("IRTScoring"), mode = "function")) {
    stop(paste(
      "Function 'map_estimate_latent_regression' not found in IRTScoring package.",
      "",
      "This function may not be implemented yet.",
      "",
      "Expected signature:",
      "  map_estimate_latent_regression(",
      "    responses = item_responses,",
      "    loadings = irt_params$loadings,",
      "    thresholds = irt_params$thresholds,",
      "    covariates = covariates,",
      "    formula = formula_string",
      "  )",
      "",
      "Please check IRTScoring documentation or create GitHub issue.",
      sep = "\n"
    ))
  }

  # Construct formula for latent regression
  formula_string <- paste(formula_terms, collapse = " + ")
  cat(sprintf("Latent regression formula: theta ~ %s\n\n", formula_string))

  # Call IRTScoring function (placeholder - adjust based on actual API)
  tryCatch({
    scores <- IRTScoring::map_estimate_latent_regression(
      responses = item_responses,
      loadings = irt_params$loadings,
      thresholds = irt_params$thresholds,
      covariates = covariates,
      formula = formula_string
    )

    cat("[OK] MAP estimation completed\n")
    cat(sprintf("    Scored %d persons\n", nrow(scores)))

    return(scores)

  }, error = function(e) {
    stop(sprintf("IRTScoring error: %s", e$message))
  })
}

#' Score Bifactor Model with MAP Estimation
#'
#' Wrapper for IRTScoring package MAP estimation (bifactor models)
#' Includes latent regression with covariates
#' Returns scores for general factor + all specific factors
#'
#' @param item_responses Matrix of item responses (persons × items)
#' @param irt_params List with IRT parameters from load_irt_parameters_from_codebook()
#' @param covariates Data frame with covariate columns for latent regression
#' @param formula_terms Character vector of covariate names for regression formula
#' @return Data frame with theta and se columns for each factor
#' @export
score_bifactor_map <- function(item_responses, irt_params, covariates, formula_terms) {

  cat("\n", strrep("=", 60), "\n")
  cat("MAP SCORING: BIFACTOR MODEL\n")
  cat(strrep("=", 60), "\n\n")

  # Check if IRTScoring package is available
  if (!requireNamespace("IRTScoring", quietly = TRUE)) {
    stop(paste(
      "IRTScoring package not installed.",
      "Install from: https://github.com/marcus-waldman/IRTScoring",
      sep = "\n"
    ))
  }

  cat(sprintf("Factors: %s\n", paste(irt_params$factors, collapse = ", ")))

  # TODO: This is a placeholder for actual IRTScoring function call
  # The exact function name and syntax will depend on IRTScoring package implementation

  cat("\nAttempting to call IRTScoring::map_estimate_bifactor_latent_regression()...\n\n")

  # Check if function exists
  if (!exists("map_estimate_bifactor_latent_regression", where = asNamespace("IRTScoring"), mode = "function")) {
    stop(paste(
      "Function 'map_estimate_bifactor_latent_regression' not found in IRTScoring package.",
      "",
      "This function may not be implemented yet.",
      "",
      "Expected signature:",
      "  map_estimate_bifactor_latent_regression(",
      "    responses = item_responses,",
      "    loadings_matrix = irt_params$loadings,",
      "    thresholds = irt_params$thresholds,",
      "    factors = irt_params$factors,",
      "    covariates = covariates,",
      "    formula = formula_string",
      "  )",
      "",
      "Expected output: Data frame with columns:",
      "  theta_gen, se_gen, theta_factor1, se_factor1, ...",
      "",
      "Please check IRTScoring documentation or create GitHub issue.",
      sep = "\n"
    ))
  }

  # Construct formula for latent regression
  formula_string <- paste(formula_terms, collapse = " + ")
  cat(sprintf("Latent regression formula: theta ~ %s\n\n", formula_string))

  # Call IRTScoring function (placeholder - adjust based on actual API)
  tryCatch({
    scores <- IRTScoring::map_estimate_bifactor_latent_regression(
      responses = item_responses,
      loadings_matrix = irt_params$loadings,
      thresholds = irt_params$thresholds,
      factors = irt_params$factors,
      covariates = covariates,
      formula = formula_string
    )

    cat("[OK] MAP estimation completed\n")
    cat(sprintf("    Scored %d persons\n", nrow(scores)))
    cat(sprintf("    Returned %d factor scores per person\n", length(irt_params$factors)))

    return(scores)

  }, error = function(e) {
    stop(sprintf("IRTScoring error: %s", e$message))
  })
}

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

# library(yaml)
# library(IRTScoring)
#
# # Load configuration
# config <- yaml::read_yaml("config/irt_scoring/irt_scoring_config.yaml")
#
# # Load codebook parameters
# irt_params <- load_irt_parameters_from_codebook(
#   codebook_path = config$data_sources$codebook_path,
#   scale_config = config$scales$kidsights
# )
#
# # Load completed dataset
# data <- get_completed_dataset(imputation_m = 1, study_id = "ne25")
#
# # Prepare covariates
# cov_result <- get_standard_covariates(
#   data = data,
#   config = config,
#   scale_name = "kidsights"
# )
#
# # Prepare item responses
# item_responses <- prepare_item_responses(
#   data = cov_result$data,
#   item_names = irt_params$item_names,
#   scale_config = config$scales$kidsights
# )
#
# # Score with MAP estimation
# scores <- score_unidimensional_map(
#   item_responses = item_responses,
#   irt_params = irt_params,
#   covariates = cov_result$data,
#   formula_terms = cov_result$formula_terms
# )

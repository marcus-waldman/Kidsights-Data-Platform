# Bootstrap Helper Functions for NE25 Raking Targets (glm2 Version)
# Created: January 2025
# Purpose: Generate bootstrap replicate estimates using glm2/multinom with starting values
# Refactored from: bootstrap_helpers.R (survey package version)

library(glm2)
library(nnet)
library(future)
library(future.apply)

# Source centralized configuration
source("config/bootstrap_config.R")

# Configure parallel processing memory limit from config
max_globals_bytes <- BOOTSTRAP_CONFIG$max_globals_gb * 1024^3
options(future.globals.maxSize = max_globals_bytes)

cat("\n========================================\n")
cat("Parallel Processing Configuration\n")
cat("========================================\n")
cat("future.globals.maxSize:", round(max_globals_bytes / 1024^3, 1), "GB\n")
cat("Parallel workers:", BOOTSTRAP_CONFIG$parallel_workers, "\n")
cat("========================================\n\n")

# ============================================================================
# Function 1: Binary GLM Bootstrap with glm2 and Starting Values
# ============================================================================

#' Generate Bootstrap Replicates for Binary GLM using glm2 with Starting Values
#'
#' Fits glm2 models on bootstrap replicate weights, using coefficients from
#' the main model as starting values for efficiency.
#'
#' @param data Data frame with outcome, predictors, and replicate weights
#' @param formula Model formula (e.g., I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR)
#' @param replicate_weights Matrix of bootstrap replicate weights (n_obs x n_boot)
#' @param pred_data Data frame with prediction covariates
#' @param main_weights Vector of main design weights (default: row means of replicate_weights)
#'
#' @return List with:
#'   - point_estimates: Vector of point estimates from main model
#'   - boot_estimates: Matrix of bootstrap estimates (n_pred x n_boot)
#'   - n_boot: Number of bootstrap replicates
#'   - main_iterations: Iterations for main model
#'   - boot_iterations_mean: Mean iterations for bootstrap models
#'
#' @examples
#' # Extract replicate weights from bootstrap design
#' replicate_weights <- boot_design$repweights
#'
#' # Generate bootstrap estimates
#' result <- generate_bootstrap_glm2(
#'   data = acs_data,
#'   formula = I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
#'   replicate_weights = replicate_weights,
#'   pred_data = data.frame(AGE = 0:5, MULTYEAR = 2023)
#' )
generate_bootstrap_glm2 <- function(data, formula, replicate_weights, pred_data,
                                    main_weights = NULL) {

  n_boot <- ncol(replicate_weights)

  cat("  [Bootstrap GLM2] Using", n_boot, "bootstrap replicate weights...\n")

  # Step 1: Fit main model with original weights
  cat("    [1/3] Fitting main model with glm2...\n")

  if (is.null(main_weights)) {
    # Use row means of replicate weights as proxy for original weights
    main_weights <- rowMeans(replicate_weights)
  }

  # Add weights as column to avoid scoping issues
  data_with_wts <- data
  data_with_wts$.main_weights <- main_weights

  model_main <- glm2::glm2(
    formula = formula,
    data = data_with_wts,
    weights = .main_weights,
    family = binomial()
  )

  # Get point estimates
  point_est <- predict(model_main, newdata = pred_data, type = "response")
  cat("    Point estimates computed (n =", length(point_est), ")\n")
  cat("    Main model iterations:", model_main$iter, "\n")

  # Extract starting values (coefficients from main model)
  start_coef <- coef(model_main)
  cat("    Starting values extracted (", length(start_coef), " coefficients)\n\n", sep = "")

  # Step 2: Generate replicate estimates using PARALLEL processing
  cat("    [2/3] Generating bootstrap estimates with starting values...\n")

  # Configure parallel workers from config
  n_workers <- BOOTSTRAP_CONFIG$parallel_workers
  future::plan(future::multisession, workers = n_workers)
  cat("           Starting", n_workers, "parallel workers...\n")

  # Parallel bootstrap estimation with starting values
  boot_results <- future.apply::future_lapply(1:n_boot, function(i) {
    # Add bootstrap weights as column to avoid scoping issues
    data_boot <- data
    data_boot$.boot_wts <- replicate_weights[, i]

    # Fit model with i-th bootstrap weight using starting values
    model_boot <- glm2::glm2(
      formula = formula,
      data = data_boot,
      weights = .boot_wts,  # i-th replicate weights
      family = binomial(),
      start = start_coef  # ← STARTING VALUES for speed
    )

    # Return predictions and iteration count
    list(
      predictions = as.numeric(predict(model_boot, newdata = pred_data, type = "response")),
      iterations = model_boot$iter
    )
  }, future.seed = TRUE, future.packages = c("glm2"))

  # Close workers after use
  future::plan(future::sequential)
  cat("           Workers closed\n")

  # Step 3: Extract results
  cat("    [3/3] Extracting bootstrap results...\n")

  # Extract predictions (matrix: n_pred x n_boot)
  boot_estimates <- do.call(cbind, lapply(boot_results, function(x) x$predictions))

  # Extract iteration counts for diagnostics
  boot_iterations <- sapply(boot_results, function(x) x$iterations)
  cat("    Bootstrap iterations: mean =", round(mean(boot_iterations), 1),
      ", range = [", min(boot_iterations), ",", max(boot_iterations), "]\n")
  cat("    Speedup from starting values: ",
      round(model_main$iter / mean(boot_iterations), 2), "x\n", sep = "")

  cat("    Bootstrap estimates: ", nrow(boot_estimates), " predictions x ",
      ncol(boot_estimates), " replicates\n\n", sep = "")

  # Return results
  list(
    point_estimates = as.numeric(point_est),
    boot_estimates = boot_estimates,
    n_boot = n_boot,
    main_iterations = model_main$iter,
    boot_iterations_mean = mean(boot_iterations)
  )
}

# ============================================================================
# Function 2: Multinomial Bootstrap with nnet::multinom and Starting Weights
# ============================================================================

#' Generate Bootstrap Replicates for Multinomial Logistic using multinom with Starting Weights
#'
#' Fits nnet::multinom models on bootstrap replicate weights, using weights from
#' the main model as starting values for efficiency (via Wts argument).
#'
#' @param data Data frame with categorical outcome, predictors, and replicate weights
#' @param formula Model formula (e.g., fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR)
#' @param replicate_weights Matrix of bootstrap replicate weights (n_obs x n_boot)
#' @param pred_data Data frame with prediction covariates
#' @param main_weights Vector of main design weights (default: row means of replicate_weights)
#'
#' @return List with:
#'   - point_estimates: Data frame with point estimates (long format: age, category, estimate)
#'   - boot_estimates: Array of bootstrap estimates (n_ages x n_categories x n_boot)
#'   - n_boot: Number of bootstrap replicates
#'   - categories: Vector of category names
#'
#' @examples
#' # Generate bootstrap estimates for FPL categories
#' result <- generate_bootstrap_multinom(
#'   data = acs_data,
#'   formula = fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
#'   replicate_weights = replicate_weights,
#'   pred_data = data.frame(AGE = 0:5, MULTYEAR = 2023)
#' )
generate_bootstrap_multinom <- function(data, formula, replicate_weights, pred_data,
                                        main_weights = NULL) {

  n_boot <- ncol(replicate_weights)

  cat("  [Bootstrap Multinom] Using", n_boot, "bootstrap replicate weights...\n")

  # Step 1: Fit main multinomial model
  cat("    [1/3] Fitting main multinomial model...\n")

  if (is.null(main_weights)) {
    main_weights <- rowMeans(replicate_weights)
  }

  # Add weights as column to avoid scoping issues
  data_with_wts <- data
  data_with_wts$.main_weights <- main_weights

  model_main <- nnet::multinom(
    formula = formula,
    data = data_with_wts,
    weights = .main_weights,
    trace = FALSE
  )

  # Get point estimates
  point_pred <- predict(model_main, newdata = pred_data, type = "probs")

  # Handle case where predictions is a vector (2 categories)
  if (is.vector(point_pred)) {
    point_pred <- cbind(1 - point_pred, point_pred)
    colnames(point_pred) <- model_main$lev
  }

  categories <- colnames(point_pred)
  cat("    Point estimates computed (", nrow(point_pred), " ages x ",
      length(categories), " categories)\n", sep = "")

  # Extract starting weights (Wts from main model)
  start_wts <- model_main$wts
  cat("    Starting weights extracted (", length(start_wts), " parameters)\n\n", sep = "")

  # Step 2: Generate replicate estimates using PARALLEL processing
  cat("    [2/3] Generating bootstrap estimates with starting weights...\n")

  # Configure parallel workers from config
  n_workers <- BOOTSTRAP_CONFIG$parallel_workers
  future::plan(future::multisession, workers = n_workers)
  cat("           Starting", n_workers, "parallel workers...\n")

  # Parallel bootstrap estimation with starting weights
  boot_results <- future.apply::future_lapply(1:n_boot, function(i) {
    # Add bootstrap weights as column to avoid scoping issues
    data_boot <- data
    data_boot$.boot_wts <- replicate_weights[, i]

    # Fit multinom with i-th bootstrap weight using starting weights
    model_boot <- nnet::multinom(
      formula = formula,
      data = data_boot,
      weights = .boot_wts,  # i-th replicate weights
      Wts = start_wts,  # ← STARTING WEIGHTS for speed
      trace = FALSE
    )

    # Get predictions
    pred_boot <- predict(model_boot, newdata = pred_data, type = "probs")

    # Handle 2-category case
    if (is.vector(pred_boot)) {
      pred_boot <- cbind(1 - pred_boot, pred_boot)
      colnames(pred_boot) <- model_boot$lev
    }

    # Return as matrix (n_ages x n_categories)
    pred_boot
  }, future.seed = TRUE, future.packages = c("nnet"))

  # Close workers after use
  future::plan(future::sequential)
  cat("           Workers closed\n")

  # Step 3: Convert list of matrices to 3D array
  cat("    [3/3] Converting to 3D array...\n")

  # Create array: (n_ages, n_categories, n_boot)
  n_ages <- nrow(pred_data)
  n_categories <- length(categories)
  boot_estimates <- array(
    data = unlist(boot_results),
    dim = c(n_ages, n_categories, n_boot),
    dimnames = list(
      age = pred_data$AGE,
      category = categories,
      replicate = 1:n_boot
    )
  )

  cat("    Bootstrap estimates: ", n_ages, " ages x ", n_categories,
      " categories x ", n_boot, " replicates\n\n", sep = "")

  # Create long-format point estimates
  point_estimates_long <- data.frame(
    age = rep(pred_data$AGE, each = n_categories),
    category = rep(categories, times = n_ages),
    estimate = as.vector(t(point_pred))
  )

  # Return results
  list(
    point_estimates = point_estimates_long,
    boot_estimates = boot_estimates,
    n_boot = n_boot,
    categories = categories
  )
}

# ============================================================================
# Function 3: Format Bootstrap Results for Saving
# ============================================================================

#' Format Bootstrap Results to Long Format for Database Storage
#'
#' Converts bootstrap results to long format with columns: age, estimand, replicate, estimate
#'
#' @param boot_result Result from generate_bootstrap_glm2()
#' @param ages Vector of ages (0-5)
#' @param estimand_name Name of estimand (e.g., "sex_male")
#'
#' @return Data frame with columns: age, estimand, replicate, estimate
format_bootstrap_results <- function(boot_result, ages, estimand_name) {

  n_ages <- length(ages)
  n_boot <- boot_result$n_boot

  # Create data frame for bootstrap estimates
  boot_long <- data.frame(
    age = rep(ages, times = n_boot),
    estimand = estimand_name,
    replicate = rep(1:n_boot, each = n_ages),
    estimate = as.numeric(boot_result$boot_estimates)
  )

  boot_long
}

#' Format Multinomial Bootstrap Results to Long Format
#'
#' Converts multinomial bootstrap results (3D array) to long format
#'
#' @param boot_result Result from generate_bootstrap_multinom()
#' @param ages Vector of ages (0-5)
#' @param estimand_prefix Prefix for estimand names (e.g., "fpl_")
#'
#' @return Data frame with columns: age, estimand, replicate, estimate
format_multinom_bootstrap_results <- function(boot_result, ages, estimand_prefix) {

  n_ages <- length(ages)
  n_categories <- length(boot_result$categories)
  n_boot <- boot_result$n_boot

  # Create long format from 3D array
  # Array dims: (n_ages, n_categories, n_boot)
  boot_array <- boot_result$boot_estimates

  # Convert 3D array to long format manually to ensure correct ordering
  # We need: for each replicate, for each age, for each category
  boot_list <- list()
  idx <- 1

  for (rep in 1:n_boot) {
    for (age_idx in 1:n_ages) {
      for (cat_idx in 1:n_categories) {
        boot_list[[idx]] <- data.frame(
          age = ages[age_idx],
          estimand = paste0(estimand_prefix, boot_result$categories[cat_idx]),
          replicate = rep,
          estimate = boot_array[age_idx, cat_idx, rep]
        )
        idx <- idx + 1
      }
    }
  }

  boot_long <- dplyr::bind_rows(boot_list)
  boot_long
}

# ============================================================================
# LOAD MESSAGE
# ============================================================================

cat("========================================\n")
cat("Bootstrap Helper Functions (glm2) Loaded\n")
cat("========================================\n")
cat("Available functions:\n")
cat("  - generate_bootstrap_glm2() - Binary GLM with starting values\n")
cat("  - generate_bootstrap_multinom() - Multinomial with starting weights\n")
cat("  - format_bootstrap_results() - Convert to long format\n")
cat("  - format_multinom_bootstrap_results() - Convert multinom to long format\n")
cat("\n")
cat("IMPORTANT: These functions use starting values for speed\n")
cat("  - glm2: Uses start = coef(main_model)\n")
cat("  - multinom: Uses Wts = main_model$wts\n")
cat("========================================\n\n")

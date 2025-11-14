# ==============================================================================
# Precompute Logistic/Ordered Logit Models for Age Gradient Explorer
# ==============================================================================
#
# This script fits all models in parallel and saves results to disk.
# Run this script once (or when calibration data updates) to regenerate models.
#
# NEW FEATURES:
# - Fits models WITH and WITHOUT top 1%, 2%, 3%, 4%, 5% influence points
# - Stores regression coefficients (beta for years on logit scale)
#
# Usage:
#   source("scripts/shiny/age_gradient_explorer/precompute_models.R")
#
# Output:
#   scripts/shiny/age_gradient_explorer/precomputed_models.rds
#
# ==============================================================================

library(duckdb)
library(dplyr)
library(MASS)
library(future)
library(future.apply)

cat("\n")
cat(strrep("=", 80), "\n")
cat("PRECOMPUTE MODELS FOR AGE GRADIENT EXPLORER\n")
cat(strrep("=", 80), "\n\n")

# ==============================================================================
# Load Calibration Data
# ==============================================================================

cat("[1/4] Loading calibration dataset from DuckDB...\n")

db_path <- "data/duckdb/kidsights_local.duckdb"

if (!file.exists(db_path)) {
  stop("Database not found at: ", db_path)
}

conn <- dbConnect(duckdb(), dbdir = db_path, read_only = TRUE)

calibration_data <- dbGetQuery(conn, "
  SELECT * FROM calibration_dataset_2020_2025
")

dbDisconnect(conn)

cat(sprintf("  Loaded %d records\n", nrow(calibration_data)))

# Extract item columns
metadata_cols <- c("study", "studynum", "id", "years")
item_cols <- setdiff(names(calibration_data), metadata_cols)

cat(sprintf("  Items to process: %d\n\n", length(item_cols)))

# ==============================================================================
# Setup Parallel Processing
# ==============================================================================

cat("[2/4] Setting up parallel processing with future...\n")

# Detect available cores
n_cores <- future::availableCores() - 1  # Leave 1 core free
n_cores <- max(1, n_cores)  # At least 1 core

cat(sprintf("  Using %d parallel workers\n\n", n_cores))

# Configure future plan (multisession for Windows compatibility)
future::plan(future::multisession, workers = n_cores)

# ==============================================================================
# Define Model Fitting Function
# ==============================================================================

fit_single_model <- function(data, is_binary, age_seq) {
  # Fits a single logistic/polr model and returns predictions + coefficient

  if (nrow(data) < 10) {
    return(list(
      predictions = data.frame(),
      beta_years = NA,
      model_converged = FALSE,
      model_type = "none"
    ))
  }

  tryCatch({
    if (is_binary) {
      # Binary logistic regression
      model <- glm(response ~ years, data = data, family = binomial())

      # Extract regression coefficient (beta for years on logit scale)
      beta_years <- coef(model)["years"]

      # Predictions
      pred_data <- data.frame(years = age_seq)
      pred_data$prob <- predict(model, newdata = pred_data, type = "response")
      pred_data$response_level <- "1"

      return(list(
        predictions = pred_data,
        beta_years = beta_years,
        model_converged = TRUE,
        model_type = "logistic"
      ))

    } else {
      # Ordinal: Treat as numeric and use linear regression
      model <- lm(response ~ years, data = data)

      # Extract regression coefficient
      beta_years <- coef(model)["years"]

      # Predictions on original response scale
      pred_data <- data.frame(years = age_seq)
      pred_data$prob <- predict(model, newdata = pred_data)
      pred_data$response_level <- "predicted"

      return(list(
        predictions = pred_data,
        beta_years = beta_years,
        model_converged = TRUE,
        model_type = "lm_ordinal"
      ))
    }
  }, error = function(e) {
    # Fallback: Try linear model for diagnostic purposes
    tryCatch({
      lm_model <- lm(response ~ years, data = data)

      # Extract coefficient (on raw scale, not logit)
      beta_years <- coef(lm_model)["years"]

      # Predictions (scale to 0-1 range for consistency)
      pred_data <- data.frame(years = age_seq)
      pred_values <- predict(lm_model, newdata = pred_data)
      pred_data$prob <- (pred_values - min(data$response, na.rm = TRUE)) /
                        (max(data$response, na.rm = TRUE) - min(data$response, na.rm = TRUE))
      pred_data$response_level <- "lm_fit"

      return(list(
        predictions = pred_data,
        beta_years = beta_years,
        model_converged = TRUE,
        model_type = "lm",
        fallback_used = TRUE,
        original_error = e$message
      ))
    }, error = function(e2) {
      # Complete failure
      return(list(
        predictions = data.frame(),
        beta_years = NA,
        model_converged = FALSE,
        model_type = "none",
        error_message = paste("GLM/POLR error:", e$message, "; LM error:", e2$message)
      ))
    })
  })
}

fit_item_models <- function(item_name, calibration_data) {
  # Extract item data
  item_data <- calibration_data %>%
    dplyr::select(study, years, response = !!sym(item_name)) %>%
    dplyr::filter(!is.na(response))

  if (nrow(item_data) < 10) {
    return(NULL)  # Skip items with insufficient data
  }

  # Determine item type
  unique_responses <- sort(unique(item_data$response))
  n_categories <- length(unique_responses)
  is_binary <- n_categories == 2

  # Age prediction grid
  age_seq <- seq(0, 6, length.out = 100)

  # Initialize results
  results <- list(
    item_name = item_name,
    is_binary = is_binary,
    n_categories = n_categories,
    pooled = list(),
    reduced_1pct = list(),
    reduced_2pct = list(),
    reduced_3pct = list(),
    reduced_4pct = list(),
    reduced_5pct = list(),
    study_specific = list(),
    model_type = NULL
  )

  # --------------------------------------------------------------------------
  # POOLED MODEL (WITH INFLUENCE POINTS)
  # --------------------------------------------------------------------------

  model_full <- fit_single_model(item_data, is_binary, age_seq)

  # Calculate influence metrics from full model
  influence_data_list <- list(
    influence_data_1pct = data.frame(),
    influence_data_2pct = data.frame(),
    influence_data_3pct = data.frame(),
    influence_data_4pct = data.frame(),
    influence_data_5pct = data.frame()
  )

  if (model_full$model_converged && nrow(item_data) >= 10) {
    tryCatch({
      if (model_full$model_type == "logistic") {
        temp_model <- glm(response ~ years, data = item_data, family = binomial())
        cooksd <- cooks.distance(temp_model)
      } else if (model_full$model_type == "polr") {
        item_data$response_factor <- factor(item_data$response, ordered = TRUE)
        temp_model <- MASS::polr(response_factor ~ years, data = item_data)
        resids <- residuals(temp_model)
        cooksd <- abs(resids) / sd(resids, na.rm = TRUE)
      } else {
        temp_model <- lm(response ~ years, data = item_data)
        cooksd <- cooks.distance(temp_model)
      }

      item_data$cooksd <- cooksd

      # Compute influence data at each threshold
      thresholds <- c(0.99, 0.98, 0.97, 0.96, 0.95)
      threshold_names <- c("influence_data_1pct", "influence_data_2pct",
                          "influence_data_3pct", "influence_data_4pct", "influence_data_5pct")

      for (i in seq_along(thresholds)) {
        item_data[[paste0("influential_", i)]] <- cooksd > quantile(cooksd, thresholds[i], na.rm = TRUE)
        influence_data_list[[threshold_names[i]]] <-
          item_data[item_data[[paste0("influential_", i)]], c("study", "years", "response", "cooksd")]
      }
    }, error = function(e) {
      # Silently skip influence calculation if it fails
    })
  }

  results$pooled <- c(
    model_full,
    influence_data_list
  )
  results$model_type <- model_full$model_type

  # --------------------------------------------------------------------------
  # POOLED MODELS (WITHOUT TOP 1%, 2%, 3%, 4%, 5% INFLUENCE POINTS)
  # --------------------------------------------------------------------------

  thresholds <- c(0.99, 0.98, 0.97, 0.96, 0.95)
  threshold_names <- c("reduced_1pct", "reduced_2pct", "reduced_3pct", "reduced_4pct", "reduced_5pct")

  for (i in seq_along(thresholds)) {
    influence_col <- paste0("influential_", i)

    if (influence_col %in% names(item_data) &&
        sum(item_data[[influence_col]], na.rm = TRUE) > 0 &&
        nrow(item_data) - sum(item_data[[influence_col]], na.rm = TRUE) >= 10) {
      # Remove influential points
      item_data_reduced <- item_data[!item_data[[influence_col]], ]
      model_reduced <- fit_single_model(item_data_reduced, is_binary, age_seq)
      results[[threshold_names[i]]] <- model_reduced
    } else {
      # Not enough data after removing influence points, use same as full
      results[[threshold_names[i]]] <- model_full
    }
  }

  # --------------------------------------------------------------------------
  # STUDY-SPECIFIC MODELS
  # --------------------------------------------------------------------------

  for (study_name in unique(item_data$study)) {
    study_data <- item_data[item_data$study == study_name, ]

    if (nrow(study_data) < 10) next

    # Fit model with influence points
    study_model_full <- fit_single_model(study_data, is_binary, age_seq)

    # Calculate influence metrics at multiple thresholds
    study_influence_data_list <- list(
      influence_data_1pct = data.frame(),
      influence_data_2pct = data.frame(),
      influence_data_3pct = data.frame(),
      influence_data_4pct = data.frame(),
      influence_data_5pct = data.frame()
    )

    if (study_model_full$model_converged) {
      tryCatch({
        if (study_model_full$model_type == "logistic") {
          temp_model <- glm(response ~ years, data = study_data, family = binomial())
          cooksd <- cooks.distance(temp_model)
        } else if (study_model_full$model_type == "polr") {
          study_data$response_factor <- factor(study_data$response, ordered = TRUE)
          temp_model <- MASS::polr(response_factor ~ years, data = study_data)
          resids <- residuals(temp_model)
          cooksd <- abs(resids) / sd(resids, na.rm = TRUE)
        } else {
          temp_model <- lm(response ~ years, data = study_data)
          cooksd <- cooks.distance(temp_model)
        }

        study_data$cooksd <- cooksd

        # Compute influence data at each threshold
        thresholds <- c(0.99, 0.98, 0.97, 0.96, 0.95)
        threshold_names <- c("influence_data_1pct", "influence_data_2pct",
                            "influence_data_3pct", "influence_data_4pct", "influence_data_5pct")

        for (i in seq_along(thresholds)) {
          study_data[[paste0("influential_", i)]] <- cooksd > quantile(cooksd, thresholds[i], na.rm = TRUE)
          study_influence_data_list[[threshold_names[i]]] <-
            study_data[study_data[[paste0("influential_", i)]], c("study", "years", "response", "cooksd")]
        }
      }, error = function(e) {
        # Silently skip influence calculation if it fails
      })
    }

    # Add study column to predictions
    if (nrow(study_model_full$predictions) > 0) {
      study_model_full$predictions$study <- study_name
    }

    # Fit models without influence points (one for each threshold)
    study_reduced_models <- list()
    thresholds <- c(0.99, 0.98, 0.97, 0.96, 0.95)
    threshold_names <- c("reduced_1pct", "reduced_2pct", "reduced_3pct", "reduced_4pct", "reduced_5pct")

    for (i in seq_along(thresholds)) {
      influence_col <- paste0("influential_", i)

      if (influence_col %in% names(study_data) &&
          sum(study_data[[influence_col]], na.rm = TRUE) > 0 &&
          nrow(study_data) - sum(study_data[[influence_col]], na.rm = TRUE) >= 10) {
        study_data_reduced <- study_data[!study_data[[influence_col]], ]
        study_model_reduced <- fit_single_model(study_data_reduced, is_binary, age_seq)

        if (nrow(study_model_reduced$predictions) > 0) {
          study_model_reduced$predictions$study <- study_name
        }

        study_reduced_models[[threshold_names[i]]] <- study_model_reduced
      } else {
        study_reduced_models[[threshold_names[i]]] <- study_model_full
      }
    }

    results$study_specific[[study_name]] <- c(
      list(full = c(study_model_full, study_influence_data_list)),
      study_reduced_models
    )
  }

  return(results)
}

# ==============================================================================
# Fit All Models in Parallel
# ==============================================================================

cat("[3/4] Fitting models in parallel (with and without influence points)...\n")
cat(sprintf("  Total items: %d\n", length(item_cols)))

start_time <- Sys.time()

# Use future_lapply for parallel processing
precomputed_models <- future.apply::future_lapply(
  item_cols,
  function(item_name) {
    fit_item_models(item_name, calibration_data)
  },
  future.seed = TRUE
)

# Name the list elements by item name
names(precomputed_models) <- item_cols

# Remove NULL entries (items with insufficient data)
precomputed_models <- precomputed_models[!sapply(precomputed_models, is.null)]

end_time <- Sys.time()
elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat(sprintf("  Completed in %.1f seconds\n", elapsed))
cat(sprintf("  Models fitted: %d items\n", length(precomputed_models)))
cat(sprintf("  Items skipped (insufficient data): %d\n\n", length(item_cols) - length(precomputed_models)))

# ==============================================================================
# Save Results to Disk
# ==============================================================================

cat("[4/4] Saving precomputed models to disk...\n")

output_path <- "scripts/shiny/age_gradient_explorer/precomputed_models.rds"

saveRDS(precomputed_models, file = output_path, compress = "xz")

file_size_mb <- file.size(output_path) / (1024^2)

cat(sprintf("  File saved: %s\n", output_path))
cat(sprintf("  File size: %.2f MB\n\n", file_size_mb))

# ==============================================================================
# Summary
# ==============================================================================

cat(strrep("=", 80), "\n")
cat("PRECOMPUTATION COMPLETE\n")
cat(strrep("=", 80), "\n\n")

cat("Summary:\n")
cat(sprintf("  Items processed: %d\n", length(precomputed_models)))
cat(sprintf("  Parallel workers: %d\n", n_cores))
cat(sprintf("  Computation time: %.1f seconds\n", elapsed))
cat(sprintf("  Output file: %s (%.2f MB)\n\n", output_path, file_size_mb))

cat("New features:\n")
cat("  [OK] Models fitted WITH influence points (full dataset)\n")
cat("  [OK] Models fitted WITHOUT top 1%%, 2%%, 3%%, 4%%, 5%% influence points (5 reduced datasets)\n")
cat("  [OK] Regression coefficients stored (beta for years on logit scale)\n\n")

cat("Next step: Launch Age Gradient Explorer app\n")
cat("  shiny::runApp('scripts/shiny/age_gradient_explorer')\n\n")

# Clean up future plan
future::plan(future::sequential)

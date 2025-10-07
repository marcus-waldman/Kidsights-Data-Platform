# Bootstrap Helper Functions for NE25 Raking Targets
# Created: October 2025
# Purpose: Generate bootstrap replicate weights for uncertainty quantification

library(survey)
library(svrep)
library(dplyr)
library(future)
library(future.apply)

# Configure parallel processing memory limit
# Set to 128 GB to allow large bootstrap design objects + function closures
# Bootstrap design (~200 MB) + function closures (~1 GB) need substantial headroom
# Increased for 16-core parallel processing
max_globals_bytes <- 128 * 1024^3  # 128 GB

options(future.globals.maxSize = max_globals_bytes)

cat("\n========================================\n")
cat("Parallel Processing Configuration\n")
cat("========================================\n")
cat("future.globals.maxSize:", round(max_globals_bytes / 1024^3, 1), "GB\n")
cat("========================================\n\n")

#' Generate Bootstrap Replicates for ACS Estimates
#'
#' Creates bootstrap replicate estimates for survey-weighted GLM predictions
#' using a SHARED bootstrap design (created once for all estimands)
#'
#' @param boot_design Bootstrap design object (from svrep::as_bootstrap_design)
#'   This should be the SHARED bootstrap design loaded from acs_bootstrap_design.rds
#' @param formula Model formula (e.g., outcome ~ age_factor + year)
#' @param pred_data Data frame with prediction covariates
#' @param family Model family (default quasibinomial())
#'
#' @return List with:
#'   - point_estimates: Vector of point estimates for each row in pred_data
#'   - boot_estimates: Matrix of bootstrap estimates (nrow = nrow(pred_data), ncol = n_boot)
#'   - n_boot: Number of replicates in the bootstrap design
#'
#' @examples
#' # Load shared bootstrap design (created by 01a_create_acs_bootstrap_design.R)
#' boot_design <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")
#'
#' # Generate bootstrap estimates using SHARED replicate weights
#' result <- generate_acs_bootstrap(boot_design, outcome ~ age_factor, pred_data)
#'
generate_acs_bootstrap <- function(boot_design, formula, pred_data,
                                   family = quasibinomial()) {

  # Get number of replicates from bootstrap design
  n_boot <- ncol(boot_design$repweights)

  cat("  [Bootstrap] Using shared replicate weights (", n_boot, " replicates)...\n", sep = "")

  # Step 1: Fit model on original design (from boot_design)
  cat("    [1/3] Fitting model on original design...\n")
  model_orig <- survey::svyglm(
    formula = formula,
    design = boot_design,
    family = family
  )

  # Get point estimates
  point_est <- predict(model_orig, newdata = pred_data, type = "response")
  cat("    [2/3] Point estimates computed (n =", length(point_est), ")\n")

  # Step 2: Generate replicate estimates using PARALLEL processing
  cat("    [3/3] Generating replicate estimates from shared bootstrap design...\n")

  # Configure parallel workers locally (16 cores = half of 32 logical processors)
  n_workers <- 16
  future::plan(future::multisession, workers = n_workers)
  cat("           Starting", n_workers, "parallel workers...\n")

  # Parallel bootstrap estimation using future_lapply
  # Pass the full boot_design object to workers (simpler and more reliable)
  boot_est_list <- future.apply::future_lapply(1:n_boot, function(i) {
    # Create a copy of the bootstrap design and update weights
    temp_design <- boot_design
    temp_design$pweights <- boot_design$repweights[, i]

    # Fit model and predict using updated design
    model_rep <- survey::svyglm(formula, design = temp_design, family = family)
    as.numeric(predict(model_rep, newdata = pred_data, type = "response"))
  }, future.seed = TRUE, future.packages = c("survey"))

  # IMPORTANT: Close workers after use to avoid corruption across scripts
  future::plan(future::sequential)
  cat("           Workers closed\n")

  # Combine into matrix (predictions as rows, replicates as columns)
  boot_estimates <- do.call(cbind, boot_est_list)

  cat("    Bootstrap estimates: ", nrow(boot_estimates), "predictions x",
      ncol(boot_estimates), "replicates (SHARED)\n")

  # Return results
  list(
    point_estimates = as.numeric(point_est),
    boot_estimates = boot_estimates,
    n_boot = n_boot
  )
}


#' Generate Bootstrap Replicates for NHIS Estimates
#'
#' Similar to ACS bootstrap but for NHIS data (simpler model structure)
#'
#' @param boot_design Bootstrap design object (from svrep::as_bootstrap_design)
#' @param formula Model formula
#' @param pred_data Prediction data
#' @param family Model family
#'
#' @return List with point estimates and bootstrap estimates
#'
generate_nhis_bootstrap <- function(boot_design, formula, pred_data,
                                    family = quasibinomial()) {
  # NHIS uses same logic as ACS
  generate_acs_bootstrap(boot_design, formula, pred_data, family)
}


#' Generate Bootstrap Replicates for NSCH Estimates
#'
#' Bootstrap for NSCH multi-year survey design estimates
#'
#' @param boot_design Bootstrap design object (from svrep::as_bootstrap_design)
#' @param formula Model formula
#' @param pred_data Prediction data
#' @param family Model family
#'
#' @return List with point estimates and bootstrap estimates
#'
generate_nsch_bootstrap <- function(boot_design, formula, pred_data,
                                    family = quasibinomial()) {
  # NSCH uses same logic as ACS
  generate_acs_bootstrap(boot_design, formula, pred_data, family)
}


#' Format Bootstrap Results for Saving
#'
#' Converts bootstrap results to long format for database storage
#'
#' @param boot_result Result from generate_*_bootstrap()
#' @param ages Vector of ages (0-5)
#' @param estimand_name Name of estimand
#'
#' @return Data frame with columns: age, estimand, replicate, estimate
#'
format_bootstrap_results <- function(boot_result, ages, estimand_name) {

  n_ages <- length(ages)
  n_boot <- boot_result$n_boot

  # Create data frame for bootstrap estimates
  boot_long <- data.frame(
    age = rep(ages, times = n_boot),
    estimand = estimand_name,
    replicate = rep(1:n_boot, each = n_ages),
    estimate = as.numeric(t(boot_result$boot_estimates))
  )

  boot_long
}

cat("\n========================================\n")
cat("Bootstrap Helper Functions Loaded\n")
cat("========================================\n")
cat("Available functions:\n")
cat("  - generate_acs_bootstrap(boot_design, ...)\n")
cat("  - generate_nhis_bootstrap(boot_design, ...)\n")
cat("  - generate_nsch_bootstrap(boot_design, ...)\n")
cat("  - format_bootstrap_results(...)\n")
cat("\n")
cat("IMPORTANT: All functions now require a\n")
cat("SHARED bootstrap design as first parameter.\n")
cat("Create once per data source, use for all estimands.\n")
cat("========================================\n\n")

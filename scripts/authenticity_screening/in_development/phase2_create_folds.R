# Phase 2: Create σ-Specific Stratified Folds
#
# This script:
#   1. For EACH σ_sum_w value from Phase 1b:
#      a. Extract weights (w) from penalized model fit
#      b. Filter to participants with w > 0.5
#      c. Create 16 age-stratified folds using filtered subset
#      d. Save fold assignments specific to that σ value
#
# Why σ-specific folds?
#   - Different σ values → different effective sample sizes (w > 0.5 threshold)
#   - Each σ evaluated on the participants it actually includes
#   - Age stratification ensures balanced folds within each subset
#
# Outputs (9 files, one per σ):
#   - fold_assignments_sigma_{idx}.rds: pid + fold for participants with w > 0.5
#   - fold_diagnostics_sigma_{idx}.rds: Fold balance statistics
#   - fold_metadata.rds: Sample size summary across all σ values

library(rstan)
library(dplyr)
library(ggplot2)

# Source utilities
source("scripts/authenticity_screening/in_development/gh_quadrature_utils.R")

#' Create σ-Specific Stratified Folds for All Penalized Models
#'
#' For each σ_sum_w value from Phase 1b, this function:
#'   1. Extracts weights (w) from the penalized model
#'   2. Filters to participants with w > 0.5
#'   3. Creates 16 age-stratified folds using the filtered subset
#'   4. Saves fold assignments specific to that σ value
#'
#' @param M_data Data frame with columns: person_id (1:N), age, item_id, response
#' @param fits_params List of extracted parameters from Phase 1b (length = number of σ values)
#' @param weight_threshold Minimum weight for inclusion (default: 0.5)
#' @param n_folds Number of folds (default: 16)
#' @param output_dir Directory to save results
#' @param create_plots Whether to create diagnostic plots (default: TRUE)
#' @return List with fold_metadata (sample sizes per σ)
#'
#' @details
#' NOTE: M_data uses person_id (1:N) as unique identifier.
#' This is created in 00_prepare_cv_data.R by mapping (pid, record_id) → person_id.
create_folds_phase2_multi_sigma <- function(M_data, fits_params,
                                             weight_threshold = 0.5,
                                             n_folds = 16,
                                             output_dir = "output/authenticity_cv",
                                             create_plots = TRUE) {

  cat("\n")
  cat("================================================================================\n")
  cat("  PHASE 2: Creating σ-Specific Stratified Folds\n")
  cat("================================================================================\n")
  cat("\n")

  # Extract σ values from fits_params
  sigma_values <- sapply(fits_params, function(x) x$sigma_sum_w)
  n_sigma <- length(sigma_values)

  cat(sprintf("Configuration:\n"))
  cat(sprintf("  Number of σ values: %d\n", n_sigma))
  cat(sprintf("  σ range: %.3f to %.3f\n", min(sigma_values), max(sigma_values)))
  cat(sprintf("  Weight threshold: w > %.2f\n", weight_threshold))
  cat(sprintf("  Number of folds: %d\n\n", n_folds))

  # Get unique person-level data (all participants)
  # person_id is artificial (1:N), already unique
  person_data_all <- M_data %>%
    dplyr::group_by(person_id) %>%
    dplyr::summarise(
      age = dplyr::first(age),
      .groups = "drop"
    ) %>%
    dplyr::arrange(person_id)

  N_total <- nrow(person_data_all)
  cat(sprintf("Total person-level observations: N = %d\n\n", N_total))

  # Initialize metadata storage
  fold_metadata <- data.frame(
    sigma_idx = integer(),
    sigma_sum_w = numeric(),
    N_total = integer(),
    N_filtered = integer(),
    N_excluded = integer(),
    pct_excluded = numeric()
  )

  # Loop over all σ values
  for (sigma_idx in 1:n_sigma) {
    sigma_sum_w <- sigma_values[sigma_idx]

    cat(sprintf("================================================================================\n"))
    cat(sprintf("  Processing σ_sum_w = %.3f (index %d/%d)\n", sigma_sum_w, sigma_idx, n_sigma))
    cat(sprintf("================================================================================\n\n"))

    # Extract weights for this σ
    w_all <- fits_params[[sigma_idx]]$w

    if (length(w_all) != N_total) {
      stop(sprintf("Mismatch: %d weights from σ_idx=%d but %d PIDs in M_data",
                   length(w_all), sigma_idx, N_total))
    }

    # Add weights to person data
    person_data <- person_data_all
    person_data$w <- w_all

    # Filter to w > threshold
    person_data_filtered <- person_data %>%
      dplyr::filter(w > weight_threshold)

    N_filtered <- nrow(person_data_filtered)
    N_excluded <- N_total - N_filtered
    pct_excluded <- 100 * N_excluded / N_total

    cat(sprintf("  Total participants: %d\n", N_total))
    cat(sprintf("  w > %.2f: %d (%.1f%%)\n", weight_threshold, N_filtered,
                100 * N_filtered / N_total))
    cat(sprintf("  Excluded: %d (%.1f%%)\n\n", N_excluded, pct_excluded))

    if (N_filtered < n_folds) {
      stop(sprintf("ERROR: Only %d participants remain after filtering, but need at least %d for %d folds",
                   N_filtered, n_folds, n_folds))
    }

    # Create age-stratified folds
    # Sort by age and number off consecutively to ensure age balance
    person_data_filtered <- person_data_filtered %>%
      dplyr::arrange(age) %>%
      dplyr::mutate(fold = rep(1:n_folds, length.out = N_filtered))

    # Compute fold diagnostics
    fold_diagnostics <- person_data_filtered %>%
      dplyr::group_by(fold) %>%
      dplyr::summarise(
        n = dplyr::n(),
        mean_w = mean(w),
        sd_w = sd(w),
        min_w = min(w),
        max_w = max(w),
        mean_age = mean(age),
        sd_age = sd(age),
        min_age = min(age),
        max_age = max(age),
        .groups = "drop"
      )

    cat("\n")
    cat("Fold diagnostics:\n")
    print(fold_diagnostics, n = n_folds)
    cat("\n")

    # Check balance
    cat("Balance checks:\n")
    cat(sprintf("  Fold size: %d to %d (ideal: %.0f)\n",
                min(fold_diagnostics$n), max(fold_diagnostics$n),
                N_filtered / n_folds))
    cat(sprintf("  Mean w: %.3f to %.3f (range: %.3f)\n",
                min(fold_diagnostics$mean_w),
                max(fold_diagnostics$mean_w),
                diff(range(fold_diagnostics$mean_w))))
    cat(sprintf("  Mean age: %.2f to %.2f (range: %.2f)\n",
                min(fold_diagnostics$mean_age),
                max(fold_diagnostics$mean_age),
                diff(range(fold_diagnostics$mean_age))))
    cat("\n")

    # Save results for this σ
    folds_file <- file.path(output_dir, sprintf("fold_assignments_sigma_%d.rds", sigma_idx))
    diagnostics_file <- file.path(output_dir, sprintf("fold_diagnostics_sigma_%d.rds", sigma_idx))
    person_data_file <- file.path(output_dir, sprintf("person_data_sigma_%d.rds", sigma_idx))

    # Save fold assignments (person_id, fold)
    fold_assignments <- person_data_filtered %>%
      dplyr::select(person_id, fold)

    saveRDS(fold_assignments, folds_file)
    saveRDS(fold_diagnostics, diagnostics_file)
    saveRDS(person_data_filtered, person_data_file)

    cat(sprintf("[OK] Saved fold assignments: %s\n", folds_file))
    cat(sprintf("[OK] Saved diagnostics: %s\n", diagnostics_file))
    cat(sprintf("[OK] Saved person data: %s\n\n", person_data_file))

    # Store metadata
    fold_metadata <- rbind(fold_metadata, data.frame(
      sigma_idx = sigma_idx,
      sigma_sum_w = sigma_sum_w,
      N_total = N_total,
      N_filtered = N_filtered,
      N_excluded = N_excluded,
      pct_excluded = pct_excluded
    ))
  }  # End loop over σ values

  # Save overall metadata
  metadata_file <- file.path(output_dir, "fold_metadata.rds")
  saveRDS(fold_metadata, metadata_file)

  cat("================================================================================\n")
  cat("  SUMMARY: Fold Metadata Across All σ Values\n")
  cat("================================================================================\n\n")
  print(fold_metadata, row.names = FALSE)
  cat("\n")
  cat(sprintf("[OK] Saved metadata: %s\n\n", metadata_file))

  cat("================================================================================\n")
  cat("  PHASE 2 COMPLETE\n")
  cat("================================================================================\n")
  cat(sprintf("  Created %d sets of fold assignments (one per σ value)\n", n_sigma))
  cat(sprintf("  Each set has %d folds\n", n_folds))
  cat(sprintf("  Total files created: %d\n", n_sigma * 3 + 1))
  cat("================================================================================\n\n")

  return(fold_metadata)
}


# Example usage (commented out - run interactively)
# M_data <- readRDS("data/temp/cv_M_data.rds")
# fits_params <- readRDS("output/authenticity_cv/fits_full_penalty_params.rds")
# fold_metadata <- create_folds_phase2_multi_sigma(M_data, fits_params)

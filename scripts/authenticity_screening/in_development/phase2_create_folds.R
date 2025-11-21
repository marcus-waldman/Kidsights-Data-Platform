# Phase 2: Extract logitwgt and Create Stratified Folds
#
# This script:
#   1. Extracts logitwgt from the σ_sum_w = 1.0 fit (middle of grid)
#   2. Creates 16 stratified folds by sorting on logitwgt + age
#   3. Validates fold balance
#
# Stratification ensures each fold has similar distributions of:
#   - Authenticity weights (prevents all inauthentic in one fold)
#   - Ages (prevents age confounding)
#
# Outputs:
#   - fold_assignments.rds: Vector of fold IDs (1-16) for each participant
#   - fold_diagnostics.rds: Summary statistics per fold

library(rstan)
library(dplyr)
library(ggplot2)

# Source utilities
source("scripts/authenticity_screening/in_development/gh_quadrature_utils.R")

#' Create Stratified Folds from Penalized Model Fit
#'
#' @param M_data Data frame with columns: pid, age (and others)
#' @param fits_params List of extracted parameters from Phase 1b
#' @param sigma_for_stratification Which σ value to use (default: 1.0)
#' @param n_folds Number of folds (default: 16)
#' @param output_dir Directory to save results
#' @param create_plots Whether to create diagnostic plots (default: TRUE)
#' @return Data frame with pid and fold assignment
create_folds_phase2 <- function(M_data, fits_params,
                                 sigma_for_stratification = 1.0,
                                 n_folds = 16,
                                 output_dir = "output/authenticity_cv",
                                 create_plots = TRUE) {

  cat("\n")
  cat("================================================================================\n")
  cat("  PHASE 2: Creating Stratified Folds\n")
  cat("================================================================================\n")
  cat("\n")

  # Find fit with closest sigma to target
  sigma_values <- sapply(fits_params, function(x) x$sigma_sum_w)
  idx <- which.min(abs(sigma_values - sigma_for_stratification))
  sigma_used <- sigma_values[idx]

  if (abs(sigma_used - sigma_for_stratification) > 0.01) {
    warning(sprintf("Requested σ = %.3f not found. Using σ = %.3f instead.",
                    sigma_for_stratification, sigma_used))
  }

  cat(sprintf("Using σ_sum_w = %.3f for stratification\n", sigma_used))
  cat(sprintf("Creating %d folds\n\n", n_folds))

  # Extract logitwgt and get unique person-level data
  logitwgt_all <- fits_params[[idx]]$logitwgt
  w_all <- fits_params[[idx]]$w

  # Get unique PIDs with age
  person_data <- M_data %>%
    dplyr::group_by(pid) %>%
    dplyr::summarise(
      age = dplyr::first(age),
      .groups = "drop"
    ) %>%
    dplyr::arrange(pid)

  if (length(logitwgt_all) != nrow(person_data)) {
    stop(sprintf("Mismatch: %d logitwgt values but %d unique PIDs",
                 length(logitwgt_all), nrow(person_data)))
  }

  # Add weights to person data
  person_data$logitwgt <- logitwgt_all
  person_data$w <- w_all

  cat(sprintf("Person-level data:\n"))
  cat(sprintf("  N = %d participants\n", nrow(person_data)))
  cat(sprintf("  logitwgt: mean = %.3f, sd = %.3f, range = [%.3f, %.3f]\n",
              mean(person_data$logitwgt), sd(person_data$logitwgt),
              min(person_data$logitwgt), max(person_data$logitwgt)))
  cat(sprintf("  w: mean = %.3f, sd = %.3f, range = [%.3f, %.3f]\n",
              mean(person_data$w), sd(person_data$w),
              min(person_data$w), max(person_data$w)))
  cat(sprintf("  age: mean = %.2f, sd = %.2f, range = [%.2f, %.2f]\n",
              mean(person_data$age), sd(person_data$age),
              min(person_data$age), max(person_data$age)))
  cat("\n")

  # Create stratified folds
  folds <- create_stratified_folds(
    logitwgt = person_data$logitwgt,
    age = person_data$age,
    n_folds = n_folds
  )

  person_data$fold <- folds

  # Compute fold diagnostics
  fold_diagnostics <- person_data %>%
    dplyr::group_by(fold) %>%
    dplyr::summarise(
      n = dplyr::n(),
      mean_logitwgt = mean(logitwgt),
      sd_logitwgt = sd(logitwgt),
      mean_w = mean(w),
      sd_w = sd(w),
      n_excluded = sum(w < 0.1),
      n_included = sum(w > 0.9),
      mean_age = mean(age),
      sd_age = sd(age),
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
              nrow(person_data) / n_folds))
  cat(sprintf("  Mean logitwgt: %.3f to %.3f (range: %.3f)\n",
              min(fold_diagnostics$mean_logitwgt),
              max(fold_diagnostics$mean_logitwgt),
              diff(range(fold_diagnostics$mean_logitwgt))))
  cat(sprintf("  Mean w: %.3f to %.3f (range: %.3f)\n",
              min(fold_diagnostics$mean_w),
              max(fold_diagnostics$mean_w),
              diff(range(fold_diagnostics$mean_w))))
  cat(sprintf("  Mean age: %.2f to %.2f (range: %.2f)\n",
              min(fold_diagnostics$mean_age),
              max(fold_diagnostics$mean_age),
              diff(range(fold_diagnostics$mean_age))))
  cat("\n")

  # Save results
  folds_file <- file.path(output_dir, "fold_assignments.rds")
  diagnostics_file <- file.path(output_dir, "fold_diagnostics.rds")
  person_data_file <- file.path(output_dir, "person_data_with_folds.rds")

  # Just save fold vector (for easy merging)
  fold_assignments <- data.frame(
    pid = person_data$pid,
    fold = person_data$fold
  )

  saveRDS(fold_assignments, folds_file)
  saveRDS(fold_diagnostics, diagnostics_file)
  saveRDS(person_data, person_data_file)

  cat(sprintf("[OK] Saved fold assignments: %s\n", folds_file))
  cat(sprintf("[OK] Saved diagnostics: %s\n", diagnostics_file))
  cat(sprintf("[OK] Saved person data: %s\n", person_data_file))
  cat("\n")

  # Create diagnostic plots
  if (create_plots) {
    cat("Creating diagnostic plots...\n")

    plots_dir <- file.path(output_dir, "plots")
    if (!dir.exists(plots_dir)) {
      dir.create(plots_dir, recursive = TRUE)
    }

    # Plot 1: Distribution of logitwgt by fold
    p1 <- ggplot2::ggplot(person_data, ggplot2::aes(x = factor(fold), y = logitwgt)) +
      ggplot2::geom_boxplot(fill = "steelblue", alpha = 0.6) +
      ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
      ggplot2::labs(
        title = "Distribution of logitwgt by Fold",
        subtitle = sprintf("σ_sum_w = %.3f used for stratification", sigma_used),
        x = "Fold",
        y = "logitwgt"
      ) +
      ggplot2::theme_minimal()

    ggplot2::ggsave(file.path(plots_dir, "fold_logitwgt_distribution.png"),
                    p1, width = 10, height = 6, dpi = 300)

    # Plot 2: Distribution of age by fold
    p2 <- ggplot2::ggplot(person_data, ggplot2::aes(x = factor(fold), y = age)) +
      ggplot2::geom_boxplot(fill = "darkgreen", alpha = 0.6) +
      ggplot2::labs(
        title = "Distribution of Age by Fold",
        x = "Fold",
        y = "Age (years)"
      ) +
      ggplot2::theme_minimal()

    ggplot2::ggsave(file.path(plots_dir, "fold_age_distribution.png"),
                    p2, width = 10, height = 6, dpi = 300)

    # Plot 3: Fold diagnostics (means)
    p3_data <- fold_diagnostics %>%
      tidyr::pivot_longer(
        cols = c(mean_logitwgt, mean_w, mean_age),
        names_to = "metric",
        values_to = "value"
      )

    p3 <- ggplot2::ggplot(p3_data, ggplot2::aes(x = factor(fold), y = value)) +
      ggplot2::geom_col(fill = "coral", alpha = 0.7) +
      ggplot2::facet_wrap(~ metric, scales = "free_y", ncol = 1) +
      ggplot2::labs(
        title = "Fold-Level Summary Statistics",
        x = "Fold",
        y = "Mean Value"
      ) +
      ggplot2::theme_minimal()

    ggplot2::ggsave(file.path(plots_dir, "fold_summary_stats.png"),
                    p3, width = 10, height = 8, dpi = 300)

    cat(sprintf("[OK] Saved plots to: %s\n", plots_dir))
    cat("\n")
  }

  cat("================================================================================\n")
  cat("  PHASE 2 COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  return(fold_assignments)
}


# Example usage (commented out - run interactively)
# fits_params <- readRDS("output/authenticity_cv/fits_full_penalty_params.rds")
# fold_assignments <- create_folds_phase2(M_data, fits_params)

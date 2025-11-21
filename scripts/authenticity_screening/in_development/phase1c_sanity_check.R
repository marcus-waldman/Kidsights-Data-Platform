# Phase 1c: Sanity Check - Low Weights Should Correspond to Extreme Eta
#
# This diagnostic phase validates that the authenticity screening model is
# working as intended by checking that low weights (w < 0.5) are assigned to
# participants with extreme person effects as measured by Mahalanobis distance.
#
# The Mahalanobis distance accounts for the covariance structure between
# eta_psychosocial and eta_developmental, providing a statistically principled
# measure of extremity: D² = (η - μ)ᵀ Σ⁻¹ (η - μ)
#
# Inputs:
#   - fit0_params: Base model parameters (Phase 1a)
#   - fits_params: List of penalized model parameters (Phase 1b)
#
# Outputs:
#   - Bivariate scatter plots with Mahalanobis distance contours
#   - Summary statistics table
#   - Diagnostic pass/fail assessment

library(ggplot2)
library(dplyr)

#' Run Phase 1c Sanity Check
#'
#' @param fit0_params List with base model parameters (tau, beta1, delta, eta_*)
#' @param fits_params List of penalized model parameters (one per sigma value)
#' @param sigma_grid Vector of sigma_sum_w values
#' @param output_dir Directory to save diagnostic plots
#' @param weight_threshold Threshold for low weights (default: 0.5)
#' @param eta_threshold Threshold for extreme Mahalanobis distance (default: 3.0)
#' @return List with diagnostic_summary and pass/fail status
run_sanity_check <- function(fit0_params, fits_params, sigma_grid,
                               output_dir = "output/authenticity_cv",
                               weight_threshold = 0.5,
                               eta_threshold = 3.0) {

  cat("\n")
  cat("================================================================================\n")
  cat("  PHASE 1c: Sanity Check (Weight vs Eta Correspondence)\n")
  cat("================================================================================\n")
  cat("\n")

  # Create plots directory
  plots_dir <- file.path(output_dir, "plots")
  if (!dir.exists(plots_dir)) {
    dir.create(plots_dir, recursive = TRUE)
  }

  # Extract eta scores from base model (Phase 1a)
  eta_psychosocial <- fit0_params$eta_psychosocial
  eta_developmental <- fit0_params$eta_developmental

  N <- length(eta_psychosocial)

  # Create eta matrix for Mahalanobis distance computation
  eta_matrix <- cbind(eta_psychosocial, eta_developmental)

  # Compute covariance matrix and center
  eta_center <- colMeans(eta_matrix)
  eta_cov <- cov(eta_matrix)
  eta_cor <- cor(eta_matrix)[1, 2]

  # Compute Mahalanobis distance for each person
  # D² = (η - μ)ᵀ Σ⁻¹ (η - μ)
  mahal_dist_sq <- mahalanobis(eta_matrix, center = eta_center, cov = eta_cov)
  mahal_dist <- sqrt(mahal_dist_sq)

  cat(sprintf("Base model (Phase 1a) person effects:\n"))
  cat(sprintf("  N = %d participants\n", N))
  cat(sprintf("  eta_psychosocial: mean = %.3f, sd = %.3f\n",
              mean(eta_psychosocial), sd(eta_psychosocial)))
  cat(sprintf("  eta_developmental: mean = %.3f, sd = %.3f\n",
              mean(eta_developmental), sd(eta_developmental)))
  cat(sprintf("  Correlation (eta_psych, eta_dev): %.3f\n", eta_cor))
  cat(sprintf("  Mahalanobis distance: mean = %.3f, median = %.3f, max = %.3f\n",
              mean(mahal_dist), median(mahal_dist), max(mahal_dist)))
  cat(sprintf("  Chi-squared(2) p = 0.01 threshold: D > %.3f (D² > %.3f)\n",
              sqrt(qchisq(0.99, df = 2)), qchisq(0.99, df = 2)))
  cat("\n")

  # Initialize summary table
  diagnostic_summary <- data.frame(
    sigma_sum_w = numeric(),
    n_low_weight = integer(),
    pct_low_weight = numeric(),
    n_extreme_eta = integer(),
    n_low_w_and_extreme_eta = integer(),
    precision = numeric(),  # P(D > threshold | w < threshold)
    recall = numeric(),     # P(w < threshold | D > threshold)
    cor_w_mahal = numeric()
  )

  # Process each sigma value
  for (i in seq_along(fits_params)) {
    params <- fits_params[[i]]
    sigma_sum_w <- params$sigma_sum_w

    cat(sprintf("Processing σ_sum_w = %.3f...\n", sigma_sum_w))

    # Extract weights from penalized model
    w <- params$w

    if (length(w) != N) {
      warning(sprintf("Length mismatch: w (%d) != eta (%d). Skipping.", length(w), N))
      next
    }

    # Identify low-weight and extreme-eta participants
    # Using Mahalanobis distance threshold
    low_weight <- w < weight_threshold
    extreme_eta <- mahal_dist > eta_threshold

    n_low_weight <- sum(low_weight)
    n_extreme_eta <- sum(extreme_eta)
    n_low_w_and_extreme_eta <- sum(low_weight & extreme_eta)

    # Compute diagnostic metrics
    precision <- if (n_low_weight > 0) n_low_w_and_extreme_eta / n_low_weight else NA
    recall <- if (n_extreme_eta > 0) n_low_w_and_extreme_eta / n_extreme_eta else NA
    cor_w_mahal <- cor(w, mahal_dist, use = "complete.obs")

    # Add to summary table
    diagnostic_summary <- rbind(diagnostic_summary, data.frame(
      sigma_sum_w = sigma_sum_w,
      n_low_weight = n_low_weight,
      pct_low_weight = 100 * n_low_weight / N,
      n_extreme_eta = n_extreme_eta,
      n_low_w_and_extreme_eta = n_low_w_and_extreme_eta,
      precision = precision,
      recall = recall,
      cor_w_mahal = cor_w_mahal
    ))

    # Create diagnostic scatter plot
    plot_data <- data.frame(
      eta_psychosocial = eta_psychosocial,
      eta_developmental = eta_developmental,
      mahal_dist = mahal_dist,
      w = w,
      low_weight = low_weight,
      extreme_eta = extreme_eta
    )

    # Compute ellipse for Mahalanobis distance = eta_threshold
    # Using parameterization: (x - μ)ᵀ Σ⁻¹ (x - μ) = D²
    library(ellipse)
    ellipse_data <- ellipse(eta_cov, centre = eta_center, level = pchisq(eta_threshold^2, df = 2))

    p <- ggplot(plot_data, aes(x = eta_psychosocial, y = eta_developmental)) +
      # Add Mahalanobis distance contour
      geom_path(data = as.data.frame(ellipse_data),
                aes(x = V1, y = V2),
                color = "gray50", linetype = "dashed", linewidth = 0.8, inherit.aes = FALSE) +
      geom_point(aes(color = low_weight, size = low_weight, alpha = low_weight)) +
      scale_color_manual(
        name = sprintf("Weight < %.2f", weight_threshold),
        values = c("FALSE" = "steelblue", "TRUE" = "red"),
        labels = c("FALSE" = sprintf("\u2265 %.2f", weight_threshold),
                   "TRUE" = sprintf("< %.2f", weight_threshold))
      ) +
      scale_size_manual(values = c("FALSE" = 1.5, "TRUE" = 2), guide = "none") +
      scale_alpha_manual(values = c("FALSE" = 0.4, "TRUE" = 0.8), guide = "none") +
      labs(
        title = sprintf("Phase 1c Sanity Check: \u03c3_sum_w = %.3f", sigma_sum_w),
        subtitle = sprintf(
          "%d low-weight (%.1f%%) | %d extreme (D > %.1f) | Precision: %.1f%% | r(w, D) = %.3f",
          n_low_weight, 100 * n_low_weight / N, n_extreme_eta, eta_threshold,
          100 * precision, cor_w_mahal
        ),
        x = "\u03b7_psychosocial (person effect)",
        y = "\u03b7_developmental (person effect)",
        caption = sprintf("Dashed ellipse: Mahalanobis distance D = %.1f (accounts for covariance)", eta_threshold)
      ) +
      theme_minimal() +
      theme(
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(size = 9),
        plot.caption = element_text(size = 8, hjust = 0),
        legend.position = "bottom"
      ) +
      coord_fixed()

    # Save plot
    plot_file <- file.path(plots_dir, sprintf("phase1c_sanity_check_sigma_%.3f.png", sigma_sum_w))
    ggsave(plot_file, p, width = 8, height = 7, dpi = 150)

    cat(sprintf("  Low weight (w < %.2f): %d / %d (%.1f%%)\n",
                weight_threshold, n_low_weight, N, 100 * n_low_weight / N))
    cat(sprintf("  Extreme responders (D > %.1f): %d / %d (%.1f%%)\n",
                eta_threshold, n_extreme_eta, N, 100 * n_extreme_eta / N))
    cat(sprintf("  Overlap (low w AND extreme D): %d\n", n_low_w_and_extreme_eta))
    cat(sprintf("  Precision (D > %.1f | w < %.2f): %.1f%%\n",
                eta_threshold, weight_threshold, 100 * precision))
    cat(sprintf("  Correlation (w, D_Mahalanobis): %.3f\n", cor_w_mahal))
    cat(sprintf("  [OK] Saved plot: %s\n", basename(plot_file)))
    cat("\n")
  }

  # Overall assessment
  cat("================================================================================\n")
  cat("  DIAGNOSTIC SUMMARY\n")
  cat("================================================================================\n")
  cat("\n")

  print(diagnostic_summary, row.names = FALSE, digits = 3)
  cat("\n")

  # Pass/fail criteria
  min_precision <- min(diagnostic_summary$precision, na.rm = TRUE)
  mean_cor_mahal <- mean(diagnostic_summary$cor_w_mahal, na.rm = TRUE)

  cat("Pass/Fail Criteria:\n")
  cat(sprintf("  1. Minimum precision (D > threshold | w < threshold): %.1f%% ", 100 * min_precision))
  if (min_precision > 0.7) {
    cat("[PASS: > 70%]\n")
    precision_pass <- TRUE
  } else {
    cat("[FAIL: < 70%]\n")
    precision_pass <- FALSE
  }

  cat(sprintf("  2. Mean correlation (w, D_Mahalanobis): %.3f ", mean_cor_mahal))
  if (mean_cor_mahal < -0.5) {
    cat("[PASS: strongly negative]\n")
    cor_pass <- TRUE
  } else if (mean_cor_mahal < -0.3) {
    cat("[WARNING: moderately negative]\n")
    cor_pass <- TRUE
  } else {
    cat("[FAIL: not sufficiently negative]\n")
    cor_pass <- FALSE
  }

  overall_pass <- precision_pass && cor_pass

  cat("\n")
  if (overall_pass) {
    cat("[OK] PHASE 1c PASSED: Model correctly assigns low weights to extreme responders\n")
    cat("     (using Mahalanobis distance to account for covariance structure)\n")
  } else {
    cat("[WARNING] PHASE 1c FAILED: Model may not be functioning as intended\n")
    cat("          Review diagnostic plots before proceeding to Phase 2\n")
  }
  cat("\n")

  cat("================================================================================\n")
  cat("  PHASE 1c COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  return(list(
    diagnostic_summary = diagnostic_summary,
    overall_pass = overall_pass,
    precision_pass = precision_pass,
    cor_pass = cor_pass
  ))
}


# Example usage (commented out - run interactively)
# fit0_params <- readRDS("output/authenticity_cv/fit0_params.rds")
# fits_params <- readRDS("output/authenticity_cv/fits_full_penalty_params.rds")
# sigma_grid <- 2^(seq(-1, 1, by = 0.25))
# results <- run_sanity_check(fit0_params, fits_params, sigma_grid)

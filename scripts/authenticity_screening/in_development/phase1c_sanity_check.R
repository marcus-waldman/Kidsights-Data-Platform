# Phase 1c: Sanity Check - Low Weights Should Correspond to Extreme Eta
#
# This diagnostic phase validates that the authenticity screening model is
# working as intended by checking that low weights (w < 0.5) are assigned to
# participants with extreme person effects as measured by Robust Mahalanobis distance.
#
# The Robust Mahalanobis distance uses the Minimum Covariance Determinant (MCD)
# estimator to compute robust center and covariance, accounting for skewness and
# outliers in the person effects distribution: D² = (η - μ_robust)ᵀ Σ_robust⁻¹ (η - μ_robust)
#
# Inputs:
#   - fit0_params: Base model parameters (Phase 1a)
#   - fits_params: List of penalized model parameters (Phase 1b)
#
# Outputs:
#   - Bivariate scatter plots with Robust Mahalanobis distance contours
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
#' @param eta_threshold_prob Probability level for extreme Mahalanobis distance (default: 0.99)
#' @return List with diagnostic_summary and pass/fail status
run_sanity_check <- function(fit0_params, fits_params, sigma_grid,
                               output_dir = "output/authenticity_cv",
                               weight_threshold = 0.5,
                               eta_threshold_prob = 0.99) {

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

  # Compute robust covariance matrix and center using MCD estimator
  library(robustbase)
  cat(sprintf("Computing robust location and covariance (MCD estimator)...\n"))
  mcd_result <- robustbase::covMcd(eta_matrix, alpha = 0.75)

  eta_center_robust <- mcd_result$center
  eta_cov_robust <- mcd_result$cov

  # Also compute classical estimates for comparison
  eta_center_classical <- colMeans(eta_matrix)
  eta_cov_classical <- cov(eta_matrix)
  eta_cor_classical <- cor(eta_matrix)[1, 2]

  # Compute Robust Mahalanobis distance for each person
  # D² = (η - μ_robust)ᵀ Σ_robust⁻¹ (η - μ_robust)
  mahal_dist_sq <- mahalanobis(eta_matrix, center = eta_center_robust, cov = eta_cov_robust)
  mahal_dist <- sqrt(mahal_dist_sq)

  # Compute MCD-adjusted cutoffs for multiple probability levels
  prob_levels <- c(0.95, 0.99, 0.999)
  cutoff_levels <- data.frame(
    prob = prob_levels,
    cutoff = sqrt(qchisq(prob_levels, df = 2))
  )

  # Primary threshold for classification (user-specified)
  eta_threshold <- sqrt(qchisq(eta_threshold_prob, df = 2))

  cat(sprintf("\nBase model (Phase 1a) person effects:\n"))
  cat(sprintf("  N = %d participants\n", N))
  cat(sprintf("  eta_psychosocial: mean = %.3f, sd = %.3f\n",
              mean(eta_psychosocial), sd(eta_psychosocial)))
  cat(sprintf("  eta_developmental: mean = %.3f, sd = %.3f\n",
              mean(eta_developmental), sd(eta_developmental)))
  cat(sprintf("  Correlation (eta_psych, eta_dev): %.3f (classical)\n", eta_cor_classical))
  cat(sprintf("\nRobust estimates (MCD, alpha=0.75):\n"))
  cat(sprintf("  Center (eta_psych): %.3f (classical: %.3f)\n",
              eta_center_robust[1], eta_center_classical[1]))
  cat(sprintf("  Center (eta_dev): %.3f (classical: %.3f)\n",
              eta_center_robust[2], eta_center_classical[2]))
  cat(sprintf("  Robust Mahalanobis distance: mean = %.3f, median = %.3f, max = %.3f\n",
              mean(mahal_dist), median(mahal_dist), max(mahal_dist)))
  cat(sprintf("\nRobust distance cutoffs (chi-squared approximation):\n"))
  for (i in 1:nrow(cutoff_levels)) {
    n_extreme <- sum(mahal_dist > cutoff_levels$cutoff[i])
    cat(sprintf("  p = %.3f: D > %.3f (%d participants, %.1f%%)\n",
                cutoff_levels$prob[i], cutoff_levels$cutoff[i],
                n_extreme, 100 * n_extreme / N))
  }
  cat(sprintf("\nUsing p = %.3f (D > %.3f) for classification\n", eta_threshold_prob, eta_threshold))
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
    cor_w_mahal = numeric(),
    skewness_weighted = numeric(),  # Weighted skewness
    z_skewness = numeric()  # Z-score of skewness
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

    # Extract skewness diagnostics from params (before creating plots)
    # Check if skewness diagnostics exist (backwards compatibility)
    has_skewness <- !is.null(params$z_skewness_final) && length(params$z_skewness_final) > 0

    if (has_skewness) {
      z_skewness <- params$z_skewness_final
      skewness_weighted <- params$skewness_weighted_final
    } else {
      z_skewness <- NA
      skewness_weighted <- NA
    }

    # Add to summary table
    diagnostic_summary <- rbind(diagnostic_summary, data.frame(
      sigma_sum_w = sigma_sum_w,
      n_low_weight = n_low_weight,
      pct_low_weight = 100 * n_low_weight / N,
      n_extreme_eta = n_extreme_eta,
      n_low_w_and_extreme_eta = n_low_w_and_extreme_eta,
      precision = precision,
      recall = recall,
      cor_w_mahal = cor_w_mahal,
      skewness_weighted = skewness_weighted,
      z_skewness = z_skewness
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

    # Compute multiple ellipses for different probability levels
    # Using parameterization: (x - μ_robust)ᵀ Σ_robust⁻¹ (x - μ_robust) = D²
    library(ellipse)

    # Create ellipse data for each probability level
    ellipse_list <- lapply(1:nrow(cutoff_levels), function(i) {
      prob <- cutoff_levels$prob[i]
      level <- prob
      ellipse_matrix <- ellipse(eta_cov_robust, centre = eta_center_robust, level = level)
      data.frame(
        eta_psychosocial = ellipse_matrix[, 1],
        eta_developmental = ellipse_matrix[, 2],
        prob = prob,
        prob_label = sprintf("p=%.3f", prob)
      )
    })
    ellipse_data <- dplyr::bind_rows(ellipse_list)

    # Find label positions (rightmost point on each ellipse)
    label_positions <- ellipse_data %>%
      dplyr::group_by(prob) %>%
      dplyr::slice_max(eta_psychosocial, n = 1) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(
        label = sprintf("p=%.3f", prob),
        hjust = 0,
        vjust = 0.5
      )

    p <- ggplot(plot_data, aes(x = eta_psychosocial, y = eta_developmental)) +
      # Add multiple Mahalanobis distance contours
      geom_path(data = ellipse_data,
                aes(x = eta_psychosocial, y = eta_developmental, group = prob, linetype = prob_label),
                color = "gray40", linewidth = 0.6, inherit.aes = FALSE) +
      scale_linetype_manual(
        name = "Robust Mahalanobis",
        values = c("p=0.950" = "dotted", "p=0.990" = "dashed", "p=0.999" = "solid")
      ) +
      # Add contour labels
      geom_text(data = label_positions,
                aes(x = eta_psychosocial, y = eta_developmental, label = label),
                hjust = -0.1, vjust = 0.5, size = 3, color = "gray30", inherit.aes = FALSE) +
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
          "%d low-weight (%.1f%%) | %d extreme (D_robust > %.2f, p=%.3f) | Precision: %.1f%% | r(w, D) = %.3f",
          n_low_weight, 100 * n_low_weight / N, n_extreme_eta, eta_threshold, eta_threshold_prob,
          100 * precision, cor_w_mahal
        ),
        x = "\u03b7_psychosocial (person effect)",
        y = "\u03b7_developmental (person effect)",
        caption = "Ellipse contours show Robust Mahalanobis distance (MCD estimator, alpha=0.75) at p=0.95, 0.99, 0.999"
      ) +
      theme_minimal() +
      theme(
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(size = 9),
        plot.caption = element_text(size = 8, hjust = 0),
        legend.position = "bottom",
        legend.box = "vertical"
      ) +
      coord_fixed()

    # Save scatter plot
    plot_file <- file.path(plots_dir, sprintf("phase1c_sanity_check_sigma_%.3f.png", sigma_sum_w))
    ggsave(plot_file, p, width = 8, height = 7, dpi = 150)

    # =========================================================================
    # SKEWNESS PENALTY DIAGNOSTIC PLOT (only if diagnostics available)
    # =========================================================================

    if (has_skewness) {
      # Extract t_std_soft from params (z_skewness and skewness_weighted already extracted above)
      t_std_soft <- params$t_std_soft_final

      # Create histogram of soft-clipped standardized t-statistics
      hist_data <- data.frame(t_std_soft = t_std_soft)

      # Generate N(0,1) density curve for overlay
      x_range <- seq(-4, 4, length.out = 200)
      normal_density <- data.frame(
        x = x_range,
        y = dnorm(x_range, mean = 0, sd = 1)
      )

      p_skew <- ggplot(hist_data, aes(x = t_std_soft)) +
        geom_histogram(aes(y = after_stat(density)), bins = 50,
                       fill = "steelblue", alpha = 0.6, color = "white") +
        geom_line(data = normal_density, aes(x = x, y = y),
                  color = "red", linewidth = 1, linetype = "dashed") +
        geom_vline(xintercept = 0, color = "black", linewidth = 0.8, linetype = "solid") +
        labs(
          title = sprintf("Skewness Penalty Diagnostic: \u03c3_sum_w = %.3f", sigma_sum_w),
          subtitle = sprintf(
            "Weighted skewness: %.4f | z-score: %.3f | Mean t: %.3f",
            skewness_weighted, z_skewness, mean(t_std_soft)
          ),
          x = "Soft-Clipped Standardized t-Statistic (t_std_soft_final)",
          y = "Density",
          caption = "Red dashed line: N(0,1) expected under symmetry | Vertical line: perfect symmetry (t=0)"
        ) +
        theme_minimal() +
        theme(
          plot.title = element_text(face = "bold"),
          plot.subtitle = element_text(size = 9),
          plot.caption = element_text(size = 8, hjust = 0)
        )

      # Save skewness diagnostic plot
      skew_plot_file <- file.path(plots_dir, sprintf("phase1c_skewness_sigma_%.3f.png", sigma_sum_w))
      ggsave(skew_plot_file, p_skew, width = 8, height = 6, dpi = 150)
    } else {
      skew_plot_file <- NULL  # No skewness plot for old fits
    }

    cat(sprintf("  Low weight (w < %.2f): %d / %d (%.1f%%)\n",
                weight_threshold, n_low_weight, N, 100 * n_low_weight / N))
    cat(sprintf("  Extreme responders (D_robust > %.1f): %d / %d (%.1f%%)\n",
                eta_threshold, n_extreme_eta, N, 100 * n_extreme_eta / N))
    cat(sprintf("  Overlap (low w AND extreme D): %d\n", n_low_w_and_extreme_eta))
    cat(sprintf("  Precision (D > %.1f | w < %.2f): %.1f%%\n",
                eta_threshold, weight_threshold, 100 * precision))
    cat(sprintf("  Correlation (w, D_robust): %.3f\n", cor_w_mahal))

    if (has_skewness) {
      cat(sprintf("  Weighted skewness: %.4f (z-score: %.3f)\n", skewness_weighted, z_skewness))
    }

    cat(sprintf("  [OK] Saved plots:\n"))
    cat(sprintf("      - %s\n", basename(plot_file)))

    if (has_skewness && !is.null(skew_plot_file)) {
      cat(sprintf("      - %s\n", basename(skew_plot_file)))
    }

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

  cat(sprintf("  2. Mean correlation (w, D_robust): %.3f ", mean_cor_mahal))
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
    cat("     (using Robust Mahalanobis distance with MCD estimator)\n")
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

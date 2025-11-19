#!/usr/bin/env Rscript

#' Create Diagnostic Plots for Authenticity Screening
#'
#' Generates comprehensive diagnostic plots for 2D IRT model and Cook's D influence:
#'
#' 2D IRT Parameter Diagnostics (Plots 1-4):
#'   1. Scatter plot: eta_psychosocial vs eta_developmental
#'   2. Marginal distribution of eta_psychosocial (histogram + density)
#'   3. Marginal distribution of eta_developmental (histogram + density)
#'   4. Bivariate density contour plot with correlation annotation
#'
#' Cook's D Influence Diagnostics (Plots 5-7):
#'   5. Histogram of Cook's D×N with influence thresholds
#'   6. Scatter: Cook's D×N vs lz (quadrant analysis)
#'   7. Influential participant classification bar chart
#'
#' Note: Uses full model eta estimates and LOOCV Cook's D for N=2,635 authentic

library(dplyr)
library(ggplot2)
library(patchwork)

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY SCREENING: DIAGNOSTIC PLOTS (AUTHENTIC PARTICIPANTS)\n")
cat("================================================================================\n")
cat("\n")

# ============================================================================
# PHASE 1: LOAD DATA
# ============================================================================

cat("=== PHASE 1: LOAD DATA ===\n\n")

cat("[Step 1/2] Loading full model parameters...\n")
params_full <- readRDS("results/full_model_params.rds")

cat(sprintf("      Loaded full model parameters (eta_correlation = %.3f)\n",
            params_full$eta_correlation))

cat("\n[Step 2/3] Loading authentic participant eta values...\n")
authentic_eta <- readRDS("results/full_model_eta_lookup.rds")

cat(sprintf("      Loaded: %d authentic participants\n", nrow(authentic_eta)))

# Calculate empirical correlation
cor_empirical <- cor(authentic_eta$authenticity_eta_psychosocial_full,
                      authentic_eta$authenticity_eta_developmental_full)

cat(sprintf("      Empirical correlation: %.3f\n", cor_empirical))
cat(sprintf("      Model correlation: %.3f\n", params_full$eta_correlation))
cat(sprintf("      Difference: %.3f\n", cor_empirical - params_full$eta_correlation))

# Calculate marginal SDs
sd_psychosocial <- sd(authentic_eta$authenticity_eta_psychosocial_full)
sd_developmental <- sd(authentic_eta$authenticity_eta_developmental_full)

cat("\n[Step 3/3] Loading Cook's D diagnostics...\n")
loocv_cooks_d <- readRDS("results/loocv_cooks_d.rds")

cat(sprintf("      Loaded: %d LOOCV results with Cook's D\n", nrow(loocv_cooks_d)))

# Summary statistics for Cook's D
cooks_d_scaled_valid <- loocv_cooks_d$cooks_d_scaled[!is.na(loocv_cooks_d$cooks_d_scaled)]
n_influential_4 <- sum(loocv_cooks_d$influential_4, na.rm = TRUE)
n_influential_N <- sum(loocv_cooks_d$influential_N, na.rm = TRUE)

cat(sprintf("      Cook's D×N range: [%.2f, %.2f]\n",
            min(cooks_d_scaled_valid), max(cooks_d_scaled_valid)))
cat(sprintf("      Highly influential (D×N > 4): %d participants (%.1f%%)\n",
            n_influential_4, 100 * n_influential_4 / length(cooks_d_scaled_valid)))
cat(sprintf("      Very high influence (D×N > %d): %d participants (%.1f%%)\n",
            nrow(loocv_cooks_d), n_influential_N, 100 * n_influential_N / length(cooks_d_scaled_valid)))

cat(sprintf("      SD(eta_psychosocial): %.3f (target: 1.0)\n", sd_psychosocial))
cat(sprintf("      SD(eta_developmental): %.3f (target: 1.0)\n", sd_developmental))

# ============================================================================
# PHASE 2: CREATE PLOTS
# ============================================================================

cat("\n=== PHASE 2: CREATE DIAGNOSTIC PLOTS ===\n\n")

# Create output directory
if (!dir.exists("results/plots")) {
  dir.create("results/plots", recursive = TRUE)
}

# Determine correlation strength
cor_strength <- ifelse(abs(params_full$eta_correlation) < 0.3, "weak",
                       ifelse(abs(params_full$eta_correlation) < 0.7, "moderate", "strong"))

cat("[Plot 1/7] Scatter plot: eta_psychosocial vs eta_developmental...\n")

p1 <- ggplot2::ggplot(authentic_eta,
                       ggplot2::aes(x = authenticity_eta_psychosocial_full,
                                    y = authenticity_eta_developmental_full)) +
  ggplot2::geom_point(alpha = 0.4, size = 2, color = "#2E86AB") +
  ggplot2::geom_smooth(method = "lm", se = TRUE, color = "#A23B72", linewidth = 1.5) +
  ggplot2::labs(
    title = "Two-Dimensional IRT: Psychosocial Problems vs Developmental Functioning",
    subtitle = sprintf("N=2,635 authentic participants | r=%.3f (%s) | Model eta_correlation=%.3f",
                       cor_empirical, cor_strength, params_full$eta_correlation),
    x = "Psychosocial Problems (eta[, 1])",
    y = "Developmental Functioning (eta[, 2])"
  ) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 16),
    plot.subtitle = ggplot2::element_text(size = 12, color = "gray30")
  ) +
  ggplot2::annotate("text", x = Inf, y = -Inf,
                    label = sprintf("LKJ(1) prior (uniform)\nMarginal SD: psych=%.2f, dev=%.2f",
                                    sd_psychosocial, sd_developmental),
                    hjust = 1.1, vjust = -0.5, size = 3.5, color = "gray50")

ggplot2::ggsave("results/plots/01_eta_scatter.png", p1, width = 10, height = 8, dpi = 300)
cat("      Saved: results/plots/01_eta_scatter.png\n")

cat("\n[Plot 2/7] Marginal distribution: eta_psychosocial...\n")

p2 <- ggplot2::ggplot(authentic_eta,
                       ggplot2::aes(x = authenticity_eta_psychosocial_full)) +
  ggplot2::geom_histogram(ggplot2::aes(y = ggplot2::after_stat(density)),
                          alpha = 0.6, fill = "#2E86AB", bins = 40, color = "white") +
  ggplot2::geom_density(color = "#A23B72", linewidth = 1.5) +
  ggplot2::stat_function(fun = dnorm, args = list(mean = 0, sd = 1),
                         linetype = "dashed", color = "black", linewidth = 1) +
  ggplot2::labs(
    title = "Marginal Distribution: Psychosocial Problems Dimension",
    subtitle = sprintf("N=2,635 | SD=%.3f (target: 1.0) | Dashed = N(0,1) reference",
                       sd_psychosocial),
    x = "Psychosocial Problems (eta[, 1])",
    y = "Density"
  ) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(size = 11, color = "gray30")
  )

ggplot2::ggsave("results/plots/02_eta_psychosocial_marginal.png", p2, width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/02_eta_psychosocial_marginal.png\n")

cat("\n[Plot 3/7] Marginal distribution: eta_developmental...\n")

p3 <- ggplot2::ggplot(authentic_eta,
                       ggplot2::aes(x = authenticity_eta_developmental_full)) +
  ggplot2::geom_histogram(ggplot2::aes(y = ggplot2::after_stat(density)),
                          alpha = 0.6, fill = "#2E86AB", bins = 40, color = "white") +
  ggplot2::geom_density(color = "#A23B72", linewidth = 1.5) +
  ggplot2::stat_function(fun = dnorm, args = list(mean = 0, sd = 1),
                         linetype = "dashed", color = "black", linewidth = 1) +
  ggplot2::labs(
    title = "Marginal Distribution: Developmental Functioning Dimension",
    subtitle = sprintf("N=2,635 | SD=%.3f (target: 1.0) | Dashed = N(0,1) reference",
                       sd_developmental),
    x = "Developmental Functioning (eta[, 2])",
    y = "Density"
  ) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(size = 11, color = "gray30")
  )

ggplot2::ggsave("results/plots/03_eta_developmental_marginal.png", p3, width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/03_eta_developmental_marginal.png\n")

cat("\n[Plot 4/7] Bivariate density contours...\n")

p4 <- ggplot2::ggplot(authentic_eta,
                       ggplot2::aes(x = authenticity_eta_psychosocial_full,
                                    y = authenticity_eta_developmental_full)) +
  ggplot2::geom_density_2d(color = "#2E86AB", linewidth = 0.8) +
  ggplot2::geom_point(alpha = 0.15, size = 1, color = "#2E86AB") +
  ggplot2::labs(
    title = "Bivariate Density: Two-Dimensional IRT Model",
    subtitle = sprintf("N=2,635 authentic | Contours show bivariate normal with r=%.3f",
                       cor_empirical),
    x = "Psychosocial Problems (eta[, 1])",
    y = "Developmental Functioning (eta[, 2])"
  ) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(size = 11, color = "gray30")
  ) +
  ggplot2::annotate("text", x = Inf, y = -Inf,
                    label = sprintf("LKJ(1) prior (uniform)\nEstimated r=%.3f (%s correlation)",
                                    params_full$eta_correlation, cor_strength),
                    hjust = 1.1, vjust = -0.5, size = 3.5, color = "gray50")

ggplot2::ggsave("results/plots/04_bivariate_density.png", p4, width = 10, height = 8, dpi = 300)
cat("      Saved: results/plots/04_bivariate_density.png\n")

# ============================================================================
# COOK'S D DIAGNOSTIC PLOTS
# ============================================================================

cat("\n[Plot 5/7] Cook's D histogram...\n")

p5 <- ggplot2::ggplot(loocv_cooks_d %>% dplyr::filter(!is.na(cooks_d_scaled)),
                       ggplot2::aes(x = cooks_d_scaled)) +
  ggplot2::geom_histogram(alpha = 0.7, fill = "#E07A5F", bins = 50, color = "white") +
  ggplot2::geom_vline(xintercept = 4, linetype = "dashed", color = "#D62828", linewidth = 1.2) +
  ggplot2::geom_vline(xintercept = nrow(loocv_cooks_d), linetype = "dotted", color = "#003049", linewidth = 1) +
  ggplot2::labs(
    title = "Cook's D Influence Diagnostics (Authentic Participants)",
    subtitle = sprintf("N=2,635 | %d highly influential (D×N > 4) | %d very high (D×N > N)",
                       n_influential_4, n_influential_N),
    x = "Cook's D × N (sample-size invariant)",
    y = "Count"
  ) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(size = 11, color = "gray30")
  ) +
  ggplot2::annotate("text", x = 4, y = Inf,
                    label = "D×N > 4\n(high influence)",
                    hjust = -0.1, vjust = 1.5, size = 3, color = "#D62828") +
  ggplot2::annotate("text", x = nrow(loocv_cooks_d), y = Inf,
                    label = sprintf("D×N > %d\n(very high)", nrow(loocv_cooks_d)),
                    hjust = -0.1, vjust = 1.5, size = 3, color = "#003049")

ggplot2::ggsave("results/plots/05_cooks_d_histogram.png", p5, width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/05_cooks_d_histogram.png\n")

cat("\n[Plot 6/7] Cook's D vs log-posterior z-score...\n")

p6 <- ggplot2::ggplot(loocv_cooks_d %>% dplyr::filter(!is.na(cooks_d_scaled) & !is.na(lz)),
                       ggplot2::aes(x = lz, y = cooks_d_scaled, color = influential_4)) +
  ggplot2::geom_point(alpha = 0.6, size = 2) +
  ggplot2::geom_hline(yintercept = 4, linetype = "dashed", color = "#D62828", linewidth = 1) +
  ggplot2::geom_vline(xintercept = -2, linetype = "dashed", color = "#457B9D", linewidth = 1) +
  ggplot2::scale_color_manual(
    values = c("FALSE" = "#2E86AB", "TRUE" = "#D62828"),
    labels = c("FALSE" = "Normal influence", "TRUE" = "High influence (D×N > 4)")
  ) +
  ggplot2::labs(
    title = "Cook's D vs Response Pattern Quality",
    subtitle = "Quadrant analysis: high influence + unusual pattern → potential inauthenticity",
    x = "Log-Posterior Z-Score (lz)",
    y = "Cook's D × N (influence)",
    color = "Influence Level"
  ) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(size = 11, color = "gray30"),
    legend.position = "bottom"
  ) +
  ggplot2::annotate("text", x = -2, y = Inf,
                    label = "Unusual\npattern\n(lz < -2)",
                    hjust = 1.2, vjust = 1.5, size = 3, color = "#457B9D") +
  ggplot2::annotate("rect", xmin = -Inf, xmax = -2, ymin = 4, ymax = Inf,
                    alpha = 0.05, fill = "#D62828")

ggplot2::ggsave("results/plots/06_cooks_d_vs_lz.png", p6, width = 10, height = 7, dpi = 300)
cat("      Saved: results/plots/06_cooks_d_vs_lz.png\n")

cat("\n[Plot 7/7] Influential participants flag distribution...\n")

# Create summary data frame for flag visualization
flag_summary <- data.frame(
  category = c("Normal influence", "High influence (D×N > 4)", "Very high (D×N > N)"),
  count = c(
    sum(!loocv_cooks_d$influential_4, na.rm = TRUE),
    sum(loocv_cooks_d$influential_4 & !loocv_cooks_d$influential_N, na.rm = TRUE),
    sum(loocv_cooks_d$influential_N, na.rm = TRUE)
  )
)

flag_summary$percentage <- 100 * flag_summary$count / sum(flag_summary$count)
flag_summary$category <- factor(flag_summary$category,
                                 levels = c("Normal influence", "High influence (D×N > 4)", "Very high (D×N > N)"))

p7 <- ggplot2::ggplot(flag_summary, ggplot2::aes(x = category, y = count, fill = category)) +
  ggplot2::geom_col(alpha = 0.8, color = "white", linewidth = 0.5) +
  ggplot2::geom_text(ggplot2::aes(label = sprintf("%d\n(%.1f%%)", count, percentage)),
                     vjust = -0.5, size = 4, fontface = "bold") +
  ggplot2::scale_fill_manual(
    values = c("Normal influence" = "#2E86AB",
               "High influence (D×N > 4)" = "#E07A5F",
               "Very high (D×N > N)" = "#D62828")
  ) +
  ggplot2::labs(
    title = "Influential Participant Classification",
    subtitle = "Quality assurance flags for Age Gradient Explorer integration",
    x = NULL,
    y = "Number of Participants"
  ) +
  ggplot2::theme_minimal(base_size = 14) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", size = 14),
    plot.subtitle = ggplot2::element_text(size = 11, color = "gray30"),
    legend.position = "none",
    axis.text.x = ggplot2::element_text(angle = 15, hjust = 1)
  ) +
  ggplot2::ylim(0, max(flag_summary$count) * 1.15)

ggplot2::ggsave("results/plots/07_influential_flags.png", p7, width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/07_influential_flags.png\n")

# ============================================================================
# PHASE 3: CREATE SUMMARY PANEL
# ============================================================================

cat("\n=== PHASE 3: CREATE SUMMARY PANELS ===\n\n")

cat("[Panel 1/2] 2D IRT diagnostic panel (2×2)...\n")

panel_eta <- (p1 + p4) / (p2 + p3) +
  patchwork::plot_annotation(
    title = "Authenticity Screening: Two-Dimensional IRT Parameter Diagnostics",
    subtitle = sprintf("Full Model (N=2,635) | LKJ(1) correlation prior (uniform) | eta_correlation = %.3f (%s)",
                       params_full$eta_correlation, cor_strength),
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(size = 18, face = "bold"),
      plot.subtitle = ggplot2::element_text(size = 13, color = "gray30")
    )
  )

ggplot2::ggsave("results/plots/00_eta_diagnostic_panel.png", panel_eta, width = 16, height = 14, dpi = 300)
cat("      Saved: results/plots/00_eta_diagnostic_panel.png\n")

cat("\n[Panel 2/2] Cook's D diagnostic panel (3-plot layout)...\n")

panel_cooks <- p5 / (p6 + p7) +
  patchwork::plot_annotation(
    title = "Authenticity Screening: Cook's D Influence Diagnostics",
    subtitle = sprintf("N=2,635 authentic | %d highly influential (D×N > 4) | Jackknife Hessian approximation",
                       n_influential_4),
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(size = 18, face = "bold"),
      plot.subtitle = ggplot2::element_text(size = 13, color = "gray30")
    )
  )

ggplot2::ggsave("results/plots/00_cooks_d_diagnostic_panel.png", panel_cooks, width = 16, height = 12, dpi = 300)
cat("      Saved: results/plots/00_cooks_d_diagnostic_panel.png\n")

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n")
cat("================================================================================\n")
cat("  DIAGNOSTIC PLOTS COMPLETE\n")
cat("================================================================================\n")
cat("\n")

cat("Summary:\n")
cat(sprintf("  Authentic participants: %d\n", nrow(authentic_eta)))
cat(sprintf("  Estimated correlation: %.3f (%s)\n", params_full$eta_correlation, cor_strength))
cat(sprintf("  Empirical correlation: %.3f\n", cor_empirical))
cat(sprintf("  Marginal SD (psychosocial): %.3f (target: 1.0)\n", sd_psychosocial))
cat(sprintf("  Marginal SD (developmental): %.3f (target: 1.0)\n", sd_developmental))
cat("\n")

cat("Cook's D Influence Diagnostics:\n")
cat(sprintf("  Cook's D×N range: [%.2f, %.2f]\n", min(cooks_d_scaled_valid), max(cooks_d_scaled_valid)))
cat(sprintf("  Highly influential (D×N > 4): %d participants (%.1f%%)\n",
            n_influential_4, 100 * n_influential_4 / length(cooks_d_scaled_valid)))
cat(sprintf("  Very high influence (D×N > %d): %d participants (%.1f%%)\n",
            nrow(loocv_cooks_d), n_influential_N, 100 * n_influential_N / length(cooks_d_scaled_valid)))
cat("\n")

cat("Output files:\n")
cat("  2D IRT Parameter Diagnostics:\n")
cat("    results/plots/01_eta_scatter.png\n")
cat("    results/plots/02_eta_psychosocial_marginal.png\n")
cat("    results/plots/03_eta_developmental_marginal.png\n")
cat("    results/plots/04_bivariate_density.png\n")
cat("    results/plots/00_eta_diagnostic_panel.png (2×2 summary)\n")
cat("\n")
cat("  Cook's D Influence Diagnostics:\n")
cat("    results/plots/05_cooks_d_histogram.png\n")
cat("    results/plots/06_cooks_d_vs_lz.png\n")
cat("    results/plots/07_influential_flags.png\n")
cat("    results/plots/00_cooks_d_diagnostic_panel.png (3-plot summary)\n")
cat("\n")

cat("Interpretation:\n")
cat("  2D IRT Model:\n")
cat("    - LKJ(1) prior is uniform over all correlations (non-informative)\n")
cat("    - Data-driven correlation estimation without prior assumptions\n")
cat("    - Marginal SDs > 1.0 indicate person variation in latent traits\n")
cat("    - Standard normal marginals maintain interpretability\n")
cat("\n")
cat("  Cook's D Diagnostics:\n")
cat("    - D×N > 4: Study-invariant threshold for high influence\n")
cat("    - High influence + low lz: Unusual AND influential (QA review)\n")
cat("    - Quadrant analysis identifies potential inauthenticity\n")
cat("    - Flags available for Age Gradient Explorer integration\n")
cat("\n")

cat("[OK] Diagnostic plots complete!\n")
cat("\n")

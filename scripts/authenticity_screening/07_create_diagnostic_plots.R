#!/usr/bin/env Rscript

#' Create Diagnostic Plots for Authenticity Screening
#'
#' Generates diagnostic plots focusing on IRT parameters (eta) for authentic participants:
#'   1. Scatter plot: eta_psychosocial vs eta_developmental
#'   2. Marginal distribution of eta_psychosocial (histogram + density)
#'   3. Marginal distribution of eta_developmental (histogram + density)
#'   4. Bivariate density contour plot with correlation annotation
#'
#' Note: Uses full model eta estimates for all 2,635 authentic participants

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

cat("\n[Step 2/2] Loading authentic participant eta values...\n")
authentic_eta <- readRDS("results/full_model_eta_lookup.rds")

cat(sprintf("      Loaded: %d authentic participants\n", nrow(authentic_eta)))

# Calculate empirical correlation
cor_empirical <- cor(authentic_eta$authenticity_eta_psychosocial,
                      authentic_eta$authenticity_eta_developmental)

cat(sprintf("      Empirical correlation: %.3f\n", cor_empirical))
cat(sprintf("      Model correlation: %.3f\n", params_full$eta_correlation))
cat(sprintf("      Difference: %.3f\n", cor_empirical - params_full$eta_correlation))

# Calculate marginal SDs
sd_psychosocial <- sd(authentic_eta$authenticity_eta_psychosocial)
sd_developmental <- sd(authentic_eta$authenticity_eta_developmental)

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

cat("[Plot 1/4] Scatter plot: eta_psychosocial vs eta_developmental...\n")

p1 <- ggplot2::ggplot(authentic_eta,
                       ggplot2::aes(x = authenticity_eta_psychosocial,
                                    y = authenticity_eta_developmental)) +
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

cat("\n[Plot 2/4] Marginal distribution: eta_psychosocial...\n")

p2 <- ggplot2::ggplot(authentic_eta,
                       ggplot2::aes(x = authenticity_eta_psychosocial)) +
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

cat("\n[Plot 3/4] Marginal distribution: eta_developmental...\n")

p3 <- ggplot2::ggplot(authentic_eta,
                       ggplot2::aes(x = authenticity_eta_developmental)) +
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

cat("\n[Plot 4/4] Bivariate density contours...\n")

p4 <- ggplot2::ggplot(authentic_eta,
                       ggplot2::aes(x = authenticity_eta_psychosocial,
                                    y = authenticity_eta_developmental)) +
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
# PHASE 3: CREATE SUMMARY PANEL
# ============================================================================

cat("\n=== PHASE 3: CREATE SUMMARY PANEL ===\n\n")

cat("[Panel] Combining plots into 2x2 summary panel...\n")

panel <- (p1 + p4) / (p2 + p3) +
  patchwork::plot_annotation(
    title = "Authenticity Screening: Two-Dimensional IRT Parameter Diagnostics",
    subtitle = sprintf("Full Model (N=2,635) | LKJ(1) correlation prior (uniform) | eta_correlation = %.3f (%s)",
                       params_full$eta_correlation, cor_strength),
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(size = 18, face = "bold"),
      plot.subtitle = ggplot2::element_text(size = 13, color = "gray30")
    )
  )

ggplot2::ggsave("results/plots/00_eta_diagnostic_panel.png", panel, width = 16, height = 14, dpi = 300)
cat("      Saved: results/plots/00_eta_diagnostic_panel.png\n")

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

cat("Output files:\n")
cat("  results/plots/01_eta_scatter.png\n")
cat("  results/plots/02_eta_psychosocial_marginal.png\n")
cat("  results/plots/03_eta_developmental_marginal.png\n")
cat("  results/plots/04_bivariate_density.png\n")
cat("  results/plots/00_eta_diagnostic_panel.png (2x2 summary)\n")
cat("\n")

cat("Interpretation:\n")
cat("  - LKJ(1) prior is uniform over all correlations (non-informative)\n")
cat("  - Data-driven correlation estimation without prior assumptions\n")
cat("  - Marginal SDs > 1.0 indicate person variation in latent traits\n")
cat("  - Standard normal marginals maintain interpretability\n")
cat("\n")

cat("[OK] Diagnostic plots complete!\n")
cat("\n")

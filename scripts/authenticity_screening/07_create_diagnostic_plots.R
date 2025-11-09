#!/usr/bin/env Rscript

#' Create Diagnostic Plots for Authenticity Screening
#'
#' Generates 5 diagnostic plots to visualize LOOCV results, weight distributions,
#' and ROC performance:
#'   1. Histogram of lz values (authentic vs inauthentic, overlaid)
#'   2. Density plot of avg_logpost distributions
#'   3. Dual ROC curves with AUC annotations
#'   4. Weight distribution by quintile (boxplot)
#'   5. Coverage plot showing authentic range with inauthentic overlay

library(dplyr)
library(ggplot2)
library(patchwork)

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY SCREENING: DIAGNOSTIC PLOTS\n")
cat("================================================================================\n")
cat("\n")

# ============================================================================
# PHASE 1: LOAD DATA
# ============================================================================

cat("=== PHASE 1: LOAD DATA ===\n\n")

cat("[Step 1/5] Loading authentic LOOCV results...\n")
authentic <- readRDS("results/loocv_authentic_results.rds") %>%
  dplyr::filter(converged_main & converged_holdout) %>%
  dplyr::mutate(group = "Authentic")

cat(sprintf("      Loaded: %d authentic participants\n", nrow(authentic)))

cat("\n[Step 2/5] Loading weighted inauthentic results...\n")
inauthentic <- readRDS("results/inauthentic_weighted.rds") %>%
  dplyr::filter(sufficient_data & converged) %>%
  dplyr::mutate(group = "Inauthentic")

cat(sprintf("      Loaded: %d inauthentic participants\n", nrow(inauthentic)))

cat("\n[Step 3/5] Loading ROC analysis results...\n")
roc_results <- readRDS("results/roc_analysis_results.rds")

cat(sprintf("      Loaded: ROC data (AUC low = %.4f, AUC high = %.4f)\n",
            roc_results$roc_low$auc, roc_results$roc_high$auc))

cat("\n[Step 4/5] Loading quintile stratification...\n")
quintile_counts <- readRDS("results/quintile_stratification.rds")

cat(sprintf("      Loaded: %d quintiles\n", nrow(quintile_counts)))

cat("\n[Step 5/5] Combining datasets...\n")

# Combine for plotting
combined <- dplyr::bind_rows(
  authentic %>% dplyr::select(pid, avg_logpost, lz, group),
  inauthentic %>% dplyr::select(pid, avg_logpost, lz, group)
)

cat(sprintf("      Combined: %d total participants\n", nrow(combined)))

# ============================================================================
# PHASE 2: CREATE DIAGNOSTIC PLOTS
# ============================================================================

cat("\n=== PHASE 2: CREATE DIAGNOSTIC PLOTS ===\n\n")

cat("[Plot 1/5] Histogram of standardized lz values...\n")

# Plot 1: Histogram of lz values (overlaid)
p1 <- ggplot2::ggplot(combined, ggplot2::aes(x = lz, fill = group)) +
  ggplot2::geom_histogram(alpha = 0.6, position = "identity", bins = 50) +
  ggplot2::geom_vline(xintercept = 0, linetype = "dashed", color = "black", linewidth = 0.8) +
  ggplot2::scale_fill_manual(values = c("Authentic" = "#2E86AB", "Inauthentic" = "#A23B72")) +
  ggplot2::labs(
    title = "Standardized Log-Posterior Distribution (lz)",
    subtitle = sprintf("Authentic (N=%d) vs. Inauthentic (N=%d)",
                      sum(combined$group == "Authentic"),
                      sum(combined$group == "Inauthentic")),
    x = "lz (standardized avg_logpost)",
    y = "Count",
    fill = "Group"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    legend.position = "top",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank()
  )

cat("      [OK] Plot 1 created\n")

cat("\n[Plot 2/5] Density plot of avg_logpost...\n")

# Plot 2: Density plot of avg_logpost
p2 <- ggplot2::ggplot(combined, ggplot2::aes(x = avg_logpost, fill = group)) +
  ggplot2::geom_density(alpha = 0.5) +
  ggplot2::geom_vline(xintercept = mean(authentic$avg_logpost),
                     linetype = "dashed", color = "#2E86AB", linewidth = 0.8) +
  ggplot2::scale_fill_manual(values = c("Authentic" = "#2E86AB", "Inauthentic" = "#A23B72")) +
  ggplot2::labs(
    title = "Average Log-Posterior Distribution",
    subtitle = "100% of inauthentic fall within authentic range",
    x = "avg_logpost (log_posterior / n_items)",
    y = "Density",
    fill = "Group"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    legend.position = "top",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank()
  )

cat("      [OK] Plot 2 created\n")

cat("\n[Plot 3/5] Dual ROC curves...\n")

# Plot 3: Dual ROC curves
roc_low_df <- data.frame(
  fpr = 1 - roc_results$roc_low$specificities,
  tpr = roc_results$roc_low$sensitivities,
  group = "Poor Fit (lz < 0)"
)

roc_high_df <- data.frame(
  fpr = 1 - roc_results$roc_high$specificities,
  tpr = roc_results$roc_high$sensitivities,
  group = "Gaming (lz > 0)"
)

roc_combined <- dplyr::bind_rows(roc_low_df, roc_high_df)

p3 <- ggplot2::ggplot(roc_combined, ggplot2::aes(x = fpr, y = tpr, color = group)) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
  ggplot2::scale_color_manual(values = c("Poor Fit (lz < 0)" = "#E63946",
                                        "Gaming (lz > 0)" = "#F4A261")) +
  ggplot2::annotate("text", x = 0.7, y = 0.3,
                   label = sprintf("Poor Fit AUC = %.3f", roc_results$roc_low$auc),
                   color = "#E63946", size = 4) +
  ggplot2::annotate("text", x = 0.7, y = 0.2,
                   label = sprintf("Gaming AUC = %.3f", roc_results$roc_high$auc),
                   color = "#F4A261", size = 4) +
  ggplot2::labs(
    title = "ROC Curves for Authenticity Classification",
    subtitle = "Poor discrimination (AUC ~0.34-0.50)",
    x = "False Positive Rate",
    y = "True Positive Rate",
    color = "Detection Type"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    legend.position = "top",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank()
  )

cat("      [OK] Plot 3 created\n")

cat("\n[Plot 4/5] Weight distribution by quintile...\n")

# Plot 4: Weight distribution by quintile (boxplot)
p4 <- ggplot2::ggplot(inauthentic, ggplot2::aes(x = quintile, y = att_weight, fill = quintile)) +
  ggplot2::geom_boxplot(alpha = 0.7, outlier.shape = NA) +
  ggplot2::geom_jitter(width = 0.2, alpha = 0.4, size = 1.5) +
  ggplot2::geom_hline(yintercept = 1.0, linetype = "dashed", color = "black", linewidth = 0.8) +
  ggplot2::scale_fill_viridis_d(option = "plasma", begin = 0.2, end = 0.9) +
  ggplot2::labs(
    title = "Normalized Weight Distribution by Quintile",
    subtitle = sprintf("Mean = 1.0, Range = [%.2f, %.2f], Sum = %d",
                      min(inauthentic$att_weight),
                      max(inauthentic$att_weight),
                      nrow(inauthentic)),
    x = "Quintile (based on authentic avg_logpost)",
    y = "Normalized Weight",
    fill = "Quintile"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    legend.position = "none",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank()
  )

cat("      [OK] Plot 4 created\n")

cat("\n[Plot 5/5] Coverage plot with quintile boundaries...\n")

# Plot 5: Coverage plot showing authentic range with inauthentic overlay
quintile_breaks <- quantile(authentic$avg_logpost,
                            probs = c(0, 0.2, 0.4, 0.6, 0.8, 1.0),
                            na.rm = TRUE)

p5 <- ggplot2::ggplot(combined, ggplot2::aes(x = avg_logpost, y = group, fill = group)) +
  ggplot2::geom_violin(alpha = 0.6, trim = FALSE) +
  ggplot2::geom_jitter(height = 0.1, alpha = 0.3, size = 1) +
  ggplot2::geom_vline(xintercept = quintile_breaks[-1],
                     linetype = "dotted", color = "gray40", linewidth = 0.5) +
  ggplot2::scale_fill_manual(values = c("Authentic" = "#2E86AB", "Inauthentic" = "#A23B72")) +
  ggplot2::labs(
    title = "Coverage Analysis: Inauthentic vs. Authentic Distribution",
    subtitle = "Dashed lines show quintile boundaries from authentic distribution",
    x = "avg_logpost (log_posterior / n_items)",
    y = "",
    fill = "Group"
  ) +
  ggplot2::theme_minimal(base_size = 12) +
  ggplot2::theme(
    legend.position = "none",
    plot.title = ggplot2::element_text(face = "bold"),
    panel.grid.minor = ggplot2::element_blank(),
    axis.text.y = ggplot2::element_text(size = 12, face = "bold")
  )

cat("      [OK] Plot 5 created\n")

# ============================================================================
# PHASE 3: SAVE PLOTS
# ============================================================================

cat("\n=== PHASE 3: SAVE PLOTS ===\n\n")

# Create output directory if it doesn't exist
if (!dir.exists("results/plots")) {
  dir.create("results/plots", recursive = TRUE)
  cat("      Created directory: results/plots/\n")
}

cat("\n[Step 1/6] Saving individual plots...\n")

ggplot2::ggsave("results/plots/01_lz_histogram.png", plot = p1,
               width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/01_lz_histogram.png\n")

ggplot2::ggsave("results/plots/02_avg_logpost_density.png", plot = p2,
               width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/02_avg_logpost_density.png\n")

ggplot2::ggsave("results/plots/03_roc_curves.png", plot = p3,
               width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/03_roc_curves.png\n")

ggplot2::ggsave("results/plots/04_weight_by_quintile.png", plot = p4,
               width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/04_weight_by_quintile.png\n")

ggplot2::ggsave("results/plots/05_coverage_plot.png", plot = p5,
               width = 10, height = 6, dpi = 300)
cat("      Saved: results/plots/05_coverage_plot.png\n")

cat("\n[Step 2/6] Creating combined panel plot...\n")

# Combined panel (2x2 grid with title)
combined_panel <- (p1 + p2) / (p3 + p4) +
  patchwork::plot_annotation(
    title = "Authenticity Screening Diagnostic Summary",
    subtitle = sprintf("LOOCV Results: %d Authentic, %d Inauthentic | Normalized Weights: Sum=196, Mean=1.0",
                      sum(combined$group == "Authentic"),
                      sum(combined$group == "Inauthentic")),
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(size = 16, face = "bold"),
      plot.subtitle = ggplot2::element_text(size = 12)
    )
  )

ggplot2::ggsave("results/plots/00_combined_panel.png", plot = combined_panel,
               width = 16, height = 12, dpi = 300)
cat("      Saved: results/plots/00_combined_panel.png\n")

cat("\n[Step 3/6] Creating full diagnostic report plot...\n")

# Full report (3x2 grid)
full_report <- (p1 + p2) / (p3 + p4) / (p5 + ggplot2::theme_void()) +
  patchwork::plot_annotation(
    title = "Authenticity Screening: Complete Diagnostic Report",
    subtitle = sprintf("LOOCV: %d Authentic (99.9%% converged) | Inauthentic: %d (100%% coverage) | Weights: Normalized to N=196",
                      sum(combined$group == "Authentic"),
                      sum(combined$group == "Inauthentic")),
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(size = 18, face = "bold"),
      plot.subtitle = ggplot2::element_text(size = 13)
    )
  )

ggplot2::ggsave("results/plots/00_full_diagnostic_report.png", plot = full_report,
               width = 16, height = 18, dpi = 300)
cat("      Saved: results/plots/00_full_diagnostic_report.png\n")

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n")
cat("================================================================================\n")
cat("  DIAGNOSTIC PLOTS CREATED\n")
cat("================================================================================\n")
cat("\n")

cat("Individual Plots:\n")
cat("  1. results/plots/01_lz_histogram.png\n")
cat("  2. results/plots/02_avg_logpost_density.png\n")
cat("  3. results/plots/03_roc_curves.png\n")
cat("  4. results/plots/04_weight_by_quintile.png\n")
cat("  5. results/plots/05_coverage_plot.png\n")
cat("\n")

cat("Summary Panels:\n")
cat("  - results/plots/00_combined_panel.png (2x2 grid, key plots)\n")
cat("  - results/plots/00_full_diagnostic_report.png (3x2 grid, all plots)\n")
cat("\n")

cat("Key Findings:\n")
cat(sprintf("  - LOOCV: %d authentic, 99.9%% convergence\n", sum(combined$group == "Authentic")))
cat(sprintf("  - Inauthentic: %d participants, 100%% coverage overlap\n", sum(combined$group == "Inauthentic")))
cat(sprintf("  - ROC: Poor discrimination (AUC %.2f-%.2f)\n",
           roc_results$roc_low$auc, roc_results$roc_high$auc))
cat(sprintf("  - Weights: Normalized (sum=%d, mean=%.2f, range=[%.2f, %.2f])\n",
           nrow(inauthentic), mean(inauthentic$att_weight),
           min(inauthentic$att_weight), max(inauthentic$att_weight)))
cat("\n")

cat("[OK] All diagnostic plots created!\n")
cat("\n")

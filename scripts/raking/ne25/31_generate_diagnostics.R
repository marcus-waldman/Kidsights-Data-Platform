# Phase 6: Generate Diagnostic Visualizations and Reports
# Tasks 19-22: Correlation heatmaps, mean comparisons, propensity diagnostics, efficiency reports

library(dplyr)
library(ggplot2)
library(gridExtra)
library(reshape2)

cat("\n========================================\n")
cat("Phase 6: Generate Diagnostic Reports\n")
cat("========================================\n\n")

# Create output directory for figures
if (!dir.exists("figures/raking")) {
  dir.create("figures/raking", recursive = TRUE)
}

# Variable names
design_vars <- c("male", "age", "white_nh", "black", "hispanic",
                 "educ_years", "married", "poverty_ratio")

# Load all moments
cat("[0] Loading covariance matrices...\n")
acs_moments <- readRDS("data/raking/ne25/acs_moments.rds")
nhis_moments <- readRDS("data/raking/ne25/nhis_moments.rds")
nsch_moments <- readRDS("data/raking/ne25/nsch_moments.rds")
cat("    ✓ All moments loaded\n\n")

# ============================================================================
# TASK 19: Correlation Heatmaps
# ============================================================================

cat("========================================\n")
cat("Task 19: Generate Correlation Heatmaps\n")
cat("========================================\n\n")

# Function to create correlation heatmap
create_correlation_heatmap <- function(cor_matrix, title, var_names) {
  # Convert to long format for ggplot
  cor_long <- reshape2::melt(cor_matrix)
  colnames(cor_long) <- c("Var1", "Var2", "Correlation")

  # Create heatmap
  p <- ggplot2::ggplot(cor_long, ggplot2::aes(x = Var1, y = Var2, fill = Correlation)) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::scale_fill_gradient2(
      low = "blue", mid = "white", high = "red",
      midpoint = 0, limits = c(-1, 1),
      name = "Correlation"
    ) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", Correlation)), size = 3) +
    ggplot2::labs(
      title = title,
      x = NULL, y = NULL
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      plot.title = ggplot2::element_text(hjust = 0.5, face = "bold")
    )

  return(p)
}

cat("[1] Creating ACS correlation heatmap...\n")
p_acs <- create_correlation_heatmap(
  acs_moments$correlation,
  "ACS Nebraska Correlation Matrix\n(2019-2023 Pooled, Children 0-5)",
  design_vars
)

ggsave("figures/raking/acs_correlation_heatmap.png", p_acs,
       width = 8, height = 7, dpi = 300)
cat("    ✓ Saved: figures/raking/acs_correlation_heatmap.png\n")

cat("[2] Creating NHIS correlation heatmap...\n")
p_nhis <- create_correlation_heatmap(
  nhis_moments$correlation,
  "NHIS North Central Correlation Matrix\n(Nebraska-Reweighted, 2019-2024)",
  design_vars
)

ggsave("figures/raking/nhis_correlation_heatmap.png", p_nhis,
       width = 8, height = 7, dpi = 300)
cat("    ✓ Saved: figures/raking/nhis_correlation_heatmap.png\n")

cat("[3] Creating NSCH correlation heatmap...\n")
p_nsch <- create_correlation_heatmap(
  nsch_moments$correlation,
  "NSCH North Central Correlation Matrix\n(Nebraska-Reweighted, 2021-2022)",
  design_vars
)

ggsave("figures/raking/nsch_correlation_heatmap.png", p_nsch,
       width = 8, height = 7, dpi = 300)
cat("    ✓ Saved: figures/raking/nsch_correlation_heatmap.png\n")

cat("[4] Creating combined comparison plot...\n")
p_combined <- gridExtra::grid.arrange(p_acs, p_nhis, p_nsch, ncol = 3)

ggsave("figures/raking/correlation_comparison_3sources.png", p_combined,
       width = 20, height = 7, dpi = 300)
cat("    ✓ Saved: figures/raking/correlation_comparison_3sources.png\n\n")

cat("Task 19 Complete: Correlation Heatmaps Generated\n\n")

# ============================================================================
# TASK 20: Mean Comparison Table
# ============================================================================

cat("========================================\n")
cat("Task 20: Generate Mean Comparison Table\n")
cat("========================================\n\n")

cat("[1] Creating weighted mean comparison table...\n")

mean_comparison <- data.frame(
  Variable = design_vars,
  ACS = round(acs_moments$mu, 4),
  NHIS = round(nhis_moments$mu, 4),
  NSCH = round(nsch_moments$mu, 4)
)

# Add difference columns
mean_comparison$Diff_NHIS_ACS <- round(mean_comparison$NHIS - mean_comparison$ACS, 4)
mean_comparison$Diff_NSCH_ACS <- round(mean_comparison$NSCH - mean_comparison$ACS, 4)
mean_comparison$Diff_NSCH_NHIS <- round(mean_comparison$NSCH - mean_comparison$NHIS, 4)

cat("\nWeighted Means (Nebraska-Representative):\n")
print(mean_comparison)

# Save to CSV
write.csv(mean_comparison, "figures/raking/mean_comparison_table.csv", row.names = FALSE)
cat("\n    ✓ Saved: figures/raking/mean_comparison_table.csv\n")

# Create visual comparison plot
mean_long <- reshape2::melt(mean_comparison[, 1:4], id.vars = "Variable")
colnames(mean_long) <- c("Variable", "Source", "Mean")

p_means <- ggplot2::ggplot(mean_long, ggplot2::aes(x = Variable, y = Mean, fill = Source)) +
  ggplot2::geom_bar(stat = "identity", position = "dodge") +
  ggplot2::labs(
    title = "Weighted Means Comparison Across Sources",
    subtitle = "Nebraska-representative estimates (NHIS/NSCH propensity-reweighted)",
    x = "Variable",
    y = "Weighted Mean"
  ) +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
    plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
    plot.subtitle = ggplot2::element_text(hjust = 0.5, size = 9)
  ) +
  ggplot2::scale_fill_manual(values = c("ACS" = "#1f78b4", "NHIS" = "#33a02c", "NSCH" = "#e31a1c"))

ggsave("figures/raking/mean_comparison_plot.png", p_means,
       width = 10, height = 6, dpi = 300)
cat("    ✓ Saved: figures/raking/mean_comparison_plot.png\n\n")

cat("Task 20 Complete: Mean Comparison Generated\n\n")

# ============================================================================
# TASK 21: Propensity Diagnostic Plots
# ============================================================================

cat("========================================\n")
cat("Task 21: Generate Propensity Diagnostic Plots\n")
cat("========================================\n\n")

# Load ACS data with propensity scores
acs_with_prop <- readRDS("data/raking/ne25/acs_nc_with_propensity.rds")

# Load NHIS and NSCH reweighted data
nhis_reweighted <- readRDS("data/raking/ne25/nhis_reweighted.rds")
nsch_reweighted <- readRDS("data/raking/ne25/nsch_reweighted.rds")

cat("[1] Creating common support density plots...\n")

# Prepare data for density plots
acs_ne_props <- acs_with_prop$p_nebraska[acs_with_prop$nebraska == 1]
acs_other_props <- acs_with_prop$p_nebraska[acs_with_prop$nebraska == 0]

prop_data <- data.frame(
  propensity = c(acs_ne_props, acs_other_props,
                 nhis_reweighted$p_nebraska, nsch_reweighted$p_nebraska),
  group = c(
    rep("Nebraska (ACS)", length(acs_ne_props)),
    rep("Other NC States (ACS)", length(acs_other_props)),
    rep("NHIS (NC)", nrow(nhis_reweighted)),
    rep("NSCH (NC)", nrow(nsch_reweighted))
  )
)

# Density plot showing common support
p_common_support <- ggplot2::ggplot(prop_data, ggplot2::aes(x = propensity, fill = group)) +
  ggplot2::geom_density(alpha = 0.5) +
  ggplot2::labs(
    title = "Propensity Score Distributions: Common Support Check",
    subtitle = "Overlap between Nebraska (target) and NC sources ensures valid reweighting",
    x = "P(Nebraska | Demographics)",
    y = "Density",
    fill = "Group"
  ) +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
    plot.subtitle = ggplot2::element_text(hjust = 0.5, size = 9)
  ) +
  ggplot2::scale_fill_manual(values = c(
    "Nebraska (ACS)" = "#1f78b4",
    "Other NC States (ACS)" = "#a6cee3",
    "NHIS (NC)" = "#33a02c",
    "NSCH (NC)" = "#e31a1c"
  ))

ggsave("figures/raking/propensity_common_support.png", p_common_support,
       width = 10, height = 6, dpi = 300)
cat("    ✓ Saved: figures/raking/propensity_common_support.png\n")

# Boxplot comparison
p_prop_boxplot <- ggplot2::ggplot(prop_data, ggplot2::aes(x = group, y = propensity, fill = group)) +
  ggplot2::geom_boxplot() +
  ggplot2::labs(
    title = "Propensity Score Distributions by Group",
    x = NULL,
    y = "P(Nebraska | Demographics)"
  ) +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
    plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
    legend.position = "none"
  ) +
  ggplot2::scale_fill_manual(values = c(
    "Nebraska (ACS)" = "#1f78b4",
    "Other NC States (ACS)" = "#a6cee3",
    "NHIS (NC)" = "#33a02c",
    "NSCH (NC)" = "#e31a1c"
  ))

ggsave("figures/raking/propensity_boxplot.png", p_prop_boxplot,
       width = 8, height = 6, dpi = 300)
cat("    ✓ Saved: figures/raking/propensity_boxplot.png\n\n")

cat("Task 21 Complete: Propensity Diagnostics Generated\n\n")

# ============================================================================
# TASK 22: Effective Sample Size Report
# ============================================================================

cat("========================================\n")
cat("Task 22: Generate Effective Sample Size Report\n")
cat("========================================\n\n")

# Load propensity diagnostics
nhis_diag <- readRDS("data/raking/ne25/nhis_propensity_diagnostics.rds")
nsch_diag <- readRDS("data/raking/ne25/nsch_propensity_diagnostics.rds")

cat("[1] Creating effective sample size summary...\n\n")

efficiency_summary <- data.frame(
  Source = c("ACS", "NHIS", "NSCH"),
  Raw_N = c(acs_moments$n, nhis_diag$n_complete, nsch_diag$n_complete),
  Effective_N = c(
    round(acs_moments$n_eff, 1),
    round(nhis_diag$efficiency_metrics$n_eff_adjusted, 1),
    round(nsch_diag$efficiency_metrics$n_eff_adjusted, 1)
  ),
  Efficiency_Pct = c(
    round(acs_moments$n_eff / acs_moments$n * 100, 1),
    round(nhis_diag$efficiency_metrics$efficiency * 100, 1),
    round(nsch_diag$efficiency_metrics$efficiency * 100, 1)
  ),
  Reweighting = c("None (Nebraska direct)", "Propensity (NC → NE)", "Propensity (NC → NE)")
)

cat("Effective Sample Size Summary:\n")
print(efficiency_summary)

# Check for efficiency warnings
efficiency_summary$Warning <- ifelse(efficiency_summary$Efficiency_Pct < 50, "Low efficiency", "OK")

cat("\nEfficiency Flags:\n")
print(efficiency_summary[, c("Source", "Efficiency_Pct", "Warning")])

# Save summary
write.csv(efficiency_summary, "figures/raking/efficiency_summary.csv", row.names = FALSE)
cat("\n    ✓ Saved: figures/raking/efficiency_summary.csv\n")

# Visualization: Effective N comparison
p_efficiency <- ggplot2::ggplot(efficiency_summary,
                                 ggplot2::aes(x = Source, y = Efficiency_Pct, fill = Source)) +
  ggplot2::geom_bar(stat = "identity") +
  ggplot2::geom_hline(yintercept = 50, linetype = "dashed", color = "red") +
  ggplot2::geom_text(ggplot2::aes(label = paste0(Efficiency_Pct, "%")),
                     vjust = -0.5, size = 5) +
  ggplot2::labs(
    title = "Reweighting Efficiency: Effective Sample Size Retention",
    subtitle = "Dashed line = 50% threshold (minimum acceptable efficiency)",
    x = "Data Source",
    y = "Efficiency (Effective N / Raw N) %"
  ) +
  ggplot2::ylim(0, 105) +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
    plot.subtitle = ggplot2::element_text(hjust = 0.5, size = 9),
    legend.position = "none"
  ) +
  ggplot2::scale_fill_manual(values = c("ACS" = "#1f78b4", "NHIS" = "#33a02c", "NSCH" = "#e31a1c"))

ggsave("figures/raking/efficiency_comparison.png", p_efficiency,
       width = 8, height = 6, dpi = 300)
cat("    ✓ Saved: figures/raking/efficiency_comparison.png\n\n")

cat("Task 22 Complete: Efficiency Report Generated\n\n")

# ============================================================================
# COMPREHENSIVE DIAGNOSTIC SUMMARY
# ============================================================================

cat("========================================\n")
cat("Comprehensive Diagnostic Summary\n")
cat("========================================\n\n")

cat("COVARIANCE MATRIX OUTPUTS:\n")
cat("  ✓ ACS moments (Nebraska 2019-2023):", acs_moments$n, "children\n")
cat("  ✓ NHIS moments (NC → NE reweighted):", nhis_moments$n, "parent-child pairs\n")
cat("  ✓ NSCH moments (NC → NE reweighted):", nsch_moments$n, "children\n\n")

cat("EFFICIENCY METRICS:\n")
cat("  • ACS:", round(acs_moments$n_eff / acs_moments$n * 100, 1), "% (direct Nebraska)\n")
cat("  • NHIS:", round(nhis_diag$efficiency_metrics$efficiency * 100, 1), "% (propensity reweighted)\n")
cat("  • NSCH:", round(nsch_diag$efficiency_metrics$efficiency * 100, 1), "% (propensity reweighted)\n\n")

cat("DIAGNOSTIC OUTPUTS CREATED:\n")
cat("  ✓ Correlation heatmaps (3 sources + combined)\n")
cat("  ✓ Mean comparison table and plot\n")
cat("  ✓ Propensity common support plots\n")
cat("  ✓ Efficiency summary report\n\n")

cat("All diagnostic files saved to: figures/raking/\n\n")

cat("========================================\n")
cat("Phase 6 Complete: Diagnostics Generated\n")
cat("========================================\n\n")

cat("Ready for KL divergence weighting implementation\n\n")

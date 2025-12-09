# Phase 6b: Validate Block 1 Pooling
# Statistical tests to verify that Block 1 means are not significantly different across sources
# Uses Wald tests with weighted covariance matrices

library(dplyr)
library(ggplot2)

cat("\n========================================\n")
cat("Phase 6b: Validate Block 1 Pooling\n")
cat("========================================\n\n")

# Create output directory
if (!dir.exists("figures/raking")) {
  dir.create("figures/raking", recursive = TRUE)
}

# ============================================================================
# STEP 1: Load Source-Specific Moments
# ============================================================================

cat("[1] Loading source-specific moments...\n")

acs <- readRDS("data/raking/ne25/acs_moments.rds")
nhis <- readRDS("data/raking/ne25/nhis_moments.rds")
nsch <- readRDS("data/raking/ne25/nsch_moments.rds")
unified <- readRDS("data/raking/ne25/unified_moments.rds")

cat("    ✓ All moments loaded\n\n")

# ============================================================================
# STEP 2: Extract Block 1 Common Demographics (7 variables)
# ============================================================================

cat("[2] Extracting Block 1 common demographics...\n")

block1_vars <- c("male", "age", "white_nh", "black", "hispanic", "educ_years", "poverty_ratio")

# ACS: All 7 variables
mu_acs <- acs$mu[1:7]
Sigma_acs <- acs$Sigma[1:7, 1:7]
n_eff_acs <- acs$n_eff

# NHIS: Skip married (index 7), extract indices 1-6 and 8
mu_nhis <- nhis$mu[c(1:6, 8)]
Sigma_nhis <- nhis$Sigma[c(1:6, 8), c(1:6, 8)]
n_eff_nhis <- nhis$n_eff

# NSCH: First 7 variables
mu_nsch <- nsch$mu[1:7]
Sigma_nsch <- nsch$Sigma[1:7, 1:7]
n_eff_nsch <- nsch$n_eff

# Pooled Block 1
mu_pooled <- unified$mu[1:7]

cat("    ✓ Block 1 extracted (7 variables)\n\n")

# ============================================================================
# STEP 3: Wald Tests for Mean Differences
# ============================================================================

cat("[3] Conducting Wald tests for mean differences...\n\n")

# Function to compute Wald statistic for difference between two weighted means
# H0: mu1 = mu2
# Test statistic: (mu1 - mu2)' * Var(mu1 - mu2)^(-1) * (mu1 - mu2) ~ chi-square(df=7)
compute_wald_test <- function(mu1, Sigma1, n_eff1, mu2, Sigma2, n_eff2, var_names) {
  # Standard errors of means (SE = sqrt(Sigma / n_eff))
  Var_mu1 <- Sigma1 / n_eff1
  Var_mu2 <- Sigma2 / n_eff2

  # Variance of difference (assuming independence across sources)
  Var_diff <- Var_mu1 + Var_mu2

  # Mean difference
  diff <- mu1 - mu2

  # Wald statistic: diff' * Var_diff^(-1) * diff
  # Check if matrix is invertible
  if (kappa(Var_diff) > 1e10) {
    warning("Variance matrix near-singular, using pseudo-inverse")
    Var_diff_inv <- MASS::ginv(Var_diff)
  } else {
    Var_diff_inv <- solve(Var_diff)
  }

  wald_stat <- t(diff) %*% Var_diff_inv %*% diff

  # P-value from chi-square distribution (df = number of variables)
  df <- length(mu1)
  p_value <- 1 - pchisq(wald_stat, df = df)

  # Individual standardized differences (z-scores)
  se_diff <- sqrt(diag(Var_diff))
  z_scores <- diff / se_diff

  # Cohen's d effect sizes
  # d = (mu1 - mu2) / pooled_SD
  # Pooled SD = sqrt((Sigma1 + Sigma2) / 2)
  pooled_sd <- sqrt((diag(Sigma1) + diag(Sigma2)) / 2)
  cohens_d <- diff / pooled_sd

  return(list(
    wald_stat = as.numeric(wald_stat),
    df = df,
    p_value = as.numeric(p_value),
    diff = diff,
    se_diff = se_diff,
    z_scores = z_scores,
    cohens_d = cohens_d,
    var_names = var_names
  ))
}

# Test 1: ACS vs NHIS
cat("Test 1: ACS vs NHIS\n")
test_acs_nhis <- compute_wald_test(mu_acs, Sigma_acs, n_eff_acs,
                                    mu_nhis, Sigma_nhis, n_eff_nhis,
                                    block1_vars)

cat(sprintf("  Wald statistic: %.4f (df=%d)\n", test_acs_nhis$wald_stat, test_acs_nhis$df))
cat(sprintf("  P-value: %.4f ", test_acs_nhis$p_value))
if (test_acs_nhis$p_value > 0.05) {
  cat("(✓ No significant difference)\n")
} else {
  cat("(WARNING: Significant difference detected)\n")
}
cat("\n")

# Test 2: ACS vs NSCH
cat("Test 2: ACS vs NSCH\n")
test_acs_nsch <- compute_wald_test(mu_acs, Sigma_acs, n_eff_acs,
                                    mu_nsch, Sigma_nsch, n_eff_nsch,
                                    block1_vars)

cat(sprintf("  Wald statistic: %.4f (df=%d)\n", test_acs_nsch$wald_stat, test_acs_nsch$df))
cat(sprintf("  P-value: %.4f ", test_acs_nsch$p_value))
if (test_acs_nsch$p_value > 0.05) {
  cat("(✓ No significant difference)\n")
} else {
  cat("(WARNING: Significant difference detected)\n")
}
cat("\n")

# Test 3: NHIS vs NSCH
cat("Test 3: NHIS vs NSCH\n")
test_nhis_nsch <- compute_wald_test(mu_nhis, Sigma_nhis, n_eff_nhis,
                                     mu_nsch, Sigma_nsch, n_eff_nsch,
                                     block1_vars)

cat(sprintf("  Wald statistic: %.4f (df=%d)\n", test_nhis_nsch$wald_stat, test_nhis_nsch$df))
cat(sprintf("  P-value: %.4f ", test_nhis_nsch$p_value))
if (test_nhis_nsch$p_value > 0.05) {
  cat("(✓ No significant difference)\n")
} else {
  cat("(WARNING: Significant difference detected)\n")
}
cat("\n")

# ============================================================================
# STEP 4: Cohen's d Effect Sizes
# ============================================================================

cat("[4] Computing Cohen's d effect sizes...\n\n")

# Combine all Cohen's d values into a data frame
cohens_d_df <- data.frame(
  Variable = block1_vars,
  ACS_vs_NHIS = test_acs_nhis$cohens_d,
  ACS_vs_NSCH = test_acs_nsch$cohens_d,
  NHIS_vs_NSCH = test_nhis_nsch$cohens_d
)

cat("Cohen's d effect sizes (standardized mean differences):\n")
cat("Interpretation: |d| < 0.2 (small), 0.2-0.5 (small-medium), 0.5-0.8 (medium), > 0.8 (large)\n\n")
cohens_d_display <- cohens_d_df
cohens_d_display[, 2:4] <- round(cohens_d_display[, 2:4], 3)
print(cohens_d_display)

# Flag variables with |d| > 0.5 (medium or larger effect)
cohens_d_df$Flag_ACS_NHIS <- ifelse(abs(cohens_d_df$ACS_vs_NHIS) > 0.5, "*", "")
cohens_d_df$Flag_ACS_NSCH <- ifelse(abs(cohens_d_df$ACS_vs_NSCH) > 0.5, "*", "")
cohens_d_df$Flag_NHIS_NSCH <- ifelse(abs(cohens_d_df$NHIS_vs_NSCH) > 0.5, "*", "")

cat("\n\nFlagged variables (|d| > 0.5, medium or larger effect):\n")
flagged <- cohens_d_df[cohens_d_df$Flag_ACS_NHIS == "*" |
                        cohens_d_df$Flag_ACS_NSCH == "*" |
                        cohens_d_df$Flag_NHIS_NSCH == "*", ]

if (nrow(flagged) > 0) {
  print(flagged[, c("Variable", "ACS_vs_NHIS", "ACS_vs_NSCH", "NHIS_vs_NSCH")])
} else {
  cat("  (None - all variables within acceptable range)\n")
}

cat("\n")

# ============================================================================
# STEP 5: Create Mean Comparison Plot with Error Bars
# ============================================================================

cat("[5] Creating mean comparison plot with error bars...\n")

# Prepare data for plotting
mean_data <- data.frame(
  Variable = rep(block1_vars, 3),
  Source = rep(c("ACS", "NHIS", "NSCH"), each = 7),
  Mean = c(mu_acs, mu_nhis, mu_nsch),
  SE = c(
    sqrt(diag(Sigma_acs) / n_eff_acs),
    sqrt(diag(Sigma_nhis) / n_eff_nhis),
    sqrt(diag(Sigma_nsch) / n_eff_nsch)
  )
)

# Add 95% confidence intervals
mean_data$CI_lower <- mean_data$Mean - 1.96 * mean_data$SE
mean_data$CI_upper <- mean_data$Mean + 1.96 * mean_data$SE

# Create plot with error bars
p_means_ci <- ggplot2::ggplot(mean_data, ggplot2::aes(x = Variable, y = Mean, color = Source, group = Source)) +
  ggplot2::geom_point(size = 3, position = ggplot2::position_dodge(width = 0.5)) +
  ggplot2::geom_errorbar(
    ggplot2::aes(ymin = CI_lower, ymax = CI_upper),
    width = 0.2,
    position = ggplot2::position_dodge(width = 0.5)
  ) +
  ggplot2::labs(
    title = "Block 1 Weighted Means with 95% Confidence Intervals",
    subtitle = "Overlapping CIs indicate no significant difference (calibrated to Nebraska demographics)",
    x = "Variable",
    y = "Weighted Mean ± 1.96 SE",
    color = "Source"
  ) +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
    plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
    plot.subtitle = ggplot2::element_text(hjust = 0.5, size = 9)
  ) +
  ggplot2::scale_color_manual(values = c("ACS" = "#1f78b4", "NHIS" = "#33a02c", "NSCH" = "#e31a1c"))

ggplot2::ggsave("figures/raking/block1_means_comparison_ci.png", p_means_ci,
       width = 10, height = 6, dpi = 300)
cat("    ✓ Saved: figures/raking/block1_means_comparison_ci.png\n\n")

# ============================================================================
# STEP 6: Create Cohen's d Heatmap
# ============================================================================

cat("[6] Creating Cohen's d heatmap...\n")

# Reshape Cohen's d for heatmap
d_long <- reshape2::melt(cohens_d_df[, 1:4], id.vars = "Variable")
colnames(d_long) <- c("Variable", "Comparison", "Cohens_d")

# Create heatmap
p_d_heatmap <- ggplot2::ggplot(d_long, ggplot2::aes(x = Comparison, y = Variable, fill = Cohens_d)) +
  ggplot2::geom_tile(color = "white") +
  ggplot2::scale_fill_gradient2(
    low = "blue", mid = "white", high = "red",
    midpoint = 0, limits = c(-1, 1),
    name = "Cohen's d"
  ) +
  ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", Cohens_d)), size = 3.5) +
  ggplot2::geom_hline(yintercept = seq(1.5, 6.5, 1), color = "gray80", linewidth = 0.5) +
  ggplot2::labs(
    title = "Cohen's d Effect Sizes Across Sources",
    subtitle = "|d| < 0.2 (small), 0.2-0.5 (small-medium), 0.5-0.8 (medium), > 0.8 (large)",
    x = "Comparison",
    y = "Variable"
  ) +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
    plot.title = ggplot2::element_text(hjust = 0.5, face = "bold"),
    plot.subtitle = ggplot2::element_text(hjust = 0.5, size = 9)
  )

ggplot2::ggsave("figures/raking/block1_cohens_d_heatmap.png", p_d_heatmap,
       width = 8, height = 6, dpi = 300)
cat("    ✓ Saved: figures/raking/block1_cohens_d_heatmap.png\n\n")

# ============================================================================
# STEP 7: Save Summary Statistics
# ============================================================================

cat("[7] Saving validation summary...\n")

# Create summary table
validation_summary <- data.frame(
  Comparison = c("ACS vs NHIS", "ACS vs NSCH", "NHIS vs NSCH"),
  Wald_Statistic = c(test_acs_nhis$wald_stat, test_acs_nsch$wald_stat, test_nhis_nsch$wald_stat),
  DF = c(test_acs_nhis$df, test_acs_nsch$df, test_nhis_nsch$df),
  P_Value = c(test_acs_nhis$p_value, test_acs_nsch$p_value, test_nhis_nsch$p_value),
  Significant = c(
    ifelse(test_acs_nhis$p_value < 0.05, "Yes", "No"),
    ifelse(test_acs_nsch$p_value < 0.05, "Yes", "No"),
    ifelse(test_nhis_nsch$p_value < 0.05, "Yes", "No")
  )
)

write.csv(validation_summary, "figures/raking/block1_validation_summary.csv", row.names = FALSE)
cat("    ✓ Saved: figures/raking/block1_validation_summary.csv\n")

write.csv(cohens_d_df, "figures/raking/block1_cohens_d_table.csv", row.names = FALSE)
cat("    ✓ Saved: figures/raking/block1_cohens_d_table.csv\n\n")

# ============================================================================
# STEP 8: Final Summary
# ============================================================================

cat("========================================\n")
cat("Block 1 Pooling Validation Summary\n")
cat("========================================\n\n")

cat("WALD TEST RESULTS (Joint test across all 7 Block 1 variables):\n\n")
print(validation_summary)

cat("\n\nINTERPRETATION:\n")
cat("  • P-value > 0.05: No significant difference (✓ pooling justified)\n")
cat("  • P-value < 0.05: Significant difference (⚠ pooling may not be appropriate)\n\n")

n_significant <- sum(validation_summary$Significant == "Yes")
if (n_significant == 0) {
  cat("✓ CONCLUSION: All pairwise comparisons show no significant differences.\n")
  cat("  Pooling Block 1 demographics across ACS/NHIS/NSCH is statistically justified.\n\n")
} else {
  cat("⚠ WARNING: ", n_significant, " comparison(s) show significant differences.\n")
  cat("  Review individual variable z-scores to identify problematic variables.\n\n")
}

cat("OUTPUTS CREATED:\n")
cat("  ✓ Mean comparison plot with 95% CIs\n")
cat("  ✓ Z-score heatmap\n")
cat("  ✓ Validation summary tables\n\n")

cat("========================================\n")
cat("Phase 6b Complete: Validation Done\n")
cat("========================================\n\n")

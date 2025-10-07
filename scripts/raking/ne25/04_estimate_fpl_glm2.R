# Phase 2, Task 2.4: Estimate Federal Poverty Level Distribution (glm2 version with bootstrap)
# 5 estimands: 0-99%, 100-199%, 200-299%, 300-399%, 400%+
# Refactored: January 2025
# Changes: Uses nnet::multinom() instead of 5 separate survey::svyglm() models

library(nnet)
library(dplyr)
source("config/bootstrap_config.R")
source("scripts/raking/ne25/estimation_helpers_glm2.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

cat("\n========================================\n")
cat("Task 2.4: Estimate Federal Poverty Level (multinom)\n")
cat("========================================\n\n")

# Load ACS design (to extract data and bootstrap weights)
cat("[1] Loading ACS survey design...\n")
acs_design <- readRDS("data/raking/ne25/acs_design.rds")
acs_data <- acs_design$variables
cat("    Sample size:", nrow(acs_data), "\n\n")

# Create FPL category variable
cat("[2] Creating FPL category variable...\n")
acs_data$fpl_category <- cut(
  acs_data$POVERTY,
  breaks = c(0, 100, 200, 300, 400, 600),
  labels = c("0-99%", "100-199%", "200-299%", "300-399%", "400%+"),
  include.lowest = TRUE,
  right = FALSE
)

# Filter out missing (POVERTY >= 600)
cat("    Records before filter:", nrow(acs_data), "\n")
acs_data_fpl <- acs_data[acs_data$POVERTY < 600 & !is.na(acs_data$fpl_category), ]
cat("    Records after filter:", nrow(acs_data_fpl), "\n")

# Check distribution
cat("\n    FPL category distribution:\n")
fpl_table <- table(acs_data_fpl$fpl_category)
print(fpl_table)
cat("\n")

# Estimate FPL using multinomial logistic regression
cat("[3] Estimating FPL using multinomial logistic regression...\n")
cat("    Formula: fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR\n")
cat("    Method: Single multinomial model (5 categories)\n\n")

# Calculate mean year for prediction
mean_year <- mean(acs_data_fpl$MULTYEAR)

fpl_est <- fit_multinom_estimates(
  data = acs_data_fpl,
  formula = fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
  weights_col = "PERWT",
  predict_year = mean_year,
  ages = 0:5
)

cat("\n[4] Predictions by age:\n")
# Reshape for display
fpl_matrix <- matrix(fpl_est$estimate, nrow = 6, ncol = 5, byrow = TRUE)
colnames(fpl_matrix) <- c("0-99%", "100-199%", "200-299%", "300-399%", "400%+")
rownames(fpl_matrix) <- paste("Age", 0:5)
print(round(fpl_matrix, 4))

# Validate predictions
cat("\n[5] Validating predictions...\n")

# Check row sums (should all be 1.0)
row_sums <- rowSums(fpl_matrix)
cat("    Row sums (should all be ~1.0):\n")
for (i in 1:length(row_sums)) {
  cat("      Age", i-1, ":", round(row_sums[i], 6), "\n")
}

if (all(abs(row_sums - 1.0) < 0.001)) {
  cat("    [OK] All row sums are valid (within 0.001 of 1.0)\n")
} else {
  cat("    [WARN] Some row sums deviate from 1.0\n")
}

# Check ranges (all should be 0-1)
if (all(fpl_matrix >= 0 & fpl_matrix <= 1)) {
  cat("    [OK] All predictions in valid range [0, 1]\n")
} else {
  cat("    [WARN] Some predictions outside [0, 1]\n")
}

# Create results data frame
cat("\n[6] Creating results data frame...\n")
fpl_estimates <- data.frame(
  age = fpl_est$age,
  estimand = fpl_est$category,
  estimate = fpl_est$estimate
)

cat("    Created", nrow(fpl_estimates), "rows (6 ages × 5 categories)\n")
cat("\n    First 10 rows:\n")
print(head(fpl_estimates, 10))

# Plausibility check
cat("\n[7] Plausibility check (Nebraska child poverty):\n")
cat("    Below poverty (0-99%):", round(mean(fpl_matrix[, 1]) * 100, 1), "% (expect ~12-18%)\n")
cat("    Near poverty (100-199%):", round(mean(fpl_matrix[, 2]) * 100, 1), "% (expect ~15-20%)\n")
cat("    Middle income (200-299%):", round(mean(fpl_matrix[, 3]) * 100, 1), "% (expect ~15-20%)\n")
cat("    Upper-middle (300-399%):", round(mean(fpl_matrix[, 4]) * 100, 1), "% (expect ~12-15%)\n")
cat("    High income (400%+):", round(mean(fpl_matrix[, 5]) * 100, 1), "% (expect ~30-40%)\n")

# Validate using helper function
cat("\n[8] Multinomial estimate validation:\n")
validate_multinomial_estimates(fpl_estimates, "FPL Distribution")

# Save point estimates
cat("\n[9] Saving FPL point estimates...\n")
saveRDS(fpl_estimates, "data/raking/ne25/fpl_estimates_glm2.rds")
cat("    Saved to: data/raking/ne25/fpl_estimates_glm2.rds\n")

# Generate bootstrap replicates using SHARED bootstrap design
cat("\n[10] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design
cat("     Loading shared ACS bootstrap design...\n")
boot_design_full <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")

# Extract replicate weights and filter to FPL sample
cat("     Filtering replicate weights to FPL sample (POVERTY < 600)...\n")
replicate_weights_full <- boot_design_full$repweights

# Detect n_boot from replicate weights
n_boot <- ncol(replicate_weights_full)
cat("     Bootstrap design loaded (", n_boot, " replicates)\n", sep = "")

# Filter rows to match acs_data_fpl (POVERTY < 600 & valid category)
fpl_indicator <- acs_data$POVERTY < 600 & !is.na(acs_data$fpl_category)
replicate_weights_fpl <- replicate_weights_full[fpl_indicator, ]
cat("     Filtered to", nrow(replicate_weights_fpl), "children with valid FPL\n\n")

# Create prediction data frame
pred_data <- data.frame(
  AGE = 0:5,
  MULTYEAR = mean_year
)

# Generate bootstrap estimates using multinom with starting weights
boot_result <- generate_bootstrap_multinom(
  data = acs_data_fpl,
  formula = fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
  replicate_weights = replicate_weights_fpl,
  pred_data = pred_data
)

cat("\n")

# Format bootstrap results for saving
boot_long <- format_multinom_bootstrap_results(
  boot_result = boot_result,
  ages = 0:5,
  estimand_prefix = "fpl_"
)

# Save bootstrap estimates
saveRDS(boot_long, "data/raking/ne25/fpl_estimates_boot_glm2.rds")
cat("[11] Saved bootstrap estimates to: data/raking/ne25/fpl_estimates_boot_glm2.rds\n")
cat("     Bootstrap dimensions:", nrow(boot_long), "rows (5 categories × 6 ages ×", n_boot, "replicates)\n")

cat("\n[12] Key improvements over original approach:\n")
cat("     - Single multinomial model instead of 5 separate binary models\n")
cat("     - Predictions automatically sum to 1.0 (no manual normalization)\n")
cat("     - Statistically more efficient (models category correlations)\n")
cat("     - Bootstrap replicates also sum to 1.0 within each replicate\n")

cat("\n========================================\n")
cat("Task 2.4 Complete (multinom version)\n")
cat("========================================\n\n")

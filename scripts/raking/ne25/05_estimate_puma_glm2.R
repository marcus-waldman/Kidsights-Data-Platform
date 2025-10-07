# Phase 2, Task 2.5: Estimate PUMA Geography Distribution (glm2 version with bootstrap)
# 14 estimands: one for each Nebraska PUMA
# Refactored: January 2025
# Changes: Uses nnet::multinom() instead of 14 separate survey::svyglm() models

library(nnet)
library(dplyr)
source("config/bootstrap_config.R")
source("scripts/raking/ne25/estimation_helpers_glm2.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

cat("\n========================================\n")
cat("Task 2.5: Estimate PUMA Geography (multinom)\n")
cat("========================================\n\n")

# Load ACS design (to extract data and bootstrap weights)
cat("[1] Loading ACS survey design...\n")
acs_design <- readRDS("data/raking/ne25/acs_design.rds")
acs_data <- acs_design$variables
cat("    Sample size:", nrow(acs_data), "\n\n")

# Identify Nebraska PUMAs
cat("[2] Identifying Nebraska PUMAs...\n")
puma_distribution <- table(acs_data$PUMA)
cat("    Found", length(puma_distribution), "PUMAs in Nebraska\n\n")
cat("    PUMA distribution:\n")
print(puma_distribution)
cat("\n")

# Convert PUMA to factor for multinomial model
pumas <- sort(unique(acs_data$PUMA))
n_pumas <- length(pumas)
acs_data$PUMA <- factor(acs_data$PUMA, levels = pumas)

# Estimate PUMA using multinomial logistic regression
cat("[3] Estimating PUMA using multinomial logistic regression...\n")
cat("    Formula: PUMA ~ AGE + MULTYEAR + AGE:MULTYEAR\n")
cat("    Method: Single multinomial model (", n_pumas, " categories)\n\n", sep = "")

# Calculate mean year for prediction
mean_year <- mean(acs_data$MULTYEAR)

puma_est <- fit_multinom_estimates(
  data = acs_data,
  formula = PUMA ~ AGE + MULTYEAR + AGE:MULTYEAR,
  weights_col = "PERWT",
  predict_year = mean_year,
  ages = 0:5
)

cat("\n[4] Predictions by age (first 6 PUMAs):\n")
# Reshape for display
puma_matrix <- matrix(puma_est$estimate, nrow = 6, ncol = n_pumas, byrow = TRUE)
colnames(puma_matrix) <- pumas
rownames(puma_matrix) <- paste("Age", 0:5)
print(round(puma_matrix[, 1:min(6, n_pumas)], 4))

# Validate predictions
cat("\n[5] Validating predictions...\n")

# Check row sums (should all be 1.0)
row_sums <- rowSums(puma_matrix)
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
if (all(puma_matrix >= 0 & puma_matrix <= 1)) {
  cat("    [OK] All predictions in valid range [0, 1]\n")
} else {
  cat("    [WARN] Some predictions outside [0, 1]\n")
}

# Create results data frame
cat("\n[6] Creating results data frame...\n")
puma_estimates <- data.frame(
  age = puma_est$age,
  estimand = paste0("puma_", puma_est$category),
  estimate = puma_est$estimate
)

cat("    Created", nrow(puma_estimates), "rows (6 ages ×", n_pumas, "PUMAs)\n")
cat("\n    Sample rows (first PUMA, all ages):\n")
first_puma_name <- paste0("puma_", pumas[1])
print(puma_estimates[puma_estimates$estimand == first_puma_name, ])

# Summary statistics by PUMA
cat("\n[7] Average proportion by PUMA (across ages):\n")
puma_means <- colMeans(puma_matrix)
puma_summary <- data.frame(
  PUMA = pumas,
  avg_proportion = round(puma_means, 4),
  pct = round(puma_means * 100, 1)
)
print(puma_summary)

# Validate using helper function
cat("\n[8] Multinomial estimate validation:\n")
validate_multinomial_estimates(puma_estimates, "PUMA Distribution")

# Save point estimates
cat("\n[9] Saving PUMA point estimates...\n")
saveRDS(puma_estimates, "data/raking/ne25/puma_estimates_glm2.rds")
cat("    Saved to: data/raking/ne25/puma_estimates_glm2.rds\n")

# Generate bootstrap replicates using SHARED bootstrap design
cat("\n[10] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design
cat("     Loading shared ACS bootstrap design...\n")
boot_design_full <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")

# Extract replicate weights (all ACS data)
replicate_weights_full <- boot_design_full$repweights

# Detect n_boot from replicate weights
n_boot <- ncol(replicate_weights_full)
cat("     Bootstrap design loaded (", n_boot, " replicates)\n", sep = "")
cat("     Using full ACS sample (", nrow(replicate_weights_full), " children)\n\n", sep = "")

# Create prediction data frame
pred_data <- data.frame(
  AGE = 0:5,
  MULTYEAR = mean_year
)

# Generate bootstrap estimates using multinom with starting weights
boot_result <- generate_bootstrap_multinom(
  data = acs_data,
  formula = PUMA ~ AGE + MULTYEAR + AGE:MULTYEAR,
  replicate_weights = replicate_weights_full,
  pred_data = pred_data
)

cat("\n")

# Format bootstrap results for saving
boot_long <- format_multinom_bootstrap_results(
  boot_result = boot_result,
  ages = 0:5,
  estimand_prefix = "puma_"
)

# Save bootstrap estimates
saveRDS(boot_long, "data/raking/ne25/puma_estimates_boot_glm2.rds")
cat("[11] Saved bootstrap estimates to: data/raking/ne25/puma_estimates_boot_glm2.rds\n")
cat("     Bootstrap dimensions:", nrow(boot_long), "rows (", n_pumas, " PUMAs × 6 ages ×", n_boot, "replicates)\n", sep = "")

cat("\n[12] Key improvements over original approach:\n")
cat("     - Single multinomial model instead of ", n_pumas, " separate binary models\n", sep = "")
cat("     - Predictions automatically sum to 1.0 (no manual normalization)\n")
cat("     - Statistically more efficient (models PUMA correlations)\n")
cat("     - Bootstrap replicates also sum to 1.0 within each replicate\n")

cat("\n========================================\n")
cat("Task 2.5 Complete (multinom version)\n")
cat("========================================\n\n")

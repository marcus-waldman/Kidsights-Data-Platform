# Phase 4.1: Estimate PHQ-2 Depression (GLM2 Version)
# Binary outcome: proportion with PHQ-2 ≥3 (positive screen)
# Refactored to use glm2::glm2() instead of survey::svyglm()

library(dplyr)
library(glm2)

cat("\n========================================\n")
cat("Task 4.1: Estimate PHQ-2 Depression (GLM2)\n")
cat("========================================\n\n")

# Load configuration and helper functions
source("config/bootstrap_config.R")
source("scripts/raking/ne25/estimation_helpers_glm2.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

# 1. Load PHQ-2 data
cat("[1] Loading PHQ-2 data...\n")

phq_data <- readRDS("data/raking/ne25/nhis_phq2_data.rds")

cat("    Total parent-child pairs:", nrow(phq_data), "\n")
cat("    Years:", paste(sort(unique(phq_data$YEAR)), collapse = ", "), "\n")

# 2. Check PHQ item coding
cat("\n[2] Checking PHQ item coding...\n")

cat("    PHQINTR distribution:\n")
print(table(phq_data$PHQINTR_parent, useNA = "ifany"))

cat("\n    PHQDEP distribution:\n")
print(table(phq_data$PHQDEP_parent, useNA = "ifany"))

# 3. Recode PHQ items (IPUMS codes → 0-3 scale)
cat("\n[3] Recoding PHQ items (IPUMS codes → 0-3 scale)...\n")

# IPUMS NHIS coding: 0=Not at all, 1=Several days, 2=More than half, 3=Nearly every day
# 7=Unknown-refused, 8=Unknown-not ascertained, 9=Unknown-don't know
# PHQ-2 standard: Same as IPUMS (0-3), but need to filter out 7/8/9

# Filter out missing codes (7, 8, 9) and set to NA
phq_data <- phq_data %>%
  dplyr::mutate(
    phqintr_recoded = dplyr::if_else(PHQINTR_parent >= 0 & PHQINTR_parent <= 3,
                                     PHQINTR_parent, NA_real_),
    phqdep_recoded = dplyr::if_else(PHQDEP_parent >= 0 & PHQDEP_parent <= 3,
                                    PHQDEP_parent, NA_real_)
  )

cat("    PHQINTR recoded distribution (0-3):\n")
print(table(phq_data$phqintr_recoded, useNA = "ifany"))

cat("\n    PHQDEP recoded distribution (0-3):\n")
print(table(phq_data$phqdep_recoded, useNA = "ifany"))

# 4. Calculate PHQ-2 total score
cat("\n[4] Calculating PHQ-2 total score (0-6)...\n")

# Only calculate total if both items are valid (not NA)
phq_data <- phq_data %>%
  dplyr::mutate(
    phq2_total = dplyr::if_else(!is.na(phqintr_recoded) & !is.na(phqdep_recoded),
                                phqintr_recoded + phqdep_recoded,
                                NA_real_)
  )

# Filter to complete cases only
phq_data_complete <- phq_data %>%
  dplyr::filter(!is.na(phq2_total))

cat("    Records with complete PHQ-2:", nrow(phq_data_complete), "\n")
cat("    Records excluded (missing data):", nrow(phq_data) - nrow(phq_data_complete), "\n")

# Use complete cases for subsequent analysis
phq_data <- phq_data_complete

cat("    PHQ-2 total distribution:\n")
print(table(phq_data$phq2_total, useNA = "ifany"))

cat("\n    Summary statistics:\n")
cat("      Min:", min(phq_data$phq2_total, na.rm = TRUE), "\n")
cat("      Max:", max(phq_data$phq2_total, na.rm = TRUE), "\n")
cat("      Mean:", round(mean(phq_data$phq2_total, na.rm = TRUE), 2), "\n")
cat("      Median:", median(phq_data$phq2_total, na.rm = TRUE), "\n")

# 5. Create binary positive screen indicator (PHQ-2 ≥3)
cat("\n[5] Creating binary positive screen indicator (PHQ-2 >=3)...\n")

phq_data <- phq_data %>%
  dplyr::mutate(
    phq2_positive = as.numeric(phq2_total >= 3)
  )

cat("    Positive screens (unweighted):", sum(phq_data$phq2_positive), "\n")
cat("    Negative screens (unweighted):", sum(phq_data$phq2_positive == 0), "\n")
cat("    Proportion positive (unweighted):",
    round(mean(phq_data$phq2_positive), 3), "\n")

# 6. Estimate PHQ-2 positive rate with glm2
cat("\n[6] Estimating PHQ-2 positive rate with glm2 (year main effects)...\n")

# Create modeling dataset with weights column
cat("    Preparing data...\n")
modeling_data <- phq_data
modeling_data$.weights <- phq_data$ADULTW_parent

# Fit glm2 model (YEAR as continuous predictor)
cat("    Fitting glm2 model...\n")

# Need to use weights directly without formula reference
# This is a known glm2 scoping issue - pass weights as vector
model_phq2 <- glm2::glm2(
  phq2_positive ~ YEAR,
  data = modeling_data,
  weights = modeling_data$.weights,  # Pass as vector, not column name
  family = binomial()
)

cat("    Model converged in", model_phq2$iter, "iterations\n")

# Prediction data: 2023 (most recent year, will be replicated for ages 0-5)
pred_data <- data.frame(YEAR = 2023)

# Get point estimate
phq2_estimate <- predict(model_phq2, newdata = pred_data, type = "response")[1]

cat("\n    Point estimate (at 2023):", round(phq2_estimate, 4),
    "(", round(phq2_estimate * 100, 1), "%)\n")

# For context, show by-year predictions
cat("\n    Estimates by year (for context):\n")
for (year in sort(unique(modeling_data$YEAR))) {
  pred_year <- data.frame(YEAR = year)
  est_year <- predict(model_phq2, newdata = pred_year, type = "response")[1]
  cat("      Year", year, ":", round(est_year, 4),
      "(", round(est_year * 100, 1), "%)\n")
}

# 7. Create results data frame
cat("\n[7] Creating results data frame...\n")

# PHQ-2 is constant across child ages (parent characteristic), use 2023 estimate
phq2_result <- data.frame(
  age = 0:5,
  estimand = "PHQ-2 Positive",
  estimate = rep(phq2_estimate, 6)
)

print(phq2_result)

# 8. Validate estimate
cat("\n[8] Validation checks...\n")

# Range check
if (phq2_estimate >= 0 && phq2_estimate <= 1) {
  cat("    [OK] Estimate in valid range [0, 1]\n")
} else {
  cat("    [ERROR] Estimate out of range\n")
}

# Plausibility check (national PHQ-2 rates typically 5-15%)
if (phq2_estimate >= 0.03 && phq2_estimate <= 0.20) {
  cat("    [OK] Plausible for North Central region (3-20%)\n")
} else {
  cat("    [WARN] Outside typical range (3-20%)\n")
}

# 9. Save point estimates
cat("\n[9] Saving PHQ-2 point estimate...\n")

saveRDS(phq2_result, "data/raking/ne25/phq2_estimate_glm2.rds")
cat("    Saved to: data/raking/ne25/phq2_estimate_glm2.rds\n")

# 10. Generate bootstrap replicates
cat("\n[10] Generating bootstrap replicates with glm2...\n")

# Load shared NHIS bootstrap design
# NOTE: Bootstrap design was created from nhis_phq2_scored.rds (complete cases only)
# which matches our phq_data after filtering, so row counts should align
boot_design_full <- readRDS("data/raking/ne25/nhis_bootstrap_design.rds")
replicate_weights_full <- boot_design_full$repweights

cat("     Bootstrap design loaded (n =", nrow(boot_design_full$variables), ")\n")
cat("     Total replicates available:", ncol(replicate_weights_full), "\n")

# Verify row count match
if (nrow(replicate_weights_full) != nrow(phq_data)) {
  stop("ERROR: Bootstrap design row count (", nrow(replicate_weights_full),
       ") != phq_data row count (", nrow(phq_data), ")!")
}

# Respect bootstrap config
n_boot <- BOOTSTRAP_CONFIG$n_boot
if (ncol(replicate_weights_full) > n_boot) {
  cat("     [INFO] Using first", n_boot, "replicates (from", ncol(replicate_weights_full), "available)\n")
  replicate_weights_full <- replicate_weights_full[, 1:n_boot]
}

# Generate bootstrap using helper function
boot_result <- generate_bootstrap_glm2(
  data = modeling_data,  # Use modeling_data which has .weights column
  formula = phq2_positive ~ YEAR,
  replicate_weights = replicate_weights_full,
  pred_data = pred_data
)

cat("     Bootstrap complete:", nrow(boot_result$boot_estimates), "predictions x",
    ncol(boot_result$boot_estimates), "replicates\n")

# 11. Format and save bootstrap replicates
cat("\n[11] Formatting and saving bootstrap replicates...\n")

# Since PHQ-2 is constant across ages, replicate the single bootstrap estimate across ages 0-5
ages <- 0:5
boot_estimates <- boot_result$boot_estimates  # Use correct field name
n_boot_actual <- ncol(boot_estimates)

cat("    Boot estimates dimensions:", nrow(boot_estimates), "x", n_boot_actual, "\n")
cat("    Creating", length(ages), "ages x", n_boot_actual, "replicates =",
    length(ages) * n_boot_actual, "rows\n")

# Create bootstrap results data frame
# boot_result$boot_estimates is 1 x n_boot (1 prediction × n_boot replicates)
# Need to replicate across 6 ages
phq2_boot <- data.frame(
  age = rep(ages, times = n_boot_actual),
  estimand = "phq2_positive",
  replicate = rep(1:n_boot_actual, each = length(ages)),
  estimate = rep(as.numeric(boot_estimates[1, ]), each = length(ages))
)

cat("    Bootstrap replicates formatted:\n")
cat("      Total rows:", nrow(phq2_boot), "(6 ages x", n_boot, "replicates)\n")
cat("      Columns:", paste(names(phq2_boot), collapse = ", "), "\n\n")

# Verify structure
cat("    First few rows:\n")
print(head(phq2_boot, 12))

# Save bootstrap replicates
saveRDS(phq2_boot, "data/raking/ne25/phq2_estimate_boot_glm2.rds")
cat("\n    Bootstrap replicates saved to: data/raking/ne25/phq2_estimate_boot_glm2.rds\n")

cat("\n========================================\n")
cat("Task 4.1 Complete (GLM2 with Bootstrap)\n")
cat("========================================\n")
cat("\nSummary:\n")
cat("  - Sample size:", nrow(phq_data), "parent-child pairs (complete data)\n")
cat("  - Years: 2019, 2022, 2023 (pooled with year main effects)\n")
cat("  - PHQ-2 positive rate:", round(phq2_estimate * 100, 1), "% (at 2023)\n")
cat("  - Constant across child ages 0-5 (parent characteristic)\n")
cat("  - Bootstrap replicates:", n_boot, "\n")
cat("  - Total bootstrap rows:", nrow(phq2_boot), "(6 ages x", n_boot, "replicates)\n")
cat("  - Model iterations:", model_phq2$iter, "\n\n")

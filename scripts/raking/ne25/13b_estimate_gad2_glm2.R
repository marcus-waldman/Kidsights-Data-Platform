# Phase 4.2: Estimate GAD-2 Anxiety (GLM2 Version)
# Binary outcome: proportion with GAD-2 ≥3 (positive screen)
# Adapted from PHQ-2 script - same methodology

library(dplyr)
library(glm2)

cat("\n========================================\n")
cat("Task 4.2: Estimate GAD-2 Anxiety (GLM2)\n")
cat("========================================\n\n")

# Load configuration and helper functions
source("config/bootstrap_config.R")
source("scripts/raking/ne25/estimation_helpers_glm2.R")
source("scripts/raking/ne25/bootstrap_helpers_glm2.R")

# 1. Load GAD-2 data
cat("[1] Loading GAD-2 data...\n")

gad_data <- readRDS("data/raking/ne25/nhis_gad2_data.rds")

cat("    Total parent-child pairs:", nrow(gad_data), "\n")
cat("    Years:", paste(sort(unique(gad_data$YEAR)), collapse = ", "), "\n")

# 2. Check GAD item coding
cat("\n[2] Checking GAD item coding...\n")

cat("    GADANX distribution:\n")
print(table(gad_data$GADANX_parent, useNA = "ifany"))

cat("\n    GADWORCTRL distribution:\n")
print(table(gad_data$GADWORCTRL_parent, useNA = "ifany"))

# 3. Recode GAD items (IPUMS codes → 0-3 scale)
cat("\n[3] Recoding GAD items (IPUMS codes → 0-3 scale)...\n")

# IPUMS NHIS coding: 0=Not at all, 1=Several days, 2=More than half, 3=Nearly every day
# 7=Unknown-refused, 8=Unknown-not ascertained, 9=Unknown-don't know
# GAD-2 standard: Same as IPUMS (0-3), but need to filter out 7/8/9

# Filter out missing codes (7, 8, 9) and set to NA
gad_data <- gad_data %>%
  dplyr::mutate(
    gadanx_recoded = dplyr::if_else(GADANX_parent >= 0 & GADANX_parent <= 3,
                                     GADANX_parent, NA_real_),
    gadworctrl_recoded = dplyr::if_else(GADWORCTRL_parent >= 0 & GADWORCTRL_parent <= 3,
                                        GADWORCTRL_parent, NA_real_)
  )

cat("    GADANX recoded distribution (0-3):\n")
print(table(gad_data$gadanx_recoded, useNA = "ifany"))

cat("\n    GADWORCTRL recoded distribution (0-3):\n")
print(table(gad_data$gadworctrl_recoded, useNA = "ifany"))

# 4. Calculate GAD-2 total score
cat("\n[4] Calculating GAD-2 total score (0-6)...\n")

# Only calculate total if both items are valid (not NA)
gad_data <- gad_data %>%
  dplyr::mutate(
    gad2_total = dplyr::if_else(!is.na(gadanx_recoded) & !is.na(gadworctrl_recoded),
                                gadanx_recoded + gadworctrl_recoded,
                                NA_real_)
  )

# Filter to complete cases only
gad_data_complete <- gad_data %>%
  dplyr::filter(!is.na(gad2_total))

cat("    Records with complete GAD-2:", nrow(gad_data_complete), "\n")
cat("    Records excluded (missing data):", nrow(gad_data) - nrow(gad_data_complete), "\n")

# Use complete cases for subsequent analysis
gad_data <- gad_data_complete

cat("    GAD-2 total distribution:\n")
print(table(gad_data$gad2_total, useNA = "ifany"))

cat("\n    Summary statistics:\n")
cat("      Min:", min(gad_data$gad2_total, na.rm = TRUE), "\n")
cat("      Max:", max(gad_data$gad2_total, na.rm = TRUE), "\n")
cat("      Mean:", round(mean(gad_data$gad2_total, na.rm = TRUE), 2), "\n")
cat("      Median:", median(gad_data$gad2_total, na.rm = TRUE), "\n")

# 5. Create binary positive screen indicator (GAD-2 ≥3)
cat("\n[5] Creating binary positive screen indicator (GAD-2 >=3)...\n")

gad_data <- gad_data %>%
  dplyr::mutate(
    gad2_positive = as.numeric(gad2_total >= 3)
  )

cat("    Positive screens (unweighted):", sum(gad_data$gad2_positive), "\n")
cat("    Negative screens (unweighted):", sum(gad_data$gad2_positive == 0), "\n")
cat("    Proportion positive (unweighted):",
    round(mean(gad_data$gad2_positive), 3), "\n")

# 6. Estimate GAD-2 positive rate with glm2
cat("\n[6] Estimating GAD-2 positive rate with glm2 (year main effects)...\n")

# Create modeling dataset with weights column
cat("    Preparing data...\n")
modeling_data <- gad_data
modeling_data$.weights <- gad_data$ADULTW_parent

# Fit glm2 model (YEAR as continuous predictor)
cat("    Fitting glm2 model...\n")

# Need to use weights directly without formula reference
# This is a known glm2 scoping issue - pass weights as vector
model_gad2 <- glm2::glm2(
  gad2_positive ~ YEAR,
  data = modeling_data,
  weights = modeling_data$.weights,  # Pass as vector, not column name
  family = binomial()
)

cat("    Model converged in", model_gad2$iter, "iterations\n")

# Prediction data: 2023 (most recent year, will be replicated for ages 0-5)
pred_data <- data.frame(YEAR = 2023)

# Get point estimate
gad2_estimate <- predict(model_gad2, newdata = pred_data, type = "response")[1]

cat("\n    Point estimate (at 2023):", round(gad2_estimate, 4),
    "(", round(gad2_estimate * 100, 1), "%)\n")

# For context, show by-year predictions
cat("\n    Estimates by year (for context):\n")
for (year in sort(unique(modeling_data$YEAR))) {
  pred_year <- data.frame(YEAR = year)
  est_year <- predict(model_gad2, newdata = pred_year, type = "response")[1]
  cat("      Year", year, ":", round(est_year, 4),
      "(", round(est_year * 100, 1), "%)\n")
}

# 7. Create results data frame
cat("\n[7] Creating results data frame...\n")

# GAD-2 is constant across child ages (parent characteristic), use 2023 estimate
gad2_result <- data.frame(
  age = 0:5,
  estimand = "GAD-2 Positive",
  estimate = rep(gad2_estimate, 6)
)

print(gad2_result)

# 8. Validate estimate
cat("\n[8] Validation checks...\n")

# Range check
if (gad2_estimate >= 0 && gad2_estimate <= 1) {
  cat("    [OK] Estimate in valid range [0, 1]\n")
} else {
  cat("    [ERROR] Estimate out of range\n")
}

# Plausibility check (national GAD-2 rates typically 5-20%)
if (gad2_estimate >= 0.03 && gad2_estimate <= 0.25) {
  cat("    [OK] Plausible for North Central region (3-25%)\n")
} else {
  cat("    [WARN] Outside typical range (3-25%)\n")
}

# 9. Save point estimates
cat("\n[9] Saving GAD-2 point estimate...\n")

saveRDS(gad2_result, "data/raking/ne25/gad2_estimate_glm2.rds")
cat("    Saved to: data/raking/ne25/gad2_estimate_glm2.rds\n")

# 10. Generate bootstrap replicates
cat("\n[10] Generating bootstrap replicates with glm2...\n")

# Load shared NHIS bootstrap design
# NOTE: Bootstrap design was created from nhis_phq2_scored.rds (complete cases only)
# GAD-2 has slightly different missingness, so we need to match rows
boot_design_full <- readRDS("data/raking/ne25/nhis_bootstrap_design.rds")
replicate_weights_full <- boot_design_full$repweights
boot_ids <- boot_design_full$variables

cat("     Bootstrap design loaded (n =", nrow(boot_design_full$variables), ")\n")
cat("     Total replicates available:", ncol(replicate_weights_full), "\n")

# Match GAD-2 data to bootstrap design using SERIAL + PERNUM_child + YEAR as key
cat("     Matching GAD-2 data to bootstrap design...\n")
gad_data$match_id <- paste(gad_data$SERIAL, gad_data$PERNUM_child, gad_data$YEAR, sep = "_")
boot_ids$match_id <- paste(boot_ids$SERIAL, boot_ids$PERNUM_child, boot_ids$YEAR, sep = "_")

# Find matching rows
gad_matched <- gad_data %>%
  dplyr::filter(match_id %in% boot_ids$match_id) %>%
  dplyr::arrange(match_id)

boot_matched <- boot_ids %>%
  dplyr::filter(match_id %in% gad_data$match_id) %>%
  dplyr::arrange(match_id)

cat("     GAD-2 complete cases:", nrow(gad_data), "\n")
cat("     Bootstrap design cases:", nrow(boot_ids), "\n")
cat("     Matched cases:", nrow(gad_matched), "\n")

# Use matched subset
modeling_data_boot <- gad_matched
modeling_data_boot$.weights <- gad_matched$ADULTW_parent

# Get matching bootstrap weights (reorder to match gad_matched)
boot_match_indices <- match(gad_matched$match_id, boot_ids$match_id)
replicate_weights_matched <- replicate_weights_full[boot_match_indices, ]

cat("     Replicate weights subset dimensions:", nrow(replicate_weights_matched), "x",
    ncol(replicate_weights_matched), "\n")

# Verify row count match
if (nrow(replicate_weights_matched) != nrow(gad_matched)) {
  stop("ERROR: Bootstrap weights row count (", nrow(replicate_weights_matched),
       ") != matched GAD data row count (", nrow(gad_matched), ")!")
}

# Detect n_boot from replicate weights
n_boot <- ncol(replicate_weights_matched)
cat("     Bootstrap replicates:", n_boot, "\n")

# Generate bootstrap using helper function
boot_result <- generate_bootstrap_glm2(
  data = modeling_data_boot,  # Use matched data with .weights column
  formula = gad2_positive ~ YEAR,
  replicate_weights = replicate_weights_matched,
  pred_data = pred_data
)

cat("     Bootstrap complete:", nrow(boot_result$boot_estimates), "predictions x",
    ncol(boot_result$boot_estimates), "replicates\n")

# 11. Format and save bootstrap replicates
cat("\n[11] Formatting and saving bootstrap replicates...\n")

# Since GAD-2 is constant across ages, replicate the single bootstrap estimate across ages 0-5
ages <- 0:5
boot_estimates <- boot_result$boot_estimates  # Use correct field name
n_boot_actual <- ncol(boot_estimates)

cat("    Boot estimates dimensions:", nrow(boot_estimates), "x", n_boot_actual, "\n")
cat("    Creating", length(ages), "ages x", n_boot_actual, "replicates =",
    length(ages) * n_boot_actual, "rows\n")

# Create bootstrap results data frame
# boot_result$boot_estimates is 1 x n_boot (1 prediction × n_boot replicates)
# Need to replicate across 6 ages
gad2_boot <- data.frame(
  age = rep(ages, times = n_boot_actual),
  estimand = "gad2_positive",
  replicate = rep(1:n_boot_actual, each = length(ages)),
  estimate = rep(as.numeric(boot_estimates[1, ]), each = length(ages))
)

cat("    Bootstrap replicates formatted:\n")
cat("      Total rows:", nrow(gad2_boot), "(6 ages x", n_boot, "replicates)\n")
cat("      Columns:", paste(names(gad2_boot), collapse = ", "), "\n\n")

# Verify structure
cat("    First few rows:\n")
print(head(gad2_boot, 12))

# Save bootstrap replicates
saveRDS(gad2_boot, "data/raking/ne25/gad2_estimate_boot_glm2.rds")
cat("\n    Bootstrap replicates saved to: data/raking/ne25/gad2_estimate_boot_glm2.rds\n")

cat("\n========================================\n")
cat("Task 4.2 Complete (GLM2 with Bootstrap)\n")
cat("========================================\n")
cat("\nSummary:\n")
cat("  - Sample size (point estimate):", nrow(gad_data), "parent-child pairs\n")
cat("  - Sample size (bootstrap):", nrow(gad_matched), "parent-child pairs (matched to PHQ-2)\n")
cat("  - Years: 2019, 2022, 2023 (pooled with year main effects)\n")
cat("  - GAD-2 positive rate:", round(gad2_estimate * 100, 1), "% (at 2023)\n")
cat("  - Constant across child ages 0-5 (parent characteristic)\n")
cat("  - Bootstrap replicates:", n_boot, "\n")
cat("  - Total bootstrap rows:", nrow(gad2_boot), "(6 ages x", n_boot, "replicates)\n")
cat("  - Model iterations:", model_gad2$iter, "\n\n")

# Phase 3, Task 3.2: Estimate PHQ-2 Depression
# Binary outcome: proportion with PHQ-2 ≥3 (positive screen)

library(survey)
library(dplyr)

cat("\n========================================\n")
cat("Task 3.2: Estimate PHQ-2 Depression\n")
cat("========================================\n\n")

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
cat("\n[5] Creating binary positive screen indicator (PHQ-2 \u22653)...\n")

phq_data <- phq_data %>%
  dplyr::mutate(
    phq2_positive = as.numeric(phq2_total >= 3)
  )

cat("    Positive screens (unweighted):", sum(phq_data$phq2_positive), "\n")
cat("    Negative screens (unweighted):", sum(phq_data$phq2_positive == 0), "\n")
cat("    Proportion positive (unweighted):",
    round(mean(phq_data$phq2_positive), 3), "\n")

# 6. Load shared bootstrap design
cat("\n[6] Loading shared NHIS bootstrap design...\n")

# Load the shared bootstrap design created by 12a_create_nhis_bootstrap_design.R
boot_design <- readRDS("data/raking/ne25/nhis_bootstrap_design.rds")

cat("    Bootstrap design loaded\n")
cat("    Sample size:", nrow(boot_design), "\n")
cat("    Number of replicates:", ncol(boot_design$repweights), "\n")
cat("    Number of PSUs:", length(unique(phq_data$PSU_child)), "\n")
cat("    Number of strata:", length(unique(phq_data$STRATA_child)), "\n")

# 7. Estimate PHQ-2 positive rate with bootstrap
cat("\n[7] Estimating PHQ-2 positive rate (survey-weighted GLM with year main effects)...\n")
cat("    Loading bootstrap helper functions...\n")

source("scripts/raking/ne25/bootstrap_helpers.R")

# Generate bootstrap replicates using shared bootstrap design
cat("\n    Generating bootstrap replicates (SHARED replicate weights)...\n")

# Prediction data: 2023 (most recent year), replicated for ages 0-5
pred_data <- data.frame(YEAR = 2023)

# Call bootstrap helper function
boot_result <- generate_nhis_bootstrap(
  boot_design = boot_design,
  formula = phq2_positive ~ YEAR,
  pred_data = pred_data,
  family = quasibinomial()
)

# Extract point estimate (single value, will be replicated across ages)
phq2_estimate <- boot_result$point_estimates[1]

cat("\n    Point estimate (at 2023):", round(phq2_estimate, 4),
    "(", round(phq2_estimate * 100, 1), "%)\n")

# For context, also fit model and show by-year predictions
model_phq2 <- survey::svyglm(
  phq2_positive ~ YEAR,
  design = boot_design,
  family = quasibinomial()
)

cat("\n    Estimates by year (for context):\n")
for (year in sort(unique(phq_data$YEAR))) {
  pred_year <- data.frame(YEAR = year)
  est_year <- predict(model_phq2, newdata = pred_year, type = "response")[1]
  cat("      Year", year, ":", round(est_year, 4),
      "(", round(est_year * 100, 1), "%)\n")
}

# 8. Create results data frame
cat("\n[8] Creating results data frame...\n")

# PHQ-2 is constant across child ages (parent characteristic), use mean year estimate
phq2_result <- data.frame(
  age = 0:5,
  estimand = "PHQ-2 Positive",
  estimate = rep(phq2_estimate, 6)
)

print(phq2_result)

# 9. Validate estimate
cat("\n[9] Validation checks...\n")

# Range check
if (phq2_estimate >= 0 && phq2_estimate <= 1) {
  cat("    \u2713 Estimate in valid range [0, 1]\n")
} else {
  cat("    \u2717 ERROR: Estimate out of range\n")
}

# Plausibility check (national PHQ-2 rates typically 5-15%)
if (phq2_estimate >= 0.03 && phq2_estimate <= 0.20) {
  cat("    \u2713 Plausible for North Central region (3-20%)\n")
} else {
  cat("    \u26a0 WARNING: Outside typical range (3-20%)\n")
}

# 10. Check by year
cat("\n[10] PHQ-2 positive rates by year (for context)...\n")

year_rates <- phq_data %>%
  dplyr::group_by(YEAR) %>%
  dplyr::summarise(
    n = dplyr::n(),
    n_positive = sum(phq2_positive),
    rate_unweighted = mean(phq2_positive),
    .groups = "drop"
  )

print(year_rates)

# 11. Save point estimates
cat("\n[11] Saving PHQ-2 point estimate...\n")

saveRDS(phq2_result, "data/raking/ne25/phq2_estimate.rds")
cat("    Saved to: data/raking/ne25/phq2_estimate.rds\n")

# 12. Format and save bootstrap replicates
cat("\n[12] Formatting and saving bootstrap replicates...\n")

# Since PHQ-2 is constant across ages, replicate the single bootstrap estimate across ages 0-5
n_boot <- boot_result$n_boot
ages <- 0:5

# Create bootstrap results data frame
# boot_result$boot_estimates is 1x4 (1 prediction × 4 replicates)
# Need to replicate across 6 ages
phq2_boot <- data.frame(
  age = rep(ages, times = n_boot),
  estimand = "phq2_positive",
  replicate = rep(1:n_boot, each = length(ages)),
  estimate = rep(as.numeric(boot_result$boot_estimates[1, ]), each = length(ages))
)

cat("    Bootstrap replicates formatted:\n")
cat("      Total rows:", nrow(phq2_boot), "(6 ages ×", n_boot, "replicates)\n")
cat("      Columns:", paste(names(phq2_boot), collapse = ", "), "\n\n")

# Verify structure
cat("    First few rows:\n")
print(head(phq2_boot, 12))

# Save bootstrap replicates
saveRDS(phq2_boot, "data/raking/ne25/phq2_estimate_boot.rds")
cat("\n    Bootstrap replicates saved to: data/raking/ne25/phq2_estimate_boot.rds\n")

# Save full PHQ-2 data with scores
saveRDS(phq_data, "data/raking/ne25/nhis_phq2_scored.rds")
cat("    Saved scored data to: data/raking/ne25/nhis_phq2_scored.rds\n")

cat("\n========================================\n")
cat("Task 3.2 Complete (with Bootstrap)\n")
cat("========================================\n")
cat("\nSummary:\n")
cat("  - Sample size:", nrow(phq_data), "parent-child pairs (complete data)\n")
cat("  - Years: 2019, 2022, 2023 (pooled with year main effects)\n")
cat("  - PHQ-2 positive rate:", round(phq2_estimate * 100, 1), "% (at 2023)\n")
cat("  - Constant across child ages 0-5 (parent characteristic)\n")
cat("  - Bootstrap replicates:", n_boot, "(shared NHIS design)\n")
cat("  - Total bootstrap rows:", nrow(phq2_boot), "(6 ages ×", n_boot, "replicates)\n\n")

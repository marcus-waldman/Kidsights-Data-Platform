# Phase 2, Task 2.5: Estimate PUMA Geography Distribution (with bootstrap replicates)
# 14 estimands: one for each Nebraska PUMA

library(survey)
library(dplyr)
source("scripts/raking/ne25/estimation_helpers.R")
source("scripts/raking/ne25/bootstrap_helpers.R")

cat("\n========================================\n")
cat("Task 2.5: Estimate PUMA Geography\n")
cat("========================================\n\n")

# Load ACS design
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

# 1. Identify Nebraska PUMAs
cat("[1] Identifying Nebraska PUMAs...\n")
acs_data <- acs_design$variables

puma_distribution <- table(acs_data$PUMA)
cat("    Found", length(puma_distribution), "PUMAs in Nebraska\n\n")
cat("    PUMA distribution:\n")
print(puma_distribution)
cat("\n")

# Convert to data frame for display
puma_counts <- data.frame(
  PUMA = names(puma_distribution),
  count = as.numeric(puma_distribution)
)
puma_counts <- puma_counts[order(puma_counts$PUMA), ]

# 2. Fit separate binary logistic models for each PUMA
cat("[2] Fitting binary logistic models for each PUMA...\n")

pumas <- sort(unique(acs_data$PUMA))
n_pumas <- length(pumas)

mean_year <- mean(acs_data$MULTYEAR)
pred_data <- data.frame(
  AGE = 0:5,
  MULTYEAR = mean_year
)

# Store predictions for each PUMA
puma_raw_predictions <- matrix(0, nrow = 6, ncol = n_pumas)
colnames(puma_raw_predictions) <- pumas

for (i in 1:n_pumas) {
  cat("    Fitting model for PUMA", pumas[i], "...\n")

  # Create binary indicator
  acs_design$variables$current_puma <- as.numeric(acs_design$variables$PUMA == pumas[i])

  # Fit model
  model <- survey::svyglm(
    current_puma ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design,
    family = quasibinomial()
  )

  # Get predictions
  preds <- predict(model, newdata = pred_data, type = "response")
  puma_raw_predictions[, i] <- as.numeric(preds)
}

cat("    All", n_pumas, "models fitted successfully\n")

# 3. Normalize predictions to sum to 1.0
cat("\n[3] Normalizing predictions (ensure row sums = 1.0)...\n")

puma_predictions <- puma_raw_predictions / rowSums(puma_raw_predictions)

cat("    Predictions generated (6 ages ×", n_pumas, "PUMAs)\n")
cat("\n    First 6 PUMAs by age:\n")
print(round(puma_predictions[, 1:min(6, n_pumas)], 4))

# 4. Validate predictions
cat("\n[4] Validating predictions...\n")

# Check row sums (should all be 1.0)
row_sums <- rowSums(puma_predictions)
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
if (all(puma_predictions >= 0 & puma_predictions <= 1)) {
  cat("    [OK] All predictions in valid range [0, 1]\n")
} else {
  cat("    [WARN] Some predictions outside [0, 1]\n")
}

# 5. Create results data frame
cat("\n[5] Creating results data frame...\n")

puma_estimates <- data.frame(
  age = rep(0:5, each = n_pumas),
  estimand = rep(paste0("puma_", pumas), 6),
  estimate = as.vector(t(puma_predictions))
)

cat("    Created", nrow(puma_estimates), "rows (6 ages ×", n_pumas, "PUMAs)\n")
cat("\n    Sample rows (first PUMA, all ages):\n")
first_puma_name <- paste0("puma_", pumas[1])
print(puma_estimates[puma_estimates$estimand == first_puma_name, ])

# 6. Summary statistics by PUMA
cat("\n[6] Average proportion by PUMA (across ages):\n")
puma_means <- colMeans(puma_predictions)
puma_summary <- data.frame(
  PUMA = pumas,
  avg_proportion = round(puma_means, 4),
  pct = round(puma_means * 100, 1)
)
print(puma_summary)

# 7. Save point estimates
cat("\n[7] Saving PUMA point estimates...\n")
saveRDS(puma_estimates, "data/raking/ne25/puma_estimates.rds")
cat("    Saved to: data/raking/ne25/puma_estimates.rds\n")

# 8. Generate bootstrap replicates for all PUMAs using SHARED bootstrap design
cat("\n[8] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design
cat("    Loading shared ACS bootstrap design...\n")
boot_design <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")
cat("    Bootstrap design loaded (", ncol(boot_design$repweights), " replicates)\n\n", sep = "")

# Store bootstrap results for each PUMA
boot_results_list <- list()

# Generate bootstrap for each PUMA
for (i in 1:n_pumas) {
  cat("    [8.", i, "] Generating bootstrap for PUMA ", pumas[i], "...\n", sep = "")

  # Create binary indicator for this PUMA
  boot_design$variables$current_puma <- as.numeric(boot_design$variables$PUMA == pumas[i])

  # Generate bootstrap estimates
  boot_result <- generate_acs_bootstrap(
    boot_design = boot_design,
    formula = current_puma ~ AGE + MULTYEAR + AGE:MULTYEAR,
    pred_data = pred_data,
    family = quasibinomial()
  )

  # Format as long data
  estimand_name <- paste0("puma_", pumas[i])
  boot_long <- format_bootstrap_results(
    boot_result = boot_result,
    ages = 0:5,
    estimand_name = estimand_name
  )

  boot_results_list[[i]] <- boot_long
}

# Combine all bootstrap results
puma_boot_estimates <- dplyr::bind_rows(boot_results_list)

# Save bootstrap estimates
saveRDS(puma_boot_estimates, "data/raking/ne25/puma_estimates_boot.rds")
cat("    Saved bootstrap estimates to: data/raking/ne25/puma_estimates_boot.rds\n")
cat("    Bootstrap dimensions:", nrow(puma_boot_estimates), "rows (", n_pumas, " PUMAs × 6 ages × n_boot replicates)\n", sep = "")

cat("\n[9] Bootstrap generation complete\n")
cat("    Note: Bootstrap replicates are NOT normalized across PUMAs\n")
cat("    Normalization will be applied during post-stratification weighting\n")

cat("\n========================================\n")
cat("Task 2.5 Complete (with Bootstrap)\n")
cat("========================================\n\n")

# Phase 2, Task 2.4: Estimate Federal Poverty Level Distribution (with bootstrap replicates)
# 5 estimands: 0-99%, 100-199%, 200-299%, 300-399%, 400%+

library(survey)
library(nnet)
source("scripts/raking/ne25/estimation_helpers.R")
source("scripts/raking/ne25/bootstrap_helpers.R")

cat("\n========================================\n")
cat("Task 2.4: Estimate Federal Poverty Level\n")
cat("========================================\n\n")

# Load ACS design
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

# 1. Create FPL category variable
cat("[1] Creating FPL category variable...\n")

# Extract data from survey design
acs_data <- acs_design$variables

# Create 5-level FPL category
# POVERTY variable: ratio of income to poverty threshold * 100
# 0-99 = below poverty, 100-199 = 1-2x poverty, etc.
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

# Recreate survey design with filtered data
acs_design_fpl <- survey::svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_fpl,
  nest = TRUE
)

# 2. Fit separate binary models for each FPL category
cat("[2] Fitting binary logistic models for each FPL category...\n")

# We'll fit 5 separate models and normalize to ensure probabilities sum to 1
mean_year <- mean(acs_data_fpl$MULTYEAR)
pred_data <- data.frame(
  AGE = 0:5,
  MULTYEAR = mean_year
)

# Store predictions for each category
fpl_raw_predictions <- matrix(0, nrow = 6, ncol = 5)
colnames(fpl_raw_predictions) <- c("0-99%", "100-199%", "200-299%", "300-399%", "400%+")

categories <- c("0-99%", "100-199%", "200-299%", "300-399%", "400%+")

for (i in 1:5) {
  cat("    Fitting model for", categories[i], "...\n")

  # Create binary indicator
  acs_design_fpl$variables$current_category <- as.numeric(acs_design_fpl$variables$fpl_category == categories[i])

  # Fit model
  model <- survey::svyglm(
    current_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design_fpl,
    family = quasibinomial()
  )

  # Get predictions
  preds <- predict(model, newdata = pred_data, type = "response")
  fpl_raw_predictions[, i] <- as.numeric(preds)
}

cat("    All 5 models fitted successfully\n")

# 3. Normalize predictions to sum to 1.0
cat("\n[3] Normalizing predictions (ensure row sums = 1.0)...\n")

fpl_predictions <- fpl_raw_predictions / rowSums(fpl_raw_predictions)

cat("    Predictions generated (6 ages × 5 categories)\n")
cat("\n    Predictions by age:\n")
print(round(fpl_predictions, 4))

# 4. Validate predictions
cat("\n[4] Validating predictions...\n")

# Check row sums (should all be 1.0)
row_sums <- rowSums(fpl_predictions)
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
if (all(fpl_predictions >= 0 & fpl_predictions <= 1)) {
  cat("    [OK] All predictions in valid range [0, 1]\n")
} else {
  cat("    [WARN] Some predictions outside [0, 1]\n")
}

# 5. Create results data frame
cat("\n[5] Creating results data frame...\n")

fpl_estimates <- data.frame(
  age = rep(0:5, each = 5),
  estimand = rep(c("0-99%", "100-199%", "200-299%", "300-399%", "400%+"), 6),
  estimate = as.vector(t(fpl_predictions))
)

cat("    Created", nrow(fpl_estimates), "rows (6 ages × 5 categories)\n")
cat("\n    First 10 rows:\n")
print(head(fpl_estimates, 10))

# 6. Plausibility check (poverty rates for Nebraska)
cat("\n[6] Plausibility check (Nebraska child poverty):\n")
cat("    Below poverty (0-99%):", round(mean(fpl_predictions[, 1]) * 100, 1), "% (expect ~12-18%)\n")
cat("    Near poverty (100-199%):", round(mean(fpl_predictions[, 2]) * 100, 1), "% (expect ~15-20%)\n")
cat("    Middle income (200-299%):", round(mean(fpl_predictions[, 3]) * 100, 1), "% (expect ~15-20%)\n")
cat("    Upper-middle (300-399%):", round(mean(fpl_predictions[, 4]) * 100, 1), "% (expect ~12-15%)\n")
cat("    High income (400%+):", round(mean(fpl_predictions[, 5]) * 100, 1), "% (expect ~30-40%)\n")

# 7. Save point estimates
cat("\n[7] Saving FPL point estimates...\n")
saveRDS(fpl_estimates, "data/raking/ne25/fpl_estimates.rds")
cat("    Saved to: data/raking/ne25/fpl_estimates.rds\n")

# 8. Generate bootstrap replicates for all 5 FPL categories using SHARED bootstrap design
cat("\n[8] Generating bootstrap replicates using SHARED bootstrap design...\n")

# Load shared bootstrap design (but need to filter to FPL sample)
cat("    Loading shared ACS bootstrap design...\n")
boot_design_full <- readRDS("data/raking/ne25/acs_bootstrap_design.rds")

# Since FPL includes all ACS observations, just use the full bootstrap design
boot_design_fpl <- boot_design_full

# Add fpl_category variable to bootstrap design
boot_design_fpl$variables$fpl_category <- cut(
  boot_design_fpl$variables$POVERTY,
  breaks = c(0, 100, 200, 300, 400, 600),
  labels = c("0-99%", "100-199%", "200-299%", "300-399%", "400%+"),
  include.lowest = TRUE,
  right = FALSE
)

cat("    Bootstrap design loaded (", ncol(boot_design_fpl$repweights), " replicates)\n\n", sep = "")

# Prediction data (same as point estimates)
pred_data <- data.frame(
  AGE = 0:5,
  MULTYEAR = mean_year
)

# Store bootstrap results for each category
boot_results_list <- list()

# Generate bootstrap for each FPL category
for (i in 1:5) {
  cat("    [8.", i, "] Generating bootstrap for", categories[i], "...\n", sep = "")

  # Create binary indicator for this category
  boot_design_fpl$variables$current_category <- as.numeric(boot_design_fpl$variables$fpl_category == categories[i])

  # Generate bootstrap estimates
  boot_result <- generate_acs_bootstrap(
    boot_design = boot_design_fpl,
    formula = current_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
    pred_data = pred_data,
    family = quasibinomial()
  )

  # Format as long data
  estimand_name <- paste0("fpl_", gsub("[-%+]", "", categories[i]))
  boot_long <- format_bootstrap_results(
    boot_result = boot_result,
    ages = 0:5,
    estimand_name = estimand_name
  )

  boot_results_list[[i]] <- boot_long
}

# Combine all bootstrap results
fpl_boot_estimates <- dplyr::bind_rows(boot_results_list)

# Save bootstrap estimates
saveRDS(fpl_boot_estimates, "data/raking/ne25/fpl_estimates_boot.rds")
cat("    Saved bootstrap estimates to: data/raking/ne25/fpl_estimates_boot.rds\n")
cat("    Bootstrap dimensions:", nrow(fpl_boot_estimates), "rows (5 estimands × 6 ages × n_boot replicates)\n")

cat("\n[9] Bootstrap generation complete\n")
cat("    Note: Bootstrap replicates are NOT normalized across categories\n")
cat("    Normalization will be applied during post-stratification weighting\n")

cat("\n========================================\n")
cat("Task 2.4 Complete (with Bootstrap)\n")
cat("========================================\n\n")

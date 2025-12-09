# Phase 5: Compute Weighted Covariance Matrices
# Computes (μ, Σ) for ACS, NHIS, and NSCH using survey-weighted data
# Block structure:
#   - ACS: 8 variables (Block 1 demographics including principal_city)
#   - NHIS: 10 variables (Block 1: 7 common + married, NO principal_city + Block 2: 2 mental health)
#   - NSCH: 11 variables (Block 1: 8 demographics including principal_city + Block 3: 3 child outcomes)

library(arrow)
library(dplyr)

cat("\n========================================\n")
cat("Phase 5: Compute Covariance Matrices\n")
cat("========================================\n\n")

# Source weighted covariance utilities
cat("[0] Loading utilities...\n")
source("scripts/raking/ne25/utils/weighted_covariance.R")
source("scripts/raking/ne25/utils/impute_missing.R")
cat("    ✓ Utilities loaded\n\n")

# Variable names (block structure)
# Block 1: Common demographics (8 variables)
block1_common <- c("male", "age", "white_nh", "black", "hispanic",
                   "educ_years", "poverty_ratio", "principal_city")

# Source-specific variable sets
acs_vars <- block1_common  # 8 variables (includes principal_city)
nhis_vars <- c(block1_common[1:6], "married", block1_common[7],  # 8 Block 1 (7 common without principal_city + married)
               "phq2_total", "gad2_total")  # 2 Block 2
nsch_vars <- c(block1_common,  # 8 Block 1 (includes principal_city)
               "child_ace_1", "child_ace_2plus", "excellent_health")  # 3 Block 3

# ============================================================================
# TASK 16: Compute ACS Moments (μ^ACS, Σ^ACS)
# ============================================================================

cat("========================================\n")
cat("Task 16: Compute ACS Moments\n")
cat("========================================\n\n")

# 1. Load ACS design matrix
cat("[1] Loading ACS design matrix...\n")
if (!file.exists("data/raking/ne25/acs_design_matrix.feather")) {
  stop("ACS design matrix not found. Run 29_create_design_matrices.R first.")
}

acs_design <- arrow::read_feather("data/raking/ne25/acs_design_matrix.feather")
cat("    Loaded:", nrow(acs_design), "rows x", ncol(acs_design), "columns\n\n")

# 2. Extract design matrix and weights
cat("[2] Extracting design matrix (X) and weights (w)...\n")

X_acs <- as.matrix(acs_design[, acs_vars])
w_acs <- acs_design$survey_weight

cat("    X dimensions:", nrow(X_acs), "×", ncol(X_acs), "(8 Block 1 demographics)\n")
cat("    Weight sum:", format(sum(w_acs), big.mark = ","), "\n")
cat("    Weight range:", round(min(w_acs), 2), "to", round(max(w_acs), 2), "\n\n")

# 3. Compute weighted moments
cat("[3] Computing weighted mean and covariance...\n")

acs_moments <- compute_weighted_moments(X_acs, w_acs)

cat("    ✓ Moments computed\n")
cat("    Sample size:", acs_moments$n, "\n")
cat("    Effective N:", round(acs_moments$n_eff, 1), "\n")
cat("    Efficiency:", round(acs_moments$n_eff / acs_moments$n * 100, 1), "%\n\n")

# 4. Display mean vector
cat("[4] Weighted Mean Vector (μ^ACS):\n")
mu_acs_df <- data.frame(
  variable = acs_vars,
  mean = round(acs_moments$mu, 4)
)
print(mu_acs_df)

# 5. Display covariance matrix
cat("\n[5] Weighted Covariance Matrix (Σ^ACS):\n")
colnames(acs_moments$Sigma) <- acs_vars
rownames(acs_moments$Sigma) <- acs_vars
print(round(acs_moments$Sigma, 4))

# 6. Compute correlation matrix
cat("\n[6] Correlation Matrix (ACS):\n")
acs_cor <- cor_from_cov(acs_moments$Sigma)
colnames(acs_cor) <- acs_vars
rownames(acs_cor) <- acs_vars
print(round(acs_cor, 3))

# 7. Save ACS moments
cat("\n[7] Saving ACS moments...\n")

acs_output <- list(
  mu = acs_moments$mu,
  Sigma = acs_moments$Sigma,
  correlation = acs_cor,
  n = acs_moments$n,
  n_eff = acs_moments$n_eff,
  weight_sum = acs_moments$weight_sum,
  variable_names = acs_vars,
  block_structure = list(
    block1 = 1:8  # All 8 variables are Block 1 (common demographics)
  ),
  source = "ACS",
  geography = "Nebraska",
  years = "2019-2023 pooled"
)

saveRDS(acs_output, "data/raking/ne25/acs_moments.rds")
cat("    ✓ Saved to: data/raking/ne25/acs_moments.rds\n\n")

cat("Task 16 Complete: ACS Moments Computed\n\n")

# ============================================================================
# TASK 17: Compute NHIS Moments (μ^NHIS, Σ^NHIS)
# ============================================================================

cat("========================================\n")
cat("Task 17: Compute NHIS Moments\n")
cat("========================================\n\n")

# 1. Load NHIS design matrix
cat("[1] Loading NHIS design matrix...\n")
if (!file.exists("data/raking/ne25/nhis_design_matrix.feather")) {
  stop("NHIS design matrix not found. Run 29_create_design_matrices.R first.")
}

nhis_design <- arrow::read_feather("data/raking/ne25/nhis_design_matrix.feather")
cat("    Loaded:", nrow(nhis_design), "rows x", ncol(nhis_design), "columns\n\n")

# 2. Impute missing values using CART
cat("[2] Imputing missing values (Block 2: mental health)...\n")

# CART imputation with seed for reproducibility
nhis_design_imputed <- impute_cart(
  data = nhis_design,
  vars = nhis_vars,
  weight_var = "survey_weight",
  seed = 20251209,  # YYYYMMDD format
  m = 1,
  maxit = 5
)

cat("\n")

# 3. Extract design matrix and calibrated weights
cat("[3] Extracting design matrix (X) and calibrated weights (w)...\n")

X_nhis <- as.matrix(nhis_design_imputed[, nhis_vars])
w_nhis <- nhis_design_imputed$survey_weight  # This is calibrated_weight from KL divergence optimization

cat("    X dimensions:", nrow(X_nhis), "×", ncol(X_nhis), "(8 Block 1 [no principal_city] + 2 Block 2)\n")
cat("    Calibrated weight sum:", format(sum(w_nhis), big.mark = ","), "\n")
cat("    Weight range:", round(min(w_nhis), 2), "to", round(max(w_nhis), 2), "\n\n")

# 4. Compute weighted moments (using imputed data)
cat("[4] Computing weighted mean and covariance (Nebraska-calibrated, imputed)...\n")

nhis_moments <- compute_weighted_moments(X_nhis, w_nhis)

cat("    ✓ Moments computed\n")
cat("    Sample size:", nhis_moments$n, "\n")
cat("    Effective N:", round(nhis_moments$n_eff, 1), "\n")
cat("    Efficiency:", round(nhis_moments$n_eff / nhis_moments$n * 100, 1), "%\n\n")

# 5. Display mean vector
cat("[5] Weighted Mean Vector (μ^NHIS):\n")
mu_nhis_df <- data.frame(
  variable = nhis_vars,
  mean = round(nhis_moments$mu, 4)
)
print(mu_nhis_df)

# 6. Display covariance matrix
cat("\n[6] Weighted Covariance Matrix (Σ^NHIS):\n")
colnames(nhis_moments$Sigma) <- nhis_vars
rownames(nhis_moments$Sigma) <- nhis_vars
print(round(nhis_moments$Sigma, 4))

# 7. Compute correlation matrix
cat("\n[7] Correlation Matrix (NHIS):\n")
nhis_cor <- cor_from_cov(nhis_moments$Sigma)
colnames(nhis_cor) <- nhis_vars
rownames(nhis_cor) <- nhis_vars
print(round(nhis_cor, 3))

# 8. Save NHIS moments
cat("\n[8] Saving NHIS moments...\n")

nhis_output <- list(
  mu = nhis_moments$mu,
  Sigma = nhis_moments$Sigma,
  correlation = nhis_cor,
  n = nhis_moments$n,
  n_eff = nhis_moments$n_eff,
  weight_sum = nhis_moments$weight_sum,
  variable_names = nhis_vars,
  block_structure = list(
    block1 = 1:8,   # Demographics (7 common without principal_city + married)
    block2 = 9:10   # Mental health (phq2_total, gad2_total)
  ),
  source = "NHIS",
  geography = "North Central (Nebraska-calibrated)",
  years = "2019-2024",
  note = "Covariance reflects Nebraska demographics via KL divergence calibration. Block 2 has ~55% missingness."
)

saveRDS(nhis_output, "data/raking/ne25/nhis_moments.rds")
cat("    ✓ Saved to: data/raking/ne25/nhis_moments.rds\n\n")

cat("Task 17 Complete: NHIS Moments Computed\n\n")

# ============================================================================
# TASK 18: Compute NSCH Moments (μ^NSCH, Σ^NSCH)
# ============================================================================

cat("========================================\n")
cat("Task 18: Compute NSCH Moments\n")
cat("========================================\n\n")

# 1. Load NSCH design matrix
cat("[1] Loading NSCH design matrix...\n")
if (!file.exists("data/raking/ne25/nsch_design_matrix.feather")) {
  stop("NSCH design matrix not found. Run 29_create_design_matrices.R first.")
}

nsch_design <- arrow::read_feather("data/raking/ne25/nsch_design_matrix.feather")
cat("    Loaded:", nrow(nsch_design), "rows x", ncol(nsch_design), "columns\n\n")

# 2. Impute missing values using CART
cat("[2] Imputing missing values (Block 3: child outcomes)...\n")

# CART imputation with seed for reproducibility
nsch_design_imputed <- impute_cart(
  data = nsch_design,
  vars = nsch_vars,
  weight_var = "survey_weight",
  seed = 20251209,  # YYYYMMDD format
  m = 1,
  maxit = 5
)

cat("\n")

# 3. Extract design matrix and calibrated weights
cat("[3] Extracting design matrix (X) and calibrated weights (w)...\n")

X_nsch <- as.matrix(nsch_design_imputed[, nsch_vars])
w_nsch <- nsch_design_imputed$survey_weight  # This is calibrated_weight from KL divergence optimization

cat("    X dimensions:", nrow(X_nsch), "×", ncol(X_nsch), "(8 Block 1 + 3 Block 3)\n")
cat("    Calibrated weight sum:", format(sum(w_nsch), big.mark = ","), "\n")
cat("    Weight range:", round(min(w_nsch), 2), "to", round(max(w_nsch), 2), "\n\n")

# 4. Compute weighted moments (using imputed data)
cat("[4] Computing weighted mean and covariance (Nebraska-calibrated, imputed)...\n")

nsch_moments <- compute_weighted_moments(X_nsch, w_nsch)

cat("    ✓ Moments computed\n")
cat("    Sample size:", nsch_moments$n, "\n")
cat("    Effective N:", round(nsch_moments$n_eff, 1), "\n")
cat("    Efficiency:", round(nsch_moments$n_eff / nsch_moments$n * 100, 1), "%\n\n")

# 5. Display mean vector
cat("[5] Weighted Mean Vector (μ^NSCH):\n")
mu_nsch_df <- data.frame(
  variable = nsch_vars,
  mean = round(nsch_moments$mu, 4)
)
print(mu_nsch_df)

# 6. Display covariance matrix
cat("\n[6] Weighted Covariance Matrix (Σ^NSCH):\n")
colnames(nsch_moments$Sigma) <- nsch_vars
rownames(nsch_moments$Sigma) <- nsch_vars
print(round(nsch_moments$Sigma, 4))

# 7. Compute correlation matrix
cat("\n[7] Correlation Matrix (NSCH):\n")
nsch_cor <- cor_from_cov(nsch_moments$Sigma)
colnames(nsch_cor) <- nsch_vars
rownames(nsch_cor) <- nsch_vars
print(round(nsch_cor, 3))

# 8. Save NSCH moments
cat("\n[8] Saving NSCH moments...\n")

nsch_output <- list(
  mu = nsch_moments$mu,
  Sigma = nsch_moments$Sigma,
  correlation = nsch_cor,
  n = nsch_moments$n,
  n_eff = nsch_moments$n_eff,
  weight_sum = nsch_moments$weight_sum,
  variable_names = nsch_vars,
  block_structure = list(
    block1 = 1:8,   # Demographics (8 common, no married)
    block3 = 9:11   # Child outcomes (child_ace_1, child_ace_2plus, excellent_health)
  ),
  source = "NSCH",
  geography = "Nebraska + 6 border states (Nebraska-calibrated)",
  years = "2021-2022 pooled",
  note = "Covariance reflects Nebraska demographics via KL divergence calibration. Block 3 has 13.3% (ACE) and 0.3% (health) missingness."
)

saveRDS(nsch_output, "data/raking/ne25/nsch_moments.rds")
cat("    ✓ Saved to: data/raking/ne25/nsch_moments.rds\n\n")

cat("Task 18 Complete: NSCH Moments Computed\n\n")

# ============================================================================
# SUMMARY: Compare Moments Across Sources
# ============================================================================

cat("========================================\n")
cat("Cross-Source Moment Comparison\n")
cat("========================================\n\n")

cat("WEIGHTED MEANS (μ) - Block 1 Common Demographics (7 variables, excluding principal_city):\n\n")
# Compare only the 7 common Block 1 variables (excluding principal_city which NHIS doesn't have)
mean_comparison <- data.frame(
  Variable = block1_common[1:7],  # Exclude principal_city
  ACS = round(acs_moments$mu[1:7], 4),
  NHIS = round(nhis_moments$mu[1:7], 4),
  NSCH = round(nsch_moments$mu[1:7], 4)
)
print(mean_comparison)

cat("\n\nSOURCE-SPECIFIC VARIABLES:\n")
cat("  ACS: principal_city =", round(acs_moments$mu[8], 4), "\n")
cat("  NHIS (Block 1): married =", round(nhis_moments$mu[8], 4), "\n")
cat("  NHIS (Block 2): phq2_total =", round(nhis_moments$mu[9], 4),
    ", gad2_total =", round(nhis_moments$mu[10], 4), "\n")
cat("  NSCH: principal_city =", round(nsch_moments$mu[8], 4), "\n")
cat("  NSCH (Block 3): child_ace_1 =", round(nsch_moments$mu[9], 4),
    ", child_ace_2plus =", round(nsch_moments$mu[10], 4),
    ", excellent_health =", round(nsch_moments$mu[11], 4), "\n")

cat("\n\nSAMPLE SIZE SUMMARY:\n")
sample_summary <- data.frame(
  Source = c("ACS", "NHIS", "NSCH"),
  Raw_N = c(acs_moments$n, nhis_moments$n, nsch_moments$n),
  Effective_N = c(round(acs_moments$n_eff, 1),
                  round(nhis_moments$n_eff, 1),
                  round(nsch_moments$n_eff, 1)),
  Efficiency_Pct = c(
    round(acs_moments$n_eff / acs_moments$n * 100, 1),
    round(nhis_moments$n_eff / nhis_moments$n * 100, 1),
    round(nsch_moments$n_eff / nsch_moments$n * 100, 1)
  )
)
print(sample_summary)

cat("\n========================================\n")
cat("Phase 5 Complete: All Covariance Matrices Computed\n")
cat("========================================\n\n")

cat("Outputs:\n")
cat("  - data/raking/ne25/acs_moments.rds\n")
cat("  - data/raking/ne25/nhis_moments.rds\n")
cat("  - data/raking/ne25/nsch_moments.rds\n\n")

cat("Each file contains:\n")
cat("  - mu: Weighted mean vector\n")
cat("      ACS: 8 × 1 (Block 1 with principal_city)\n")
cat("      NHIS: 10 × 1 (8 Block 1 without principal_city + 2 Block 2)\n")
cat("      NSCH: 11 × 1 (8 Block 1 with principal_city + 3 Block 3)\n")
cat("  - Sigma: Weighted covariance matrix (block-factored)\n")
cat("  - correlation: Correlation matrix\n")
cat("  - n, n_eff: Sample sizes\n")
cat("  - block_structure: Variable indices for each block\n")
cat("  - Metadata (source, geography, years)\n\n")

cat("Ready for Phase 6: Generate diagnostic visualizations\n\n")

# Phase 5b: Pool Moments Across Sources
# Creates unified moment structure by pooling Block 1 demographics across ACS/NHIS/NSCH
# and appending source-specific Blocks 2-3
#
# Block structure:
#   - Block 1: 7 common demographics (pooled from ACS + NHIS + NSCH, NO principal_city)
#   - Block 1b: principal_city (pooled from ACS + NSCH only, NHIS excluded)
#   - Block 2: 2 mental health variables (NHIS only)
#   - Block 3: 3 child outcomes (NSCH only)
#
# Output: unified_moments.rds with 13-variable moment structure

library(dplyr)

cat("\n========================================\n")
cat("Phase 5b: Pool Moments Across Sources\n")
cat("========================================\n\n")

# Source utilities
cat("[0] Loading utilities...\n")
source("scripts/raking/ne25/utils/weighted_covariance.R")
cat("    ✓ Utilities loaded\n\n")

# ============================================================================
# STEP 1: Load Source-Specific Moments
# ============================================================================

cat("[1] Loading source-specific moments...\n")

if (!file.exists("data/raking/ne25/acs_moments.rds")) {
  stop("ACS moments not found. Run 30_compute_covariance_matrices.R first.")
}
if (!file.exists("data/raking/ne25/nhis_moments.rds")) {
  stop("NHIS moments not found. Run 30_compute_covariance_matrices.R first.")
}
if (!file.exists("data/raking/ne25/nsch_moments.rds")) {
  stop("NSCH moments not found. Run 30_compute_covariance_matrices.R first.")
}

acs <- readRDS("data/raking/ne25/acs_moments.rds")
nhis <- readRDS("data/raking/ne25/nhis_moments.rds")
nsch <- readRDS("data/raking/ne25/nsch_moments.rds")

cat("    ✓ ACS moments loaded (n_eff =", round(acs$n_eff, 1), ")\n")
cat("    ✓ NHIS moments loaded (n_eff =", round(nhis$n_eff, 1), ")\n")
cat("    ✓ NSCH moments loaded (n_eff =", round(nsch$n_eff, 1), ")\n\n")

# ============================================================================
# STEP 2: Pool Block 1 Demographics (7 common + 1 principal_city)
# ============================================================================

cat("[2] Pooling Block 1 demographics...\n")

# Step 2a: Pool 7 common variables across all 3 sources
cat("  [2a] Pooling 7 common variables (ACS + NHIS + NSCH)...\n")

n_eff_acs <- acs$n_eff
n_eff_nhis <- nhis$n_eff
n_eff_nsch <- nsch$n_eff

total_n_eff_common <- n_eff_acs + n_eff_nhis + n_eff_nsch

cat(sprintf("      ACS n_eff: %.1f (%.1f%% weight)\n",
            n_eff_acs, n_eff_acs / total_n_eff_common * 100))
cat(sprintf("      NHIS n_eff: %.1f (%.1f%% weight)\n",
            n_eff_nhis, n_eff_nhis / total_n_eff_common * 100))
cat(sprintf("      NSCH n_eff: %.1f (%.1f%% weight)\n",
            n_eff_nsch, n_eff_nsch / total_n_eff_common * 100))
cat(sprintf("      Total n_eff: %.1f\n\n", total_n_eff_common))

# Extract 7 common variables (no principal_city, no married)
mu_acs_common <- acs$mu[1:7]
Sigma_acs_common <- acs$Sigma[1:7, 1:7]

mu_nhis_common <- nhis$mu[1:7]
Sigma_nhis_common <- nhis$Sigma[1:7, 1:7]

mu_nsch_common <- nsch$mu[1:7]
Sigma_nsch_common <- nsch$Sigma[1:7, 1:7]

# Pool using n_eff weights
mu_common_pooled <- (n_eff_acs * mu_acs_common +
                     n_eff_nhis * mu_nhis_common +
                     n_eff_nsch * mu_nsch_common) / total_n_eff_common

Sigma_common_pooled <- (n_eff_acs * Sigma_acs_common +
                        n_eff_nhis * Sigma_nhis_common +
                        n_eff_nsch * Sigma_nsch_common) / total_n_eff_common

cat("      ✓ 7 common variables pooled\n\n")

# Step 2b: Pool principal_city from ACS + NSCH only (NHIS excluded)
cat("  [2b] Pooling principal_city (ACS + NSCH only, NHIS excluded)...\n")

total_n_eff_princip <- n_eff_acs + n_eff_nsch

cat(sprintf("      ACS n_eff: %.1f (%.1f%% weight)\n",
            n_eff_acs, n_eff_acs / total_n_eff_princip * 100))
cat(sprintf("      NSCH n_eff: %.1f (%.1f%% weight)\n",
            n_eff_nsch, n_eff_nsch / total_n_eff_princip * 100))
cat(sprintf("      Total n_eff: %.1f\n\n", total_n_eff_princip))

# Extract principal_city (index 8 for ACS and NSCH)
mu_princip_pooled <- (n_eff_acs * acs$mu[8] +
                      n_eff_nsch * nsch$mu[8]) / total_n_eff_princip

var_princip_pooled <- (n_eff_acs * acs$Sigma[8, 8] +
                       n_eff_nsch * nsch$Sigma[8, 8]) / total_n_eff_princip

cat("      ✓ principal_city pooled\n\n")

# Combine into full Block 1 (8 variables)
mu_block1_pooled <- c(mu_common_pooled, mu_princip_pooled)
Sigma_block1_pooled <- matrix(0, 8, 8)
Sigma_block1_pooled[1:7, 1:7] <- Sigma_common_pooled
Sigma_block1_pooled[8, 8] <- var_princip_pooled

# Cross-covariances between 7 common and principal_city (from ACS + NSCH)
# Pool covariances between common vars and principal_city
cov_common_princip_acs <- acs$Sigma[1:7, 8]
cov_common_princip_nsch <- nsch$Sigma[1:7, 8]
cov_common_princip_pooled <- (n_eff_acs * cov_common_princip_acs +
                              n_eff_nsch * cov_common_princip_nsch) / total_n_eff_princip

Sigma_block1_pooled[1:7, 8] <- cov_common_princip_pooled
Sigma_block1_pooled[8, 1:7] <- cov_common_princip_pooled

cat("    ✓ Block 1 complete (8 variables: 7 common + principal_city)\n")
cat("    Pooled means:\n")
block1_vars <- c("male", "age", "white_nh", "black", "hispanic", "educ_years", "poverty_ratio", "principal_city")
for (i in 1:8) {
  cat(sprintf("      %s: %.4f\n", block1_vars[i], mu_block1_pooled[i]))
}
cat("\n")

# ============================================================================
# STEP 3: Extract Block 2 (Mental Health from NHIS)
# ============================================================================

cat("[3] Extracting Block 2 (mental health) from NHIS...\n")

# Block 2 was already computed with CART imputation in script 30
# Extract from NHIS moments (indices 9-10)
mu_block2 <- nhis$mu[9:10]
Sigma_block2 <- nhis$Sigma[9:10, 9:10]
n_eff_block2 <- nhis$n_eff  # Same n_eff as Block 1 (full imputed sample)

cat(sprintf("    ✓ Block 2 extracted (n_eff = %.1f, CART imputed)\n", n_eff_block2))
cat("    Means:\n")
cat(sprintf("      phq2_total: %.4f\n", mu_block2[1]))
cat(sprintf("      gad2_total: %.4f\n\n", mu_block2[2]))

# Extract cross-covariance between Block 1 (7 common) and Block 2 from NHIS moments
# Block 1: indices 1-7 (7 common variables, no principal_city, skip married at index 8)
# Block 2: indices 9-10
Sigma_block1_block2 <- nhis$Sigma[1:7, 9:10]

cat("    ✓ Block 1 × Block 2 cross-covariance extracted\n\n")

# ============================================================================
# STEP 4: Extract Block 3 (Child Outcomes from NSCH)
# ============================================================================

cat("[4] Extracting Block 3 (child outcomes) from NSCH...\n")

# Block 3 was already computed with CART imputation in script 30
# Extract from NSCH moments (indices 9-11)
mu_block3 <- nsch$mu[9:11]
Sigma_block3 <- nsch$Sigma[9:11, 9:11]
n_eff_block3 <- nsch$n_eff  # Same n_eff as Block 1 (full imputed sample)

cat(sprintf("    ✓ Block 3 extracted (n_eff = %.1f, CART imputed)\n", n_eff_block3))
cat("    Means:\n")
cat(sprintf("      child_ace_1: %.4f\n", mu_block3[1]))
cat(sprintf("      child_ace_2plus: %.4f\n", mu_block3[2]))
cat(sprintf("      excellent_health: %.4f\n\n", mu_block3[3]))

# Extract cross-covariance between Block 1 and Block 3 from NSCH moments
# Block 1: indices 1-8
# Block 3: indices 9-11
Sigma_block1_block3 <- nsch$Sigma[1:8, 9:11]

cat("    ✓ Block 1 × Block 3 cross-covariance extracted\n\n")

# ============================================================================
# STEP 5: Construct Unified 13×13 Moment Structure
# ============================================================================

cat("[5] Constructing unified 13×13 moment structure...\n")

# Variable layout:
#   1-8:    Block 1 (demographics, pooled from ACS+NHIS+NSCH)
#   9-10:   Block 2 (mental health, NHIS only)
#   11-13:  Block 3 (child outcomes, NSCH only)

unified_vars <- c(block1_vars, "phq2_total", "gad2_total",
                  "child_ace_1", "child_ace_2plus", "excellent_health")

# Construct 13×1 mean vector
mu_unified <- c(mu_block1_pooled, mu_block2, mu_block3)

# Construct 13×13 covariance matrix
Sigma_unified <- matrix(0, nrow = 13, ncol = 13)
rownames(Sigma_unified) <- unified_vars
colnames(Sigma_unified) <- unified_vars

# Block 1 × Block 1 (pooled)
Sigma_unified[1:8, 1:8] <- Sigma_block1_pooled

# Block 2 × Block 2 (NHIS)
Sigma_unified[9:10, 9:10] <- Sigma_block2

# Block 3 × Block 3 (NSCH)
Sigma_unified[11:13, 11:13] <- Sigma_block3

# Block 1 × Block 2 cross-covariance (NHIS, only 7 common variables, not principal_city)
# NHIS doesn't have principal_city, so only indices 1-7 have cross-covariance with Block 2
Sigma_unified[1:7, 9:10] <- Sigma_block1_block2
Sigma_unified[9:10, 1:7] <- t(Sigma_block1_block2)
# principal_city (index 8) × Block 2: UNOBSERVED (NHIS doesn't have principal_city)
Sigma_unified[8, 9:10] <- 0
Sigma_unified[9:10, 8] <- 0

# Block 1 × Block 3 cross-covariance (NSCH)
Sigma_unified[1:8, 11:13] <- Sigma_block1_block3
Sigma_unified[11:13, 1:8] <- t(Sigma_block1_block3)

# Block 2 × Block 3 cross-covariance: NOT OBSERVED (set to 0)
# These blocks come from different sources (NHIS vs NSCH) with no overlap
Sigma_unified[9:10, 11:13] <- 0
Sigma_unified[11:13, 9:10] <- 0

cat("    ✓ Unified covariance structure assembled\n")
cat("    Observed blocks:\n")
cat("      Block 1 × Block 1: Pooled (ACS + NHIS + NSCH)\n")
cat("      Block 1 × Block 2: NHIS cross-covariance\n")
cat("      Block 1 × Block 3: NSCH cross-covariance\n")
cat("      Block 2 × Block 2: NHIS\n")
cat("      Block 3 × Block 3: NSCH\n")
cat("      Block 2 × Block 3: UNOBSERVED (set to 0)\n\n")

# ============================================================================
# STEP 6: Validate Covariance Matrix Properties
# ============================================================================

cat("[6] Validating unified covariance matrix...\n")

# Check symmetry
max_asymmetry <- max(abs(Sigma_unified - t(Sigma_unified)))
cat(sprintf("    Max asymmetry: %.2e ", max_asymmetry))
if (max_asymmetry < 1e-10) {
  cat("(✓ symmetric)\n")
} else {
  cat("(WARNING: not symmetric!)\n")
}

# Check positive definiteness via eigenvalues
eigenvalues <- eigen(Sigma_unified, symmetric = TRUE, only.values = TRUE)$values
min_eigenvalue <- min(eigenvalues)
cat(sprintf("    Min eigenvalue: %.4f ", min_eigenvalue))
if (min_eigenvalue > 0) {
  cat("(✓ positive definite)\n")
} else if (min_eigenvalue > -1e-10) {
  cat("(✓ positive semi-definite, numerically zero)\n")
} else {
  cat("(ERROR: NOT positive definite!)\n")
  cat("\n    Eigenvalue spectrum:\n")
  for (i in 1:length(eigenvalues)) {
    cat(sprintf("      λ%d: %.6f\n", i, eigenvalues[i]))
  }
}

cat("\n")

# ============================================================================
# STEP 7: Compute Correlation Matrix
# ============================================================================

cat("[7] Computing unified correlation matrix...\n")

cor_unified <- cor_from_cov(Sigma_unified)

cat("    ✓ Correlation matrix computed\n\n")

# ============================================================================
# STEP 8: Save Unified Moments
# ============================================================================

cat("[8] Saving unified moments...\n")

unified_output <- list(
  mu = mu_unified,
  Sigma = Sigma_unified,
  correlation = cor_unified,
  variable_names = unified_vars,
  block_structure = list(
    block1 = 1:8,    # Demographics (pooled)
    block2 = 9:10,   # Mental health (NHIS)
    block3 = 11:13   # Child outcomes (NSCH)
  ),
  n_eff = list(
    block1 = total_n_eff_common,
    block2 = n_eff_block2,
    block3 = n_eff_block3
  ),
  pooling_weights = list(
    acs = n_eff_acs / total_n_eff_common,
    nhis = n_eff_nhis / total_n_eff_common,
    nsch = n_eff_nsch / total_n_eff_common
  ),
  source = "Pooled (ACS + NHIS + NSCH)",
  geography = "Nebraska-representative",
  note = paste(
    "Block 1 pooled using n_eff weights from ACS/NHIS/NSCH.",
    "Block 2 from NHIS only (45% complete cases).",
    "Block 3 from NSCH only (87% complete cases).",
    "Block 2 × Block 3 cross-covariance unobserved (different sources)."
  )
)

saveRDS(unified_output, "data/raking/ne25/unified_moments.rds")
cat("    ✓ Saved to: data/raking/ne25/unified_moments.rds\n\n")

# ============================================================================
# STEP 9: Display Summary
# ============================================================================

cat("========================================\n")
cat("Unified Moment Summary\n")
cat("========================================\n\n")

cat("UNIFIED MEAN VECTOR (13 variables):\n\n")
mu_df <- data.frame(
  variable = unified_vars,
  mean = round(mu_unified, 4)
)
print(mu_df)

cat("\n\nUNIFIED COVARIANCE MATRIX (diagonal variances):\n")
for (i in 1:13) {
  cat(sprintf("  %s: %.4f\n", unified_vars[i], Sigma_unified[i, i]))
}

cat("\n\nEFFECTIVE SAMPLE SIZES:\n")
cat(sprintf("  Block 1 (pooled): %.1f\n", total_n_eff_common))
cat(sprintf("  Block 2 (NHIS):   %.1f\n", n_eff_block2))
cat(sprintf("  Block 3 (NSCH):   %.1f\n\n", n_eff_block3))

cat("========================================\n")
cat("Phase 5b Complete: Moments Pooled\n")
cat("========================================\n\n")

cat("Output: data/raking/ne25/unified_moments.rds\n")
cat("  - 13 × 1 mean vector (pooled Block 1 + NHIS Block 2 + NSCH Block 3)\n")
cat("  - 13 × 13 covariance matrix (block-factored structure)\n")
cat("  - Block 2 × Block 3 cross-covariance = 0 (unobserved)\n\n")

cat("Ready for Phase 6: Generate diagnostic visualizations\n\n")

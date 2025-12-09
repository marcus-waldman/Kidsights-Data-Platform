# Phase 5b: Pool Moments Across Sources
# Creates unified moment structure by pooling Block 1 across ACS/NHIS/NSCH
# and appending source-specific Blocks 2-3
#
# Block structure:
#   - Block 1: 21 variables (7 demographics pooled from ACS+NHIS+NSCH + 14 PUMA dummies from ACS only)
#   - Block 2: 2 mental health variables (NHIS only)
#   - Block 3: 1 child outcome (NSCH only, excellent_health)
#
# Output: unified_moments.rds with 24-variable moment structure

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
# STEP 2: Pool Block 1 (21 variables: 7 demographics + 14 PUMA dummies)
# ============================================================================

cat("[2] Building Block 1 (7 demographics pooled + 14 PUMA from ACS)...\n")

n_eff_acs <- acs$n_eff
n_eff_nhis <- nhis$n_eff
n_eff_nsch <- nsch$n_eff

total_n_eff_block1 <- n_eff_acs + n_eff_nhis + n_eff_nsch

cat(sprintf("    ACS n_eff: %.1f (%.1f%% weight)\n",
            n_eff_acs, n_eff_acs / total_n_eff_block1 * 100))
cat(sprintf("    NHIS n_eff: %.1f (%.1f%% weight)\n",
            n_eff_nhis, n_eff_nhis / total_n_eff_block1 * 100))
cat(sprintf("    NSCH n_eff: %.1f (%.1f%% weight)\n",
            n_eff_nsch, n_eff_nsch / total_n_eff_block1 * 100))
cat(sprintf("    Total n_eff: %.1f\n\n", total_n_eff_block1))

# Extract 7 common demographics (indices 1-7 in all sources)
mu_demo_acs <- acs$mu[1:7]
Sigma_demo_acs <- acs$Sigma[1:7, 1:7]

mu_demo_nhis <- nhis$mu[1:7]
Sigma_demo_nhis <- nhis$Sigma[1:7, 1:7]

mu_demo_nsch <- nsch$mu[1:7]
Sigma_demo_nsch <- nsch$Sigma[1:7, 1:7]

# Pool 7 demographics using n_eff weights
mu_demo_pooled <- (n_eff_acs * mu_demo_acs +
                   n_eff_nhis * mu_demo_nhis +
                   n_eff_nsch * mu_demo_nsch) / total_n_eff_block1

Sigma_demo_pooled <- (n_eff_acs * Sigma_demo_acs +
                      n_eff_nhis * Sigma_demo_nhis +
                      n_eff_nsch * Sigma_demo_nsch) / total_n_eff_block1

cat("    ✓ Demographics pooled across ACS/NHIS/NSCH (7 variables)\n")
cat("    Pooled demographics means:\n")
demo_vars <- c("male", "age", "white_nh", "black", "hispanic", "educ_years", "poverty_ratio")
for (i in 1:7) {
  cat(sprintf("      %s: %.4f\n", demo_vars[i], mu_demo_pooled[i]))
}
cat("\n")

# Extract 14 PUMA dummies from ACS only (indices 8-21 in acs_moments)
# ACS structure after PUMA addition: 1-7 (demographics), 8-21 (14 PUMA dummies)
mu_puma <- acs$mu[8:21]
Sigma_puma <- acs$Sigma[8:21, 8:21]

# Cross-covariance between pooled demographics and PUMA (within ACS context, but use ACS-NHIS-NSCH averages for demos)
Sigma_demo_puma <- acs$Sigma[1:7, 8:21]

cat("    ✓ PUMA dummies extracted from ACS (14 variables, ACS-only)\n")
puma_codes <- c(100, 200, 300, 400, 500, 600, 701, 702, 801, 802, 901, 902, 903, 904)
puma_vars <- sprintf("puma_%d", puma_codes)
cat("    PUMA means:\n")
for (i in 1:14) {
  cat(sprintf("      %s: %.4f\n", puma_vars[i], mu_puma[i]))
}
cat("\n")

# Construct Block 1: 7 pooled demographics + 14 PUMA dummies (21 variables total)
block1_vars <- c(demo_vars, puma_vars)
mu_block1 <- c(mu_demo_pooled, mu_puma)

# Construct 21×21 Block 1 covariance matrix
Sigma_block1 <- matrix(0, nrow = 21, ncol = 21)
# Demographics × Demographics (pooled)
Sigma_block1[1:7, 1:7] <- Sigma_demo_pooled
# PUMA × PUMA (ACS only)
Sigma_block1[8:21, 8:21] <- Sigma_puma
# Demographics × PUMA (ACS-specific, but this represents the covariance structure in the population)
Sigma_block1[1:7, 8:21] <- Sigma_demo_puma
Sigma_block1[8:21, 1:7] <- t(Sigma_demo_puma)

cat("    ✓ Block 1 complete (21 variables = 7 demographics + 14 PUMA dummies)\n\n")

# ============================================================================
# STEP 3: Extract Block 2 (Mental Health from NHIS)
# ============================================================================

cat("[3] Extracting Block 2 (mental health) from NHIS...\n")

# Block 2 was already computed with CART imputation in script 30
# Extract from NHIS moments
# NHIS structure: 1-7 (demographics), 8 (married), 9-10 (phq2/gad2)
# We need indices 9-10 for mental health
mu_block2 <- nhis$mu[9:10]
Sigma_block2 <- nhis$Sigma[9:10, 9:10]
n_eff_block2 <- nhis$n_eff  # Same n_eff as Block 1 (full imputed sample)

cat(sprintf("    ✓ Block 2 extracted (n_eff = %.1f, CART imputed)\n", n_eff_block2))
cat("    Means:\n")
cat(sprintf("      phq2_total: %.4f\n", mu_block2[1]))
cat(sprintf("      gad2_total: %.4f\n\n", mu_block2[2]))

# Extract cross-covariance between Block 1 and Block 2 from NHIS moments
# Block 1: Only the 7 pooled demographics are in NHIS (indices 1-7)
# Block 2: indices 9-10 (mental health, AFTER married at index 8)
# We use the pooled demographics covariance × NHIS mental health cross-covariance
Sigma_block1_block2 <- nhis$Sigma[1:7, 9:10]  # 7 demographics × 2 mental health

cat("    ✓ Block 1 × Block 2 cross-covariance extracted (demographics × mental health)\n\n")

# ============================================================================
# STEP 4: Extract Block 3 (Child Outcome from NSCH)
# ============================================================================

cat("[4] Extracting Block 3 (child outcome) from NSCH...\n")

# Block 3: excellent_health only
# Extract from NSCH moments
# NSCH structure: 1-7 (demographics), 8-9 (child_ace_1, child_ace_2plus), 10 (excellent_health)
# We need index 10 for excellent_health
mu_block3 <- nsch$mu[10]
Sigma_block3 <- as.matrix(nsch$Sigma[10, 10])  # Convert to 1×1 matrix
n_eff_block3 <- nsch$n_eff  # Same n_eff as Block 1 (full imputed sample)

cat(sprintf("    ✓ Block 3 extracted (n_eff = %.1f, CART imputed)\n", n_eff_block3))
cat("    Means:\n")
cat(sprintf("      excellent_health: %.4f\n\n", mu_block3))

# Extract cross-covariance between Block 1 and Block 3 from NSCH moments
# Block 1: indices 1-7 (demographics only)
# Block 3: index 10 (excellent_health)
Sigma_block1_block3 <- as.matrix(nsch$Sigma[1:7, 10])  # 7×1 matrix

cat("    ✓ Block 1 × Block 3 cross-covariance extracted (demographics × child outcome)\n\n")

# ============================================================================
# STEP 5: Construct Unified 24×24 Moment Structure
# ============================================================================

cat("[5] Constructing unified 24×24 moment structure...\n")

# Variable layout:
#   1-21:   Block 1 (7 demographics pooled from ACS+NHIS+NSCH + 14 PUMA from ACS only)
#   22-23:  Block 2 (mental health, NHIS only)
#   24:     Block 3 (child outcome, NSCH only)

block2_vars <- c("phq2_total", "gad2_total")
block3_vars <- c("excellent_health")
unified_vars <- c(block1_vars, block2_vars, block3_vars)

# Construct 24×1 mean vector
mu_unified <- c(mu_block1, mu_block2, mu_block3)

# Construct 24×24 covariance matrix
Sigma_unified <- matrix(0, nrow = 24, ncol = 24)
rownames(Sigma_unified) <- unified_vars
colnames(Sigma_unified) <- unified_vars

# Block 1 × Block 1 (21×21: pooled demographics + ACS PUMA)
Sigma_unified[1:21, 1:21] <- Sigma_block1

# Block 2 × Block 2 (NHIS, 2×2)
Sigma_unified[22:23, 22:23] <- Sigma_block2

# Block 3 × Block 3 (NSCH, 1×1)
Sigma_unified[24, 24] <- Sigma_block3[1, 1]

# Block 1 × Block 2 cross-covariance (21×2)
# Only the 7 demographics in Block 1 have observed covariance with mental health
# PUMA dummies have NO observed covariance with mental health (ACS vs NHIS unobserved)
Sigma_unified[1:7, 22:23] <- Sigma_block1_block2  # Demographics × mental health (observed)
Sigma_unified[8:21, 22:23] <- 0                   # PUMA × mental health (unobserved)
Sigma_unified[22:23, 1:7] <- t(Sigma_block1_block2)
Sigma_unified[22:23, 8:21] <- 0

# Block 1 × Block 3 cross-covariance (21×1)
# Only the 7 demographics in Block 1 have observed covariance with child outcome
# PUMA dummies have NO observed covariance with child outcome (ACS vs NSCH unobserved)
Sigma_unified[1:7, 24] <- Sigma_block1_block3[, 1]  # Demographics × child outcome (observed)
Sigma_unified[8:21, 24] <- 0                        # PUMA × child outcome (unobserved)
Sigma_unified[24, 1:7] <- Sigma_block1_block3[, 1]
Sigma_unified[24, 8:21] <- 0

# Block 2 × Block 3 cross-covariance: NOT OBSERVED (set to 0)
# These blocks come from different sources (NHIS vs NSCH) with no overlap
Sigma_unified[22:23, 24] <- 0
Sigma_unified[24, 22:23] <- 0

cat("    ✓ Unified 24×24 covariance structure assembled\n")
cat("    Structure:\n")
cat("      Block 1 (21×21): 7 pooled demographics + 14 PUMA dummies\n")
cat("      Block 2 (2×2):   Mental health (NHIS only)\n")
cat("      Block 3 (1×1):   Child outcome (NSCH only)\n")
cat("    Cross-covariances:\n")
cat("      Demographics × mental health: OBSERVED (NHIS)\n")
cat("      Demographics × child outcome: OBSERVED (NSCH)\n")
cat("      PUMA × mental health:         UNOBSERVED (set to 0)\n")
cat("      PUMA × child outcome:         UNOBSERVED (set to 0)\n")
cat("      Mental health × child outcome: UNOBSERVED (set to 0)\n\n")

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

cat("[8] Creating covariance mask matrix for Stan...\n")

# Create 24×24 binary mask matrix (1 = observed, 0 = unobserved)
cov_mask <- matrix(0, nrow = 24, ncol = 24)
rownames(cov_mask) <- unified_vars
colnames(cov_mask) <- unified_vars

# Block 1 × Block 1 (21×21): ALL OBSERVED from ACS
cov_mask[1:21, 1:21] <- 1

# Block 2 × Block 2 (2×2): ALL OBSERVED from NHIS
cov_mask[22:23, 22:23] <- 1

# Block 3 × Block 3 (1×1): ALL OBSERVED from NSCH
cov_mask[24, 24] <- 1

# Demographics × Mental Health (7×2): OBSERVED from NHIS
cov_mask[1:7, 22:23] <- 1
cov_mask[22:23, 1:7] <- 1

# Demographics × Child Outcome (7×1): OBSERVED from NSCH
cov_mask[1:7, 24] <- 1
cov_mask[24, 1:7] <- 1

# PUMA × Mental Health (14×2): UNOBSERVED (already 0)
# PUMA × Child Outcome (14×1): UNOBSERVED (already 0)
# Mental Health × Child Outcome (2×1): UNOBSERVED (already 0)

n_total_elements <- 24 * 24
n_observed_elements <- sum(cov_mask)
pct_observed <- (n_observed_elements / n_total_elements) * 100

cat(sprintf("    ✓ Covariance mask created: %d / %d elements observed (%.1f%%)\n",
            n_observed_elements, n_total_elements, pct_observed))
cat("    Observed blocks:\n")
cat("      - Block 1 × Block 1 (21×21 = 441 elements)\n")
cat("      - Block 2 × Block 2 (2×2 = 4 elements)\n")
cat("      - Block 3 × Block 3 (1×1 = 1 element)\n")
cat("      - Demographics × Mental Health (7×2 × 2 = 28 elements)\n")
cat("      - Demographics × Child Outcome (7×1 × 2 = 14 elements)\n")
cat(sprintf("      Total observed: %d elements\n", n_observed_elements))
cat("    Unobserved blocks (masked to 0):\n")
cat("      - PUMA × Mental Health (14×2 × 2 = 56 elements)\n")
cat("      - PUMA × Child Outcome (14×1 × 2 = 28 elements)\n")
cat("      - Mental Health × Child Outcome (2×1 × 2 = 4 elements)\n\n")

cat("[9] Saving unified moments...\n")

unified_output <- list(
  mu = mu_unified,
  Sigma = Sigma_unified,
  cov_mask = cov_mask,  # NEW: Binary mask for Stan factorized model
  correlation = cor_unified,
  variable_names = unified_vars,
  block_structure = list(
    block1 = 1:21,    # 7 demographics (pooled ACS+NHIS+NSCH) + 14 PUMA (ACS only)
    block2 = 22:23,   # Mental health (NHIS only)
    block3 = 24       # Child outcome (NSCH only)
  ),
  n_eff = list(
    block1 = total_n_eff_block1,
    block2 = n_eff_block2,
    block3 = n_eff_block3
  ),
  pooling_weights = list(
    acs = n_eff_acs / total_n_eff_block1,
    nhis = n_eff_nhis / total_n_eff_block1,
    nsch = n_eff_nsch / total_n_eff_block1
  ),
  source = "Pooled (ACS + NHIS + NSCH with PUMA from ACS only)",
  geography = "Nebraska PUMAs with state demographics",
  note = paste(
    "Block 1 (21 vars): 7 demographics pooled using n_eff weights from ACS/NHIS/NSCH + 14 PUMA dummies from ACS only.",
    "Block 2 (2 vars): Mental health from NHIS only (phq2_total, gad2_total, 45% complete cases).",
    "Block 3 (1 var): Child outcome from NSCH only (excellent_health, 87% complete cases).",
    "Cross-covariances: Demographics × mental health (NHIS), demographics × child outcome (NSCH).",
    "PUMA × mental health and PUMA × child outcome are unobserved (set to 0).",
    "Covariance mask matrix included for Stan factorized calibration (488/576 elements observed)."
  )
)

saveRDS(unified_output, "data/raking/ne25/unified_moments.rds")
cat("    ✓ Saved to: data/raking/ne25/unified_moments.rds\n\n")

# ============================================================================
# STEP 10: Display Summary
# ============================================================================

cat("========================================\n")
cat("Unified Moment Summary\n")
cat("========================================\n\n")

cat("UNIFIED MEAN VECTOR (24 variables):\n\n")
mu_df <- data.frame(
  variable = unified_vars,
  mean = round(mu_unified, 4)
)
print(mu_df)

cat("\n\nUNIFIED COVARIANCE MATRIX (diagonal variances):\n")
cat("Block 1 - Demographics & PUMA (21 variables):\n")
for (i in 1:21) {
  cat(sprintf("  %s: %.4f\n", unified_vars[i], Sigma_unified[i, i]))
}
cat("\nBlock 2 - Mental Health (2 variables):\n")
for (i in 22:23) {
  cat(sprintf("  %s: %.4f\n", unified_vars[i], Sigma_unified[i, i]))
}
cat("\nBlock 3 - Child Outcome (1 variable):\n")
cat(sprintf("  %s: %.4f\n", unified_vars[24], Sigma_unified[24, 24]))

cat("\n\nEFFECTIVE SAMPLE SIZES:\n")
cat(sprintf("  Block 1 (pooled):  %.1f\n", total_n_eff_block1))
cat(sprintf("  Block 2 (NHIS):    %.1f\n", n_eff_block2))
cat(sprintf("  Block 3 (NSCH):    %.1f\n\n", n_eff_block3))

cat("========================================\n")
cat("Phase 5b Complete: Unified Moments Pooled\n")
cat("========================================\n\n")

cat("Output: data/raking/ne25/unified_moments.rds\n")
cat("  - 24 × 1 mean vector\n")
cat("  - 24 × 24 covariance matrix (block-factored structure)\n")
cat("  - Block 1 (21 vars): 7 demographics pooled + 14 PUMA (ACS only)\n")
cat("  - Block 2 (2 vars): Mental health from NHIS\n")
cat("  - Block 3 (1 var): Child outcome from NSCH\n")
cat("  - Partial cross-covariances: Demographics with mental health & child outcome\n")
cat("  - PUMA × mental health = 0 (unobserved)\n")
cat("  - PUMA × child outcome = 0 (unobserved)\n")
cat("  - Mental health × child outcome = 0 (unobserved)\n\n")

cat("Ready for NE25 harmonization (script 32)\n\n")

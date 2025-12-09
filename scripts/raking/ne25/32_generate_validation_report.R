# Phase 4a, Task 5: Generate Comprehensive Validation Report
# Compiles all harmonization validation results into a single HTML report
# Purpose: Document all sanity checks and provide visual diagnostics

library(dplyr)
library(arrow)

cat("\n========================================\n")
cat("Task 4a.5: Generate Validation Report\n")
cat("========================================\n\n")

# 1. Load all validation utilities
cat("[1] Loading validation utilities...\n")
source("scripts/raking/ne25/utils/validate_raw_inputs.R")
source("scripts/raking/ne25/utils/validate_harmonized_distributions.R")
source("scripts/raking/ne25/utils/validate_cross_source_consistency.R")
source("scripts/raking/ne25/utils/validate_covariance_matrices.R")
source("scripts/raking/ne25/utils/validate_propensity_reweighting.R")
cat("    ✓ Utilities loaded\n\n")

# 2. Load all prepared data
cat("[2] Loading prepared data...\n")

# Load design matrices
acs_design <- arrow::read_feather("data/raking/ne25/acs_design_matrix.feather")
nhis_design <- arrow::read_feather("data/raking/ne25/nhis_design_matrix.feather")
nsch_design <- arrow::read_feather("data/raking/ne25/nsch_design_matrix.feather")

cat("    ✓ Design matrices loaded\n")

# Load reweighted data
nhis_reweighted <- readRDS("data/raking/ne25/nhis_reweighted.rds")
nsch_reweighted <- readRDS("data/raking/ne25/nsch_reweighted.rds")

cat("    ✓ Reweighted datasets loaded\n")

# Load moments
acs_moments <- readRDS("data/raking/ne25/acs_moments.rds")
nhis_moments <- readRDS("data/raking/ne25/nhis_moments.rds")
nsch_moments <- readRDS("data/raking/ne25/nsch_moments.rds")

cat("    ✓ Covariance moments loaded\n\n")

# 3. Run all validation checks
cat("[3] Running comprehensive validation checks...\n\n")

# Phase 2: Post-harmonization distribution checks
cat("--- Post-Harmonization Distribution Checks ---\n")
acs_dist_validation <- validate_harmonized_data(acs_design, "ACS")
nhis_dist_validation <- validate_harmonized_data(nhis_design, "NHIS")
nsch_dist_validation <- validate_harmonized_data(nsch_design, "NSCH")

# Phase 3: Cross-source consistency
cat("\n--- Cross-Source Consistency Checks ---\n")
consistency_validation <- validate_cross_source_consistency(
  acs_design,
  nhis_design,
  nsch_design
)

# Phase 4: Covariance matrix validation
cat("\n--- Covariance Matrix Validation ---\n")
acs_matrix_validation <- validate_covariance_matrix(acs_moments, "ACS")
nhis_matrix_validation <- validate_covariance_matrix(nhis_moments, "NHIS")
nsch_matrix_validation <- validate_covariance_matrix(nsch_moments, "NSCH")

# Phase 5: Propensity reweighting validation
cat("\n--- Propensity Reweighting Validation ---\n")

# Load ACS Nebraska for comparison
acs_nc <- arrow::read_feather("data/raking/ne25/acs_north_central.feather")
acs_ne <- acs_nc %>% dplyr::filter(STATEFIP == 31)

# Create harmonized variables for ACS Nebraska
source("scripts/raking/ne25/utils/harmonize_race_ethnicity.R")
source("scripts/raking/ne25/utils/harmonize_education.R")
source("scripts/raking/ne25/utils/harmonize_marital_status.R")

acs_ne$male <- as.integer(acs_ne$SEX == 1)
acs_ne$age <- acs_ne$AGE
acs_ne$race_harmonized <- harmonize_acs_race(acs_ne$RACE, acs_ne$HISPAN)
race_dummies <- create_race_dummies(acs_ne$race_harmonized)
acs_ne$white_nh <- race_dummies$white_nh
acs_ne$black <- race_dummies$black
acs_ne$hispanic <- race_dummies$hispanic
acs_ne$educ_years <- harmonize_acs_education(acs_ne$EDUC_MOM)
acs_ne$married <- as.integer(acs_ne$MARST_HEAD == 1)
acs_ne$poverty_ratio <- acs_ne$POVERTY

# Validate propensity reweighting for both sources
nhis_reweight_validation <- validate_propensity_reweighting(
  nhis_reweighted,
  acs_ne,
  "NHIS"
)

nsch_reweight_validation <- validate_propensity_reweighting(
  nsch_reweighted,
  acs_ne,
  "NSCH"
)

# 4. Compile validation results
cat("\n[4] Compiling validation results...\n\n")

validation_summary <- list(
  timestamp = Sys.time(),
  distribution_checks = list(
    acs = acs_dist_validation,
    nhis = nhis_dist_validation,
    nsch = nsch_dist_validation
  ),
  cross_source_consistency = consistency_validation,
  covariance_matrices = list(
    acs = acs_matrix_validation,
    nhis = nhis_matrix_validation,
    nsch = nsch_matrix_validation
  ),
  propensity_reweighting = list(
    nhis = nhis_reweight_validation,
    nsch = nsch_reweight_validation
  )
)

# 5. Generate summary report
cat("[5] Generating summary report...\n\n")

cat("========================================\n")
cat("VALIDATION SUMMARY REPORT\n")
cat("========================================\n\n")

cat("Report Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Count issues by category
dist_issues <- sum(
  length(acs_dist_validation$issues),
  length(nhis_dist_validation$issues),
  length(nsch_dist_validation$issues)
)

consistency_issues <- length(consistency_validation$issues)

matrix_issues <- sum(
  length(acs_matrix_validation$issues),
  length(nhis_matrix_validation$issues),
  length(nsch_matrix_validation$issues)
)

reweight_issues <- sum(
  length(nhis_reweight_validation$issues),
  length(nsch_reweight_validation$issues)
)

total_issues <- dist_issues + consistency_issues + matrix_issues + reweight_issues

cat("OVERALL RESULTS:\n")
cat("  Total issues detected:", total_issues, "\n")
cat("  Distribution checks:", dist_issues, "issues\n")
cat("  Cross-source consistency:", consistency_issues, "issues\n")
cat("  Covariance matrices:", matrix_issues, "issues\n")
cat("  Propensity reweighting:", reweight_issues, "issues\n\n")

if (total_issues == 0) {
  cat("✓ ALL VALIDATION CHECKS PASSED - Pipeline ready for analysis\n\n")
} else {
  cat("✗ WARNING: Issues detected - review details above\n\n")
}

# 6. Save validation results
cat("[6] Saving validation results...\n")

# Create output directory if needed
if (!dir.exists("data/raking/ne25")) {
  dir.create("data/raking/ne25", recursive = TRUE)
}

# Save as RDS for later analysis
saveRDS(validation_summary, "data/raking/ne25/validation_summary.rds")
cat("    ✓ Saved: data/raking/ne25/validation_summary.rds\n")

# 7. Create detailed report tables
cat("\n[7] Creating detailed report...\n\n")

cat("========================================\n")
cat("DETAILED VALIDATION RESULTS\n")
cat("========================================\n\n")

# Distribution checks summary
cat("[DISTRIBUTION CHECKS]\n\n")

cat("ACS Distribution Validation:\n")
cat("  Valid:", acs_dist_validation$valid, "\n")
cat("  Records:", acs_dist_validation$n_records, "\n")
if (length(acs_dist_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in acs_dist_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

cat("NHIS Distribution Validation:\n")
cat("  Valid:", nhis_dist_validation$valid, "\n")
cat("  Records:", nhis_dist_validation$n_records, "\n")
if (length(nhis_dist_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in nhis_dist_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

cat("NSCH Distribution Validation:\n")
cat("  Valid:", nsch_dist_validation$valid, "\n")
cat("  Records:", nsch_dist_validation$n_records, "\n")
if (length(nsch_dist_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in nsch_dist_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

# Cross-source consistency
cat("[CROSS-SOURCE CONSISTENCY]\n\n")
cat("  Valid:", consistency_validation$valid, "\n")
if (length(consistency_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in consistency_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

# Covariance matrices
cat("[COVARIANCE MATRICES]\n\n")

cat("ACS Covariance Matrix:\n")
cat("  Valid:", acs_matrix_validation$valid, "\n")
cat("  Condition number:", round(acs_matrix_validation$condition_number, 2), "\n")
if (length(acs_matrix_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in acs_matrix_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

cat("NHIS Covariance Matrix:\n")
cat("  Valid:", nhis_matrix_validation$valid, "\n")
cat("  Condition number:", round(nhis_matrix_validation$condition_number, 2), "\n")
if (length(nhis_matrix_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in nhis_matrix_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

cat("NSCH Covariance Matrix:\n")
cat("  Valid:", nsch_matrix_validation$valid, "\n")
cat("  Condition number:", round(nsch_matrix_validation$condition_number, 2), "\n")
if (length(nsch_matrix_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in nsch_matrix_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

# Propensity reweighting
cat("[PROPENSITY REWEIGHTING]\n\n")

cat("NHIS Propensity Reweighting:\n")
cat("  Valid:", nhis_reweight_validation$valid, "\n")
cat("  Common support (% outside):", round(nhis_reweight_validation$common_support$pct_outside, 1), "%\n")
cat("  Weight ratio:", round(nhis_reweight_validation$weight_diagnostics$weight_ratio, 1), "\n")
if (length(nhis_reweight_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in nhis_reweight_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

cat("NSCH Propensity Reweighting:\n")
cat("  Valid:", nsch_reweight_validation$valid, "\n")
cat("  Common support (% outside):", round(nsch_reweight_validation$common_support$pct_outside, 1), "%\n")
cat("  Weight ratio:", round(nsch_reweight_validation$weight_diagnostics$weight_ratio, 1), "\n")
if (length(nsch_reweight_validation$issues) > 0) {
  cat("  Issues:\n")
  for (issue in nsch_reweight_validation$issues) {
    cat("    -", issue, "\n")
  }
}
cat("\n")

# 8. Final summary
cat("========================================\n")
cat("Task 4a.5 Complete: Validation Report Generated\n")
cat("========================================\n\n")

if (total_issues == 0) {
  cat("✓ VALIDATION COMPLETE\n")
  cat("  All harmonization checks passed\n")
  cat("  Pipeline is ready for KL divergence weighting computation\n\n")
} else {
  cat("✗ VALIDATION COMPLETE WITH WARNINGS\n")
  cat("  ", total_issues, " issues detected across validation checks\n")
  cat("  Review details above before proceeding\n\n")
}

cat("Results saved to: data/raking/ne25/validation_summary.rds\n\n")

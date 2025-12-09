# Master Orchestration Script: Covariance Matrix Pipeline
# Runs complete pipeline from ACS extraction → covariance computation → diagnostics
# Output: (μ, Σ) for ACS, NHIS, NSCH with Nebraska-representative weighting

cat("\n========================================\n")
cat("COVARIANCE MATRIX PIPELINE\n")
cat("Nebraska 2025 (NE25) Raking Targets\n")
cat("========================================\n\n")

cat("This pipeline computes weighted covariance matrices from:\n")
cat("  • ACS (Nebraska children 0-5, 2019-2023)\n")
cat("  • NHIS (North Central parents → Nebraska-reweighted, 2019-2024)\n")
cat("  • NSCH (North Central children → Nebraska-reweighted, 2021-2022)\n\n")

cat("Pipeline phases:\n")
cat("  Phase 1-3: Harmonization utilities (already created)\n")
cat("  Phase 4a: Propensity score estimation and reweighting\n")
cat("  Phase 4b: Design matrix creation (8 variables)\n")
cat("  Phase 5: Weighted covariance computation\n")
cat("  Phase 6: Diagnostic visualization and validation\n\n")

# Track execution time
start_time <- Sys.time()

# ============================================================================
# PHASE 4a: Propensity Score Estimation and Reweighting
# ============================================================================

cat("========================================\n")
cat("PHASE 4a: Propensity Reweighting\n")
cat("========================================\n\n")

# Task 1: Extract ACS North Central states
if (!file.exists("data/raking/ne25/acs_north_central.feather")) {
  cat("[Task 4a.1] Extracting ACS North Central states...\n")
  source("scripts/raking/ne25/25_extract_acs_north_central.R")
} else {
  cat("[Task 4a.1] ✓ ACS North Central data exists\n\n")
}

# Task 2: Not needed - using raking instead of propensity model
cat("[Task 4a.2] Skipped - Using raking approach instead of propensity weighting\n\n")

# Task 3: Calibrate NHIS to Nebraska (KL divergence via Stan)
if (!file.exists("data/raking/ne25/nhis_calibrated.rds")) {
  cat("[Task 4a.3] Calibrating NHIS to Nebraska (KL divergence)...\n")
  source("scripts/raking/ne25/27_calibrate_nhis_to_nebraska.R")
} else {
  cat("[Task 4a.3] ✓ NHIS calibrated data exists\n\n")
}

# Task 4: Calibrate NSCH to Nebraska (KL divergence via Stan)
if (!file.exists("data/raking/ne25/nsch_calibrated.rds")) {
  cat("[Task 4a.4] Calibrating NSCH to Nebraska (KL divergence)...\n")
  source("scripts/raking/ne25/28_calibrate_nsch_to_nebraska.R")
} else {
  cat("[Task 4a.4] ✓ NSCH calibrated data exists\n\n")
}

cat("Phase 4a Complete: Propensity Reweighting\n\n")

# ============================================================================
# PHASE 4b: Design Matrix Creation
# ============================================================================

cat("========================================\n")
cat("PHASE 4b: Design Matrix Creation\n")
cat("========================================\n\n")

# Create all three design matrices (ACS, NHIS, NSCH)
design_matrices_exist <- all(file.exists(c(
  "data/raking/ne25/acs_design_matrix.feather",
  "data/raking/ne25/nhis_design_matrix.feather",
  "data/raking/ne25/nsch_design_matrix.feather"
)))

if (!design_matrices_exist) {
  cat("[Tasks 13-15] Creating design matrices...\n")
  source("scripts/raking/ne25/29_create_design_matrices.R")
} else {
  cat("[Tasks 13-15] ✓ All design matrices exist\n\n")
}

cat("Phase 4b Complete: Design Matrices Created\n\n")

# ============================================================================
# PHASE 5: Covariance Matrix Computation
# ============================================================================

cat("========================================\n")
cat("PHASE 5: Covariance Computation\n")
cat("========================================\n\n")

# Compute (μ, Σ) for all three sources
moments_exist <- all(file.exists(c(
  "data/raking/ne25/acs_moments.rds",
  "data/raking/ne25/nhis_moments.rds",
  "data/raking/ne25/nsch_moments.rds"
)))

if (!moments_exist) {
  cat("[Tasks 16-18] Computing covariance matrices...\n")
  source("scripts/raking/ne25/30_compute_covariance_matrices.R")
} else {
  cat("[Tasks 16-18] ✓ All covariance matrices exist\n\n")

  # Load and display summary
  acs_moments <- readRDS("data/raking/ne25/acs_moments.rds")
  nhis_moments <- readRDS("data/raking/ne25/nhis_moments.rds")
  nsch_moments <- readRDS("data/raking/ne25/nsch_moments.rds")

  cat("  ACS: n =", acs_moments$n, ", n_eff =", round(acs_moments$n_eff, 1), "\n")
  cat("  NHIS: n =", nhis_moments$n, ", n_eff =", round(nhis_moments$n_eff, 1), "\n")
  cat("  NSCH: n =", nsch_moments$n, ", n_eff =", round(nsch_moments$n_eff, 1), "\n\n")
}

cat("Phase 5 Complete: Covariance Matrices Computed\n\n")

# ============================================================================
# PHASE 6: Diagnostic Visualization and Validation
# ============================================================================

cat("========================================\n")
cat("PHASE 6: Diagnostic Generation\n")
cat("========================================\n\n")

# Generate all diagnostic plots and reports
diagnostics_exist <- all(file.exists(c(
  "figures/raking/acs_correlation_heatmap.png",
  "figures/raking/mean_comparison_table.csv",
  "figures/raking/propensity_common_support.png",
  "figures/raking/efficiency_summary.csv"
)))

if (!diagnostics_exist) {
  cat("[Tasks 19-22] Generating diagnostics...\n")
  source("scripts/raking/ne25/31_generate_diagnostics.R")
} else {
  cat("[Tasks 19-22] ✓ All diagnostics exist\n\n")
}

cat("Phase 6 Complete: Diagnostics Generated\n\n")

# ============================================================================
# PHASE 7: Validation Report Generation
# ============================================================================

cat("========================================\n")
cat("PHASE 7: Validation Report\n")
cat("========================================\n\n")

# Generate comprehensive validation report
if (!file.exists("validation_report.html")) {
  cat("[Task 7] Generating validation report...\n")

  # Check if quarto is available
  quarto_available <- tryCatch({
    system2("quarto", args = "--version", stdout = TRUE, stderr = TRUE)
    TRUE
  }, error = function(e) FALSE)

  if (quarto_available) {
    cat("    Rendering validation_report.qmd with Quarto...\n")
    system2("quarto", args = c("render", "scripts/raking/ne25/validation_report.qmd", "--output-dir", "."))
    cat("    ✓ Validation report generated: validation_report.html\n\n")
  } else {
    cat("    WARNING: Quarto not found - running R script instead\n")
    source("scripts/raking/ne25/32_generate_validation_report.R")
    cat("    ✓ Validation report generated (console output saved)\n\n")
  }
} else {
  cat("[Task 7] ✓ Validation report exists\n\n")
}

cat("Phase 7 Complete: Validation Report Generated\n\n")

# ============================================================================
# PIPELINE SUMMARY
# ============================================================================

end_time <- Sys.time()
elapsed <- difftime(end_time, start_time, units = "mins")

cat("========================================\n")
cat("PIPELINE COMPLETE\n")
cat("========================================\n\n")

cat("Execution time:", round(elapsed, 2), "minutes\n\n")

cat("OUTPUTS CREATED:\n\n")

cat("1. Calibrated Data (KL divergence via Stan):\n")
cat("   - data/raking/ne25/nhis_calibrated.rds\n")
cat("   - data/raking/ne25/nsch_calibrated.rds\n\n")

cat("2. Calibration Diagnostics:\n")
cat("   - data/raking/ne25/nhis_calibration_diagnostics.rds\n")
cat("   - data/raking/ne25/nsch_calibration_diagnostics.rds\n\n")

cat("3. Design Matrices (8 variables × n observations):\n")
cat("   - data/raking/ne25/acs_design_matrix.feather\n")
cat("   - data/raking/ne25/nhis_design_matrix.feather\n")
cat("   - data/raking/ne25/nsch_design_matrix.feather\n\n")

cat("4. Covariance Matrices:\n")
cat("   - data/raking/ne25/acs_moments.rds (μ^ACS, Σ^ACS)\n")
cat("   - data/raking/ne25/nhis_moments.rds (μ^NHIS, Σ^NHIS)\n")
cat("   - data/raking/ne25/nsch_moments.rds (μ^NSCH, Σ^NSCH)\n\n")

cat("5. Diagnostic Figures (figures/raking/):\n")
cat("   - acs_correlation_heatmap.png\n")
cat("   - nhis_correlation_heatmap.png\n")
cat("   - nsch_correlation_heatmap.png\n")
cat("   - correlation_comparison_3sources.png\n")
cat("   - mean_comparison_plot.png\n")
cat("   - propensity_common_support.png\n")
cat("   - efficiency_comparison.png\n\n")

cat("6. Summary Reports:\n")
cat("   - figures/raking/mean_comparison_table.csv\n")
cat("   - figures/raking/efficiency_summary.csv\n\n")

cat("NEXT STEPS:\n")
cat("  1. Review diagnostic plots for covariate balance\n")
cat("  2. Validate calibration convergence (all marginals <1%% error)\n")
cat("  3. Check efficiency metrics (target >20%% minimum)\n")
cat("  4. Use calibrated moments for NE25 survey weight adjustment\n\n")

cat("For questions or issues, see:\n")
cat("  - Plan file: ~/.claude/plans/glimmering-petting-anchor.md\n")
cat("  - Documentation: docs/raking/\n\n")

# Complete NE25 Raking Targets Pipeline
# Runs ALL phases from scratch: ACS (Phase 1) + NHIS (Phase 2) + NSCH (Phase 4) + Consolidation (Phase 5)
# This is the FULL end-to-end pipeline test including all estimation steps

library(dplyr)

# Source bootstrap configuration FIRST (single source of truth for n_boot)
source("config/bootstrap_config.R")
n_boot <- BOOTSTRAP_CONFIG$n_boot
cat("\n[CONFIG] Bootstrap configuration loaded: n_boot =", n_boot, "\n")

cat("\n========================================\n")
cat("COMPLETE NE25 Raking Targets Pipeline\n")
cat("========================================\n\n")

cat("This pipeline will generate:\n")
cat("  - Phase 1: ACS estimates (25 estimands from 7 GLM2 scripts)\n")
cat("  - Phase 2: NHIS estimates (2 estimands: PHQ-2, GAD-2)\n")
cat("  - Phase 4: NSCH estimates (4 estimands)\n")
cat("  - Phase 5: Consolidation and database\n")
cat("  - Total: 186 rows (31 estimands × 6 ages)\n")
cat("  - Bootstrap replicates:", n_boot, "\n\n")

# Track execution time
start_time <- Sys.time()

# ============================================================================
# PHASE 1: ACS ESTIMATES (25 estimands)
# ============================================================================

cat("[PHASE 1] ACS Estimates (25 estimands)\n\n")

# 1.1: Create ACS survey design (if needed)
if (!file.exists("data/raking/ne25/acs_design.rds")) {
  cat("  [1.1] Creating ACS survey design...\n")
  source("scripts/raking/ne25/01_create_acs_design.R")
} else {
  cat("  ✓ ACS survey design exists\n")
}

# 1.1a: Create ACS bootstrap design (if needed)
if (!file.exists("data/raking/ne25/acs_bootstrap_design.rds")) {
  cat("  [1.1a] Creating ACS bootstrap design (4096 replicates)...\n")
  cat("         This may take 1-2 minutes...\n")
  source("scripts/raking/ne25/01a_create_acs_bootstrap_design.R")
} else {
  cat("  ✓ ACS bootstrap design exists\n")
}

# 1.2: Estimate sex (1 estimand: Male)
cat("  [1.2] Estimating sex distribution...\n")
source("scripts/raking/ne25/02_estimate_sex_glm2.R")

# 1.3: Estimate race/ethnicity (3 estimands)
cat("  [1.3] Estimating race/ethnicity...\n")
source("scripts/raking/ne25/03_estimate_race_ethnicity_glm2.R")

# 1.4: Estimate FPL (5 estimands)
cat("  [1.4] Estimating income (FPL categories)...\n")
source("scripts/raking/ne25/04_estimate_fpl_glm2.R")

# 1.5: Estimate PUMA (14 estimands)
cat("  [1.5] Estimating PUMA geography...\n")
source("scripts/raking/ne25/05_estimate_puma_glm2.R")

# 1.6: Estimate mother's education (1 estimand)
cat("  [1.6] Estimating mother's education...\n")
source("scripts/raking/ne25/06_estimate_mother_education_glm2.R")

# 1.7: Estimate mother's marital status (1 estimand)
cat("  [1.7] Estimating mother's marital status...\n")
source("scripts/raking/ne25/07_estimate_mother_marital_status_glm2.R")

# 1.8: Compile ACS estimates
cat("  [1.8] Compiling ACS estimates...\n")
source("scripts/raking/ne25/08_compile_acs_estimates.R")

# 1.9: Validate ACS estimates
cat("  [1.9] Validating ACS estimates...\n")
source("scripts/raking/ne25/09_validate_acs_estimates.R")

# 1.10: Save final ACS estimates
cat("  [1.10] Saving final ACS estimates...\n")
source("scripts/raking/ne25/10_save_acs_estimates_final.R")

acs_est <- readRDS("data/raking/ne25/acs_estimates.rds")
cat("  ✓ ACS Phase 1 Complete:", nrow(acs_est), "rows\n\n")

# ============================================================================
# PHASE 2: NHIS ESTIMATES (2 estimands: PHQ-2, GAD-2)
# ============================================================================

cat("[PHASE 2] NHIS Estimates (2 estimands: PHQ-2, GAD-2)\n\n")

# 2.1: Filter NHIS parents
if (!file.exists("data/raking/ne25/nhis_parents_ne.rds")) {
  cat("  [2.1] Filtering NHIS parents...\n")
  source("scripts/raking/ne25/12_filter_nhis_parents.R")
} else {
  cat("  ✓ NHIS parents data exists\n")
}

# 2.1a: Create NHIS bootstrap design (if needed)
if (!file.exists("data/raking/ne25/nhis_bootstrap_design.rds")) {
  cat("  [2.1a] Creating NHIS bootstrap design (4096 replicates)...\n")
  cat("         This may take 1-2 minutes...\n")
  source("scripts/raking/ne25/12a_create_nhis_bootstrap_design.R")
} else {
  cat("  ✓ NHIS bootstrap design exists\n")
}

# 2.2: Estimate PHQ-2 (depression)
cat("  [2.2] Estimating PHQ-2 (depression)...\n")
source("scripts/raking/ne25/13_estimate_phq2_glm2.R")

# 2.3: Estimate GAD-2 (anxiety)
cat("  [2.3] Estimating GAD-2 (anxiety)...\n")
source("scripts/raking/ne25/13b_estimate_gad2_glm2.R")

cat("  ✓ NHIS Phase 2 Complete: 2 estimands\n\n")

# ============================================================================
# PHASE 4: NSCH ESTIMATES (4 estimands)
# ============================================================================

cat("[PHASE 4] NSCH Estimates (4 estimands)\n\n")

# 4.1: Filter NSCH Nebraska children
if (!file.exists("data/raking/ne25/nsch_nebraska.rds")) {
  cat("  [4.1] Filtering NSCH Nebraska children...\n")
  source("scripts/raking/ne25/17_filter_nsch_nebraska.R")
} else {
  cat("  ✓ NSCH Nebraska data exists\n")
}

# 4.1a: Create NSCH bootstrap design (if needed)
if (!file.exists("data/raking/ne25/nsch_bootstrap_design.rds")) {
  cat("  [4.1a] Creating NSCH bootstrap design (4096 replicates)...\n")
  cat("         This may take 1-2 minutes...\n")
  source("scripts/raking/ne25/17a_create_nsch_bootstrap_design.R")
} else {
  cat("  ✓ NSCH bootstrap design exists\n")
}

# 4.2: Estimate NSCH outcomes (3 estimands)
cat("  [4.2] Estimating NSCH outcomes...\n")
source("scripts/raking/ne25/18_estimate_nsch_outcomes_glm2.R")

# 4.3: Estimate child care (1 estimand)
cat("  [4.3] Estimating child care...\n")
source("scripts/raking/ne25/20_estimate_childcare_2022.R")

# 4.4: Validate and save NSCH estimates
cat("  [4.4] Validating NSCH estimates...\n")
source("scripts/raking/ne25/19_validate_save_nsch.R")

nsch_est <- readRDS("data/raking/ne25/nsch_estimates.rds")
cat("  ✓ NSCH Phase 4 Complete:", nrow(nsch_est), "rows\n\n")

# ============================================================================
# PHASE 5: CONSOLIDATION AND DATABASE
# ============================================================================

cat("[PHASE 5] Consolidation and Database\n\n")

# Bootstrap consolidation
cat("  [Bootstrap Consolidation] Combining all bootstrap replicates...\n")

# 5.1: Consolidate ACS bootstrap replicates
cat("  [5.1] Consolidating ACS bootstrap replicates...\n")
source("scripts/raking/ne25/21a_consolidate_acs_bootstrap.R")

# 5.2: Consolidate NSCH bootstrap replicates
cat("  [5.2] Consolidating NSCH bootstrap replicates...\n")
source("scripts/raking/ne25/21b_consolidate_nsch_boot.R")

# 5.3: Consolidate ALL bootstrap replicates
cat("  [5.3] Consolidating ALL bootstrap replicates (ACS + NHIS + NSCH)...\n")
source("scripts/raking/ne25/22_consolidate_all_boot_replicates.R")

# 5.4: Consolidate point estimates
cat("  [5.4] Consolidating point estimates...\n")
source("scripts/raking/ne25/21_consolidate_estimates.R")

# 5.5: Add descriptions
cat("  [5.5] Adding estimand descriptions...\n")
source("scripts/raking/ne25/22_add_descriptions.R")

# 5.6: Validate consolidated data
cat("  [5.6] Validating consolidated data...\n")
source("scripts/raking/ne25/23_validate_targets.R")

# 5.7: Load to database
cat("  [5.7] Loading to database...\n")
system2(
  "C:/Users/marcu/AppData/Local/Programs/Python/Python313/python.exe",
  args = c("scripts/raking/ne25/24_create_database_table.py"),
  stdout = TRUE,
  stderr = TRUE
)

cat("\n")

# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("========================================\n")
cat("Complete Pipeline Finished\n")
cat("========================================\n\n")

end_time <- Sys.time()
elapsed <- difftime(end_time, start_time, units = "mins")

all_est <- readRDS("data/raking/ne25/raking_targets_consolidated.rds")
all_boot <- readRDS("data/raking/ne25/all_bootstrap_replicates.rds")

cat("Summary:\n")
cat("  ACS estimands: 25\n")
cat("  NHIS estimands: 2 (PHQ-2, GAD-2)\n")
cat("  NSCH estimands: 4\n")
cat("  Total estimands:", length(unique(all_est$estimand)), "\n")
cat("  Total rows:", nrow(all_est), "(31 estimands × 6 ages)\n")
cat("  Bootstrap replicates:", nrow(all_boot), "(31 × 6 × 4096)\n")
cat("  Database table: raking_targets_ne25\n")
cat("  Execution time:", round(elapsed, 2), "minutes\n\n")

cat("To query the raking targets:\n")
cat("  Python: from python.db.connection import DatabaseManager\n")
cat("          db = DatabaseManager()\n")
cat("          with db.get_connection(read_only=True) as conn:\n")
cat("              results = conn.execute(\"SELECT * FROM raking_targets_ne25 WHERE age_years = 3\").fetchall()\n\n")

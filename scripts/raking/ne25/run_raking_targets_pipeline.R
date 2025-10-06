# NE25 Raking Targets Pipeline (Phases 1-5)
# Master orchestration script for generating raking targets
#
# This pipeline:
# - Phase 1: Loads and processes ACS data (25 estimands)
# - Phase 2: Filters and estimates NHIS data (1 estimand)
# - Phase 3: (Deprecated - replaced by Phase 4)
# - Phase 4: Filters and estimates NSCH data (4 estimands)
# - Phase 5: Consolidates, validates, and loads to database
#
# Output: raking_targets_ne25 table with 180 rows (30 estimands × 6 ages)

library(dplyr)

cat("\n========================================\n")
cat("NE25 Raking Targets Pipeline\n")
cat("========================================\n\n")

# Track execution time
start_time <- Sys.time()

# PHASE 1: ACS Estimates (already completed - skip if files exist)
cat("[PHASE 1] ACS Estimates (25 estimands)\n")
if (!file.exists("data/raking/ne25/acs_estimates.rds")) {
  cat("  ERROR: ACS estimates not found. Run ACS pipeline first:\n")
  cat("    scripts/raking/ne25/01_*.R through 10_*.R\n")
  stop("Missing ACS estimates")
} else {
  acs_est <- readRDS("data/raking/ne25/acs_estimates.rds")
  cat("  ✓ Loaded ACS estimates:", nrow(acs_est), "rows\n\n")
}

# PHASE 2: NHIS Estimates (1 estimand)
cat("[PHASE 2] NHIS Estimates (1 estimand)\n")

# Check if NHIS data needs to be filtered
if (!file.exists("data/raking/ne25/nhis_parents_ne.rds")) {
  cat("  [2.1] Filtering NHIS parents...\n")
  source("scripts/raking/ne25/12_filter_nhis_parents.R")
} else {
  cat("  ✓ NHIS parents data exists\n")
}

# Check if NHIS estimates need to be calculated
if (!file.exists("data/raking/ne25/nhis_estimates_raw.rds")) {
  cat("  [2.2] Estimating PHQ-2 outcomes...\n")
  source("scripts/raking/ne25/13_estimate_phq2.R")
} else {
  cat("  ✓ NHIS raw estimates exist\n")
}

# Validate and save NHIS estimates
cat("  [2.3] Validating NHIS estimates...\n")
source("scripts/raking/ne25/14_validate_save_nhis.R")

nhis_est <- readRDS("data/raking/ne25/nhis_estimates.rds")
cat("  ✓ NHIS estimates validated:", nrow(nhis_est), "rows\n\n")

# PHASE 4: NSCH Estimates (4 estimands)
cat("[PHASE 4] NSCH Estimates (4 estimands)\n")

# Check if NSCH Nebraska data needs to be filtered
if (!file.exists("data/raking/ne25/nsch_nebraska.rds")) {
  cat("  [4.1] Filtering NSCH Nebraska children...\n")
  source("scripts/raking/ne25/17_filter_nsch_nebraska.R")
} else {
  cat("  ✓ NSCH Nebraska data exists\n")
}

# Check if NSCH 2023 estimates need to be calculated
if (!file.exists("data/raking/ne25/nsch_estimates_raw.rds")) {
  cat("  [4.2] Estimating NSCH 2023 outcomes...\n")
  source("scripts/raking/ne25/18_estimate_nsch_outcomes.R")
} else {
  cat("  ✓ NSCH 2023 raw estimates exist\n")
}

# Check if NSCH 2022 child care estimates need to be calculated
if (!file.exists("data/raking/ne25/childcare_2022_estimates.rds")) {
  cat("  [4.3] Estimating child care from NSCH 2022...\n")
  source("scripts/raking/ne25/20_estimate_childcare_2022.R")
} else {
  cat("  ✓ NSCH 2022 child care estimates exist\n")
}

# Validate and save NSCH estimates
cat("  [4.4] Validating NSCH estimates...\n")
source("scripts/raking/ne25/19_validate_save_nsch.R")

nsch_est <- readRDS("data/raking/ne25/nsch_estimates.rds")
cat("  ✓ NSCH estimates validated:", nrow(nsch_est), "rows\n\n")

# PHASE 5: Consolidation and Database
cat("[PHASE 5] Consolidation and Database\n")

# Consolidate all estimates
cat("  [5.1-5.2] Consolidating estimates...\n")
source("scripts/raking/ne25/21_consolidate_estimates.R")

# Add descriptions
cat("  [5.3] Adding estimand descriptions...\n")
source("scripts/raking/ne25/22_add_descriptions.R")

# Validate consolidated data
cat("  [5.4-5.5] Validating consolidated data...\n")
source("scripts/raking/ne25/23_validate_targets.R")

# Load to database
cat("  [5.6-5.9] Loading to database...\n")
system2(
  "C:/Users/marcu/AppData/Local/Programs/Python/Python313/python.exe",
  args = c("scripts/raking/ne25/24_create_database_table.py"),
  stdout = TRUE,
  stderr = TRUE
)

cat("\n")

# Final summary
cat("========================================\n")
cat("Pipeline Complete\n")
cat("========================================\n\n")

end_time <- Sys.time()
elapsed <- difftime(end_time, start_time, units = "mins")

cat("Summary:\n")
cat("  ACS estimands:", length(unique(acs_est$estimand)), "\n")
cat("  NHIS estimands:", length(unique(nhis_est$estimand)), "\n")
cat("  NSCH estimands:", length(unique(nsch_est$estimand)), "\n")
cat("  Total estimands:",
    length(unique(acs_est$estimand)) +
    length(unique(nhis_est$estimand)) +
    length(unique(nsch_est$estimand)), "\n")
cat("  Total rows:", nrow(acs_est) + nrow(nhis_est) + nrow(nsch_est), "\n")
cat("  Database table: raking_targets_ne25\n")
cat("  Execution time:", round(elapsed, 2), "minutes\n\n")

cat("To query the raking targets:\n")
cat("  Python: from python.db.connection import DatabaseManager\n")
cat("          db = DatabaseManager()\n")
cat("          with db.get_connection(read_only=True) as conn:\n")
cat("              results = conn.execute(\"SELECT * FROM raking_targets_ne25 WHERE age_years = 3\").fetchall()\n\n")

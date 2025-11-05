#!/usr/bin/env Rscript
# =============================================================================
# IRT Calibration Pipeline - Main Orchestrator
# =============================================================================
# Purpose: Generate and export IRT calibration dataset from multiple studies
#
# This pipeline:
#   1. Creates/updates study-specific calibration tables (NE20, NE22, USA24, NE25, NSCH21, NSCH22)
#   2. Combines tables and exports to Mplus .dat format
#   3. Validates output and reports summary statistics
#
# Usage:
#   # Full pipeline (create tables + export)
#   Rscript scripts/irt_scoring/run_calibration_pipeline.R
#
#   # Skip table creation, only export (faster if tables exist)
#   Rscript scripts/irt_scoring/run_calibration_pipeline.R --export-only
#
#   # Create tables only (no export)
#   Rscript scripts/irt_scoring/run_calibration_pipeline.R --tables-only
#
#   # Custom NSCH sample size
#   Rscript scripts/irt_scoring/run_calibration_pipeline.R --nsch-sample 5000
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("IRT CALIBRATION PIPELINE\n")
cat(strrep("=", 80), "\n\n")

# =============================================================================
# Parse Command Line Arguments
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)

# Default parameters
export_only <- "--export-only" %in% args
tables_only <- "--tables-only" %in% args
skip_quality_check <- "--skip-quality-check" %in% args
nsch_sample_size <- 1000  # Default sample size

# Parse NSCH sample size
nsch_arg_idx <- which(args == "--nsch-sample")
if (length(nsch_arg_idx) > 0 && length(args) >= nsch_arg_idx + 1) {
  nsch_sample_size <- as.integer(args[nsch_arg_idx + 1])
}

cat("Pipeline Configuration:\n")
cat(sprintf("  Mode: %s\n",
            ifelse(export_only, "EXPORT ONLY",
                   ifelse(tables_only, "TABLES ONLY", "FULL PIPELINE"))))
cat(sprintf("  NSCH sample size: %d per year\n", nsch_sample_size))
cat(sprintf("  Quality check: %s\n", ifelse(skip_quality_check, "SKIPPED", "ENABLED")))
cat(sprintf("  Database: data/duckdb/kidsights_local.duckdb\n"))
cat(sprintf("  Output: mplus/calibdat.dat\n\n"))

# =============================================================================
# Step 1: Create/Update Calibration Tables
# =============================================================================

if (!export_only) {
  cat(strrep("=", 80), "\n")
  cat("STEP 1: CREATE/UPDATE CALIBRATION TABLES\n")
  cat(strrep("=", 80), "\n\n")
  
  # Check if historical tables exist
  library(duckdb)
  conn <- duckdb::dbConnect(duckdb::duckdb(), 
                             dbdir = "data/duckdb/kidsights_local.duckdb", 
                             read_only = TRUE)
  tables <- DBI::dbListTables(conn)
  DBI::dbDisconnect(conn)
  
  historical_tables <- c("ne20_calibration", "ne22_calibration", "usa24_calibration")
  historical_exist <- all(historical_tables %in% tables)
  
  # Import historical data if needed
  if (!historical_exist) {
    cat("[1A] Importing historical calibration data (NE20, NE22, USA24)\n\n")
    source("scripts/irt_scoring/import_historical_calibration.R")
    cat("\n")
  } else {
    cat("[1A] Historical calibration tables already exist (skipping import)\n\n")
  }
  
  # Create/update current study tables
  cat("[1B] Creating current study calibration tables (NE25, NSCH21, NSCH22)\n\n")
  source("scripts/irt_scoring/create_calibration_tables.R")
  create_calibration_tables(
    codebook_path = "codebook/data/codebook.json",
    db_path = "data/duckdb/kidsights_local.duckdb",
    studies = c("NE25", "NSCH21", "NSCH22")
  )
  
  cat("\n[OK] All calibration tables created/updated\n\n")
}

# =============================================================================
# Step 2: Validate Calibration Tables
# =============================================================================

if (!export_only && !tables_only) {
  cat(strrep("=", 80), "\n")
  cat("STEP 2: VALIDATE CALIBRATION TABLES\n")
  cat(strrep("=", 80), "\n\n")

  cat("Running validation checks...\n\n")
  source("scripts/irt_scoring/validate_calibration_tables.R")
  cat("\n")
}

# =============================================================================
# Step 2.5: Quality Assessment (Optional)
# =============================================================================

if (!export_only && !tables_only && !skip_quality_check) {
  cat(strrep("=", 80), "\n")
  cat("STEP 2.5: DATA QUALITY ASSESSMENT\n")
  cat(strrep("=", 80), "\n\n")

  cat("Running quality checks on calibration data...\n\n")
  source("scripts/irt_scoring/validate_calibration_quality.R")

  validate_calibration_quality(
    db_path = "data/duckdb/kidsights_local.duckdb",
    codebook_path = "codebook/data/codebook.json",
    output_path = "docs/irt_scoring/quality_flags.csv",
    verbose = TRUE
  )

  cat("\n[INFO] Quality assessment complete. Review flags at:\n")
  cat("       - CSV: docs/irt_scoring/quality_flags.csv\n")
  cat("       - HTML Report: docs/irt_scoring/calibration_quality_report.html\n")
  cat("       (Render report with: quarto render docs/irt_scoring/calibration_quality_report.qmd)\n\n")
}

# =============================================================================
# Step 3: Export Calibration Dataset
# =============================================================================

if (!tables_only) {
  cat(strrep("=", 80), "\n")
  cat("STEP 3: EXPORT CALIBRATION DATASET\n")
  cat(strrep("=", 80), "\n\n")
  
  source("scripts/irt_scoring/export_calibration_dat.R")
  
  export_calibration_dat(
    output_dat = "mplus/calibdat.dat",
    db_path = "data/duckdb/kidsights_local.duckdb",
    studies = "ALL",
    nsch_sample_size = nsch_sample_size,
    nsch_sample_seed = 12345,
    create_db_view = FALSE
  )
  
  cat("\n[OK] Calibration dataset exported\n\n")
}

# =============================================================================
# Summary
# =============================================================================

cat(strrep("=", 80), "\n")
cat("PIPELINE COMPLETE\n")
cat(strrep("=", 80), "\n\n")

if (!tables_only) {
  cat("Output Files:\n")
  cat("  - mplus/calibdat.dat (Mplus-compatible dataset)\n\n")
}

cat("Calibration Tables in Database:\n")
cat("  - ne20_calibration   (37,546 records - Nebraska 2020)\n")
cat("  - ne22_calibration   (2,431 records  - Nebraska 2022)\n")
cat("  - ne25_calibration   (3,507 records  - Nebraska 2025)\n")
cat("  - nsch21_calibration (20,719 records - NSCH 2021, ALL data)\n")
cat("  - nsch22_calibration (19,741 records - NSCH 2022, ALL data)\n")
cat("  - usa24_calibration  (1,600 records  - USA 2024)\n\n")

cat("Next Steps:\n")
cat("  1. Review output: mplus/calibdat.dat\n")
cat("  2. Create Mplus .inp file: See docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md\n")
cat("  3. Run Mplus calibration: mplus calibration.inp\n\n")

cat("[OK] IRT Calibration Pipeline completed successfully\n\n")

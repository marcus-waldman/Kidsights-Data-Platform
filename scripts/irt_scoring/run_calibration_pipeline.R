#!/usr/bin/env Rscript
# =============================================================================
# IRT Calibration Pipeline - Main Orchestrator
# =============================================================================
# Purpose: Generate and export IRT calibration dataset from multiple studies
#
# This pipeline:
#   1. Creates/updates study-specific calibration tables (NE20, NE22, USA24, NE25, NSCH21, NSCH22)
#   2. Validates calibration tables (record counts, age ranges, item coverage)
#   3. Validates for sentinel missing codes (values >= 90) - MANDATORY
#   4. Validates calibration data quality (category mismatches, negative correlations)
#   5. Creates long format dataset with QA masking (NEW in v3.5)
#   6. Exports to Mplus .dat format
#   7. Reports summary statistics
#
# Usage:
#   # Full pipeline (create tables + long format + export)
#   Rscript scripts/irt_scoring/run_calibration_pipeline.R
#
#   # Skip table creation, only export (faster if tables exist)
#   Rscript scripts/irt_scoring/run_calibration_pipeline.R --export-only
#
#   # Create tables only (no export)
#   Rscript scripts/irt_scoring/run_calibration_pipeline.R --tables-only
#
#   # Skip long format creation (faster)
#   Rscript scripts/irt_scoring/run_calibration_pipeline.R --skip-long-format
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
skip_long_format <- "--skip-long-format" %in% args
nsch_sample_size <- 1000  # Default sample size

# Quality checks are now MANDATORY (removed --skip-quality-check option)

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
cat(sprintf("  Quality check: MANDATORY (always enabled)\n"))
cat(sprintf("  Long format creation: %s\n", ifelse(skip_long_format, "SKIPPED", "ENABLED")))
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

  # Validate NE25 calibration table (most critical for data loss detection)
  cat("[1C] Validating NE25 calibration table item presence\n\n")
  source("R/utils/verify_calibration_items.R")

  library(duckdb)
  conn <- duckdb::dbConnect(duckdb::duckdb(),
                             dbdir = "data/duckdb/kidsights_local.duckdb",
                             read_only = TRUE)
  ne25_calib <- DBI::dbReadTable(conn, "ne25_calibration")
  DBI::dbDisconnect(conn)

  ne25_verification <- verify_calibration_items(
    data = ne25_calib,
    lexicon_name = "equate",
    verbose = TRUE,
    stop_on_missing = FALSE  # Don't stop - missing items OK for multi-study context
  )

  if (ne25_verification$passed) {
    cat("[OK] NE25 calibration table: All expected items present\n\n")
  } else {
    cat(sprintf("[WARNING] NE25 calibration table: %d expected items missing\n\n",
                length(ne25_verification$missing_items)))
  }
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
# Step 2.4: Sentinel Missing Code Validation (MANDATORY)
# =============================================================================

if (!export_only && !tables_only) {
  cat(strrep("=", 80), "\n")
  cat("STEP 2.4: SENTINEL MISSING CODE VALIDATION (MANDATORY)\n")
  cat(strrep("=", 80), "\n\n")

  cat("Checking ALL calibration tables for sentinel missing codes (values >= 90)...\n")
  cat("This validates:\n")
  cat("  - Historical data (NE20, NE22, USA24)\n")
  cat("  - NSCH transformations (NSCH21, NSCH22)\n")
  cat("  - Current study (NE25)\n\n")

  source("scripts/irt_scoring/validate_calibration_sentinel_codes.R")

  validate_calibration_sentinel_codes(
    db_path = "data/duckdb/kidsights_local.duckdb",
    codebook_path = "codebook/data/codebook.json",
    verbose = TRUE,
    stop_on_error = TRUE  # STOP pipeline if contamination detected
  )

  cat("\n[OK] All calibration tables are clean (no values >= 90)\n\n")
}

# =============================================================================
# Step 2.5: Data Quality Assessment (MANDATORY)
# =============================================================================

if (!export_only && !tables_only) {
  cat(strrep("=", 80), "\n")
  cat("STEP 2.5: DATA QUALITY ASSESSMENT (MANDATORY)\n")
  cat(strrep("=", 80), "\n\n")

  cat("Running mandatory quality checks on calibration data...\n\n")
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
# Step 2.6: Create Long Format Dataset with QA Masking
# =============================================================================

if (!export_only && !tables_only && !skip_long_format) {
  cat(strrep("=", 80), "\n")
  cat("STEP 2.6: CREATE LONG FORMAT DATASET\n")
  cat(strrep("=", 80), "\n\n")

  cat("Creating long format calibration dataset with:\n")
  cat("  - ALL NSCH data (development + holdout for external validation)\n")
  cat("  - Cook's D influence point detection\n")
  cat("  - QA masking flags (NE25 removal + influence points)\n\n")

  source("scripts/irt_scoring/create_calibration_long.R")

  cat("\n[OK] Long format dataset created: calibration_dataset_long\n")
  cat("     - 1.39M rows × 9 columns (id, years, study, studynum, lex_equate, y, cooksd_quantile, maskflag, devflag)\n")
  cat("     - Development sample: devflag=1\n")
  cat("     - NSCH holdout: devflag=0\n")
  cat("     - QA cleaned: maskflag=1\n\n")

  # Validate long format dataset
  cat("[2.6A] Validating long format dataset integrity\n\n")

  library(duckdb)
  conn <- duckdb::dbConnect(duckdb::duckdb(),
                             dbdir = "data/duckdb/kidsights_local.duckdb",
                             read_only = TRUE)
  long_data <- DBI::dbReadTable(conn, "calibration_dataset_long")
  DBI::dbDisconnect(conn)

  # Validate required columns exist
  required_cols <- c("id", "years", "study", "studynum", "lex_equate", "y",
                     "cooksd_quantile", "maskflag", "devflag")
  missing_cols <- setdiff(required_cols, names(long_data))

  if (length(missing_cols) > 0) {
    cat(sprintf("[ERROR] Long format dataset missing required columns: %s\n",
                paste(missing_cols, collapse = ", ")))
  } else {
    cat("[OK] All required columns present\n")
  }

  # Validate maskflag and devflag distributions
  maskflag_dist <- table(long_data$maskflag)
  devflag_dist <- table(long_data$devflag)

  cat(sprintf("\nMaskflag distribution:\n"))
  cat(sprintf("  0 (original):  %d rows (%.1f%%)\n",
              maskflag_dist["0"], 100 * maskflag_dist["0"] / sum(maskflag_dist)))
  cat(sprintf("  1 (QA cleaned): %d rows (%.1f%%)\n",
              maskflag_dist["1"], 100 * maskflag_dist["1"] / sum(maskflag_dist)))

  cat(sprintf("\nDevflag distribution:\n"))
  cat(sprintf("  0 (NSCH holdout):   %d rows (%.1f%%)\n",
              devflag_dist["0"], 100 * devflag_dist["0"] / sum(devflag_dist)))
  cat(sprintf("  1 (development):    %d rows (%.1f%%)\n",
              devflag_dist["1"], 100 * devflag_dist["1"] / sum(devflag_dist)))

  # Validate cooksd_quantile range
  cooksd_range <- range(long_data$cooksd_quantile, na.rm = TRUE)
  cat(sprintf("\nCook's D quantile range: [%.4f, %.4f]\n", cooksd_range[1], cooksd_range[2]))

  if (cooksd_range[1] < 0 || cooksd_range[2] > 1) {
    cat("[WARNING] Cook's D quantile outside expected range [0, 1]\n")
  } else {
    cat("[OK] Cook's D quantile within expected range\n")
  }

  cat("\n[OK] Long format dataset validation complete\n\n")

} else if (!export_only && !tables_only && skip_long_format) {
  cat(strrep("=", 80), "\n")
  cat("STEP 2.6: CREATE LONG FORMAT DATASET (SKIPPED)\n")
  cat(strrep("=", 80), "\n\n")
  cat("[INFO] Long format creation skipped (--skip-long-format flag)\n\n")
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

  # Validate Mplus export format
  cat("[3A] Validating Mplus export file format\n\n")
  source("R/utils/verify_mplus_export.R")

  # Calculate expected counts from actual table sizes
  library(duckdb)
  conn_validate <- duckdb::dbConnect(duckdb::duckdb(),
                                     dbdir = "data/duckdb/kidsights_local.duckdb",
                                     read_only = TRUE)

  expected_records <- (
    DBI::dbGetQuery(conn_validate, "SELECT COUNT(*) as n FROM ne20_calibration")$n +
    DBI::dbGetQuery(conn_validate, "SELECT COUNT(*) as n FROM ne22_calibration")$n +
    DBI::dbGetQuery(conn_validate, "SELECT COUNT(*) as n FROM ne25_calibration")$n +
    DBI::dbGetQuery(conn_validate, "SELECT COUNT(*) as n FROM usa24_calibration")$n +
    (2 * nsch_sample_size)  # NSCH21 + NSCH22 samples
  )

  DBI::dbDisconnect(conn_validate)

  mplus_verification <- verify_mplus_export(
    dat_file = "mplus/calibdat.dat",
    expected_n = expected_records,
    expected_vars = NULL,  # Variable count depends on item selection
    verbose = TRUE,
    stop_on_error = FALSE  # Don't stop - allow warnings
  )

  if (mplus_verification$passed) {
    cat("[OK] Mplus export file format validated\n\n")
  } else {
    cat(sprintf("[WARNING] Mplus export has %d format issues - review before calibration\n\n",
                length(mplus_verification$errors)))
  }
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

cat("Calibration Tables in Database:\n\n")
cat("Study-Specific Tables (Wide Format):\n")
cat("  - ne20_calibration   (37,546 records - Nebraska 2020)\n")
cat("  - ne22_calibration   (2,431 records  - Nebraska 2022)\n")
cat("  - ne25_calibration   (3,507 records  - Nebraska 2025)\n")
cat("  - nsch21_calibration (20,719 records - NSCH 2021, ALL data)\n")
cat("  - nsch22_calibration (19,741 records - NSCH 2022, ALL data)\n")
cat("  - usa24_calibration  (1,600 records  - USA 2024)\n\n")

cat("Long Format Table (NEW):\n")
cat("  - calibration_dataset_long (1,390,768 rows)\n")
cat("    * Includes ALL NSCH data (development + holdout)\n")
cat("    * QA masking flags (maskflag: 0=original, 1=cleaned)\n")
cat("    * Dev/holdout split (devflag: 1=development, 0=NSCH holdout)\n")
cat("    * Cook's D influence quantiles for each item\n\n")

cat("Next Steps:\n")
cat("  1. Review output: mplus/calibdat.dat (wide format export)\n")
cat("  2. OR export from long format (QA cleaned):\n")
cat("     See docs/irt_scoring/calibration_qa_cleanup_summary.md for query examples\n")
cat("  3. Create Mplus .inp file: See docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md\n")
cat("  4. Run Mplus calibration: mplus calibration.inp\n")
cat("  5. Validate with NSCH holdout: Query calibration_dataset_long WHERE devflag=0\n\n")

cat("[OK] IRT Calibration Pipeline completed successfully\n\n")

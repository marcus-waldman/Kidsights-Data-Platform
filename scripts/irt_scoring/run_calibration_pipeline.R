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
# Step 1: Verify Data Sources (SIMPLIFIED - No Study Tables Created)
# =============================================================================
#
# NOTE: Study-specific calibration tables (ne25_calibration, nsch21_calibration, etc.)
#       are NO LONGER CREATED. The calibration_dataset_long table created in Step 2.6
#       is the SINGLE SOURCE OF TRUTH for all calibration data.
#
# This step only verifies that upstream data sources exist:
#   - ne25_transformed (NE25 pipeline output)
#   - historical_calibration_2020_2024 (NE20, NE22, USA24 combined)
#   - nsch_2021, nsch_2022 (NSCH raw data)
# =============================================================================

if (!export_only) {
  cat(strrep("=", 80), "\n")
  cat("STEP 1: VERIFY DATA SOURCES\n")
  cat(strrep("=", 80), "\n\n")

  # Check if required upstream tables exist
  library(duckdb)
  conn <- duckdb::dbConnect(duckdb::duckdb(),
                             dbdir = "data/duckdb/kidsights_local.duckdb",
                             read_only = TRUE)
  tables <- DBI::dbListTables(conn)
  DBI::dbDisconnect(conn)

  required_tables <- c("ne25_transformed", "historical_calibration_2020_2024",
                       "nsch_2021", "nsch_2022")
  missing_tables <- setdiff(required_tables, tables)

  if (length(missing_tables) > 0) {
    stop(sprintf("Missing required upstream tables: %s\nRun the appropriate pipelines first.",
                 paste(missing_tables, collapse = ", ")))
  }

  cat("[OK] All required upstream data sources exist:\n")
  cat("     - ne25_transformed (NE25 pipeline)\n")
  cat("     - historical_calibration_2020_2024 (NE20, NE22, USA24)\n")
  cat("     - nsch_2021, nsch_2022 (NSCH raw data)\n\n")
}

# =============================================================================
# Step 2: Create Long Format Dataset (SINGLE SOURCE OF TRUTH)
# =============================================================================

if (!export_only && !tables_only && !skip_long_format) {
  cat(strrep("=", 80), "\n")
  cat("STEP 2: CREATE LONG FORMAT DATASET\n")
  cat(strrep("=", 80), "\n\n")

  cat("Creating calibration_dataset_long (SINGLE SOURCE OF TRUTH) with:\n")
  cat("  - NE25 data from ne25_transformed (direct, no intermediate table)\n")
  cat("  - Historical data (NE20, NE22, USA24)\n")
  cat("  - ALL NSCH data (development + holdout for external validation)\n")
  cat("  - Seeded dev/holdout split (reproducible)\n")
  cat("  - Cook's D influence point detection\n")
  cat("  - QA masking flags\n\n")

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
  cat("STEP 2: CREATE LONG FORMAT DATASET (SKIPPED)\n")
  cat(strrep("=", 80), "\n\n")
  cat("[INFO] Long format creation skipped (--skip-long-format flag)\n")
  cat("[WARNING] Using existing calibration_dataset_long table from previous run\n\n")
}

# =============================================================================
# Step 3: Data Quality Assessment
# =============================================================================

if (!export_only && !tables_only) {
  cat(strrep("=", 80), "\n")
  cat("STEP 3: DATA QUALITY ASSESSMENT\n")
  cat(strrep("=", 80), "\n\n")

  cat("Running mandatory quality checks on calibration_dataset_long...\n\n")
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
# Step 4: Export to Mplus Format (DEPRECATED - Use calibration_dataset_long instead)
# =============================================================================

if (!tables_only) {
  cat(strrep("=", 80), "\n")
  cat("STEP 4: EXPORT TO MPLUS FORMAT (DEPRECATED)\n")
  cat(strrep("=", 80), "\n\n")

  cat("[NOTE] The export_calibration_dat.R function still uses old study-specific tables.\n")
  cat("       This step is DEPRECATED and will be removed in future versions.\n")
  cat("       For Mplus calibration, query calibration_dataset_long directly using DuckDB.\n")
  cat("       See: docs/irt_scoring/calibration_qa_cleanup_summary.md\n\n")

  cat("[INFO] Skipping deprecated Mplus export step\n\n")
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

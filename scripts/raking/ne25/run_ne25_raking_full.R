# ============================================================================
# NE25 Full Raking-Weight Pipeline (M-imputation)
# ============================================================================
#
# Single-entry orchestrator that runs the complete M=5 multi-imputation
# calibrated raking weight pipeline end-to-end:
#
#   1. Verify prerequisites (unified_moments.rds from scripts 29..30b) exist
#   2. Ensure DuckDB schema for ne25_raked_weights
#   3. Script 32: produce M harmonized feathers
#   4. Script 33: Stan optimization for each of M imputations
#   5. Script 34: insert long-format weights into DuckDB
#
# Prerequisites (run once before this script; NOT part of this orchestrator):
#   - scripts/raking/ne25/run_raking_targets_pipeline.R  (targets 01..24)
#   - scripts/raking/ne25/25_extract_acs_north_central.R
#   - scripts/raking/ne25/29_create_design_matrices.R
#   - scripts/raking/ne25/30_compute_covariance_matrices.R
#   - scripts/raking/ne25/30b_pool_moments.R
#   - scripts/imputation/ne25/run_full_imputation_pipeline.R
#   These produce data/raking/ne25/unified_moments.rds and populate the
#   ne25_imputed_* DuckDB tables that script 32 consumes.
#
# Typical runtime:
#   Step 3 (script 32): ~2 min for M=5 (MICE fallback dominates)
#   Step 4 (script 33): ~15 min for M=5 (~3 min per Stan refit, model cached)
#   Step 5 (script 34): ~10 s (DuckDB insert)
#   Total: ~17-20 min
#
# Part of NE25 Bucket 2 (multi-imputation integration). Step 5 of 7.
# See docs/archive/raking/ne25/ne25_weights_roadmap.md and WEIGHT_CONSTRUCTION.qmd section 5.1.
# ============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

source("R/utils/environment_config.R")  # for get_python_path()

cat("\n============================================================\n")
cat("  NE25 Full Raking-Weight Pipeline (M=5 multi-imputation)\n")
cat("============================================================\n\n")

overall_start <- Sys.time()

# ----------------------------------------------------------------------------
# [0] Verify prerequisites
# ----------------------------------------------------------------------------
cat("[0] Verifying prerequisites...\n")

moments_file <- "data/raking/ne25/unified_moments.rds"
if (!file.exists(moments_file)) {
  stop(sprintf(paste(
    "Prerequisite missing: %s",
    "Run the targets-pipeline + scripts 29, 30, 30b first, e.g.:",
    "  Rscript scripts/raking/ne25/run_raking_targets_pipeline.R",
    "then 25..30b in order.",
    sep = "\n"), moments_file))
}
cat(sprintf("    [OK] unified_moments.rds present (%s)\n",
            format(file.info(moments_file)$mtime, "%Y-%m-%d %H:%M")))

# ----------------------------------------------------------------------------
# [1] Ensure ne25_raked_weights table exists (idempotent)
# ----------------------------------------------------------------------------
cat("\n[1] Ensuring ne25_raked_weights DuckDB schema exists...\n")

python_path <- get_python_path()
init_status <- system2(
  python_path,
  args = c("pipelines/python/init_raked_weights_table.py"),
  stdout = TRUE,
  stderr = TRUE
)
# system2 returns status as attribute; warn on nonzero
if (!is.null(attr(init_status, "status")) && attr(init_status, "status") != 0) {
  cat(paste(init_status, collapse = "\n"), "\n")
  stop("init_raked_weights_table.py failed")
}
cat("    [OK] ne25_raked_weights table ready\n")

# ----------------------------------------------------------------------------
# [2] Stage: script 32 — harmonize for M imputations
# ----------------------------------------------------------------------------
cat("\n[2] Script 32: harmonize ne25 for M imputations...\n")
t0 <- Sys.time()
source("scripts/raking/ne25/32_prepare_ne25_for_weighting.R")
cat(sprintf("    elapsed: %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ----------------------------------------------------------------------------
# [3] Stage: script 33 — Stan calibration for M imputations
# ----------------------------------------------------------------------------
cat("\n[3] Script 33: Stan KL-divergence calibration for M imputations...\n")
t0 <- Sys.time()
source("scripts/raking/ne25/33_compute_kl_divergence_weights.R")
cat(sprintf("    elapsed: %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ----------------------------------------------------------------------------
# [4] Stage: script 34 — insert long-format weights into DuckDB
# ----------------------------------------------------------------------------
cat("\n[4] Script 34: store weights in ne25_raked_weights...\n")
t0 <- Sys.time()
source("scripts/raking/ne25/34_store_raked_weights_long.R")
cat(sprintf("    elapsed: %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ----------------------------------------------------------------------------
# [5] Final summary
# ----------------------------------------------------------------------------
overall_elapsed <- as.numeric(difftime(Sys.time(), overall_start, units = "mins"))

cat("\n============================================================\n")
cat("  NE25 Raking-Weight Pipeline Complete\n")
cat("============================================================\n\n")
cat(sprintf("  Total elapsed: %.1f min\n", overall_elapsed))
cat("  Outputs:\n")
cat("    - data/raking/ne25/ne25_harmonized/ne25_harmonized_m{1..M}.feather\n")
cat("    - data/raking/ne25/ne25_weights/ne25_calibrated_weights_m{1..M}.feather\n")
cat("    - data/raking/ne25/ne25_weights/calibration_diagnostics_m{1..M}.rds\n")
cat("    - DuckDB table: ne25_raked_weights\n\n")
cat("  Next: re-run the main NE25 pipeline (run_ne25_pipeline.R) so Step 6.9\n")
cat("        picks up the m=1 weights from ne25_raked_weights for the legacy\n")
cat("        calibrated_weight column on ne25_transformed.\n\n")

# Run Complete Bootstrap Pipeline (Production Mode: n_boot = 4096)
# Orchestrates all bootstrap scripts from Phases 2-5
# Expected: 737,280 bootstrap replicates in database

# Load environment configuration utilities
source("R/utils/environment_config.R")

# Load bootstrap configuration
source("config/bootstrap_config.R")

# Configuration (n_boot now comes from BOOTSTRAP_CONFIG)
n_boot <- BOOTSTRAP_CONFIG$n_boot
log_file <- "logs/bootstrap_pipeline_production.log"

# Get Python path from environment
python_path <- get_python_path()
cat("Python executable:", python_path, "\n")

# NOTE: Parallel processing is managed LOCALLY within bootstrap_helpers.R
# Each estimation script starts and closes workers independently to avoid corruption
# No global future::plan() configuration needed

cat("System cores detected:", parallel::detectCores(), "\n")
cat("Parallel processing: Managed locally within each script (2 workers per script)\n")

# Create logs directory if needed
if (!dir.exists("logs")) {
  dir.create("logs", recursive = TRUE)
}

# Start logging
sink(log_file, split = TRUE)

cat("\n")
cat("================================================================================\n")
cat("BOOTSTRAP PIPELINE - PRODUCTION RUN\n")
cat("================================================================================\n\n")
cat("Configuration:\n")
cat("  n_boot:", n_boot, "\n")
cat("  Mode:", ifelse(n_boot == 4, "TEST", "PRODUCTION"), "\n")
cat("  Start time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("  Log file:", log_file, "\n")
cat("  Expected database rows: 737,280\n")
cat("  Estimated runtime: 15-20 minutes\n\n")

# Track timing
start_time <- Sys.time()
phase_times <- list()

# Helper function to run script and track time
run_script <- function(script_path, phase_name) {
  cat("================================================================================\n")
  cat("PHASE:", phase_name, "\n")
  cat("Script:", script_path, "\n")
  cat("================================================================================\n\n")

  phase_start <- Sys.time()

  tryCatch({
    source(script_path)
    phase_end <- Sys.time()
    elapsed <- as.numeric(difftime(phase_end, phase_start, units = "secs"))

    cat("\n[OK]", phase_name, "completed in", round(elapsed, 2), "seconds\n\n")

    return(list(status = "SUCCESS", time = elapsed))
  }, error = function(e) {
    phase_end <- Sys.time()
    elapsed <- as.numeric(difftime(phase_end, phase_start, units = "secs"))

    cat("\n[ERROR]", phase_name, "failed after", round(elapsed, 2), "seconds\n")
    cat("Error message:", conditionMessage(e), "\n\n")

    return(list(status = "FAILED", time = elapsed, error = conditionMessage(e)))
  })
}

# Phase 2: ACS Bootstrap (25 estimands)
cat("\n")
cat("################################################################################\n")
cat("PHASE 2: ACS BOOTSTRAP (25 estimands)\n")
cat("################################################################################\n\n")

phase2_start <- Sys.time()

acs_scripts <- c(
  "scripts/raking/ne25/01a_create_acs_bootstrap_design.R",
  "scripts/raking/ne25/02_estimate_sex_glm2.R",           # GLM2 refactored
  "scripts/raking/ne25/03_estimate_race_ethnicity_glm2.R", # GLM2 refactored
  "scripts/raking/ne25/04_estimate_fpl_glm2.R",           # GLM2 refactored (multinomial)
  "scripts/raking/ne25/05_estimate_puma_glm2.R",          # GLM2 refactored (multinomial)
  "scripts/raking/ne25/06_estimate_mother_education_glm2.R", # GLM2 refactored
  "scripts/raking/ne25/07_estimate_mother_marital_status_glm2.R", # GLM2 refactored
  "scripts/raking/ne25/21a_consolidate_acs_bootstrap.R"
)

phase2_results <- list()
for (script in acs_scripts) {
  script_name <- basename(script)
  phase2_results[[script_name]] <- run_script(script, paste("ACS -", script_name))
}

phase2_end <- Sys.time()
phase2_elapsed <- as.numeric(difftime(phase2_end, phase2_start, units = "secs"))
phase_times[["Phase 2: ACS Bootstrap"]] <- phase2_elapsed

# Check Phase 2 output
if (file.exists("data/raking/ne25/acs_bootstrap_consolidated.rds")) {
  acs_boot <- readRDS("data/raking/ne25/acs_bootstrap_consolidated.rds")
  cat("\n[VERIFY] ACS bootstrap file exists:", nrow(acs_boot), "rows (expected: 600)\n")
  if (nrow(acs_boot) == 600) {
    cat("[OK] ACS row count correct\n")
  } else {
    cat("[ERROR] ACS row count mismatch!\n")
  }
} else {
  cat("\n[ERROR] ACS bootstrap file not found!\n")
}

# Phase 3: NHIS Bootstrap (1 estimand)
cat("\n")
cat("################################################################################\n")
cat("PHASE 3: NHIS BOOTSTRAP (1 estimand)\n")
cat("################################################################################\n\n")

phase3_start <- Sys.time()

nhis_scripts <- c(
  "scripts/raking/ne25/12a_create_nhis_bootstrap_design.R",
  "scripts/raking/ne25/13_estimate_phq2_glm2.R"  # GLM2 refactored
)

phase3_results <- list()
for (script in nhis_scripts) {
  script_name <- basename(script)
  phase3_results[[script_name]] <- run_script(script, paste("NHIS -", script_name))
}

phase3_end <- Sys.time()
phase3_elapsed <- as.numeric(difftime(phase3_end, phase3_start, units = "secs"))
phase_times[["Phase 3: NHIS Bootstrap"]] <- phase3_elapsed

# Check Phase 3 output
if (file.exists("data/raking/ne25/phq2_estimate_boot.rds")) {
  nhis_boot <- readRDS("data/raking/ne25/phq2_estimate_boot.rds")
  cat("\n[VERIFY] NHIS bootstrap file exists:", nrow(nhis_boot), "rows (expected: 24)\n")
  if (nrow(nhis_boot) == 24) {
    cat("[OK] NHIS row count correct\n")
  } else {
    cat("[ERROR] NHIS row count mismatch!\n")
  }
} else {
  cat("\n[ERROR] NHIS bootstrap file not found!\n")
}

# Phase 4: NSCH Bootstrap (4 estimands)
cat("\n")
cat("################################################################################\n")
cat("PHASE 4: NSCH BOOTSTRAP (4 estimands)\n")
cat("################################################################################\n\n")

phase4_start <- Sys.time()

nsch_scripts <- c(
  "scripts/raking/ne25/17a_create_nsch_bootstrap_design.R",
  "scripts/raking/ne25/18_estimate_nsch_outcomes_glm2.R",  # GLM2 refactored
  "scripts/raking/ne25/20_estimate_childcare_2022.R",
  "scripts/raking/ne25/21b_consolidate_nsch_boot.R"
)

phase4_results <- list()
for (script in nsch_scripts) {
  script_name <- basename(script)
  phase4_results[[script_name]] <- run_script(script, paste("NSCH -", script_name))
}

phase4_end <- Sys.time()
phase4_elapsed <- as.numeric(difftime(phase4_end, phase4_start, units = "secs"))
phase_times[["Phase 4: NSCH Bootstrap"]] <- phase4_elapsed

# Check Phase 4 output
if (file.exists("data/raking/ne25/nsch_bootstrap_consolidated.rds")) {
  nsch_boot <- readRDS("data/raking/ne25/nsch_bootstrap_consolidated.rds")
  cat("\n[VERIFY] NSCH bootstrap file exists:", nrow(nsch_boot), "rows (expected: 96)\n")
  if (nrow(nsch_boot) == 96) {
    cat("[OK] NSCH row count correct\n")
  } else {
    cat("[ERROR] NSCH row count mismatch!\n")
  }
} else {
  cat("\n[ERROR] NSCH bootstrap file not found!\n")
}

# Phase 5: Cross-source consolidation and database insertion
cat("\n")
cat("################################################################################\n")
cat("PHASE 5: DATABASE INTEGRATION\n")
cat("################################################################################\n\n")

phase5_start <- Sys.time()

# Step 1: Consolidate all sources
phase5_results <- list()
phase5_results[["22_consolidate"]] <- run_script(
  "scripts/raking/ne25/22_consolidate_all_boot_replicates.R",
  "Consolidate All Sources"
)

# Check consolidated file
if (file.exists("data/raking/ne25/all_bootstrap_replicates.rds")) {
  all_boot <- readRDS("data/raking/ne25/all_bootstrap_replicates.rds")
  cat("\n[VERIFY] Consolidated bootstrap file exists:", nrow(all_boot), "rows (expected: 720)\n")
  if (nrow(all_boot) == 720) {
    cat("[OK] Consolidated row count correct\n")
  } else {
    cat("[ERROR] Consolidated row count mismatch!\n")
  }
} else {
  cat("\n[ERROR] Consolidated bootstrap file not found!\n")
}

# Step 2: Insert into database (Python script)
cat("\n")
cat("================================================================================\n")
cat("PHASE: Database Insertion (Python)\n")
cat("Script: scripts/raking/ne25/23_insert_boot_replicates.py\n")
cat("================================================================================\n\n")

db_insert_start <- Sys.time()

# Run Python script (using environment-configured path)
python_result <- system2(
  command = python_path,
  args = "scripts/raking/ne25/23_insert_boot_replicates.py",
  stdout = TRUE,
  stderr = TRUE
)

db_insert_end <- Sys.time()
db_insert_elapsed <- as.numeric(difftime(db_insert_end, db_insert_start, units = "secs"))

# Print Python output
cat(paste(python_result, collapse = "\n"))
cat("\n\n[OK] Database insertion completed in", round(db_insert_elapsed, 2), "seconds\n\n")

phase5_end <- Sys.time()
phase5_elapsed <- as.numeric(difftime(phase5_end, phase5_start, units = "secs"))
phase_times[["Phase 5: Database Integration"]] <- phase5_elapsed

# Final Summary
end_time <- Sys.time()
total_elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat("\n")
cat("================================================================================\n")
cat("BOOTSTRAP PIPELINE SUMMARY\n")
cat("================================================================================\n\n")

cat("Phase Timings:\n")
for (phase_name in names(phase_times)) {
  cat(sprintf("  %-35s: %6.2f seconds (%5.1f%%)\n",
              phase_name,
              phase_times[[phase_name]],
              100 * phase_times[[phase_name]] / total_elapsed))
}

cat("\nTotal Execution Time:", round(total_elapsed, 2), "seconds (", round(total_elapsed / 60, 1), "minutes)\n\n")

# Check for any failures
all_results <- c(phase2_results, phase3_results, phase4_results, phase5_results)
failed_scripts <- sapply(all_results, function(x) x$status == "FAILED")

if (any(failed_scripts)) {
  cat("\n[ERROR] Some scripts failed:\n")
  for (script_name in names(all_results)[failed_scripts]) {
    cat("  -", script_name, "\n")
    cat("    Error:", all_results[[script_name]]$error, "\n")
  }
  cat("\nPipeline completed with ERRORS\n\n")
} else {
  cat("[SUCCESS] All scripts executed successfully\n\n")
}

# Final verification
cat("Final Verification:\n")

# Check database
library(duckdb)
con <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")

tryCatch({
  db_count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM raking_targets_boot_replicates")
  cat("  Database rows:", db_count$n, "(expected: 720)\n")

  if (db_count$n == 720) {
    cat("  [OK] Database row count correct\n")
  } else {
    cat("  [ERROR] Database row count mismatch!\n")
  }

  # Check by source
  source_counts <- DBI::dbGetQuery(con, "
    SELECT data_source, COUNT(*) as n
    FROM raking_targets_boot_replicates
    GROUP BY data_source
    ORDER BY data_source
  ")

  cat("\n  Rows by data source:\n")
  for (i in 1:nrow(source_counts)) {
    expected <- c(ACS = 600, NHIS = 24, NSCH = 96)
    actual <- source_counts$n[i]
    source <- source_counts$data_source[i]
    status <- if (actual == expected[source]) "[OK]" else "[ERROR]"
    cat(sprintf("    %s %-5s: %3d (expected: %3d)\n", status, source, actual, expected[source]))
  }

}, error = function(e) {
  cat("  [ERROR] Could not query database:", conditionMessage(e), "\n")
})

DBI::dbDisconnect(con, shutdown = TRUE)

cat("\n")
cat("================================================================================\n")
cat("END OF PIPELINE\n")
cat("================================================================================\n")
cat("End time:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Log saved to:", log_file, "\n\n")

if (!any(failed_scripts) && db_count$n == 720) {
  cat("[SUCCESS] Bootstrap pipeline test mode completed successfully!\n")
  cat("Next step: Review results, then change n_boot to 4096 for production run\n\n")
} else {
  cat("[FAILED] Bootstrap pipeline encountered errors. Review log for details.\n\n")
}

# Stop logging
sink()

# Return summary invisibly
invisible(list(
  total_time = total_elapsed,
  phase_times = phase_times,
  all_results = all_results,
  success = !any(failed_scripts) && db_count$n == 720
))

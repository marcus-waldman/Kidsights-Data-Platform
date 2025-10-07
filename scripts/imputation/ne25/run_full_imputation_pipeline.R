# Unified Imputation Pipeline Orchestrator
#
# Runs the complete imputation workflow:
#   Stage 1: Geographic imputation (PUMA, County, Census Tract)
#   Stage 2: Sociodemographic imputation (Sex, Race, Education, Income, Family Size)
#
# Usage:
#   Rscript scripts/imputation/run_full_imputation_pipeline.R

# =============================================================================
# SETUP
# =============================================================================

cat("KIDSIGHTS IMPUTATION PIPELINE - UNIFIED ORCHESTRATOR\n")
cat(strrep("=", 60), "\n")

# Load required packages
if (!requireNamespace("reticulate", quietly = TRUE)) {
  stop("Package 'reticulate' is required. Install with: install.packages('reticulate')")
}

# Source configuration
source("R/imputation/config.R")

# Load study-specific configuration
study_id <- "ne25"
study_config <- get_study_config(study_id)
config <- get_imputation_config()

cat("\nPipeline Configuration:\n")
cat("  Study ID:", study_id, "\n")
cat("  Study Name:", study_config$study_name, "\n")
cat("  Number of imputations (M):", config$n_imputations, "\n")
cat("  Random seed:", config$random_seed, "\n")
cat("  Database:", config$database$db_path, "\n")
cat("  Scripts directory:", study_config$scripts_dir, "\n")
cat("  Data directory:", study_config$data_dir, "\n")

cat("\n  Geography variables:", paste(config$geography$variables, collapse = ", "), "\n")
cat("  Sociodem variables:", paste(config$sociodemographic$variables, collapse = ", "), "\n")

# =============================================================================
# STAGE 1: GEOGRAPHIC IMPUTATION (Python)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 1: Geographic Imputation (PUMA, County, Census Tract)\n")
cat(strrep("=", 60), "\n")

start_time_geo <- Sys.time()

geography_script <- file.path(study_config$scripts_dir, "01_impute_geography.py")
cat("\n[INFO] Launching Python script:", geography_script, "\n")

tryCatch({
  reticulate::py_run_file(geography_script)
  cat("\n[OK] Geographic imputation complete\n")
}, error = function(e) {
  cat("\n[ERROR] Geographic imputation failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to geographic imputation failure")
})

end_time_geo <- Sys.time()
elapsed_geo <- as.numeric(difftime(end_time_geo, start_time_geo, units = "secs"))
cat(sprintf("\nStage 1 completed in %.1f seconds\n", elapsed_geo))

# =============================================================================
# STAGE 2: SOCIODEMOGRAPHIC IMPUTATION (R)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 2: Sociodemographic Imputation (Sex, Race, Education, Income, Family Size)\n")
cat(strrep("=", 60), "\n")

start_time_sociodem <- Sys.time()

sociodem_script <- file.path(study_config$scripts_dir, "02_impute_sociodemographic.R")
cat("\n[INFO] Launching R script:", sociodem_script, "\n")

tryCatch({
  source(sociodem_script)
  cat("\n[OK] Sociodemographic imputation complete\n")
}, error = function(e) {
  cat("\n[ERROR] Sociodemographic imputation failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to sociodemographic imputation failure")
})

end_time_sociodem <- Sys.time()
elapsed_sociodem <- as.numeric(difftime(end_time_sociodem, start_time_sociodem, units = "secs"))
cat(sprintf("\nStage 2 completed in %.1f seconds\n", elapsed_sociodem))

# =============================================================================
# STAGE 3: DATABASE INSERTION (Python)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 3: Insert Sociodemographic Imputations into Database\n")
cat(strrep("=", 60), "\n")

start_time_insert <- Sys.time()

insert_script <- file.path(study_config$scripts_dir, "02b_insert_sociodem_imputations.py")
cat("\n[INFO] Launching Python script:", insert_script, "\n")

tryCatch({
  reticulate::py_run_file(insert_script)
  cat("\n[OK] Database insertion complete\n")
}, error = function(e) {
  cat("\n[ERROR] Database insertion failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to database insertion failure")
})

end_time_insert <- Sys.time()
elapsed_insert <- as.numeric(difftime(end_time_insert, start_time_insert, units = "secs"))
cat(sprintf("\nStage 3 completed in %.1f seconds\n", elapsed_insert))

# =============================================================================
# FINAL SUMMARY
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("PIPELINE COMPLETE - All Imputations Stored in Database\n")
cat(strrep("=", 60), "\n")

total_elapsed <- elapsed_geo + elapsed_sociodem + elapsed_insert

cat("\nExecution Time Summary:\n")
cat(sprintf("  Stage 1 (Geography):        %6.1f seconds\n", elapsed_geo))
cat(sprintf("  Stage 2 (Sociodemographic): %6.1f seconds\n", elapsed_sociodem))
cat(sprintf("  Stage 3 (Database Insert):  %6.1f seconds\n", elapsed_insert))
cat(sprintf("  Total:                      %6.1f seconds (%.1f minutes)\n",
            total_elapsed, total_elapsed / 60))

cat("\nImputation Results:\n")
cat(sprintf("  Number of imputations (M): %d\n", config$n_imputations))
cat(sprintf("  Geography variables: %d (%s)\n",
            length(config$geography$variables),
            paste(config$geography$variables, collapse = ", ")))
cat(sprintf("  Sociodem variables: %d (%s)\n",
            length(config$sociodemographic$variables),
            paste(config$sociodemographic$variables, collapse = ", ")))
cat(sprintf("  Total imputed variables: %d\n",
            length(config$geography$variables) + length(config$sociodemographic$variables)))

table_prefix <- study_config$table_prefix

cat("\nDatabase Tables Updated:\n")
cat(sprintf("  Geographic: %s_puma, %s_county, %s_census_tract\n", table_prefix, table_prefix, table_prefix))
cat(sprintf("  Sociodem: %s_female, %s_raceG, %s_educ_mom, %s_educ_a2,\n", table_prefix, table_prefix, table_prefix, table_prefix))
cat(sprintf("            %s_income, %s_family_size, %s_fplcat\n", table_prefix, table_prefix, table_prefix))

cat("\nNext Steps:\n")
cat("  1. Validate: python -m python.imputation.helpers\n")
cat("  2. Query completed datasets:\n")
cat("     from python.imputation.helpers import get_completed_dataset\n")
cat(sprintf("     df = get_completed_dataset(m=1, variables=['female', 'raceG', 'puma'], study_id='%s')\n", study_id))
cat("  3. Run analysis with multiply imputed data\n")

cat("\n", strrep("=", 60), "\n")

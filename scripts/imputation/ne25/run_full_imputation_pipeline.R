# Unified Imputation Pipeline Orchestrator
#
# Runs the complete imputation workflow:
#   Stage 1: Geographic imputation (PUMA, County, Census Tract)
#   Stage 2: Sociodemographic imputation (Sex, Race, Education, Income, Family Size)
#   Stage 3: Childcare imputation (3 sub-stages)
#     3a: cc_receives_care (Boolean imputation)
#     3b: cc_primary_type + cc_hours_per_week (Conditional imputation)
#     3c: childcare_10hrs_nonfamily (Derived outcome)
#   Stage 4: Adult Mental Health & Parenting imputation (PHQ-2, GAD-2, q1502)
#
# Usage:
#   Rscript scripts/imputation/ne25/run_full_imputation_pipeline.R

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
source("R/utils/environment_config.R")
source("R/imputation/config.R")

# Configure reticulate to use .env Python executable
python_path <- get_python_path()
cat("\nPython Configuration:\n")
cat("  Python executable:", python_path, "\n")
reticulate::use_python(python_path, required = TRUE)

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
cat("  Childcare variables: cc_receives_care, cc_primary_type, cc_hours_per_week, childcare_10hrs_nonfamily\n")
cat("  Mental health variables: phq2_interest, phq2_depressed, gad2_nervous, gad2_worry, q1502, phq2_positive, gad2_positive\n")

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
# STAGE 4: CHILDCARE IMPUTATION - Stage 1 (R)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 4: Childcare Imputation - Stage 1 (cc_receives_care)\n")
cat(strrep("=", 60), "\n")

start_time_cc1 <- Sys.time()

cc1_script <- file.path(study_config$scripts_dir, "03a_impute_cc_receives_care.R")
cat("\n[INFO] Launching R script:", cc1_script, "\n")

tryCatch({
  source(cc1_script)
  cat("\n[OK] Childcare Stage 1 imputation complete\n")
}, error = function(e) {
  cat("\n[ERROR] Childcare Stage 1 imputation failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to childcare Stage 1 imputation failure")
})

end_time_cc1 <- Sys.time()
elapsed_cc1 <- as.numeric(difftime(end_time_cc1, start_time_cc1, units = "secs"))
cat(sprintf("\nStage 4 completed in %.1f seconds\n", elapsed_cc1))

# =============================================================================
# STAGE 5: CHILDCARE IMPUTATION - Stage 2 (R)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 5: Childcare Imputation - Stage 2 (cc_primary_type + cc_hours_per_week)\n")
cat(strrep("=", 60), "\n")

start_time_cc2 <- Sys.time()

cc2_script <- file.path(study_config$scripts_dir, "03b_impute_cc_type_hours.R")
cat("\n[INFO] Launching R script:", cc2_script, "\n")

tryCatch({
  source(cc2_script)
  cat("\n[OK] Childcare Stage 2 imputation complete\n")
}, error = function(e) {
  cat("\n[ERROR] Childcare Stage 2 imputation failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to childcare Stage 2 imputation failure")
})

end_time_cc2 <- Sys.time()
elapsed_cc2 <- as.numeric(difftime(end_time_cc2, start_time_cc2, units = "secs"))
cat(sprintf("\nStage 5 completed in %.1f seconds\n", elapsed_cc2))

# =============================================================================
# STAGE 6: CHILDCARE IMPUTATION - Stage 3 (R)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 6: Childcare Imputation - Stage 3 (childcare_10hrs_nonfamily derived)\n")
cat(strrep("=", 60), "\n")

start_time_cc3 <- Sys.time()

cc3_script <- file.path(study_config$scripts_dir, "03c_derive_childcare_10hrs.R")
cat("\n[INFO] Launching R script:", cc3_script, "\n")

tryCatch({
  source(cc3_script)
  cat("\n[OK] Childcare Stage 3 derivation complete\n")
}, error = function(e) {
  cat("\n[ERROR] Childcare Stage 3 derivation failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to childcare Stage 3 derivation failure")
})

end_time_cc3 <- Sys.time()
elapsed_cc3 <- as.numeric(difftime(end_time_cc3, start_time_cc3, units = "secs"))
cat(sprintf("\nStage 6 completed in %.1f seconds\n", elapsed_cc3))

# =============================================================================
# STAGE 7: INSERT CHILDCARE IMPUTATIONS (Python)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 7: Insert Childcare Imputations into Database\n")
cat(strrep("=", 60), "\n")

start_time_cc_insert <- Sys.time()

cc_insert_script <- file.path(study_config$scripts_dir, "04_insert_childcare_imputations.py")
cat("\n[INFO] Launching Python script:", cc_insert_script, "\n")

tryCatch({
  reticulate::py_run_file(cc_insert_script)
  cat("\n[OK] Childcare database insertion complete\n")
}, error = function(e) {
  cat("\n[ERROR] Childcare database insertion failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to childcare database insertion failure")
})

end_time_cc_insert <- Sys.time()
elapsed_cc_insert <- as.numeric(difftime(end_time_cc_insert, start_time_cc_insert, units = "secs"))
cat(sprintf("\nStage 7 completed in %.1f seconds\n", elapsed_cc_insert))

# =============================================================================
# STAGE 8: ADULT MENTAL HEALTH & PARENTING IMPUTATION (R)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 8: Adult Mental Health & Parenting (PHQ-2, GAD-2, q1502)\n")
cat(strrep("=", 60), "\n")

start_time_mh <- Sys.time()

mh_script <- file.path(study_config$scripts_dir, "05_impute_adult_mental_health.R")
cat("\n[INFO] Launching R script:", mh_script, "\n")

tryCatch({
  source(mh_script)
  cat("\n[OK] Adult mental health & parenting imputation complete\n")
}, error = function(e) {
  cat("\n[ERROR] Adult mental health & parenting imputation failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to mental health imputation failure")
})

end_time_mh <- Sys.time()
elapsed_mh <- as.numeric(difftime(end_time_mh, start_time_mh, units = "secs"))
cat(sprintf("\nStage 8 completed in %.1f seconds\n", elapsed_mh))

# =============================================================================
# STAGE 9: INSERT MENTAL HEALTH IMPUTATIONS (Python)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 9: Insert Mental Health & Parenting Imputations into Database\n")
cat(strrep("=", 60), "\n")

start_time_mh_insert <- Sys.time()

mh_insert_script <- file.path(study_config$scripts_dir, "05b_insert_mental_health_imputations.py")
cat("\n[INFO] Launching Python script:", mh_insert_script, "\n")

tryCatch({
  reticulate::py_run_file(mh_insert_script)
  cat("\n[OK] Mental health & parenting database insertion complete\n")
}, error = function(e) {
  cat("\n[ERROR] Mental health & parenting database insertion failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to mental health database insertion failure")
})

end_time_mh_insert <- Sys.time()
elapsed_mh_insert <- as.numeric(difftime(end_time_mh_insert, start_time_mh_insert, units = "secs"))
cat(sprintf("\nStage 9 completed in %.1f seconds\n", elapsed_mh_insert))

# =============================================================================
# STAGE 10: CHILD ACES IMPUTATION (R)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 10: Child ACEs Imputation (8 items + total)\n")
cat(strrep("=", 60), "\n")

start_time_ca <- Sys.time()

ca_script <- file.path(study_config$scripts_dir, "06_impute_child_aces.R")
cat("\n[INFO] Launching R script:", ca_script, "\n")

tryCatch({
  source(ca_script)
  cat("\n[OK] Child ACEs imputation complete\n")
}, error = function(e) {
  cat("\n[ERROR] Child ACEs imputation failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to child ACEs imputation failure")
})

end_time_ca <- Sys.time()
elapsed_ca <- as.numeric(difftime(end_time_ca, start_time_ca, units = "secs"))
cat(sprintf("\nStage 10 completed in %.1f seconds\n", elapsed_ca))

# =============================================================================
# STAGE 11: INSERT CHILD ACES IMPUTATIONS (Python)
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("STAGE 11: Insert Child ACEs Imputations into Database\n")
cat(strrep("=", 60), "\n")

start_time_ca_insert <- Sys.time()

ca_insert_script <- file.path(study_config$scripts_dir, "06b_insert_child_aces.py")
cat("\n[INFO] Launching Python script:", ca_insert_script, "\n")

tryCatch({
  reticulate::py_run_file(ca_insert_script)
  cat("\n[OK] Child ACEs database insertion complete\n")
}, error = function(e) {
  cat("\n[ERROR] Child ACEs database insertion failed:\n")
  cat("  ", e$message, "\n")
  stop("Pipeline halted due to child ACEs database insertion failure")
})

end_time_ca_insert <- Sys.time()
elapsed_ca_insert <- as.numeric(difftime(end_time_ca_insert, start_time_ca_insert, units = "secs"))
cat(sprintf("\nStage 11 completed in %.1f seconds\n", elapsed_ca_insert))

# =============================================================================
# FINAL SUMMARY
# =============================================================================

cat("\n", strrep("=", 60), "\n")
cat("PIPELINE COMPLETE - All Imputations Stored in Database\n")
cat(strrep("=", 60), "\n")

total_elapsed <- elapsed_geo + elapsed_sociodem + elapsed_insert +
                 elapsed_cc1 + elapsed_cc2 + elapsed_cc3 + elapsed_cc_insert +
                 elapsed_mh + elapsed_mh_insert +
                 elapsed_ca + elapsed_ca_insert

cat("\nExecution Time Summary:\n")
cat(sprintf("  Stage 1 (Geography):                  %6.1f seconds\n", elapsed_geo))
cat(sprintf("  Stage 2 (Sociodemographic):           %6.1f seconds\n", elapsed_sociodem))
cat(sprintf("  Stage 3 (Sociodem DB Insert):         %6.1f seconds\n", elapsed_insert))
cat(sprintf("  Stage 4 (Childcare - Receives Care):  %6.1f seconds\n", elapsed_cc1))
cat(sprintf("  Stage 5 (Childcare - Type + Hours):   %6.1f seconds\n", elapsed_cc2))
cat(sprintf("  Stage 6 (Childcare - Derived):        %6.1f seconds\n", elapsed_cc3))
cat(sprintf("  Stage 7 (Childcare DB Insert):        %6.1f seconds\n", elapsed_cc_insert))
cat(sprintf("  Stage 8 (Mental Health & Parenting):  %6.1f seconds\n", elapsed_mh))
cat(sprintf("  Stage 9 (Mental Health DB Insert):    %6.1f seconds\n", elapsed_mh_insert))
cat(sprintf("  Stage 10 (Child ACEs):                %6.1f seconds\n", elapsed_ca))
cat(sprintf("  Stage 11 (Child ACEs DB Insert):      %6.1f seconds\n", elapsed_ca_insert))
cat(sprintf("  Total:                                %6.1f seconds (%.1f minutes)\n",
            total_elapsed, total_elapsed / 60))

cat("\nImputation Results:\n")
cat(sprintf("  Number of imputations (M): %d\n", config$n_imputations))
cat(sprintf("  Geography variables: %d (%s)\n",
            length(config$geography$variables),
            paste(config$geography$variables, collapse = ", ")))
cat(sprintf("  Sociodem variables: %d (%s)\n",
            length(config$sociodemographic$variables),
            paste(config$sociodemographic$variables, collapse = ", ")))
cat(sprintf("  Childcare variables: 4 (cc_receives_care, cc_primary_type, cc_hours_per_week, childcare_10hrs_nonfamily)\n"))
cat(sprintf("  Mental health variables: 7 (phq2_interest, phq2_depressed, gad2_nervous, gad2_worry, q1502, phq2_positive, gad2_positive)\n"))
cat(sprintf("  Child ACEs variables: 9 (8 ACE items + child_ace_total)\n"))
cat(sprintf("  Total imputed variables: %d\n",
            length(config$geography$variables) + length(config$sociodemographic$variables) + 4 + 7 + 9))

table_prefix <- study_config$table_prefix

cat("\nDatabase Tables Updated:\n")
cat(sprintf("  Geographic: %s_puma, %s_county, %s_census_tract\n", table_prefix, table_prefix, table_prefix))
cat(sprintf("  Sociodem: %s_female, %s_raceG, %s_educ_mom, %s_educ_a2,\n", table_prefix, table_prefix, table_prefix, table_prefix))
cat(sprintf("            %s_income, %s_family_size, %s_fplcat\n", table_prefix, table_prefix, table_prefix))
cat(sprintf("  Childcare: %s_cc_receives_care, %s_cc_primary_type,\n", table_prefix, table_prefix))
cat(sprintf("             %s_cc_hours_per_week, %s_childcare_10hrs_nonfamily\n", table_prefix, table_prefix))
cat(sprintf("  Mental Health: %s_phq2_interest, %s_phq2_depressed,\n", table_prefix, table_prefix))
cat(sprintf("                 %s_gad2_nervous, %s_gad2_worry, %s_q1502,\n", table_prefix, table_prefix, table_prefix))
cat(sprintf("                 %s_phq2_positive, %s_gad2_positive\n", table_prefix, table_prefix))
cat(sprintf("  Child ACEs: %s_child_ace_parent_divorce, %s_child_ace_parent_death,\n", table_prefix, table_prefix))
cat(sprintf("              %s_child_ace_parent_jail, %s_child_ace_domestic_violence,\n", table_prefix, table_prefix))
cat(sprintf("              %s_child_ace_neighborhood_violence, %s_child_ace_mental_illness,\n", table_prefix, table_prefix))
cat(sprintf("              %s_child_ace_substance_use, %s_child_ace_discrimination,\n", table_prefix, table_prefix))
cat(sprintf("              %s_child_ace_total\n", table_prefix))

cat("\nNext Steps:\n")
cat("  1. Validate: python -m python.imputation.helpers\n")
cat("  2. Query completed datasets:\n")
cat("     from python.imputation.helpers import get_complete_dataset\n")
cat(sprintf("     df = get_complete_dataset(study_id='%s', imputation_number=1)  # All 30 variables\n", study_id))
cat("  3. Query mental health imputations:\n")
cat("     from python.imputation.helpers import get_mental_health_imputations\n")
cat(sprintf("     mh = get_mental_health_imputations(study_id='%s', imputation_number=1)\n", study_id))
cat("  4. Query child ACEs imputations:\n")
cat("     from python.imputation.helpers import get_child_aces_imputations\n")
cat(sprintf("     aces = get_child_aces_imputations(study_id='%s', imputation_number=1)\n", study_id))
cat("  5. Run analysis with multiply imputed data (all 30 variables)\n")

cat("\n", strrep("=", 60), "\n")

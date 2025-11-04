# =============================================================================
# IRT Scoring Script: Kidsights Developmental Scale
# =============================================================================
# Purpose: Calculate MAP scores for Kidsights unidimensional developmental scale
#          using latent regression with standard covariates + log(age+1) term
#
# Model: Unidimensional GRM (203 items, NE22 calibration)
# Method: MAP estimation with latent regression
# Output: Feather files (one per imputation m) → Python inserts to DuckDB
#
# Execution: Called by run_irt_scoring_pipeline.R or standalone
# Runtime: ~X minutes (to be determined after testing)
#
# Version: 1.0
# Created: January 4, 2025
# =============================================================================

cat("\n")
cat(strrep("=", 70), "\n")
cat("KIDSIGHTS DEVELOPMENTAL SCALE - IRT SCORING\n")
cat(strrep("=", 70), "\n")
cat(sprintf("Start time: %s\n", Sys.time()))
cat("\n")

# =============================================================================
# SETUP
# =============================================================================

# Load required packages with explicit namespacing
library(yaml)           # Configuration loading
library(jsonlite)       # Codebook JSON parsing
library(duckdb)         # Database connection
library(arrow)          # Feather file I/O
library(dplyr)          # Data manipulation (all calls use dplyr::)
# library(IRTScoring)   # MAP estimation - loaded conditionally

# Source helper functions
cat("Loading helper functions...\n")
source("scripts/irt_scoring/helpers/covariate_preparation.R")
source("scripts/irt_scoring/helpers/map_scoring.R")
cat("[OK] Helper functions loaded\n\n")

# =============================================================================
# LOAD CONFIGURATION
# =============================================================================

cat(strrep("-", 70), "\n")
cat("STEP 1: LOAD CONFIGURATION\n")
cat(strrep("-", 70), "\n\n")

config_path <- "config/irt_scoring/irt_scoring_config.yaml"
if (!file.exists(config_path)) {
  stop(sprintf("Configuration file not found: %s", config_path))
}

config <- yaml::read_yaml(config_path)
cat(sprintf("[OK] Configuration loaded: %s\n", config_path))

# Extract Kidsights configuration
kidsights_config <- config$scales$kidsights

if (!kidsights_config$enabled) {
  stop("Kidsights scale is not enabled in configuration")
}

cat(sprintf("  Scale: %s\n", kidsights_config$description))
cat(sprintf("  Model type: %s\n", kidsights_config$model_type))
cat(sprintf("  Calibration study: %s\n", kidsights_config$calibration_study))
cat(sprintf("  Developmental scale: %s\n", kidsights_config$developmental_scale))
cat(sprintf("  Scoring method: %s\n", kidsights_config$scoring_method))
cat("\n")

# =============================================================================
# LOAD IRT PARAMETERS FROM CODEBOOK
# =============================================================================

cat(strrep("-", 70), "\n")
cat("STEP 2: LOAD IRT PARAMETERS\n")
cat(strrep("-", 70), "\n")

irt_params <- load_irt_parameters_from_codebook(
  codebook_path = config$data_sources$codebook_path,
  scale_config = kidsights_config
)

cat(sprintf("[OK] Loaded IRT parameters for %d items\n", length(irt_params$item_names)))
cat("\n")

# =============================================================================
# CONNECT TO DATABASE
# =============================================================================

cat(strrep("-", 70), "\n")
cat("STEP 3: CONNECT TO DATABASE\n")
cat(strrep("-", 70), "\n\n")

db_path <- config$data_sources$database_path
if (!file.exists(db_path)) {
  stop(sprintf("Database not found: %s", db_path))
}

con <- duckdb::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
cat(sprintf("[OK] Connected to database: %s\n\n", db_path))

# =============================================================================
# LOOP THROUGH IMPUTATIONS
# =============================================================================

cat(strrep("=", 70), "\n")
cat("STEP 4: SCORE ACROSS IMPUTATIONS\n")
cat(strrep("=", 70), "\n\n")

n_imputations <- config$n_imputations
study_id <- config$study_id

cat(sprintf("Study ID: %s\n", study_id))
cat(sprintf("Number of imputations: %d\n\n", n_imputations))

# Create temp directory for output Feather files
temp_output_dir <- file.path(tempdir(), "kidsights_scores")
dir.create(temp_output_dir, showWarnings = FALSE, recursive = TRUE)
cat(sprintf("Output directory: %s\n\n", temp_output_dir))

# Store results
all_scores <- list()

for (m in 1:n_imputations) {

  cat(strrep("=", 70), "\n")
  cat(sprintf("IMPUTATION %d of %d\n", m, n_imputations))
  cat(strrep("=", 70), "\n\n")

  start_time_m <- Sys.time()

  # ---------------------------------------------------------------------------
  # Load completed dataset for this imputation
  # ---------------------------------------------------------------------------

  cat(sprintf("Loading completed dataset for imputation m=%d...\n", m))

  # TODO: Replace with actual imputation helper function when available
  # For now, using direct database query with LEFT JOIN + COALESCE pattern

  # Get base data
  base_query <- sprintf("SELECT * FROM %s_transformed WHERE eligible = TRUE", study_id)
  base_data <- duckdb::dbGetQuery(con, base_query)

  cat(sprintf("  Base data: %d records\n", nrow(base_data)))

  # Get imputed variables for this m
  # (Assuming get_completed_dataset() helper function exists)
  # This would join imputation tables and COALESCE imputed with observed values

  # Placeholder: For MVP, assume all needed variables are in base_data
  # In production, would call:
  # data_m <- get_completed_dataset(imputation_m = m, study_id = study_id)

  data_m <- base_data
  cat(sprintf("  Completed dataset: %d records, %d columns\n",
              nrow(data_m), ncol(data_m)))
  cat("\n")

  # ---------------------------------------------------------------------------
  # Prepare covariates
  # ---------------------------------------------------------------------------

  cat("Preparing covariates...\n")
  cov_result <- get_standard_covariates(
    data = data_m,
    config = config,
    scale_name = "kidsights"
  )

  data_with_covs <- cov_result$data
  formula_terms <- cov_result$formula_terms

  # ---------------------------------------------------------------------------
  # Prepare item responses
  # ---------------------------------------------------------------------------

  cat("Preparing item responses...\n")
  item_responses <- prepare_item_responses(
    data = data_with_covs,
    item_names = irt_params$item_names,
    scale_config = kidsights_config
  )

  # ---------------------------------------------------------------------------
  # Call MAP scoring
  # ---------------------------------------------------------------------------

  cat("Calling MAP estimation...\n")

  tryCatch({
    scores_m <- score_unidimensional_map(
      item_responses = item_responses,
      irt_params = irt_params,
      covariates = data_with_covs,
      formula_terms = formula_terms
    )

    # Add metadata columns
    scores_m$study_id <- study_id
    scores_m$pid <- data_with_covs$pid
    scores_m$record_id <- data_with_covs$record_id
    scores_m$imputation_m <- m

    # Reorder columns
    scores_m <- scores_m %>%
      dplyr::select(study_id, pid, record_id, imputation_m,
                    theta_kidsights, se_kidsights)

    cat(sprintf("[OK] Scored %d records for imputation m=%d\n", nrow(scores_m), m))

    # Store results
    all_scores[[m]] <- scores_m

    # Write to Feather file
    output_file <- file.path(temp_output_dir, sprintf("kidsights_scores_m%d.feather", m))
    arrow::write_feather(scores_m, output_file)
    cat(sprintf("[OK] Wrote scores to: %s\n", output_file))

  }, error = function(e) {
    cat(sprintf("\n[ERROR] Scoring failed for imputation m=%d:\n", m))
    cat(sprintf("  %s\n\n", e$message))

    # Check if error is due to missing IRTScoring function
    if (grepl("not found in IRTScoring", e$message)) {
      cat(strrep("-", 70), "\n")
      cat("MISSING IRTSCORING FEATURE DETECTED\n")
      cat(strrep("-", 70), "\n\n")
      cat("The required IRTScoring function is not available.\n")
      cat("Would you like to:\n")
      cat("  1. Generate a GitHub issue draft for this feature request\n")
      cat("  2. Continue with manual implementation\n")
      cat("  3. Exit and install/update IRTScoring package\n\n")
      cat("For now, halting pipeline.\n")
      cat("Run with IRTScoring package installed to complete scoring.\n\n")
    }

    # Disconnect and stop
    duckdb::dbDisconnect(con, shutdown = TRUE)
    stop("Pipeline halted due to scoring error")
  })

  end_time_m <- Sys.time()
  elapsed_m <- as.numeric(difftime(end_time_m, start_time_m, units = "secs"))
  cat(sprintf("\nImputation %d completed in %.1f seconds\n\n", m, elapsed_m))
}

# =============================================================================
# CLEANUP
# =============================================================================

cat(strrep("=", 70), "\n")
cat("SCORING COMPLETE\n")
cat(strrep("=", 70), "\n\n")

# Disconnect from database
duckdb::dbDisconnect(con, shutdown = TRUE)
cat("[OK] Database connection closed\n\n")

# Summary
cat("SUMMARY:\n")
cat(sprintf("  Imputations scored: %d\n", length(all_scores)))
cat(sprintf("  Output directory: %s\n", temp_output_dir))
cat(sprintf("  Files created:\n"))

for (m in 1:n_imputations) {
  output_file <- file.path(temp_output_dir, sprintf("kidsights_scores_m%d.feather", m))
  if (file.exists(output_file)) {
    file_size <- file.size(output_file) / 1024  # KB
    cat(sprintf("    - kidsights_scores_m%d.feather (%.1f KB)\n", m, file_size))
  }
}

cat("\n")
cat("NEXT STEP:\n")
cat("  Run Python database insertion script:\n")
cat("  py scripts/irt_scoring/01b_insert_kidsights_scores.py\n")
cat("\n")

cat(sprintf("End time: %s\n", Sys.time()))
cat(strrep("=", 70), "\n")

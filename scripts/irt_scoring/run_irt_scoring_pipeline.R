# =============================================================================
# IRT Scoring Pipeline Orchestrator
# =============================================================================
# Purpose: Coordinate MAP scoring for selected scales
#          Selective execution for development/testing
#
# Usage:
#   Rscript run_irt_scoring_pipeline.R --scales kidsights
#   Rscript run_irt_scoring_pipeline.R --scales psychosocial
#   Rscript run_irt_scoring_pipeline.R --scales kidsights,psychosocial
#   Rscript run_irt_scoring_pipeline.R --scales all
#
# Future: Will integrate into imputation pipeline as Stage 12-13
#
# Version: 1.0
# Created: January 4, 2025
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("IRT SCORING PIPELINE - SELECTIVE EXECUTION\n")
cat(strrep("=", 80), "\n")
cat(sprintf("Start time: %s\n", Sys.time()))
cat("\n")

pipeline_start_time <- Sys.time()

# =============================================================================
# COMMAND-LINE ARGUMENT PARSING
# =============================================================================

cat(strrep("-", 80), "\n")
cat("PARSING COMMAND-LINE ARGUMENTS\n")
cat(strrep("-", 80), "\n\n")

# Get command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Parse --scales flag
scales_arg <- NULL
if (length(args) > 0) {
  for (i in seq_along(args)) {
    if (args[i] == "--scales" && i < length(args)) {
      scales_arg <- args[i + 1]
      break
    }
  }
}

# Default to all scales if not specified
if (is.null(scales_arg)) {
  cat("[INFO] No --scales flag provided. Using default: all scales\n")
  scales_arg <- "all"
}

cat(sprintf("--scales argument: %s\n", scales_arg))

# Parse comma-separated scale names
if (scales_arg == "all") {
  selected_scales <- c("kidsights", "psychosocial")
} else {
  selected_scales <- unlist(strsplit(scales_arg, ","))
  selected_scales <- trimws(selected_scales)  # Remove whitespace
}

cat(sprintf("\nSelected scales: %s\n", paste(selected_scales, collapse = ", ")))

# Validate scale names
valid_scales <- c("kidsights", "psychosocial")
invalid_scales <- setdiff(selected_scales, valid_scales)

if (length(invalid_scales) > 0) {
  cat(sprintf("\n[ERROR] Invalid scale name(s): %s\n", paste(invalid_scales, collapse = ", ")))
  cat(sprintf("Valid options: %s\n", paste(valid_scales, collapse = ", ")))
  stop("Invalid --scales argument")
}

cat("\n")

# =============================================================================
# LOAD CONFIGURATION
# =============================================================================

cat(strrep("-", 80), "\n")
cat("LOADING CONFIGURATION\n")
cat(strrep("-", 80), "\n\n")

library(yaml)

config_path <- "config/irt_scoring/irt_scoring_config.yaml"
if (!file.exists(config_path)) {
  stop(sprintf("Configuration file not found: %s", config_path))
}

config <- yaml::read_yaml(config_path)
cat(sprintf("[OK] Configuration loaded: %s\n", config_path))
cat(sprintf("  Study ID: %s\n", config$study_id))
cat(sprintf("  Number of imputations: %d\n", config$n_imputations))
cat("\n")

# =============================================================================
# GET PYTHON PATH
# =============================================================================

# Source environment config to get Python path
if (!exists("get_python_path", mode = "function")) {
  if (file.exists("R/utils/environment_config.R")) {
    source("R/utils/environment_config.R")
  } else {
    # Fallback
    get_python_path <- function() {
      python_cmd <- Sys.which("python")
      if (python_cmd == "") python_cmd <- Sys.which("python3")
      if (python_cmd == "") python_cmd <- Sys.which("py")
      if (python_cmd == "") stop("Python executable not found")
      return(python_cmd)
    }
  }
}

python_path <- get_python_path()
cat(sprintf("[INFO] Python executable: %s\n\n", python_path))

# =============================================================================
# EXECUTE SCORING FOR SELECTED SCALES
# =============================================================================

cat(strrep("=", 80), "\n")
cat("EXECUTING IRT SCORING\n")
cat(strrep("=", 80), "\n\n")

# Track results
scoring_results <- list()

# -----------------------------------------------------------------------------
# KIDSIGHTS SCALE
# -----------------------------------------------------------------------------

if ("kidsights" %in% selected_scales) {

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("SCALE 1: KIDSIGHTS DEVELOPMENTAL SCORES\n")
  cat(strrep("=", 80), "\n\n")

  start_time_kidsights <- Sys.time()

  # R Scoring Script
  kidsights_r_script <- "scripts/irt_scoring/01_score_kidsights.R"
  cat(sprintf("[INFO] Launching R scoring script: %s\n\n", kidsights_r_script))

  tryCatch({
    source(kidsights_r_script)
    cat("\n[OK] Kidsights scoring complete\n\n")
  }, error = function(e) {
    cat("\n[ERROR] Kidsights scoring failed:\n")
    cat(sprintf("  %s\n\n", e$message))
    scoring_results$kidsights$r_status <- "FAILED"
    scoring_results$kidsights$r_error <- e$message
    # Continue to next scale instead of halting entire pipeline
    return(NULL)
  })

  # Python Database Insertion Script
  kidsights_py_script <- "scripts/irt_scoring/01b_insert_kidsights_scores.py"
  cat(sprintf("[INFO] Launching Python insertion script: %s\n\n", kidsights_py_script))

  tryCatch({
    exit_code <- system2(python_path, args = kidsights_py_script, stdout = TRUE, stderr = TRUE)
    cat(exit_code, sep = "\n")
    cat("\n[OK] Kidsights database insertion complete\n\n")
    scoring_results$kidsights$status <- "SUCCESS"
  }, error = function(e) {
    cat("\n[ERROR] Kidsights database insertion failed:\n")
    cat(sprintf("  %s\n\n", e$message))
    scoring_results$kidsights$py_status <- "FAILED"
    scoring_results$kidsights$py_error <- e$message
  })

  end_time_kidsights <- Sys.time()
  elapsed_kidsights <- as.numeric(difftime(end_time_kidsights, start_time_kidsights, units = "secs"))
  scoring_results$kidsights$elapsed_seconds <- elapsed_kidsights

  cat(sprintf("\nKidsights scoring completed in %.1f seconds\n", elapsed_kidsights))
}

# -----------------------------------------------------------------------------
# PSYCHOSOCIAL SCALE
# -----------------------------------------------------------------------------

if ("psychosocial" %in% selected_scales) {

  cat("\n")
  cat(strrep("=", 80), "\n")
  cat("SCALE 2: PSYCHOSOCIAL BIFACTOR SCORES\n")
  cat(strrep("=", 80), "\n\n")

  start_time_psychosocial <- Sys.time()

  # R Scoring Script
  psychosocial_r_script <- "scripts/irt_scoring/02_score_psychosocial.R"
  cat(sprintf("[INFO] Launching R scoring script: %s\n\n", psychosocial_r_script))

  tryCatch({
    source(psychosocial_r_script)
    cat("\n[OK] Psychosocial scoring complete\n\n")
  }, error = function(e) {
    cat("\n[ERROR] Psychosocial scoring failed:\n")
    cat(sprintf("  %s\n\n", e$message))
    scoring_results$psychosocial$r_status <- "FAILED"
    scoring_results$psychosocial$r_error <- e$message
    return(NULL)
  })

  # Python Database Insertion Script
  psychosocial_py_script <- "scripts/irt_scoring/02b_insert_psychosocial_scores.py"
  cat(sprintf("[INFO] Launching Python insertion script: %s\n\n", psychosocial_py_script))

  tryCatch({
    exit_code <- system2(python_path, args = psychosocial_py_script, stdout = TRUE, stderr = TRUE)
    cat(exit_code, sep = "\n")
    cat("\n[OK] Psychosocial database insertion complete\n\n")
    scoring_results$psychosocial$status <- "SUCCESS"
  }, error = function(e) {
    cat("\n[ERROR] Psychosocial database insertion failed:\n")
    cat(sprintf("  %s\n\n", e$message))
    scoring_results$psychosocial$py_status <- "FAILED"
    scoring_results$psychosocial$py_error <- e$message
  })

  end_time_psychosocial <- Sys.time()
  elapsed_psychosocial <- as.numeric(difftime(end_time_psychosocial, start_time_psychosocial, units = "secs"))
  scoring_results$psychosocial$elapsed_seconds <- elapsed_psychosocial

  cat(sprintf("\nPsychosocial scoring completed in %.1f seconds\n", elapsed_psychosocial))
}

# =============================================================================
# PIPELINE SUMMARY
# =============================================================================

cat("\n")
cat(strrep("=", 80), "\n")
cat("PIPELINE SUMMARY\n")
cat(strrep("=", 80), "\n\n")

pipeline_end_time <- Sys.time()
total_elapsed <- as.numeric(difftime(pipeline_end_time, pipeline_start_time, units = "secs"))

cat(sprintf("Selected scales: %s\n", paste(selected_scales, collapse = ", ")))
cat(sprintf("Total execution time: %.1f seconds (%.1f minutes)\n", total_elapsed, total_elapsed / 60))
cat("\n")

# Scale-specific timing
cat("Scale-specific timing:\n")
for (scale_name in names(scoring_results)) {
  if (!is.null(scoring_results[[scale_name]]$elapsed_seconds)) {
    cat(sprintf("  %s: %.1f seconds\n",
                scale_name,
                scoring_results[[scale_name]]$elapsed_seconds))
  }
}

cat("\n")

# Status check
all_success <- TRUE
for (scale_name in names(scoring_results)) {
  if (!is.null(scoring_results[[scale_name]]$r_status)) {
    if (scoring_results[[scale_name]]$r_status == "FAILED") {
      all_success <- FALSE
      cat(sprintf("[ERROR] %s scoring failed\n", scale_name))
    }
  }
  if (!is.null(scoring_results[[scale_name]]$py_status)) {
    if (scoring_results[[scale_name]]$py_status == "FAILED") {
      all_success <- FALSE
      cat(sprintf("[ERROR] %s database insertion failed\n", scale_name))
    }
  }
}

if (all_success) {
  cat("\n[OK] All selected scales completed successfully!\n")
} else {
  cat("\n[WARN] Some scales encountered errors. See messages above.\n")
}

cat("\n")
cat(sprintf("End time: %s\n", Sys.time()))
cat(strrep("=", 80), "\n")
cat("\n")

# Return results invisibly (useful if sourced by other scripts)
invisible(scoring_results)

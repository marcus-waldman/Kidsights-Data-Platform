#!/usr/bin/env Rscript

#' Quick Setup and Run Script for NE25 Pipeline
#'
#' This script will:
#' 1. Set up the environment and install packages
#' 2. Initialize the database
#' 3. Run the complete pipeline
#'
#' Usage: source("setup_and_run.R")

cat("===========================================\n")
cat("   Kidsights NE25 Setup & Pipeline\n")
cat("===========================================\n")
cat("This script will set up and run the complete NE25 pipeline.\n")
cat("Please ensure you have internet connectivity and OneDrive access.\n\n")

# Step 1: Setup
cat("🔧 STEP 1: Setting up environment...\n")
tryCatch({
  source("scripts/setup/init_ne25_pipeline.R")
  setup_result <- setup_ne25_pipeline(test_redcap = TRUE, force_reinstall = FALSE)

  if (setup_result) {
    cat("✅ Setup completed successfully!\n\n")
  } else {
    stop("Setup failed - please check error messages above")
  }

}, error = function(e) {
  cat("❌ Setup failed:", e$message, "\n")
  cat("Please run the setup manually:\n")
  cat("  source('scripts/setup/init_ne25_pipeline.R')\n")
  cat("  setup_ne25_pipeline()\n")
  stop("Cannot proceed without successful setup")
})

# Step 2: Run Pipeline
cat("🚀 STEP 2: Running NE25 pipeline...\n\n")
tryCatch({
  source("run_ne25_pipeline.R")
  cat("\n✅ All steps completed!\n")

}, error = function(e) {
  cat("❌ Pipeline execution failed:", e$message, "\n")
  cat("You can try running the pipeline manually:\n")
  cat("  source('run_ne25_pipeline.R')\n")
})

cat("\n===========================================\n")
cat("   Setup and Pipeline Complete\n")
cat("===========================================\n")
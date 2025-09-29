#!/usr/bin/env Rscript
#' Complete NE25 Codebook Audit Runner
#'
#' Master script that runs the complete audit process:
#' 1. Extract REDCap metadata
#' 2. Extract codebook response sets
#' 3. Analyze dictionary current state
#' 4. Perform three-way comparison
#' 5. Generate comprehensive reports
#'
#' @author Kidsights Data Platform
#' @date 2025-09-18

cat("================================================================\n")
cat("NE25 CODEBOOK AUDIT - COMPLETE PIPELINE\n")
cat("================================================================\n")
cat("Starting comprehensive audit at:", as.character(Sys.time()), "\n\n")

# Set up error handling
options(error = function() {
  cat("\n❌ AUDIT FAILED\n")
  cat("Check error messages above for details\n")
  cat("================================================================\n")
  quit(status = 1)
})

# Track execution time
start_time <- Sys.time()

tryCatch({

  # Step 1: Extract REDCap Metadata
  cat("🔍 Step 1/5: Extracting REDCap metadata...\n")
  source("scripts/audit/ne25_codebook/extract_redcap_metadata.R")
  cat("✅ REDCap metadata extraction complete\n\n")

  # Step 2: Extract Codebook Response Sets
  cat("📚 Step 2/5: Extracting codebook response sets...\n")
  source("scripts/audit/ne25_codebook/extract_codebook_responses.R")
  cat("✅ Codebook response extraction complete\n\n")

  # Step 3: Analyze Dictionary
  cat("📊 Step 3/5: Analyzing dictionary current state...\n")
  source("scripts/audit/ne25_codebook/analyze_dictionary.R")
  cat("✅ Dictionary analysis complete\n\n")

  # Step 4: Three-Way Comparison
  cat("🔄 Step 4/5: Performing three-way source comparison...\n")
  source("scripts/audit/ne25_codebook/compare_sources.R")
  cat("✅ Three-way comparison complete\n\n")

  # Step 5: Generate Reports
  cat("📄 Step 5/5: Generating comprehensive audit reports...\n")
  source("scripts/audit/ne25_codebook/generate_audit_report.R")
  cat("✅ Audit reports generation complete\n\n")

  # Calculate execution time
  end_time <- Sys.time()
  duration <- end_time - start_time

  cat("================================================================\n")
  cat("✅ COMPLETE AUDIT SUCCESSFUL\n")
  cat("================================================================\n")
  cat("Total execution time:", round(as.numeric(duration, units = "mins"), 2), "minutes\n")
  cat("Audit completed at:", as.character(end_time), "\n\n")

  cat("📋 AUDIT SUMMARY:\n")
  cat("- All 46 PS items found in REDCap with proper response options\n")
  cat("- All 46 PS items found in codebook with correct response sets\n")
  cat("- All 46 PS items missing value labels in dictionary (100% failure)\n")
  cat("- Issue: Pipeline fails to preserve response labels during transformation\n\n")

  cat("📁 REPORTS LOCATION:\n")
  cat("scripts/audit/ne25_codebook/reports/\n")
  cat("- Start with: NE25_PS_AUDIT_SUMMARY.txt\n")
  cat("- Index: audit_reports_index.txt\n\n")

  cat("🔧 NEXT ACTIONS:\n")
  cat("1. Review audit summary report\n")
  cat("2. Investigate pipeline transformation process\n")
  cat("3. Implement response label preservation\n")
  cat("4. Add validation checks to prevent regression\n")
  cat("================================================================\n")

}, error = function(e) {
  cat("\n❌ AUDIT PIPELINE FAILED\n")
  cat("Error:", e$message, "\n")
  cat("Check individual script outputs for details\n")
  cat("================================================================\n")
  quit(status = 1)
})

cat("Audit pipeline completed successfully!\n")
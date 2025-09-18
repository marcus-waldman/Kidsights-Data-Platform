#!/usr/bin/env Rscript
#
# NE25 Codebook Audit - Master Script
#
# Purpose: Complete workflow for validating and updating NE25 codebook
#
# Author: Kidsights Data Platform
# Date: September 17, 2025
# Version: 1.0

cat("=== NE25 CODEBOOK AUDIT WORKFLOW ===\n\n")

# ==============================================================================
# STEP 1: VALIDATION
# ==============================================================================

cat("STEP 1: Validating NE25 items against actual data...\n")
cat("---------------------------------------------------\n")

source("scripts/codebook/validate_ne25_codebook.R")

cat("\n")

# ==============================================================================
# STEP 2: GENERATE REPORT
# ==============================================================================

cat("STEP 2: Generating validation report...\n")
cat("---------------------------------------\n")

source("scripts/codebook/generate_ne25_report.R")

cat("\n")

# ==============================================================================
# STEP 3: OPTIONAL UPDATE
# ==============================================================================

cat("STEP 3: Codebook update options\n")
cat("--------------------------------\n")

# Load validation results to check if updates are needed
validation_results <- readRDS("scripts/codebook/ne25_validation_results.rds")

if (validation_results$summary$missing_items > 0) {
  cat("⚠️  ISSUES FOUND: Some items need to be removed from NE25\n")
  cat(glue("   {validation_results$summary$missing_items} items claim NE25 but are not in data\n\n"))

  cat("Would you like to run the update script to fix these issues? (y/n): ")
  response <- tolower(readline())

  if (response %in% c("y", "yes", "1", "true")) {
    cat("\nRunning update script...\n")
    source("scripts/codebook/update_ne25_codebook.R")
  } else {
    cat("\n✓ Skipping update. You can run update_ne25_codebook.R manually later.\n")
  }
} else {
  cat("✅ NO UPDATES NEEDED: All NE25 items are valid\n\n")

  # Check if IRT parameters could be copied
  if (validation_results$summary$items_with_ne22_irt > validation_results$summary$items_with_irt) {
    potential_copies <- validation_results$summary$items_with_ne22_irt - validation_results$summary$items_with_irt
    cat(glue("💡 OPTIMIZATION OPPORTUNITY: {potential_copies} items could have NE22 IRT parameters copied to NE25\n\n"))

    cat("Would you like to copy NE22 IRT parameters to NE25 items? (y/n): ")
    response <- tolower(readline())

    if (response %in% c("y", "yes", "1", "true")) {
      cat("\nCopying IRT parameters...\n")
      # Set copy_irt_params to TRUE in the update script
      source("scripts/codebook/update_ne25_codebook.R")
      # Note: The update script will ask about IRT copying again, but that's intentional for safety
    } else {
      cat("✓ Skipping IRT parameter copying.\n")
    }
  }
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n=== AUDIT COMPLETE ===\n")
cat("Files created:\n")
cat("- docs/codebook/ne25_validation_report.md (validation report)\n")
cat("- scripts/codebook/ne25_validation_results.rds (validation data)\n")

# Check if backup was created
if (file.exists("scripts/codebook/ne25_update_log.txt")) {
  cat("- scripts/codebook/ne25_update_log.txt (update log)\n")

  # Find the most recent backup
  backup_files <- list.files("codebook/data", pattern = "codebook_pre_ne25_audit_.*\\.json", full.names = TRUE)
  if (length(backup_files) > 0) {
    latest_backup <- backup_files[which.max(file.mtime(backup_files))]
    cat(glue("- {latest_backup} (backup)\n"))
  }
}

cat("\nNext steps:\n")
cat("1. Review the validation report: docs/codebook/ne25_validation_report.md\n")
if (validation_results$summary$missing_items > 0) {
  cat("2. Consider running update_ne25_codebook.R to fix any issues\n")
} else {
  cat("2. No issues found - codebook is accurate!\n")
}
cat("3. Commit changes if updates were made\n\n")

cat("Audit workflow complete! 🎉\n")
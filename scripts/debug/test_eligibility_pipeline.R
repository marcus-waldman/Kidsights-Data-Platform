#!/usr/bin/env Rscript
# Debug script for eligibility pipeline failure
# Uses cached datasets to avoid repeated REDCap API calls

# SETUP
library(dplyr)
library(tidyr)
library(stringr)
library(yaml)

# Source functions
source("R/harmonize/ne25_eligibility.R")
source("R/transform/ne25_transforms.R")
source("R/documentation/generate_interactive_dictionary.R")

# CONFIGURATION
cache_dir <- "temp/pipeline_cache"
cat("=== ELIGIBILITY PIPELINE DEBUG SCRIPT ===\n")
cat("Cache directory:", cache_dir, "\n")

# Check if cache files exist
cache_files <- c(
  "step2_validated_data.rds",
  "step2_combined_dictionary.rds"
)

missing_files <- cache_files[!file.exists(file.path(cache_dir, cache_files))]
if (length(missing_files) > 0) {
  cat("❌ Missing cache files:", paste(missing_files, collapse=", "), "\n")
  cat("Please run the pipeline first to generate cache files.\n")
  quit(status = 1)
}

cat("✅ All cache files found\n\n")

# LOAD CACHED DATA
cat("📂 Loading cached datasets...\n")

# Load validated data (3,908 records from REDCap)
validated_data <- readRDS(file.path(cache_dir, "step2_validated_data.rds"))
cat("- Validated data:", nrow(validated_data), "records,", ncol(validated_data), "columns\n")

# Load combined dictionary
combined_dictionary <- readRDS(file.path(cache_dir, "step2_combined_dictionary.rds"))
cat("- Combined dictionary:", length(combined_dictionary), "field definitions\n")

cat("\n🔍 DEBUGGING check_ne25_eligibility FUNCTION\n")

# TEST 1: Verify function is loaded
cat("\n--- Test 1: Function availability ---\n")
if (exists("check_ne25_eligibility")) {
  cat("✅ check_ne25_eligibility function found\n")
} else {
  cat("❌ check_ne25_eligibility function NOT found\n")
  cat("Available functions:", ls(pattern="check_"), "\n")
  quit(status = 1)
}

# TEST 2: Check data structure for eligibility validation
cat("\n--- Test 2: Data structure validation ---\n")
cat("Validated data structure:\n")
cat("- Dimensions:", nrow(validated_data), "x", ncol(validated_data), "\n")
cat("- Class:", class(validated_data), "\n")

# Check for required columns
required_cols <- c("pid", "record_id", "eq001", "eq002", "eq003", "age_in_days", "fq001", "retrieved_date")
cat("Required columns check:\n")
for (col in required_cols) {
  if (col %in% names(validated_data)) {
    cat("  ✅", col, "found\n")
  } else {
    cat("  ❌", col, "MISSING\n")
  }
}

# TEST 3: Try the problematic function call
cat("\n--- Test 3: Execute check_ne25_eligibility ---\n")
cat("Calling check_ne25_eligibility with cached data...\n")

start_time <- Sys.time()
tryCatch({
  eligibility_checks <- check_ne25_eligibility(validated_data, combined_dictionary)

  end_time <- Sys.time()
  duration <- as.numeric(end_time - start_time)

  cat("✅ SUCCESS! Function completed in", round(duration, 2), "seconds\n")
  cat("Result structure:\n")
  str(eligibility_checks)

  # Save successful result
  saveRDS(eligibility_checks, file.path(cache_dir, "step3_eligibility_checks.rds"))
  cat("💾 Cached successful eligibility checks\n")

  cat("\n--- Test 4: Try apply_ne25_eligibility with successful checks ---\n")
  if (exists("apply_ne25_eligibility")) {
    eligibility_results <- apply_ne25_eligibility(validated_data, eligibility_checks)
    cat("✅ apply_ne25_eligibility also completed successfully!\n")
    cat("Result dimensions:", nrow(eligibility_results), "x", ncol(eligibility_results), "\n")

    # Save result
    saveRDS(eligibility_results, file.path(cache_dir, "step4_eligibility_results.rds"))

    # Show summary statistics
    cat("\nEligibility summary:\n")
    cat("- Eligible participants:", sum(eligibility_results$eligible, na.rm = TRUE), "\n")
    cat("- Authentic participants:", sum(eligibility_results$authentic, na.rm = TRUE), "\n")
    cat("- Included participants:", sum(eligibility_results$include, na.rm = TRUE), "\n")
  }

}, error = function(e) {
  cat("❌ ERROR in check_ne25_eligibility:\n")
  cat("Message:", e$message, "\n")
  cat("Call:", deparse(e$call), "\n")

  # Additional debugging
  cat("\nAdditional debugging info:\n")
  cat("- validated_data class:", class(validated_data), "\n")
  cat("- combined_dictionary class:", class(combined_dictionary), "\n")
  cat("- combined_dictionary length:", length(combined_dictionary), "\n")

  quit(status = 1)
})

cat("\n🎉 DEBUG SCRIPT COMPLETED SUCCESSFULLY\n")
cat("All cached files are available for further testing:\n")
cat("- step2_validated_data.rds\n")
cat("- step2_combined_dictionary.rds\n")
cat("- step3_eligibility_checks.rds\n")
cat("- step4_eligibility_results.rds\n")
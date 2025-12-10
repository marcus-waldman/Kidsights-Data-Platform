#!/usr/bin/env Rscript
################################################################################
# HRTL Scoring Pipeline Orchestrator
# Runs all steps: domain extraction -> Rasch -> imputation -> scoring
################################################################################

message("=== HRTL Scoring Pipeline ===\n")
start_time <- Sys.time()

# Step 1: Extract domain datasets
message("\n--- STEP 1: Extract Domain Datasets ---\n")
source("scripts/hrtl/01_extract_domain_datasets.R")

# Step 2: Fit Rasch models
message("\n--- STEP 2: Fit Rasch Models ---\n")
source("scripts/hrtl/02_fit_rasch_models.R")

# Step 3: Impute missing values
message("\n--- STEP 3: Impute Missing Values ---\n")
source("scripts/hrtl/03_impute_missing_values.R")

# Step 4: Score HRTL
message("\n--- STEP 4: Score HRTL ---\n")
source("scripts/hrtl/04_score_hrtl.R")

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
message(sprintf("\nHRTL Pipeline complete in %.1f seconds", elapsed))

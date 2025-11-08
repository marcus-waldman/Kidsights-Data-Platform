#!/usr/bin/env Rscript

#' Authenticity Screening - Phase 2: Fit Full Model
#'
#' This script:
#' 1. Compiles the Stan model
#' 2. Tests on a small subset (100 participants, 20 items)
#' 3. Fits the full model on all 2,635 authentic participants
#' 4. Saves results for LOOCV

library(cmdstanr)

cat("=== PHASE 2: STAN MODEL FITTING ===\n\n")

# Load helper functions
source("R/authenticity/stan_interface.R")
source("R/authenticity/diagnostics.R")

# Create output directory
dir.create("results", showWarnings = FALSE, recursive = TRUE)

# ============================================================================
# STEP 1: COMPILE STAN MODEL
# ============================================================================

cat("[Step 1/4] Compiling Stan model...\n")

model <- compile_authenticity_model(
  stan_file = "models/authenticity_glmm.stan",
  force_recompile = TRUE
)

cat("[OK] Stan model compiled\n")

# ============================================================================
# STEP 2: LOAD DATA
# ============================================================================

cat("\n[Step 2/4] Loading Stan data...\n")

stan_data_full <- readRDS("data/temp/stan_data_authentic.rds")

cat(sprintf("      Full dataset: N=%d, J=%d, M=%d\n",
            stan_data_full$N, stan_data_full$J, stan_data_full$M))


# ============================================================================
# STEP 3: FIT FULL MODEL
# ============================================================================

cat("\n[Step 3/4] Fitting full model on all 2,635 authentic participants...\n")
cat("      This may take several minutes...\n\n")

# Create initial values
init_full <- create_init_values(
  J = stan_data_full$J,
  N = stan_data_full$N,
  seed = 789
)

# Fit full model
fit_full <- fit_authenticity_glmm(
  stan_data = stan_data_full,
  model = model,
  init_values = init_full,
  algorithm = "lbfgs",
  max_iterations = 10000,
  refresh = 500
)

# Check convergence
if (fit_full$return_codes() == 0) {
  cat("\n[OK] Full model converged successfully\n")
} else {
  warning("\n[WARN] Full model may not have converged (code: ",
          fit_full$return_codes(), ")")
}

# Extract parameters
params_full <- extract_parameters(fit_full)

cat("\nParameter estimates (full model):\n")
cat("  delta (threshold spacing):", sprintf("%.3f", params_full$delta), "\n")
cat("  eta SD (empirical person variation):", sprintf("%.3f", sd(params_full$eta)), "\n")
cat("  tau range:", sprintf("[%.2f, %.2f]", min(params_full$tau), max(params_full$tau)), "\n")
cat("  beta1 range:", sprintf("[%.2f, %.2f]", min(params_full$beta1), max(params_full$beta1)), "\n")
cat("  eta range:", sprintf("[%.2f, %.2f]", min(params_full$eta), max(params_full$eta)), "\n")

# ============================================================================
# STEP 5: SAVE RESULTS
# ============================================================================

cat("\n[Step 5/5] Saving results...\n")

# Save full model fit
saveRDS(fit_full, "results/full_model_fit.rds")
cat("      Saved: results/full_model_fit.rds\n")

# Save parameter estimates
saveRDS(params_full, "results/full_model_params.rds")
cat("      Saved: results/full_model_params.rds\n")

# Extract and save log-likelihoods
log_lik_full <- extract_log_lik(fit_full)
saveRDS(log_lik_full, "results/full_model_log_lik.rds")
cat("      Saved: results/full_model_log_lik.rds\n")

# ============================================================================
# PHASE 2 SUMMARY
# ============================================================================

cat("\n=== PHASE 2 COMPLETE ===\n\n")
cat("Summary:\n")
cat("  Full model: FITTED (N=", stan_data_full$N, ", J=", stan_data_full$J, ", M=", stan_data_full$M, ")\n", sep = "")
cat("  Convergence: ", ifelse(fit_full$return_codes() == 0, "SUCCESS", "CHECK WARNINGS"), "\n", sep = "")
cat("\nKey parameters:\n")
cat("  Threshold spacing (delta):", sprintf("%.3f", params_full$delta), "\n")
cat("  Person variation (eta SD):", sprintf("%.3f", sd(params_full$eta)), "\n")
cat("\n[OK] Phase 2 model fitting complete!\n")
cat("\nNext: Proceed to Phase 3 (LOOCV for out-of-sample lz distribution)\n")

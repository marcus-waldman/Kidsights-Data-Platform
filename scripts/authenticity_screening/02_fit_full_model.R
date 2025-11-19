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
  history_size = 50, 
  refresh = 20
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

cat("\n=== PARAMETER ESTIMATES (FULL MODEL) ===\n\n")

# Correlation between dimensions
cat("Correlation Between Dimensions:\n")
cat(sprintf("  eta_correlation (LKJ): %.3f\n", params_full$eta_correlation))
cor_strength <- ifelse(abs(params_full$eta_correlation) < 0.3, "weak",
                       ifelse(abs(params_full$eta_correlation) < 0.7, "moderate", "strong"))
cat(sprintf("  Strength: %s\n", cor_strength))
cat("  (LKJ(1) prior is uniform over all correlations)\n")

# Threshold parameters
cat("\nThreshold Parameters:\n")
cat(sprintf("  delta[1] (psychosocial spacing): %.3f\n", params_full$delta[1]))
cat(sprintf("  delta[2] (developmental spacing): %.3f\n", params_full$delta[2]))
cat(sprintf("  tau (first thresholds): range [%.2f, %.2f]\n",
            min(params_full$tau), max(params_full$tau)))

# Age effects
cat("\nAge Effects:\n")
cat(sprintf("  beta1 (age slopes): range [%.2f, %.2f]\n",
            min(params_full$beta1), max(params_full$beta1)))
cat(sprintf("    Mean: %.3f\n", mean(params_full$beta1)))
cat(sprintf("    Positive slopes: %d/%d (%.1f%%)\n",
            sum(params_full$beta1 > 0), length(params_full$beta1),
            100 * sum(params_full$beta1 > 0) / length(params_full$beta1)))

# Person random effects (Psychosocial)
cat("\nPerson Random Effects (Psychosocial):\n")
cat(sprintf("  eta[, 1]: N=%d\n", length(params_full$eta_psychosocial)))
cat(sprintf("    Range: [%.2f, %.2f]\n",
            min(params_full$eta_psychosocial), max(params_full$eta_psychosocial)))
cat(sprintf("    SD:    %.3f (target: 1.0 for standard normal marginal)\n", sd(params_full$eta_psychosocial)))

# Person random effects (Developmental)
cat("\nPerson Random Effects (Developmental):\n")
cat(sprintf("  eta[, 2]: N=%d\n", length(params_full$eta_developmental)))
cat(sprintf("    Range: [%.2f, %.2f]\n",
            min(params_full$eta_developmental), max(params_full$eta_developmental)))
cat(sprintf("    SD:    %.3f (target: 1.0 for standard normal marginal)\n", sd(params_full$eta_developmental)))

# Empirical correlation check
cat("\nEmpirical Correlation Check:\n")
cor_eta_empirical <- cor(params_full$eta_psychosocial, params_full$eta_developmental)
cat(sprintf("  Empirical cor(eta[,1], eta[,2]): %.3f\n", cor_eta_empirical))
cat(sprintf("  Estimated eta_correlation: %.3f\n", params_full$eta_correlation))
cat(sprintf("  Difference: %.3f (should be near 0)\n", abs(cor_eta_empirical - params_full$eta_correlation)))

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

# Create eta_full lookup with (pid, record_id) mapping
pids_full <- attr(stan_data_full, "pid")
record_ids_full <- attr(stan_data_full, "record_id")

eta_full_lookup <- data.frame(
  pid = pids_full,
  record_id = record_ids_full,
  authenticity_eta_psychosocial = params_full$eta_psychosocial,
  authenticity_eta_developmental = params_full$eta_developmental
)

saveRDS(eta_full_lookup, "results/full_model_eta_lookup.rds")
cat("      Saved: results/full_model_eta_lookup.rds\n")
cat(sprintf("      eta_full lookup: %d participants (pid, record_id, eta_psych, eta_dev)\n",
            nrow(eta_full_lookup)))

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
cat("  Estimated correlation:", sprintf("%.3f (%s)", params_full$eta_correlation, cor_strength), "\n")
cat("  Threshold spacing (delta[1]):", sprintf("%.3f", params_full$delta[1]), "\n")
cat("  Threshold spacing (delta[2]):", sprintf("%.3f", params_full$delta[2]), "\n")
cat("  Person variation (eta[,1] SD):", sprintf("%.3f (target: 1.0)", sd(params_full$eta_psychosocial)), "\n")
cat("  Person variation (eta[,2] SD):", sprintf("%.3f (target: 1.0)", sd(params_full$eta_developmental)), "\n")
cat("  Empirical correlation:", sprintf("%.3f", cor_eta_empirical), "\n")
cat("\n[OK] Phase 2 model fitting complete!\n")
cat("\nModel notes:\n")
cat("  - LKJ(1) prior is uniform over all correlations (non-informative)\n")
cat("  - Marginal variances fixed at 1 (standard normal)\n")
cat("  - Correlation estimated from data with flat prior\n")
cat("\nNext: Proceed to Phase 3 (LOOCV for out-of-sample lz distribution)\n")

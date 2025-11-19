#!/usr/bin/env Rscript

#' Compute Log-Posterior for Inauthentic Participants
#'
#' Uses full N=2,635 model parameters to estimate log-posterior
#' for each inauthentic participant.
#'
#' Strategy:
#'   1. Load full N model parameters (from LOOCV Phase 2)
#'   2. Load inauthentic participants' data
#'   3. For each inauthentic participant:
#'      - Fit holdout model (fixed item params, estimate eta_i)
#'      - Extract log_posterior and avg_logpost
#'   4. Flag participants with < 5 items as insufficient data
#'   5. Save results
#'
#' Backend: rstan
#' Expected runtime: ~30 seconds (872 participants)

library(rstan)
library(dplyr)

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY SCREENING: INAUTHENTIC LOG-POSTERIOR ESTIMATION\n")
cat("================================================================================\n")
cat("\n")

# Set rstan options
rstan_options(auto_write = TRUE)

# ============================================================================
# PHASE 1: LOAD DATA AND PARAMETERS
# ============================================================================

cat("=== PHASE 1: LOAD DATA AND PARAMETERS ===\n\n")

cat("[Step 1/4] Loading Stan data for inauthentic participants...\n")

# Load inauthentic stan data (already prepared in Phase 1)
stan_data_inauthentic <- readRDS("data/temp/stan_data_inauthentic.rds")

# Extract metadata
inauthentic_pids <- attr(stan_data_inauthentic, "pid")
inauthentic_record_ids <- attr(stan_data_inauthentic, "record_id")
item_mapping <- attr(stan_data_inauthentic, "item_names")

cat(sprintf("      Found %d inauthentic participants\n", length(inauthentic_pids)))
cat(sprintf("      Item responses: %d observations\n", stan_data_inauthentic$M))

cat("\n[Step 2/4] Loading full N model parameters...\n")

# Load LOOCV distribution parameters (includes full N fit)
# We'll re-fit the full N model to get parameters
stan_data_authentic <- readRDS("data/temp/stan_data_authentic.rds")
main_model <- rstan::stan_model("models/authenticity_glmm.stan")

cat("      Fitting full N=2,635 model to get item parameters...\n")

fit_full <- rstan::optimizing(
  object = main_model,
  data = stan_data_authentic,
  seed = 12345,
  iter = 10000,
  algorithm = "LBFGS",
  verbose = FALSE
)

if (fit_full$return_code != 0) {
  stop("Full model failed to converge")
}

cat("      [OK] Full model fitted\n")

# Extract parameters
params_full <- fit_full$par
tau_full <- params_full[grepl("^tau\\[", names(params_full))]
beta1_full <- params_full[grepl("^beta1\\[", names(params_full))]
delta_full <- params_full[grepl("^delta\\[", names(params_full))]  # Now 2-element vector
eta_correlation_full <- params_full["eta_correlation"]

# Get dimension and K from authentic stan_data (same structure as inauthentic)
dimension <- stan_data_authentic$dimension
K <- stan_data_authentic$K
J <- stan_data_authentic$J

cat(sprintf("      Extracted: tau(%d), beta1(%d), delta(%.3f, %.3f), eta_corr(%.3f)\n",
            length(tau_full), length(beta1_full), delta_full[1], delta_full[2], eta_correlation_full))

# ============================================================================
# PHASE 2: COMPILE HOLDOUT MODEL
# ============================================================================

cat("\n=== PHASE 2: COMPILE HOLDOUT MODEL ===\n\n")

cat("[Step 3/4] Compiling holdout Stan model...\n")
holdout_model <- rstan::stan_model("models/authenticity_holdout.stan")
cat("      [OK] Holdout model compiled\n")

# ============================================================================
# PHASE 3: ESTIMATE LOG-POSTERIOR FOR EACH INAUTHENTIC PARTICIPANT
# ============================================================================

cat("\n=== PHASE 3: ESTIMATE LOG-POSTERIOR FOR INAUTHENTIC PARTICIPANTS ===\n\n")

cat(sprintf("[Step 4/4] Computing log-posterior for %d inauthentic participants...\n",
            length(inauthentic_pids)))

# Prepare data structures
J <- stan_data_inauthentic$J
K <- stan_data_inauthentic$K
N <- stan_data_inauthentic$N

results_list <- vector("list", N)

for (p in 1:N) {

  # Progress update every 100 participants
  if (p %% 100 == 0) {
    cat(sprintf("      Processing %d / %d (%.1f%%)...\n",
                p, N, 100 * p / N))
  }

  # Extract person i's data from vectorized stan data
  mask_i <- stan_data_inauthentic$ivec == p
  y_i <- stan_data_inauthentic$yvec[mask_i]
  j_i <- stan_data_inauthentic$jvec[mask_i]
  age_i <- stan_data_inauthentic$age[p]
  n_items <- length(y_i)

  # Check if sufficient data (5+ items)
  sufficient_data <- n_items >= 5

  if (n_items == 0) {
    # No item responses
    results_list[[p]] <- list(
      pid = inauthentic_pids[p],
      record_id = inauthentic_record_ids[p],
      log_posterior = NA_real_,
      avg_logpost = NA_real_,
      n_items = 0,
      authenticity_eta_psychosocial_full = NA_real_,
      authenticity_eta_developmental_full = NA_real_,
      authenticity_eta_psychosocial_holdout = NA_real_,
      authenticity_eta_developmental_holdout = NA_real_,
      sufficient_data = FALSE,
      converged = FALSE
    )
    next
  }

  # Prepare holdout data
  stan_data_holdout <- list(
    J = J,
    tau = tau_full,
    beta1 = beta1_full,
    delta = delta_full,
    K = K,
    dimension = dimension,
    eta_correlation = eta_correlation_full,
    M_holdout = n_items,
    j_holdout = j_i,
    y_holdout = y_i,
    age_holdout = age_i
  )

  # Fit holdout model
  fit_holdout <- rstan::optimizing(
    object = holdout_model,
    data = stan_data_holdout,
    seed = 54321 + p,
    iter = 10000,
    algorithm = "LBFGS",
    verbose = FALSE
  )

  # Check convergence
  converged <- !is.null(fit_holdout$return_code) &&
               length(fit_holdout$return_code) > 0 &&
               fit_holdout$return_code == 0

  if (!converged) {
    results_list[[p]] <- list(
      pid = inauthentic_pids[p],
      record_id = inauthentic_record_ids[p],
      log_posterior = NA_real_,
      avg_logpost = NA_real_,
      n_items = n_items,
      authenticity_eta_psychosocial_full = NA_real_,
      authenticity_eta_developmental_full = NA_real_,
      authenticity_eta_psychosocial_holdout = NA_real_,
      authenticity_eta_developmental_holdout = NA_real_,
      sufficient_data = sufficient_data,
      converged = FALSE
    )
    next
  }

  # Extract results including 2D eta
  log_posterior <- fit_holdout$par["log_posterior"]

  # Extract 2D eta from holdout model
  eta_psychosocial_holdout <- fit_holdout$par["eta_psychosocial_holdout"]
  eta_developmental_holdout <- fit_holdout$par["eta_developmental_holdout"]

  avg_logpost <- log_posterior / n_items

  results_list[[p]] <- list(
    pid = inauthentic_pids[p],
    record_id = inauthentic_record_ids[p],
    log_posterior = log_posterior,
    avg_logpost = avg_logpost,
    n_items = n_items,
    authenticity_eta_psychosocial_full = eta_psychosocial_holdout,     # Dim 1
    authenticity_eta_developmental_full = eta_developmental_holdout,   # Dim 2
    authenticity_eta_psychosocial_holdout = eta_psychosocial_holdout,  # Same as full
    authenticity_eta_developmental_holdout = eta_developmental_holdout, # Same as full
    sufficient_data = sufficient_data,
    converged = TRUE
  )
}

cat(sprintf("      [OK] Processed %d inauthentic participants\n", length(inauthentic_pids)))

# ============================================================================
# PHASE 4: PROCESS AND SAVE RESULTS
# ============================================================================

cat("\n=== PHASE 4: PROCESS AND SAVE RESULTS ===\n\n")

cat("[Step 1/3] Converting results to data frame...\n")

inauthentic_df <- dplyr::bind_rows(results_list)

cat(sprintf("      [OK] %d results collected\n", nrow(inauthentic_df)))

# Summary statistics
n_total <- nrow(inauthentic_df)
n_sufficient <- sum(inauthentic_df$sufficient_data, na.rm = TRUE)
n_converged <- sum(inauthentic_df$converged, na.rm = TRUE)
n_sufficient_converged <- sum(inauthentic_df$sufficient_data &
                                inauthentic_df$converged, na.rm = TRUE)

cat(sprintf("      Total inauthentic: %d\n", n_total))
cat(sprintf("      Sufficient data (5+ items): %d (%.1f%%)\n",
            n_sufficient, 100 * n_sufficient / n_total))
cat(sprintf("      Converged: %d (%.1f%%)\n",
            n_converged, 100 * n_converged / n_total))
cat(sprintf("      Sufficient & converged: %d (%.1f%%)\n",
            n_sufficient_converged, 100 * n_sufficient_converged / n_total))

cat("\n[Step 2/3] Adding standardized lz values...\n")

# Load LOOCV distribution parameters
loocv_params <- readRDS("results/loocv_distribution_params.rds")
mean_avg <- loocv_params$mean_avg_logpost
sd_avg <- loocv_params$sd_avg_logpost

cat(sprintf("      Using LOOCV distribution: mean=%.4f, sd=%.4f\n", mean_avg, sd_avg))

# Calculate lz
inauthentic_df <- inauthentic_df %>%
  dplyr::mutate(
    lz = (avg_logpost - mean_avg) / sd_avg
  )

cat("      [OK] lz standardization complete\n")

# Summary of lz values for sufficient data participants
inauthentic_sufficient <- inauthentic_df %>%
  dplyr::filter(sufficient_data & converged)

if (nrow(inauthentic_sufficient) > 0) {
  cat("\n      LZ statistics (sufficient data only):\n")
  cat(sprintf("        Mean lz: %.4f\n", mean(inauthentic_sufficient$lz, na.rm = TRUE)))
  cat(sprintf("        SD lz: %.4f\n", sd(inauthentic_sufficient$lz, na.rm = TRUE)))
  cat(sprintf("        Min lz: %.4f\n", min(inauthentic_sufficient$lz, na.rm = TRUE)))
  cat(sprintf("        Max lz: %.4f\n", max(inauthentic_sufficient$lz, na.rm = TRUE)))
}

cat("\n[Step 3/3] Saving results...\n")

# Save full inauthentic results
saveRDS(inauthentic_df, "results/inauthentic_logpost_results.rds")
cat("      Saved: results/inauthentic_logpost_results.rds\n")

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n")
cat("================================================================================\n")
cat("  INAUTHENTIC LOG-POSTERIOR ESTIMATION COMPLETE\n")
cat("================================================================================\n")
cat("\n")

cat("Summary:\n")
cat(sprintf("  Total inauthentic participants: %d\n", n_total))
cat(sprintf("  Sufficient data (5+ items): %d (%.1f%%)\n",
            n_sufficient, 100 * n_sufficient / n_total))
cat(sprintf("  Successfully converged: %d (%.1f%%)\n",
            n_sufficient_converged, 100 * n_sufficient_converged / n_total))
cat("\n")

if (nrow(inauthentic_sufficient) > 0) {
  cat("LZ Statistics (for classification):\n")
  cat(sprintf("  Mean lz (inauthentic): %.4f\n",
              mean(inauthentic_sufficient$lz, na.rm = TRUE)))
  cat(sprintf("  SD lz (inauthentic): %.4f\n",
              sd(inauthentic_sufficient$lz, na.rm = TRUE)))
  cat("\n")
}

cat("Next Steps:\n")
cat("  1. ROC analysis to determine optimal threshold (Task 8)\n")
cat("  2. Calculate classification metrics (Task 9)\n")
cat("  3. Create diagnostic plots (Task 10)\n")
cat("\n")

cat("[OK] Inauthentic log-posterior estimation complete!\n")
cat("\n")

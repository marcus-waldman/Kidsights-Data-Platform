#!/usr/bin/env Rscript

#' Compute Cook's D for Inauthentic Participants
#'
#' For each inauthentic participant with sufficient data (>=5 items), this script:
#'   1. Creates augmented training set: N_authentic + participant_i
#'   2. Fits augmented model → extracts parameters θ_{N+i}
#'   3. Computes param_diff: Δθ_i = θ_{N+i} - θ_{N_authentic}
#'   4. Extracts 2D eta estimates from augmented fit
#'   5. Uses jackknife Hessian from authentic LOOCV
#'   6. Computes Cook's D: D_i = Δθ_i' × H × Δθ_i / p
#'   7. Scales by N: D_i × N (sample-size invariant)
#'
#' This measures: "What would happen if we mistakenly included this
#' inauthentic response in training?"
#'
#' Input:
#'   - data/temp/stan_data_authentic.rds (N=2,635 authentic baseline)
#'   - data/temp/stan_data_inauthentic.rds (N=872 inauthentic)
#'   - results/full_model_params.rds (baseline θ_{N_authentic})
#'   - results/loocv_hessian_approx.rds (jackknife Hessian from authentic)
#'
#' Output:
#'   - results/inauthentic_cooks_d.rds (Cook's D + 2D eta for inauthentic)
#'
#' Parallelization: future + furrr (16 cores, ~10 min total)

library(rstan)
library(dplyr)
library(future)
library(furrr)
library(progressr)

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY SCREENING: COOK'S D FOR INAUTHENTIC PARTICIPANTS\n")
cat("================================================================================\n")
cat("\n")

# ============================================================================
# PHASE 1: LOAD DATA AND BASELINE MODEL
# ============================================================================

cat("=== PHASE 1: LOAD DATA ===\n\n")

cat("[Step 1/5] Loading authentic baseline data...\n")
stan_data_authentic <- readRDS("data/temp/stan_data_authentic.rds")
N_authentic <- stan_data_authentic$N
J <- stan_data_authentic$J

cat(sprintf("      Authentic baseline: N=%d, J=%d items\n", N_authentic, J))

cat("\n[Step 2/5] Loading inauthentic participant data...\n")
stan_data_inauthentic <- readRDS("data/temp/stan_data_inauthentic.rds")
inauthentic_pids <- attr(stan_data_inauthentic, "pid")
inauthentic_record_ids <- attr(stan_data_inauthentic, "record_id")
N_inauthentic <- length(inauthentic_pids)

cat(sprintf("      Inauthentic participants: N=%d\n", N_inauthentic))

cat("\n[Step 3/5] Loading baseline model parameters...\n")
params_baseline <- readRDS("results/full_model_params.rds")

# Extract baseline parameters as vectors
tau_baseline <- params_baseline$tau
beta1_baseline <- params_baseline$beta1
delta_baseline <- params_baseline$delta
eta_correlation_baseline <- params_baseline$eta_correlation

cat(sprintf("      Baseline: tau(%d), beta1(%d), delta(%d), eta_corr(%.3f)\n",
            length(tau_baseline), length(beta1_baseline), length(delta_baseline),
            eta_correlation_baseline))

cat("\n[Step 4/5] Loading jackknife Hessian from authentic LOOCV...\n")
hessian_approx <- readRDS("results/loocv_hessian_approx.rds")
p <- nrow(hessian_approx)

cat(sprintf("      Hessian: %d × %d matrix\n", p, p))
cat(sprintf("      Parameter count: p = %d (tau + beta1 + delta + eta_corr)\n", p))

cat("\n[Step 5/5] Compiling Stan model...\n")

# Compile main model
model <- rstan::stan_model("models/authenticity_glmm.stan")
cat("      [OK] Stan model compiled\n")

# ============================================================================
# PHASE 2: FILTER TO SUFFICIENT DATA
# ============================================================================

cat("\n=== PHASE 2: FILTER INAUTHENTIC PARTICIPANTS ===\n\n")

cat("[Step 1/1] Filtering to participants with sufficient data (>=5 items)...\n")

# Count items per participant
item_counts <- table(stan_data_inauthentic$ivec)
sufficient_mask <- item_counts >= 5

n_sufficient <- sum(sufficient_mask)
n_insufficient <- N_inauthentic - n_sufficient

cat(sprintf("      Sufficient data (>=5 items): %d (%.1f%%)\n",
            n_sufficient, 100 * n_sufficient / N_inauthentic))
cat(sprintf("      Insufficient data (<5 items): %d (%.1f%%)\n",
            n_insufficient, 100 * n_insufficient / N_inauthentic))

# Get participant indices with sufficient data
sufficient_participants <- as.integer(names(item_counts)[sufficient_mask])

# ============================================================================
# PHASE 3: DEFINE AUGMENTED MODEL FITTING FUNCTION
# ============================================================================

cat("\n=== PHASE 3: DEFINE AUGMENTED MODEL FITTING ===\n\n")

#' Fit augmented model (N_authentic + 1 inauthentic participant)
#'
#' @param i_inauth Index in stan_data_inauthentic$ivec (1 to N_inauthentic)
#' @param stan_data_authentic Authentic baseline data
#' @param stan_data_inauthentic Inauthentic participant data
#' @param inauthentic_pids Vector of inauthentic PIDs
#' @param inauthentic_record_ids Vector of inauthentic record IDs
#' @param tau_baseline Baseline tau parameters
#' @param beta1_baseline Baseline beta1 parameters
#' @param delta_baseline Baseline delta parameters (2-element)
#' @param eta_correlation_baseline Baseline eta correlation
#' @param hessian_approx Jackknife Hessian (p × p)
#' @param model Compiled Stan model
#'
#' @return List with Cook's D and 2D eta estimates
fit_augmented_model <- function(i_inauth, stan_data_authentic, stan_data_inauthentic,
                                  inauthentic_pids, inauthentic_record_ids,
                                  tau_baseline, beta1_baseline, delta_baseline,
                                  eta_correlation_baseline, hessian_approx, model) {

  # --------------------------------------------------
  # Step 1: Extract inauthentic participant's data
  # --------------------------------------------------

  mask_i <- stan_data_inauthentic$ivec == i_inauth
  n_items_i <- sum(mask_i)

  # Extract observations for participant i
  jvec_i <- stan_data_inauthentic$jvec[mask_i]
  yvec_i <- stan_data_inauthentic$yvec[mask_i]
  age_i <- stan_data_inauthentic$age[i_inauth]

  # --------------------------------------------------
  # Step 2: Create augmented dataset (N_authentic + 1)
  # --------------------------------------------------

  N_augmented <- stan_data_authentic$N + 1
  M_augmented <- stan_data_authentic$M + n_items_i

  # Concatenate observations
  ivec_augmented <- c(stan_data_authentic$ivec, rep(N_augmented, n_items_i))
  jvec_augmented <- c(stan_data_authentic$jvec, jvec_i)
  yvec_augmented <- c(stan_data_authentic$yvec, yvec_i)
  age_augmented <- c(stan_data_authentic$age, age_i)

  stan_data_augmented <- list(
    M = M_augmented,
    N = N_augmented,
    J = stan_data_authentic$J,
    yvec = yvec_augmented,
    ivec = ivec_augmented,
    jvec = jvec_augmented,
    age = age_augmented,
    K = stan_data_authentic$K,
    dimension = stan_data_authentic$dimension
  )

  # --------------------------------------------------
  # Step 3: Fit augmented model
  # --------------------------------------------------

  fit_augmented <- rstan::optimizing(
    object = model,
    data = stan_data_augmented,
    iter = 10000,
    algorithm = "LBFGS",
    verbose = FALSE,
    refresh = 0
  )

  # Check convergence
  if (fit_augmented$return_code != 0) {
    return(list(
      pid = inauthentic_pids[i_inauth],
      record_id = inauthentic_record_ids[i_inauth],
      n_items = n_items_i,
      cooks_d = NA_real_,
      cooks_d_scaled = NA_real_,
      influential_4 = FALSE,
      influential_N = FALSE,
      authenticity_eta_psychosocial_full = NA_real_,
      authenticity_eta_developmental_full = NA_real_,
      authenticity_eta_psychosocial_holdout = NA_real_,
      authenticity_eta_developmental_holdout = NA_real_,
      converged = FALSE
    ))
  }

  # --------------------------------------------------
  # Step 4: Extract parameters and compute differences
  # --------------------------------------------------

  params_augmented <- fit_augmented$par
  tau_augmented <- params_augmented[grepl("^tau\\[", names(params_augmented))]
  beta1_augmented <- params_augmented[grepl("^beta1\\[", names(params_augmented))]
  delta_augmented <- params_augmented[grepl("^delta\\[", names(params_augmented))]
  eta_correlation_augmented <- params_augmented["eta_correlation"]

  # Compute parameter differences
  param_diff <- c(
    tau_augmented - tau_baseline,
    beta1_augmented - beta1_baseline,
    delta_augmented - delta_baseline,
    eta_correlation_augmented - eta_correlation_baseline
  )

  # --------------------------------------------------
  # Step 5: Compute Cook's D using jackknife Hessian
  # --------------------------------------------------

  # D_i = diff' × H × diff / p
  cooks_d <- as.numeric(t(param_diff) %*% hessian_approx %*% param_diff / nrow(hessian_approx))
  cooks_d_scaled <- cooks_d * stan_data_authentic$N  # Sample-size invariant

  # --------------------------------------------------
  # Step 6: Extract 2D eta for participant i
  # --------------------------------------------------

  # Extract eta matrix (N_augmented × 2)
  eta_names <- names(params_augmented)[grepl("^eta\\[", names(params_augmented))]
  eta_values <- params_augmented[eta_names]
  eta_matrix <- matrix(eta_values, nrow = N_augmented, ncol = 2, byrow = TRUE)

  # Get eta for last participant (the inauthentic participant)
  eta_psychosocial_full <- eta_matrix[N_augmented, 1]
  eta_developmental_full <- eta_matrix[N_augmented, 2]

  # For inauthentic, "holdout" is same as "full" (no LOOCV concept)
  eta_psychosocial_holdout <- eta_psychosocial_full
  eta_developmental_holdout <- eta_developmental_full

  # --------------------------------------------------
  # Step 7: Return results
  # --------------------------------------------------

  return(list(
    pid = inauthentic_pids[i_inauth],
    record_id = inauthentic_record_ids[i_inauth],
    n_items = n_items_i,
    cooks_d = cooks_d,
    cooks_d_scaled = cooks_d_scaled,
    influential_4 = (cooks_d_scaled > 4),
    influential_N = (cooks_d_scaled > stan_data_authentic$N),
    authenticity_eta_psychosocial_full = eta_psychosocial_full,
    authenticity_eta_developmental_full = eta_developmental_full,
    authenticity_eta_psychosocial_holdout = eta_psychosocial_holdout,
    authenticity_eta_developmental_holdout = eta_developmental_holdout,
    converged = TRUE
  ))
}

cat("[OK] Augmented model fitting function defined\n")

# ============================================================================
# PHASE 4: RUN PARALLEL COMPUTATION
# ============================================================================

cat("\n=== PHASE 4: COMPUTE COOK'S D (PARALLEL) ===\n\n")

# Configure parallel backend
default_cores <- floor(parallel::detectCores() / 2)
n_cores <- as.integer(Sys.getenv("N_CORES", default_cores))
cat(sprintf("[Config] Using %d cores (detected %d total)\n", n_cores, parallel::detectCores()))

plan(multisession, workers = n_cores)

cat(sprintf("\n[Parallel] Running %d augmented model fits...\n", n_sufficient))
cat(sprintf("      Estimated time: ~%.1f minutes with %d cores\n",
            n_sufficient * 48 / 60 / n_cores, n_cores))

start_time <- Sys.time()

# Run with progress bar
results_list <- with_progress({
  p <- progressor(steps = n_sufficient)

  future_map(
    sufficient_participants,
    function(i_inauth) {
      p()  # Update progress
      fit_augmented_model(
        i_inauth = i_inauth,
        stan_data_authentic = stan_data_authentic,
        stan_data_inauthentic = stan_data_inauthentic,
        inauthentic_pids = inauthentic_pids,
        inauthentic_record_ids = inauthentic_record_ids,
        tau_baseline = tau_baseline,
        beta1_baseline = beta1_baseline,
        delta_baseline = delta_baseline,
        eta_correlation_baseline = eta_correlation_baseline,
        hessian_approx = hessian_approx,
        model = model
      )
    },
    .options = furrr_options(seed = TRUE)
  )
})

end_time <- Sys.time()
total_time <- as.numeric(difftime(end_time, start_time, units = "secs"))

cat(sprintf("\n[OK] Parallel computation complete (%.1f minutes)\n", total_time / 60))

# ============================================================================
# PHASE 5: COMBINE RESULTS AND SAVE
# ============================================================================

cat("\n=== PHASE 5: SAVE RESULTS ===\n\n")

# Convert to data frame
results_df <- dplyr::bind_rows(results_list)

# Add rows for insufficient data participants (NA values)
insufficient_df <- data.frame(
  pid = inauthentic_pids[!sufficient_participants %in% 1:N_inauthentic],
  record_id = inauthentic_record_ids[!sufficient_participants %in% 1:N_inauthentic],
  n_items = NA_integer_,
  cooks_d = NA_real_,
  cooks_d_scaled = NA_real_,
  influential_4 = FALSE,
  influential_N = FALSE,
  authenticity_eta_psychosocial_full = NA_real_,
  authenticity_eta_developmental_full = NA_real_,
  authenticity_eta_psychosocial_holdout = NA_real_,
  authenticity_eta_developmental_holdout = NA_real_,
  converged = FALSE
)

# Combine sufficient and insufficient
results_complete <- dplyr::bind_rows(results_df, insufficient_df)

# Save results
saveRDS(results_complete, "results/inauthentic_cooks_d.rds")
cat("      Saved: results/inauthentic_cooks_d.rds\n")

# Summary statistics
n_converged <- sum(results_complete$converged, na.rm = TRUE)
n_influential_4 <- sum(results_complete$influential_4, na.rm = TRUE)
n_influential_N <- sum(results_complete$influential_N, na.rm = TRUE)

cat("\n")
cat("================================================================================\n")
cat("  INAUTHENTIC COOK'S D COMPLETE\n")
cat("================================================================================\n")
cat("\n")

cat("Summary:\n")
cat(sprintf("  Total inauthentic participants: %d\n", nrow(results_complete)))
cat(sprintf("  Sufficient data (>=5 items): %d (%.1f%%)\n",
            n_sufficient, 100 * n_sufficient / nrow(results_complete)))
cat(sprintf("  Converged: %d (%.1f%%)\n",
            n_converged, 100 * n_converged / n_sufficient))
cat(sprintf("  Highly influential (D×N > 4): %d (%.1f%%)\n",
            n_influential_4, 100 * n_influential_4 / n_converged))
cat(sprintf("  Very high influence (D×N > %d): %d (%.1f%%)\n",
            N_authentic, n_influential_N, 100 * n_influential_N / n_converged))
cat("\n")

cat("Execution time:\n")
cat(sprintf("  Total: %.1f minutes (%.2f hours)\n", total_time / 60, total_time / 3600))
cat(sprintf("  Per participant: %.1f seconds\n", total_time / n_sufficient))
cat("\n")

cat("Next steps:\n")
cat("  1. Run 08_compute_pipeline_weights.R to merge Cook's D into pipeline\n")
cat("  2. Inspect influential inauthentic: filter(influential_4 == TRUE)\n")
cat("  3. Cross-reference with avg_logpost to identify most concerning patterns\n")
cat("\n")

cat("[OK] Inauthentic Cook's D computation complete!\n")
cat("\n")

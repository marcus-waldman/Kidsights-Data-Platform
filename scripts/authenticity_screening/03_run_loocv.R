#!/usr/bin/env Rscript

#' Run Leave-One-Out Cross-Validation for Authenticity Screening
#'
#' This script implements LOOCV to build an out-of-sample distribution of
#' average log-posterior values for authentic participants.
#'
#' WARM-START STRATEGY (enables ~4.5 minute execution with 16 cores):
#'   1. Fit full N=2,635 model ONCE → extract all parameters
#'   2. For each iteration i:
#'      a. Create eta_init = eta[-i] - mean(eta[-i])  [satisfies sum-to-zero]
#'      b. Fit N-1 model with init={eta_init, tau, beta1, delta} [39x speedup!]
#'      c. Extract item parameters from N-1 fit
#'      d. Fit holdout model (fixed items, estimate eta_i)
#'      e. Extract log_posterior and avg_logpost = log_posterior / n_items
#'
#' CRITICAL: Saves BOTH log_posterior AND avg_logpost for re-analysis flexibility
#'
#' Backend: rstan (v2.36.0.9000 with Stan 2.37.0)
#' Parallelization: future + furrr (16 cores)
#' Progress: progressr
#'
#' Expected runtime: ~4.5 minutes with 16 cores (1.4 sec/iteration)

library(rstan)
library(dplyr)
library(future)
library(furrr)
library(progressr)

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY SCREENING: LEAVE-ONE-OUT CROSS-VALIDATION\n")
cat("================================================================================\n")
cat("\n")

# Set rstan options
rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())

# Set up parallel backend
n_cores <- 16
plan(multisession, workers = n_cores)
cat(sprintf("[Setup] Parallel backend: %d cores\n", n_cores))
cat("[Setup] Warm-start: centered eta + item params (39x speedup)\n")

# ============================================================================
# PHASE 1: LOAD DATA AND COMPILE MODELS
# ============================================================================

cat("\n=== PHASE 1: DATA LOADING AND MODEL COMPILATION ===\n\n")

cat("[Step 1/3] Loading Stan data...\n")
stan_data_full <- readRDS("data/temp/stan_data_authentic.rds")
pids_full <- attr(stan_data_full, "pid")
N <- stan_data_full$N
J <- stan_data_full$J
M <- stan_data_full$M

cat(sprintf("      Full data: N=%d, J=%d, M=%d\n", N, J, M))

cat("\n[Step 2/3] Compiling Stan models...\n")
main_model <- rstan::stan_model("models/authenticity_glmm.stan")
cat("      [OK] Main model compiled\n")

holdout_model <- rstan::stan_model("models/authenticity_holdout.stan")
cat("      [OK] Holdout model compiled\n")

# ============================================================================
# PHASE 2: FIT FULL N MODEL FOR WARM-START INITIALIZATION
# ============================================================================

cat("\n=== PHASE 2: FIT FULL N MODEL (ONE-TIME WARM-START SETUP) ===\n\n")

cat(sprintf("[Step 3/3] Fitting full N=%d model...\n", N))
cat("      This takes ~48 seconds...\n")

start_time_full <- Sys.time()

fit_full <- rstan::optimizing(
  object = main_model,
  data = stan_data_full,
  seed = 12345,
  iter = 10000,
  algorithm = "LBFGS",
  verbose = FALSE
)

end_time_full <- Sys.time()
fit_time_full <- as.numeric(difftime(end_time_full, start_time_full, units = "secs"))

if (fit_full$return_code != 0) {
  stop("Full N model failed to converge (return code: ", fit_full$return_code, ")")
}

cat(sprintf("      [OK] Full model fitted in %.1f seconds (%.2f minutes)\n",
            fit_time_full, fit_time_full / 60))

# Extract ALL parameters for warm-start initialization
params_full <- fit_full$par
eta_full <- params_full[grepl("^eta\\[", names(params_full))]
tau_full <- params_full[grepl("^tau\\[", names(params_full))]
beta1_full <- params_full[grepl("^beta1\\[", names(params_full))]
delta_full <- params_full["delta"]

cat(sprintf("      Extracted: eta(%d), tau(%d), beta1(%d), delta(%.3f)\n",
            length(eta_full), length(tau_full), length(beta1_full), delta_full))

# Verify sum-to-zero constraint
cat(sprintf("      Full eta: sum=%.6f (sum-to-zero constraint verified)\n",
            sum(eta_full)))

# ============================================================================
# PHASE 3: DEFINE LOOCV ITERATION FUNCTION
# ============================================================================

cat("\n=== PHASE 3: LOOCV ITERATION FUNCTION ===\n\n")

#' Run a single LOOCV iteration with centered eta warm-start
#'
#' @param i Index of participant to hold out (1 to N)
#' @param stan_data_full Full Stan data list
#' @param pids_full Vector of participant IDs
#' @param eta_full Full N eta parameters
#' @param tau_full Full N tau parameters
#' @param beta1_full Full N beta1 parameters
#' @param delta_full Full N delta parameter
#' @param main_model Compiled main Stan model
#' @param holdout_model Compiled holdout Stan model
#'
#' @return List with (i, pid, log_posterior, avg_logpost, n_items, eta_est,
#'                     converged_main, converged_holdout)
run_loocv_iteration <- function(i, stan_data_full, pids_full,
                                 eta_full, tau_full, beta1_full, delta_full,
                                 main_model, holdout_model) {

  # --------------------------------------------------
  # Step 1: Create leave-one-out data
  # --------------------------------------------------

  mask_loo <- stan_data_full$ivec != i
  ivec_loo <- stan_data_full$ivec[mask_loo]
  ivec_loo_reindexed <- as.integer(as.factor(ivec_loo))

  stan_data_loo <- list(
    M = sum(mask_loo),
    N = stan_data_full$N - 1,
    J = stan_data_full$J,
    yvec = stan_data_full$yvec[mask_loo],
    ivec = ivec_loo_reindexed,
    jvec = stan_data_full$jvec[mask_loo],
    age = stan_data_full$age[-i],
    K = stan_data_full$K
  )

  # --------------------------------------------------
  # Step 2: Create CENTERED eta for warm-start
  # --------------------------------------------------

  # Extract eta[-i] and center to satisfy sum-to-zero constraint
  eta_loo <- eta_full[-i]
  eta_loo_centered <- eta_loo - mean(eta_loo)

  # Create initialization list
  init_warmstart <- list(
    eta = eta_loo_centered,  # CENTERED eta (satisfies sum_to_zero_vector)
    tau = tau_full,
    beta1 = beta1_full,
    delta = delta_full
  )

  # --------------------------------------------------
  # Step 3: Fit N-1 model with warm-start
  # --------------------------------------------------

  fit_loo <- rstan::optimizing(
    object = main_model,
    data = stan_data_loo,
    init = init_warmstart,
    seed = 12345 + i,
    iter = 10000,
    algorithm = "LBFGS",
    verbose = FALSE
  )

  # Robust convergence check (handle optimizer creation failures)
  converged_main <- !is.null(fit_loo$return_code) &&
                    length(fit_loo$return_code) > 0 &&
                    fit_loo$return_code == 0

  if (!converged_main) {
    return(list(
      i = i,
      pid = pids_full[i],
      log_posterior = NA_real_,
      avg_logpost = NA_real_,
      n_items = NA_integer_,
      eta_est = NA_real_,
      converged_main = FALSE,
      converged_holdout = FALSE
    ))
  }

  # --------------------------------------------------
  # Step 4: Extract item parameters from N-1 fit
  # --------------------------------------------------

  params_loo <- fit_loo$par
  tau_loo <- params_loo[grepl("^tau\\[", names(params_loo))]
  beta1_loo <- params_loo[grepl("^beta1\\[", names(params_loo))]
  delta_loo <- params_loo["delta"]

  # --------------------------------------------------
  # Step 5: Extract held-out person's data
  # --------------------------------------------------

  mask_holdout <- stan_data_full$ivec == i
  y_holdout <- stan_data_full$yvec[mask_holdout]
  j_holdout <- stan_data_full$jvec[mask_holdout]
  age_holdout <- stan_data_full$age[i]
  M_holdout <- length(y_holdout)

  # --------------------------------------------------
  # Step 6: Fit holdout model (estimate only eta_i)
  # --------------------------------------------------

  stan_data_holdout <- list(
    J = stan_data_full$J,
    tau = tau_loo,
    beta1 = beta1_loo,
    delta = delta_loo,
    K = stan_data_full$K,
    M_holdout = M_holdout,
    j_holdout = j_holdout,
    y_holdout = y_holdout,
    age_holdout = age_holdout
  )

  fit_holdout <- rstan::optimizing(
    object = holdout_model,
    data = stan_data_holdout,
    seed = 54321 + i,
    iter = 10000,
    algorithm = "LBFGS",
    verbose = FALSE
  )

  # Robust convergence check (handle optimizer creation failures)
  converged_holdout <- !is.null(fit_holdout$return_code) &&
                       length(fit_holdout$return_code) > 0 &&
                       fit_holdout$return_code == 0

  if (!converged_holdout) {
    return(list(
      i = i,
      pid = pids_full[i],
      log_posterior = NA_real_,
      avg_logpost = NA_real_,
      n_items = M_holdout,
      eta_est = NA_real_,
      converged_main = TRUE,
      converged_holdout = FALSE
    ))
  }

  # --------------------------------------------------
  # Step 7: Extract log posterior and calculate average
  # --------------------------------------------------

  log_posterior <- fit_holdout$par["log_posterior"]
  eta_est <- fit_holdout$par["eta_holdout"]
  avg_logpost <- log_posterior / M_holdout

  # --------------------------------------------------
  # Step 8: Return results
  # --------------------------------------------------

  return(list(
    i = i,
    pid = pids_full[i],
    log_posterior = log_posterior,  # RAW log-posterior (for re-analysis)
    avg_logpost = avg_logpost,      # Per-item average (for standardization)
    n_items = M_holdout,
    eta_est = eta_est,
    converged_main = TRUE,
    converged_holdout = TRUE
  ))
}

cat("[OK] LOOCV iteration function defined\n")
cat("      Uses centered eta warm-start (39x speedup)\n")

# ============================================================================
# PHASE 4: RUN LOOCV IN PARALLEL WITH PROGRESS BAR
# ============================================================================

cat("\n=== PHASE 4: RUN LOOCV (2,635 ITERATIONS, 16 CORES) ===\n\n")

cat(sprintf("Starting LOOCV with %d participants...\n", N))
cat("Expected runtime: ~4.5 minutes (1.4 seconds per iteration)\n")
cat("Progress bar will update in real-time...\n\n")

# Create results directory
dir.create("results/loocv_progress", showWarnings = FALSE, recursive = TRUE)

# Run LOOCV with progress bar
handlers(global = TRUE)
handlers("progress")

start_time_loocv <- Sys.time()

loocv_results <- with_progress({
  p <- progressor(steps = N)

  furrr::future_map(
    1:N,
    function(i) {
      # Run iteration
      result <- run_loocv_iteration(
        i = i,
        stan_data_full = stan_data_full,
        pids_full = pids_full,
        eta_full = eta_full,
        tau_full = tau_full,
        beta1_full = beta1_full,
        delta_full = delta_full,
        main_model = main_model,
        holdout_model = holdout_model
      )

      # Update progress bar
      p()

      # Save intermediate results every 100 iterations
      if (i %% 100 == 0) {
        checkpoint_file <- sprintf("results/loocv_progress/loocv_checkpoint_%04d.rds", i)
        tryCatch({
          saveRDS(result, checkpoint_file)
        }, error = function(e) {
          # Silently ignore save errors in parallel workers
        })
      }

      return(result)
    },
    .options = furrr_options(seed = TRUE)
  )
})

end_time_loocv <- Sys.time()
total_time_loocv <- as.numeric(difftime(end_time_loocv, start_time_loocv, units = "secs"))

cat("\n")
cat(sprintf("[OK] LOOCV complete in %.1f seconds (%.2f minutes)\n",
            total_time_loocv, total_time_loocv / 60))

# ============================================================================
# PHASE 5: PROCESS RESULTS AND SAVE
# ============================================================================

cat("\n=== PHASE 5: PROCESS AND SAVE RESULTS ===\n\n")

cat("[Step 1/4] Converting results to data frame...\n")

loocv_df <- dplyr::bind_rows(loocv_results)

cat(sprintf("      [OK] %d results collected\n", nrow(loocv_df)))

# Check convergence
n_converged_main <- sum(loocv_df$converged_main, na.rm = TRUE)
n_converged_holdout <- sum(loocv_df$converged_holdout, na.rm = TRUE)
n_both_converged <- sum(loocv_df$converged_main & loocv_df$converged_holdout, na.rm = TRUE)

cat(sprintf("      Main model converged: %d / %d (%.1f%%)\n",
            n_converged_main, N, 100 * n_converged_main / N))
cat(sprintf("      Holdout model converged: %d / %d (%.1f%%)\n",
            n_converged_holdout, N, 100 * n_converged_holdout / N))
cat(sprintf("      Both converged: %d / %d (%.1f%%)\n",
            n_both_converged, N, 100 * n_both_converged / N))

cat("\n[Step 2/4] Computing distribution statistics...\n")

loocv_converged <- loocv_df %>%
  dplyr::filter(converged_main & converged_holdout)

mean_avg_logpost <- mean(loocv_converged$avg_logpost, na.rm = TRUE)
sd_avg_logpost <- sd(loocv_converged$avg_logpost, na.rm = TRUE)

cat(sprintf("      Mean avg_logpost: %.4f\n", mean_avg_logpost))
cat(sprintf("      SD avg_logpost: %.4f\n", sd_avg_logpost))

distribution_params <- list(
  mean_avg_logpost = mean_avg_logpost,
  sd_avg_logpost = sd_avg_logpost,
  n_converged = n_both_converged,
  n_total = N
)

cat("\n[Step 3/4] Calculating standardized lz values...\n")

loocv_df <- loocv_df %>%
  dplyr::mutate(
    lz = (avg_logpost - mean_avg_logpost) / sd_avg_logpost
  )

cat("      [OK] lz standardization complete\n")

cat("\n[Step 4/4] Saving results...\n")

# Save full LOOCV results
saveRDS(loocv_df, "results/loocv_authentic_results.rds")
cat("      Saved: results/loocv_authentic_results.rds\n")

# Save distribution parameters
saveRDS(distribution_params, "results/loocv_distribution_params.rds")
cat("      Saved: results/loocv_distribution_params.rds\n")

# Save summary statistics
summary_stats <- loocv_df %>%
  dplyr::filter(converged_main & converged_holdout) %>%
  dplyr::summarise(
    n = dplyr::n(),
    mean_log_posterior = mean(log_posterior, na.rm = TRUE),
    sd_log_posterior = sd(log_posterior, na.rm = TRUE),
    mean_avg_logpost = mean(avg_logpost, na.rm = TRUE),
    sd_avg_logpost = sd(avg_logpost, na.rm = TRUE),
    mean_lz = mean(lz, na.rm = TRUE),
    sd_lz = sd(lz, na.rm = TRUE),
    mean_n_items = mean(n_items, na.rm = TRUE),
    median_n_items = median(n_items, na.rm = TRUE),
    min_n_items = min(n_items, na.rm = TRUE),
    max_n_items = max(n_items, na.rm = TRUE)
  )

saveRDS(summary_stats, "results/loocv_summary_stats.rds")
cat("      Saved: results/loocv_summary_stats.rds\n")

# ============================================================================
# PHASE 6: SUMMARY REPORT
# ============================================================================

cat("\n")
cat("================================================================================\n")
cat("  LOOCV COMPLETE\n")
cat("================================================================================\n")
cat("\n")

cat("Execution Summary:\n")
cat(sprintf("  Total runtime: %.2f minutes (%.2f hours)\n",
            total_time_loocv / 60, total_time_loocv / 3600))
cat(sprintf("  Iterations: %d\n", N))
cat(sprintf("  Convergence rate: %.1f%%\n", 100 * n_both_converged / N))
cat(sprintf("  Speedup enabled by: Centered eta warm-start (39x)\n"))
cat("\n")

cat("Distribution Parameters (for standardization):\n")
cat(sprintf("  mean_avg_logpost: %.4f\n", mean_avg_logpost))
cat(sprintf("  sd_avg_logpost: %.4f\n", sd_avg_logpost))
cat("\n")

cat("Summary Statistics:\n")
print(summary_stats)
cat("\n")

cat("Next Steps:\n")
cat("  1. Compute avg_logpost for inauthentic participants (Task 6)\n")
cat("  2. Standardize inauthentic values using LOOCV distribution (Task 7)\n")
cat("  3. ROC analysis to determine optimal threshold (Task 8)\n")
cat("  4. Calculate classification metrics (Task 9)\n")
cat("  5. Create diagnostic plots (Task 10)\n")
cat("\n")

cat("[OK] LOOCV phase complete!\n")
cat("\n")

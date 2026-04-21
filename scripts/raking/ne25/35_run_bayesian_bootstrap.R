# ============================================================================
# Script 35: NE25 Bayesian-Bootstrap Orchestrator (Bucket 3)
# ============================================================================
#
# Orchestrates the full M imputations * B Bayesian-bootstrap draws = M*B
# Stan optimizations for NE25 weight sampling-variance estimation.
#
# Phase 1 -- Baselines (5 cold-start fits, sequential):
#   For each m in 1..M, run Stan with bbw = rep(1, N) (default; Bucket 2
#   equivalent) and init = 0. Verify baseline calibrated_weight matches
#   the stored ne25_raked_weights WHERE imputation_m = m to within 0.1 --
#   this is the built-in regression test against Bucket 2. baseline_wgt_raw
#   is still captured (for possible later warm-start experiments) but not
#   used by the current bootstrap worker.
#
# Phase 2 -- Bootstrap (M*B cold-start fits, future.apply parallel):
#   For each (m, b) in 1..M x 1..B, run run_one_bootstrap_fit() which:
#     - draws bbw_b ~ Exp(1) with seed = 20260420 + 1000*m + b,
#     - calls the wrapper with bbw = bbw_b (enters the moment-matching
#       loss as a multiplicative data weight, not as a prior),
#     - writes weights_m{m}_b{b}.feather to the bootstrap output dir.
#
# Concurrency model:
#   - future.apply::future_lapply with future::multisession plan
#   - N_WORKERS = 8 (reduced from 16 to avoid Stan compile-cache contention)
#   - Pre-compile Stan model in the parent R session so that workers only
#     ever do cache reads (not writes) when cmdstanr::cmdstan_model() is
#     called. This is the fix for the callr-pool silent-crash failure
#     observed in the previous attempt.
#   - Chunked execution (chunk = 2 * N_WORKERS) for progress heartbeats.
#   - Per-chunk tryCatch around run_one_bootstrap_fit: any job's failure is
#     captured as {error, stan_ok=FALSE} in the results list rather than
#     aborting the whole batch.
#
# Resumability: each (m, b) whose output feather already exists is skipped
# on startup. Re-invoking this script after an interruption fills gaps.
#
# Outputs:
#   - data/raking/ne25/ne25_weights_boot/baseline_wgt_raw.rds
#   - data/raking/ne25/ne25_weights_boot/weights_m{m}_b{b}.feather (1,000 files)
#   - data/raking/ne25/ne25_weights_boot/run_summary.rds
# ============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(future)
  library(future.apply)
  library(DBI)
  library(duckdb)
  library(cmdstanr)
})

source("scripts/raking/ne25/utils/calibrate_weights_simplex_factorized_cmdstan.R")
source("R/imputation/config.R")  # for get_n_imputations()

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

M          <- get_n_imputations()    # 5
B          <- 200                    # Bayesian bootstrap draws per imputation
N_WORKERS  <- 8                      # future::multisession pool size
CHUNK_SIZE <- N_WORKERS * 2          # jobs per future_lapply call (progress grain)
SEED_BASE  <- 20260420L

harmonized_dir   <- "data/raking/ne25/ne25_harmonized"
unified_moments  <- "data/raking/ne25/unified_moments.rds"
boot_output_dir  <- "data/raking/ne25/ne25_weights_boot"
baseline_rds     <- file.path(boot_output_dir, "baseline_wgt_raw.rds")
summary_rds      <- file.path(boot_output_dir, "run_summary.rds")
stan_file        <- "scripts/raking/ne25/utils/calibrate_weights_simplex_factorized.stan"
wrapper_file     <- "scripts/raking/ne25/utils/calibrate_weights_simplex_factorized_cmdstan.R"
worker_file      <- "scripts/raking/ne25/utils/run_one_bootstrap_fit.R"

if (!dir.exists(boot_output_dir)) dir.create(boot_output_dir, recursive = TRUE)

source(worker_file)  # defines run_one_bootstrap_fit()

cat("\n=========================================================\n")
cat("  NE25 Bayesian-Bootstrap Orchestrator (Bucket 3)\n")
cat("=========================================================\n\n")
cat(sprintf("  M (imputations):       %d\n", M))
cat(sprintf("  B (bootstrap draws):   %d\n", B))
cat(sprintf("  Total Stan calls:      %d baselines + %d bootstrap = %d\n",
            M, M*B, M + M*B))
cat(sprintf("  future workers:        %d\n", N_WORKERS))
cat(sprintf("  Chunk size (progress): %d\n", CHUNK_SIZE))
cat(sprintf("  Output dir:            %s\n\n", boot_output_dir))

overall_start <- Sys.time()

# ============================================================================
# PRE-COMPILE Stan model in parent (fix for compile-cache contention)
# ============================================================================

cat("---------------------------------------------------------\n")
cat("  Pre-compile: Stan model (parent session)\n")
cat("---------------------------------------------------------\n\n")

t0 <- Sys.time()
mod_parent <- cmdstanr::cmdstan_model(stan_file, quiet = TRUE)
cat(sprintf("  [OK] Stan model compiled in %.1f s\n", as.numeric(Sys.time() - t0, units = "secs")))
cat(sprintf("  Binary: %s\n\n", mod_parent$exe_file()))

# ============================================================================
# PHASE 1 -- Baselines (sequential, cold-start)
# ============================================================================

cat("---------------------------------------------------------\n")
cat("  Phase 1: Baseline fits (M=5, cold-start, flat prior)\n")
cat("---------------------------------------------------------\n\n")

unified <- readRDS(unified_moments)

db_path <- Sys.getenv("KIDSIGHTS_DB_PATH")
if (db_path == "") db_path <- "data/duckdb/kidsights_local.duckdb"
con <- DBI::dbConnect(duckdb::duckdb(), db_path, read_only = TRUE)
bucket2_weights <- DBI::dbGetQuery(con, sprintf("
  SELECT pid, record_id, imputation_m, calibrated_weight
  FROM ne25_raked_weights
  WHERE imputation_m <= %d
", M))
DBI::dbDisconnect(con, shutdown = TRUE)

baseline_list <- vector("list", M)
names(baseline_list) <- as.character(seq_len(M))

# Track whether we can skip re-running baselines (resumable)
baseline_exists_and_valid <- file.exists(baseline_rds)
if (baseline_exists_and_valid) {
  prev <- tryCatch(readRDS(baseline_rds), error = function(e) NULL)
  if (!is.null(prev) && length(prev) == M && all(as.character(seq_len(M)) %in% names(prev))) {
    baseline_list <- prev
    cat(sprintf("  [RESUME] Loaded %d baseline wgt_raw vectors from %s (skipping Phase 1)\n\n",
                M, baseline_rds))
  } else {
    baseline_exists_and_valid <- FALSE
  }
}

if (!baseline_exists_and_valid) {
  for (m in seq_len(M)) {
    cat(sprintf("  [baseline m=%d] running Stan (flat prior, cold start)...\n", m))
    t0 <- Sys.time()
    ne25_m <- arrow::read_feather(
      file.path(harmonized_dir, sprintf("ne25_harmonized_m%d.feather", m))
    )
    res_b <- calibrate_weights_simplex_factorized_stan(
      data             = ne25_m,
      target_mean      = unified$mu,
      target_cov       = unified$Sigma,
      cov_mask         = unified$cov_mask,
      calibration_vars = unified$variable_names,
      min_weight       = 1E-2,
      max_weight       = 100,
      verbose          = FALSE,
      history_size     = 50,
      refresh          = 10000,
      iter             = 1000
    )
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    cat(sprintf("    done in %.1f s (Kish N = %.1f, weight ratio = %.2f)\n",
                elapsed, res_b$effective_n, res_b$weight_ratio))

    stored_m <- bucket2_weights %>%
      dplyr::filter(imputation_m == m) %>%
      dplyr::mutate(pid = as.integer(pid), record_id = as.integer(record_id))
    mer <- merge(
      data.frame(pid = as.integer(ne25_m$pid),
                 record_id = as.integer(ne25_m$record_id),
                 new_w = res_b$calibrated_weight),
      stored_m %>% dplyr::select(pid, record_id, stored_w = calibrated_weight),
      by = c("pid", "record_id")
    )
    max_diff <- max(abs(mer$new_w - mer$stored_w))
    if (max_diff < 1e-6) {
      cat(sprintf("    [OK] baseline matches Bucket 2 byte-identical (max diff %.3e)\n", max_diff))
    } else if (max_diff < 0.1) {
      cat(sprintf("    [OK] baseline close to Bucket 2 (max diff %.3e, autodiff drift)\n", max_diff))
    } else {
      stop(sprintf("baseline m=%d differs from Bucket 2 by %.3e -- regression failure", m, max_diff))
    }

    if (is.null(res_b$wgt_raw_estimate)) {
      stop(sprintf("wrapper did not return wgt_raw_estimate for m=%d", m))
    }
    baseline_list[[as.character(m)]] <- res_b$wgt_raw_estimate
  }

  saveRDS(baseline_list, baseline_rds)
  cat(sprintf("\n  Saved %d baseline wgt_raw vectors to %s\n\n", M, baseline_rds))
}

# ============================================================================
# PHASE 2 -- Bootstrap (future.apply parallel, chunked)
# ============================================================================

cat("---------------------------------------------------------\n")
cat("  Phase 2: Bootstrap fits (future.apply pool)\n")
cat("---------------------------------------------------------\n\n")

# Configure future plan
future::plan(future::multisession, workers = N_WORKERS)
on.exit(future::plan(future::sequential), add = TRUE)
cat(sprintf("  future::plan(multisession, workers = %d)\n\n", N_WORKERS))

# Build full work grid and filter out already-completed (resumable)
work_grid <- expand.grid(m = seq_len(M), b = seq_len(B))
work_grid$seed <- SEED_BASE + 1000L * work_grid$m + work_grid$b
work_grid$output_path <- with(work_grid, file.path(
  boot_output_dir, sprintf("weights_m%d_b%d.feather", m, b)
))
work_grid$done <- file.exists(work_grid$output_path)

n_total   <- nrow(work_grid)
n_done    <- sum(work_grid$done)
pending   <- work_grid[!work_grid$done, ]
n_pending <- nrow(pending)

cat(sprintf("  Total (m, b) jobs:     %d\n", n_total))
cat(sprintf("  Already completed:     %d (resumable skip)\n", n_done))
cat(sprintf("  To run this session:   %d\n\n", n_pending))

# Process pending work in chunks for progress reporting
all_results <- vector("list", n_pending)
result_idx  <- 0L
chunk_starts <- seq(1, n_pending, by = CHUNK_SIZE)

for (cs in chunk_starts) {
  ce <- min(cs + CHUNK_SIZE - 1L, n_pending)
  chunk <- pending[cs:ce, ]

  chunk_t0 <- Sys.time()
  chunk_results <- future.apply::future_lapply(
    seq_len(nrow(chunk)),
    function(j) {
      row_m    <- chunk$m[j]
      row_b    <- chunk$b[j]
      row_seed <- as.integer(chunk$seed[j])
      tryCatch(
        run_one_bootstrap_fit(
          m                    = row_m,
          b                    = row_b,
          seed                 = row_seed,
          harmonized_dir       = harmonized_dir,
          unified_moments_file = unified_moments,
          output_dir           = boot_output_dir,
          wrapper_file         = wrapper_file,
          history_size         = 50,
          iter                 = 1000,
          min_weight           = 0.01,
          max_weight           = 100
        ),
        error = function(e) {
          list(m = row_m, b = row_b, stan_ok = FALSE,
               error = conditionMessage(e))
        }
      )
    },
    future.seed = TRUE,
    future.globals = list(
      chunk                = chunk,
      harmonized_dir       = harmonized_dir,
      unified_moments      = unified_moments,
      boot_output_dir      = boot_output_dir,
      wrapper_file         = wrapper_file,
      run_one_bootstrap_fit = run_one_bootstrap_fit
    )
  )

  # Accumulate results
  for (j in seq_along(chunk_results)) {
    result_idx <- result_idx + 1L
    all_results[[result_idx]] <- chunk_results[[j]]
  }

  # Progress log
  chunk_elapsed <- as.numeric(difftime(Sys.time(), chunk_t0, units = "secs"))
  n_files_now <- length(list.files(boot_output_dir,
                                   pattern = "^weights_m\\d+_b\\d+\\.feather$"))
  elapsed_min <- as.numeric(difftime(Sys.time(), overall_start, units = "mins"))
  cat(sprintf("  [%s] chunk %d/%d done (%d jobs in %.1f s) | feathers on disk: %d | elapsed: %.1f min\n",
              format(Sys.time(), "%H:%M:%S"),
              which(chunk_starts == cs), length(chunk_starts),
              nrow(chunk), chunk_elapsed,
              n_files_now, elapsed_min))
}

# ============================================================================
# Collect results into summary data.frame
# ============================================================================

cat("\n---------------------------------------------------------\n")
cat("  Collecting per-(m, b) results\n")
cat("---------------------------------------------------------\n\n")

results <- data.frame(
  m            = work_grid$m,
  b            = work_grid$b,
  kish_n       = NA_real_,
  weight_ratio = NA_real_,
  stan_ok      = NA,
  error        = NA_character_
)

# Mark already-done jobs as skipped (no summary available)
for (res in all_results) {
  if (is.null(res)) next
  idx <- which(results$m == res$m & results$b == res$b)
  if (!is.null(res$error) && !is.na(res$error)) {
    results$error[idx] <- res$error
    results$stan_ok[idx] <- FALSE
  } else {
    results$kish_n[idx]       <- res$kish_n
    results$weight_ratio[idx] <- res$weight_ratio
    results$stan_ok[idx]      <- isTRUE(res$stan_ok)
  }
}

saveRDS(results, summary_rds)

# ============================================================================
# Final summary
# ============================================================================

overall_elapsed <- as.numeric(difftime(Sys.time(), overall_start, units = "mins"))

cat("=========================================================\n")
cat("  Bayesian-bootstrap orchestrator complete\n")
cat("=========================================================\n\n")
cat(sprintf("  Total elapsed: %.1f min\n\n", overall_elapsed))

n_stan_ok  <- sum(isTRUE(results$stan_ok), na.rm = TRUE)
n_failed   <- sum(!is.na(results$error))
final_files <- list.files(boot_output_dir, pattern = "^weights_m\\d+_b\\d+\\.feather$")
cat(sprintf("  Stan ok flag TRUE:   %d\n", n_stan_ok))
cat(sprintf("  Failed / error:      %d\n", n_failed))
cat(sprintf("  Feather files:       %d / %d expected\n",
            length(final_files), n_total))

if (length(final_files) < n_total) {
  cat(sprintf("\n  [WARN] %d feathers missing. Re-run this script to fill gaps (resumable).\n",
              n_total - length(final_files)))
} else {
  cat("\n  [OK] All expected feathers present.\n")
  cat("  Next step: run scripts/raking/ne25/36_store_bootstrap_weights_long.R\n")
}

cat("\n")

# ============================================================================
# run_one_bootstrap_fit — Single (m, b) Bayesian-bootstrap Stan refit worker
# ============================================================================
#
# Invoked via callr::r() from the Bucket 3 orchestrator (script 35). Each call
# runs one Stan optimization with a Dirichlet(1, 1, ..., 1) draw as the
# per-observation prior concentration (Bayesian bootstrap) and a baseline
# simplex vector as the init (warm-start).
#
# Produces a single feather at output_dir/weights_m{m}_b{b}.feather so the
# orchestrator can resume after interruption by skipping any (m, b) pair whose
# output already exists.
#
# Arguments:
#   m, b                   Integers identifying (imputation, bootstrap draw)
#   seed                   Integer for reproducibility of the Dirichlet draw
#   harmonized_dir         Directory holding ne25_harmonized_m{m}.feather files
#   unified_moments_file   Path to unified_moments.rds (shared across all m, b)
#   baseline_wgt_raw_file  Path to an RDS containing a named list:
#                          list("1" = numeric N-vector on simplex scale, ...,
#                               "5" = numeric N-vector)
#                          Produced by the orchestrator from the 5 baseline
#                          (flat-prior) fits.
#   output_dir             Where to write weights_m{m}_b{b}.feather
#   wrapper_file           Path to calibrate_weights_simplex_factorized_cmdstan.R
#   history_size, iter     Stan L-BFGS tuning; defaults match production
#   min_weight, max_weight Hard weight bounds; defaults match production
#
# Returns (compact, small enough for callr IPC):
#   list(m, b, output_path, kish_n, weight_ratio, stan_ok)
# ============================================================================

run_one_bootstrap_fit <- function(m, b,
                                  seed,
                                  harmonized_dir,
                                  unified_moments_file,
                                  baseline_wgt_raw_file,
                                  output_dir,
                                  wrapper_file,
                                  history_size = 50,
                                  iter = 1000,
                                  min_weight = 0.01,
                                  max_weight = 100) {

  suppressPackageStartupMessages({
    library(arrow)
    library(dplyr)
  })

  # Source the Stan wrapper (fresh R process has no cached sources)
  source(wrapper_file)

  # -------------------------------------------------------------------------
  # Load inputs
  # -------------------------------------------------------------------------
  harmonized_path <- file.path(
    harmonized_dir, sprintf("ne25_harmonized_m%d.feather", m)
  )
  if (!file.exists(harmonized_path)) {
    stop(sprintf("Harmonized file not found: %s", harmonized_path))
  }
  ne25 <- arrow::read_feather(harmonized_path)
  N <- nrow(ne25)

  unified <- readRDS(unified_moments_file)

  baseline_list <- readRDS(baseline_wgt_raw_file)
  baseline_key  <- as.character(m)
  if (!baseline_key %in% names(baseline_list)) {
    stop(sprintf("Baseline wgt_raw for m=%d not found in %s",
                 m, baseline_wgt_raw_file))
  }
  baseline_wgt_raw <- baseline_list[[baseline_key]]
  if (length(baseline_wgt_raw) != N) {
    stop(sprintf("Baseline wgt_raw length (%d) != N (%d) for m=%d",
                 length(baseline_wgt_raw), N, m))
  }

  # -------------------------------------------------------------------------
  # Draw Bayesian-bootstrap concentration vector.
  #
  # Classical Bayesian bootstrap draws w ~ Dirichlet(1,...,1) and uses w as
  # *data weights*. Here we adapt it by using (1 + wb_b) as the Dirichlet
  # prior concentration on wgt_raw: the +1 shift keeps every alpha_i >= 1,
  # avoiding the log-prior boundary singularity that arises when any alpha
  # is < 1. This preserves the per-observation bootstrap perturbation while
  # keeping the optimization numerically stable. Mean concentration = 2
  # (vs. the flat-prior concentration of 1).
  #
  # If the bootstrap-variance magnitude comes out too small, the +1 offset
  # can be tuned (smaller offset => more spread, but risk of instability).
  # -------------------------------------------------------------------------
  set.seed(seed)
  g     <- rexp(N, rate = 1)
  wb_b  <- (g / sum(g)) * N    # classical Bayesian-bootstrap draw; mean = 1
  alpha <- 1 + wb_b            # shift up so all concentrations >= 1

  # -------------------------------------------------------------------------
  # Call Stan wrapper with Bayesian-bootstrap prior.
  #
  # NOTE: init is deliberately 0 (cold start) rather than the baseline
  # wgt_raw. Warm-starting from the baseline caused cmdstanr's constrained
  # -> unconstrained transform to blow up on boundary-adjacent wgt_raw
  # values, triggering "Fitting failed" during gradient evaluation. Cold
  # start takes longer per fit (~3 min vs ~1 min warm) but is numerically
  # robust. We keep baseline_wgt_raw loaded so a future iteration could
  # test a clipped warm-start (e.g., pmax(baseline, eps)) without a
  # worker signature change.
  # -------------------------------------------------------------------------
  result <- calibrate_weights_simplex_factorized_stan(
    data             = ne25,
    target_mean      = unified$mu,
    target_cov       = unified$Sigma,
    cov_mask         = unified$cov_mask,
    calibration_vars = unified$variable_names,
    min_weight       = min_weight,
    max_weight       = max_weight,
    dirichlet_alpha  = alpha,
    init             = 0,
    verbose          = FALSE,
    history_size     = history_size,
    refresh          = iter,   # silence per-iteration prints in callr workers
    iter             = iter
  )

  # -------------------------------------------------------------------------
  # Persist result as per-(m, b) feather for resumability
  # -------------------------------------------------------------------------
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  output_path <- file.path(
    output_dir, sprintf("weights_m%d_b%d.feather", m, b)
  )
  out_df <- ne25 %>%
    dplyr::select(pid, record_id, study_id) %>%
    dplyr::mutate(
      imputation_m      = as.integer(m),
      boot_b            = as.integer(b),
      calibrated_weight = result$calibrated_weight
    )
  arrow::write_feather(out_df, output_path)

  # -------------------------------------------------------------------------
  # Compact return summary (cheap to pass back via callr)
  # -------------------------------------------------------------------------
  list(
    m            = as.integer(m),
    b            = as.integer(b),
    output_path  = output_path,
    kish_n       = result$effective_n,
    weight_ratio = result$weight_ratio,
    stan_ok      = result$stan_terminated_normally
  )
}

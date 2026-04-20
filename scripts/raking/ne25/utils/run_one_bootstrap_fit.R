# ============================================================================
# run_one_bootstrap_fit -- Single (m, b) Bayesian-bootstrap Stan refit worker
# ============================================================================
#
# Invoked via callr::r_bg() from the Bucket 3 orchestrator (script 35).
# Each call runs one Stan optimization with:
#   - the flat Dirichlet(1,...,1) prior on wgt_raw (no gradient contribution),
#   - a Bayesian-bootstrap data weight `bbw_b` drawn from Gamma(1, 1)
#     (equivalent to Dirichlet(1,...,1) up to scale) passed as a per-obs
#     multiplier that enters the MOMENT-MATCHING LOSS (never the prior).
#
# This mirrors the NE22 pattern (C:/Users/marcu/git-repositories/
# Kidsights-Disparities-NE22/utils/utils.R::make_design_weights), where
# `wgts_mxb = optim_par * bbw_b` is the final replicate weight. In our Stan
# model the equivalent is
#   w_eff     = (wgt * bbw_b) / sum(wgt * bbw_b)
#   wgt_final = N * w_eff
# computed inside the Stan `transformed parameters` block. bbw enters the
# moment-matching loss but never the prior, so there is no Dirichlet-gradient
# singularity (the flat prior contributes nothing to the gradient).
#
# Produces a single feather at output_dir/weights_m{m}_b{b}.feather so the
# orchestrator can resume after interruption by skipping any (m, b) pair
# whose output already exists.
#
# Arguments:
#   m, b                   Integers identifying (imputation, bootstrap draw)
#   seed                   Integer for reproducibility of the bbw draw
#   harmonized_dir         Directory holding ne25_harmonized_m{m}.feather
#   unified_moments_file   Path to unified_moments.rds (shared across all m,b)
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

  # -------------------------------------------------------------------------
  # Draw Bayesian-bootstrap data weight.
  #
  # Classical Rubin (1981) Bayesian bootstrap draws w ~ Dirichlet(1,...,1)
  # on the N-simplex. Equivalently, draw g ~ Gamma(1, 1) = Exp(1) and use
  # g / sum(g). The Stan model renormalizes (w_eff = wgt .* bbw / sum(...)),
  # so the absolute scale of bbw is irrelevant -- we just need strictly
  # positive values with the right distribution shape.
  #
  # Using bbw = rexp(N, 1) directly (unnormalized) is simplest and
  # equivalent to a Dirichlet(1,...,1) draw after the Stan renormalization.
  # -------------------------------------------------------------------------
  set.seed(seed)
  bbw_b <- rexp(N, rate = 1)

  # -------------------------------------------------------------------------
  # Call Stan wrapper with Bayesian-bootstrap data weight.
  # Prior stays flat; bbw enters the moment-matching loss inside Stan.
  # Init = 0 (cold start) is safe and sufficient here.
  # -------------------------------------------------------------------------
  result <- calibrate_weights_simplex_factorized_stan(
    data             = ne25,
    target_mean      = unified$mu,
    target_cov       = unified$Sigma,
    cov_mask         = unified$cov_mask,
    calibration_vars = unified$variable_names,
    min_weight       = min_weight,
    max_weight       = max_weight,
    bbw              = bbw_b,
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

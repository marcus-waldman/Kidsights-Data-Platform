#!/usr/bin/env Rscript

#' Compute Authenticity Weights for NE25 Pipeline
#'
#' Pipeline-optimized function that assigns authenticity weights using cached
#' LOOCV distribution. Designed for integration as Step 6.5 in NE25 pipeline.
#'
#' @param data Data frame with ne25_transformed data (must include authentic flag)
#' @param rebuild_loocv Logical, force LOOCV rebuild (default: FALSE, use cache)
#' @param cache_dir Directory containing LOOCV cache files (default: "results/")
#'
#' @return Data frame with 4 new columns:
#'   - authenticity_weight: Normalized weight (1.0 for authentic, 0.42-1.96 for inauthentic)
#'   - authenticity_lz: Standardized z-score of avg_logpost
#'   - authenticity_avg_logpost: Raw log_posterior / n_items
#'   - authenticity_quintile: Quintile assignment (1-5)
#'
#' @details
#' Uses cached LOOCV distribution (2,635 authentic participants) by default.
#' Only re-computes avg_logpost for inauthentic participants (<30 sec).
#' Set rebuild_loocv=TRUE to force full LOOCV rebuild (~7 min, 16 cores).
#'
#' Weighting Strategy:
#'   - Authentic participants: weight = 1.0 (unweighted)
#'   - Inauthentic participants (5+ items): quintile-based normalized weights
#'   - Inauthentic participants (<5 items): weight = NA (insufficient data)
#'
#' Cores Configuration:
#'   - Default: floor(parallel::detectCores() / 2) for safety
#'   - Override: Set N_CORES=16 in .env file
#'
#' @examples
#' # Load data from database
#' library(duckdb)
#' con <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
#' data <- dbGetQuery(con, "SELECT * FROM ne25_transformed")
#' dbDisconnect(con)
#'
#' # Compute weights (uses cached LOOCV, ~30 sec)
#' data <- compute_authenticity_weights(data, rebuild_loocv = FALSE)
#'
#' # Force LOOCV rebuild (~7 min)
#' data <- compute_authenticity_weights(data, rebuild_loocv = TRUE)

compute_authenticity_weights <- function(data,
                                          rebuild_loocv = FALSE,
                                          cache_dir = "results/") {

  cat("\n")
  cat("================================================================================\n")
  cat("  AUTHENTICITY WEIGHTING (PIPELINE MODE)\n")
  cat("================================================================================\n")
  cat("\n")

  # Load required packages
  library(dplyr)
  library(rstan)
  library(future)
  library(furrr)
  library(progressr)

  # Set rstan options
  rstan_options(auto_write = TRUE)
  options(mc.cores = parallel::detectCores())

  # Configure parallel backend (cores)
  default_cores <- floor(parallel::detectCores() / 2)
  n_cores <- as.integer(Sys.getenv("N_CORES", default_cores))
  cat(sprintf("[Config] Using %d cores (detected %d total)\n",
              n_cores, parallel::detectCores()))
  cat(sprintf("[Config] Rebuild LOOCV: %s\n", rebuild_loocv))
  cat(sprintf("[Config] Cache directory: %s\n", cache_dir))
  cat("\n")

  # ==========================================================================
  # PHASE 1: LOAD OR BUILD LOOCV DISTRIBUTION
  # ==========================================================================

  cat("=== PHASE 1: LOOCV DISTRIBUTION ===\n\n")

  loocv_cache_file <- file.path(cache_dir, "loocv_authentic_results.rds")

  if (!rebuild_loocv && file.exists(loocv_cache_file)) {
    cat("[Cache] Loading cached LOOCV distribution...\n")
    loocv_results <- readRDS(loocv_cache_file)
    cat(sprintf("[Cache] Loaded: %d authentic participants\n", nrow(loocv_results)))

  } else {
    if (rebuild_loocv) {
      cat("[Rebuild] Forcing LOOCV rebuild (this will take ~7 minutes)...\n")
    } else {
      cat("[Rebuild] Cache not found, building LOOCV distribution...\n")
    }

    # Run full LOOCV (call the existing script)
    source("scripts/authenticity_screening/03_run_loocv.R")

    # Reload after rebuild
    loocv_results <- readRDS(loocv_cache_file)
    cat(sprintf("[Rebuild] Completed: %d authentic participants\n", nrow(loocv_results)))
  }

  # Filter to converged results
  loocv_results <- loocv_results %>%
    dplyr::filter(converged_main & converged_holdout)

  # Extract distribution parameters
  mean_authentic <- mean(loocv_results$avg_logpost, na.rm = TRUE)
  sd_authentic <- sd(loocv_results$avg_logpost, na.rm = TRUE)

  cat(sprintf("[Stats] Mean avg_logpost: %.4f\n", mean_authentic))
  cat(sprintf("[Stats] SD avg_logpost: %.4f\n", sd_authentic))

  # Extract quintile boundaries
  quintile_breaks <- quantile(loocv_results$avg_logpost,
                               probs = c(0, 0.2, 0.4, 0.6, 0.8, 1.0),
                               na.rm = TRUE)

  cat("\n[Quintiles] Boundaries (avg_logpost):\n")
  for (i in 1:5) {
    cat(sprintf("  Q%d: [%.4f, %.4f]\n",
                i, quintile_breaks[i], quintile_breaks[i+1]))
  }

  # Load eta_full lookup for authentic participants
  eta_full_file <- file.path(cache_dir, "full_model_eta_lookup.rds")
  if (!file.exists(eta_full_file)) {
    stop(paste0("Full model eta lookup not found: ", eta_full_file, "\n",
                "Run scripts/authenticity_screening/02_fit_full_model.R first."))
  }

  eta_full_lookup_authentic <- readRDS(eta_full_file)
  cat(sprintf("\n[Loaded] eta_full lookup: %d authentic participants\n",
              nrow(eta_full_lookup_authentic)))

  # ==========================================================================
  # PHASE 2: PREPARE STAN DATA FOR INAUTHENTIC
  # ==========================================================================

  cat("\n=== PHASE 2: PREPARE INAUTHENTIC DATA ===\n\n")

  # Identify inauthentic participants
  inauthentic_pids <- data %>%
    dplyr::filter(!authentic) %>%
    dplyr::pull(pid)

  cat(sprintf("[Filter] Found %d inauthentic participants\n", length(inauthentic_pids)))

  # Load stan_data_inauthentic (prepared in Phase 1)
  stan_data_file <- "data/temp/stan_data_inauthentic.rds"

  if (!file.exists(stan_data_file)) {
    stop(paste0("Stan data file not found: ", stan_data_file, "\n",
                "Run scripts/authenticity_screening/01_prepare_data.R first."))
  }

  stan_data_inauthentic <- readRDS(stan_data_file)
  inauthentic_pids_stan <- attr(stan_data_inauthentic, "pid")
  inauthentic_record_ids_stan <- attr(stan_data_inauthentic, "record_id")
  item_mapping <- attr(stan_data_inauthentic, "item_names")

  # Count items per participant
  item_counts <- table(stan_data_inauthentic$ivec)
  n_items_vec <- as.integer(item_counts)
  names(n_items_vec) <- names(item_counts)

  # Filter to participants with 5+ items
  sufficient_data_mask <- n_items_vec >= 5
  n_sufficient <- sum(sufficient_data_mask)

  cat(sprintf("[Filter] %d participants with 5+ items (sufficient for scoring)\n", n_sufficient))
  cat(sprintf("[Filter] %d participants with <5 items (insufficient, will receive NA weights)\n",
              sum(!sufficient_data_mask)))

  # ==========================================================================
  # PHASE 3: LOAD ITEM PARAMETERS FROM FULL MODEL
  # ==========================================================================

  cat("\n=== PHASE 3: LOAD ITEM PARAMETERS ===\n\n")

  # Load full model parameters (from Phase 3)
  params_file <- file.path(cache_dir, "full_model_params.rds")

  if (!file.exists(params_file)) {
    stop(paste0("Full model parameters not found: ", params_file, "\n",
                "Run scripts/authenticity_screening/02_fit_full_model.R first."))
  }

  params_full <- readRDS(params_file)

  # Extract item parameters (params_full is a list with components $tau, $beta1, $delta, $eta)
  tau_full <- params_full$tau
  beta1_full <- params_full$beta1
  delta_full <- params_full$delta

  J <- length(tau_full)

  cat(sprintf("[Loaded] Item parameters: %d items\n", J))
  cat(sprintf("[Loaded] tau range: [%.4f, %.4f]\n", min(tau_full), max(tau_full)))
  cat(sprintf("[Loaded] beta1 range: [%.4f, %.4f]\n", min(beta1_full), max(beta1_full)))
  cat(sprintf("[Loaded] delta: %.4f\n", delta_full))

  # ==========================================================================
  # PHASE 4: COMPILE HOLDOUT MODEL
  # ==========================================================================

  cat("\n=== PHASE 4: COMPILE HOLDOUT MODEL ===\n\n")

  holdout_model_file <- "models/authenticity_holdout.stan"

  if (!file.exists(holdout_model_file)) {
    stop(paste0("Holdout model not found: ", holdout_model_file))
  }

  cat("[Compile] Compiling holdout Stan model...\n")
  holdout_model <- rstan::stan_model(holdout_model_file)
  cat("[Compile] Compilation complete\n")

  # ==========================================================================
  # PHASE 5: COMPUTE LOG-POSTERIOR FOR INAUTHENTIC (PARALLEL)
  # ==========================================================================

  cat("\n=== PHASE 5: COMPUTE LOG-POSTERIOR FOR INAUTHENTIC ===\n\n")

  cat(sprintf("[Parallel] Using %d cores for inauthentic scoring\n", n_cores))

  plan(multisession, workers = n_cores)

  # Prepare holdout function
  compute_holdout_logpost <- function(i, stan_data_inauthentic, tau_full, beta1_full, delta_full, K, holdout_model) {

    # Extract participant i's data
    mask_i <- stan_data_inauthentic$ivec == i
    y_holdout <- stan_data_inauthentic$yvec[mask_i]
    j_holdout <- stan_data_inauthentic$jvec[mask_i]
    age_holdout <- stan_data_inauthentic$age[i]
    M_holdout <- length(y_holdout)

    # Skip if insufficient data
    if (M_holdout < 5) {
      return(list(
        i = i,
        sufficient_data = FALSE,
        converged = FALSE,
        log_posterior = NA_real_,
        avg_logpost = NA_real_,
        n_items = M_holdout,
        authenticity_eta_full = NA_real_,
        authenticity_eta_holdout = NA_real_
      ))
    }

    # Prepare Stan data
    stan_data_holdout <- list(
      J = length(tau_full),
      tau = tau_full,
      beta1 = beta1_full,
      delta = delta_full,
      K = K,
      M_holdout = M_holdout,
      j_holdout = j_holdout,
      y_holdout = y_holdout,
      age_holdout = age_holdout
    )

    # Fit holdout model
    fit_holdout <- rstan::optimizing(
      object = holdout_model,
      data = stan_data_holdout,
      seed = 54321 + i,
      iter = 10000,
      algorithm = "LBFGS",
      verbose = FALSE
    )

    # Check convergence
    converged <- !is.null(fit_holdout$return_code) &&
                 length(fit_holdout$return_code) > 0 &&
                 fit_holdout$return_code == 0

    if (!converged) {
      return(list(
        i = i,
        sufficient_data = TRUE,
        converged = FALSE,
        log_posterior = NA_real_,
        avg_logpost = NA_real_,
        n_items = M_holdout,
        authenticity_eta_full = NA_real_,
        authenticity_eta_holdout = NA_real_
      ))
    }

    # Extract results
    log_posterior <- fit_holdout$par["log_posterior"]
    eta_est <- fit_holdout$par["eta_holdout"]
    avg_logpost <- log_posterior / M_holdout

    return(list(
      i = i,
      sufficient_data = TRUE,
      converged = TRUE,
      log_posterior = log_posterior,
      avg_logpost = avg_logpost,
      n_items = M_holdout,
      authenticity_eta_full = eta_est,       # Same as holdout for inauthentic
      authenticity_eta_holdout = eta_est     # Estimated using full model params
    ))
  }

  # Run in parallel with progress bar
  with_progress({
    p <- progressor(steps = length(unique(stan_data_inauthentic$ivec)))

    inauthentic_results <- future_map(
      unique(stan_data_inauthentic$ivec),
      function(i) {
        result <- compute_holdout_logpost(i, stan_data_inauthentic, tau_full, beta1_full, delta_full,
                                           stan_data_inauthentic$K, holdout_model)
        result$pid <- inauthentic_pids_stan[i]  # Add PID and record_id while i is in scope
        result$record_id <- inauthentic_record_ids_stan[i]
        p()
        return(result)
      },
      .options = furrr_options(seed = TRUE)
    )
  })

  # Convert to data frame
  inauthentic_df <- dplyr::bind_rows(inauthentic_results)

  cat(sprintf("\n[Results] %d participants scored\n", nrow(inauthentic_df)))
  cat(sprintf("[Results] %d converged (%.1f%%)\n",
              sum(inauthentic_df$converged),
              100 * mean(inauthentic_df$converged)))
  cat(sprintf("[Results] %d with sufficient data (5+ items)\n",
              sum(inauthentic_df$sufficient_data)))

  # ==========================================================================
  # PHASE 6: ASSIGN WEIGHTS
  # ==========================================================================

  cat("\n=== PHASE 6: ASSIGN WEIGHTS ===\n\n")

  # Filter to sufficient + converged
  inauthentic_scored <- inauthentic_df %>%
    dplyr::filter(sufficient_data & converged)

  cat(sprintf("[Weights] %d inauthentic participants eligible for weighting\n",
              nrow(inauthentic_scored)))

  # Standardize lz
  inauthentic_scored <- inauthentic_scored %>%
    dplyr::mutate(
      lz = (avg_logpost - mean_authentic) / sd_authentic
    )

  # Assign quintiles
  inauthentic_scored$quintile <- cut(inauthentic_scored$avg_logpost,
                                      breaks = quintile_breaks,
                                      labels = 1:5,
                                      include.lowest = TRUE)

  # Calculate propensity scores
  authentic_counts <- loocv_results %>%
    dplyr::mutate(quintile = cut(avg_logpost, breaks = quintile_breaks, labels = 1:5, include.lowest = TRUE)) %>%
    dplyr::count(quintile, name = "n_authentic")

  inauthentic_counts <- inauthentic_scored %>%
    dplyr::count(quintile, name = "n_inauthentic")

  quintile_propensities <- dplyr::full_join(authentic_counts, inauthentic_counts, by = "quintile") %>%
    tidyr::replace_na(list(n_inauthentic = 0)) %>%
    dplyr::mutate(
      total = n_authentic + n_inauthentic,
      propensity = n_authentic / total
    )

  # Assign raw ATT weights
  inauthentic_scored <- inauthentic_scored %>%
    dplyr::left_join(quintile_propensities %>% dplyr::select(quintile, propensity), by = "quintile") %>%
    dplyr::mutate(
      authenticity_weight_raw = propensity / (1 - propensity)
    )

  # Normalize weights to sum to N_inauthentic
  n_inauthentic <- nrow(inauthentic_scored)
  inauthentic_scored <- inauthentic_scored %>%
    dplyr::mutate(
      authenticity_weight = authenticity_weight_raw * (n_inauthentic / sum(authenticity_weight_raw))
    )

  cat(sprintf("[Weights] Sum of weights: %.2f (target: %d)\n",
              sum(inauthentic_scored$authenticity_weight), n_inauthentic))
  cat(sprintf("[Weights] Weight range: [%.4f, %.4f]\n",
              min(inauthentic_scored$authenticity_weight),
              max(inauthentic_scored$authenticity_weight)))

  # ==========================================================================
  # PHASE 7: MERGE WEIGHTS BACK TO DATA
  # ==========================================================================

  cat("\n=== PHASE 7: MERGE WEIGHTS TO DATA ===\n\n")

  # Prepare eta lookup for inauthentic participants
  inauthentic_eta_lookup <- inauthentic_scored %>%
    dplyr::select(pid, record_id, authenticity_eta_full, authenticity_eta_holdout)

  # Load safe_left_join
  source("R/utils/safe_joins.R")

  # MERGE ORDER: Authentic LOOCV scores FIRST, then inauthentic weights
  # (to avoid column collision - both have avg_logpost and lz)

  # Prepare authentic LOOCV scores lookup
  cat("[Merging] LOOCV scores (avg_logpost, lz) for authentic participants...\n")
  authentic_loocv_lookup <- loocv_results %>%
    dplyr::filter(converged_holdout == TRUE) %>%
    dplyr::select(pid, record_id, avg_logpost, lz) %>%
    dplyr::rename(
      authenticity_avg_logpost = avg_logpost,
      authenticity_lz = lz
    )

  # Merge authentic LOOCV scores FIRST
  data <- data %>%
    safe_left_join(authentic_loocv_lookup, by_vars = c("pid", "record_id"),
                   allow_collision = FALSE, auto_fix = TRUE)

  cat(sprintf("  Merged LOOCV scores for %d authentic participants\n",
              nrow(authentic_loocv_lookup)))

  # Prepare inauthentic weight lookup (weights and scores)
  weight_lookup <- inauthentic_scored %>%
    dplyr::select(pid, record_id, authenticity_weight, lz, avg_logpost, quintile) %>%
    dplyr::rename(
      authenticity_lz = lz,
      authenticity_avg_logpost = avg_logpost,
      authenticity_quintile = quintile
    )

  # Merge inauthentic weights and scores (allow collision since columns already exist for authentic)
  cat("[Merging] Weights and scores for inauthentic participants...\n")
  data <- data %>%
    safe_left_join(weight_lookup, by_vars = c("pid", "record_id"),
                   allow_collision = TRUE, auto_fix = FALSE)

  # Coalesce .x and .y columns (keep authentic .x values, use inauthentic .y values)
  # Note: authenticity_weight and authenticity_quintile only exist as .y (no collision)
  data <- data %>%
    dplyr::mutate(
      authenticity_lz = dplyr::coalesce(authenticity_lz.x, authenticity_lz.y),
      authenticity_avg_logpost = dplyr::coalesce(authenticity_avg_logpost.x, authenticity_avg_logpost.y)
    ) %>%
    dplyr::select(-authenticity_lz.x, -authenticity_lz.y,
                  -authenticity_avg_logpost.x, -authenticity_avg_logpost.y)

  # Assign weight = 1.0 for authentic participants (keep their LOOCV lz values)
  data <- data %>%
    dplyr::mutate(
      authenticity_weight = ifelse(authentic, 1.0, authenticity_weight)
    )

  # Calculate quintiles for ALL participants based on authentic LOOCV distribution
  cat("[Computing] Quintiles for all participants based on LOOCV distribution...\n")
  quintile_breaks <- quantile(loocv_results$avg_logpost[loocv_results$converged_holdout],
                               probs = seq(0, 1, 0.2), na.rm = TRUE)

  data <- data %>%
    dplyr::mutate(
      authenticity_quintile = dplyr::case_when(
        is.na(authenticity_avg_logpost) ~ NA_integer_,
        authenticity_avg_logpost <= quintile_breaks[2] ~ 1L,
        authenticity_avg_logpost <= quintile_breaks[3] ~ 2L,
        authenticity_avg_logpost <= quintile_breaks[4] ~ 3L,
        authenticity_avg_logpost <= quintile_breaks[5] ~ 4L,
        TRUE ~ 5L
      )
    )

  # Merge eta values for ALL participants (authentic + inauthentic)
  cat("\n[Merging] eta_full for all participants...\n")

  # Combine eta_full from authentic (full model) and inauthentic (holdout model)
  eta_full_combined <- dplyr::bind_rows(
    eta_full_lookup_authentic,  # 2,635 authentic from full model
    inauthentic_eta_lookup %>% dplyr::select(pid, record_id, authenticity_eta_full)  # 196 inauthentic
  )

  data <- data %>%
    safe_left_join(
      eta_full_combined,
      by_vars = c("pid", "record_id"),
      allow_collision = FALSE,
      auto_fix = TRUE
    )

  cat(sprintf("  Merged %d eta_full values\n", sum(!is.na(data$authenticity_eta_full))))

  # Merge eta_holdout for all participants
  cat("[Merging] eta_holdout for all participants...\n")

  # Combine eta_holdout from authentic (LOOCV) and inauthentic (same as eta_full)
  loocv_eta_lookup <- loocv_results %>%
    dplyr::select(pid, record_id, authenticity_eta_holdout)

  eta_holdout_combined <- dplyr::bind_rows(
    loocv_eta_lookup,  # 2,635 authentic from LOOCV
    inauthentic_eta_lookup %>% dplyr::select(pid, record_id, authenticity_eta_holdout)  # 196 inauthentic
  )

  data <- data %>%
    safe_left_join(
      eta_holdout_combined,
      by_vars = c("pid", "record_id"),
      allow_collision = FALSE,
      auto_fix = TRUE
    )

  cat(sprintf("  Merged %d eta_holdout values\n", sum(!is.na(data$authenticity_eta_holdout))))

  # Convert quintile to integer
  data$authenticity_quintile <- as.integer(data$authenticity_quintile)

  # Summary
  n_authentic <- sum(data$authentic, na.rm = TRUE)
  n_inauthentic_weighted <- sum(!data$authentic & !is.na(data$authenticity_weight), na.rm = TRUE)
  n_inauthentic_na <- sum(!data$authentic & is.na(data$authenticity_weight), na.rm = TRUE)

  cat(sprintf("[Merge] Authentic participants: %d (weight = 1.0)\n", n_authentic))
  cat(sprintf("[Merge] Inauthentic with weights: %d (range: %.2f - %.2f)\n",
              n_inauthentic_weighted,
              min(data$authenticity_weight[!data$authentic & !is.na(data$authenticity_weight)], na.rm = TRUE),
              max(data$authenticity_weight[!data$authentic & !is.na(data$authenticity_weight)], na.rm = TRUE)))
  cat(sprintf("[Merge] Inauthentic with NA weights: %d (<5 items)\n", n_inauthentic_na))

  # Eta and LOOCV summary
  n_eta_full <- sum(!is.na(data$authenticity_eta_full), na.rm = TRUE)
  n_eta_holdout <- sum(!is.na(data$authenticity_eta_holdout), na.rm = TRUE)
  n_loocv_scores <- sum(!is.na(data$authenticity_avg_logpost), na.rm = TRUE)
  n_expected_eta <- n_authentic + n_inauthentic_weighted  # 2,635 + 196 = 2,831
  cat(sprintf("\n[Eta] authenticity_eta_full: %d records (expected: %d)\n", n_eta_full, n_expected_eta))
  cat(sprintf("[Eta] authenticity_eta_holdout: %d records (expected: %d)\n", n_eta_holdout, n_expected_eta))
  cat(sprintf("[LOOCV] authenticity_avg_logpost & authenticity_lz: %d records\n", n_loocv_scores))

  # Quintile distribution
  quintile_counts <- table(data$authenticity_quintile, useNA = "ifany")
  cat("\n[Quintiles] Distribution across all participants:\n")
  for(q in 1:5) {
    count <- ifelse(as.character(q) %in% names(quintile_counts), quintile_counts[as.character(q)], 0)
    cat(sprintf("  Q%d: %d participants\n", q, count))
  }

  # ==========================================================================
  # SUMMARY
  # ==========================================================================

  cat("\n")
  cat("================================================================================\n")
  cat("  AUTHENTICITY WEIGHTS COMPUTED\n")
  cat("================================================================================\n")
  cat("\n")

  cat("Columns Added:\n")
  cat("  - authenticity_weight: Normalized weight (1.0 for authentic, 0.42-1.96 for inauthentic)\n")
  cat("  - authenticity_avg_logpost: Out-of-sample log_posterior / n_items (from LOOCV for all)\n")
  cat("  - authenticity_lz: Standardized z-score of avg_logpost (from LOOCV distribution)\n")
  cat("  - authenticity_quintile: Quintile assignment (1-5) based on LOOCV distribution\n")
  cat("  - authenticity_eta_full: Individual ability from full N=2,635 model\n")
  cat("    * Authentic: from joint full model | Inauthentic: from holdout with full params\n")
  cat("  - authenticity_eta_holdout: Individual ability from holdout models\n")
  cat("    * Authentic: from LOO (N-1 model) | Inauthentic: same as eta_full\n")
  cat("\n")

  cat("Next Steps:\n")
  cat("  - Create meets_inclusion column: (eligible == TRUE & !is.na(authenticity_weight))\n")
  cat("  - Store in database: ne25_transformed table\n")
  cat("\n")

  return(data)
}

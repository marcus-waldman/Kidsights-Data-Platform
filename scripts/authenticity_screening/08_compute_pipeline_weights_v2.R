#!/usr/bin/env Rscript

#' Compute Authenticity Weights for NE25 Pipeline (Version 2 - Cached Results)
#'
#' Streamlined version that loads all cached authenticity metrics and merges
#' them into the pipeline data. No re-computation - uses pre-computed results.
#'
#' @param data Data frame with ne25_transformed data (must include authentic flag)
#' @param cache_dir Directory containing cached results (default: "results/")
#'
#' @return Data frame with 12 authenticity columns:
#'   - authenticity_weight: Normalized weight (1.0 or 0.42-1.96 or NA)
#'   - authenticity_lz: Standardized z-score
#'   - authenticity_avg_logpost: Per-item log-posterior
#'   - authenticity_quintile: Quintile (1-5)
#'   - authenticity_eta_psychosocial_full: Dimension 1, full model
#'   - authenticity_eta_developmental_full: Dimension 2, full model
#'   - authenticity_eta_psychosocial_holdout: Dimension 1, LOOCV/holdout
#'   - authenticity_eta_developmental_holdout: Dimension 2, LOOCV/holdout
#'   - authenticity_cooks_d: Raw Cook's D
#'   - authenticity_cooks_d_scaled: D×N (sample-size invariant)
#'   - authenticity_influential_4: D×N > 4
#'   - authenticity_influential_N: D×N > N
#'
#' @details
#' Requires pre-computed cache files (run pipeline first):
#'   - results/loocv_cooks_d.rds (from 03_run_loocv.R)
#'   - results/inauthentic_cooks_d.rds (from 05_compute_inauthentic_cooks_d.R)
#'   - results/full_model_eta_lookup.rds (from 03_run_loocv.R)
#'   - results/loocv_distribution_params.rds (from 03_run_loocv.R)

compute_authenticity_weights <- function(data, cache_dir = "results/") {

  cat("\n")
  cat("================================================================================\n")
  cat("  AUTHENTICITY WEIGHTING (PIPELINE MODE - V2)\n")
  cat("================================================================================\n")
  cat("\n")

  # Load required packages
  library(dplyr)
  source("R/utils/safe_joins.R")

  # ==========================================================================
  # PHASE 1: LOAD CACHED RESULTS
  # ==========================================================================

  cat("=== PHASE 1: LOAD CACHED RESULTS ===\n\n")

  # Load authentic LOOCV + Cook's D
  loocv_cooks_file <- file.path(cache_dir, "loocv_cooks_d.rds")
  if (!file.exists(loocv_cooks_file)) {
    stop(paste0("Authentic Cook's D not found: ", loocv_cooks_file, "\n",
                "Run scripts/authenticity_screening/03_run_loocv.R first."))
  }

  loocv_cooks_d <- readRDS(loocv_cooks_file)
  cat(sprintf("[Loaded] loocv_cooks_d.rds: %d authentic participants\n", nrow(loocv_cooks_d)))

  # Load inauthentic Cook's D
  inauth_cooks_file <- file.path(cache_dir, "inauthentic_cooks_d.rds")
  if (!file.exists(inauth_cooks_file)) {
    stop(paste0("Inauthentic Cook's D not found: ", inauth_cooks_file, "\n",
                "Run scripts/authenticity_screening/05_compute_inauthentic_cooks_d.R first."))
  }

  inauth_cooks_d <- readRDS(inauth_cooks_file)
  cat(sprintf("[Loaded] inauthentic_cooks_d.rds: %d inauthentic participants\n", nrow(inauth_cooks_d)))

  # Load full model 2D eta lookup (authentic full + holdout)
  eta_lookup_file <- file.path(cache_dir, "full_model_eta_lookup.rds")
  if (!file.exists(eta_lookup_file)) {
    stop(paste0("Eta lookup not found: ", eta_lookup_file, "\n",
                "Run scripts/authenticity_screening/03_run_loocv.R first."))
  }

  eta_lookup <- readRDS(eta_lookup_file)
  cat(sprintf("[Loaded] full_model_eta_lookup.rds: %d authentic participants (4 eta columns)\n",
              nrow(eta_lookup)))

  # Load LOOCV distribution parameters
  dist_params_file <- file.path(cache_dir, "loocv_distribution_params.rds")
  if (!file.exists(dist_params_file)) {
    stop(paste0("Distribution params not found: ", dist_params_file, "\n",
                "Run scripts/authenticity_screening/03_run_loocv.R first."))
  }

  dist_params <- readRDS(dist_params_file)
  mean_authentic <- dist_params$mean_avg_logpost
  sd_authentic <- dist_params$sd_avg_logpost

  cat(sprintf("\n[Distribution] Authentic LOOCV: mean=%.4f, sd=%.4f\n",
              mean_authentic, sd_authentic))

  # ==========================================================================
  # PHASE 2: PREPARE AUTHENTIC METRICS
  # ==========================================================================

  cat("\n=== PHASE 2: PREPARE AUTHENTIC METRICS ===\n\n")

  # Extract authentic metrics (lz, avg_logpost, Cook's D from LOOCV)
  authentic_metrics <- loocv_cooks_d %>%
    dplyr::filter(converged_main & converged_holdout) %>%
    dplyr::select(
      pid, record_id,
      avg_logpost, lz,
      authenticity_eta_psychosocial_holdout,
      authenticity_eta_developmental_holdout,
      cooks_d, cooks_d_scaled,
      influential_4, influential_N
    ) %>%
    dplyr::rename(
      authenticity_avg_logpost = avg_logpost,
      authenticity_lz = lz,
      authenticity_cooks_d = cooks_d,
      authenticity_cooks_d_scaled = cooks_d_scaled,
      authenticity_influential_4 = influential_4,
      authenticity_influential_N = influential_N
    )

  cat(sprintf("[Prepared] Authentic metrics: %d participants\n", nrow(authentic_metrics)))

  # Merge authentic full model 2D eta
  authentic_metrics <- authentic_metrics %>%
    safe_left_join(
      eta_lookup %>% dplyr::select(pid, record_id,
                                     authenticity_eta_psychosocial_full,
                                     authenticity_eta_developmental_full),
      by_vars = c("pid", "record_id"),
      allow_collision = FALSE
    )

  # ==========================================================================
  # PHASE 3: PREPARE INAUTHENTIC METRICS
  # ==========================================================================

  cat("\n=== PHASE 3: PREPARE INAUTHENTIC METRICS ===\n\n")

  # Inauthentic metrics already have everything we need (2D eta + Cook's D)
  # Just need to add lz and rename columns
  inauthentic_metrics <- inauth_cooks_d %>%
    dplyr::mutate(
      # Calculate lz using authentic LOOCV distribution
      # But first need avg_logpost - get from inauthentic_logpost_results.rds
      authenticity_lz = NA_real_,  # Will populate after loading logpost results
      authenticity_avg_logpost = NA_real_
    ) %>%
    dplyr::select(
      pid, record_id,
      n_items,
      cooks_d, cooks_d_scaled,
      influential_4, influential_N,
      authenticity_eta_psychosocial_full,
      authenticity_eta_developmental_full,
      authenticity_eta_psychosocial_holdout,
      authenticity_eta_developmental_holdout,
      authenticity_lz,  # Will populate
      authenticity_avg_logpost  # Will populate
    ) %>%
    dplyr::rename(
      authenticity_cooks_d = cooks_d,
      authenticity_cooks_d_scaled = cooks_d_scaled,
      authenticity_influential_4 = influential_4,
      authenticity_influential_N = influential_N
    )

  # Load inauthentic logpost results for avg_logpost and lz
  inauth_logpost_file <- file.path(cache_dir, "inauthentic_logpost_results.rds")
  if (file.exists(inauth_logpost_file)) {
    inauth_logpost <- readRDS(inauth_logpost_file)

    # Merge avg_logpost and lz from logpost results
    inauthentic_metrics <- inauthentic_metrics %>%
      safe_left_join(
        inauth_logpost %>%
          dplyr::select(pid, record_id, avg_logpost, lz) %>%
          dplyr::rename(
            avg_logpost_tmp = avg_logpost,
            lz_tmp = lz
          ),
        by_vars = c("pid", "record_id"),
        allow_collision = FALSE
      ) %>%
      dplyr::mutate(
        authenticity_avg_logpost = dplyr::coalesce(authenticity_avg_logpost, avg_logpost_tmp),
        authenticity_lz = dplyr::coalesce(authenticity_lz, lz_tmp)
      ) %>%
      dplyr::select(-avg_logpost_tmp, -lz_tmp)

    cat(sprintf("[Loaded] inauthentic_logpost_results.rds: merged avg_logpost and lz\n"))
  } else {
    warning("inauthentic_logpost_results.rds not found - lz and avg_logpost will be NA for inauthentic")
  }

  cat(sprintf("[Prepared] Inauthentic metrics: %d participants\n", nrow(inauthentic_metrics)))

  # ==========================================================================
  # PHASE 4: COMPUTE WEIGHTS AND QUINTILES
  # ==========================================================================

  cat("\n=== PHASE 4: COMPUTE WEIGHTS AND QUINTILES ===\n\n")

  # Quintile breaks from authentic LOOCV distribution
  quintile_breaks <- quantile(loocv_cooks_d$avg_logpost[loocv_cooks_d$converged_main & loocv_cooks_d$converged_holdout],
                               probs = seq(0, 1, 0.2), na.rm = TRUE)

  cat("[Quintiles] Boundaries (avg_logpost):\n")
  for (i in 1:5) {
    cat(sprintf("  Q%d: [%.4f, %.4f]\n", i, quintile_breaks[i], quintile_breaks[i+1]))
  }

  # Compute quintiles for ALL participants
  compute_quintile <- function(avg_logpost) {
    dplyr::case_when(
      is.na(avg_logpost) ~ NA_integer_,
      avg_logpost <= quintile_breaks[2] ~ 1L,
      avg_logpost <= quintile_breaks[3] ~ 2L,
      avg_logpost <= quintile_breaks[4] ~ 3L,
      avg_logpost <= quintile_breaks[5] ~ 4L,
      TRUE ~ 5L
    )
  }

  authentic_metrics <- authentic_metrics %>%
    dplyr::mutate(
      authenticity_quintile = compute_quintile(authenticity_avg_logpost),
      authenticity_weight = 1.0  # All authentic get weight = 1.0
    )

  inauthentic_metrics <- inauthentic_metrics %>%
    dplyr::mutate(
      authenticity_quintile = compute_quintile(authenticity_avg_logpost)
    )

  # Compute quintile-based weights for inauthentic (only those with >=5 items)
  # Count authentic participants in each quintile
  quintile_counts <- table(authentic_metrics$authenticity_quintile)

  # Normalized weights: w_q = (N_q / N_total) / (n_q_inauth / n_total_inauth)
  inauthentic_metrics <- inauthentic_metrics %>%
    dplyr::mutate(
      authenticity_weight = dplyr::case_when(
        n_items < 5 ~ NA_real_,  # Insufficient data
        is.na(authenticity_quintile) ~ NA_real_,
        TRUE ~ {
          N_total <- sum(quintile_counts)
          n_total_inauth <- sum(n_items >= 5 & !is.na(authenticity_quintile))
          N_q <- quintile_counts[as.character(authenticity_quintile)]
          n_q_inauth <- table(authenticity_quintile[n_items >= 5])[as.character(authenticity_quintile)]

          (N_q / N_total) / (n_q_inauth / n_total_inauth)
        }
      )
    )

  cat(sprintf("\n[Weights] Authentic: all get weight = 1.0\n"))
  cat(sprintf("[Weights] Inauthentic: quintile-based (range: %.2f - %.2f)\n",
              min(inauthentic_metrics$authenticity_weight, na.rm = TRUE),
              max(inauthentic_metrics$authenticity_weight, na.rm = TRUE)))

  # ==========================================================================
  # PHASE 5: MERGE ALL METRICS TO DATA
  # ==========================================================================

  cat("\n=== PHASE 5: MERGE TO DATA ===\n\n")

  # Combine authentic and inauthentic metrics
  all_metrics <- dplyr::bind_rows(authentic_metrics, inauthentic_metrics)

  cat(sprintf("[Combined] Total metrics: %d participants\n", nrow(all_metrics)))

  # Merge into data
  data <- data %>%
    safe_left_join(
      all_metrics,
      by_vars = c("pid", "record_id"),
      allow_collision = FALSE,
      auto_fix = TRUE
    )

  # Summary
  n_authentic <- sum(data$authentic, na.rm = TRUE)
  n_inauthentic_weighted <- sum(!data$authentic & !is.na(data$authenticity_weight), na.rm = TRUE)
  n_inauthentic_na <- sum(!data$authentic & is.na(data$authenticity_weight), na.rm = TRUE)

  cat(sprintf("\n[Merge] Authentic participants: %d (weight = 1.0)\n", n_authentic))
  cat(sprintf("[Merge] Inauthentic with weights: %d (range: %.2f - %.2f)\n",
              n_inauthentic_weighted,
              min(data$authenticity_weight[!data$authentic & !is.na(data$authenticity_weight)], na.rm = TRUE),
              max(data$authenticity_weight[!data$authentic & !is.na(data$authenticity_weight)], na.rm = TRUE)))
  cat(sprintf("[Merge] Inauthentic with NA weights: %d (<5 items)\n", n_inauthentic_na))

  # ==========================================================================
  # SUMMARY
  # ==========================================================================

  cat("\n")
  cat("================================================================================\n")
  cat("  AUTHENTICITY WEIGHTS COMPUTED\n")
  cat("================================================================================\n")
  cat("\n")

  cat("Columns Added (12 total):\n")
  cat("  - authenticity_weight: Normalized weight (1.0 or 0.42-1.96 or NA)\n")
  cat("  - authenticity_lz: Standardized z-score\n")
  cat("  - authenticity_avg_logpost: Per-item log-posterior\n")
  cat("  - authenticity_quintile: Quintile (1-5)\n")
  cat("  - authenticity_eta_psychosocial_full: Dimension 1, full model\n")
  cat("  - authenticity_eta_developmental_full: Dimension 2, full model\n")
  cat("  - authenticity_eta_psychosocial_holdout: Dimension 1, LOOCV/holdout\n")
  cat("  - authenticity_eta_developmental_holdout: Dimension 2, LOOCV/holdout\n")
  cat("  - authenticity_cooks_d: Raw Cook's D\n")
  cat("  - authenticity_cooks_d_scaled: D×N (sample-size invariant)\n")
  cat("  - authenticity_influential_4: D×N > 4\n")
  cat("  - authenticity_influential_N: D×N > N\n")
  cat("\n")

  cat("Next Steps:\n")
  cat("  - Create meets_inclusion: (eligible == TRUE & !is.na(authenticity_weight))\n")
  cat("  - Store in database: ne25_transformed table\n")
  cat("\n")

  return(data)
}

#!/usr/bin/env Rscript

#' Compute Normalized Authenticity Weights via Quintile-Based Balancing
#'
#' Uses inverse propensity treatment weighting (IPTW) to construct
#' continuous authenticity weights for inauthentic participants, normalized
#' to maintain the original sample size.
#'
#' Approach:
#'   1. Stratify authentic LOOCV distribution into quintiles (avg_logpost)
#'   2. Calculate propensity = P(authentic | quintile)
#'   3. Assign raw weights to inauthentic: weight_raw = p / (1 - p)
#'   4. Normalize: weight = weight_raw * (N_inauthentic / sum(weight_raw))
#'
#' Interpretation:
#'   - Weights sum to original sample size (not inflated)
#'   - High weight → avg_logpost typical of authentic (authentic-like)
#'   - Low weight → avg_logpost atypical of authentic (less authentic-like)
#'   - Use for balancing on avg_logpost while preserving sample size

library(dplyr)

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY SCREENING: NORMALIZED BALANCING WEIGHTS\n")
cat("================================================================================\n")
cat("\n")

# ============================================================================
# PHASE 1: LOAD DATA
# ============================================================================

cat("=== PHASE 1: LOAD DATA ===\n\n")

cat("[Step 1/2] Loading authentic LOOCV results...\n")
authentic <- readRDS("results/loocv_authentic_results.rds") %>%
  dplyr::filter(converged_main & converged_holdout) %>%
  dplyr::mutate(authentic_flag = 1)

cat(sprintf("      Authentic: %d participants\n", nrow(authentic)))

cat("\n[Step 2/2] Loading inauthentic results...\n")
inauthentic <- readRDS("results/inauthentic_logpost_results.rds") %>%
  dplyr::filter(sufficient_data & converged) %>%
  dplyr::mutate(authentic_flag = 0)

cat(sprintf("      Inauthentic: %d participants\n", nrow(inauthentic)))

# ============================================================================
# PHASE 2: CREATE QUINTILE STRATIFICATION
# ============================================================================

cat("\n=== PHASE 2: QUINTILE STRATIFICATION ===\n\n")

cat("[Step 1/3] Computing quintile boundaries from authentic distribution...\n")

# Define quintile boundaries based on authentic distribution
quintile_breaks <- quantile(authentic$avg_logpost,
                             probs = c(0, 0.2, 0.4, 0.6, 0.8, 1.0),
                             na.rm = TRUE)

cat("      Quintile boundaries (avg_logpost):\n")
for (i in 1:5) {
  cat(sprintf("        Q%d: [%.4f, %.4f]\n",
              i, quintile_breaks[i], quintile_breaks[i+1]))
}

cat("\n[Step 2/3] Assigning quintiles to all participants...\n")

# Assign quintiles to authentic
authentic$quintile <- cut(authentic$avg_logpost,
                          breaks = quintile_breaks,
                          labels = 1:5,
                          include.lowest = TRUE)

# Assign quintiles to inauthentic
inauthentic$quintile <- cut(inauthentic$avg_logpost,
                             breaks = quintile_breaks,
                             labels = 1:5,
                             include.lowest = TRUE)

cat(sprintf("      [OK] Assigned quintiles to %d participants\n",
            nrow(authentic) + nrow(inauthentic)))

cat("\n[Step 3/3] Counting participants per quintile...\n")

# Count by quintile
quintile_counts <- dplyr::bind_rows(authentic, inauthentic) %>%
  dplyr::group_by(quintile, authentic_flag) %>%
  dplyr::summarise(n = dplyr::n(), .groups = "drop") %>%
  tidyr::pivot_wider(names_from = authentic_flag,
                     values_from = n,
                     values_fill = 0,
                     names_prefix = "n_") %>%
  dplyr::rename(n_inauthentic = n_0, n_authentic = n_1) %>%
  dplyr::mutate(
    total = n_authentic + n_inauthentic,
    pct_inauthentic = 100 * n_inauthentic / total
  )

cat("\n      Quintile distribution:\n")
cat("      ┌─────────┬──────────┬────────────┬───────┬──────────────┐\n")
cat("      │ Quintile│ Authentic│ Inauthentic│ Total │ % Inauthentic│\n")
cat("      ├─────────┼──────────┼────────────┼───────┼──────────────┤\n")
for (i in 1:nrow(quintile_counts)) {
  cat(sprintf("      │   Q%d    │  %6d  │    %6d  │ %5d │    %5.1f%%   │\n",
              as.integer(quintile_counts$quintile[i]),
              quintile_counts$n_authentic[i],
              quintile_counts$n_inauthentic[i],
              quintile_counts$total[i],
              quintile_counts$pct_inauthentic[i]))
}
cat("      └─────────┴──────────┴────────────┴───────┴──────────────┘\n")

# ============================================================================
# PHASE 3: CALCULATE PROPENSITY SCORES
# ============================================================================

cat("\n=== PHASE 3: PROPENSITY SCORE CALCULATION ===\n\n")

cat("[Step 1/2] Computing propensity scores within each quintile...\n")

# Calculate propensity: P(authentic | quintile)
quintile_counts <- quintile_counts %>%
  dplyr::mutate(
    propensity = n_authentic / total
  )

cat("\n      Propensity scores by quintile:\n")
cat("      ┌─────────┬────────────┐\n")
cat("      │ Quintile│ Propensity │\n")
cat("      ├─────────┼────────────┤\n")
for (i in 1:nrow(quintile_counts)) {
  cat(sprintf("      │   Q%d    │   %.4f   │\n",
              as.integer(quintile_counts$quintile[i]),
              quintile_counts$propensity[i]))
}
cat("      └─────────┴────────────┘\n")

cat("[Step 2/3] Computing raw ATT weights for inauthentic participants...\n")

# Merge propensity scores to inauthentic participants
inauthentic <- inauthentic %>%
  dplyr::left_join(
    quintile_counts %>% dplyr::select(quintile, propensity),
    by = "quintile"
  ) %>%
  dplyr::mutate(
    att_weight_raw = propensity / (1 - propensity)
  )

cat(sprintf("      [OK] Computed raw weights for %d inauthentic participants\n",
            nrow(inauthentic)))

cat("\n[Step 3/3] Normalizing weights to maintain original sample size...\n")

# Store original sample size
n_inauthentic <- nrow(inauthentic)

# Normalize weights so they sum to n_inauthentic (not inflated)
inauthentic <- inauthentic %>%
  dplyr::mutate(
    att_weight = att_weight_raw * (n_inauthentic / sum(att_weight_raw))
  )

cat(sprintf("      [OK] Normalized weights sum to %.2f (target: %d)\n",
            sum(inauthentic$att_weight), n_inauthentic))

# ============================================================================
# PHASE 4: WEIGHT SUMMARY STATISTICS
# ============================================================================

cat("\n=== PHASE 4: WEIGHT SUMMARY STATISTICS ===\n\n")

cat("[Step 1/1] Weight distribution for inauthentic participants...\n")

weight_summary <- inauthentic %>%
  dplyr::summarise(
    n = dplyr::n(),
    mean_weight = mean(att_weight, na.rm = TRUE),
    sd_weight = sd(att_weight, na.rm = TRUE),
    min_weight = min(att_weight, na.rm = TRUE),
    q25_weight = quantile(att_weight, 0.25, na.rm = TRUE),
    median_weight = median(att_weight, na.rm = TRUE),
    q75_weight = quantile(att_weight, 0.75, na.rm = TRUE),
    max_weight = max(att_weight, na.rm = TRUE)
  )

# Calculate sum of weights
sum_weights <- sum(inauthentic$att_weight, na.rm = TRUE)

cat("\n      Weight distribution:\n")
cat(sprintf("        N: %d\n", weight_summary$n))
cat(sprintf("        Sum of weights: %.2f (effective sample size)\n", sum_weights))
cat(sprintf("        Mean: %.4f\n", weight_summary$mean_weight))
cat(sprintf("        SD: %.4f\n", weight_summary$sd_weight))
cat(sprintf("        Min: %.4f\n", weight_summary$min_weight))
cat(sprintf("        Q1: %.4f\n", weight_summary$q25_weight))
cat(sprintf("        Median: %.4f\n", weight_summary$median_weight))
cat(sprintf("        Q3: %.4f\n", weight_summary$q75_weight))
cat(sprintf("        Max: %.4f\n", weight_summary$max_weight))

cat("\n      Weight distribution by quintile:\n")
weight_by_quintile <- inauthentic %>%
  dplyr::group_by(quintile) %>%
  dplyr::summarise(
    n = dplyr::n(),
    mean_weight = mean(att_weight, na.rm = TRUE),
    min_weight = min(att_weight, na.rm = TRUE),
    max_weight = max(att_weight, na.rm = TRUE),
    .groups = "drop"
  )

cat("      ┌─────────┬───────┬─────────────┬─────────┬─────────┐\n")
cat("      │ Quintile│   N   │  Mean Weight│   Min   │   Max   │\n")
cat("      ├─────────┼───────┼─────────────┼─────────┼─────────┤\n")
for (i in 1:nrow(weight_by_quintile)) {
  cat(sprintf("      │   Q%d    │  %3d  │    %.4f   │ %.4f  │ %.4f  │\n",
              as.integer(weight_by_quintile$quintile[i]),
              weight_by_quintile$n[i],
              weight_by_quintile$mean_weight[i],
              weight_by_quintile$min_weight[i],
              weight_by_quintile$max_weight[i]))
}
cat("      └─────────┴───────┴─────────────┴─────────┴─────────┘\n")

# ============================================================================
# PHASE 5: SAVE RESULTS
# ============================================================================

cat("\n=== PHASE 5: SAVE RESULTS ===\n\n")

cat("[Step 1/3] Saving weighted inauthentic data...\n")

saveRDS(inauthentic, "results/inauthentic_weighted.rds")
cat("      Saved: results/inauthentic_weighted.rds\n")

cat("\n[Step 2/3] Saving quintile stratification table...\n")

saveRDS(quintile_counts, "results/quintile_stratification.rds")
cat("      Saved: results/quintile_stratification.rds\n")

cat("\n[Step 3/3] Saving weight summary...\n")

weight_results <- list(
  quintile_counts = quintile_counts,
  weight_summary = weight_summary,
  weight_by_quintile = weight_by_quintile,
  quintile_breaks = quintile_breaks,
  sum_weights = sum_weights,
  n_inauthentic = nrow(inauthentic)
)

saveRDS(weight_results, "results/authenticity_weights_summary.rds")
cat("      Saved: results/authenticity_weights_summary.rds\n")

# ============================================================================
# SUMMARY
# ============================================================================

cat("\n")
cat("================================================================================\n")
cat("  AUTHENTICITY WEIGHTS COMPUTED\n")
cat("================================================================================\n")
cat("\n")

cat("Quintile Stratification:\n")
cat(sprintf("  Q1 (lowest avg_logpost): %d authentic, %d inauthentic (%.1f%% inauth)\n",
            quintile_counts$n_authentic[1], quintile_counts$n_inauthentic[1],
            quintile_counts$pct_inauthentic[1]))
cat(sprintf("  Q5 (highest avg_logpost): %d authentic, %d inauthentic (%.1f%% inauth)\n",
            quintile_counts$n_authentic[5], quintile_counts$n_inauthentic[5],
            quintile_counts$pct_inauthentic[5]))
cat("\n")

cat("Propensity Range:\n")
cat(sprintf("  Lowest: %.4f (Q with most inauthentic)\n", min(quintile_counts$propensity)))
cat(sprintf("  Highest: %.4f (Q with fewest inauthentic)\n", max(quintile_counts$propensity)))
cat("\n")

cat("Normalized Authenticity Weight Distribution (Inauthentic):\n")
cat(sprintf("  N: %d participants\n", weight_summary$n))
cat(sprintf("  Sum: %.2f (maintains original sample size)\n", sum_weights))
cat(sprintf("  Mean: %.4f\n", weight_summary$mean_weight))
cat(sprintf("  Range: [%.4f, %.4f]\n", weight_summary$min_weight, weight_summary$max_weight))
cat("\n")

cat("Interpretation:\n")
cat(sprintf("  - Weights sum to %d (original sample size, not inflated)\n", weight_summary$n))
cat("  - Higher weight → avg_logpost typical of authentic (more authentic-like)\n")
cat("  - Lower weight → avg_logpost atypical of authentic (less authentic-like)\n")
cat("  - Use weights to balance on avg_logpost while preserving sample size\n")
cat("\n")

cat("Next Steps:\n")
cat("  1. Create diagnostic plots showing weight distributions (Task 9)\n")
cat("  2. Document weighting methodology (Task 10)\n")
cat("\n")

cat("[OK] Authenticity weights computed!\n")
cat("\n")

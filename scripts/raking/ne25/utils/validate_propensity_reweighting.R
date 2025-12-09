# Validation Utilities: Propensity Reweighting Validation
# Purpose: Validate common support, covariate balance, and efficiency for NHIS/NSCH reweighting
# These functions check that propensity score reweighting is successful and valid

library(dplyr)

# Helper function to compute weighted variance
weighted_var <- function(x, w, na.rm = TRUE) {
  if (na.rm) {
    idx <- !is.na(x) & !is.na(w)
    x <- x[idx]
    w <- w[idx]
  }

  if (length(x) < 2) return(NA_real_)

  mean_x <- weighted.mean(x, w, na.rm = na.rm)
  sum(w * (x - mean_x)^2, na.rm = na.rm) / sum(w, na.rm = na.rm)
}

# ============================================================================
# Propensity Reweighting Validation
# ============================================================================

validate_propensity_reweighting <- function(source_data, acs_nebraska, source_name = "Unknown") {
  cat("\n========================================\n")
  cat("Propensity Reweighting Validation:", source_name, "\n")
  cat("========================================\n\n")

  issues <- list()

  # 1. Common support check
  cat("[1] Common support assessment:\n")

  p_min_source <- min(source_data$p_nebraska, na.rm = TRUE)
  p_max_source <- max(source_data$p_nebraska, na.rm = TRUE)
  p_min_ne <- min(acs_nebraska$p_nebraska, na.rm = TRUE)
  p_max_ne <- max(acs_nebraska$p_nebraska, na.rm = TRUE)

  cat("    Nebraska propensity score range:\n")
  cat("      Min:", round(p_min_ne, 4), "\n")
  cat("      Max:", round(p_max_ne, 4), "\n")
  cat("    ", source_name, " propensity score range:\n")
  cat("      Min:", round(p_min_source, 4), "\n")
  cat("      Max:", round(p_max_source, 4), "\n")

  # Check overlap
  if (p_min_source > p_max_ne || p_max_source < p_min_ne) {
    issues$no_overlap <- sprintf("No overlap: %s entirely outside Nebraska range", source_name)
    cat("    ✗ ERROR: No overlap in propensity score ranges!\n")
  }

  # Check if >10% of observations outside Nebraska range
  outside_range <- source_data$p_nebraska < p_min_ne | source_data$p_nebraska > p_max_ne
  pct_outside <- mean(outside_range, na.rm = TRUE) * 100

  cat("    Records outside Nebraska range:", round(pct_outside, 1), "%\n")

  if (pct_outside > 10) {
    issues$poor_overlap <- sprintf("%.1f%% of %s records outside Nebraska support", pct_outside, source_name)
    cat("    ! WARNING: >10% of records outside Nebraska support\n")
  } else {
    cat("    ✓ Good overlap (< 10% outside Nebraska support)\n")
  }

  # 2. Extreme weights check
  cat("\n[2] Weight distribution:\n")

  min_weight <- min(source_data$adjusted_weight[source_data$adjusted_weight > 0], na.rm = TRUE)
  max_weight <- max(source_data$adjusted_weight, na.rm = TRUE)
  weight_ratio <- max_weight / min_weight

  cat("    Min weight:", round(min_weight, 4), "\n")
  cat("    Max weight:", round(max_weight, 4), "\n")
  cat("    Weight ratio (max/min):", round(weight_ratio, 1), "\n")
  cat("    Mean weight:", round(mean(source_data$adjusted_weight, na.rm = TRUE), 2), "\n")
  cat("    Median weight:", round(median(source_data$adjusted_weight, na.rm = TRUE), 2), "\n")

  if (weight_ratio > 1000) {
    issues$extreme_weights <- sprintf("Extreme weight ratio: %.0f (>1000 threshold)", weight_ratio)
    cat("    ✗ WARNING: Extreme weight concentration (ratio > 1000)\n")
  } else if (weight_ratio > 500) {
    cat("    ! Note: Moderate weight concentration (ratio 500-1000)\n")
  } else {
    cat("    ✓ Acceptable weight distribution\n")
  }

  # 3. Covariate balance check
  cat("\n[3] Covariate balance (standardized differences):\n")

  vars_to_check <- c("male", "age", "white_nh", "black", "hispanic",
                     "educ_years", "married", "poverty_ratio")

  # Filter to complete cases
  complete_idx <- complete.cases(source_data[, vars_to_check]) &
                  complete.cases(acs_nebraska[, vars_to_check])

  source_complete <- source_data[complete_idx, ]
  acs_ne_complete <- acs_nebraska[complete_idx, ]

  balance_table <- data.frame(
    Variable = character(),
    Nebraska_Mean = numeric(),
    Source_Weighted_Mean = numeric(),
    Std_Diff = numeric()
  )

  for (var in vars_to_check) {
    if (!(var %in% names(source_complete)) || !(var %in% names(acs_ne_complete))) {
      next
    }

    # Nebraska weighted mean
    ne_mean <- weighted.mean(acs_ne_complete[[var]], acs_ne_complete$PERWT, na.rm = TRUE)

    # Source reweighted mean
    source_mean <- weighted.mean(source_complete[[var]], source_complete$adjusted_weight, na.rm = TRUE)

    # Standardized difference: (mean_difference) / SD_pooled
    ne_sd <- sqrt(weighted_var(acs_ne_complete[[var]], acs_ne_complete$PERWT))
    pooled_sd <- sqrt((ne_sd^2 + sqrt(weighted_var(source_complete[[var]], source_complete$adjusted_weight))^2) / 2)

    std_diff <- (source_mean - ne_mean) / pooled_sd

    balance_table <- rbind(balance_table, data.frame(
      Variable = var,
      Nebraska_Mean = round(ne_mean, 3),
      Source_Weighted_Mean = round(source_mean, 3),
      Std_Diff = round(std_diff, 3)
    ))
  }

  print(balance_table)

  # Flag if any standardized difference >0.1 (common threshold)
  max_std_diff <- max(abs(balance_table$Std_Diff), na.rm = TRUE)
  cat("\n    Max |Std Diff|:", round(max_std_diff, 3), "\n")

  if (max_std_diff > 0.20) {
    issues$poor_balance <- sprintf("Poor covariate balance (max std diff: %.3f > 0.20)", max_std_diff)
    cat("    ✗ WARNING: Poor covariate balance (max |std diff| > 0.20)\n")
  } else if (max_std_diff > 0.10) {
    cat("    ! Note: Moderate imbalance (0.10 < max |std diff| ≤ 0.20)\n")
  } else {
    cat("    ✓ Good covariate balance (all |std diff| ≤ 0.10)\n")
  }

  # Summary
  cat("\n")
  if (length(issues) == 0) {
    cat("✓ All propensity reweighting checks PASSED\n\n")
  } else {
    cat("✗ WARNING: Propensity reweighting validation issues detected:\n")
    cat("   Issues found:\n")
    for (name in names(issues)) {
      cat("   - ", issues[[name]], "\n")
    }
    cat("\n")
  }

  list(
    valid = length(issues) == 0,
    issues = issues,
    balance_table = balance_table,
    common_support = list(
      acs_range = c(p_min_ne, p_max_ne),
      source_range = c(p_min_source, p_max_source),
      pct_outside = pct_outside
    ),
    weight_diagnostics = list(
      min_weight = min_weight,
      max_weight = max_weight,
      weight_ratio = weight_ratio
    )
  )
}

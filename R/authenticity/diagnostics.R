#' Diagnostics for Authenticity Screening GLMM
#'
#' Functions to calculate person-fit statistics (lz) and compare distributions

library(dplyr)

#' Calculate lz statistic for each person
#'
#' The lz statistic standardizes the log-likelihood by its expected value
#' and standard deviation under the fitted model, making it comparable
#' across persons who answered different numbers of items.
#'
#' lz = (log_lik - E[log_lik]) / SD[log_lik]
#'
#' @param log_lik Vector of observed log-likelihoods (from Stan)
#' @param stan_data Original Stan data list
#' @param params Parameter estimates (tau, beta1, delta, sigma, eta)
#' @return Data frame with pid, log_lik, log_lik_expected, log_lik_sd, lz
#' @export
calculate_lz <- function(log_lik, stan_data, params) {

  N <- stan_data$N

  # Calculate expected log-likelihood and SD for each person
  log_lik_expected <- numeric(N)
  log_lik_sd <- numeric(N)

  for (i in 1:N) {
    # Find all observations for this person
    obs_idx <- which(stan_data$ivec == i)

    if (length(obs_idx) == 0) {
      log_lik_expected[i] <- NA
      log_lik_sd[i] <- NA
      next
    }

    # Calculate expected log-likelihood under fitted model
    # E[log p] for each response
    expected_contributions <- numeric(length(obs_idx))
    variance_contributions <- numeric(length(obs_idx))

    for (m_idx in seq_along(obs_idx)) {
      m <- obs_idx[m_idx]

      j <- stan_data$jvec[m]
      y <- stan_data$yvec[m]
      k_max <- stan_data$K[j] - 1

      # Linear predictor
      lp <- params$beta1[j] * stan_data$age[i] + params$eta[i]

      # For each possible response category, calculate probability
      probs <- numeric(k_max + 1)

      for (k in 0:k_max) {
        # Calculate thresholds
        if (k == 0) {
          tau_left <- -Inf
        } else {
          tau_left <- params$tau[j] + (k - 1) * params$delta
        }

        if (k == k_max) {
          tau_right <- Inf
        } else {
          tau_right <- params$tau[j] + k * params$delta
        }

        # Probability
        p_left <- plogis(tau_left + lp)
        p_right <- plogis(tau_right + lp)
        probs[k + 1] <- p_right - p_left
      }

      # Expected log-likelihood is sum of p * log(p)
      # (entropy-based expected value)
      expected_contributions[m_idx] <- sum(probs * log(probs + 1e-10))

      # Variance of log-likelihood
      # Var[log p(Y)] = E[log p(Y)^2] - E[log p(Y)]^2
      expected_log_sq <- sum(probs * log(probs + 1e-10)^2)
      variance_contributions[m_idx] <- expected_log_sq - expected_contributions[m_idx]^2
    }

    log_lik_expected[i] <- sum(expected_contributions)
    log_lik_sd[i] <- sqrt(sum(variance_contributions))
  }

  # Calculate lz
  lz <- (log_lik - log_lik_expected) / log_lik_sd

  # Create results data frame
  results <- data.frame(
    person_idx = 1:N,
    pid = attr(stan_data, "pid"),  # Get from attributes
    log_lik = log_lik,
    log_lik_expected = log_lik_expected,
    log_lik_sd = log_lik_sd,
    lz = lz,
    n_items_answered = sapply(1:N, function(i) sum(stan_data$ivec == i))
  )

  return(results)
}

#' Compare distributions of lz between authentic and inauthentic
#'
#' @param lz_authentic Data frame with lz for authentic participants
#' @param lz_inauthentic Data frame with lz for inauthentic participants
#' @param output_dir Directory to save plots
#' @return List with summary statistics and plots
#' @export
compare_lz_distributions <- function(lz_authentic, lz_inauthentic, output_dir = "results/plots") {

  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  # Summary statistics
  summary_stats <- list(
    authentic = list(
      n = nrow(lz_authentic),
      mean = mean(lz_authentic$lz, na.rm = TRUE),
      sd = sd(lz_authentic$lz, na.rm = TRUE),
      quantiles = quantile(lz_authentic$lz, probs = c(0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99), na.rm = TRUE)
    ),
    inauthentic = list(
      n = nrow(lz_inauthentic),
      mean = mean(lz_inauthentic$lz, na.rm = TRUE),
      sd = sd(lz_inauthentic$lz, na.rm = TRUE),
      quantiles = quantile(lz_inauthentic$lz, probs = c(0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99), na.rm = TRUE)
    )
  )

  # Print summary
  cat("\n=== LZ DISTRIBUTION COMPARISON ===\n\n")
  cat("Authentic participants (N =", summary_stats$authentic$n, "):\n")
  cat("  Mean lz:", sprintf("%.3f", summary_stats$authentic$mean), "\n")
  cat("  SD lz:", sprintf("%.3f", summary_stats$authentic$sd), "\n")
  cat("  5th percentile:", sprintf("%.3f", summary_stats$authentic$quantiles["5%"]), "\n")
  cat("  95th percentile:", sprintf("%.3f", summary_stats$authentic$quantiles["95%"]), "\n\n")

  cat("Inauthentic participants (N =", summary_stats$inauthentic$n, "):\n")
  cat("  Mean lz:", sprintf("%.3f", summary_stats$inauthentic$mean), "\n")
  cat("  SD lz:", sprintf("%.3f", summary_stats$inauthentic$sd), "\n")
  cat("  5th percentile:", sprintf("%.3f", summary_stats$inauthentic$quantiles["5%"]), "\n")
  cat("  95th percentile:", sprintf("%.3f", summary_stats$inauthentic$quantiles["95%"]), "\n")

  return(summary_stats)
}

#' Flag potential false negatives based on lz distribution
#'
#' @param lz_inauthentic Data frame with lz for inauthentic participants
#' @param lz_authentic_quantiles Quantiles from authentic LOOCV distribution
#' @param threshold_percentile Percentile threshold (default: 0.05)
#' @return Data frame with flagged participants
#' @export
flag_false_negatives <- function(lz_inauthentic,
                                  lz_authentic_quantiles,
                                  threshold_percentile = 0.05) {

  threshold_lz <- lz_authentic_quantiles[paste0(threshold_percentile * 100, "%")]

  flagged <- lz_inauthentic %>%
    dplyr::mutate(
      lz_percentile = sapply(lz, function(x) {
        mean(x >= lz_authentic_quantiles, na.rm = TRUE)
      }),
      flag_recovery = lz > threshold_lz
    ) %>%
    dplyr::arrange(dplyr::desc(lz))

  cat("\n=== FALSE NEGATIVE FLAGGING ===\n\n")
  cat("Threshold:", sprintf("%.3f", threshold_lz), "(", threshold_percentile * 100, "th percentile)\n")
  cat("Flagged participants:", sum(flagged$flag_recovery, na.rm = TRUE), "/", nrow(flagged), "\n")
  cat("Percentage flagged:", sprintf("%.1f%%", 100 * mean(flagged$flag_recovery, na.rm = TRUE)), "\n")

  return(flagged)
}

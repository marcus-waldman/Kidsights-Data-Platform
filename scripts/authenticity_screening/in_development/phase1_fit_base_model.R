# Phase 1a: Fit Base 2D IRT Model (No Weights, No Penalty)
#
# This script fits the standard 2D IRT model without authenticity screening.
# The fitted parameters (tau, beta1, delta, eta) are used as warm starts for
# the penalized models in Phase 1b.
#
# Model: authenticity_glmm_independent.stan
#   - 2D graded response model
#   - Independent person effects (no correlation)
#   - No participant weights
#   - No skewness penalty
#
# Outputs:
#   - fit0_full: Stan fit object
#   - fit0_params.rds: Extracted parameter estimates

library(rstan)
library(dplyr)

# Source utilities
source("scripts/authenticity_screening/in_development/gh_quadrature_utils.R")

#' Fit Base 2D IRT Model
#'
#' @param M_data Data frame with columns: pid, item_id, response, age
#' @param J_data Data frame with columns: item_id, K (num categories), dimension
#' @param output_dir Directory to save results (default: "output/authenticity_cv")
#' @param n_chains Number of MCMC chains (default: 4)
#' @param n_iter Number of iterations per chain (default: 2000)
#' @param n_cores Number of cores for parallel chains (default: 4)
#' @return Stan fit object
fit_base_model <- function(M_data, J_data, output_dir = "output/authenticity_cv",
                           n_chains = 4, n_iter = 2000, n_cores = 4) {

  cat("\n")
  cat("================================================================================\n")
  cat("  PHASE 1a: Fitting Base 2D IRT Model (No Penalty)\n")
  cat("================================================================================\n")
  cat("\n")

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat(sprintf("[OK] Created output directory: %s\n", output_dir))
  }

  # Get unique PIDs and map to 1:N
  unique_pids <- unique(M_data$pid)
  N <- length(unique_pids)

  pid_map <- data.frame(
    pid = unique_pids,
    new_id = 1:N
  )

  M_data$ivec <- pid_map$new_id[match(M_data$pid, pid_map$pid)]

  # Get age vector (one per person)
  age <- M_data %>%
    dplyr::group_by(ivec) %>%
    dplyr::summarise(age = dplyr::first(age), .groups = "drop") %>%
    dplyr::arrange(ivec) %>%
    dplyr::pull(age)

  # Prepare Stan data
  stan_data <- list(
    M = nrow(M_data),
    N = N,
    J = nrow(J_data),
    ivec = M_data$ivec,
    jvec = M_data$item_id,
    yvec = M_data$response,
    age = age,
    K = J_data$K,
    dimension = J_data$dimension
  )

  cat(sprintf("Data summary:\n"))
  cat(sprintf("  N = %d persons\n", stan_data$N))
  cat(sprintf("  M = %d observations\n", stan_data$M))
  cat(sprintf("  J = %d items\n", stan_data$J))
  cat(sprintf("  Age range: %.2f to %.2f years\n", min(age), max(age)))
  cat("\n")

  # Compile model (if not already compiled)
  model_file <- "models/authenticity_glmm_independent.stan"

  if (!file.exists(model_file)) {
    stop(sprintf("Model file not found: %s", model_file))
  }

  cat(sprintf("Compiling model: %s\n", model_file))
  stan_model <- rstan::stan_model(file = model_file, model_name = "base_2d_irt")
  cat("[OK] Model compiled successfully\n\n")

  # Fit model
  cat(sprintf("Fitting model (%d chains, %d iterations per chain)...\n", n_chains, n_iter))
  cat("This may take 10-30 minutes depending on data size.\n\n")

  fit_start <- Sys.time()

  fit0_full <- rstan::sampling(
    stan_model,
    data = stan_data,
    chains = n_chains,
    iter = n_iter,
    warmup = floor(n_iter / 2),
    cores = n_cores,
    refresh = 100,
    control = list(adapt_delta = 0.95, max_treedepth = 12),
    seed = 12345
  )

  fit_end <- Sys.time()
  fit_duration <- as.numeric(difftime(fit_end, fit_start, units = "mins"))

  cat("\n")
  cat(sprintf("[OK] Model fitting complete (%.1f minutes)\n", fit_duration))
  cat("\n")

  # Check convergence
  cat("Checking convergence diagnostics...\n")
  summary_fit <- rstan::summary(fit0_full)$summary
  max_rhat <- max(summary_fit[, "Rhat"], na.rm = TRUE)
  min_neff <- min(summary_fit[, "n_eff"], na.rm = TRUE)

  cat(sprintf("  Max Rhat: %.4f %s\n", max_rhat,
              ifelse(max_rhat < 1.1, "[OK]", "[WARNING: > 1.1]")))
  cat(sprintf("  Min n_eff: %.0f %s\n", min_neff,
              ifelse(min_neff > 100, "[OK]", "[WARNING: < 100]")))

  if (max_rhat > 1.1) {
    warning("Some parameters have Rhat > 1.1. Consider increasing iterations.")
  }

  cat("\n")

  # Extract parameters for warm starting
  cat("Extracting parameters for warm starting...\n")

  params <- list(
    tau = colMeans(rstan::extract(fit0_full, "tau")[[1]]),
    beta1 = colMeans(rstan::extract(fit0_full, "beta1")[[1]]),
    delta = colMeans(rstan::extract(fit0_full, "delta")[[1]]),
    eta_psychosocial = colMeans(rstan::extract(fit0_full, "eta_psychosocial")[[1]]),
    eta_developmental = colMeans(rstan::extract(fit0_full, "eta_developmental")[[1]])
  )

  # Save results
  fit_file <- file.path(output_dir, "fit0_full.rds")
  params_file <- file.path(output_dir, "fit0_params.rds")

  saveRDS(fit0_full, fit_file)
  saveRDS(params, params_file)

  cat(sprintf("[OK] Saved fit object: %s\n", fit_file))
  cat(sprintf("[OK] Saved parameters: %s\n", params_file))
  cat("\n")

  # Summary statistics
  cat("Parameter summary:\n")
  cat(sprintf("  tau: mean = %.3f, sd = %.3f, range = [%.3f, %.3f]\n",
              mean(params$tau), sd(params$tau), min(params$tau), max(params$tau)))
  cat(sprintf("  beta1: mean = %.3f, sd = %.3f, range = [%.3f, %.3f]\n",
              mean(params$beta1), sd(params$beta1), min(params$beta1), max(params$beta1)))
  cat(sprintf("  delta: [%.3f, %.3f] (psychosocial, developmental)\n",
              params$delta[1], params$delta[2]))
  cat(sprintf("  eta_psychosocial: mean = %.3f, sd = %.3f\n",
              mean(params$eta_psychosocial), sd(params$eta_psychosocial)))
  cat(sprintf("  eta_developmental: mean = %.3f, sd = %.3f\n",
              mean(params$eta_developmental), sd(params$eta_developmental)))
  cat("\n")

  cat("================================================================================\n")
  cat("  PHASE 1a COMPLETE\n")
  cat("================================================================================\n")
  cat("\n")

  return(fit0_full)
}


# Example usage (commented out - run interactively)
# M_data <- read.csv("data/responses.csv")  # Columns: pid, item_id, response, age
# J_data <- read.csv("data/items.csv")      # Columns: item_id, K, dimension
# fit0_full <- fit_base_model(M_data, J_data)

// Calibration Estimator: Pure Simplex Parameterization
// Purpose: Estimate survey weights to match population distribution
// Method: Minimize KL divergence using N-dimensional simplex for weights
//
// Mathematical form:
//   wgt[i] ~ Dirichlet(concentration)
//   wgt sums to 1, final_wgt[i] = N * wgt[i]
//
// Advantages over linear model:
// - Weights automatically sum to 1 (natural constraint)
// - Bounded: each weight in [0, 1]
// - Flexible: N parameters can match complex distributions
// - Dirichlet prior provides smoothing
//
// Trade-offs:
// - High dimensional (N parameters vs K+1)
// - Less interpretable (no demographic coefficients)
// - May overfit if N >> K

data {
  int<lower=1> N;                                 // Number of observations
  int<lower=1> K;                                 // Number of calibration variables

  matrix[N, K] X;                                 // Design matrix
  vector[K] target_mean;                          // Target mean vector
  cov_matrix[K] target_cov;                       // Target covariance matrix

  real<lower=0> concentration;                    // Dirichlet concentration parameter (1.0 = uniform)
  real<lower=0> min_weight_multiplier;            // Min weight = min_weight_multiplier / N (e.g., 0.1)
  real<lower=0> max_weight_multiplier;            // Max weight = max_weight_multiplier / N (e.g., 10.0)
}

transformed data {
  real min_wgt = min_weight_multiplier / N;       // Minimum allowed simplex weight
  real max_wgt = max_weight_multiplier / N;       // Maximum allowed simplex weight
}

parameters {
  simplex[N] wgt_raw;                             // Unconstrained simplex weights
}

transformed parameters {
  // Constrain weights to [min_wgt, max_wgt] while preserving simplex constraint
  // Map from [0, 1] to [min_wgt, max_wgt] via affine transformation
  simplex[N] wgt;

  {
    vector[N] wgt_scaled = min_wgt + (max_wgt - min_wgt) * wgt_raw;
    wgt = wgt_scaled / sum(wgt_scaled);  // Renormalize to ensure sum = 1
  }
}

model {
  // Dirichlet prior on raw (unconstrained) simplex weights
  // concentration = 1.0 → uniform prior (no preference)
  // concentration > 1.0 → weights cluster near 1/N
  // concentration < 1.0 → weights prefer extremes
  wgt_raw ~ dirichlet(rep_vector(concentration, N));

  // Compute achieved mean and covariance from weighted sample
  // Note: wgt sums to 1, so weight_sum = 1.0
  vector[K] achieved_mean;
  for (k in 1:K) {
    achieved_mean[k] = sum(wgt .* X[, k]);
  }

  // Achieved covariance matrix (weighted)
  matrix[K, K] achieved_cov;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X[, i] - achieved_mean[i];
      vector[N] dev_j = X[, j] - achieved_mean[j];
      achieved_cov[i, j] = sum(wgt .* dev_i .* dev_j);
    }
  }

  // KL divergence: KL(target || achieved)
  // KL(Q||P) = 0.5 * [tr(Σ_Q^{-1} Σ_P) + (μ_P - μ_Q)^T Σ_Q^{-1} (μ_P - μ_Q) - K + log(det(Σ_Q)/det(Σ_P))]
  // Q = target (what we want), P = achieved (what we have)
  matrix[K, K] target_cov_inv = inverse_spd(target_cov);
  vector[K] mean_diff = achieved_mean - target_mean;

  real trace_term = trace(target_cov_inv * achieved_cov);
  real mahalanobis = mean_diff' * target_cov_inv * mean_diff;
  real logdet_term = log_determinant(target_cov) - log_determinant(achieved_cov);

  real kl_divergence = 0.5 * (trace_term + mahalanobis - K + logdet_term);

  // Objective: minimize KL divergence only
  // No weight penalty needed - Dirichlet prior provides regularization
  target += -kl_divergence;
}

generated quantities {
  // ===== Final Weights (scaled by N) =====
  vector[N] wgt_final = N * wgt;

  // ===== Achieved Mean and Covariance (using simplex weights) =====
  vector[K] achieved_mean_final;
  for (k in 1:K) {
    achieved_mean_final[k] = sum(wgt .* X[, k]);
  }

  matrix[K, K] achieved_cov_final;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X[, i] - achieved_mean_final[i];
      vector[N] dev_j = X[, j] - achieved_mean_final[j];
      achieved_cov_final[i, j] = sum(wgt .* dev_i .* dev_j);
    }
  }

  // ===== Final KL Divergence =====
  matrix[K, K] target_cov_inv_final = inverse_spd(target_cov);
  vector[K] mean_diff_final = achieved_mean_final - target_mean;

  real trace_term_final = trace(target_cov_inv_final * achieved_cov_final);
  real mahalanobis_final = mean_diff_final' * target_cov_inv_final * mean_diff_final;
  real logdet_term_final = log_determinant(target_cov) - log_determinant(achieved_cov_final);

  real kl_divergence_final = 0.5 * (trace_term_final + mahalanobis_final - K + logdet_term_final);

  // ===== Weight Diagnostics =====
  real weight_sum = sum(wgt_final);              // Should be N
  real min_weight = min(wgt_final);
  real max_weight = max(wgt_final);
  real mean_weight = mean(wgt_final);             // Should be 1.0
  real median_weight = quantile(wgt_final, 0.5);
  real weight_ratio = max_weight / min_weight;

  // ===== Effective Sample Size (Kish Formula) =====
  // n_eff = (Σw)^2 / Σ(w^2)
  vector[N] wgt_squared = wgt_final .* wgt_final;
  real n_eff = (weight_sum * weight_sum) / sum(wgt_squared);
  real efficiency_pct = (n_eff / N) * 100;
}

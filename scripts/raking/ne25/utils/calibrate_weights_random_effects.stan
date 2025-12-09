// Calibration Estimator with Random Effects
// Purpose: Estimate survey weights with individual-level random deviations
// Method: Minimize KL divergence using hierarchical model
//
// Mathematical form:
//   log(wgt[i]) = alpha + X[i,] * beta + u[i]
//   u[i] ~ Normal(0, sigma_u)
//   sum(u) = 0 (sum-to-zero constraint for identifiability)
//
// Advantages over fixed effects:
// - Individual flexibility while maintaining regularization
// - Hierarchical shrinkage prevents extreme weights
// - Can capture complex individual patterns beyond linear predictor
//
// Parameters:
// - alpha: Intercept (K+1 fixed effects total with beta)
// - beta[K]: Coefficients for calibration variables
// - u[N-1]: Individual random effects (sum-to-zero via N-1 parameterization)
// - sigma_u: Standard deviation of random effects

data {
  int<lower=1> N;                                 // Number of observations
  int<lower=1> K;                                 // Number of calibration variables

  matrix[N, K] X;                                 // Design matrix
  vector[K] target_mean;                          // Target mean vector
  cov_matrix[K] target_cov;                       // Target covariance matrix
}

transformed data {
  // Standardize X for numerical stability
  vector[K] X_mean;
  vector[K] X_sd;
  matrix[N, K] X_std;

  for (k in 1:K) {
    X_mean[k] = mean(X[, k]);
    X_sd[k] = sd(X[, k]);

    // Handle zero-variance columns
    if (X_sd[k] < 1e-10) {
      X_sd[k] = 1.0;
    }

    X_std[, k] = (X[, k] - X_mean[k]) / X_sd[k];
  }

  // QR decomposition for fixed effects
  matrix[N, K] Q_ast = qr_thin_Q(X_std) * sqrt(N - 1);
  matrix[K, K] R_ast = qr_thin_R(X_std) / sqrt(N - 1);
  matrix[K, K] R_ast_inv = inverse(R_ast);
}

parameters {
  real alpha_raw;                                 // Intercept (standardized scale)
  vector[K] theta;                                // QR-parameterized fixed effects
  vector[N-1] u_raw;                              // Random effects (N-1 for sum-to-zero)
  real<lower=0> sigma_u;                          // Random effects standard deviation
}

transformed parameters {
  // Random effects with sum-to-zero constraint
  // u[1:N-1] are free, u[N] = -sum(u[1:N-1])
  vector[N] u;
  u[1:(N-1)] = u_raw;
  u[N] = -sum(u_raw);

  // Log weights = fixed effects + random effects
  vector[N] log_wgt_std = alpha_raw + Q_ast * theta + sigma_u * u;
  vector[N] wgt = exp(log_wgt_std);
}

model {
  // Priors
  alpha_raw ~ normal(0, 1);
  theta ~ normal(0, 1);
  sigma_u ~ cauchy(0, 2.5);                       // Half-Cauchy hyperprior
  u_raw ~ normal(0, 1);                           // Standard normal (scaled by sigma_u)

  // Compute achieved mean and covariance from weighted sample
  real weight_sum = sum(wgt);

  vector[K] achieved_mean;
  for (k in 1:K) {
    achieved_mean[k] = sum(wgt .* X[, k]) / weight_sum;
  }

  matrix[K, K] achieved_cov;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X[, i] - achieved_mean[i];
      vector[N] dev_j = X[, j] - achieved_mean[j];
      achieved_cov[i, j] = sum(wgt .* dev_i .* dev_j) / weight_sum;
    }
  }

  // KL divergence: KL(target || achieved)
  matrix[K, K] target_cov_inv = inverse_spd(target_cov);
  vector[K] mean_diff = achieved_mean - target_mean;

  real trace_term = trace(target_cov_inv * achieved_cov);
  real mahalanobis = mean_diff' * target_cov_inv * mean_diff;
  real logdet_term = log_determinant(target_cov) - log_determinant(achieved_cov);

  real kl_divergence = 0.5 * (trace_term + mahalanobis - K + logdet_term);

  // Objective: minimize KL divergence
  target += -kl_divergence;
}

generated quantities {
  // Transform QR coefficients back to original scale
  vector[K] beta_std = R_ast_inv * theta;
  vector[K] beta;
  real alpha;

  for (k in 1:K) {
    beta[k] = beta_std[k] / X_sd[k];
  }

  alpha = alpha_raw - dot_product(beta_std, X_mean ./ X_sd);

  // Final weights on original scale (including random effects)
  vector[N] log_wgt_final = alpha + X * beta + sigma_u * u;
  vector[N] wgt_final = exp(log_wgt_final);

  // Achieved mean and covariance
  real weight_sum_final = sum(wgt_final);

  vector[K] achieved_mean_final;
  for (k in 1:K) {
    achieved_mean_final[k] = sum(wgt_final .* X[, k]) / weight_sum_final;
  }

  matrix[K, K] achieved_cov_final;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X[, i] - achieved_mean_final[i];
      vector[N] dev_j = X[, j] - achieved_mean_final[j];
      achieved_cov_final[i, j] = sum(wgt_final .* dev_i .* dev_j) / weight_sum_final;
    }
  }

  // Final KL divergence
  matrix[K, K] target_cov_inv_final = inverse_spd(target_cov);
  vector[K] mean_diff_final = achieved_mean_final - target_mean;

  real trace_term_final = trace(target_cov_inv_final * achieved_cov_final);
  real mahalanobis_final = mean_diff_final' * target_cov_inv_final * mean_diff_final;
  real logdet_term_final = log_determinant(target_cov) - log_determinant(achieved_cov_final);

  real kl_divergence_final = 0.5 * (trace_term_final + mahalanobis_final - K + logdet_term_final);

  // Weight diagnostics
  real weight_sum = sum(wgt_final);
  real min_weight = min(wgt_final);
  real max_weight = max(wgt_final);
  real mean_weight = mean(wgt_final);
  real median_weight = quantile(wgt_final, 0.5);
  real weight_ratio = max_weight / min_weight;

  // Effective sample size (Kish)
  vector[N] wgt_squared = wgt_final .* wgt_final;
  real n_eff = (weight_sum * weight_sum) / sum(wgt_squared);
  real efficiency_pct = (n_eff / N) * 100;

  // Random effects diagnostics
  real u_min = min(u);
  real u_max = max(u);
  real u_sd_empirical = sd(u);
}

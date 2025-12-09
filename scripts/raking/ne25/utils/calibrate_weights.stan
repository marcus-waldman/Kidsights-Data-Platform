// Calibration Estimator Model with KL Divergence Loss
// Purpose: Estimate survey weights to match population distribution
// Method: Minimize KL divergence between weighted sample and target population
//
// Mathematical form:
//   wgt[i] = exp(alpha + X[i,] * beta)
//   where alpha is intercept, beta is K coefficient vector
//   Objective: minimize KL(Target || Achieved)
//
// KL divergence between multivariate normals:
//   KL(Q||P) = 0.5 * [tr(Σ_P^{-1} Σ_Q) + (μ_P - μ_Q)^T Σ_P^{-1} (μ_P - μ_Q) - K + log(det(Σ_P)/det(Σ_Q))]
//
// Numerical stability:
// - QR decomposition of standardized X for orthogonal basis
// - Coefficients transformed back to original scale in generated quantities

data {
  int<lower=1> N;                                 // Number of observations
  int<lower=1> K;                                 // Number of calibration variables (covariates)

  matrix[N, K] X;                                 // Design matrix (X[i,k] = covariate k for observation i)
  vector[K] target_mean;                          // Target mean vector (from ACS weighted)
  cov_matrix[K] target_cov;                       // Target covariance matrix (from ACS weighted)
}

transformed data {
  // Standardize X (mean=0, sd=1), handling zero-variance columns
  vector[K] X_mean = to_vector(rep_row_vector(0, K));
  vector[K] X_sd = to_vector(rep_row_vector(1, K));
  matrix[N, K] X_std;

  for (k in 1:K) {
    X_mean[k] = mean(X[, k]);
    X_sd[k] = sd(X[, k]);

    // Handle zero-variance columns (set sd=1 to avoid division by zero)
    if (X_sd[k] < 1e-10) {
      X_sd[k] = 1.0;
    }

    X_std[, k] = (X[, k] - X_mean[k]) / X_sd[k];
  }

  // QR decomposition of standardized X
  matrix[N, K] Q_ast;
  matrix[K, K] R_ast;
  matrix[K, K] R_ast_inv;

  Q_ast = qr_thin_Q(X_std) * sqrt(N - 1);
  R_ast = qr_thin_R(X_std) / sqrt(N - 1);
  R_ast_inv = inverse(R_ast);
}

parameters {
  real alpha_raw;                                 // Intercept (on standardized scale)
  vector[K] theta;                                // QR-parameterized coefficients
}

transformed parameters {
  // Weights computed using QR basis (for optimization)
  vector[N] log_wgt_std = alpha_raw + Q_ast * theta;
  vector[N] wgt = exp(log_wgt_std);
}

model {
  // Regularization priors on QR-parameterized coefficients
  alpha_raw ~ normal(0, 1);
  theta ~ normal(0, 1);

  // Compute achieved mean and covariance from weighted sample (on ORIGINAL scale)
  real weight_sum = sum(wgt);

  // Achieved mean vector
  vector[K] achieved_mean;
  for (k in 1:K) {
    achieved_mean[k] = sum(wgt .* X[, k]) / weight_sum;
  }

  // Achieved covariance matrix (weighted)
  matrix[K, K] achieved_cov;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X[, i] - achieved_mean[i];
      vector[N] dev_j = X[, j] - achieved_mean[j];
      achieved_cov[i, j] = sum(wgt .* dev_i .* dev_j) / weight_sum;
    }
  }

  // KL divergence: KL(target || achieved)
  // KL(Q||P) = 0.5 * [tr(Σ_P^{-1} Σ_Q) + (μ_P - μ_Q)^T Σ_P^{-1} (μ_P - μ_Q) - K + log(det(Σ_P)/det(Σ_Q))]
  // Here Q = target (what we want), P = achieved (what we have)
  // So we need target_cov_inv (Σ_Q^{-1}) NOT achieved_cov_inv
  matrix[K, K] target_cov_inv = inverse_spd(target_cov);
  vector[K] mean_diff = achieved_mean - target_mean;

  real trace_term = trace(target_cov_inv * achieved_cov);
  real mahalanobis = mean_diff' * target_cov_inv * mean_diff;
  real logdet_term = log_determinant(target_cov) - log_determinant(achieved_cov);

  real kl_divergence = 0.5 * (trace_term + mahalanobis - K + logdet_term);

  // Penalty for extreme weights
  real weight_penalty = variance(log_wgt_std);

  // Combined objective: minimize KL divergence only (no weight penalty)
  // KL divergence naturally penalizes extreme distributions via log-determinant term
  target += -kl_divergence;
}

generated quantities {
  // ===== Transform QR coefficients back to original scale =====
  vector[K] beta_std = R_ast_inv * theta;         // Coefficients on standardized scale
  vector[K] beta;                                  // Coefficients on original scale
  real alpha;                                      // Intercept on original scale

  // Transform to original scale: beta_original = beta_std / X_sd
  for (k in 1:K) {
    beta[k] = beta_std[k] / X_sd[k];
  }

  // Adjust intercept for centering
  alpha = alpha_raw - dot_product(beta_std, X_mean ./ X_sd);

  // ===== Compute final weights on ORIGINAL scale =====
  vector[N] log_wgt_final = alpha + X * beta;
  vector[N] wgt_final = exp(log_wgt_final);

  // ===== Achieved Mean and Covariance =====
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

  // ===== Final KL Divergence =====
  matrix[K, K] target_cov_inv_final = inverse_spd(target_cov);
  vector[K] mean_diff_final = achieved_mean_final - target_mean;

  real trace_term_final = trace(target_cov_inv_final * achieved_cov_final);
  real mahalanobis_final = mean_diff_final' * target_cov_inv_final * mean_diff_final;
  real logdet_term_final = log_determinant(target_cov) - log_determinant(achieved_cov_final);

  real kl_divergence_final = 0.5 * (trace_term_final + mahalanobis_final - K + logdet_term_final);

  // ===== Weight Diagnostics =====
  real weight_sum = sum(wgt_final);
  real min_weight = min(wgt_final);
  real max_weight = max(wgt_final);
  real mean_weight = mean(wgt_final);
  real median_weight = quantile(wgt_final, 0.5);
  real weight_ratio = max_weight / min_weight;

  // ===== Effective Sample Size (Kish Formula) =====
  // n_eff = (Σw)^2 / Σ(w^2)
  vector[N] wgt_squared = wgt_final .* wgt_final;
  real n_eff = (weight_sum * weight_sum) / sum(wgt_squared);
  real efficiency_pct = (n_eff / N) * 100;
}

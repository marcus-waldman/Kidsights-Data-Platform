// Calibration Estimator with Factorized Covariance (Masked KL Divergence)
// Purpose: Estimate survey weights with incomplete covariance structure
// Method: Minimize KL divergence using only OBSERVED covariance elements
//
// Key Innovation: Mask matrix specifies which Σ elements are observed
//   - Observed elements (mask[i,j] = 1): Included in KL divergence
//   - Unobserved elements (mask[i,j] = 0): Excluded from KL divergence
//
// Use Case: Multi-source data where some variable pairs unobserved
//   - Example: PUMA (ACS) × Mental Health (NHIS) = unobserved
//   - Solution: Set mask[puma_indices, mh_indices] = 0
//
// Mathematical form:
//   wgt[i] = exp(alpha + X[i,] * beta)
//   KL divergence computed only over observed Σ elements

data {
  int<lower=1> N;                                 // Number of observations
  int<lower=1> K;                                 // Number of calibration variables

  matrix[N, K] X;                                 // Design matrix
  vector[K] target_mean;                          // Target mean vector
  matrix[K, K] target_cov;                        // Target covariance (NOT positive definite - has 0 cross-blocks)

  // NEW: Covariance mask (1 = observed, 0 = unobserved)
  matrix<lower=0, upper=1>[K, K] cov_mask;       // Binary mask for observed covariances
}

transformed data {
  // Standardize X for numerical stability
  vector[K] X_mean = to_vector(rep_row_vector(0, K));
  vector[K] X_sd = to_vector(rep_row_vector(1, K));
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

  // QR decomposition for orthogonal parameterization
  matrix[N, K] Q_ast = qr_thin_Q(X_std) * sqrt(N - 1);
  matrix[K, K] R_ast = qr_thin_R(X_std) / sqrt(N - 1);
  matrix[K, K] R_ast_inv = inverse(R_ast);

  // Count observed covariance elements (for effective dimensionality)
  int n_observed_cov = 0;
  for (i in 1:K) {
    for (j in 1:K) {
      if (cov_mask[i, j] > 0.5) {  // Observed element
        n_observed_cov += 1;
      }
    }
  }

  // Effective degrees of freedom for KL divergence
  // Only count observed covariance elements, not full K*(K+1)/2
  int K_eff = n_observed_cov;
}

parameters {
  real alpha_raw;                                 // Intercept (standardized scale)
  vector[K] theta;                                // QR-parameterized coefficients
}

transformed parameters {
  // Weights computed using QR basis
  vector[N] log_wgt_std = alpha_raw + Q_ast * theta;
  vector[N] wgt = exp(log_wgt_std);
}

model {
  // Regularization priors
  alpha_raw ~ normal(0, 1);
  theta ~ normal(0, 1);

  // Compute achieved mean and covariance from weighted sample
  real weight_sum = sum(wgt);

  // Achieved mean vector
  vector[K] achieved_mean;
  for (k in 1:K) {
    achieved_mean[k] = sum(wgt .* X[, k]) / weight_sum;
  }

  // Achieved covariance matrix (full K×K, will be masked later)
  matrix[K, K] achieved_cov;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X[, i] - achieved_mean[i];
      vector[N] dev_j = X[, j] - achieved_mean[j];
      achieved_cov[i, j] = sum(wgt .* dev_i .* dev_j) / weight_sum;
    }
  }

  // ========================================================================
  // MASKED KL DIVERGENCE: Only use observed covariance elements
  // ========================================================================
  //
  // Standard KL(Q||P) for multivariate normal:
  //   KL = 0.5 * [tr(Σ_P^{-1} Σ_Q) + (μ_P - μ_Q)^T Σ_P^{-1} (μ_P - μ_Q)
  //               - K + log(det(Σ_P)/det(Σ_Q))]
  //
  // Problem: This assumes ALL elements of Σ_Q and Σ_P are observed
  //
  // Solution: Compute element-wise covariance loss for observed elements only
  //   - Mean term: Standard Mahalanobis distance (all means observed)
  //   - Covariance term: Weighted Frobenius norm over OBSERVED elements
  //   - Skip log-determinant term (requires full covariance structure)
  //
  // Simplified objective (valid for factorized Σ):
  //   Loss = 0.5 * [(μ_achieved - μ_target)^T Σ_target^{-1} (μ_achieved - μ_target)
  //                 + Σ_ij [mask[i,j] * (Σ_achieved[i,j] - Σ_target[i,j])^2 / Σ_target[i,i]]]
  //
  // Note: This is an APPROXIMATION that avoids full matrix inversion on masked Σ
  // ========================================================================

  vector[K] mean_diff = achieved_mean - target_mean;

  // Inverse of target covariance (use full matrix, but only for mean matching)
  // For factorized structure, inverse may be block-diagonal or near-singular
  // We use generalized inverse (pseudo-inverse) via Cholesky with regularization
  matrix[K, K] target_cov_reg = target_cov + diag_matrix(rep_vector(1e-6, K));
  matrix[K, K] target_cov_inv = inverse_spd(target_cov_reg);

  // Mean matching term (Mahalanobis distance)
  real mahalanobis = mean_diff' * target_cov_inv * mean_diff;

  // Covariance matching term (masked Frobenius norm)
  // Only penalize differences in OBSERVED covariance elements
  real cov_loss = 0.0;

  for (i in 1:K) {
    for (j in 1:K) {
      if (cov_mask[i, j] > 0.5) {  // Only observed elements
        // Weighted squared difference, normalized by target variance
        real target_val = target_cov[i, j];
        real achieved_val = achieved_cov[i, j];
        real target_sd = sqrt(target_cov[i, i] * target_cov[j, j]);

        if (target_sd > 1e-10) {
          real normalized_diff = (achieved_val - target_val) / target_sd;
          cov_loss += normalized_diff * normalized_diff;
        }
      }
    }
  }

  // Combined loss (no log-determinant term for factorized covariance)
  real total_loss = 0.5 * (mahalanobis + cov_loss);

  // Objective: minimize loss
  target += -total_loss;
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

  // Final weights on original scale
  vector[N] log_wgt_final = alpha + X * beta;
  vector[N] wgt_final = exp(log_wgt_final);

  // Achieved mean and covariance (for diagnostics)
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

  // Final loss (masked)
  vector[K] mean_diff_final = achieved_mean_final - target_mean;
  matrix[K, K] target_cov_reg_final = target_cov + diag_matrix(rep_vector(1e-6, K));
  matrix[K, K] target_cov_inv_final = inverse_spd(target_cov_reg_final);

  real mahalanobis_final = mean_diff_final' * target_cov_inv_final * mean_diff_final;

  real cov_loss_final = 0.0;
  for (i in 1:K) {
    for (j in 1:K) {
      if (cov_mask[i, j] > 0.5) {
        real target_val = target_cov[i, j];
        real achieved_val = achieved_cov_final[i, j];
        real target_sd = sqrt(target_cov[i, i] * target_cov[j, j]);

        if (target_sd > 1e-10) {
          real normalized_diff = (achieved_val - target_val) / target_sd;
          cov_loss_final += normalized_diff * normalized_diff;
        }
      }
    }
  }

  real total_loss_final = 0.5 * (mahalanobis_final + cov_loss_final);

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

  // Diagnostics: observed vs total covariance elements
  int n_total_cov = K * K;
  int n_observed = n_observed_cov;
  real pct_observed = (n_observed * 100.0) / n_total_cov;
}

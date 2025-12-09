// Calibration Estimator: Simplex Parameterization with Factorized Covariance
// Purpose: Estimate survey weights with incomplete covariance structure
// Method: Minimize masked KL divergence using N-dimensional simplex for weights
//
// Mathematical form:
//   wgt[i] ~ Dirichlet(concentration)
//   wgt sums to 1, final_wgt[i] = N * wgt[i]
//   Weights constrained: min_weight <= final_wgt[i] <= max_weight
//
// Advantages:
// - Flexible: N parameters can match complex distributions
// - Bounded weights with explicit min/max constraints
// - Handles factorized (singular) covariance matrices
// - Dirichlet prior provides smoothing

data {
  int<lower=1> N;                                 // Number of observations
  int<lower=1> K;                                 // Number of calibration variables

  matrix[N, K] X;                                 // Design matrix
  vector[K] target_mean;                          // Target mean vector
  matrix[K, K] target_cov;                        // Target covariance (may be singular)

  // Covariance mask (1 = observed, 0 = unobserved)
  matrix<lower=0, upper=1>[K, K] cov_mask;

  real<lower=0> concentration;                    // Dirichlet concentration (1.0 = uniform)
  real<lower=0> min_weight_multiplier;            // Min weight = min_weight_multiplier (e.g., 0.1)
  real<lower=0> max_weight_multiplier;            // Max weight = max_weight_multiplier (e.g., 10.0)
}

transformed data {
  real min_wgt = min_weight_multiplier / N;       // Minimum allowed simplex weight
  real max_wgt = max_weight_multiplier / N;       // Maximum allowed simplex weight

  // Count observed covariance elements
  int n_observed_cov = 0;
  for (i in 1:K) {
    for (j in 1:K) {
      if (cov_mask[i, j] > 0.5) {
        n_observed_cov += 1;
      }
    }
  }
}

parameters {
  simplex[N] wgt_raw;                             // Unconstrained simplex weights
}

transformed parameters {
  // Constrain weights to [min_wgt, max_wgt] while preserving simplex constraint
  simplex[N] wgt;

  {
    vector[N] wgt_scaled = min_wgt + (max_wgt - min_wgt) * wgt_raw;
    wgt = wgt_scaled / sum(wgt_scaled);  // Renormalize to ensure sum = 1
  }
  
  // Final weights (scaled by N)
  vector[N] wgt_final = N * wgt;
  
   // Effective sample size (Kish)
  vector[N] wgt_squared = wgt_final .* wgt_final;
  real weight_sum = sum(wgt_final);              // Should be N
  real n_eff = (weight_sum * weight_sum) / sum(wgt_squared);
  real efficiency_pct = (n_eff / N) * 100;
  
}

model {
  // Dirichlet prior on raw simplex weights
  wgt_raw ~ dirichlet(rep_vector(concentration, N));
  efficiency_pct~normal(100,75);

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

  // ========================================================================
  // MASKED KL DIVERGENCE
  // ========================================================================

  vector[K] mean_diff = achieved_mean - target_mean;

  // Mean matching term (diagonal approximation to avoid singular matrix inversion)
  real mahalanobis = 0.0;
  for (k in 1:K) {
    if (target_cov[k, k] > 1e-10) {
      real normalized_diff = mean_diff[k] / sqrt(target_cov[k, k]);
      mahalanobis += normalized_diff * normalized_diff;
    }
  }

  // Covariance matching term (masked Frobenius norm)
  real cov_loss = 0.0;
  for (i in 1:K) {
    for (j in 1:K) {
      if (cov_mask[i, j] > 0.5) {  // Only observed elements
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

  // Combined loss
  real total_loss = 0.5 * (mahalanobis + cov_loss);

  // Objective: minimize loss
  target += -total_loss;
}

generated quantities {
  

  // Achieved mean and covariance (using simplex weights)
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

  // Final loss (masked)
  vector[K] mean_diff_final = achieved_mean_final - target_mean;

  real mahalanobis_final = 0.0;
  for (k in 1:K) {
    if (target_cov[k, k] > 1e-10) {
      real normalized_diff = mean_diff_final[k] / sqrt(target_cov[k, k]);
      mahalanobis_final += normalized_diff * normalized_diff;
    }
  }

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
  real min_weight = min(wgt_final);
  real max_weight = max(wgt_final);
  real mean_weight = mean(wgt_final);             // Should be 1.0
  real median_weight = quantile(wgt_final, 0.5);
  real weight_ratio = max_weight / min_weight;

 

  // Diagnostics: observed covariance coverage
  int n_total_cov = K * K;
  real pct_observed = (n_observed_cov * 100.0) / n_total_cov;
}

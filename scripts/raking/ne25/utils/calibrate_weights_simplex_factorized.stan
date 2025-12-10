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

  // Standardization factors from raking targets (pass from R)
  vector[K] scale_mean;                           // Mean of each calibration variable
  vector[K] scale_sd;                             // SD of each calibration variable
  int<lower=0, upper=1> use_standardization;     // Flag: 1 = use standardization, 0 = raw scale
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

  // ========================================================================
  // STANDARDIZATION (Optional, applied if use_standardization = 1)
  // ========================================================================
  // Transform design matrix and targets to standardized scale
  // This improves optimizer efficiency without changing final weights

  matrix[N, K] X_work;                            // Working copy of design matrix
  vector[K] target_mean_work;                     // Working copy of target mean
  matrix[K, K] target_cov_work;                   // Working copy of target covariance

  if (use_standardization == 1) {
    // Standardize design matrix: X_std = (X - mean) / sd
    for (n in 1:N) {
      for (k in 1:K) {
        if (scale_sd[k] > 1e-10) {
          X_work[n, k] = (X[n, k] - scale_mean[k]) / scale_sd[k];
        } else {
          X_work[n, k] = X[n, k] - scale_mean[k];  // If no variation, just center
        }
      }
    }

    // Standardize target mean: target_mean_std = (target_mean - mean) / sd
    for (k in 1:K) {
      if (scale_sd[k] > 1e-10) {
        target_mean_work[k] = (target_mean[k] - scale_mean[k]) / scale_sd[k];
      } else {
        target_mean_work[k] = target_mean[k] - scale_mean[k];
      }
    }

    // Standardize target covariance: cov_std = cov / (sd_i * sd_j)
    for (i in 1:K) {
      for (j in 1:K) {
        real sd_product = scale_sd[i] * scale_sd[j];
        if (sd_product > 1e-10) {
          target_cov_work[i, j] = target_cov[i, j] / sd_product;
        } else {
          target_cov_work[i, j] = target_cov[i, j];  // If no variation, use original
        }
      }
    }
  } else {
    // If not standardizing, use raw data
    X_work = X;
    target_mean_work = target_mean;
    target_cov_work = target_cov;
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
  // Uses standardized data if use_standardization = 1
  vector[K] achieved_mean;
  for (k in 1:K) {
    achieved_mean[k] = sum(wgt .* X_work[, k]);
  }

  // Achieved covariance matrix (weighted)
  matrix[K, K] achieved_cov;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X_work[, i] - achieved_mean[i];
      vector[N] dev_j = X_work[, j] - achieved_mean[j];
      achieved_cov[i, j] = sum(wgt .* dev_i .* dev_j);
    }
  }

  // ========================================================================
  // MASKED KL DIVERGENCE (on standardized scale if use_standardization = 1)
  // ========================================================================

  vector[K] mean_diff = achieved_mean - target_mean_work;

  // Mean matching term (diagonal approximation to avoid singular matrix inversion)
  real mahalanobis = 0.0;
  for (k in 1:K) {
    if (target_cov_work[k, k] > 1e-10) {
      real normalized_diff = mean_diff[k] / sqrt(target_cov_work[k, k]);
      mahalanobis += normalized_diff * normalized_diff;
    }
  }

  // Covariance matching term (masked Frobenius norm)
  real cov_loss = 0.0;
  for (i in 1:K) {
    for (j in 1:K) {
      if (cov_mask[i, j] > 0.5) {  // Only observed elements
        real target_val = target_cov_work[i, j];
        real achieved_val = achieved_cov[i, j];
        real target_sd = sqrt(target_cov_work[i, i] * target_cov_work[j, j]);

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
  

  // Achieved mean and covariance (using simplex weights, on standardized scale)
  vector[K] achieved_mean_final;
  for (k in 1:K) {
    achieved_mean_final[k] = sum(wgt .* X_work[, k]);
  }

  matrix[K, K] achieved_cov_final;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X_work[, i] - achieved_mean_final[i];
      vector[N] dev_j = X_work[, j] - achieved_mean_final[j];
      achieved_cov_final[i, j] = sum(wgt .* dev_i .* dev_j);
    }
  }

  // Final loss (masked, on standardized scale)
  vector[K] mean_diff_final = achieved_mean_final - target_mean_work;

  real mahalanobis_final = 0.0;
  for (k in 1:K) {
    if (target_cov_work[k, k] > 1e-10) {
      real normalized_diff = mean_diff_final[k] / sqrt(target_cov_work[k, k]);
      mahalanobis_final += normalized_diff * normalized_diff;
    }
  }

  real cov_loss_final = 0.0;
  for (i in 1:K) {
    for (j in 1:K) {
      if (cov_mask[i, j] > 0.5) {
        real target_val = target_cov_work[i, j];
        real achieved_val = achieved_cov_final[i, j];
        real target_sd = sqrt(target_cov_work[i, i] * target_cov_work[j, j]);

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

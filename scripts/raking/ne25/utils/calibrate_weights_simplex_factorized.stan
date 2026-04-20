// Calibration Estimator: Simplex Parameterization with Factorized Covariance
// Purpose: Estimate survey weights with incomplete covariance structure
// Method: Minimize masked moment-matching loss using N-dimensional simplex
//
// Mathematical form:
//   wgt_raw    ~ Dirichlet(1, 1, ..., 1)                   // flat prior — always
//   wgt        = renormalize(min_wgt + (max_wgt - min_wgt) * wgt_raw)
//   w_eff      = renormalize(wgt .* bbw)                   // bootstrap-perturbed simplex
//   wgt_final  = N * w_eff                                 // analyst-facing weight
//
// Bayesian bootstrap integration (NE22 pattern):
//   bbw is passed IN FROM R as a per-observation multiplicative data weight:
//     * bbw = rep_vector(1, N)    -> baseline (identical to Bucket 2)
//     * bbw = rexp(N, 1) draw     -> Bayesian bootstrap replicate
//   bbw enters the MOMENT CALCULATION (not the prior), so it's smooth in wgt
//   and cannot cause gradient singularities. The flat Dirichlet(1,...,1) prior
//   on wgt_raw has identically zero gradient contribution, eliminating the
//   boundary-blowup failure mode of earlier prior-concentration variants.

data {
  int<lower=1> N;                                 // Number of observations
  int<lower=1> K;                                 // Number of calibration variables

  matrix[N, K] X;                                 // Design matrix
  vector[K] target_mean;                          // Target mean vector
  matrix[K, K] target_cov;                        // Target covariance (may be singular)

  // Covariance mask (1 = observed, 0 = unobserved)
  matrix<lower=0, upper=1>[K, K] cov_mask;

  // Bayesian-bootstrap data weight multiplier.
  // Scale is arbitrary (Stan renormalizes w_eff internally).
  //   * baseline/Bucket 2 equivalence: pass rep_vector(1.0, N)
  //   * bootstrap replicate b: pass rexp(N, 1) or rdirichlet(1, rep(1, N))
  vector<lower=0>[N] bbw;

  real<lower=0> min_weight_multiplier;            // Min final weight in [min_weight_multiplier, max_weight_multiplier]
  real<lower=0> max_weight_multiplier;

  // Standardization factors from raking targets (pass from R)
  vector[K] scale_mean;                           // Mean of each calibration variable
  vector[K] scale_sd;                             // SD of each calibration variable
  int<lower=0, upper=1> use_standardization;      // Flag: 1 = use standardization, 0 = raw scale
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
  matrix[N, K] X_work;
  vector[K] target_mean_work;
  matrix[K, K] target_cov_work;

  if (use_standardization == 1) {
    for (n in 1:N) {
      for (k in 1:K) {
        if (scale_sd[k] > 1e-10) {
          X_work[n, k] = (X[n, k] - scale_mean[k]) / scale_sd[k];
        } else {
          X_work[n, k] = X[n, k] - scale_mean[k];
        }
      }
    }
    for (k in 1:K) {
      if (scale_sd[k] > 1e-10) {
        target_mean_work[k] = (target_mean[k] - scale_mean[k]) / scale_sd[k];
      } else {
        target_mean_work[k] = target_mean[k] - scale_mean[k];
      }
    }
    for (i in 1:K) {
      for (j in 1:K) {
        real sd_product = scale_sd[i] * scale_sd[j];
        if (sd_product > 1e-10) {
          target_cov_work[i, j] = target_cov[i, j] / sd_product;
        } else {
          target_cov_work[i, j] = target_cov[i, j];
        }
      }
    }
  } else {
    X_work = X;
    target_mean_work = target_mean;
    target_cov_work = target_cov;
  }
}

parameters {
  simplex[N] wgt_raw;                             // Unconstrained simplex weights
}

transformed parameters {
  // Bounded simplex weights (raking adjustment only; no bootstrap applied yet)
  simplex[N] wgt;
  {
    vector[N] wgt_scaled = min_wgt + (max_wgt - min_wgt) * wgt_raw;
    wgt = wgt_scaled / sum(wgt_scaled);
  }

  // Effective weights combining raking adjustment with Bayesian-bootstrap
  // data perturbation. For bbw = rep_vector(1, N), w_eff == wgt (Bucket 2
  // behavior is reproduced exactly).
  simplex[N] w_eff;
  {
    vector[N] w_combined = wgt .* bbw;
    w_eff = w_combined / sum(w_combined);
  }

  // Final analyst-facing weights (sum to N by construction)
  vector[N] wgt_final = N * w_eff;

  // Effective sample size (Kish), computed on w_eff
  vector[N] wgt_squared = wgt_final .* wgt_final;
  real weight_sum = sum(wgt_final);               // Should be N
  real n_eff = (weight_sum * weight_sum) / sum(wgt_squared);
  real efficiency_pct = (n_eff / N) * 100;
}

model {
  // Flat Dirichlet prior on the raw simplex weights. No bootstrap information
  // enters here; bbw is used only inside the moment-matching loss below.
  wgt_raw ~ dirichlet(rep_vector(1.0, N));

  // Soft prior on Kish efficiency (unchanged from Bucket 2)
  efficiency_pct ~ normal(100, 75);

  // ========================================================================
  // Moment-matching loss — computed on w_eff (which incorporates bbw)
  // ========================================================================
  vector[K] achieved_mean;
  for (k in 1:K) {
    achieved_mean[k] = sum(w_eff .* X_work[, k]);
  }

  matrix[K, K] achieved_cov;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X_work[, i] - achieved_mean[i];
      vector[N] dev_j = X_work[, j] - achieved_mean[j];
      achieved_cov[i, j] = sum(w_eff .* dev_i .* dev_j);
    }
  }

  vector[K] mean_diff = achieved_mean - target_mean_work;

  // Mean matching (diagonal weighting; avoids inverting the singular target cov)
  real mahalanobis = 0.0;
  for (k in 1:K) {
    if (target_cov_work[k, k] > 1e-10) {
      real normalized_diff = mean_diff[k] / sqrt(target_cov_work[k, k]);
      mahalanobis += normalized_diff * normalized_diff;
    }
  }

  // Covariance matching (masked Frobenius norm, correlation-scale normalized)
  real cov_loss = 0.0;
  for (i in 1:K) {
    for (j in 1:K) {
      if (cov_mask[i, j] > 0.5) {
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

  real total_loss = 0.5 * (mahalanobis + cov_loss);
  target += -total_loss;
}

generated quantities {
  // Achieved mean / cov on the final simplex (w_eff), for diagnostics.
  vector[K] achieved_mean_final;
  for (k in 1:K) {
    achieved_mean_final[k] = sum(w_eff .* X_work[, k]);
  }

  matrix[K, K] achieved_cov_final;
  for (i in 1:K) {
    for (j in 1:K) {
      vector[N] dev_i = X_work[, i] - achieved_mean_final[i];
      vector[N] dev_j = X_work[, j] - achieved_mean_final[j];
      achieved_cov_final[i, j] = sum(w_eff .* dev_i .* dev_j);
    }
  }

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

  // Weight diagnostics (on the bootstrap-perturbed wgt_final)
  real min_weight = min(wgt_final);
  real max_weight = max(wgt_final);
  real mean_weight = mean(wgt_final);             // Should be 1.0
  real median_weight = quantile(wgt_final, 0.5);
  real weight_ratio = max_weight / min_weight;

  int n_total_cov = K * K;
  real pct_observed = (n_observed_cov * 100.0) / n_total_cov;
}

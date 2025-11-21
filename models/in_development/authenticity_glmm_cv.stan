/**
 * Authenticity Screening GLMM - Cross-Validation Version with Gauss-Hermite Quadrature
 *
 * This is a specialized version of authenticity_glmm_beta_sumprior_stable.stan for
 * cross-validation. Key differences:
 *   - Accepts BOTH training and holdout data
 *   - Fits parameters ONLY on training data (no holdout contribution to target)
 *   - Evaluates holdout via Gauss-Hermite quadrature (marginal likelihood)
 *   - Returns per-person deviances for CV loss calculation
 *
 * Cross-Validation Strategy:
 *   - Training data: Used to estimate all parameters (tau, beta1, delta, eta, logitwgt)
 *   - Holdout data: Evaluated via marginal likelihood (integrating out eta)
 *   - GH quadrature: Two independent 1D integrations (dimensions uncorrelated)
 *   - Loss: Mean per-person deviance (normalized by item count)
 *
 * Design Philosophy:
 *   - Same model as stable version, but with train/holdout separation
 *   - Prevents data leakage: holdout persons' eta not estimated from their data
 *   - Proper marginalization: ∫ p(y|η,θ) × φ(η) dη via GH quadrature
 */

data {
  // ============================================================================
  // TRAINING DATA (used for fitting)
  // ============================================================================

  int<lower=1> M_train;        // Number of training observations
  int<lower=1> N_train;        // Number of training persons
  int<lower=1> J;              // Number of items (same for train/holdout)

  array[M_train] int<lower=1, upper=N_train> ivec_train;
  array[M_train] int<lower=1, upper=J> jvec_train;
  array[M_train] int<lower=0> yvec_train;

  vector[N_train] age_train;   // Age for training persons

  // ============================================================================
  // HOLDOUT DATA (used only for evaluation in generated quantities)
  // ============================================================================

  int<lower=0> M_holdout;      // Number of holdout observations
  int<lower=0> N_holdout;      // Number of holdout persons

  array[M_holdout] int<lower=1, upper=N_holdout> ivec_holdout;
  array[M_holdout] int<lower=1, upper=J> jvec_holdout;
  array[M_holdout] int<lower=0> yvec_holdout;

  vector[N_holdout] age_holdout;  // Age for holdout persons

  // ============================================================================
  // ITEM METADATA (shared across train/holdout)
  // ============================================================================

  array[J] int<lower=2> K;                      // Number of categories per item
  array[J] int<lower=1, upper=2> dimension;     // Dimension: 1=psychosocial, 2=developmental

  // ============================================================================
  // HYPERPARAMETERS
  // ============================================================================

  real<lower=0> lambda_skew;   // Skewness penalty coefficient
  real<lower=0> sigma_sum_w;   // Normal scale for sum(w) ~ Normal(N, sigma)

  // ============================================================================
  // GAUSS-HERMITE QUADRATURE (for holdout evaluation)
  // ============================================================================

  int<lower=1> n_nodes;        // Number of GH nodes (typically 21)
  vector[n_nodes] gh_nodes;    // GH nodes for N(0,1)
  vector[n_nodes] gh_weights;  // GH weights (sum to sqrt(pi))
}

transformed data {
  // Count items per training person
  array[N_train] int n_items_train = rep_array(0, N_train);

  // Count items per holdout person (for deviance normalization)
  array[N_holdout] int n_items_holdout = rep_array(0, N_holdout);

  // Soft-clipping threshold for t-statistics
  real t_clip_threshold = 10.0;

  // Small constants for soft boundaries
  real epsilon_prob = 1e-10;
  real epsilon_var = 1e-10;
  real epsilon_div = 1e-6;

  // Count training items
  for (m in 1:M_train) {
    n_items_train[ivec_train[m]] += 1;
  }

  // Count holdout items
  for (m in 1:M_holdout) {
    n_items_holdout[ivec_holdout[m]] += 1;
  }
}

parameters {
  // Item parameters (estimated from training data only)
  vector[J] tau;
  vector[J] beta1;
  vector<lower=0>[2] delta;

  // Person effects for TRAINING persons only
  vector[N_train] eta_psychosocial_train;
  vector[N_train] eta_developmental_train;

  // Weights for TRAINING persons only
  vector[N_train] logitwgt_train;
}

transformed parameters {
  // Weights on probability scale
  vector[N_train] w = inv_logit(logitwgt_train);

  // Construct eta matrix
  matrix[N_train, 2] eta_train;
  eta_train[, 1] = eta_psychosocial_train;
  eta_train[, 2] = eta_developmental_train;

  // Training person-level statistics
  vector[N_train] person_loglik = rep_vector(0, N_train);
  vector[N_train] person_loglik_sq = rep_vector(0, N_train);
  vector[N_train] mean_loglik;
  vector[N_train] sd_loglik;
  vector[N_train] t_stat;

  // Accumulate training log-likelihoods
  for (m in 1:M_train) {
    int i = ivec_train[m];
    int j = jvec_train[m];
    int y = yvec_train[m];
    int k_max = K[j] - 1;

    real eta_d = (dimension[j] == 1) ? eta_train[i, 1] : eta_train[i, 2];
    real lp = beta1[j] * age_train[i] + eta_d;

    real p;
    if (y == 0) {
      p = inv_logit(tau[j] - lp);
    } else if (y == k_max) {
      real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
      p = 1 - inv_logit(tau_left - lp);
    } else {
      real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
      real tau_right = tau[j] + y * delta[dimension[j]];
      p = inv_logit(tau_right - lp) - inv_logit(tau_left - lp);
    }

    p = p + epsilon_prob;
    real item_loglik = log(p);

    person_loglik[i] += item_loglik;
    person_loglik_sq[i] += square(item_loglik);
  }

  // Compute training person statistics
  for (i in 1:N_train) {
    if (n_items_train[i] > 1) {
      mean_loglik[i] = person_loglik[i] / n_items_train[i];
      real var_loglik = (person_loglik_sq[i] / n_items_train[i]) - square(mean_loglik[i]);
      sd_loglik[i] = sqrt(var_loglik + epsilon_var);
    } else {
      mean_loglik[i] = person_loglik[i];
      sd_loglik[i] = 1.0;
    }
  }

  // Compute precision-weighted population mean and t-statistics
  {
    real sum_weighted_loglik = 0;
    real sum_weighted_items = 0;

    for (i in 1:N_train) {
      sum_weighted_loglik += w[i] * n_items_train[i] * mean_loglik[i];
      sum_weighted_items += w[i] * n_items_train[i];
    }

    real mu_weighted = sum_weighted_loglik / (sum_weighted_items + epsilon_div);

    for (i in 1:N_train) {
      if (n_items_train[i] > 1) {
        real se_i = sd_loglik[i] / sqrt(n_items_train[i]);
        t_stat[i] = (mean_loglik[i] - mu_weighted) / se_i;
      } else {
        t_stat[i] = 0.0;
      }
    }
  }
}

model {
  // ============================================================================
  // PRIORS ON ITEM PARAMETERS
  // ============================================================================

  tau ~ normal(0, 5);
  beta1 ~ normal(0, 2);
  delta ~ student_t(3, 0, 1);

  // INDEPENDENT priors on person effects
  eta_psychosocial_train ~ std_normal();
  eta_developmental_train ~ std_normal();

  // Mixture normal prior on logit-scaled weights
  target += .5*(normal_lpdf(logitwgt_train | -4, 1) + normal_lpdf(logitwgt_train | 4, 1) );

  // ============================================================================
  // WEIGHTED LIKELIHOOD (TRAINING DATA ONLY)
  // ============================================================================

  for (i in 1:N_train) {
    target += w[i] * person_loglik[i];
  }

  // ============================================================================
  // WEIGHTED SKEWNESS PENALTY (TRAINING DATA ONLY)
  // ============================================================================

  {
    real sum_w = sum(w);
    real sum_w_sq = dot_product(w, w);
    real N_eff = square(sum_w) / (sum_w_sq + epsilon_div);

    real mean_t_weighted = dot_product(w, t_stat) / (sum_w + epsilon_div);
    vector[N_train] t_centered = t_stat - mean_t_weighted;
    real var_t_weighted = dot_product(w, t_centered .* t_centered) / (sum_w + epsilon_div);
    real sd_t_weighted = sqrt(var_t_weighted + epsilon_var);

    vector[N_train] t_std = t_centered / sd_t_weighted;

    // Soft-clip t-statistics
    vector[N_train] t_std_soft;
    for (i in 1:N_train) {
      t_std_soft[i] = t_clip_threshold * tanh(t_std[i] / t_clip_threshold);
    }

    real skewness = dot_product(w, t_std_soft .* t_std_soft .* t_std_soft) / (sum_w + epsilon_div);
    real se_skewness = sqrt(6.0 / (N_eff + 10.0));
    real z_skewness = skewness / (se_skewness + epsilon_div);

    if (!is_nan(z_skewness) && !is_inf(z_skewness)) {
      target += lambda_skew * std_normal_lpdf(z_skewness);
    }

    // Normal sum prior
    target += normal_lpdf(sum_w | N_train, sigma_sum_w);
  }
}

generated quantities {
  // ============================================================================
  // HOLDOUT EVALUATION VIA GAUSS-HERMITE QUADRATURE
  // ============================================================================

  vector[N_holdout] holdout_loglik = rep_vector(0, N_holdout);
  vector[N_holdout] holdout_deviance = rep_vector(0, N_holdout);
  real fold_loss = 0;

  // For each holdout person, compute marginal likelihood via GH quadrature
  for (i_holdout in 1:N_holdout) {
    // Separate items by dimension
    vector[n_nodes] loglik_dim1 = rep_vector(0, n_nodes);
    vector[n_nodes] loglik_dim2 = rep_vector(0, n_nodes);

    int n_dim1 = 0;
    int n_dim2 = 0;

    // Accumulate log-likelihoods for each GH node
    for (k in 1:n_nodes) {
      real eta1 = gh_nodes[k];  // For dimension 1
      real eta2 = gh_nodes[k];  // For dimension 2

      // Loop over all items for this holdout person
      for (m in 1:M_holdout) {
        if (ivec_holdout[m] == i_holdout) {
          int j = jvec_holdout[m];
          int y = yvec_holdout[m];
          int k_max = K[j] - 1;

          real eta_d = (dimension[j] == 1) ? eta1 : eta2;
          real lp = beta1[j] * age_holdout[i_holdout] + eta_d;

          real p;
          if (y == 0) {
            p = inv_logit(tau[j] - lp);
          } else if (y == k_max) {
            real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
            p = 1 - inv_logit(tau_left - lp);
          } else {
            real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
            real tau_right = tau[j] + y * delta[dimension[j]];
            p = inv_logit(tau_right - lp) - inv_logit(tau_left - lp);
          }

          p = p + epsilon_prob;

          // Accumulate to appropriate dimension
          if (dimension[j] == 1) {
            loglik_dim1[k] += log(p);
            if (k == 1) n_dim1 += 1;
          } else {
            loglik_dim2[k] += log(p);
            if (k == 1) n_dim2 += 1;
          }
        }
      }
    }

    // Compute marginal log-likelihood via log-sum-exp
    real log_marginal_dim1 = negative_infinity();
    real log_marginal_dim2 = negative_infinity();

    if (n_dim1 > 0) {
      for (k in 1:n_nodes) {
        log_marginal_dim1 = log_sum_exp(log_marginal_dim1,
                                         log(gh_weights[k]) + loglik_dim1[k]);
      }
    } else {
      log_marginal_dim1 = 0;  // No items in this dimension
    }

    if (n_dim2 > 0) {
      for (k in 1:n_nodes) {
        log_marginal_dim2 = log_sum_exp(log_marginal_dim2,
                                         log(gh_weights[k]) + loglik_dim2[k]);
      }
    } else {
      log_marginal_dim2 = 0;  // No items in this dimension
    }

    // Total marginal log-likelihood (dimensions independent)
    holdout_loglik[i_holdout] = log_marginal_dim1 + log_marginal_dim2;

    // Per-person deviance (normalized by item count)
    if (n_items_holdout[i_holdout] > 0) {
      holdout_deviance[i_holdout] = -2 * holdout_loglik[i_holdout] / n_items_holdout[i_holdout];
    }
  }

  // Fold loss: mean deviance across holdout persons
  if (N_holdout > 0) {
    fold_loss = mean(holdout_deviance);
  }

  // ============================================================================
  // TRAINING DIAGNOSTICS (same as stable version)
  // ============================================================================

  real sum_w_final = sum(w);
  real sum_w_sq_final = dot_product(w, w);
  real N_eff_final = square(sum_w_final) / (sum_w_sq_final + epsilon_div);

  real mean_weight = mean(w);
  real min_weight = min(w);
  real max_weight = max(w);

  int n_excluded = 0;
  int n_included = 0;
  for (i in 1:N_train) {
    if (w[i] < 0.1) n_excluded += 1;
    if (w[i] > 0.9) n_included += 1;
  }

  // Person-level log-likelihood for training data
  vector[N_train] log_lik_train = person_loglik;
}

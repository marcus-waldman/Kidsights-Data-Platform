/**
 * Authenticity Screening - Holdout Model for LOOCV (Two-Dimensional with LKJ Correlation)
 *
 * This model estimates TWO ability parameters (eta_psychosocial and eta_developmental)
 * for a SINGLE held-out participant given FIXED item parameters from a model fitted
 * on N-1 participants.
 *
 * Purpose: Leave-One-Out Cross-Validation
 *   1. Fit main model on N-1 participants → extract tau, beta1, delta, eta_correlation
 *   2. Pass those as DATA (fixed/known) to this model
 *   3. Estimate eta_psychosocial_holdout and eta_developmental_holdout for held-out person
 *   4. Extract log-posterior = sum(log_lik) + log_prior(eta_holdout)
 *   5. Calculate avg_logpost = log_posterior / M_holdout
 *
 * Model Structure:
 *   Same as main model (authenticity_glmm.stan), but:
 *   - Item parameters (tau, beta1, delta, eta_correlation) are DATA, not parameters
 *   - Only eta_std_holdout (standardized abilities) is estimated
 *   - Applied to single person's responses across both dimensions
 *
 * Parameters:
 *   eta_std_holdout: Standardized abilities (uncorrelated, length 2 vector)
 *
 * Transformed Parameters:
 *   eta_holdout: Correlated abilities (transformed via L_Omega)
 *   eta_psychosocial_holdout: eta_holdout[1]
 *   eta_developmental_holdout: eta_holdout[2]
 *
 * Priors:
 *   eta_std_holdout ~ std_normal() → eta_holdout ~ MVN(0, Omega) where Omega has correlation = eta_correlation
 */

data {
  // Fixed item parameters from N-1 model fit
  int<lower=1> J;                    // Number of items (same as main model)
  vector[J] tau;                      // Item thresholds (FIXED from N-1 fit)
  vector[J] beta1;                    // Age slopes (FIXED from N-1 fit)
  vector<lower=0>[2] delta;           // Threshold spacing (FIXED from N-1 fit, dimension-specific)
  array[J] int<lower=2> K;            // Number of categories per item (FIXED)
  array[J] int<lower=1, upper=2> dimension;  // Dimension assignment (FIXED)
  real<lower=-1, upper=1> eta_correlation;   // Correlation between dimensions (FIXED from N-1 fit)

  // Held-out person's data
  int<lower=1> M_holdout;             // Number of observations for this person
  array[M_holdout] int<lower=1, upper=J> j_holdout;  // Which items answered
  array[M_holdout] int<lower=0> y_holdout;           // Response values
  real age_holdout;                   // Age of held-out person
}

transformed data {
  // Construct Cholesky factor from correlation (same as main model)
  matrix[2, 2] L_Omega;
  L_Omega[1, 1] = 1;
  L_Omega[1, 2] = 0;
  L_Omega[2, 1] = eta_correlation;
  L_Omega[2, 2] = sqrt(1 - square(eta_correlation));
}

parameters {
  // Standardized abilities (uncorrelated, to be transformed)
  vector[2] eta_std_holdout;
}

transformed parameters {
  // Transform to correlated abilities (matching main model)
  vector[2] eta_holdout = L_Omega * eta_std_holdout;

  // Extract individual dimensions for backward compatibility
  real eta_psychosocial_holdout = eta_holdout[1];
  real eta_developmental_holdout = eta_holdout[2];
}

model {
  // Prior on standardized abilities (induces correlated prior on eta_holdout)
  eta_std_holdout ~ std_normal();

  // Likelihood (same structure as main model)
  for (m in 1:M_holdout) {
    int j = j_holdout[m];   // Item index
    int y = y_holdout[m];   // Response value
    int k_max = K[j] - 1;   // Maximum response for this item

    // Select eta based on item's dimension
    real eta_d = (dimension[j] == 1) ? eta_psychosocial_holdout : eta_developmental_holdout;

    // Linear predictor (using FIXED item parameters and age)
    real lp = beta1[j] * age_holdout + eta_d;

    // Calculate probability (same logic as main model)
    real p;

    if (y == 0) {
      // Lowest category
      real tau_right = tau[j];
      p = inv_logit(tau_right - lp);

    } else if (y == k_max) {
      // Highest category
      real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
      p = 1 - inv_logit(tau_left - lp);

    } else {
      // Interior category
      real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
      real tau_right = tau[j] + y * delta[dimension[j]];
      p = inv_logit(tau_right - lp) - inv_logit(tau_left - lp);
    }

    // Numerical safeguard
    p = fmax(p, 1e-10);

    // Add log-likelihood contribution
    target += log(p);
  }
}

generated quantities {
  // Log-likelihood for each observation (for diagnostics)
  vector[M_holdout] log_lik_holdout;

  // Total log-likelihood (sum across all observations)
  real total_log_lik = 0;

  // Log-prior for correlated bivariate normal
  // Since eta_std_holdout ~ std_normal() (independent), compute log-prior from that:
  // log_prior = -0.5 * sum(eta_std^2) - log(2*pi)
  real log_prior_total = -0.5 * dot_product(eta_std_holdout, eta_std_holdout) - log(2 * pi());

  // Log-posterior = log-likelihood + log-prior
  // Note: Stan's target += already computes this during sampling/optimization
  // but we calculate it explicitly here for extraction

  // Compute observation-level log-likelihoods
  for (m in 1:M_holdout) {
    int j = j_holdout[m];
    int y = y_holdout[m];
    int k_max = K[j] - 1;

    // Select eta based on item's dimension
    real eta_d = (dimension[j] == 1) ? eta_psychosocial_holdout : eta_developmental_holdout;

    real lp = beta1[j] * age_holdout + eta_d;

    real p;

    if (y == 0) {
      real tau_right = tau[j];
      p = inv_logit(tau_right - lp);

    } else if (y == k_max) {
      real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
      p = 1 - inv_logit(tau_left - lp);

    } else {
      real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
      real tau_right = tau[j] + y * delta[dimension[j]];
      p = inv_logit(tau_right - lp) - inv_logit(tau_left - lp);
    }

    p = fmax(p, 1e-10);
    log_lik_holdout[m] = log(p);
    total_log_lik += log(p);
  }

  // Log-posterior (to be extracted in R)
  real log_posterior = total_log_lik + log_prior_total;
}

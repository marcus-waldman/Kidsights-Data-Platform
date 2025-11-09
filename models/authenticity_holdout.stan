/**
 * Authenticity Screening - Holdout Model for LOOCV
 *
 * This model estimates the ability parameter (eta) for a SINGLE held-out participant
 * given FIXED item parameters from a model fitted on N-1 participants.
 *
 * Purpose: Leave-One-Out Cross-Validation
 *   1. Fit main model on N-1 participants → extract tau, beta1, delta
 *   2. Pass those as DATA (fixed/known) to this model
 *   3. Estimate only eta_holdout for the held-out person
 *   4. Extract log-posterior = sum(log_lik) + log_prior(eta_holdout)
 *   5. Calculate avg_logpost = log_posterior / M_holdout
 *
 * Model Structure:
 *   Same as main model (authenticity_glmm.stan), but:
 *   - Item parameters (tau, beta1, delta) are DATA, not parameters
 *   - Only eta_holdout is estimated
 *   - Applied to single person's responses
 *
 * Parameters:
 *   eta_holdout: Person ability parameter for held-out individual
 *
 * Prior:
 *   eta_holdout ~ normal(0, 1) [standard normal, matching main model]
 */

data {
  // Fixed item parameters from N-1 model fit
  int<lower=1> J;                    // Number of items (same as main model)
  vector[J] tau;                      // Item thresholds (FIXED from N-1 fit)
  vector[J] beta1;                    // Age slopes (FIXED from N-1 fit)
  real<lower=0> delta;                // Threshold spacing (FIXED from N-1 fit)
  array[J] int<lower=2> K;            // Number of categories per item (FIXED)

  // Held-out person's data
  int<lower=1> M_holdout;             // Number of observations for this person
  array[M_holdout] int<lower=1, upper=J> j_holdout;  // Which items answered
  array[M_holdout] int<lower=0> y_holdout;           // Response values
  real age_holdout;                   // Age of held-out person
}

parameters {
  // ONLY parameter to estimate: ability of held-out person
  real eta_holdout;
}

model {
  // Prior on eta (standard normal, matching main model)
  eta_holdout ~ std_normal();

  // Likelihood (same structure as main model)
  for (m in 1:M_holdout) {
    int j = j_holdout[m];   // Item index
    int y = y_holdout[m];   // Response value
    int k_max = K[j] - 1;   // Maximum response for this item

    // Linear predictor (using FIXED item parameters and age)
    real lp = beta1[j] * age_holdout + eta_holdout;

    // Calculate probability (same logic as main model)
    real p;

    if (y == 0) {
      // Lowest category
      real tau_right = tau[j];
      p = inv_logit(tau_right - lp);

    } else if (y == k_max) {
      // Highest category
      real tau_left = tau[j] + (y - 1) * delta;
      p = 1 - inv_logit(tau_left - lp);

    } else {
      // Interior category
      real tau_left = tau[j] + (y - 1) * delta;
      real tau_right = tau[j] + y * delta;
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

  // Log-prior for eta_holdout
  // For std_normal(): log_prior = -0.5 * eta_holdout^2 - 0.5 * log(2*pi)
  real log_prior = -0.5 * square(eta_holdout) - 0.5 * log(2 * pi());

  // Log-posterior = log-likelihood + log-prior
  // Note: Stan's target += already computes this during sampling/optimization
  // but we calculate it explicitly here for extraction

  // Compute observation-level log-likelihoods
  for (m in 1:M_holdout) {
    int j = j_holdout[m];
    int y = y_holdout[m];
    int k_max = K[j] - 1;

    real lp = beta1[j] * age_holdout + eta_holdout;

    real p;

    if (y == 0) {
      real tau_right = tau[j];
      p = inv_logit(tau_right - lp);

    } else if (y == k_max) {
      real tau_left = tau[j] + (y - 1) * delta;
      p = 1 - inv_logit(tau_left - lp);

    } else {
      real tau_left = tau[j] + (y - 1) * delta;
      real tau_right = tau[j] + y * delta;
      p = inv_logit(tau_right - lp) - inv_logit(tau_left - lp);
    }

    p = fmax(p, 1e-10);
    log_lik_holdout[m] = log(p);
    total_log_lik += log(p);
  }

  // Log-posterior (to be extracted in R)
  real log_posterior = total_log_lik + log_prior;
}

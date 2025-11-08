/**
 * Authenticity Screening GLMM
 *
 * Generalized linear mixed model for screening false negatives in authenticity
 * validation using item response patterns and age.
 *
 * Model:
 *   P(y_ij = k) = logit^-1(tau_right + lp) - logit^-1(tau_left + lp)
 *
 *   where:
 *     tau_left = -Inf if k=0, else tau[j] + (k-1)*delta
 *     tau_right = +Inf if k=K[j]-1, else tau[j] + k*delta
 *     lp = beta1[j] * age[i] + alpha*eta[i]
 *
 * Parameters:
 *   tau[j]: First threshold (0->1) for item j
 *   beta1[j]: Age slope for item j
 *   delta: Threshold spacing (positive, shared across items)
 *   sigma: Person random effect SD
 *   eta[i]: Person random effect
 *
 * Priors:
 *   tau ~ N(0, 5)
 *   beta1 ~ N(0, 2)
 *   delta ~ student_t(3, 0, 1) [0, Inf]
 *   sigma ~ student_t(3, 0, 1) [0, Inf]
 *   eta ~ N(0, sigma)
 */

data {
  int<lower=1> M;              // Total number of observations
  int<lower=1> N;              // Number of persons
  int<lower=1> J;              // Number of items

  array[M] int<lower=1, upper=N> ivec;  // Person index for each observation
  array[M] int<lower=1, upper=J> jvec;  // Item index for each observation
  array[M] int<lower=0> yvec;           // Response value for each observation

  vector[N] age;               // Age in years for each person
  array[J] int<lower=2> K;     // Number of categories for each item
}

parameters {
  vector[J] tau;               // First threshold for each item
  vector[J] beta1;             // Age slope for each item

  real<lower=0> delta;         // Threshold spacing (positive)
  sum_to_zero_vector[N] eta;
}

transformed parameters {
}

model {
  // Priors
  tau ~ normal(0, 5);
  beta1 ~ normal(0, 2);
  delta ~ student_t(3, 0, 1);
  eta ~ std_normal();
  
  // Likelihood
  for (m in 1:M) {
    int i = ivec[m];      // Person index
    int j = jvec[m];      // Item index
    int y = yvec[m];      // Response value
    int k_max = K[j] - 1; // Maximum response value for this item

    // Linear predictor
    real lp = beta1[j] * age[i] + eta[i];

    // Calculate probability (simplified to avoid infinities)
    real p;

    if (y == 0) {
      // Lowest category: p_left = 0, so p = p_right
      real tau_right = tau[j];  // First threshold
      p = inv_logit(tau_right + lp);

    } else if (y == k_max) {
      // Highest category: p_right = 1, so p = 1 - p_left
      real tau_left = tau[j] + (y - 1) * delta;
      p = 1 - inv_logit(tau_left + lp);

    } else {
      // Interior category: p = p_right - p_left
      real tau_left = tau[j] + (y - 1) * delta;
      real tau_right = tau[j] + y * delta;
      p = inv_logit(tau_right + lp) - inv_logit(tau_left + lp);
    }

    // Add small constant to avoid log(0)
    p = fmax(p, 1e-10);

    // Log-likelihood contribution
    target += log(p);
  }
}

generated quantities {
  // Person-level log-likelihood for lz calculation
  vector[N] log_lik;

  // Initialize to zero
  log_lik = rep_vector(0, N);

  // Accumulate log-likelihood for each person
  for (m in 1:M) {
    int i = ivec[m];
    int j = jvec[m];
    int y = yvec[m];
    int k_max = K[j] - 1;

    real lp = beta1[j] * age[i] + eta[i];

    // Calculate probability (simplified to avoid infinities)
    real p;

    if (y == 0) {
      real tau_right = tau[j];
      p = inv_logit(tau_right + lp);

    } else if (y == k_max) {
      real tau_left = tau[j] + (y - 1) * delta;
      p = 1 - inv_logit(tau_left + lp);

    } else {
      real tau_left = tau[j] + (y - 1) * delta;
      real tau_right = tau[j] + y * delta;
      p = inv_logit(tau_right + lp) - inv_logit(tau_left + lp);
    }

    // Numerical safeguard
    p = fmax(p, 1e-10);

    log_lik[i] += log(p);
  }
}

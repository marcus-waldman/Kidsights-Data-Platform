/**
 * LOO Authenticity Screening GLMM - Two-Dimensional IRT Model with LKJ(1) Prior
 * L_Omega is data, not a parameter
 *
 * Allows correlation between psychosocial and developmental dimensions
 * using a non-informative LKJ(1) prior (uniform over all correlations).
 *
 * Model:
 *   P(y_ij = k) = logit^-1(tau_right - lp) - logit^-1(tau_left - lp)
 *
 *   where:
 *     tau_left = -Inf if k=0, else tau[j] + (k-1)*delta
 *     tau_right = +Inf if k=K[j]-1, else tau[j] + k*delta
 *     lp = beta1[j] * age[i] + eta[i, d]
 *     d = 1 if dimension[j]=1 (psychosocial), else 2 (developmental)
 *
 * Parameters:
 *   tau[j]: First threshold (0->1) for item j
 *   beta1[j]: Age slope for item j
 *   delta[d]: Threshold spacing (positive, dimension-specific: d=1 psychosocial, d=2 developmental)
 *   eta[i, 1]: Person random effect for psychosocial dimension ~ N(0, 1) marginally
 *   eta[i, 2]: Person random effect for developmental dimension ~ N(0, 1) marginally
 *
 * Priors:
 *   tau ~ N(0, 5)
 *   beta1 ~ N(0, 2)
 *   delta ~ student_t(3, 0, 1) [0, Inf] (vectorized, applies to both dimensions)
 *   eta_std ~ N(0, 1) [standardized, then transformed to correlated with var=1]
 *
 * Design Notes:
 *   - Marginal distributions are EXACTLY standard normal: eta[i,d] ~ N(0, 1)
 *   - Only correlation is estimated, not variances (fixed at 1)
 *   - Use non-centered parameterization (eta_std) for better sampling efficiency
 *   - Correlation matrix extracted in generated quantities
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
  array[J] int<lower=1, upper=2> dimension;  // Dimension assignment: 1=psychosocial, 2=developmental
  
  cholesky_factor_corr[2] L_Omega;  // Cholesky factor of correlation matrix

}

parameters {
  vector[J] tau;               // First threshold for each item
  vector[J] beta1;             // Age slope for item j

  vector<lower=0>[2] delta;    // Threshold spacing (positive, dimension-specific)

  // Correlated person effects (multivariate normal with unit variance)
  matrix[N, 2] eta_std;        // Standardized (uncorrelated) person effects
}

transformed parameters {
  matrix[N, 2] eta;  // Correlated person effects with marginal variance = 1

  // Transform standardized effects to correlated effects
  // eta ~ MVN(0, Omega) where Omega is the correlation matrix (diagonal = 1)
  eta = eta_std * L_Omega';
}

model {

  // Priors on item parameters
  tau ~ normal(0, 5);
  beta1 ~ normal(0, 2);
  delta ~ student_t(3, 0, 1);


  // Standardized person effects (uncorrelated, unit variance)
  to_vector(eta_std) ~ std_normal();

  // Likelihood
  for (m in 1:M) {
    int i = ivec[m];      // Person index
    int j = jvec[m];      // Item index
    int y = yvec[m];      // Response value
    int k_max = K[j] - 1; // Maximum response value for this item

    // Select eta based on item's dimension (1=psychosocial, 2=developmental)
    real eta_d = (dimension[j] == 1) ? eta[i, 1] : eta[i, 2];

    // Linear predictor
    real lp = beta1[j] * age[i] + eta_d;

    // Calculate probability (simplified to avoid infinities)
    real p;

    if (y == 0) {
      // Lowest category: p_left = 0, so p = p_right
      real tau_right = tau[j];  // First threshold
      p = inv_logit(tau_right - lp);

    } else if (y == k_max) {
      // Highest category: p_right = 1, so p = 1 - p_left
      real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
      p = 1 - inv_logit(tau_left - lp);

    } else {
      // Interior category: p = p_right - p_left
      real tau_left = tau[j] + (y - 1) * delta[dimension[j]];
      real tau_right = tau[j] + y * delta[dimension[j]];
      p = inv_logit(tau_right - lp) - inv_logit(tau_left - lp);
    }

    // Add small constant to avoid log(0)
    p = fmax(p, 1e-10);

    // Log-likelihood contribution
    target += log(p);
  }
}

generated quantities {
  // Reconstruct correlation matrix from Cholesky factor
  corr_matrix[2] Omega = L_Omega * L_Omega';

  // Extract correlation between dimensions
  real eta_correlation = Omega[1, 2];

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

    // Select eta based on item's dimension
    real eta_d = (dimension[j] == 1) ? eta[i, 1] : eta[i, 2];

    real lp = beta1[j] * age[i] + eta_d;

    // Calculate probability (simplified to avoid infinities)
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

    // Numerical safeguard
    p = fmax(p, 1e-10);

    log_lik[i] += log(p);
  }
}

/**
 * Authenticity Screening GLMM - Two-Dimensional IRT with Latent Regression
 *
 * Extends the base 2D IRT model with latent regression to predict person effects
 * from demographic covariates.
 *
 * Latent Regression Model:
 *   eta[i] ~ MVN(X[i] * beta, Sigma)
 *
 *   where:
 *     X[i]: 1 × P covariate vector for person i (P = 9: intercept + 4 main + 4 interactions)
 *     beta: P × 2 regression coefficient matrix (P covariates × 2 dimensions)
 *     Sigma: 2 × 2 covariance matrix = L_Sigma * L_Sigma'
 *            L_Sigma: Cholesky factor of covariance (encodes variances + correlation)
 *            Prior: Element-wise (student_t for diagonal, normal for off-diagonal)
 *
 * Covariate Design Matrix (P = 9):
 *   X[i] = [1, female, college, above_fpl_185, no_depression,
 *           female*age_c, college*age_c, above_fpl_185*age_c, no_depression*age_c]
 *   where age_c = age - 3 (centered at 3 years)
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
 *   delta[d]: Threshold spacing (positive, dimension-specific)
 *   beta[p, d]: Regression coefficients (P × 2) for predicting eta from covariates
 *               beta[1,d] = intercept (expected eta at age 3 for reference person)
 *               beta[2-5,d] = main effects (female, college, above_fpl_185, no_depression)
 *               beta[6-9,d] = age interactions (how effects change per year from age 3)
 *   eta_psychosocial_raw[i]: Raw person residual (sum-to-zero, psychosocial dimension)
 *   eta_developmental_raw[i]: Raw person residual (sum-to-zero, developmental dimension)
 *   L_Sigma: Cholesky factor of covariance matrix (2×2)
 *   eta_std[i, d]: Standardized person residuals (unit variance, uncorrelated)
 *   eta[i, d]: Person random effect (residual after accounting for covariates)
 *              Covariance structure: Sigma = L_Sigma * L_Sigma'
 *
 * Priors:
 *   tau ~ N(0, 5)
 *   beta1 ~ N(0, 2)
 *   delta ~ student_t(3, 0, 1) [0, Inf]
 *   beta[p, d] ~ N(0, 1)  [regression coefficients, weakly informative]
 *   L_Sigma[1,1], L_Sigma[2,2] ~ student_t(3, 0, 1)  [diagonal: SDs, weakly informative]
 *   L_Sigma[2,1] ~ N(0, 1)  [off-diagonal: covariance element]
 *   eta_*_raw ~ N(0, 1)  [raw residuals, sum-to-zero, standardized in transformed parameters]
 *
 * Design Notes:
 *   - Intercept: Expected eta for reference person (male, no college, <185% FPL,
 *                depressed) at age 3 years
 *   - Age centering at 3: Makes intercept interpretable and reduces collinearity
 *   - Covariance structure: Sigma = L_Sigma * L_Sigma' (direct parameterization)
 *     - Single Cholesky factor encodes variances and correlation
 *     - Extracted in generated quantities: sigma_eta_*, eta_correlation
 *   - Covariates predict person effects: higher SES → higher developmental scores
 *   - Residual constraints: sum-to-zero, then explicitly standardized to unit variance
 *   - Transformation pipeline: eta_raw (sum-to-zero) → eta_std (standardized) → eta (covariance via L_Sigma)
 *   - Non-centered parameterization: eta = X*beta + eta_std * L_Sigma'
 *   - No discrimination parameters: variance enters through covariance matrix Sigma
 */

data {
  int<lower=1> M;              // Total number of observations
  int<lower=1> N;              // Number of persons
  int<lower=1> J;              // Number of items
  int<lower=1> P;              // Number of covariates (9: intercept + 4 main + 4 interactions)

  array[M] int<lower=1, upper=N> ivec;  // Person index for each observation
  array[M] int<lower=1, upper=J> jvec;  // Item index for each observation
  array[M] int<lower=0> yvec;           // Response value for each observation

  vector[N] age;               // Age in years for each person
  matrix[N, P] X;              // Covariate matrix (N × P)
  array[J] int<lower=2> K;     // Number of categories for each item
  array[J] int<lower=1, upper=2> dimension;  // Dimension: 1=psychosocial, 2=developmental
}

parameters {
  vector[J] tau;               // First threshold for each item
  vector[J] beta1;             // Age slope for item j

  vector<lower=0>[2] delta;    // Threshold spacing (positive, dimension-specific)

  // Latent regression coefficients (P × 2)
  matrix[P, 2] beta;           // Covariate effects on person effects

  // Uncorrelated zero-sum person residuals (raw, before standardization)
  sum_to_zero_vector[N] eta_psychosocial_raw;
  sum_to_zero_vector[N] eta_developmental_raw;

  cholesky_factor_cov[2] L_Sigma;  // Cholesky factor of covariance matrix
}

transformed parameters {
  // Standardized person residuals (unit variance, uncorrelated)
  matrix[N, 2] eta_std;
  real sd_eta_psychosocial = sd(eta_psychosocial_raw);
  real sd_eta_developmental = sd(eta_developmental_raw);
  eta_std[1:N, 1] = eta_psychosocial_raw / sd_eta_psychosocial;
  eta_std[1:N, 2] = eta_developmental_raw / sd_eta_developmental;

  // Correlated person residuals with free covariance structure
  // Covariance: Sigma = L_Sigma * L_Sigma'
  matrix[N, 2] eta;

  // Latent regression: eta = X*beta + residuals
  // Transform: apply covariance structure directly via L_Sigma
  eta = X * beta + eta_std * L_Sigma';
}

model {

  // Priors on item parameters
  tau ~ normal(0, 5);
  beta1 ~ normal(0, 2);
  delta ~ student_t(3, 0, 1);

  // Prior on latent regression coefficients (weakly informative)
  to_vector(beta) ~ normal(0, 1);

  // Prior on covariance matrix Cholesky factor (element-wise)
  // Diagonal elements: standard deviations (weakly informative, positive)
  L_Sigma[1, 1] ~ student_t(3, 0, 1);  // SD of psychosocial dimension
  L_Sigma[2, 2] ~ student_t(3, 0, 1);  // SD of developmental dimension
  // Off-diagonal: covariance element (induces correlation)
  L_Sigma[2, 1] ~ normal(0, 1);        // Covariance term

  // Vectorized prior on raw person residuals (sum-to-zero, standardized in transformed params)
  eta_psychosocial_raw ~ std_normal();
  eta_developmental_raw ~ std_normal();

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
  // Reconstruct covariance matrix from Cholesky factor
  cov_matrix[2] Sigma = L_Sigma * L_Sigma';

  // Extract standard deviations
  real sigma_eta_psychosocial = sqrt(Sigma[1, 1]);
  real sigma_eta_developmental = sqrt(Sigma[2, 2]);

  // Extract correlation between dimensions
  real eta_correlation = Sigma[1, 2] / (sigma_eta_psychosocial * sigma_eta_developmental);

  // Person-level log-likelihood for model comparison
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

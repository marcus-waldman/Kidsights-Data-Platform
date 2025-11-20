/**
 * Authenticity Screening GLMM - Two-Dimensional IRT with Skewness Penalty (BETA VERSION)
 *
 * Key differences from simplex version:
 *   - Uses INDEPENDENT Beta(alpha_wgt, beta_wgt) priors on each weight
 *   - No simplex constraint - weights can vary freely in [0, 1]
 *   - Skewness penalty uses sum(w) explicitly (not assuming sum = N)
 *   - INDEPENDENT person effects (no correlation between dimensions)
 *
 * This model simultaneously:
 *   - Estimates item parameters (tau, beta1, delta)
 *   - Estimates person effects (eta ~ N(0,1), independent by dimension)
 *   - Estimates participant weights (w_i ~ Beta) that minimize weighted skewness
 *
 * Design Philosophy:
 *   - Authentic participants should have symmetric t-distribution
 *   - Inauthentic participants create left skew in response patterns
 *   - Down-weighting them via w[i] → 0 restores symmetry
 *   - Beta(alpha, beta) prior: alpha<1, beta>1 → encourages w→0 (sparse)
 *   - Beta(alpha, beta) prior: alpha>1, beta<1 → encourages w→1 (dense)
 *   - Beta(1, 1) = Uniform[0, 1] (non-informative)
 *
 * Key Features:
 *   - Within-person t-statistics: t_i = (mean_i - μ_weighted) / (sd_i / √M_i)
 *   - Precision-weighted population mean: μ = sum(M_i × w_i × loglik_i) / sum(M_i × w_i)
 *   - Weighted skewness: accounts for current w values in mean/var/skew
 *   - Effective sample size: N_eff = (sum(w))² / sum(w²) adjusts SE for weight heterogeneity
 *   - Probabilistic penalty: -λ_skew × std_normal_lpdf(z_skewness)
 *   - Post-hoc thresholding: w < 0.1 → exclude, w > 0.9 → include
 *
 * Hyperparameters:
 *   - alpha_wgt, beta_wgt: Beta distribution shape parameters
 *     - Sparse (favor exclusion): alpha=0.5, beta=2 → E[w]=0.2, mode=0
 *     - Moderate: alpha=1, beta=1 → Uniform
 *     - Dense (favor inclusion): alpha=2, beta=0.5 → E[w]=0.8, mode=1
 *   - lambda_skew: Skewness penalty strength (recommend 1.0 = equal to likelihood)
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

  // Penalty strength and Beta prior parameters
  real<lower=0> lambda_skew;   // Skewness penalty coefficient
  real<lower=0> alpha_wgt;     // Beta prior shape parameter 1
  real<lower=0> beta_wgt;      // Beta prior shape parameter 2
}

transformed data {
  // Count number of items per person (computed from data)
  array[N] int n_items = rep_array(0, N);

  for (m in 1:M) {
    n_items[ivec[m]] += 1;
  }
}

parameters {
  vector[J] tau;               // First threshold for each item
  vector[J] beta1;             // Age slope for item j

  vector<lower=0>[2] delta;    // Threshold spacing (positive, dimension-specific)

  // INDEPENDENT person effects (no correlation between dimensions)
  vector[N] eta_psychosocial;  // Person effects for dimension 1 (psychosocial)
  vector[N] eta_developmental; // Person effects for dimension 2 (developmental)

  // Participant weights (independent Beta priors, NO simplex constraint)
  vector<lower=0.1, upper=1>[N] w;  // Weights in [0, 1], sum NOT constrained
}

transformed parameters {
  matrix[N, 2] eta;            // Person effects matrix (for compatibility)

  // Person-level statistics for t-computation
  vector[N] person_loglik;     // Sum of log-likelihoods per person
  vector[N] person_loglik_sq;  // Sum of squared log-likelihoods per person

  // t-statistics (n_items computed in transformed data)
  vector[N] mean_loglik;       // Mean log-likelihood per person
  vector[N] sd_loglik;         // Within-person SD of log-likelihoods
  vector[N] t_stat;            // t-statistic for each person

  // Construct eta matrix from independent vectors
  eta[, 1] = eta_psychosocial;
  eta[, 2] = eta_developmental;

  // Initialize person-level accumulators
  person_loglik = rep_vector(0, N);
  person_loglik_sq = rep_vector(0, N);

  // Accumulate item-level log-likelihoods
  for (m in 1:M) {
    int i = ivec[m];
    int j = jvec[m];
    int y = yvec[m];
    int k_max = K[j] - 1;

    // Select eta based on item's dimension
    real eta_d = (dimension[j] == 1) ? eta[i, 1] : eta[i, 2];

    // Linear predictor
    real lp = beta1[j] * age[i] + eta_d;

    // Calculate probability
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

    // Item-level log-likelihood
    real item_loglik = log(p);

    // Accumulate for person i
    person_loglik[i] += item_loglik;
    person_loglik_sq[i] += square(item_loglik);
  }

  // Compute per-person statistics
  for (i in 1:N) {
    if (n_items[i] > 1) {
      // Mean log-likelihood per item
      mean_loglik[i] = person_loglik[i] / n_items[i];

      // Within-person SD using sum of squares formula
      // Var = E[X^2] - E[X]^2
      real var_loglik = (person_loglik_sq[i] / n_items[i]) - square(mean_loglik[i]);
      sd_loglik[i] = sqrt(fmax(var_loglik, 1e-10));  // Safeguard against negative variance

    } else {
      // Only 1 item - cannot compute SD
      mean_loglik[i] = person_loglik[i];
      sd_loglik[i] = 1.0;  // Default (prevents division by zero)
    }
  }

  // Compute precision-weighted population mean (weighted by both M_i and w_i)
  {
    real sum_weighted_loglik = 0;
    real sum_weighted_items = 0;

    for (i in 1:N) {
      sum_weighted_loglik += w[i] * n_items[i] * mean_loglik[i];
      sum_weighted_items += w[i] * n_items[i];
    }

    real mu_weighted = sum_weighted_loglik / fmax(sum_weighted_items, 1.0);  // Safeguard

    // Compute t-statistics
    for (i in 1:N) {
      if (n_items[i] > 1) {
        // t_i = (mean_i - mu_weighted) / (sd_i / sqrt(M_i))
        real se_i = sd_loglik[i] / sqrt(n_items[i]);
        t_stat[i] = (mean_loglik[i] - mu_weighted) / se_i;
      } else {
        t_stat[i] = 0.0;  // Undefined for single item
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

  // INDEPENDENT priors on person effects (no correlation)
  eta_psychosocial ~ std_normal();
  eta_developmental ~ std_normal();

  // Beta prior on weights (INDEPENDENT, NOT simplex)
  // alpha_wgt < 1, beta_wgt > 1: Sparse (encourages w → 0)
  // alpha_wgt = 1, beta_wgt = 1: Uniform
  // alpha_wgt > 1, beta_wgt < 1: Dense (encourages w → 1)
  w ~ beta(alpha_wgt, beta_wgt);

  // ============================================================================
  // WEIGHTED LIKELIHOOD
  // ============================================================================

  for (i in 1:N) {
    // Weight person i's log-likelihood by w[i]
    target += w[i] * person_loglik[i];
  }

  // ============================================================================
  // WEIGHTED SKEWNESS PENALTY
  // ============================================================================

  {
    // Weighted statistics account for down-weighted participants
    // Uses current weight values (creates feedback loop toward symmetry)
    // Note: sum(w) is NOT constrained (can be < N or > N)

    real sum_w = sum(w);  // Compute sum explicitly
    real sum_w_sq = dot_product(w, w);

    // Effective sample size (Kish formula)
    // Accounts for variance inflation from unequal weights
    real N_eff = square(sum_w) / fmax(sum_w_sq, 1.0);  // Safeguard: N_eff >= sum_w

    // Weighted mean (point estimate under weighted distribution)
    real mean_t_weighted = dot_product(w, t_stat) / fmax(sum_w, 1.0);  // Safeguard

    // Weighted variance (point estimate)
    vector[N] t_centered = t_stat - mean_t_weighted;
    real var_t_weighted = dot_product(w, t_centered .* t_centered) / fmax(sum_w, 1.0);
    real sd_t_weighted = sqrt(fmax(var_t_weighted, 1e-10));  // Safeguard: SD >= 1e-5

    // Weighted standardization
    vector[N] t_std = t_centered / sd_t_weighted;

    // Weighted skewness (point estimate)
    real skewness = dot_product(w, t_std .* t_std .* t_std) / fmax(sum_w, 1.0);

    // Standard error of skewness (uses N_eff for sampling variance)
    // Under normality: Var(skewness) ≈ 6 / N_eff
    real se_skewness = sqrt(6.0 / fmax(N_eff, 10.0));  // Safeguard: N_eff >= 10

    // Z-score: standardized skewness
    real z_skewness = skewness / fmax(se_skewness, 1e-5);  // Safeguard against tiny SE

    // Probabilistic penalty: skewness ~ N(0, 6/N_eff) implies z ~ N(0,1)
    // lambda_skew = 1 means "skewness prior has equal weight to likelihood"
    // Only apply penalty if z_skewness is finite
    if (!is_nan(z_skewness) && !is_inf(z_skewness)) {
      target += lambda_skew * std_normal_lpdf(z_skewness);
    }
  }

}

generated quantities {
  // No correlation to report (independence model)

  // Weighted skewness diagnostics (using sum(w) explicitly)
  real sum_w_final = sum(w);
  real sum_w_sq_final = dot_product(w, w);
  real N_eff_final = square(sum_w_final) / fmax(sum_w_sq_final, 1.0);

  real mean_t_weighted_final = dot_product(w, t_stat) / fmax(sum_w_final, 1.0);
  vector[N] t_centered_final = t_stat - mean_t_weighted_final;
  real var_t_weighted_final = dot_product(w, t_centered_final .* t_centered_final) / fmax(sum_w_final, 1.0);
  real sd_t_weighted_final = sqrt(fmax(var_t_weighted_final, 1e-10));

  vector[N] t_std_final = t_centered_final / sd_t_weighted_final;
  real skewness_weighted_final = dot_product(w, t_std_final .* t_std_final .* t_std_final) / fmax(sum_w_final, 1.0);

  real se_skewness_final = sqrt(6.0 / fmax(N_eff_final, 10.0));
  real z_skewness_final = skewness_weighted_final / fmax(se_skewness_final, 1e-5);

  // Weight diagnostics
  real mean_weight = mean(w);  // NOT constrained to 1.0
  real min_weight = min(w);
  real max_weight = max(w);
  real sum_weight = sum_w_final;  // Can be anything in [0, N]

  // Count weights near boundaries (must loop, can't use vectorized comparison)
  int n_excluded = 0;
  int n_included = 0;
  for (i in 1:N) {
    if (w[i] < 0.1) n_excluded += 1;
    if (w[i] > 0.9) n_included += 1;
  }

  // Person-level log-likelihood (for compatibility with other models)
  vector[N] log_lik = person_loglik;
}

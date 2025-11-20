/**
 * Authenticity Screening GLMM - Two-Dimensional IRT with Skewness Penalty
 *
 * Extends authenticity_glmm.stan with:
 *   1. Participant weights w ~ Dirichlet(λ_wgt) on simplex, rescaled to sum(w) = N
 *   2. Weighted likelihood using w[i]
 *   3. t-statistic computation based on within-person SD and precision weighting
 *   4. Weighted skewness penalty with N_eff correction
 *
 * The model simultaneously:
 *   - Estimates item parameters (tau, beta1, delta, eta_correlation)
 *   - Estimates person effects (eta ~ MVN with correlation)
 *   - Estimates participant weights (w) that minimize weighted skewness
 *
 * Design Philosophy:
 *   - Authentic participants should have symmetric t-distribution
 *   - Inauthentic participants create left skew in response patterns
 *   - Down-weighting them via w[i] → 0 restores symmetry
 *   - Dirichlet(λ_wgt) prior: λ<1 sparse, λ=1 uniform, λ>1 dense
 *   - Simplex constraint (sum(w)=N) prevents degeneracy (all w→0)
 *
 * Key Features:
 *   - Within-person t-statistics: t_i = (mean_i - μ_weighted) / (sd_i / √M_i)
 *   - Precision-weighted population mean: μ = sum(M_i × loglik_i) / sum(M_i)
 *   - Weighted skewness: accounts for current w values in mean/var/skew
 *   - Effective sample size: N_eff = N² / sum(w²) adjusts SE for weight heterogeneity
 *   - Probabilistic penalty: -λ_skew × std_normal_lpdf(z_skewness)
 *   - Post-hoc thresholding: w < 0.1 → exclude, w > 0.9 → include
 *
 * Hyperparameters:
 *   - lambda_wgt: Dirichlet concentration (recommend 0.5-1.0 for moderate sparsity)
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

  // Penalty strength
  real<lower=0> lambda_skew;   // Skewness penalty coefficient
  real<lower=0> lambda_wgt;    // Dirichlet concentration parameter
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

  // Correlated person effects (multivariate normal with unit variance)
  matrix[N, 2] eta_std;        // Standardized (uncorrelated) person effects
  cholesky_factor_corr[2] L_Omega;  // Cholesky factor of correlation matrix

  // Participant weights (simplex: sum to 1, then rescaled to sum to N)
  simplex[N] w_raw;  // Raw weights on simplex (sum = 1)
}

transformed parameters {
  matrix[N, 2] eta;            // Correlated person effects with marginal variance = 1
  vector[N] w;                 // Rescaled weights (sum = N, mean = 1)

  // Person-level statistics for t-computation
  vector[N] person_loglik;     // Sum of log-likelihoods per person
  vector[N] person_loglik_sq;  // Sum of squared log-likelihoods per person

  // t-statistics (n_items computed in transformed data)
  vector[N] mean_loglik;       // Mean log-likelihood per person
  vector[N] sd_loglik;         // Within-person SD of log-likelihoods
  vector[N] t_stat;            // t-statistic for each person

  // Transform standardized effects to correlated effects
  eta = eta_std * L_Omega';

  // Rescale simplex weights to sum to N (mean = 1)
  w = N * w_raw;

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

  // Compute precision-weighted population mean (grand mean across all items)
  {
    real sum_total_loglik = sum(person_loglik);
    int sum_n_items = sum(n_items);
    real mu_weighted = sum_total_loglik / sum_n_items;

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

  // Prior on correlation matrix
  L_Omega ~ lkj_corr_cholesky(1);  // Uniform over all correlations

  // Standardized person effects (uncorrelated, unit variance)
  to_vector(eta_std) ~ std_normal();

  // Dirichlet prior on simplex weights
  // lambda_wgt < 1: Sparse (encourages some w → 0)
  // lambda_wgt = 1: Uniform over simplex (non-informative)
  // lambda_wgt > 1: Dense (discourages extreme weights)
  // Constraint: sum(w_raw) = 1 → sum(w) = N (prevents degeneracy)
  w_raw ~ dirichlet(rep_vector(lambda_wgt, N));

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
    // Note: sum(w) = N by construction (simplex constraint)

    // Effective sample size (Kish formula)
    // Accounts for variance inflation from unequal weights
    real sum_w_sq = dot_product(w, w);
    real N_eff = square(N) / fmax(sum_w_sq, 1.0);  // Safeguard: N_eff >= N

    // Weighted mean (point estimate under weighted distribution)
    // Divide by N since sum(w) = N
    real mean_t_weighted = dot_product(w, t_stat) / N;

    // Weighted variance (point estimate)
    vector[N] t_centered = t_stat - mean_t_weighted;
    real var_t_weighted = dot_product(w, t_centered .* t_centered) / N;
    real sd_t_weighted = sqrt(fmax(var_t_weighted, 1e-10));  // Safeguard: SD >= 1e-5

    // Weighted standardization
    vector[N] t_std = t_centered / sd_t_weighted;

    // Weighted skewness (point estimate)
    real skewness = dot_product(w, t_std .* t_std .* t_std) / N;

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
  // Reconstruct correlation matrix from Cholesky factor
  corr_matrix[2] Omega = L_Omega * L_Omega';

  // Extract correlation between dimensions
  real eta_correlation = Omega[1, 2];

  // Weighted skewness diagnostics (using sum(w) = N)
  real N_eff_final = square(N) / dot_product(w, w);

  real mean_t_weighted_final = dot_product(w, t_stat) / N;
  vector[N] t_centered_final = t_stat - mean_t_weighted_final;
  real var_t_weighted_final = dot_product(w, t_centered_final .* t_centered_final) / N;
  real sd_t_weighted_final = sqrt(var_t_weighted_final);

  vector[N] t_std_final = t_centered_final / sd_t_weighted_final;
  real skewness_weighted_final = dot_product(w, t_std_final .* t_std_final .* t_std_final) / N;

  real se_skewness_final = sqrt(6.0 / N_eff_final);
  real z_skewness_final = skewness_weighted_final / se_skewness_final;

  // Weight diagnostics
  real mean_weight = mean(w);  // Should be ≈ 1.0
  real min_weight = min(w);
  real max_weight = max(w);
  real sum_weight = N;  // Guaranteed by simplex constraint

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

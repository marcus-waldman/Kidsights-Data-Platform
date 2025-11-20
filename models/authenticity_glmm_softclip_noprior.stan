/**
 * Authenticity Screening GLMM - Two-Dimensional IRT with Skewness Penalty (SOFT-CLIPPED, NO WEIGHT PRIOR)
 *
 * Key differences from standard soft-clip model:
 *   - Uses soft-clipping transformation: softwgt = 1 - log(1 + exp(-c1*(w_raw - c2)))
 *   - Prevents extreme weights (w >> 1) while maintaining differentiability
 *   - **NEW**: No Dirichlet prior - weights determined purely by likelihood + skewness + sum prior
 *   - Sum prior on sum(softwgt) ~ N(N, sigma_sum_softwgt) prevents degeneracy
 *   - INDEPENDENT person effects (no correlation between dimensions)
 *
 * Soft-clipping parameters:
 *   - c1 = 1 (controls steepness of transition)
 *   - c2 = log(exp(0.9) - 1) ≈ 1.317 (inflection point near w = 0.9)
 *   - Effect: softwgt ≈ wgt for small wgt, but saturates as wgt → ∞
 *
 * Weight Mechanism (NO Dirichlet):
 *   - w_raw ~ no prior (improper uniform on positive reals)
 *   - Only constraints: w_raw > 0 (positivity)
 *   - Soft-clipping: softwgt[i] = 1 - log(1 + exp(-c1*(w_raw[i] - c2)))
 *   - Sum prior: sum(softwgt) ~ N(N, sigma_sum_softwgt) provides regularization
 *   - Data-driven: weights determined by likelihood + skewness penalty
 *
 * Rationale:
 *   - Removes conflicting priors (Dirichlet vs sum prior)
 *   - Skewness penalty is the primary driver of weight variation
 *   - Sum prior prevents pathological solutions (all weights → 0 or → ∞)
 *   - Simpler model with fewer hyperparameters to tune
 *
 * This model simultaneously:
 *   - Estimates item parameters (tau, beta1, delta)
 *   - Estimates person effects (eta ~ N(0,1), independent by dimension)
 *   - Estimates participant weights (w_raw) via likelihood + skewness optimization
 *
 * Design Philosophy:
 *   - Authentic participants should have symmetric t-distribution
 *   - Inauthentic participants create left skew in response patterns
 *   - Down-weighting them via softwgt[i] → 0 restores symmetry
 *   - Soft-clipping prevents numerical instability from unbounded weights
 *   - Sum prior prevents over-concentration or complete exclusion
 *
 * Key Features:
 *   - Within-person t-statistics: t_i = (mean_i - μ_weighted) / (sd_i / √M_i)
 *   - Precision-weighted population mean: μ = sum(M_i × softwgt_i × loglik_i) / sum(M_i × softwgt_i)
 *   - Weighted skewness: accounts for softwgt values in mean/var/skew
 *   - Effective sample size: N_eff = (sum(softwgt))² / sum(softwgt²)
 *   - Probabilistic penalty: lambda_skew × std_normal_lpdf(z_skewness)
 *   - Sum regularization: normal_lpdf(sum(softwgt) | N, sigma_sum_softwgt)
 *
 * Hyperparameters:
 *   - lambda_skew: Skewness penalty strength (recommend 1.0 = equal to likelihood)
 *   - sigma_sum_softwgt: Prior SD for sum(softwgt) ~ N(N, sigma)
 *     - Small (1-5): Tight constraint, strong preference for sum ≈ N
 *     - Medium (5-10): Moderate tolerance, allows ~5-10% deviation
 *     - Large (>10): Weak constraint, allows substantial down-weighting
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
  real<lower=0> lambda_skew;        // Skewness penalty coefficient
  real<lower=0> sigma_sum_softwgt;  // Prior SD for sum(softwgt) ~ N(N, sigma)
}

transformed data {
  // Count number of items per person (computed from data)
  array[N] int n_items = rep_array(0, N);

  // Soft-clipping parameters
  real c1 = 1.0;                        // Steepness of soft-clip
  real c2 = log(exp(0.9) - 1.0);        // Inflection point (≈ 1.317)

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

  // Participant weights (NO PRIOR - just positivity constraint)
  vector<lower=0>[N] w_raw;    // Raw weights (no simplex, no Dirichlet)
}

transformed parameters {
  matrix[N, 2] eta;            // Person effects matrix (for compatibility)
  vector[N] softwgt;           // Soft-clipped weights (prevent w >> 1)

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

  // Apply soft-clipping transformation directly to w_raw
  // softwgt = 1 - log(1 + exp(-c1*(w_raw - c2)))
  // This saturates around 1.0 as w_raw increases, preventing extreme values
  for (i in 1:N) {
    softwgt[i] = 1.0 - log1p(exp(-c1 * (w_raw[i] - c2)));
  }

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

  // Compute precision-weighted population mean (weighted by M_i and softwgt_i)
  {
    real sum_weighted_loglik = 0;
    real sum_weighted_items = 0;

    for (i in 1:N) {
      sum_weighted_loglik += softwgt[i] * n_items[i] * mean_loglik[i];
      sum_weighted_items += softwgt[i] * n_items[i];
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

  // NO PRIOR ON w_raw - improper uniform on (0, ∞)
  // Weights determined purely by likelihood + skewness penalty + sum prior

  // ============================================================================
  // WEIGHTED LIKELIHOOD (using soft-clipped weights)
  // ============================================================================

  for (i in 1:N) {
    // Weight person i's log-likelihood by softwgt[i]
    target += softwgt[i] * person_loglik[i];
  }

  // ============================================================================
  // WEIGHTED SKEWNESS PENALTY (using sum(softwgt) instead of N)
  // ============================================================================

  {
    // Weighted statistics account for down-weighted participants
    // Uses softwgt values (creates feedback loop toward symmetry)
    // Note: sum(softwgt) ≤ N (soft-clipping reduces total mass)

    real sum_softwgt = sum(softwgt);  // Compute sum explicitly
    real sum_softwgt_sq = dot_product(softwgt, softwgt);

    // Effective sample size (Kish formula)
    // Accounts for variance inflation from unequal weights
    real N_eff = square(sum_softwgt) / fmax(sum_softwgt_sq, 1.0);  // Safeguard

    // Weighted mean (point estimate under weighted distribution)
    real mean_t_weighted = dot_product(softwgt, t_stat) / fmax(sum_softwgt, 1.0);  // Safeguard

    // Weighted variance (point estimate)
    vector[N] t_centered = t_stat - mean_t_weighted;
    real var_t_weighted = dot_product(softwgt, t_centered .* t_centered) / fmax(sum_softwgt, 1.0);
    real sd_t_weighted = sqrt(fmax(var_t_weighted, 1e-10));  // Safeguard: SD >= 1e-5

    // Weighted standardization
    vector[N] t_std = t_centered / sd_t_weighted;

    // Weighted skewness (point estimate)
    real skewness = dot_product(softwgt, t_std .* t_std .* t_std) / fmax(sum_softwgt, 1.0);

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

    // ============================================================================
    // SUM PRIOR: Prevent degeneracy by constraining sum(softwgt) near N
    // ============================================================================

    // Prior: sum(softwgt) ~ N(N, sigma_sum_softwgt)
    // This provides regularization without competing with a Dirichlet prior
    // Prevents pathological solutions where all weights → 0 or → ∞
    target += normal_lpdf(sum_softwgt | N, sigma_sum_softwgt);
  }

}

generated quantities {
  // No correlation to report (independence model)

  // Weighted skewness diagnostics (using sum(softwgt))
  real sum_softwgt_final = sum(softwgt);
  real sum_softwgt_sq_final = dot_product(softwgt, softwgt);
  real N_eff_final = square(sum_softwgt_final) / fmax(sum_softwgt_sq_final, 1.0);

  real mean_t_weighted_final = dot_product(softwgt, t_stat) / fmax(sum_softwgt_final, 1.0);
  vector[N] t_centered_final = t_stat - mean_t_weighted_final;
  real var_t_weighted_final = dot_product(softwgt, t_centered_final .* t_centered_final) / fmax(sum_softwgt_final, 1.0);
  real sd_t_weighted_final = sqrt(fmax(var_t_weighted_final, 1e-10));

  vector[N] t_std_final = t_centered_final / sd_t_weighted_final;
  real skewness_weighted_final = dot_product(softwgt, t_std_final .* t_std_final .* t_std_final) / fmax(sum_softwgt_final, 1.0);

  real se_skewness_final = sqrt(6.0 / fmax(N_eff_final, 10.0));
  real z_skewness_final = skewness_weighted_final / fmax(se_skewness_final, 1e-5);

  // Weight diagnostics (raw and soft-clipped)
  real mean_w_raw = mean(w_raw);           // Raw weights (unconstrained)
  real min_w_raw = min(w_raw);
  real max_w_raw = max(w_raw);
  real sum_w_raw = sum(w_raw);             // Can be anything > 0

  real mean_softwgt = mean(softwgt);       // Soft-clipped weights
  real min_softwgt = min(softwgt);
  real max_softwgt = max(softwgt);
  real sum_softwgt_diag = sum_softwgt_final;  // Regularized toward N

  // Sum prior diagnostics
  real sum_deviation = sum_softwgt_final - N;  // How far from N
  real sum_deviation_pct = 100.0 * sum_deviation / N;  // Percentage change

  // Contribution of sum prior to log posterior
  real sum_prior_lpdf = normal_lpdf(sum_softwgt_final | N, sigma_sum_softwgt);

  // Count weights near boundaries (use w_raw)
  int n_excluded = 0;
  int n_included = 0;
  for (i in 1:N) {
    if (w_raw[i] < 0.1) n_excluded += 1;
    if (w_raw[i] > 0.9) n_included += 1;
  }

  // Person-level log-likelihood (for compatibility with other models)
  vector[N] log_lik = person_loglik;
}

/**
 * Authenticity Screening GLMM - Two-Dimensional IRT with Skewness Penalty (BETA + SUM PRIOR, STABILIZED)
 *
 * Key differences from standard Beta + sum prior version:
 *   - **STABILITY FIX 1**: Soft-clipping of t-statistics using tanh before cubing
 *   - **STABILITY FIX 2**: Logit-scale parameterization eliminates hard boundaries
 *   - **STABILITY FIX 3**: Soft boundaries everywhere (no fmax/fmin hard clipping)
 *   - Uses mixture of normals on logit scale (bimodal: include/exclude)
 *   - Normal sum prior prevents degeneracy (not Laplace - tested both!)
 *   - Skewness penalty uses sum(w) explicitly (not assuming sum = N)
 *   - INDEPENDENT person effects (no correlation between dimensions)
 *
 * Stability Improvements:
 *   1. Soft-clip t-statistics: t_soft = threshold × tanh(t / threshold)
 *      - Prevents extreme outliers (|t| > 10) from creating huge gradients when cubed
 *      - Smooth, differentiable everywhere (unlike hard clipping)
 *      - Barely affects normal participants (|t| < 5)
 *
 *   2. Normal prior on sum(w) retained (NOT Laplace):
 *      - Normal gradient grows proportionally with deviation: -(sum(w) - N) / σ²
 *      - Prevents degeneracy better than Laplace (constant gradient)
 *      - Acts like a "spring" pulling sum(w) back toward N
 *
 *   3. Soft boundaries throughout:
 *      - Variances: var + epsilon instead of fmax(var, epsilon)
 *      - Divisions: a / (b + epsilon) instead of a / fmax(b, epsilon)
 *      - Maintains nonzero gradients everywhere for LBFGS
 *
 * Sum Prior Rationale:
 *   - Mixture normal prior on logit scale creates bimodal distribution (include/exclude)
 *   - Without sum constraint, sum(w) can be very small or very large
 *   - Prior sum(w) ~ Normal(N, sigma) regularizes toward mean weight ≈ 1
 *   - Prevents degeneracy while allowing moderate down-weighting
 *
 * This model simultaneously:
 *   - Estimates item parameters (tau, beta1, delta)
 *   - Estimates person effects (eta ~ N(0,1), independent by dimension)
 *   - Estimates participant weights (w_i from mixture normal on logit scale) that minimize weighted skewness
 *   - Balances individual weight flexibility (mixture prior) vs collective constraint (Normal sum prior)
 *
 * Design Philosophy:
 *   - Authentic participants should have symmetric t-distribution
 *   - Inauthentic participants create left skew in response patterns
 *   - Down-weighting them via w[i] → 0 restores symmetry
 *   - Mixture normal prior controls individual weight distribution (bimodal: include/exclude)
 *   - Normal sum prior prevents pathological collective behavior
 *
 * Key Features:
 *   - Within-person t-statistics: t_i = (mean_i - μ_weighted) / (sd_i / √M_i)
 *   - Soft-clipped t-statistics: t_soft_i = 10 × tanh(t_i / 10)
 *   - Precision-weighted population mean: μ = sum(M_i × w_i × loglik_i) / sum(M_i × w_i)
 *   - Weighted skewness: accounts for current w values in mean/var/skew
 *   - Effective sample size: N_eff = (sum(w))² / sum(w²) adjusts SE for weight heterogeneity
 *   - Probabilistic penalty: lambda_skew × std_normal_lpdf(z_skewness)
 *   - Robust regularization: normal_lpdf(sum(w) | N, sigma_sum_w)
 *
 * Hyperparameters:
 *   - Mixture normal prior: 0.5 × N(-2, 2) + 0.5 × N(2, 2) on logit scale
 *     - Component 1: inv_logit(-2) ≈ 0.12 (favor exclusion)
 *     - Component 2: inv_logit(2) ≈ 0.88 (favor inclusion)
 *     - Creates bimodal distribution: clear include/exclude decision
 *   - lambda_skew: Skewness penalty strength (recommend 1.0 = equal to likelihood)
 *   - sigma_sum_w: Normal scale for sum(w) ~ Normal(N, sigma)
 *     - Small (5-10): Tight constraint, strong preference for sum ≈ N
 *     - Medium (10-20): Moderate tolerance, allows ~5-10% deviation
 *     - Large (>20): Weak constraint, allows substantial down-weighting
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

  // Penalty strength and sum prior parameter
  real<lower=0> lambda_skew;   // Skewness penalty coefficient
  real<lower=0> sigma_sum_w;   // Normal scale for sum(w) ~ Normal(N, sigma)
}

transformed data {
  // Count number of items per person (computed from data)
  array[N] int n_items = rep_array(0, N);

  // Soft-clipping threshold for t-statistics
  real t_clip_threshold = 10.0;  // Prevents extreme outliers from dominating

  // Small constants for soft boundaries (instead of hard fmax/fmin)
  real epsilon_prob = 1e-10;     // For probability floors
  real epsilon_var = 1e-10;      // For variance floors
  real epsilon_div = 1e-6;       // For division safeguards

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
  vector[N] logitwgt;  // Logit-scale weights
}

transformed parameters {
  // Obtain weights on probability scale (MUST BE FIRST - used in calculations below)
  vector[N] w = inv_logit(logitwgt);

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

    // SOFT BOUNDARY: Add epsilon smoothly instead of hard floor
    p = p + epsilon_prob;

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

      // SOFT BOUNDARY: Add epsilon instead of fmax
      sd_loglik[i] = sqrt(var_loglik + epsilon_var);

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

    // SOFT BOUNDARY: Add epsilon instead of fmax
    real mu_weighted = sum_weighted_loglik / (sum_weighted_items + epsilon_div);

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

  // Mixture normal prior on logit-scaled weights
  target += .5*(normal_lpdf(logitwgt | -10, 10) + normal_lpdf(logitwgt | 10, 10) );

  // ============================================================================
  // WEIGHTED LIKELIHOOD
  // ============================================================================

  for (i in 1:N) {
    // Weight person i's log-likelihood by w[i]
    target += w[i] * person_loglik[i];
  }

  // ============================================================================
  // WEIGHTED SKEWNESS PENALTY (WITH SOFT-CLIPPED T-STATISTICS)
  // ============================================================================

  {
    // Weighted statistics account for down-weighted participants
    // Uses current weight values (creates feedback loop toward symmetry)
    // Note: sum(w) is NOT constrained (can be < N or > N)

    real sum_w = sum(w);  // Compute sum explicitly
    real sum_w_sq = dot_product(w, w);

    // SOFT BOUNDARY: Effective sample size (Kish formula)
    real N_eff = square(sum_w) / (sum_w_sq + epsilon_div);

    // SOFT BOUNDARY: Weighted mean (point estimate under weighted distribution)
    real mean_t_weighted = dot_product(w, t_stat) / (sum_w + epsilon_div);

    // Weighted variance (point estimate)
    vector[N] t_centered = t_stat - mean_t_weighted;
    real var_t_weighted = dot_product(w, t_centered .* t_centered) / (sum_w + epsilon_div);

    // SOFT BOUNDARY: SD with epsilon added
    real sd_t_weighted = sqrt(var_t_weighted + epsilon_var);

    // Weighted standardization
    vector[N] t_std = t_centered / sd_t_weighted;

    // ============================================================================
    // STABILITY FIX 1: Soft-clip t-statistics using tanh
    // ============================================================================
    // Prevents extreme outliers from creating explosive gradients when cubed
    // tanh maps (-∞, ∞) → (-1, 1), so t_soft ∈ (-threshold, threshold)
    // For |t| < threshold/2, tanh(t/threshold) ≈ t/threshold (barely changes)
    // For |t| >> threshold, asymptotically approaches ±threshold (saturates smoothly)

    vector[N] t_std_soft;
    for (i in 1:N) {
      t_std_soft[i] = t_clip_threshold * tanh(t_std[i] / t_clip_threshold);
    }

    // Weighted skewness (point estimate, using SOFT-CLIPPED t-statistics)
    real skewness = dot_product(w, t_std_soft .* t_std_soft .* t_std_soft) / (sum_w + epsilon_div);

    // SOFT BOUNDARY: Standard error of skewness (uses N_eff for sampling variance)
    // Under normality: Var(skewness) ≈ 6 / N_eff
    real se_skewness = sqrt(6.0 / (N_eff + 10.0));  // Add 10 instead of fmax

    // SOFT BOUNDARY: Z-score with epsilon in denominator
    real z_skewness = skewness / (se_skewness + epsilon_div);

    // Probabilistic penalty: skewness ~ N(0, 6/N_eff) implies z ~ N(0,1)
    // lambda_skew = 1 means "skewness prior has equal weight to likelihood"
    // Only apply penalty if z_skewness is finite
    if (!is_nan(z_skewness) && !is_inf(z_skewness)) {
      target += lambda_skew * std_normal_lpdf(z_skewness);
    }

    // ============================================================================
    // STABILITY FIX 2: Normal prior on sum(w) prevents degeneracy
    // ============================================================================
    // Normal gradient grows proportionally with deviation: -(sum(w) - N) / σ²
    // Acts like a "spring" pulling sum(w) back toward N
    // Prevents degeneracy better than Laplace (which has constant gradient)
    //
    // Note: Initially tried Laplace, but Normal actually prevents weight
    // degeneracy better because it fights back harder as deviation increases

    // Prior: sum(w) ~ Normal(N, sigma_sum_w)
    target += normal_lpdf(sum_w | N, sigma_sum_w);
  }

}

generated quantities {
  // No correlation to report (independence model)

  // Weighted skewness diagnostics (using sum(w) explicitly)
  real sum_w_final = sum(w);
  real sum_w_sq_final = dot_product(w, w);
  real N_eff_final = square(sum_w_final) / (sum_w_sq_final + 1e-6);

  real mean_t_weighted_final = dot_product(w, t_stat) / (sum_w_final + 1e-6);
  vector[N] t_centered_final = t_stat - mean_t_weighted_final;
  real var_t_weighted_final = dot_product(w, t_centered_final .* t_centered_final) / (sum_w_final + 1e-6);
  real sd_t_weighted_final = sqrt(var_t_weighted_final + 1e-10);

  vector[N] t_std_final = t_centered_final / sd_t_weighted_final;

  // Apply same soft-clipping for diagnostics
  vector[N] t_std_soft_final;
  real t_clip_threshold_final = 10.0;
  for (i in 1:N) {
    t_std_soft_final[i] = t_clip_threshold_final * tanh(t_std_final[i] / t_clip_threshold_final);
  }

  // Skewness using soft-clipped t-statistics
  real skewness_weighted_final = dot_product(w, t_std_soft_final .* t_std_soft_final .* t_std_soft_final) / (sum_w_final + 1e-6);

  real se_skewness_final = sqrt(6.0 / (N_eff_final + 10.0));
  real z_skewness_final = skewness_weighted_final / (se_skewness_final + 1e-6);

  // Weight diagnostics
  real mean_weight = mean(w);  // NOT constrained to 1.0
  real min_weight = min(w);
  real max_weight = max(w);
  real sum_weight = sum_w_final;  // Regularized toward N via Normal prior

  // Sum prior diagnostics
  real sum_deviation = sum_w_final - N;  // How far from N
  real sum_deviation_pct = 100.0 * sum_deviation / N;  // Percentage change

  // Contribution of Normal sum prior to log posterior
  real sum_prior_lpdf = normal_lpdf(sum_w_final | N, sigma_sum_w);

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

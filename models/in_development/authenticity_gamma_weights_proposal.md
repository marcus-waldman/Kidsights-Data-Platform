# Authenticity Screening: Gamma-Based Outlier Weights Approach

**Status:** Proposal
**Date:** November 2025
**Motivation:** Replace skewness penalty (which failed to reduce weighted skewness) with principled density-ratio weighting

---

## Problem with Current Approach

The skewness penalty in `authenticity_glmm_beta_sumprior_stable.stan` does not achieve the desired goal:

- **Observed**: At σ_sum_w = 4.0, weighted skewness = 0.877 (z = 15.18)
- **Expected**: Weighted skewness → 0 as penalty strength increases
- **Issue**: Likelihood benefit from excluding poor-fitting observations overwhelms skewness penalty gradient

**Fundamental conflict**: Down-weighting left-tail outliers (good for authenticity screening) creates positive weighted skewness (bad for penalty). The two objectives fight each other.

---

## Proposed Solution: Two-Stage Gamma-Weighted Approach

### Theoretical Foundation

Under bivariate normality of person effects (η_psychosocial, η_developmental):
- Squared Mahalanobis distance: **D² ~ χ²(2)**
- Chi-square is special case of Gamma: **χ²(2) = Gamma(α=1, β=0.5)**

**Key insight**: Use Gamma distribution to approximate empirical distribution of D², enabling density ratio weights that:
1. Are principled (measure departure from expected distribution)
2. Self-calibrate (if no outliers → α̂≈1, β̂≈0.5 → weights≈1)
3. Require no hyperparameter tuning

---

## Stage 1: Fit Weighted Model with Dynamic Weights

### Stan Model Structure

#### `transformed parameters` block:
```stan
// 1. Compute squared Mahalanobis distances
vector[N] eta_combined[2];
eta_combined[1] = eta_psychosocial;
eta_combined[2] = eta_developmental;

vector[N] d_sq;
for (i in 1:N) {
  vector[2] eta_i = [eta_psychosocial[i], eta_developmental[i]]';
  d_sq[i] = dot_product(eta_i, mdivide_left_spd(Sigma_eta, eta_i));
}

// 2. Method of moments for Gamma distribution
real mean_d_sq = mean(d_sq);
real var_d_sq = variance(d_sq);
real alpha_hat = square(mean_d_sq) / (var_d_sq + 1e-6);
real beta_hat = mean_d_sq / (var_d_sq + 1e-6);

// 3. Compute weights as density ratios
vector[N] wgt;
for (i in 1:N) {
  // Target: chi-square(2) = Gamma(1, 0.5)
  // Empirical: Gamma(alpha_hat, beta_hat)
  real log_target = gamma_lpdf(d_sq[i] | 1.0, 0.5);
  real log_empirical = gamma_lpdf(d_sq[i] | alpha_hat, beta_hat);
  wgt[i] = exp(log_target - log_empirical);
}
```

#### `model` block:
```stan
// Weighted likelihood
for (i in 1:N) {
  target += wgt[i] * [log-likelihood for person i];
}
```

### Convergence Properties

- **Iterative refinement**: Initial eta → compute weights → weighted likelihood updates eta → recompute weights → ...
- **Stable equilibrium**: Converges when eta estimates and weights are mutually consistent
- **Output**: Final weights {wgt_1, ..., wgt_N} where low weight = likely outlier

---

## Stage 2: Cross-Validation for Exclusion Threshold

### Inputs
- Fixed weights {wgt_1, ..., wgt_N} from Stage 1 (never recomputed)

### Workflow

1. **Sort observations** by weight (ascending: lowest weights first)

2. **Test exclusion thresholds**: k ∈ {0, 10, 20, 30, ..., K_max}
   - k = number of lowest-weighted observations to exclude

3. **For each k, run cross-validation**:
   - Exclude bottom k observations → N-k remaining
   - Split remaining into train/holdout folds
   - Refit **unweighted base model** (`authenticity_glmm.stan`) on train folds
   - Compute out-of-sample log-likelihood loss on holdout folds

4. **Select k\***: Threshold that minimizes CV loss

5. **Final model**: Refit unweighted base model on all N-k\* observations

### Rationale for Unweighted Refitting

Once outliers are removed via hard exclusion, the remaining sample should be approximately bivariate normal → no weighting needed for clean data.

---

## Implementation Details

### 1. Mahalanobis Distance Calculation

**Option A: Use raw bivariate (η_psychosocial, η_developmental)**
- Simpler implementation
- Assumes eta ~ BivariateNormal(0, Σ)

**Option B: Use MCD robust center/covariance**
- More robust to outliers in distance calculation itself
- Requires computing MCD in R before Stan (can't do in Stan transformed parameters)
- Chicken-egg problem: need robust center to identify outliers, but outliers contaminate center

**Recommendation**: Start with Option A (raw bivariate). If MCD needed, compute in R preprocessing step.

### 2. Weight Stability

**Potential issue**: Extreme outliers could have weights → 0 or ∞

**Solution**: Soft clipping
```stan
real epsilon = 1e-3;
wgt[i] = fmax(epsilon, fmin(1.0/epsilon, raw_wgt[i]));
```

This bounds weights to [0.001, 1000] range.

### 3. Stan Gradient Complexity

Computing α̂, β̂ via method of moments creates second-order autodiff:
- Variance calculation involves squared deviations
- Ratios of moments (mean² / variance)

**Testing needed**: Verify LBFGS converges reliably with this gradient structure.

### 4. Initialization Strategy

**Option A**: Start from scratch (random initialization)
**Option B**: Initialize with eta estimates from unweighted base model

**Recommendation**: Option B for faster convergence and stability.

---

## Advantages Over Skewness Penalty

1. **No hyperparameters**: Weights emerge from data, no tuning required
2. **Self-calibrating**: Automatically gives weights≈1 if no outliers present
3. **Decoupled objectives**: Outlier identification (Stage 1) separate from threshold selection (Stage 2)
4. **Interpretable**: "This person's bivariate eta is unlikely under normality"
5. **Principled**: Based on statistical theory (density ratios, Gamma nesting of chi-square)

---

## Open Questions

1. **Convergence**: Will Stan optimization converge with weights in transformed parameters?
2. **Gradient stability**: Can LBFGS handle MOM estimators in autodiff?
3. **Weight degeneracy**: Do we need soft clipping, or are weights naturally bounded?
4. **Computational cost**: How does Stage 1 compare to current penalized model fitting time?
5. **K_max**: What's reasonable upper bound for exclusion? 10%? 20% of sample?

---

## Next Steps

1. Implement Stan model with dynamic Gamma weights
2. Test convergence on simulated data with known outliers
3. Compare Stage 1 weights to current w from penalized model
4. Implement Stage 2 CV workflow
5. Evaluate on NE25 data

---

## References

- **Chi-square as Gamma**: χ²(df) = Gamma(α = df/2, β = 1/2)
- **Bivariate normality**: D² ~ χ²(p) where p = dimension (here p=2)
- **Density ratio weighting**: wgt = p_target / p_empirical (cf. propensity score weighting)

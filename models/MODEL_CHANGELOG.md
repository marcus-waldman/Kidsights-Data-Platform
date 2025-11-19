# Authenticity Screening Model Changelog

## November 2025 - LKJ(1) Correlated Model

### Changes Made

**1. Model Files**
- **Backed up:** `authenticity_glmm.stan` → `authenticity_glmm_independent.stan` (deleted after validation)
- **Main model:** Two-dimensional IRT with LKJ(1) prior on correlation (non-informative)

### Model Specifications

**Previous Model (Independent):**
```
eta_psychosocial ~ N(0, 1) [sum-to-zero]
eta_developmental ~ N(0, 1) [sum-to-zero]
cor(eta_psychosocial, eta_developmental) = 0 (fixed)
```

**Current Model (LKJ(1) Correlated):**
```
eta ~ MVN(0, Omega) where Omega = correlation matrix
Marginal: eta[i, 1] ~ N(0, 1), eta[i, 2] ~ N(0, 1)
Prior: L_Omega ~ lkj_corr_cholesky(1)  [uniform over all correlations]
Estimated: eta_correlation (data-driven, no prior bias)
```

**Key Differences:**
- **Marginal variances:** Fixed at 1 (standard normal)
- **Correlation:** Estimated from data with LKJ(1) prior (uniform, non-informative)
- **Parameterization:** Non-centered (eta_std → eta transformation)
- **Covariance:** Sigma = [[1, rho], [rho, 1]]

### Updated R Interface

**`extract_parameters()` now returns:**
- `eta_correlation`: Estimated correlation between dimensions
- `eta`: N x 2 matrix (replaces separate vectors)
- `eta_psychosocial`: eta[, 1] (for backward compatibility)
- `eta_developmental`: eta[, 2] (for backward compatibility)

**`create_init_values()` now creates:**
- `eta_std`: N x 2 matrix of standardized effects
- `L_Omega`: 2x2 identity matrix (no correlation initially)
- Removed: `alpha_psychosocial`, `alpha_developmental`

**`create_warm_start()` now handles:**
- Reconstruction of L_Omega from correlation
- Inversion of transformation (eta → eta_std)
- Matrix-based warm starts for LOOCV

### Updated Scripts

**`02_fit_full_model.R` now displays:**
- Estimated correlation with strength interpretation (weak/moderate/strong)
- Marginal SDs (should be ~1.0)
- Empirical vs estimated correlation comparison
- Model notes explaining LKJ(1) prior (uniform over all correlations)

**Removed output:**
- Discrimination parameters (alpha_psychosocial, alpha_developmental)
- Ratio of discrimination parameters

**Added output:**
- LKJ prior interpretation
- Marginal variance verification
- Correlation strength classification

### Updated Holdout Model (LOOCV)

**`models/authenticity_holdout.stan` updated to match LKJ correlation structure:**

**Key Changes:**
- Added `eta_correlation` to data block (passed from N-1 model fit)
- Added `dimension` array to data block (item dimension assignments)
- Changed from independent priors to correlated bivariate normal:
  ```stan
  parameters {
    vector[2] eta_std_holdout;  // Standardized abilities
  }
  transformed parameters {
    vector[2] eta_holdout = L_Omega * eta_std_holdout;  // Correlated
  }
  transformed data {
    // Construct L_Omega from eta_correlation
    matrix[2, 2] L_Omega;
  }
  model {
    eta_std_holdout ~ std_normal();  // Induces MVN(0, Omega) on eta_holdout
  }
  ```
- Updated log-prior calculation to use eta_std (dot product)

**R Scripts Updated:**
- `03_run_loocv.R`: Extract eta_correlation from N-1 fit, pass to holdout model
- `04_compute_inauthentic_logpost.R`: Extract eta_correlation from full model, pass to holdout model
- `08_compute_pipeline_weights.R`: Extract eta_correlation from params_full, pass to holdout function

**Consistency:** Holdout model now uses same correlation structure as main model, ensuring proper prior specification for held-out participants

### Rationale

**Why LKJ(1) over independent?**
1. Tests whether psychosocial problems and developmental delays co-occur
2. LKJ(1) prior is non-informative (uniform over all correlations)
3. Data fully informs correlation without prior bias
4. If correlation ≈ 0, model reduces to independent case

**Why fixed marginal variance?**
1. Direct comparison with independent model
2. Better identification (no variance-correlation trade-off)
3. Cleaner interpretation (only correlation varies)
4. Standard normal marginals match independent model

### Model Selection Criteria

**Use correlated model (current) if:**
- |eta_correlation| > 0.3 (moderate or strong)
- Substantially better log-likelihood than independent
- Theoretical justification for co-occurrence

**Use independent model (backup) if:**
- |eta_correlation| < 0.3 (weak correlation)
- Simpler model preferred by parsimony
- No theoretical reason for correlation

### Files Modified

**Stan Models:**
- `models/authenticity_glmm.stan` (replaced with LKJ version)
- `models/authenticity_glmm_independent.stan` (backup of old version)
- `models/authenticity_glmm_test.stan` (original test version, kept for reference)

**R Interface:**
- `R/authenticity/stan_interface.R`:
  - `extract_parameters()` - matrix eta extraction
  - `create_init_values()` - LKJ initialization
  - `create_warm_start()` - correlation-aware warm starts

**Scripts:**
- `scripts/authenticity_screening/02_fit_full_model.R` - correlation analysis instead of discrimination

**Test Scripts:**
- `scripts/temp/test_lkj_model.R` - comprehensive LKJ model testing

### Next Steps

1. Fit full model on 2,635 authentic participants
2. Examine estimated correlation
3. Compare to independent model if needed
4. Proceed to LOOCV (03_run_loocv.R will need updates for LKJ)

---

## November 2025 - Jackknife Influence Diagnostics (Cook's D)

### Changes Made

**1. LOOCV Parameter Tracking**
- **Modified:** `scripts/authenticity_screening/03_run_loocv.R`
- **Added:** `param_diff` field to LOOCV output containing parameter differences (theta_(-i) - theta_full)
- **Storage:** ~11 MB for 540 item parameters × 2,635 participants

**2. Post-Processing Script**
- **Created:** `scripts/authenticity_screening/compute_cooks_d.R`
- Constructs N×540 parameter difference matrix from LOOCV results
- Computes jackknife covariance matrix and inverts to approximate Hessian
- Calculates Cook's D influence statistic for each participant
- Identifies influential participants using 4/N and D>1 thresholds

### Mathematical Approach

**Problem:** Computing true Cook's D requires the Hessian (observed information matrix), but with 5,810 parameters (540 item + 5,270 person), finite differences would be prohibitively expensive.

**Solution:** Jackknife-based Hessian approximation using LOOCV parameter differences.

**Method:**
1. Each LOOCV iteration provides: `diff_i = theta_(-i) - theta_full` (540-dim vector for item params only)
2. Stack into N×540 difference matrix
3. Compute jackknife covariance: `Sigma_jack = cov(diff_matrix) × (N-1)`
4. Approximate Hessian: `H ≈ inv(Sigma_jack)`
5. Cook's D for person i: `D_i = diff_i' × H × diff_i / p` where p=540

**Key Insight:** We only track item parameter changes (tau, beta1, delta, eta_correlation), not person parameters (eta_std). This reduces dimensionality from 5,810 to 540 while capturing the influence on estimating the IRT model itself.

### Interpretation

**Cook's D (D_i) measures:** How much item parameter estimates change when participant i is excluded.

**Sample-Size Invariant Version:** We use `D_scaled = D × N` to make influence metrics comparable across studies.

**Thresholds (for D×N):**
- `D×N < 4`: Not influential (typical participant)
- `4 < D×N < N`: Moderately influential (worth investigating)
- `D×N > N`: Highly influential (unusual response patterns)

**Why scale by N?** Traditional threshold `D > 4/N` varies with sample size, making cross-study comparison difficult. Scaling by N gives constant thresholds (4 and N) regardless of sample size.

**Combined with log-posterior for authenticity screening:**
- **High D + Low log_posterior:** Likely inauthentic (poor model fit + parameter instability)
- **High D + High log_posterior:** Unusual but authentic (strong unique developmental signal)
- **Low D + Low log_posterior:** Poorly fit but not influential (random noise)
- **Low D + High log_posterior:** Typical authentic participant

### Output Files

**From LOOCV (03_run_loocv.R):**
- `results/loocv_results.rds` - Now includes `param_diff` list column with:
  - `beta1_diff` (J-length vector)
  - `tau_diff` (J-length vector)
  - `delta_diff` (scalar)
  - `eta_corr_diff` (scalar)

**From Cook's D computation (compute_cooks_d.R):**
- `results/loocv_cooks_d.rds` - LOOCV results + Cook's D columns:
  - `cooks_d` (numeric, raw Cook's D)
  - `cooks_d_scaled` (numeric, D × N, sample-size invariant)
  - `influential_4` (logical, D×N > 4 threshold)
  - `influential_N` (logical, D×N > N threshold)
- `results/loocv_hessian_approx.rds` - 540×540 jackknife Hessian matrix

### Usage Example

```r
# After running LOOCV
source("scripts/authenticity_screening/compute_cooks_d.R")

# Load results
results <- readRDS("results/loocv_cooks_d.rds")

# Identify highly influential participants (using scaled version)
influential <- results %>%
  filter(influential_4) %>%
  arrange(desc(cooks_d_scaled))

# Find potential inauthentic responses (high influence + low log-posterior)
suspects <- results %>%
  filter(cooks_d_scaled > 4 & avg_logpost < median(avg_logpost, na.rm=TRUE))
```

### Advantages of Jackknife Approach

1. **No additional computation:** Uses LOOCV differences already computed
2. **Avoids finite differences:** No need for 5,810×5,810 Hessian via numerical derivatives
3. **Empirically grounded:** Captures actual parameter sensitivity to individual observations
4. **Bonus outputs:** Provides jackknife standard errors for all item parameters

### Limitations

1. **Requires complete LOOCV:** All N participants must have valid param_diff (N-1 model converged)
2. **Assumes regularity:** Jackknife covariance is accurate when N is large relative to p (p=540, N=2,635, ratio=4.9)
3. **Matrix inversion:** Can be unstable if Sigma_jack is ill-conditioned (regularization applied if condition number > 1e10)

### Files Modified

**Scripts:**
- `scripts/authenticity_screening/03_run_loocv.R` - Added param_diff tracking
- `scripts/authenticity_screening/compute_cooks_d.R` (NEW) - Cook's D computation

**Test Scripts:**
- `scripts/temp/test_cooks_d_implementation.R` - Validation on n=20 subset

---

*Date: November 2025*
*Author: Two-dimensional IRT development*

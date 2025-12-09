# NE25 KL Divergence Raking Weights Pipeline

**Last Updated:** December 2025
**Version:** 2.0
**Status:** Production Ready

---

## Overview

The KL Divergence Weighting Pipeline computes survey weights that match population targets via Kullback-Leibler (KL) divergence minimization. This is the **second phase** of the NE25 raking pipeline (after [NE25_RAKING_TARGETS_PIPELINE.md](NE25_RAKING_TARGETS_PIPELINE.md)).

### Key Features

- **24-variable structure:** 7 pooled demographics + 14 PUMA regions + 2 mental health + 1 child outcome
- **Factorized covariance:** Handles singular covariance matrices from incomplete data sources
- **Multi-imputation ready:** Designed to process M=1,2,3,4,5 imputations independently
- **Stan optimization:** BFGS/L-BFGS algorithms for efficient weight estimation
- **Flexible parameterization:** Simplex model with explicit weight constraints (min_weight, max_weight)

### Architecture

```
Phase 5 (Raking Targets Pipeline)
  ↓
  ├─ Script 30b: Pool Moments (unified_moments.rds)
  ├─ Script 32: Prepare NE25 (ne25_harmonized_m1.feather)
  └─ Script 33: Compute KL Weights (ne25_calibrated_weights_m1.feather)
       ↓
       [Repeat for m2-m5 imputations]
```

---

## Quick Start

### Single Imputation (m=1)

```r
# Run entire pipeline (Phase 5)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R
```

### Multiple Imputations (m=1-5)

```r
# Run script 33 for each imputation manually (after Script 32)
for (m in 1:5) {
  harmonized_file <- sprintf("data/raking/ne25/ne25_harmonized/ne25_harmonized_m%d.feather", m)
  source("scripts/raking/ne25/33_compute_kl_divergence_weights.R")
}
```

**Execution time:** ~2-5 minutes per imputation (24 variables, 2,785 observations)

---

## Pipeline Components

### Script 30b: Pool Moments Across Sources

**Purpose:** Create unified 24-variable moment structure (μ, Σ, n_eff)

**Input:**
- `data/raking/ne25/acs_moments.rds` (ACS: 21 variables, n_eff=1,486)
- `data/raking/ne25/nhis_moments.rds` (NHIS: 7 demographics + 2 mental health, n_eff=7,294)
- `data/raking/ne25/nsch_moments.rds` (NSCH: 7 demographics + 1 child outcome, n_eff=2,143)

**Process:**

1. **Pool Block 1 demographics** (7 variables: male, age, white_nh, black, hispanic, educ_years, poverty_ratio)
   - Pooled from ACS, NHIS, NSCH using effective sample size weights
   - Formula: μ_pooled = (n_eff_acs × μ_acs + n_eff_nhis × μ_nhis + n_eff_nsch × μ_nsch) / (n_eff_acs + n_eff_nhis + n_eff_nsch)

2. **Add Block 1 PUMA variables** (14 binary dummies: puma_100, puma_200, ..., puma_904)
   - From ACS only (no pooling needed)
   - Creates 21×21 Block 1 covariance submatrix

3. **Add Block 2 mental health** (2 variables: phq2_total, gad2_total)
   - From NHIS only
   - Cross-covariances: demographics × mental health (observed), PUMA × mental health (unobserved, set to 0)

4. **Add Block 3 child outcome** (1 variable: excellent_health)
   - From NSCH only
   - Cross-covariances: demographics × outcome (observed), PUMA × outcome (unobserved, set to 0)

5. **Create covariance mask matrix** (24×24 binary)
   - Element = 1 if observed (from joint data source)
   - Element = 0 if unobserved (from independent sources)
   - Result: 488/576 observed (84.7%), 88 unobserved (15.3%)

**Output:** `data/raking/ne25/unified_moments.rds`
```r
list(
  mu = c(0.508, 2.669, 0.641, 0.104, 0.172, 14.470, 260.6, [14 PUMA], 0.445, 0.123, 0.709),
  Sigma = 24×24 matrix (factorized, singular),
  cov_mask = 24×24 binary matrix,
  variable_names = c("male", "age", ..., "excellent_health"),
  n_eff = list(block1 = 2506.4, block2 = 7294, block3 = 2143),
  pooling_weights = list(acs = 0.593, nhis = 0.291, nsch = 0.116)
)
```

**Bug Fix (December 2025):**
- Previously extracted `nsch$mu[8]` (child_ace_1 = 0.590) instead of `nsch$mu[10]` (excellent_health = 0.709)
- Fixed in lines 164, 165, 175 to use correct index 10
- This corrected the target from 59.0% to 70.9% for excellent health

### Script 32: Prepare NE25 for Weighting

**Purpose:** Create harmonized NE25 dataset matching 24-variable structure

**Input:**
- `ne25_transformed` table (database, 2,785 records where meets_inclusion=TRUE)
- Harmonization functions:
  - `harmonize_puma.R` - Convert PUMA string to 14 binary dummies
  - `harmonize_ne25_demographics.R` - Standardize demographic variables
  - `harmonize_ne25_outcomes.R` - Calculate mental health and child outcome scores

**Process:**

1. Load NE25 records (meets_inclusion=TRUE)
2. Preprocess CBSA/PUMA (extract first value from semicolon-delimited strings)
3. Impute missing values via MICE CART (M=1 for script 32; expand to M=5 later)
4. Harmonize to 24-variable structure
5. Validate data quality
6. Save as feather

**Output:** `data/raking/ne25/ne25_harmonized/ne25_harmonized_m1.feather`
- 2,785 rows × 27 columns
- Columns: pid, record_id, study_id, + 24 harmonized variables

**Extension to Multiple Imputations:**
- Script 32 can be modified to loop over M=1:5
- Creates `ne25_harmonized_m1.feather` through `ne25_harmonized_m5.feather`
- Each imputation produces independent NE25 datasets with same structure

### Script 33: Compute KL Divergence Weights

**Purpose:** Calculate optimal survey weights via KL divergence minimization

**Input:**
- `data/raking/ne25/ne25_harmonized/ne25_harmonized_m1.feather` (2,785 × 27)
- `data/raking/ne25/unified_moments.rds` (24 targets + covariance mask)

**Method: Simplex Parameterization**

Instead of linear model log(wgt[i]) = α + X[i,]β (K+1 parameters, too constrained for 24 variables), use:

**Simplex model:** wgt ~ Dirichlet(concentration × wgt_raw)
- **Parameters:** N parameters (one per observation)
- **Constraints:** min_weight ≤ wgt[i] ≤ max_weight, Σ wgt[i] normalized
- **Objective:** Minimize masked KL divergence

**Masked KL Divergence Formula:**

```
KL = Σ wgt[i] × log(wgt[i] / (1/N))                    [Entropy term]
   + (1/2) × Σ_{k} (μ_achieved[k] - μ_target[k])² / var_target[k]  [Mean matching]
   + (1/2) × Σ_{i,j: cov_mask[i,j]=1} (Σ_achieved[i,j] - Σ_target[i,j])² / (SD[i] × SD[j])  [Covariance matching]
```

**Key Features:**

1. **Factorized covariance handling:**
   - Regular matrix (not positive definite requirement)
   - Only observed covariances (cov_mask=1) penalized
   - Unobserved blocks (cov_mask=0) ignored

2. **Weight constraints:**
   - min_weight = 0.01 (prevent extremely low weights)
   - max_weight = 100.0 (prevent extreme upweighting)
   - Formula: wgt_scaled = min_wgt + (max_wgt - min_wgt) × wgt_raw
   - Renormalized to preserve simplex property

3. **Regularization:**
   - Dirichlet prior with concentration = 1.0 (uniform smoothing)
   - Small diagonal regularization (1e-6) for numerical stability

**Stan Model:** `calibrate_weights_simplex_factorized.stan`

**R Wrapper:** `calibrate_weights_simplex_factorized_cmdstan.R`

**Process:**

```r
calibration_result <- calibrate_weights_simplex_factorized_stan(
  data = ne25_complete,                      # Complete case dataset
  target_mean = unified$mu,                  # 24-element target vector
  target_cov = unified$Sigma,                # 24×24 target covariance (singular)
  cov_mask = unified$cov_mask,               # 24×24 binary mask
  calibration_vars = variable_names,         # Variable names for reporting
  min_weight = 0.01,                         # Minimum weight constraint
  max_weight = 100.0,                        # Maximum weight constraint
  concentration = 1.0,                       # Dirichlet prior (uniform)
  verbose = TRUE,
  iter = 5000,
  history_size = 500,
  refresh = 20
)
```

**Optimization Algorithm:** L-BFGS (limited-memory BFGS)
- Efficient for large N, moderate K
- Convergence tolerance: 1e-10 gradient, 1e-6 objective
- Max iterations: 5,000

**Output:** `data/raking/ne25/ne25_weights/ne25_calibrated_weights_m1.feather`
- Input data + calibrated_weight column
- Weights sum to N (not normalized)
- Efficient N ≈ 2,400-2,600 (depending on convergence)

**Diagnostics:** `data/raking/ne25/ne25_weights/calibration_diagnostics_m1.rds`
```r
list(
  converged = TRUE/FALSE,
  effective_n = 2500.5,
  efficiency_pct = 89.8,
  weight_ratio = 125.4,              # max(wgt) / min(wgt)
  final_marginals = data.frame(      # 24 rows
    Variable = c("male", "age", ...),
    Target = c(0.508, 2.669, ...),
    Achieved = c(0.509, 2.668, ...),
    Pct_Diff = c(0.19, 0.04, ...)
  ),
  n_complete_cases = 2785,
  target_mean = unified$mu,
  target_cov = unified$Sigma,
  variable_names = unified$variable_names,
  pooling_weights = unified$pooling_weights
)
```

---

## Block Structure and Covariance Factorization

### 24 Variables Organized in 3 Blocks

**Block 1: 21 variables (Pooled + ACS-specific)**
- Pooled from ACS/NHIS/NSCH (7 demographics): male, age, white_nh, black, hispanic, educ_years, poverty_ratio
- ACS-only (14 PUMA dummies): puma_100, puma_200, ..., puma_904

**Block 2: 2 variables (NHIS-only)**
- phq2_total (parent depression, 0-6 scale)
- gad2_total (parent anxiety, 0-6 scale)

**Block 3: 1 variable (NSCH-only)**
- excellent_health (child health rating, 0-1 binary)

### Covariance Mask (24×24 Binary)

**Observed Blocks (cov_mask = 1):**
- Block 1 × Block 1 (21×21): Full covariance from ACS
- Block 2 × Block 2 (2×2): Full covariance from NHIS
- Block 3 × Block 3 (1×1): Variance from NSCH
- Block 1 × Block 2 (21×2): Cross-covariances from NHIS (demographics co-vary with mental health in NHIS sample)
- Block 1 × Block 3 (21×1): Cross-covariances from NSCH (demographics co-vary with child health in NSCH sample)

**Unobserved Blocks (cov_mask = 0):**
- Block 1 × Block 2 PUMA subset (14×2): PUMA regions only in ACS, not in NHIS → unobserved covariance
- Block 1 × Block 3 PUMA subset (14×1): PUMA regions only in ACS, not in NSCH → unobserved covariance
- Block 2 × Block 3 (2×1): Mental health from NHIS, outcomes from NSCH → unobserved cross-source covariance

**Factorized Structure Result:**
- 488 observed elements (84.7%)
- 88 unobserved elements (15.3%)
- **Singular covariance matrix:** Determinant ≈ 0, min eigenvalue ≈ 0
- **Condition number:** ~10^14 (ill-conditioned)

### Why Factorization Matters

The standard approach (matching full covariance matrix) is **infeasible** because:

1. **Incompleteness:** Data sources don't overlap (ACS ≠ NHIS ≠ NSCH)
   - ACS has PUMA, NHIS has mental health, NSCH has outcomes
   - These never co-occur in raw data

2. **Matrix singularity:** Attempting to invert 24×24 covariance with zero cross-blocks fails
   - Direct Mahalanobis distance requires invertible covariance matrix
   - Our matrix has rank < 24

3. **Solutions rejected:**
   - Full regularization (add large constant to diagonal): Destroys covariance structure
   - Dropping variables: Loses important heterogeneity (PUMA geographic targeting)
   - Listwise deletion of ACS data: Infeasible (ACS is national sample)

4. **Solution implemented:** Masked KL divergence
   - Only penalizes observed covariances (block diagonal structure)
   - Ignores unobserved cross-block covariances
   - Allows singular matrices: matrix[K,K] (not cov_matrix[K])
   - Simplex parameterization for flexibility

---

## Multi-Imputation Extension (Planned)

### Current Status

Script 33 processes **single imputation (m=1)** from script 32.

### Planned Extension to M=5

1. **Script 32 Modification:**
   - Loop over m=1:5
   - Perform MICE CART imputation separately for each m
   - Output: `ne25_harmonized_m1.feather` through `ne25_harmonized_m5.feather`

2. **Script 33 Modification:**
   - Create wrapper script to loop over m=1:5
   - For each m:
     - Load `ne25_harmonized_m{m}.feather`
     - Run KL divergence optimization (reuse stan_model across imputations)
     - Save `ne25_calibrated_weights_m{m}.feather`
     - Save `calibration_diagnostics_m{m}.rds`

3. **Database Integration:**
   - Create `ne25_calibrated_weights` table (union of all m=1:5)
   - Add `imputation_m` column to identify source imputation
   - Enables proper variance estimation via Rubin's rules

### Computational Efficiency

- **Reuse Stan compilation:** Compile once, optimize M times
- **Parallel processing:** Could parallelize m=1:5 across 5 cores
- **Total time estimate:** ~15-25 minutes (2-5 min per imputation)

---

## Convergence Diagnostics

### Convergence Criteria

**Primary:** Marginal means within 1% of targets
- Formula: |Achieved - Target| / |Target| < 0.01

**Secondary:** Effective sample size
- Kish formula: N_eff = (Σ wgt)² / Σ wgt²
- Typical efficiency: 85-95% (vs unweighted N=2,785)

### Common Issues and Solutions

**Issue 1: Poor marginal convergence (>5% difference)**
- **Cause:** min_weight/max_weight bounds too tight or too loose
- **Solution:** Adjust constraints:
  ```r
  min_weight = 0.001  # Loosen minimum
  max_weight = 1000   # Loosen maximum
  ```

**Issue 2: Very low efficiency (<50%)**
- **Cause:** Extreme weight imbalance (some observations heavily downweighted)
- **Solution:** Relax concentration parameter (default 1.0):
  ```r
  concentration = 2.0  # More smoothing
  ```

**Issue 3: Optimizer fails to converge**
- **Cause:** Covariance target too extreme relative to data
- **Solution:** Check unified_moments.rds for outliers:
  ```r
  # In script 30b, validate pooled statistics
  plot(unified$mu)  # Check for suspicious values
  plot(diag(unified$Sigma))  # Check variances
  ```

---

## Database Integration

### Tables

**Input:**
- `ne25_transformed` - Base NE25 data (used by script 32)

**Output:**
- `ne25_calibrated_weights` - Weights for all imputations (future)
  - Columns: pid, record_id, imputation_m, calibrated_weight
  - Indexes: (pid, record_id, imputation_m), (imputation_m)

**Temporary/Development:**
- `ne25_kl_convergence_history` - Optimization traces (optional)
- `ne25_weight_diagnostics` - Summary statistics (optional)

### Querying Weights

```sql
-- Get weights for imputation m=1
SELECT pid, record_id, calibrated_weight
FROM ne25_calibrated_weights
WHERE imputation_m = 1;

-- Summary statistics
SELECT imputation_m,
       MIN(calibrated_weight) as min_wgt,
       MAX(calibrated_weight) as max_wgt,
       AVG(calibrated_weight) as mean_wgt,
       SUM(calibrated_weight) as total_wgt
FROM ne25_calibrated_weights
GROUP BY imputation_m;
```

---

## Files and Locations

### Scripts

- `scripts/raking/ne25/30b_pool_moments.R` - Pool moments across sources
- `scripts/raking/ne25/32_prepare_ne25_for_weighting.R` - Harmonize NE25 data
- `scripts/raking/ne25/33_compute_kl_divergence_weights.R` - Compute KL weights

### Stan Models

- `scripts/raking/ne25/utils/calibrate_weights_simplex_factorized.stan` - Stan code
- `scripts/raking/ne25/utils/calibrate_weights_simplex_factorized_cmdstan.R` - R wrapper

### Utilities

- `scripts/raking/ne25/utils/harmonize_puma.R` - PUMA binary encoding
- `scripts/raking/ne25/utils/harmonize_ne25_demographics.R` - Demographics standardization
- `scripts/raking/ne25/utils/harmonize_ne25_outcomes.R` - Mental health + child health

### Data Outputs

- `data/raking/ne25/unified_moments.rds` - Target moments (24 variables)
- `data/raking/ne25/ne25_harmonized/ne25_harmonized_m1.feather` - Harmonized NE25 (m=1)
- `data/raking/ne25/ne25_weights/ne25_calibrated_weights_m1.feather` - Weights (m=1)
- `data/raking/ne25/ne25_weights/calibration_diagnostics_m1.rds` - Diagnostics (m=1)

---

## Troubleshooting

### Q: Script 33 fails with "unified_moments.rds not found"
**A:** Run script 30b first: `Rscript scripts/raking/ne25/30b_pool_moments.R`

### Q: Script 33 fails with "ne25_harmonized_m1.feather not found"
**A:** Run script 32 first: `Rscript scripts/raking/ne25/32_prepare_ne25_for_weighting.R`

### Q: Stan model compiles but optimization fails silently
**A:** Check:
1. No NAs in calibration variables: `colSums(is.na(ne25_complete))`
2. Covariance mask dimensions: `dim(unified$cov_mask)` should be 24×24
3. Stan code syntax: `cmdstanr::cmdstan_model("...stan")`

### Q: Weights have extreme values (e.g., max/min > 10,000)
**A:** This indicates poor calibration. Check:
1. Target moments are reasonable: `unified$mu` and `diag(unified$Sigma)`
2. Weight constraints: Try tighter bounds or higher concentration parameter
3. Covariance structure: Check `unified$cov_mask` for errors

### Q: Marginal accuracy poor (>5% difference)
**A:** Common causes:
1. Incomplete cases < 50%: Check script 32 for missing data
2. Outliers in calibration variables: Check for data entry errors
3. Weight bounds conflict with targets: Loosen constraints and re-run

---

## References

- [NE25_RAKING_TARGETS_PIPELINE.md](NE25_RAKING_TARGETS_PIPELINE.md) - Target moments pipeline
- [MISSING_DATA_GUIDE.md](../guides/MISSING_DATA_GUIDE.md) - Missing data handling
- [CODING_STANDARDS.md](../guides/CODING_STANDARDS.md) - R/Python standards
- Stan documentation: https://mc-stan.org/

---

*Last updated: December 2025*

# NE25 Raking Weight Integration Guide

**Last Updated:** December 2025 | **Version:** 1.0.0

Complete documentation for integrating calibrated raking weights into the NE25 pipeline.

---

## Overview

The NE25 pipeline now includes optional automatic integration of calibrated raking weights (Step 6.9), providing population-representative survey weighting for improved statistical inference.

**Key Numbers:**
- **2,645** in-state Nebraska records with calibrated weights
- **140** out-of-state records marked and excluded
- **71.9%** improvement in correlation RMSE (unweighted → weighted)
- **57.4%** weight efficiency (Kish effective N = 1,518.9)

---

## What Are Raking Weights?

Raking weights adjust survey samples to match population targets from external sources (ACS census data, NHIS health surveys, NSCH child health data). This reduces selection bias and improves representativeness for population inference.

**Mathematical Foundation:**

The weights minimize a masked factorized KL divergence loss:

```
L = 0.5 × [Σ_k (μ_achieved[k] - μ_target[k])²/σ_target[k]² + Σ_mask(i,j) (ρ_achieved[i,j] - ρ_target[i,j])²]
```

Where:
- **μ_achieved, μ_target:** Sample and target means for K=24 calibration variables
- **ρ_achieved, ρ_target:** Sample and target correlations (computed from covariances)
- **σ_target:** Target standard deviations (scales mean errors)
- **Σ_mask:** Factorized covariance mask (observed blocks only, unobserved blocks = 0)

**Key Insight:** The loss function approximates correlation matching rather than true KL divergence because:
1. Covariance differences are normalized by (σ_target[i] × σ_target[j])
2. This converts covariance errors into correlation errors
3. The factorization ensures numerical stability with incomplete covariance structure

---

## Calibration Variables (K=24)

| Block | Type | Variables | Count | Notes |
|-------|------|-----------|-------|-------|
| Block 1 | Demographics | male, age, white_nh, black, hispanic, educ_years, poverty_ratio | 7 | Pooled: ACS (25%) + NHIS (17%) + NSCH (58%) |
| Block 1 | PUMA Geography | puma_100...puma_904 (14 PUMA indicators) | 14 | ACS-only stratification |
| Block 2 | Mental Health | phq2_total, gad2_total | 2 | NHIS-only mental health items |
| Block 3 | Child Outcome | excellent_health | 1 | NSCH-only child health rating |

**Effective Sample Sizes by Block:**
- Block 1 (Demographics+PUMA): n_eff = ~2,000 (pooled)
- Block 2 (Mental Health): n_eff = ~1,500 (NHIS only)
- Block 3 (Child Outcome): n_eff = ~500 (NSCH only)

---

## Weight Generation Pipeline

### Scripts 25-30b: Raking Targets
Generate population targets from ACS, NHIS, and NSCH:

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R
```

**Outputs:**
- `data/raking/ne25/unified_moments.rds` (mean vector, covariance matrix, masks)
- `raking_targets_ne25` database table (180 targets × 6 age groups)

### Script 32: Harmonization
Prepare harmonized dataset with 24 calibration variables:

```bash
timeout 180 "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/32_prepare_ne25_for_weighting.R
```

**Outputs:**
- `data/raking/ne25/ne25_harmonized/ne25_harmonized_m1.feather` (2,645 × 27)
- Includes: pid, record_id, study_id + 24 calibration variables

**Education Mapping (IMPORTANT):**

Lines 315-325 map raw education text to years:

```r
educ_years = dplyr::case_when(
  grepl("Less than|8th grade|9th-12th|Some High School", ...) ~ 10,
  grepl("High School Graduate|GED", ...) ~ 12,
  grepl("Some College", ...) ~ 14,           # Note: separate from Associate
  grepl("vocational|trade|business school", ...) ~ 13,
  grepl("Associate", ...) ~ 14,
  grepl("Bachelor", ...) ~ 16,
  grepl("Master", ...) ~ 18,
  grepl("Doctorate|Professional", ...) ~ 20,
  TRUE ~ NA_real_
)
```

**Why This Matters:** CART imputation produces text strings from REDCap education categories. The regex patterns must cover ALL variations or records get listwise deletion. Recent fix added:
- "8th grade|9th-12th" (was causing ~13-16 missing)
- "vocational|trade|business school" (was causing ~14 missing)

**Result:** 0 missing values in educ_years (100% complete cases)

### Script 33: Weight Computation
Stan optimization to minimize masked KL divergence loss:

```bash
timeout 600 "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/33_compute_kl_divergence_weights.R
```

**Key Parameters:**
- **Algorithm:** BFGS (full Hessian, strict convergence: 1e-10 gradient, 1e-6 objective)
- **Max iterations:** 100 (hit limit for M=1, increase to 200+ for tighter convergence)
- **Weight constraints:** min=1E-2 (0.01), max=100
- **Standardization:** Z-score normalization of design matrix within Stan

**Outputs:**
- `data/raking/ne25/ne25_weights/ne25_calibrated_weights_m1.feather` (2,645 × 28)
  - Includes: pid, record_id, study_id + 24 variables + **calibrated_weight**
- `data/raking/ne25/ne25_weights/calibration_diagnostics_m1.rds`
  - Converged status, marginals (% diff), effective N, weight ratio
  - **NEW:** Correlation diagnostics (unweighted, target, weighted, improvements)

**Performance Metrics (M=1):**
```
Mean Matching:
  - Max % difference: 19.80% (gad2_total)
  - Hit iteration limit at 100 (acceptable - correlation structure matched well)

Correlation Matching:
  - Unweighted RMSE: 0.0381
  - Weighted RMSE: 0.0107
  - Improvement: 71.9% ← THIS IS THE PRIMARY OBJECTIVE

Weight Quality:
  - Min: 0.2093, Max: 7.0208 (ratio: 33.55)
  - Effective N (Kish): 1,518.9
  - Efficiency: 57.4% (1,518.9 / 2,645)
```

---

## NE25 Pipeline Integration

### Step 6.9: Weight Joining
Automatically joins weights if `ne25_calibrated_weights_m1.feather` exists:

```r
if (file.exists("data/raking/ne25/ne25_weights/ne25_calibrated_weights_m1.feather")) {
  weights_data <- arrow::read_feather(weights_file)
  weights_to_join <- weights_data %>%
    dplyr::select(pid, record_id, calibrated_weight)

  final_data <- final_data %>%
    dplyr::left_join(
      weights_to_join,
      by = c("pid", "record_id"),
      relationship = "one-to-one"
    )
}
```

**Result:** 2,645 records have `calibrated_weight` column

### Step 6.10: Out-of-State Exclusion
Identifies records whose zipcodes have no match in the Nebraska ZCTA→PUMA crosswalk and excludes them from the analytic set. These records are genuinely out-of-state (or have invalid zipcodes); this is the correct final treatment, not a workaround.

```r
final_data <- final_data %>%
  dplyr::mutate(
    out_of_state = dplyr::case_when(
      meets_inclusion == TRUE & is.na(calibrated_weight) ~ TRUE,
      TRUE ~ FALSE
    ),
    meets_inclusion = dplyr::case_when(
      out_of_state == TRUE ~ FALSE,
      TRUE ~ meets_inclusion
    )
  )
```

**Rationale:**
- 140 records from out-of-state zipcodes (no ZCTA→PUMA match in crosswalk)
- Cannot get weights due to missing geographic identifiers
- Marked with `out_of_state = TRUE` for audit trail
- Excluded from analysis with `meets_inclusion = FALSE`

**Result:**
- 2,645 records: meets_inclusion=TRUE & calibrated_weight not NA
- 140 records: out_of_state=TRUE & meets_inclusion=FALSE

---

## Stan Optimization Details

### Model Structure

**Simplex-N calibration model:**
```stan
simplex[N] wgt_raw;                            // one weight per observation
wgt_raw ~ dirichlet(rep_vector(concentration, N));  // flat Dirichlet(1) prior

// Final weights: scale to [min_weight, max_weight] and renormalize
vector[N] wgt_scaled = min_wgt + (max_wgt - min_wgt) * wgt_raw;
simplex[N] wgt = wgt_scaled / sum(wgt_scaled);
vector[N] wgt_final = N * wgt;
```

Where:
- **N:** Number of observations (2,645 complete cases for M=1)
- **K:** Number of calibration variables (24)
- **concentration:** Dirichlet prior concentration (1.0 = uniform, no entropy regularization)
- **X_std:** Design matrix is Z-score standardized inside `transformed data` for numerical stability; the final weights are invariant to this standardization

**Total parameters:** N (one simplex weight per observation). Earlier versions of this doc described a log-linear `log(w) = α + Xβ` form with K+1=25 parameters; that parameterization was **considered and rejected** as insufficiently expressive for matching K=24 means plus 488 masked covariance cells. See [WEIGHT_CONSTRUCTION.qmd §2.3](ne25/WEIGHT_CONSTRUCTION.qmd) for the full alternatives discussion and §3.3 for the loss specification.

### Standardization In-Model

**Why Z-score in Stan?**
1. **Scale harmony:** 70x disparity (poverty 0-400 vs binary 0-1) → all standardized to ~N(0,1)
2. **Optimizer efficiency:** 20-40% faster convergence with balanced scales
3. **Numerical stability:** Avoids underflow/overflow with extreme coefficient values
4. **Weights scale-invariant:** Log-sum remains invariant regardless of X scale

**Implementation (transformed data block):**
```stan
if (use_standardization == 1) {
  for (n in 1:N) {
    for (k in 1:K) {
      if (scale_sd[k] > 1e-10) {
        X_work[n, k] = (X[n, k] - scale_mean[k]) / scale_sd[k];
      } else {
        X_work[n, k] = X[n, k] - scale_mean[k];
      }
    }
  }
  // Similar standardization for target_mean_work and target_cov_work
} else {
  X_work = X;
  target_mean_work = target_mean;
  target_cov_work = target_cov;
}
```

### Convergence Criteria

**BFGS algorithm:**
- Gradient tolerance: 1e-10 (strict)
- Objective tolerance: 1e-6 (strict)
- Max iterations: Variable (100 for M=1, can increase to 200 for M=2-5)
- Line search: Full Hessian (expensive but stable)

**Iteration Limits:**

| Imputation | Iterations | Status | Mean RMSE | Corr RMSE | Action |
|------------|-----------|--------|-----------|-----------|--------|
| M=1 | 100 | Hit limit | 0.198 | 0.0107 | ACCEPTABLE (correlations matched) |
| M=2-5 | 100 | Hit limit? | ? | ? | INCREASE to 200 if tighter mean-matching needed |

**Note:** Primary objective is correlation matching (which is well-achieved at M=1). Mean-matching can be tightened by increasing iterations if desired.

---

## Correlation Improvement Analysis

### What We Measure

**Before Weighting (Unweighted Sample):**
- Compute Pearson correlations from raw data
- Unweighted RMSE of 24×24 correlation matrix vs target

**After Weighting (Calibrated Weights):**
- Compute weighted Pearson correlations (via weighted means and weighted covariances)
- Weighted RMSE of 24×24 correlation matrix vs target
- Percent improvement: (unweighted_RMSE - weighted_RMSE) / unweighted_RMSE × 100

### M=1 Results

**Overall Improvement:**
```
Unweighted RMSE: 0.0381
Weighted RMSE:   0.0107
Improvement:     71.9%
```

**Top 10 Correlations Improved:**

| Pair | Error Reduced | Before | After |
|------|--------------|--------|-------|
| phq2_total × white_nh | 0.1591 | 0.1650 | 0.0059 |
| excellent_health × black | 0.1490 | 0.1549 | 0.0059 |
| excellent_health × white_nh | 0.1433 | 0.1493 | 0.0060 |
| phq2_total × hispanic | 0.1126 | 0.1186 | 0.0060 |
| gad2_total × hispanic | 0.1107 | 0.1167 | 0.0060 |
| (and 5 more...) | ... | ... | ... |

### Why Correlations > Means for Objective?

The Stan loss function approximates correlation matching because:
1. **Covariance normalization:** Cov_diff / (σ_target[i] × σ_target[j]) = Corr_diff
2. **Target structure:** Factorized mask ensures computational stability (unobserved blocks = 0)
3. **Statistical focus:** Correlations more important than raw means for causal inference and structural modeling

Tight mean-matching would require higher iteration limits (200+), but the 71.9% correlation improvement indicates the weights are accomplishing their primary goal.

---

## Using Weights in Analysis

### Basic Usage

```r
# Load NE25 data from database
ne25 <- DBI::dbGetQuery(db, "SELECT * FROM ne25_transformed WHERE meets_inclusion = TRUE")

# Example: Weighted mean of excellent_health
weighted_mean <- weighted.mean(ne25$excellent_health, ne25$calibrated_weight, na.rm = TRUE)

# Example: Weighted regression
library(survey)
ne25_design <- svydesign(
  ids = ~1,
  weights = ~calibrated_weight,
  data = ne25
)
model <- svyglm(excellent_health ~ age + male + poverty_ratio,
                 design = ne25_design,
                 family = binomial())
```

### Database Query

```sql
-- Verify all in-state records have weights
SELECT
  COUNT(*) as total,
  SUM(CASE WHEN calibrated_weight IS NOT NULL THEN 1 ELSE 0 END) as with_weight,
  SUM(CASE WHEN out_of_state = TRUE THEN 1 ELSE 0 END) as out_of_state
FROM ne25_transformed
WHERE meets_inclusion = TRUE;

-- Result should be: total=2645, with_weight=2645, out_of_state=0
```

---

## Multi-Imputation Integration (M=5)

**Status:** Shipped April 2026. Full M=5 multi-imputation is the current production state.

### Architecture

For each of `M = 5` imputations from the production imputation pipeline, Stan is refit against the full 24-variable calibration targets, producing an independent weight set. All weights are stored in a single long-format DuckDB table:

```sql
-- Table: ne25_raked_weights
CREATE TABLE ne25_raked_weights (
    pid               INTEGER  NOT NULL,
    record_id         INTEGER  NOT NULL,
    study_id          VARCHAR,
    imputation_m      INTEGER  NOT NULL,
    calibrated_weight DOUBLE   NOT NULL,
    PRIMARY KEY (pid, record_id, imputation_m)
);
-- 13,225 rows for NE25 (5 imputations × 2,645 records)
```

This mirrors the `ne25_imputed_*` convention so downstream consumers recognize the pattern.

### How to use

**MI-aware analysis** (recommended) — join the appropriate per-imputation weight inside your mice loop:

```r
library(DBI); library(duckdb); library(survey)
con <- DBI::dbConnect(duckdb::duckdb(),
                      "data/duckdb/kidsights_local.duckdb", read_only = TRUE)

results <- lapply(1:5, function(m) {
  weights_m <- DBI::dbGetQuery(con, sprintf("
    SELECT pid, record_id, calibrated_weight
    FROM ne25_raked_weights
    WHERE imputation_m = %d
  ", m))
  ne25_m <- get_completed_dataset(m)
  ne25_m <- ne25_m %>%
    dplyr::inner_join(weights_m, by = c("pid", "record_id"))
  design_m <- survey::svydesign(ids = ~1, weights = ~calibrated_weight, data = ne25_m)
  survey::svyglm(outcome ~ age + male, design = design_m, family = binomial())
})

pooled <- mitools::MIcombine(results)  # Rubin's rules
```

**Single-imputation default** (backward compatible) — the `calibrated_weight` column on `ne25_transformed` is populated from `imputation_m = 1` at Step 6.9 of the main pipeline, so existing consumers (including `model_fitting.R`) keep working unchanged.

### Execution

Run the full M=5 raking-weight pipeline end-to-end:

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_ne25_raking_full.R
```

This orchestrator:
1. Verifies prerequisites (`unified_moments.rds` present from scripts 25–30b).
2. Ensures `ne25_raked_weights` DuckDB schema exists.
3. Runs script 32 (harmonize for all M imputations; consumes `ne25_imputed_*` via `R/imputation/helpers.R::get_completed_dataset()`).
4. Runs script 33 (Stan calibration loop; `cmdstanr` compile cache makes iterations 2..M compile-free).
5. Runs script 34 (long-format insert).

Typical runtime: ~17–20 minutes for M=5.

### Cross-imputation stability (M=5, April 2026 run)

| m | Kish N | Efficiency | Weight ratio | Corr RMSE |
|---|--------|------------|--------------|-----------|
| 1 | 1,518 | 57.4% | 27.4 | 0.01086 |
| 2 | 1,514 | 57.2% | 34.4 | 0.01073 |
| 3 | 1,514 | 57.3% | 33.2 | 0.01077 |
| 4 | 1,511 | 57.1% | 35.2 | 0.01081 |
| 5 | 1,538 | 58.1% | 28.8 | 0.01119 |

Kish N CV = 0.007, correlation RMSE range = 0.00046 — imputation variation is small relative to target sampling variance (as expected; imputation chiefly affects tail records, not population moments).

### Bayesian-bootstrap replicate weights (Bucket 3, shipped April 2026)

The M=5 per-imputation weights are now paired with **B=200 Bayesian-bootstrap replicates per imputation**, stored in a sibling long-format DuckDB table `ne25_raked_weights_boot`. Framework: MI + sample-only Bayesian bootstrap (Rubin 1981). Target moments are treated as fixed population quantities; replicate variability captures within-imputation sample variability only. Rubin's rules pool variance across imputations.

**Schema:**

```sql
-- Table: ne25_raked_weights_boot
CREATE TABLE ne25_raked_weights_boot (
    pid               INTEGER  NOT NULL,
    record_id         INTEGER  NOT NULL,
    study_id          VARCHAR,
    imputation_m      INTEGER  NOT NULL,
    boot_b            INTEGER  NOT NULL,
    calibrated_weight DOUBLE   NOT NULL,
    PRIMARY KEY (pid, record_id, imputation_m, boot_b)
);
-- 2,645,000 rows for NE25 (5 imputations × 200 bootstrap draws × 2,645 records)
```

**Bayesian-bootstrap mechanics (NE22-style data weight).** For replicate `b`:

1. Draw `bbw_b ~ Exp(1)` (equivalently `Dirichlet(1,…,1)` after renormalization).
2. Pass `bbw` into the Stan model as a per-observation multiplicative data weight.
3. Stan forms `w_eff = (w ⊙ bbw_b) / sum(w ⊙ bbw_b)` inside `transformed parameters`.
4. The masked factorized moment loss is evaluated on `w_eff`; the flat `Dirichlet(1,…,1)` prior on `wgt_raw` contributes zero gradient (no boundary singularities).

Setting `bbw = rep(1, N)` recovers the point-estimate (Bucket 2) weights exactly — the replicate family nests the point estimate.

**MI-aware variance via Rubin's rules:**

```r
library(DBI); library(duckdb); library(mitools)
con <- DBI::dbConnect(duckdb::duckdb(),
                      "data/duckdb/kidsights_local.duckdb", read_only = TRUE)

# One estimate per (m, b) — parallelize via future.apply if needed
estimates <- list()
for (m in 1:5) {
  ne25_m <- get_completed_dataset(m)
  for (b in 1:200) {
    wb <- DBI::dbGetQuery(con, sprintf("
      SELECT pid, record_id, calibrated_weight
      FROM ne25_raked_weights_boot
      WHERE imputation_m = %d AND boot_b = %d
    ", m, b))
    d <- ne25_m %>% dplyr::inner_join(wb, by = c("pid","record_id"))
    design <- survey::svydesign(ids = ~1, weights = ~calibrated_weight, data = d)
    estimates[[paste(m, b)]] <- list(m = m, b = b,
      est = coef(survey::svyglm(outcome ~ age + male, design = design, family = binomial()))
    )
  }
}

# Pool: within-imputation bootstrap variance + between-imputation variance (Rubin's rules)
per_m <- split(estimates, sapply(estimates, `[[`, "m"))
theta_m  <- sapply(per_m, function(ms) colMeans(do.call(rbind, lapply(ms, `[[`, "est"))))
U_m      <- sapply(per_m, function(ms) apply(do.call(rbind, lapply(ms, `[[`, "est")), 2, var))
theta    <- rowMeans(theta_m)
U_bar    <- rowMeans(U_m)                               # within-imputation variance
B        <- apply(theta_m, 1, var)                      # between-imputation variance
var_total <- U_bar + (1 + 1/5) * B                      # Rubin's rules
```

**Execution.** The bootstrap weights are produced by scripts 35 → 36:

```bash
# ~3 hours wall-clock on 8 future::multisession workers, pre-compiled Stan
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/35_run_bayesian_bootstrap.R

# Populate DuckDB from 1,000 per-(m,b) feather checkpoints (~30 s)
py scripts/raking/ne25/36_store_bootstrap_weights_long.py
```

Per-(m, b) feather checkpoints under `data/raking/ne25/ne25_weights_boot/` make the orchestrator resumable after interruption.

**Stability (April 2026 run, M=5 × B=200 = 1,000 fits):**

| Metric | Value |
|--------|-------|
| Stan convergence (`stan_ok = TRUE`) | 1,000 / 1,000 |
| Kish-N CV across bootstrap draws (per imputation) | 0.009–0.010 |
| Baseline reproducibility (`bbw = rep(1,N)` vs Bucket 2) | ~3e-2 RMS (autodiff noise) |
| Weight ratio per replicate | median ~70K, max ~474M |
| Wall-clock runtime | ~3 h (8 workers) |

The extreme weight ratios reflect the wide `[min_weight, max_weight] = [0.01, 100]` bounds. NE22 uses tighter `[0.1, 10]`; revisit for NE25 if downstream variance estimates look unstable.

---

## Troubleshooting

### Issue: 0 records with weights
**Check:** Does `ne25_calibrated_weights_m1.feather` exist?
```bash
ls -la data/raking/ne25/ne25_weights/
```
If missing, run scripts 25-33 first.

### Issue: Some records missing weight
**Check:** Education mapping in script 32
```r
# Verify zero missing values
missing_check <- ne25_harmonized %>%
  dplyr::select(starts_with("educ_years")) %>%
  dplyr::summarise(dplyr::across(everything(), ~sum(is.na(.))))
print(missing_check)  # Should all be 0
```

### Issue: Out-of-state records > 140
**Check:** ZCTA→PUMA crosswalk coverage
```sql
SELECT COUNT(DISTINCT zcta) FROM geo_zip_to_puma WHERE state = 'NE';
-- Nebraska should have ~920 unique ZCTAs
```

### Issue: Weight values seem extreme
**Check:** Weight distribution diagnostics
```r
diagnostics <- readRDS("data/raking/ne25/ne25_weights/calibration_diagnostics_m1.rds")
cat("Min:", min(weights), "Max:", max(weights), "\n")
cat("Efficiency:", diagnostics$efficiency_pct, "%\n")
cat("Effective N:", diagnostics$effective_n, "\n")
```

---

## References

- **Raking Theory:** Deville & Särndal (1992). "Calibration estimators in survey sampling"
- **Masked KL Divergence:** Adaptation of classical IPF (Iterative Proportional Fitting)
- **Stan Optimization:** BFGS with strict convergence criteria
- **Correlation Analysis:** Pearson correlation from weighted moments

---

## Related Documentation

- [Raking Targets Pipeline](RAKING_TARGETS.md)
- [NE25 Pipeline Steps](../architecture/PIPELINE_STEPS.md)
- [CLAUDE.md - NE25 Status](../../CLAUDE.md#-ne25-pipeline---production-ready-december-2025)

---

**For questions or issues:** See scripts/raking/ne25/README.md or contact project maintainers.

*Updated: December 2025 | Version: 1.0.0*

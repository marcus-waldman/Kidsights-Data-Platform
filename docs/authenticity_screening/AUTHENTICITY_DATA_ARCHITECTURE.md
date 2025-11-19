# Authenticity Screening Data Architecture

**Last Updated:** January 2025
**Version:** 2.0 (Two-Dimensional IRT with Cook's D Diagnostics)

---

## Overview

The authenticity screening system provides comprehensive metrics for assessing response authenticity and influence on parameter estimates. The architecture separates expensive computation (caching) from fast merging (pipeline integration).

---

## Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│ PHASE 1: DATA PREPARATION                                        │
│ scripts/authenticity_screening/01_prepare_data.R                 │
│   Output: data/temp/stan_data_authentic.rds (N=2,635)           │
│           data/temp/stan_data_inauthentic.rds (N=872)            │
└──────────────────────────────────────────────────────────────────┘
                                ↓
┌──────────────────────────────────────────────────────────────────┐
│ PHASE 2: LOOCV + COOK'S D (AUTHENTIC)                            │
│ scripts/authenticity_screening/03_run_loocv.R                    │
│   → Fits full N=2,635 model                                     │
│   → Runs 2,635 LOOCV iterations (~4.5 min, 16 cores)            │
│   → Auto-computes Cook's D via compute_cooks_d.R                 │
│                                                                   │
│ Output: results/full_model_params.rds                            │
│         results/full_model_eta_lookup.rds (2D eta, 6 columns)    │
│         results/loocv_authentic_results.rds                      │
│         results/loocv_cooks_d.rds (LOOCV + Cook's D)             │
│         results/loocv_hessian_approx.rds (541×541 Hessian)       │
└──────────────────────────────────────────────────────────────────┘
                                ↓
┌──────────────────────────────────────────────────────────────────┐
│ PHASE 3: INAUTHENTIC LOGPOST + COOK'S D                          │
│ scripts/authenticity_screening/04_compute_inauthentic_logpost.R  │
│   → Computes avg_logpost for inauthentic (holdout model)        │
│   → Extracts 2D eta estimates                                    │
│                                                                   │
│ scripts/authenticity_screening/05_compute_inauthentic_cooks_d.R  │
│   → Fits N+1 models (N_authentic + 1 inauthentic)               │
│   → Computes Cook's D using jackknife Hessian (~10 min)         │
│   → Extracts 2D eta from augmented models                        │
│                                                                   │
│ Output: results/inauthentic_logpost_results.rds (2D eta)         │
│         results/inauthentic_cooks_d.rds (Cook's D + 2D eta)      │
└──────────────────────────────────────────────────────────────────┘
                                ↓
┌──────────────────────────────────────────────────────────────────┐
│ PHASE 4: MERGE TO PIPELINE                                       │
│ scripts/authenticity_screening/08_compute_pipeline_weights_v2.R  │
│   → Loads all cached results (no re-computation)                 │
│   → Merges 12 authenticity columns                               │
│   → Returns data frame for database insertion                    │
│                                                                   │
│ Output: Data frame with 12 new columns (see below)               │
└──────────────────────────────────────────────────────────────────┘
```

---

## Cache Files

All cache files stored in `results/`:

| File | Source Script | Rows | Columns | Purpose |
|------|---------------|------|---------|---------|
| `full_model_params.rds` | 03_run_loocv.R | 1 | list | Full model parameters (tau, beta1, delta, eta_corr, eta matrix) |
| `full_model_eta_lookup.rds` | 03_run_loocv.R | 2,635 | 6 | 2D eta (full + holdout) for authentic participants |
| `loocv_authentic_results.rds` | 03_run_loocv.R | 2,635 | ~15 | LOOCV results with param_diff, lz, avg_logpost |
| `loocv_distribution_params.rds` | 03_run_loocv.R | 1 | list | Mean/SD for standardization |
| `loocv_cooks_d.rds` | compute_cooks_d.R | 2,635 | ~19 | LOOCV + Cook's D diagnostics |
| `loocv_hessian_approx.rds` | compute_cooks_d.R | 541×541 | matrix | Jackknife Hessian approximation |
| `inauthentic_logpost_results.rds` | 04_compute_inauthentic_logpost.R | 872 | ~12 | Inauthentic avg_logpost + 2D eta |
| `inauthentic_cooks_d.rds` | 05_compute_inauthentic_cooks_d.R | 872 | 12 | Inauthentic Cook's D + 2D eta |

---

## Database Schema

### Table: `ne25_transformed`

**12 Authenticity Columns Added:**

#### 1. Weighting & Scoring (4 columns)

```sql
authenticity_weight                      DOUBLE     -- 1.0 (authentic) or 0.42-1.96 (inauthentic) or NA (<5 items)
authenticity_lz                          DOUBLE     -- Standardized z-score: (avg_logpost - mean) / sd
authenticity_avg_logpost                 DOUBLE     -- log_posterior / n_items (per-item average)
authenticity_quintile                    INTEGER    -- Quintile 1-5 based on LOOCV distribution
```

#### 2. Two-Dimensional IRT Parameters (4 columns)

```sql
authenticity_eta_psychosocial_full       DOUBLE     -- Dimension 1 (psychosocial problems), full model
authenticity_eta_developmental_full      DOUBLE     -- Dimension 2 (developmental), full model
authenticity_eta_psychosocial_holdout    DOUBLE     -- Dimension 1, LOOCV/holdout estimate
authenticity_eta_developmental_holdout   DOUBLE     -- Dimension 2, LOOCV/holdout estimate
```

**Interpretation:**
- **Full model eta**: Estimated from joint model (N=2,635 authentic OR N+1 augmented for inauthentic)
- **Holdout eta**: Out-of-sample estimate (LOOCV for authentic, same as full for inauthentic)
- **Psychosocial dimension**: Captures externalizing/internalizing problems (61 items)
- **Developmental dimension**: Captures cognitive, motor, language, social-emotional skills (208 items)

#### 3. Cook's D Influence Diagnostics (4 columns)

```sql
authenticity_cooks_d                     DOUBLE     -- Raw Cook's D influence metric
authenticity_cooks_d_scaled              DOUBLE     -- Sample-size invariant: D × N
authenticity_influential_4               BOOLEAN    -- Highly influential: D×N > 4
authenticity_influential_N               BOOLEAN    -- Very high influence: D×N > N
```

**Interpretation:**
- **Cook's D**: Measures how much parameter estimates change when participant is included/excluded
- **D × N scaling**: Makes metric comparable across studies (threshold D×N > 4 is study-invariant)
- **Authentic**: Based on jackknife (LOOCV parameter differences)
- **Inauthentic**: Based on augmented models (N_authentic + 1)

**Use cases:**
- `influential_4 = TRUE`: Participant has substantial influence on parameter estimates
- High Cook's D + Low lz: Response pattern is both unusual AND influential → flag for QA
- High Cook's D + High lz: Gaming strategy that pulls parameters → potential inauthenticity

---

## Data Quality Flags

### Inclusion Criteria

```r
meets_inclusion = (eligible == TRUE & !is.na(authenticity_weight))
```

**Breakdown:**
- **Eligible:** Meets survey eligibility criteria
- **Non-NA weight:** Has ≥5 items answered (sufficient for authenticity assessment)

**Expected counts (NE25):**
- Authentic: 2,635 (all eligible authentic have weight = 1.0)
- Inauthentic: ~196 (those with ≥5 items get propensity weights)
- **Total meets_inclusion:** ~2,831 participants

### Missingness Patterns

| Condition | N | Weight | Eta (2D) | Cook's D | Reason |
|-----------|---|--------|----------|----------|--------|
| Authentic, converged | 2,635 | 1.0 | Present (both) | Present | Normal case |
| Inauthentic, ≥5 items | ~196 | 0.42-1.96 | Present (both) | Present | Sufficient data |
| Inauthentic, <5 items | ~676 | NA | NA | NA | Insufficient data |
| Authentic, non-converged | ~0 | 1.0 | NA | NA | Rare convergence failure |

---

## Computation Time

**First-time setup (cold cache):**
```
01_prepare_data.R                  ~30 seconds
03_run_loocv.R                     ~5 minutes (16 cores)
  └─ compute_cooks_d.R             ~10 seconds (auto-run)
04_compute_inauthentic_logpost.R   ~2 minutes
05_compute_inauthentic_cooks_d.R   ~10 minutes (16 cores)
───────────────────────────────────────────────────
TOTAL FIRST RUN:                   ~18 minutes
```

**Subsequent pipeline runs (warm cache):**
```
08_compute_pipeline_weights_v2.R   <1 second (loads cached results)
```

**Cache invalidation triggers:**
- Stan model changes (`authenticity_glmm.stan`, `authenticity_holdout.stan`)
- Calibration item changes (added/removed items)
- Training data changes (new authentic participants)

---

## Usage Examples

### 1. Run Complete Pipeline (First Time)

```r
# Step 1: Prepare data
source("scripts/authenticity_screening/01_prepare_data.R")

# Step 2: Run LOOCV + Cook's D (authentic) (~5 min)
source("scripts/authenticity_screening/03_run_loocv.R")

# Step 3: Compute inauthentic logpost (~2 min)
source("scripts/authenticity_screening/04_compute_inauthentic_logpost.R")

# Step 4: Compute inauthentic Cook's D (~10 min)
source("scripts/authenticity_screening/05_compute_inauthentic_cooks_d.R")

# Step 5: Merge to pipeline data (<1 sec)
source("scripts/authenticity_screening/08_compute_pipeline_weights_v2.R")
data_with_authenticity <- compute_authenticity_weights(data)
```

### 2. Use Cached Results (Fast)

```r
# All cache files exist from previous run
source("scripts/authenticity_screening/08_compute_pipeline_weights_v2.R")
data_with_authenticity <- compute_authenticity_weights(data)

# Creates meets_inclusion flag
data_with_authenticity <- data_with_authenticity %>%
  dplyr::mutate(
    meets_inclusion = (eligible & !is.na(authenticity_weight))
  )
```

### 3. Query Influential Participants

```sql
-- Highly influential participants (D×N > 4)
SELECT pid, record_id, authentic,
       authenticity_cooks_d_scaled,
       authenticity_lz,
       authenticity_avg_logpost
FROM ne25_transformed
WHERE authenticity_influential_4 = TRUE
ORDER BY authenticity_cooks_d_scaled DESC;

-- Suspicious: influential + unusual pattern
SELECT pid, record_id, authentic,
       authenticity_cooks_d_scaled,
       authenticity_lz
FROM ne25_transformed
WHERE authenticity_influential_4 = TRUE
  AND authenticity_lz < -2.0  -- Unusual pattern (low log-posterior)
ORDER BY authenticity_cooks_d_scaled DESC;
```

### 4. Extract 2D Eta for Analysis

```r
library(duckdb)
con <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Get 2D eta for all participants
eta_data <- dbGetQuery(con, "
  SELECT pid, record_id, authentic,
         authenticity_eta_psychosocial_full,
         authenticity_eta_developmental_full,
         authenticity_eta_psychosocial_holdout,
         authenticity_eta_developmental_holdout
  FROM ne25_transformed
  WHERE meets_inclusion = TRUE
")

# Correlation between dimensions
cor(eta_data$authenticity_eta_psychosocial_full,
    eta_data$authenticity_eta_developmental_full,
    use = "complete.obs")
```

---

## Integration with Age Gradient Explorer

The Cook's D metrics support the Age Gradient Explorer Shiny app's QA masking system:

1. **Influential items identified** via Cook's D at participant level
2. **Cross-referenced with age-response gradients** in Age Gradient Explorer
3. **Masking decisions** informed by both influence and developmental plausibility
4. **`maskflag` column** in `calibration_dataset_long` tracks QA-cleaned data

**Workflow:**
```
Cook's D → Identify influential participants
           ↓
Age Gradient Explorer → Review item-level responses
           ↓
Manual review → Set maskflag = 1 for problematic observations
           ↓
Rerun calibration → Exclude masked data from parameter estimation
```

---

## Version History

**v2.0 (January 2025):**
- Added two-dimensional IRT parameters (psychosocial + developmental)
- Added Cook's D influence diagnostics for authentic and inauthentic
- Streamlined pipeline weights function (v2) using cached results
- 12 database columns (up from 6 in v1.0)

**v1.0 (October 2025):**
- Initial implementation with 1D eta and quintile-based weighting
- 6 database columns (weight, lz, avg_logpost, quintile, eta_full, eta_holdout)

---

## References

- **Stan Model:** `models/authenticity_glmm.stan` (two-dimensional IRT with LKJ correlation)
- **Holdout Model:** `models/authenticity_holdout.stan` (LOOCV and inauthentic scoring)
- **Cook's D Theory:** Influence diagnostics via jackknife Hessian approximation
- **Weighting Strategy:** Quintile-based propensity score weighting for ATT estimation

# Individual Latent Ability (eta) Extraction Guide

**Date:** November 12, 2025
**Author:** Marcus Yuen
**Related Pipeline:** NE25 Authenticity Screening (Step 6.5)

---

## Summary

The NE25 authenticity screening pipeline **already extracts individual latent ability estimates (eta)** for each participant during the leave-one-out cross-validation (LOOCV) process. These estimates represent each person's latent ability on the underlying developmental construct measured by the survey items.

### What is eta_est?

- **eta_est**: Individual's random effect from the Generalized Linear Mixed Model (GLMM)
- **Interpretation**: Latent developmental ability on the construct being measured
- **Scale**: Centered at 0 (population mean)
- **Higher values**: More advanced developmental skills
- **Model**: Estimated by fixing item parameters (tau, beta1, delta) and solving for the person-specific eta_i

---

## Current Status

### ✅ What's Already Working

**eta_est is extracted and saved in intermediate files:**

1. **`results/loocv_authentic_results.rds`**
   - Contains `eta_est` for 2,633 authentic participants
   - Columns: `i, pid, log_posterior, avg_logpost, n_items, eta_est, converged_main, converged_holdout, lz`

2. **`results/inauthentic_logpost_results.rds`**
   - Contains `eta_est` for 196 inauthentic participants (with 5+ items and converged)
   - Columns: `pid, log_posterior, avg_logpost, n_items, eta_est, sufficient_data, converged, lz`

### ❌ What's NOT Yet Implemented

- **eta_est is NOT stored in the database** (`ne25_transformed` table)
- Currently only these authenticity columns are in the database:
  - `authenticity_weight`
  - `authenticity_lz`
  - `authenticity_avg_logpost`
  - `authenticity_quintile`
  - `meets_inclusion`

---

## How to Access eta_est

### Option 1: Extract from Intermediate Files (Current Method)

**Quick extraction script:**

```r
# Load both files
library(dplyr)

authentic <- readRDS("results/loocv_authentic_results.rds") %>%
  filter(converged_main & converged_holdout) %>%
  select(pid, eta_est, lz, avg_logpost)

inauthentic <- readRDS("results/inauthentic_logpost_results.rds") %>%
  filter(sufficient_data & converged) %>%
  select(pid, eta_est, lz, avg_logpost)

# Combine
all_eta <- bind_rows(authentic, inauthentic) %>%
  arrange(pid)

# Save as CSV for easy inspection
write.csv(all_eta, "results/individual_eta_estimates.csv", row.names = FALSE)
```

**Automated extraction:**

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/temp/extract_eta_estimates.R
```

This creates:
- `results/individual_eta_estimates.rds`
- `results/individual_eta_estimates.csv`

**Output:**
- 2,829 participants (2,633 authentic + 196 inauthentic)
- Columns: `pid, eta_est, lz, avg_logpost, log_posterior, n_items, authentic`

### Option 2: Add eta_est to Database (Recommended for Production)

**Run migration script:**

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/database/add_eta_estimate_column.R
```

This will:
1. Add `authenticity_eta_est` column to `ne25_transformed` table
2. Populate it from LOOCV and inauthentic results files
3. Create an index for efficient querying
4. Verify the update

**Query example after migration:**

```sql
-- Get participants with highest developmental ability
SELECT pid, record_id, authenticity_eta_est, authenticity_weight, authenticity_lz
FROM ne25_transformed
WHERE authenticity_eta_est IS NOT NULL
ORDER BY authenticity_eta_est DESC
LIMIT 10;

-- Compare authentic vs inauthentic
SELECT
  authentic,
  COUNT(*) as n,
  AVG(authenticity_eta_est) as mean_eta,
  MIN(authenticity_eta_est) as min_eta,
  MAX(authenticity_eta_est) as max_eta
FROM ne25_transformed
WHERE authenticity_eta_est IS NOT NULL
GROUP BY authentic;
```

---

## Summary Statistics

### Current Distribution (November 2025)

| Group | N | Mean eta | SD eta | Min eta | Max eta |
|-------|---|----------|--------|---------|---------|
| Authentic | 2,633 | -0.002 | 0.935 | -8.78 | 5.57 |
| Inauthentic | 196 | 0.239 | 1.09 | -3.73 | 3.14 |

### Key Insights

1. **Authentic participants** have slightly wider range (more extreme values)
2. **Inauthentic participants** have slightly higher mean eta (0.239 vs -0.002)
3. **Low correlation** between eta_est and lz (authenticity screening metric):
   - Authentic: r = 0.196
   - Inauthentic: r = -0.045
4. **Independence**: eta_est measures developmental ability, while lz measures response pattern authenticity

---

## Implementation Details

### Where eta_est is Extracted

**File:** `scripts/authenticity_screening/03_run_loocv.R`
**Lines:** 271, 284

```r
# Line 271: Extract eta from holdout model
eta_est <- fit_holdout$par["eta_holdout"]

# Line 284: Store in results list
eta_est = eta_est,
```

**File:** `scripts/authenticity_screening/04_compute_inauthentic_logpost.R`
**Lines:** 184, 192

```r
# Line 184: Extract eta from holdout model
eta_est <- fit_holdout$par["eta_holdout"]

# Line 192: Store in results list
eta_est = eta_est,
```

### Why eta_est is NOT in Database Currently

**File:** `scripts/authenticity_screening/08_compute_pipeline_weights.R`
**Lines:** 392-399

```r
# Only these columns are merged to database
weight_lookup <- inauthentic_scored %>%
  dplyr::select(pid, record_id, authenticity_weight, lz, avg_logpost, quintile) %>%
  dplyr::rename(
    authenticity_weight = authenticity_weight,
    authenticity_lz = lz,
    authenticity_avg_logpost = avg_logpost,
    authenticity_quintile = quintile
  )

# eta_est is NOT included in this weight_lookup!
```

---

## Recommendations

### For Research Use

If you're analyzing the relationship between developmental ability (eta) and authenticity screening:

1. **Use Option 1** (extract from intermediate files)
2. Merge with database data using `pid` as the key
3. Examine correlation between `eta_est` and `authenticity_lz`

**Example research question:**
- Do participants with lower developmental ability (eta) show more inauthentic response patterns (low lz)?

### For Production Pipeline

If you want `eta_est` available for all downstream analyses:

1. **Use Option 2** (add to database)
2. Update `scripts/authenticity_screening/08_compute_pipeline_weights.R` to include `eta_est` in the weight_lookup
3. Modify `pipelines/orchestration/ne25_pipeline.R` (Step 6.5) to save eta_est to database

**Modified code for `08_compute_pipeline_weights.R` (Line 392-399):**

```r
# Include eta_est in weight_lookup
weight_lookup <- inauthentic_scored %>%
  dplyr::select(pid, record_id, authenticity_weight, lz, avg_logpost, quintile, eta_est) %>%
  dplyr::rename(
    authenticity_weight = authenticity_weight,
    authenticity_lz = lz,
    authenticity_avg_logpost = avg_logpost,
    authenticity_quintile = quintile,
    authenticity_eta_est = eta_est  # ADD THIS LINE
  )
```

---

## Frequently Asked Questions

### Q1: What's the difference between eta_est and authenticity_lz?

- **eta_est**: Individual's latent developmental ability (how skilled they are)
- **authenticity_lz**: Standardized authenticity screening metric (how authentic their responses are)
- **Relationship**: Low correlation (r ≈ 0.20 for authentic, r ≈ -0.04 for inauthentic)

### Q2: Why are some participants missing eta_est?

Missing `eta_est` occurs when:
1. **Insufficient data**: < 5 item responses (not enough to estimate ability)
2. **Non-convergence**: Optimization failed to find a solution
3. **Inauthentic flag**: Participant was flagged as inauthentic before LOOCV (not included in authentic LOOCV)

### Q3: Can I use eta_est as a covariate in analyses?

**Yes**, but consider:
- eta_est is estimated from the same data you're analyzing (circularity risk)
- Use with caution if the outcome is related to the developmental construct
- Better for exploratory analyses or as a quality control metric

### Q4: Should I weight by authenticity_weight when using eta_est?

**It depends:**
- If analyzing developmental ability distributions: **Yes**, weight by `authenticity_weight`
- If analyzing authenticity screening itself: **No**, use unweighted eta_est
- If analyzing relationship between ability and authenticity: Use both, examine weighted vs unweighted

---

## Related Documentation

- **Authenticity Screening Overview:** [docs/authenticity_screening/README.md](../authenticity_screening/README.md)
- **LOOCV Implementation:** [scripts/authenticity_screening/03_run_loocv.R](../../scripts/authenticity_screening/03_run_loocv.R)
- **Pipeline Integration:** [pipelines/orchestration/ne25_pipeline.R](../../pipelines/orchestration/ne25_pipeline.R)
- **Database Schema:** [docs/architecture/DATABASE_SCHEMA.md](../architecture/DATABASE_SCHEMA.md)

---

## Contact

For questions about eta_est extraction or authenticity screening methodology:
- **Developer:** Marcus Yuen
- **Pipeline:** NE25 Authenticity Screening
- **Model:** `models/authenticity_glmm.stan`, `models/authenticity_holdout.stan`

---

**Last Updated:** November 12, 2025
**Version:** 1.0.0

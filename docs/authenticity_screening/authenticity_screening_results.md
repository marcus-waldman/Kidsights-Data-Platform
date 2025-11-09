# Authenticity Screening: LOOCV-Based Weighting Methodology

**Date:** November 2025
**Study:** Nebraska 2025 (NE25)
**Approach:** Leave-One-Out Cross-Validation with ATT Weighting

---

## Executive Summary

This document describes the authenticity screening methodology developed for the NE25 study using a 230-item graded response model (GLMM) estimated via Stan. The approach uses **Leave-One-Out Cross-Validation (LOOCV)** to build an out-of-sample distribution of log-posterior values for authentic participants, then compares inauthentic participants against this distribution.

**Key Findings:**
- **LOOCV Distribution:** 2,635 authentic participants, 99.9% convergence rate
- **Inauthentic Coverage:** 196 participants with sufficient data (5+ items), **100% fall within authentic range**
- **ROC Performance:** Poor discrimination (AUC 0.34-0.50) due to complete distributional overlap
- **Recommended Approach:** **ATT weighting** instead of binary classification
- **Final Weights:** Range 5.67 to 26.35, sum = 2,633 (effective sample size matches authentic)

---

## 1. Background and Motivation

### 1.1 Study Context

The NE25 study collected developmental and behavioral data on 3,507 children using REDCap. Standard authenticity checks (birthday verification, CID7) identified **872 inauthentic participants** (24.9% of sample). However, many inauthentic participants provided substantial item response data before failing authenticity checks.

**Question:** Can we use item response patterns to distinguish authentic from inauthentic participants and create **continuous authenticity weights** for analysis?

### 1.2 Data Limitation

Of 872 inauthentic participants:
- **468 (53.7%)** have 0 item responses
- **207 (23.7%)** have exactly 3 responses
- **196 (22.5%)** have 5+ item responses ← **sufficient for analysis**

Only the 196 with 5+ items can be included in log-posterior-based screening.

---

## 2. Methodology

### 2.1 Statistical Model

**Graded Response Model (GLMM):**
- **Items:** 230 developmental/behavioral items (172 original + 58 NOM, excluding 46 PS)
- **Response Categories:** Mixed binary and polytomous (K = 2 to 5)
- **Cumulative Logit Structure:**
  ```
  P(Y_ij ≥ k | η_i) = logit^(-1)(τ_j + (k-1)δ - β_1j * age_i - η_i)
  ```
- **Parameters:**
  - `η_i ~ N(0, 1)`: Person ability (sum-to-zero constraint)
  - `τ_j`: Item difficulty
  - `β_1j`: Age discrimination
  - `δ`: Threshold spacing (shared across items)
- **Backend:** rstan 2.36.0.9000 (Stan 2.37.0)

### 2.2 Leave-One-Out Cross-Validation (LOOCV)

**Objective:** Build an **out-of-sample** distribution of average log-posterior values for authentic participants to avoid overfitting.

**Two-Model Architecture:**

1. **Main Model** (`authenticity_glmm.stan`):
   - Fit on N-1 authentic participants
   - Estimate all parameters: `η[1:(N-1)]`, `τ[1:J]`, `β_1[1:J]`, `δ`

2. **Holdout Model** (`authenticity_holdout.stan`):
   - Takes item parameters from N-1 fit as **DATA** (fixed)
   - Estimates only `η_holdout` for held-out participant
   - Computes log-posterior explicitly

**LOOCV Iteration (for each i = 1 to 2,635):**
1. Fit main model on N-1 participants (excluding i)
2. Extract item parameters: `τ`, `β_1`, `δ`
3. Fit holdout model for participant i (fixed item params)
4. Extract `log_posterior_i`
5. Calculate **avg_logpost_i = log_posterior_i / n_items_i**

**Why per-item averaging?** Log-likelihood scales with number of items. Dividing by n_items creates a fair comparison across participants with different response patterns.

### 2.3 Warm-Start Optimization

**Challenge:** Each N-1 fit takes ~48 seconds (cold start) → 35.5 hours for full LOOCV.

**Solution:** Centered eta warm-start
1. Fit full N=2,635 model once → extract all parameters
2. For each iteration i:
   - Create `η_init = η[-i] - mean(η[-i])` ← satisfies sum-to-zero constraint
   - Initialize N-1 fit with `{η_init, τ, β_1, δ}`
   - **Result:** 1.2 seconds per iteration (39x speedup!)

**Final Runtime:** 6.6 minutes (16 cores, 2,635 iterations, 99.9% convergence)

---

## 3. LOOCV Results: Authentic Distribution

### 3.1 Convergence

| Metric | N | Rate |
|--------|---|------|
| Main model converged | 2,635 / 2,635 | 100.0% |
| Holdout model converged | 2,633 / 2,635 | 99.9% |
| **Both converged** | **2,633** | **99.9%** |

**Optimizer failures:** 2 participants (0.1%) failed due to "failed to create optimizer" errors (handled gracefully).

### 3.2 Distribution Parameters

**avg_logpost (authentic LOOCV):**
- **Mean:** -0.9195
- **SD:** 0.3220
- **Range:** [-3.1120, -0.1388]
- **95% range:** [-1.5505, -0.2884]

**Standardized lz:**
```
lz_i = (avg_logpost_i - mean_authentic) / sd_authentic
```
- By definition: mean = 0, SD = 1 for authentic

**Item Response Summary:**
- Mean items answered: ~33 items per participant
- Median items: 33 items
- Range: 5 to 90+ items

---

## 4. Inauthentic Participant Analysis

### 4.1 Coverage

Of 196 inauthentic participants with sufficient data:

| Metric | N | % |
|--------|---|---|
| Below authentic range (avg_logpost < -3.11) | 0 | 0.0% |
| **Within authentic range** | **196** | **100.0%** |
| Above authentic range (avg_logpost > -0.14) | 0 | 0.0% |

**Critical Finding:** All 196 inauthentic participants fall **completely within** the authentic LOOCV range.

### 4.2 Percentile Distribution

While there's 100% overlap, inauthentic participants show a shift toward poorer fit:

| Percentile Range | N | % | Expected % |
|------------------|---|---|------------|
| < 5th percentile | 36 | 18.4% | 5.0% |
| 5th-25th | 63 | 32.1% | 20.0% |
| 25th-75th | 69 | 35.2% | 50.0% |
| 75th-95th | 24 | 12.2% | 20.0% |
| > 95th percentile | 4 | 2.0% | 5.0% |

**Summary:** 50.5% of inauthentic fall in the bottom quartile (vs 25% expected), but there's substantial overlap throughout the distribution.

### 4.3 Inauthentic lz Distribution

**lz (inauthentic):**
- **Mean:** -0.5731 (worse fit than authentic)
- **SD:** 1.1612 (wider spread than authentic SD=1.0)
- **Range:** [-4.3977, 2.0923]

**Interpretation:**
- **Low lz (<0):** Potentially random/disengaged responses
- **High lz (>0):** Potentially gaming/pattern responses
- **Both extremes present:** Suggests heterogeneous inauthenticity patterns

---

## 5. ROC Analysis: Binary Classification Attempt

### 5.1 Two-ROC Approach

Given the bidirectional nature of inauthenticity (poor fit vs gaming), we conducted **two separate ROC analyses**:

**ROC 1: Poor Fit Detection (lz < 0)**
- Detects inauthentic with **poor model fit** (random responses)
- Classification: IF lz < threshold_low → INAUTHENTIC

**ROC 2: Gaming Detection (lz > 0)**
- Detects inauthentic with **suspiciously good fit** (gaming patterns)
- Classification: IF lz > threshold_high → INAUTHENTIC

### 5.2 ROC 1 Results: Poor Fit Detection

| Metric | Value |
|--------|-------|
| Data | 1,235 authentic + 132 inauthentic (lz < 0) |
| **AUC** | **0.3416** |
| Optimal threshold | lz < -3.3067 |
| Sensitivity | 0.9924 (99.2%) |
| Specificity | 0.0146 (1.5%) |
| Youden's J | 0.0070 |

**Interpretation:** AUC < 0.5 indicates **reversed discrimination** - the classifier performs worse than chance. The optimal threshold is so extreme (-3.31) that it only captures 1 out of 132 inauthentic participants.

### 5.3 ROC 2 Results: Gaming Detection

| Metric | Value |
|--------|-------|
| Data | 1,398 authentic + 64 inauthentic (lz > 0) |
| **AUC** | **0.4953** |
| Optimal threshold | lz > 1.1650 |
| Sensitivity | 0.8594 (85.9%) |
| Specificity | 0.2175 (21.8%) |
| Youden's J | 0.0768 |

**Interpretation:** AUC ≈ 0.5 indicates **no discrimination** - performance is equivalent to random guessing.

### 5.4 Combined Classification Performance

**Classification Rule:**
```
IF lz < -3.3067 OR lz > 1.1650 → INAUTHENTIC
```

| Metric | Value |
|--------|-------|
| **Sensitivity (TPR)** | **5.1%** (10/196 detected) |
| **Specificity (TNR)** | **87.8%** (2,311/2,633 correct) |
| **PPV (Precision)** | **3.0%** (10/332 flagged) |
| NPV | 92.6% (2,311/2,497) |
| Accuracy | 82.0% |

**Detection Breakdown:**
- Poor fit detections: 1 participant
- Gaming detections: 9 participants

### 5.5 Conclusion: Binary Classification Not Recommended

**Why ROC failed:**
1. **100% coverage overlap:** All inauthentic fall within authentic range
2. **Wide authentic variation:** LOOCV captures natural response heterogeneity
3. **No separation:** Cannot find threshold that distinguishes groups
4. **Poor sensitivity:** Only 5.1% of inauthentic detected
5. **High false positive rate:** 322 authentic misclassified

**Recommendation:** Abandon binary classification in favor of **continuous weighting**.

---

## 6. ATT Weighting Approach

### 6.1 Rationale

Since binary classification fails, we adopt a **continuous authenticity weighting** approach using **inverse propensity treatment weighting (IPTW)**.

**Framework:**
- **"Treated" group:** Authentic participants (N=2,633)
- **"Control" group:** Inauthentic participants (N=196)
- **Goal:** Estimate Average Treatment effect on the Treated (ATT)

**Interpretation:**
- Inauthentic participants whose avg_logpost values are **common in authentic distribution** receive **higher weights** (authentic-like)
- Inauthentic participants whose avg_logpost values are **rare in authentic distribution** receive **lower weights** (less authentic-like)

### 6.2 Quintile-Based Stratification

Instead of logistic regression, we use **quintile stratification** for simplicity and robustness.

**Step 1:** Divide authentic LOOCV distribution into **quintiles** based on avg_logpost:

| Quintile | avg_logpost Range | N Authentic | N Inauthentic | % Inauthentic |
|----------|-------------------|-------------|---------------|---------------|
| Q1 (lowest) | [-3.11, -1.15] | 527 | 93 | 15.0% |
| Q2 | [-1.15, -0.97] | 526 | 32 | 5.7% |
| Q3 | [-0.97, -0.83] | 527 | 20 | 3.7% |
| Q4 | [-0.83, -0.64] | 526 | 27 | 4.9% |
| Q5 (highest) | [-0.64, -0.14] | 527 | 24 | 4.4% |

**Observation:** 93/196 (47.4%) of inauthentic fall in Q1 (poorest fit quintile).

**Step 2:** Calculate propensity within each quintile:
```
propensity_q = n_authentic_q / (n_authentic_q + n_inauthentic_q)
```

| Quintile | Propensity P(authentic | quintile) |
|----------|-----------------------------------|
| Q1 | 0.8500 |
| Q2 | 0.9427 |
| Q3 | 0.9634 |
| Q4 | 0.9512 |
| Q5 | 0.9564 |

**Step 3:** Assign ATT weights to inauthentic participants:
```
ATT_weight = propensity / (1 - propensity)
```

### 6.3 Weight Distribution

**Overall Weight Summary (N=196 inauthentic):**
- **Sum of weights:** 2,633.00 (= N_authentic, by design)
- **Mean:** 13.43
- **SD:** 7.83
- **Range:** [5.67, 26.35]

**Weights by Quintile:**

| Quintile | N | Mean Weight | Range |
|----------|---|-------------|-------|
| Q1 | 93 | 5.67 | 5.67 - 5.67 |
| Q2 | 32 | 16.44 | 16.44 - 16.44 |
| Q3 | 20 | 26.35 | 26.35 - 26.35 |
| Q4 | 27 | 19.48 | 19.48 - 19.48 |
| Q5 | 24 | 21.96 | 21.96 - 21.96 |

**Interpretation:**
- **Q1 participants** (poorest fit): Weight = 5.67 → **down-weighted by 58%** relative to mean
- **Q3 participants** (most authentic-like): Weight = 26.35 → **up-weighted by 96%** relative to mean
- Weights are **constant within quintiles** (stratification approach)

### 6.4 Mathematical Property: Sum of Weights

**Property:** For ATT weighting, the sum of control (inauthentic) weights equals the number of treated (authentic).

**Proof:**
```
Sum of weights = Σ [p_q / (1 - p_q)] for all inauthentic participants
                = Σ [n_auth_q / n_inauth_q] across quintiles
                = Σ n_auth_q
                = N_authentic = 2,633
```

This means the **196 weighted inauthentic participants represent 2,633 "authentic-equivalent" observations** - matching the authentic sample size.

---

## 7. Usage Recommendations

### 7.1 When to Use Weights

**Apply ATT weights (`att_weight`) in all analyses involving inauthentic participants:**

**Example 1: Descriptive Statistics**
```r
# Weighted mean for inauthentic group
weighted.mean(x = inauthentic$outcome, w = inauthentic$att_weight)
```

**Example 2: Regression Analysis**
```r
# Include weights in model
lm(outcome ~ predictor, data = inauthentic, weights = att_weight)
```

**Example 3: Survey Weighting**
```r
# Combine with survey design weights
inauthentic$final_weight <- inauthentic$att_weight * inauthentic$survey_weight
```

### 7.2 Interpretation

- **High weight (Q3-Q5):** Response pattern resembles authentic participants → retain at higher weight
- **Low weight (Q1-Q2):** Response pattern differs from authentic → down-weight in analyses
- **Not binary exclusion:** All 196 participants remain in dataset but contribute differentially

### 7.3 Sensitivity Analysis

**Recommended:**
1. **Compare weighted vs unweighted estimates** to assess impact
2. **Exclude Q1 entirely** as robustness check (93 participants with weight 5.67)
3. **Report both** weighted and unweighted results in publications

---

## 8. Limitations and Caveats

### 8.1 Data Limitations

1. **Sample size:** Only 196/872 inauthentic have sufficient data (5+ items)
2. **Item coverage:** Some participants have sparse responses (5-10 items vs 230 possible)
3. **Age distribution:** Inauthentic may differ on unmeasured covariates beyond avg_logpost

### 8.2 Model Limitations

1. **Single covariate:** Propensity based only on avg_logpost (no demographics, response time, etc.)
2. **Quintile stratification:** Assumes homogeneity within quintiles
3. **Complete overlap:** Cannot estimate causal effects with 100% coverage
4. **Assumes LOOCV captures all authentic variation:** May underestimate if authentic has unknown subgroups

### 8.3 Methodological Considerations

1. **Not a validity measure:** Weights reflect similarity to authentic distribution, not response quality
2. **Gaming undetected:** If gaming mimics authentic patterns, high weights assigned
3. **Circular logic:** Using item responses to weight item response analyses

**Bottom line:** Weights are a **pragmatic solution** for handling known-inauthentic data, not a gold standard.

---

## 9. Files and Reproducibility

### 9.1 Stan Models

| File | Description |
|------|-------------|
| `models/authenticity_glmm.stan` | Main model (230 items, cumulative logit, N-1 fit) |
| `models/authenticity_holdout.stan` | Holdout model (fixed item params, estimate η_i) |

### 9.2 R Scripts

| Script | Purpose | Runtime |
|--------|---------|---------|
| `01_prepare_data.R` | Extract 230 items, create Stan data | ~30 sec |
| `02_fit_full_model.R` | Fit full N=2,635 model (validation) | ~50 sec |
| `03_run_loocv.R` | **Main LOOCV pipeline** (16 cores) | ~6.6 min |
| `04_compute_inauthentic_logpost.R` | Estimate log-posterior for 196 inauthentic | ~2 min |
| `05_roc_analysis.R` | ROC curves (poor fit + gaming) | ~10 sec |
| `06_compute_authenticity_weights.R` | **ATT weighting pipeline** | ~5 sec |

### 9.3 Results Files

| File | Contents |
|------|----------|
| `results/loocv_authentic_results.rds` | LOOCV results (2,633 × 8 data frame) |
| `results/loocv_distribution_params.rds` | Mean/SD for standardization |
| `results/inauthentic_logpost_results.rds` | Inauthentic log-posterior (196 × 7) |
| `results/inauthentic_weighted.rds` | **Inauthentic with ATT weights** (196 × 9) |
| `results/authenticity_weights_summary.rds` | Weight distribution summary |
| `results/quintile_stratification.rds` | Quintile counts and propensities |
| `results/roc_analysis_results.rds` | ROC curves and metrics |

### 9.4 Key Variables

**In `loocv_authentic_results.rds`:**
- `pid`: Participant ID
- `log_posterior`: Raw log-posterior
- `avg_logpost`: log_posterior / n_items
- `lz`: Standardized score
- `n_items`: Number of items answered
- `converged_main`, `converged_holdout`: Convergence flags

**In `inauthentic_weighted.rds`:**
- All of the above, plus:
- `quintile`: Assigned quintile (1-5)
- `propensity`: P(authentic | quintile)
- **`att_weight`**: ATT weight for analyses

---

## 10. Conclusion

**Summary:**
- LOOCV successfully builds robust out-of-sample distribution (2,633 participants, 99.9% convergence)
- Binary classification fails due to 100% distributional overlap (AUC 0.34-0.50)
- **ATT weighting recommended** as pragmatic solution
- Weights range 5.67 to 26.35, appropriately down-weight suspect responses
- Use `att_weight` variable in all analyses involving the 196 inauthentic participants

**Next Steps:**
1. Apply weights in substantive analyses
2. Conduct sensitivity analyses (weighted vs unweighted)
3. Consider excluding Q1 entirely (93 participants with weight 5.67) as robustness check
4. Document weighting in publications

**Contact:** For questions about methodology, contact the Kidsights data team.

---

**Document Version:** 1.0
**Last Updated:** November 2025
**Authors:** Kidsights Data Platform Team

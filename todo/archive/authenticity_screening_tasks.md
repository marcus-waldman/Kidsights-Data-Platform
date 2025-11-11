# Authenticity Screening via Stan GLMM - Task List

**Created:** 2025-11-07
**Last Updated:** 2025-11-07
**Status:** Phase 2 Complete (using 172 validated items) - BLOCKED on GitHub Issue #4

**Goal:** Build Stan-based GLMM to screen for false negatives in authenticity validation using LOOCV

---

## ⚠️ CURRENT BLOCKER

**GitHub Issue #4:** 104 items with lex_equate lack response_sets validation
- **Impact:** Currently using only 172/276 items (62%)
- **Next Step:** Investigate and resolve validation for 104 derived variables
- **Then:** Re-run full pipeline with all 276 items

---

## Phase 1: Data Preparation ✅ COMPLETE

### 1.1 Extract & Map Items from Codebook ✅
- [x] Load codebook.json with simplifyVector=FALSE
- [x] Extract all items with lexicons.equate defined (found: 276 items)
- [x] Create mapping: NE25 names (c020, c023...) → lex_equate names (AA4, AA5...)
- [x] Identify item types: binary vs polytomous
- [x] Calculate K[j] (number of categories per item) from response_sets
- [x] **Filter to 172 validated items** (168 binary + 4 polytomous)
- [x] Save item metadata to: `data/temp/item_metadata.rds`

**Result:**
- 276 total items extracted
- 172 validated items (with response_sets)
- 104 items excluded (no response_sets - GitHub Issue #4)

### 1.2 Load Training & Test Data ✅
- [x] Query 2,635 authentic + eligible participants from ne25_transformed
- [x] Query 872 inauthentic + eligible participants from ne25_transformed
- [x] Extract: pid, age_years, all item columns (using lowercase NE25 names)
- [x] Validate: Check for missing values, age ranges, item response distributions

**Result:**
- Training set: 2,635 authentic participants
- Test set: 872 inauthentic participants
- Age range: 0.0 - 6.0 years

### 1.3 Vectorize to Long Format ✅
- [x] Create yvec[m]: Response values (0-5, already 0-indexed)
- [x] Create ivec[m]: Person indices (1 to N)
- [x] Create jvec[m]: Item indices (1 to J)
- [x] Create age[i]: Age in years for each person
- [x] Create K[j]: Number of categories for each item
- [x] Validate: M equals sum of non-missing responses
- [x] Save Stan data list to: `data/temp/stan_data_authentic.rds`
- [x] Save inauthentic data: `data/temp/stan_data_inauthentic.rds`

**Result:**
- Training: N=2,635, J=172, M=46,402 observations (17.6 items/person)
- Test: N=872, J=172, M=4,769 observations (5.5 items/person)
- Metadata stored as attributes (pid, item_names)

### 1.4 Phase 1 Completion ✅
- [x] Verify all data files created successfully
- [x] Print summary statistics (N, J, M, item types)
- [x] **Load Phase 2 tasks into Claude todo list**

---

## Phase 2: Stan Model Development ✅ COMPLETE

### 2.1 Write Stan Model File ✅
- [x] Create `models/authenticity_glmm.stan`
- [x] Define data block: M, N, J, yvec, ivec, jvec, age, K
- [x] **Simplified parameterization:** sum_to_zero_vector[N] eta (no sigma)
- [x] **Avoided infinities:** Simplified probability calculation for boundary cases
- [x] Implement model block: Cumulative logit probabilities with age slopes
- [x] Set priors: tau ~ normal(0,5), beta1 ~ normal(0,2), delta ~ student_t(3,0,1)[0,], eta ~ std_normal()
- [x] Add generated quantities: log_lik for each person (for lz calculation)
- [x] Add numerical safeguards: p = fmax(p, 1e-10) to prevent log(0)

**Key Design Decisions:**
- **Sum-to-zero constraint** on eta instead of hierarchical N(0,σ²)
- **No sigma parameter** - person variation measured empirically as sd(eta)
- **Simplified thresholds:** Avoided negative_infinity() and positive_infinity()
- **Equal spacing:** Single delta parameter for all items

### 2.2 Create R Wrapper Functions ✅
- [x] Write `R/authenticity/stan_interface.R`: fit_authenticity_glmm() wrapper
- [x] Write `R/authenticity/diagnostics.R`: calculate_lz(), extract_person_effects()
- [x] Test Stan model compiles without errors
- [x] Updated for sum-to-zero parameterization (no sigma)
- [x] Fixed init values to enforce sum-to-zero constraint

**Note:** Skipped data_prep.R (vectorization done in 01_prepare_data.R)

### 2.3 Validate Model on Full Data ✅
- [x] Fit Stan model on all 2,635 authentic participants (L-BFGS)
- [x] Check convergence diagnostics: **SUCCESS** (return code 0)
- [x] Examine parameter estimates: All reasonable ranges
- [x] Save full model results: `results/full_model_fit.rds`
- [x] Save parameters: `results/full_model_params.rds`
- [x] Save log-likelihoods: `results/full_model_log_lik.rds`

**Results (172 items, 46,402 observations):**
- **Convergence:** Return code 0, gradient < tolerance in 1,950 iterations
- **Speed:** 13.5 seconds total
- **Log probability:** -40,188 → -27,394 (improved 12,794 units)
- **Delta (threshold spacing):** 1.472
- **Eta SD (person variation):** 0.804
- **Tau range:** [-5.09, 8.10]
- **Beta1 range:** [-5.58, 0.32]
- **Eta range:** [-5.05, 7.53]

### 2.4 Phase 2 Completion ✅
- [x] Verify Stan model runs successfully on full data
- [x] **Load Phase 3 tasks into Claude todo list**
- [ ] Document model specification in `docs/authenticity_screening_model.md` (deferred)

---

## 🚧 NEXT IMMEDIATE STEPS (Before Phase 3)

### 1. Resolve GitHub Issue #4 (PRIORITY)
- [ ] Investigate 104 items with lex_equate but no response_sets
- [ ] Determine if these are derived variables that should be excluded
- [ ] OR add response_sets definitions if they should be included
- [ ] Decision: Include or permanently exclude these items?

### 2. Re-run with Full Item Set (if resolved)
- [ ] Update 01_prepare_data.R to include resolved items
- [ ] Regenerate stan_data with full item set
- [ ] Re-fit full model with complete data

### 3. Convert to rstan Backend (PRIORITY for LOOCV)
- [ ] Rewrite `R/authenticity/stan_interface.R` to use rstan instead of cmdstanr
- [ ] **Reason:** rstan's optimizing() is faster for parallel LOOCV
- [ ] Test compilation and single fit
- [ ] Verify warm starts work with rstan

---

## Phase 3: LOOCV Implementation (NOT STARTED)

**Current Status:** BLOCKED until Issue #4 resolved and rstan backend implemented

### 3.1 Setup LOOCV Infrastructure
- [ ] Write `scripts/authenticity_screening/03_run_loocv.R`
- [ ] Convert to rstan backend for parallel processing
- [ ] Extract parameter estimates from full model as starting values
- [ ] Create parallel backend with detectCores()-1 workers
- [ ] Write function: fit_loocv_fold(i, data, start_params)
- [ ] Test LOOCV on 10 participants to estimate per-fold timing

### 3.2 Run Full LOOCV (2,635 folds)
- [ ] Launch parallel LOOCV loop with progress tracking
- [ ] For each fold i: Fit on N-1, predict on held-out person i
- [ ] Calculate out-of-sample log-likelihood for person i
- [ ] Standardize: lz_i = (ℓ_i - E[ℓ_i]) / SD[ℓ_i]
- [ ] Extract person effect: eta_i
- [ ] Save incremental results every 100 folds (in case of crashes)
- [ ] **Expected time: ~1.8 hours with 8 cores**

### 3.3 Characterize LOOCV Null Distribution
- [ ] Load all LOOCV results into data frame
- [ ] Calculate summary statistics: mean, SD, quantiles of lz
- [ ] Calculate summary statistics for eta
- [ ] Create joint distribution plots: (lz, eta) scatter with density contours
- [ ] Fit bivariate normal to (lz, eta) for 95% ellipse
- [ ] Save results: `data/loocv_authentic_distribution.rds`
- [ ] Save plots: `results/plots/loocv_distributions.png`

### 3.4 Phase 3 Completion
- [ ] Verify all 2,635 LOOCV folds completed successfully
- [ ] Create summary report: `results/loocv_completion_summary.txt`
- [ ] **Load Phase 4 tasks into Claude todo list**

---

## Phase 4: Screen Inauthentic Participants (NOT STARTED)

### 4.1 Predict for Inauthentic Participants
- [ ] Load full model (trained on all 2,635 authentic)
- [ ] Prepare Stan data for 872 inauthentic participants
- [ ] For each inauthentic participant:
  - Calculate log-likelihood using full model parameters
  - Standardize to get lz
  - Extract person effect eta
- [ ] Save results: `data/inauthentic_predictions.rds`

### 4.2 Compare Distributions
- [ ] Create lz histogram: Authentic (LOOCV) vs Inauthentic overlay
- [ ] Create eta histogram: Authentic vs Inauthentic overlay
- [ ] Create joint scatter plot: (lz, eta) with authentic 95% ellipse
- [ ] Calculate percentile ranks: Where do inauthentic fall in authentic distribution?
- [ ] Create Q-Q plots: Compare inauthentic to authentic null distribution
- [ ] Save all plots: `results/plots/distribution_comparisons.png`

### 4.3 Flag Potential False Negatives
- [ ] Define decision rule: lz > 5th percentile AND |eta| < 2 SD
- [ ] Apply rule to all 872 inauthentic participants
- [ ] Calculate percentile ranks for each inauthentic participant
- [ ] Create ranked list: Sort by likelihood of being false negative
- [ ] Generate flagged participants list: pid, lz, eta, percentile_rank, flag_recovery
- [ ] Save: `data/inauthentic_screening_results.csv`

### 4.4 Phase 4 Completion
- [ ] Verify all 872 inauthentic participants screened
- [ ] Count how many flagged for potential recovery
- [ ] Create summary table with key metrics
- [ ] **Load Phase 5 tasks into Claude todo list**

---

## Phase 5: Outputs & Documentation (NOT STARTED)

### 5.1 Create Database Tables
- [ ] Create table: `ne25_authenticity_screening`
- [ ] Schema: pid, authentic_flag (original), lz, eta, percentile_rank, flag_recovery
- [ ] Insert LOOCV results for authentic participants
- [ ] Insert screening results for inauthentic participants
- [ ] Create indexes on: pid, authentic_flag, flag_recovery

### 5.2 Generate Summary Report
- [ ] Create `reports/authenticity_screening_report.Rmd`
- [ ] Section 1: Model specification and methodology
- [ ] Section 2: LOOCV results and null distribution
- [ ] Section 3: Distribution comparison plots
- [ ] Section 4: Flagged participants summary table
- [ ] Section 5: Recommendations for manual review
- [ ] Render to HTML: `reports/authenticity_screening_report.html`

### 5.3 Create Output Files
- [ ] Export: `data/loocv_results.csv` (pid, age_years, lz_oos, eta_oos, n_items)
- [ ] Export: `data/inauthentic_screening.csv` (pid, lz, eta, percentile_rank, flag)
- [ ] Export: `data/flagged_for_review.csv` (filtered to flag_recovery=TRUE)
- [ ] Copy key plots to: `results/plots/final/`

### 5.4 Documentation
- [ ] Write: `docs/authenticity_screening_model.md` (model specification)
- [ ] Write: `docs/authenticity_screening_usage.md` (how to use results)
- [ ] Update: `docs/PIPELINE_OVERVIEW.md` (add authenticity screening section)
- [ ] Create: `scripts/authenticity_screening/README.md` (script documentation)

### 5.5 Phase 5 Completion
- [ ] Verify all outputs created successfully
- [ ] Review flagged participants list for data quality
- [ ] Archive intermediate files to: `data/temp/archive/`
- [ ] **Project complete - clear Claude todo list**

---

## Summary Statistics (Current - 172 Items)

- **Training set:** 2,635 authentic + eligible participants
- **Test set:** 872 inauthentic + eligible participants
- **Items used:** 172 validated items (168 binary, 4 polytomous)
- **Items excluded:** 104 items (awaiting GitHub Issue #4 resolution)
- **Training observations:** 46,402 (17.6 items/person)
- **Test observations:** 4,769 (5.5 items/person)
- **Model fit time:** 13.5 seconds (L-BFGS, 1,950 iterations)
- **LOOCV folds:** 2,635 (not yet started)
- **Estimated LOOCV runtime:** ~1.8 hours with 8 cores (rstan backend)

---

## Files Created

```
✅ Phase 1 & 2 Complete:

scripts/authenticity_screening/
├── 01_prepare_data.R          # Data extraction & vectorization
├── 02_fit_full_model.R         # Full model fitting (cmdstanr)
└── README.md                   # (not yet created)

models/
└── authenticity_glmm.stan      # Sum-to-zero GLMM model

R/authenticity/
├── stan_interface.R            # cmdstanr wrapper (needs rstan conversion)
└── diagnostics.R               # lz calculation functions

data/temp/
├── item_metadata.rds           # 172 validated items
├── stan_data_authentic.rds     # Training data (N=2635, J=172, M=46402)
└── stan_data_inauthentic.rds   # Test data (N=872, J=172, M=4769)

results/
├── full_model_fit.rds          # cmdstan_optimize object
├── full_model_params.rds       # tau, beta1, delta, eta
├── full_model_log_lik.rds      # Person-level log-likelihoods
└── phase1_completion_summary.txt
```

---

## Technical Notes

### Model Specification (Sum-to-Zero Parameterization)

**Data:**
- M = 46,402 observations
- N = 2,635 persons
- J = 172 items

**Parameters:**
- tau[J]: First threshold for each item (172 parameters)
- beta1[J]: Age slope for each item (172 parameters)
- delta: Threshold spacing (1 parameter, constrained > 0)
- eta[N]: Person random effects (2,635 parameters, sum-to-zero constraint)

**Model:**
```
logit(P(y_ij = k)) = tau_left + beta1[j]*age[i] + eta[i]
                   where tau_left, tau_right depend on k, tau[j], delta

Priors:
  tau ~ N(0, 5)
  beta1 ~ N(0, 2)
  delta ~ student_t(3, 0, 1)[0, Inf]
  eta ~ N(0, 1) subject to sum(eta) = 0
```

**Key Features:**
- No sigma parameter (person variation = sd(eta))
- Equal-spaced thresholds (single delta)
- Simplified boundary handling (no infinities)
- Numerical stability: p >= 1e-10

### Why rstan for LOOCV?

cmdstanr is great for single fits but rstan's `optimizing()` is faster for:
1. **Parallel processing:** Each core can independently call optimizing()
2. **Memory efficiency:** Lighter weight than spawning cmdstan processes
3. **Warm starts:** Easier to pass init values in parallel loops
4. **No I/O overhead:** No external process communication

**Expected speedup:** 2-3x faster LOOCV with rstan vs cmdstanr

# Authenticity Screening: LOOCV Tasks

**Status:** In Progress - Task 1
**Date:** November 8, 2025
**Context:** Phase 3 complete - 230-item model fitted successfully

---

## Background

After completing Phase 3 (codebook response_sets fix and 230-item model integration), we're ready to implement Leave-One-Out Cross-Validation (LOOCV) to build an out-of-sample authenticity classification system.

**Key Statistical Approach:**
- **Metric:** Average log-posterior per item (log_posterior / n_items)
- **LOOCV Distribution:** Build distribution of per-item averages from 2,635 authentic participants
- **Standardization:** lz = (avg_logpost - mean_avg_authentic) / sd_avg_authentic
- **Classification:** Compare inauthentic lz values to authentic LOOCV distribution

**Critical Finding:** Only 196 of 872 inauthentic participants (22.5%) have sufficient data (5+ item responses) for log-likelihood calculation.

---

## Task List

### Phase 1: Stan Model Development and Testing

**Task 1: Create Holdout Stan Model**
- [ ] Create `models/authenticity_holdout.stan` with specification:
  - **Data inputs:**
    - `tau[J]`, `beta1[J]`, `delta` (fitted item parameters from N-1 model, treated as FIXED/KNOWN)
    - `K[J]` (number of categories per item)
    - `y_holdout[M_holdout]` (held-out person's responses)
    - `j_holdout[M_holdout]` (which items they answered)
    - `M_holdout` (number of observations for held-out person)
  - **Parameters to estimate:**
    - `eta_holdout` ONLY (the held-out person's ability parameter)
  - **Prior:**
    - `eta_holdout ~ normal(0, 1)` (standard normal prior, matching main model)
  - **Model:**
    - Same cumulative logit structure as main model
    - Uses FIXED item parameters from N-1 fit
  - **Generated quantities:**
    - `log_lik_holdout[M_holdout]` (log-likelihood for each observation)
    - `total_log_lik` (sum of log-likelihoods)
- [ ] Add model documentation and comments

**Task 2: Test Stan Models Before Parallel Processing**
- [ ] **Test main model (`authenticity_glmm.stan`):**
  - Fit on first 100 authentic participants
  - Check convergence diagnostics
  - Verify parameter estimates are reasonable
  - Confirm log-likelihood extraction works
- [ ] **Test holdout model (`authenticity_holdout.stan`):**
  - Use fitted parameters from 100-person model
  - Hold out participant 1
  - Fit holdout model to estimate eta_1
  - Extract log posterior
  - Verify: log_posterior = sum(log_lik_holdout) + log_prior(eta_1)
  - Calculate avg_logpost = log_posterior / n_items_1
- [ ] **Test complete LOOCV iteration:**
  - Run single LOOCV iteration (e.g., i=1)
  - Fit N-1 model (exclude participant 1)
  - Extract item parameters (tau, beta1, delta)
  - Fit holdout model for participant 1
  - Extract avg_logpost
  - Verify entire workflow end-to-end
- [ ] **Test with 10 participants:**
  - Run LOOCV on first 10 authentic participants
  - Check all converge successfully
  - Verify avg_logpost values are sensible
  - Confirm no errors in workflow

**Task 3: Create LOOCV Script Infrastructure**
- [ ] Create `scripts/authenticity_screening/03_run_loocv.R`
- [ ] Set up `future` backend for parallel processing:
  - `library(future)`
  - `library(furrr)`
  - `plan(multisession, workers = 16)`
- [ ] Add `progressr` progress bar:
  - `library(progressr)`
  - `with_progress()` wrapper for iterations
  - Real-time updates on completion
- [ ] Create helper functions:
  - `fit_loo_model(i, stan_data)` - Fit main model excluding participant i
  - `fit_holdout_model(i, item_params, y_holdout, j_holdout)` - Fit holdout model
  - `compute_avg_logpost(log_posterior, n_items)` - Calculate per-item average
- [ ] Add intermediate saving (every 100 iterations)
- [ ] Add resume functionality (load previous progress if exists)
- [ ] Add error handling for failed iterations

---

### Phase 2: LOOCV Execution

**Task 4: Implement LOOCV Iteration Function**
```r
run_loocv_iteration <- function(i, stan_data_full, main_model, holdout_model) {
  # 1. Create leave-one-out data (exclude participant i)
  # 2. Fit main Stan model on N-1 participants using cmdstanr::optimize()
  # 3. Extract fitted item parameters: tau, beta1, delta
  # 4. Extract held-out person's data: y_holdout, j_holdout
  # 5. Fit holdout Stan model (takes item params as DATA, estimates only eta_i)
  # 6. Extract log posterior from holdout fit
  # 7. Calculate average: avg_logpost = log_posterior / n_items_i
  # 8. Return: list(i = i, pid = pid_i, avg_logpost = avg_logpost, n_items = n_items_i,
  #                 converged_main = TRUE/FALSE, converged_holdout = TRUE/FALSE)
}
```
- [ ] Implement data exclusion logic (remove participant i from ivec/yvec)
- [ ] Fit main model using `cmdstanr::optimize()`
- [ ] Extract item parameters and convert to holdout model data format
- [ ] Fit holdout model using `cmdstanr::optimize()`
- [ ] Extract log posterior: `log_posterior = sum(log_lik_holdout) + log_prior`
- [ ] Calculate per-item average: `avg_logpost / n_items`
- [ ] Add convergence checking for BOTH models

**Task 5: Run Full LOOCV on 2,635 Authentic Participants**
- [ ] Set up parallel execution with `furrr::future_map()`:
  ```r
  library(future)
  library(furrr)
  library(progressr)

  plan(multisession, workers = 16)

  with_progress({
    p <- progressr::progressor(steps = 2635)
    loocv_results <- furrr::future_map(
      1:2635,
      ~{
        p()  # Update progress bar
        run_loocv_iteration(.x, stan_data, main_model, holdout_model)
      },
      .options = furrr_options(seed = TRUE)
    )
  })
  ```
- [ ] Run LOOCV iterations in parallel (estimate 10-15 hours with 16 cores)
- [ ] Save intermediate results every 100 iterations to `results/loocv_progress/`
- [ ] Monitor convergence failures (both main and holdout models)
- [ ] **CRITICAL:** Save BOTH raw log_posterior AND avg_logpost for each participant:
  - `log_posterior` (raw value) - enables re-analysis with different methods
  - `avg_logpost = log_posterior / n_items` (standardized per-item)
  - `eta_est` (estimated ability parameter from holdout model)
  - `n_items` (number of items answered)
  - `converged_main`, `converged_holdout` (convergence flags)
- [ ] Collect results: data frame with (i, pid, log_posterior, avg_logpost, n_items, eta_est, converged_main, converged_holdout)

**Task 6: Compute Log-Posterior for 872 Inauthentic Participants**
- [ ] Use full model parameters (fitted on all 2,635 authentic)
- [ ] For each inauthentic participant:
  - Extract their responses (y_i, j_i, n_items_i)
  - Fit holdout model (item params as data, estimate only eta_i)
  - Extract log posterior
  - Calculate avg_logpost = log_posterior / n_items_i
- [ ] Flag participants with < 5 items (insufficient data)
- [ ] Save results: (i, pid, avg_logpost, n_items, sufficient_data, converged)

---

### Phase 3: Standardization and Threshold Determination

**Task 7: Build Out-of-Sample Distribution and Standardize**
- [ ] Extract LOOCV average log-posteriors from 2,635 authentic participants
- [ ] Calculate distribution parameters:
  - mean_avg_authentic = mean(avg_logpost_authentic)
  - sd_avg_authentic = sd(avg_logpost_authentic)
- [ ] Standardize authentic LOOCV values:
  - lz_authentic_i = (avg_logpost_i - mean_avg_authentic) / sd_avg_authentic
- [ ] Standardize inauthentic values (using same mean/SD):
  - lz_inauthentic_i = (avg_logpost_i - mean_avg_authentic) / sd_avg_authentic
- [ ] Create combined dataset with (pid, avg_logpost, lz, authentic_flag, n_items)

**Task 8: Determine Optimal Threshold**
- [ ] Compute ROC curve across lz threshold values
- [ ] Calculate metrics at each threshold:
  - Sensitivity (true positive rate)
  - Specificity (true negative rate)
  - Youden's J statistic (sensitivity + specificity - 1)
- [ ] Identify optimal threshold (maximize Youden's J or other criterion)
- [ ] Report threshold in both lz and avg_logpost scales

---

### Phase 4: Evaluation and Visualization

**Task 9: Calculate Classification Metrics**
- [ ] At optimal threshold, compute:
  - Sensitivity (TPR): P(classified inauthentic | truly inauthentic)
  - Specificity (TNR): P(classified authentic | truly authentic)
  - Positive Predictive Value (PPV)
  - Negative Predictive Value (NPV)
  - Area Under ROC Curve (AUC)
  - F1 Score
- [ ] Create confusion matrix
- [ ] Report metrics with 95% confidence intervals (bootstrap if needed)
- [ ] **Important:** Note that metrics are based on 196 inauthentic (those with sufficient data), not full 872

**Task 10: Create Diagnostic Plots**
- [ ] Plot 1: Histogram of lz values (authentic vs inauthentic, overlaid)
- [ ] Plot 2: Density plot of avg_logpost (authentic LOOCV vs inauthentic)
- [ ] Plot 3: ROC curve with AUC annotation
- [ ] Plot 4: Threshold sensitivity analysis (sensitivity/specificity vs threshold)
- [ ] Plot 5: Scatterplot (n_items vs avg_logpost, colored by authentic status)
- [ ] Save all plots to `results/loocv_diagnostics/`

**Task 11: Document Results and Save Outputs**
- [ ] Create `results/loocv_summary.md` with:
  - LOOCV execution summary (convergence rate, runtime)
  - Distribution parameters (mean_avg_authentic, sd_avg_authentic)
  - Optimal threshold (lz and avg_logpost scales)
  - Classification metrics table
  - Interpretation and recommendations
- [ ] Save RDS files:
  - `results/loocv_authentic_results.rds` (2,635 LOOCV results)
  - `results/loocv_inauthentic_results.rds` (872 inauthentic results)
  - `results/loocv_distribution_params.rds` (mean/SD for standardization)
  - `results/loocv_classification_metrics.rds` (full metrics)
- [ ] Update main README with LOOCV completion status

---

## Stan Model Specifications

### Main Model: `models/authenticity_glmm.stan`
**Purpose:** Fit on N-1 authentic participants to estimate item parameters

**Parameters:**
- `eta[N-1]` - Person ability parameters (N-1 participants)
- `tau[J]` - Item difficulty parameters
- `beta1[J]` - Item discrimination parameters
- `delta` - Threshold spacing parameter

**Priors:**
- `eta ~ normal(0, 1)`
- `tau ~ normal(0, 5)`
- `beta1 ~ normal(0, 5)`
- `delta ~ lognormal(0, 1)`

**Output:** Fitted parameters to be passed to holdout model

---

### Holdout Model: `models/authenticity_holdout.stan`
**Purpose:** Estimate ability for held-out participant given FIXED item parameters

**Data (FIXED inputs, not parameters):**
- `tau[J]` - Item difficulties (from N-1 fit)
- `beta1[J]` - Item discriminations (from N-1 fit)
- `delta` - Threshold spacing (from N-1 fit)
- `K[J]` - Number of categories per item
- `y_holdout[M_holdout]` - Held-out person's responses
- `j_holdout[M_holdout]` - Which items they answered
- `M_holdout` - Number of observations

**Parameters (to estimate):**
- `eta_holdout` - Ability of held-out person ONLY

**Prior:**
- `eta_holdout ~ normal(0, 1)` (standard normal)

**Generated Quantities:**
- `log_lik_holdout[M_holdout]` - Log-likelihood for each observation
- `total_log_lik` - Sum of log-likelihoods

**Output:**
- Log posterior = `sum(log_lik_holdout) + log(dnorm(eta_holdout, 0, 1))`
- Average: `avg_logpost = log_posterior / M_holdout`

---

## Key Formulas

### Average Log-Posterior Per Item
```
avg_logpost_i = log_posterior_i / n_items_i

Where:
  log_posterior_i = Σ log P(y_ij | θ, η_i) + log P(η_i)
  y_ij = response of person i to item j
  n_items_i = number of items answered by person i
  θ = item parameters (tau, beta1, delta) - FIXED from N-1 fit
  η_i = person ability parameter - ESTIMATED for held-out person
  log P(η_i) = log(dnorm(η_i, 0, 1)) = -0.5 * η_i^2 - 0.5 * log(2π)
```

### Standardized Log-Posterior (lz)
```
lz_i = (avg_logpost_i - mean_avg_authentic) / sd_avg_authentic

Where:
  mean_avg_authentic = mean of LOOCV avg_logpost from 2,635 authentic
  sd_avg_authentic = SD of LOOCV avg_logpost from 2,635 authentic
```

### Classification Rule
```
If lz_i < threshold:
  Classify as INAUTHENTIC
Else:
  Classify as AUTHENTIC
```

---

## Important Notes

1. **Two-Model Approach:**
   - **Main model** fits on N-1 participants → extracts item parameters
   - **Holdout model** takes item parameters as DATA → estimates only eta_i
   - This is more efficient and statistically principled than grid search

2. **Data Limitation:** Only 196/872 inauthentic participants have 5+ item responses
   - 468 have 0 responses (53.7%)
   - 207 have exactly 3 responses (23.7%)
   - Classification metrics will be based on the 196 with sufficient data

3. **Per-Item Averaging is Critical:**
   - Raw log-posteriors scale with number of items
   - Must use avg_logpost = log_posterior / n_items for fair comparison
   - LOOCV distribution is built on these averages

4. **Computational Resources:**
   - 2,635 LOOCV iterations × ~60 seconds each ≈ 10-15 hours with 16 cores
   - Using `future` + `furrr` for parallel processing
   - `progressr` for real-time progress updates
   - Intermediate results saved every 100 iterations

5. **Testing Before Scaling:**
   - MUST test both Stan models on small subset (10 participants) first
   - Verify convergence, parameter extraction, and log-posterior calculation
   - Only scale to full 2,635 after successful testing

6. **LOOCV vs In-Sample:**
   - LOOCV provides unbiased out-of-sample estimates
   - Avoids overfitting (model wasn't fitted on held-out participant)
   - Essential for valid authenticity classification

---

**Status:** Task 1 in progress
**Next Step:** Create `models/authenticity_holdout.stan` with proper specification

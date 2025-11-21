# Cross-Validation Workflow for σ_sum_w Hyperparameter Tuning

**Status:** Development | **Last Updated:** November 2025

This directory contains a complete 3-phase cross-validation pipeline for selecting the optimal `σ_sum_w` hyperparameter in the skewness-penalized authenticity screening model.

---

## Overview

**Purpose:** Tune the `σ_sum_w` hyperparameter that controls the strength of the sum prior constraint in the authenticity screening model.

**Model:** `authenticity_glmm_beta_sumprior_stable.stan` (logit-scale parameterization with mixture normal prior)

**Fixed Hyperparameter:** λ_skew = 1.0 (empirically validated)

**Tuning Range:** σ_sum_w ∈ [0.5, 2.0] via logarithmic grid: `2^(seq(-1, 1, by=0.25))` = 9 values

**Cross-Validation:** 16-fold CV with Gauss-Hermite quadrature for holdout evaluation

**Total Fits:** 1 base + 9 penalized + (9 × 16 CV) = **154 models**

---

## Three-Phase Procedure

### Phase 1: Fit Models on Full Dataset

**Phase 1a: Base Model** (`phase1_fit_base_model.R`)
- Fit standard 2D IRT model (no penalty): `authenticity_glmm_independent.stan`
- Purpose: Provide warm start for penalized models
- Output: `fit0_full.rds`, `fit0_params.rds`

**Phase 1b: Penalized Models** (`phase1_fit_penalized_models.R`)
- Fit skewness-penalized model with 9 σ_sum_w values in parallel
- Warm start from Phase 1a parameters (logitwgt initialized to 0)
- Model: `authenticity_glmm_beta_sumprior_stable.stan`
- Outputs: `fits_full_penalty.rds`, `fits_full_penalty_params.rds`

### Phase 2: Create Stratified Folds (`phase2_create_folds.R`)

**Stratification Strategy:**
1. Extract `logitwgt` from σ_sum_w = 1.0 fit (middle of grid)
2. Sort participants by logitwgt (primary), age (secondary)
3. Number off consecutively: 1, 2, 3, ..., 16, 1, 2, 3, ...
4. Result: 16 balanced folds with similar authenticity weight and age distributions

**Outputs:** `fold_assignments.rds`, `fold_diagnostics.rds`, diagnostic plots

### Phase 3: Cross-Validation Loop (`phase3_cv_loop.R`)

**Execution:**
- 9 σ_sum_w values × 16 folds = **144 CV fits in parallel**
- Each fit: Train on 15/16 folds, evaluate on 1/16 holdout
- Warm start from Phase 1b parameters

**Holdout Evaluation:**
- Cannot estimate person effects from holdout data (data leakage)
- Solution: Marginalize over η ~ N(0,1) using Gauss-Hermite quadrature
- 21-point quadrature, two independent 1D integrations (dimensions uncorrelated)
- Loss: Mean per-person deviance = -2 × log_marginal_lik / n_items

**Outputs:** `cv_results.rds`, `cv_summary.rds`, `optimal_sigma.rds`

---

## Data Preparation

**Before running the CV workflow**, you must prepare `M_data` and `J_data` from the database.

### Automated Preparation (Recommended)

```r
# Step 0: Prepare data from database (~5-10 seconds)
source("scripts/authenticity_screening/in_development/00_prepare_cv_data.R")

cv_data <- prepare_cv_data(
  db_path = "data/duckdb/kidsights_local.duckdb",
  codebook_path = "codebook/data/codebook.json",
  output_dir = "data/temp",
  use_authentic_only = TRUE  # Only authentic participants for initial CV
)

# Outputs saved to data/temp/:
#   - cv_M_data.rds: Response data (pid, item_id, response, age)
#   - cv_J_data.rds: Item metadata (item_id, K, dimension)
#   - cv_item_map.rds: Original item_id mapping
```

**What it does:**
1. Loads calibration items from `codebook.json` (with `calibration: true`)
2. Extracts response data from `ne25_calibration` table (or `calibration_dataset_long` fallback)
3. Filters to authentic participants only (recommended for initial CV)
4. Recodes item_id to consecutive integers 1:J (required by Stan)
5. Validates data integrity (response ranges, item alignment)

**Prerequisites:**
- NE25 pipeline run (creates `ne25_calibration` table)
- Authenticity screening run (creates `authentic` flag in `ne25_transformed`)

### Manual Preparation (Advanced)

If using custom data sources:

```r
# M_data: Response-level (one row per person-item response)
M_data <- data.frame(
  pid = c(1, 1, 1, 2, 2, ...),           # Participant ID
  item_id = c(1, 2, 3, 1, 2, ...),       # Consecutive integers 1:J
  response = c(0, 1, 2, 1, 0, ...),      # Response (0 to K-1)
  age = c(5.2, 5.2, 5.2, 3.8, 3.8, ...)  # Age in years
)

# J_data: Item-level metadata
J_data <- data.frame(
  item_id = c(1, 2, 3, ...),             # Consecutive integers 1:J
  K = c(3, 3, 4, ...),                   # Number of categories
  dimension = c(1, 1, 2, ...)            # 1=Psychosocial, 2=Developmental
)
```

**Critical requirements:**
- `item_id` must be consecutive integers starting at 1
- `response` must be in range [0, K-1] for each item
- All item_ids in M_data must exist in J_data

---

## Quick Start

### Complete Workflow (All 4 Steps)

**Step 0: Prepare Data** (5-10 seconds)

```r
source("scripts/authenticity_screening/in_development/00_prepare_cv_data.R")
cv_data <- prepare_cv_data()
```

**Steps 1-3: Run CV Workflow** (3-8 hours)

```r
# Load prepared data
M_data <- readRDS("data/temp/cv_M_data.rds")
J_data <- readRDS("data/temp/cv_J_data.rds")

# Run complete workflow
source("scripts/authenticity_screening/in_development/run_cv_workflow.R")

results <- run_complete_cv_workflow(
  M_data = M_data,
  J_data = J_data,
  sigma_grid = 2^(seq(-1, 1, by = 0.25)),  # 9 values: 0.5 to 2.0
  lambda_skew = 1.0,                        # Fixed
  n_folds = 16,
  output_dir = "output/authenticity_cv",
  iter = 10000,           # L-BFGS max iterations
  algorithm = "LBFGS",    # Optimization algorithm
  verbose = FALSE,        # Suppress output for Phases 1b/3
  refresh = 0             # No iteration updates
)

# Inspect results
print(results$optimal_sigma)    # Selected σ_sum_w
print(results$cv_summary)       # CV loss for all σ values
```

**Estimated Time (with L-BFGS optimization):**
- Phase 1a: 5-15 minutes (base model)
- Phase 1b: 10-20 minutes (9 penalized models in parallel)
- Phase 2: 1-2 minutes (fold creation)
- Phase 3: 1-3 hours (144 CV fits in parallel, depends on hardware)
- **Total: 1.5-4 hours** (mostly Phase 3)

### Skip Already-Completed Phases (Iterating on Phase 3)

```r
# If Phase 1 and 2 already completed, just re-run Phase 3
results <- run_complete_cv_workflow(
  M_data = M_data,
  J_data = J_data,
  skip_phase1 = TRUE,
  skip_phase2 = TRUE,
  output_dir = "output/authenticity_cv"
)
```

**Use Case:** Testing different CV parameters (e.g., number of folds, GH nodes) without re-fitting Phase 1 models.

---

## Key Parameters

### `run_complete_cv_workflow()`

| Parameter | Default | Description |
|-----------|---------|-------------|
| `M_data` | *required* | Response data: `pid`, `item_id`, `response`, `age` |
| `J_data` | *required* | Item metadata: `item_id`, `K` (categories), `dimension` (1=psychosocial, 2=developmental) |
| `sigma_grid` | `2^(seq(-1,1,by=0.25))` | σ_sum_w values to evaluate (9 values) |
| `lambda_skew` | `1.0` | Skewness penalty strength (fixed) |
| `n_folds` | `16` | Number of CV folds |
| `output_dir` | `"output/authenticity_cv"` | Directory for all results |
| `iter` | `10000` | Maximum L-BFGS iterations |
| `algorithm` | `"LBFGS"` | Optimization algorithm |
| `verbose` | `FALSE` | Print optimization progress (Phases 1b/3) |
| `refresh` | `0` | Print update every N iterations |
| `history_size` | `500` | L-BFGS history size for Hessian approximation |
| `tol_obj` | `1e-12` | Absolute tolerance for objective function |
| `tol_grad` | `1e-8` | Absolute tolerance for gradient |
| `skip_phase1` | `FALSE` | Skip Phase 1 if already run |
| `skip_phase2` | `FALSE` | Skip Phase 2 if already run |

---

## Output Files

All files saved to `output_dir` (default: `output/authenticity_cv/`)

### Phase 1 Outputs

- **`fit0_full.rds`** - Base 2D IRT model fit object
- **`fit0_params.rds`** - Extracted parameters (tau, beta1, delta, eta)
- **`fits_full_penalty.rds`** - List of 9 penalized model fits
- **`fits_full_penalty_params.rds`** - Extracted parameters for all σ values

### Phase 2 Outputs

- **`fold_assignments.rds`** - Data frame: `pid`, `fold` (1-16)
- **`fold_diagnostics.rds`** - Summary statistics per fold
- **`person_data_with_folds.rds`** - Person-level data: `pid`, `age`, `logitwgt`, `w`, `fold`
- **`plots/fold_logitwgt_distribution.png`** - Box plots of logitwgt by fold
- **`plots/fold_age_distribution.png`** - Box plots of age by fold
- **`plots/fold_summary_stats.png`** - Fold-level means

### Phase 3 Outputs

- **`cv_results.rds`** - All 144 fold results (sigma_sum_w, fold, fold_loss, max_rhat, fit_success)
- **`cv_summary.rds`** - Aggregated CV loss by σ value (mean, SE, n_folds_converged)
- **`optimal_sigma.rds`** - Selected σ_sum_w with minimum CV loss

---

## Technical Details

### Gauss-Hermite Quadrature

**Problem:** Cannot estimate person effects η for holdout participants (data leakage).

**Solution:** Marginalize over prior η ~ N(0,1) via numerical integration.

**Method:** Gauss-Hermite quadrature with 21 nodes
- Standard GH: ∫ f(x) exp(-x²) dx ≈ Σ w_k f(x_k)
- Transform to N(0,1): x_new = √2 × x_std, w_new = w_std / √π
- Two independent 1D integrations (dimensions uncorrelated)

**Implementation:**
```r
# Generate GH nodes/weights
gh <- get_gh_nodes_weights(n_nodes = 21)

# For each holdout person, compute marginal likelihood
log_marginal_dim1 <- log_sum_exp(log(gh$weights[k]) + loglik_dim1[k])
log_marginal_dim2 <- log_sum_exp(log(gh$weights[k]) + loglik_dim2[k])
log_marginal_total <- log_marginal_dim1 + log_marginal_dim2

# Per-person loss (normalized by number of items)
deviance[i] <- -2 * log_marginal_total / n_items[i]
```

### Loss Aggregation

**Per-Person Deviance:**
```
dev_i = -2 × log(marginal_likelihood_i) / n_items[i]
```

**Fold Loss:**
```
fold_loss = mean(dev_1, dev_2, ..., dev_N_holdout)
```

**CV Loss:**
```
cv_loss(σ) = mean(fold_loss_1, fold_loss_2, ..., fold_loss_16)
```

### Warm Starting Strategy

1. **Phase 1a → Phase 1b:**
   - Use Phase 1a estimates (tau, beta1, delta, eta) as initial values
   - Initialize logitwgt = 0 (neutral: inv_logit(0) ≈ 0.5)

2. **Phase 1b → Phase 3:**
   - Use Phase 1b estimates for each σ value
   - Subset eta and logitwgt to training fold participants

**Benefit:** Substantially faster convergence, fewer iterations needed.

### Parallel Execution

**Unix/Linux/Mac:**
```r
parallel::mclapply(jobs, fit_function, mc.cores = n_parallel)
```

**Windows:**
```r
cl <- parallel::makeCluster(n_parallel)
parallel::clusterExport(cl, required_objects)
parallel::clusterEvalQ(cl, {library(rstan); library(dplyr)})
parallel::parLapply(cl, jobs, fit_function)
parallel::stopCluster(cl)
```

**Recommendation:** Use high-performance computing cluster if available (144 CV fits are embarrassingly parallel).

---

## Validation

### Convergence Checks

After Phase 3 completes, inspect:

```r
cv_results <- readRDS("output/authenticity_cv/cv_results.rds")

# Check for failed fits
sum(!cv_results$fit_success)  # Should be 0

# Check optimization convergence
table(cv_results$return_code)  # Should be all 0 (success)
sum(cv_results$converged)      # Count of successful optimizations
```

### CV Loss Curve

```r
cv_summary <- readRDS("output/authenticity_cv/cv_summary.rds")

library(ggplot2)
ggplot(cv_summary, aes(x = sigma_sum_w, y = cv_loss)) +
  geom_point() +
  geom_line() +
  geom_errorbar(aes(ymin = cv_loss - se_loss, ymax = cv_loss + se_loss)) +
  scale_x_log10() +
  labs(title = "Cross-Validation Loss by σ_sum_w",
       x = "σ_sum_w (log scale)",
       y = "CV Loss (mean deviance)") +
  theme_minimal()
```

**Expected Pattern:** U-shaped curve
- Too small σ (< 0.5): Model overweights penalty, excessive exclusions
- Too large σ (> 2.0): Penalty too weak, fails to control skewness
- Optimal σ: Minimum of curve, typically 0.7-1.4

### Final Model Validation

After selecting optimal σ, refit on full dataset and validate:

1. **Exclusion Rate:** Should be 5-15% (w < 0.1)
2. **Convergence:** return_code = 0, stable log-posterior value
3. **Skewness:** sum(w) should be close to N
4. **Weight Distribution:** Bimodal (many near 0, many near 1)

---

## Files in This Directory

### R Scripts

- **`00_prepare_cv_data.R`** - Extract and format M_data/J_data from database
- **`gh_quadrature_utils.R`** - Core utilities (GH nodes, fold creation, data prep)
- **`phase1_fit_base_model.R`** - Fit base 2D IRT model
- **`phase1_fit_penalized_models.R`** - Fit 9 penalized models in parallel
- **`phase2_create_folds.R`** - Create stratified folds
- **`phase3_cv_loop.R`** - Execute 144 CV fits in parallel
- **`run_cv_workflow.R`** - Orchestrate complete 3-phase workflow

### Stan Models

Located in `models/in_development/`:

- **`authenticity_glmm_cv.stan`** - CV model with training/holdout separation and GH quadrature

**Production model** (not in development):
- `models/authenticity_glmm_beta_sumprior_stable.stan` - Model being tuned

---

## Troubleshooting

### Problem: "Some PIDs in M_data do not have fold assignments"

**Cause:** M_data contains PIDs not present in fold_assignments.

**Fix:** Ensure fold_assignments contains all unique PIDs from M_data before Phase 3.

### Problem: High proportion of failed CV fits

**Cause:** Non-convergence in L-BFGS optimization or data issues.

**Fixes:**
1. Increase `iter` (e.g., 20000 instead of 10000)
2. Adjust tolerances (e.g., `tol_rel_obj = 10`, `tol_rel_grad = 1e4`)
3. Check for participants with very few item responses (< 5)
4. Inspect failed fits' return_code values for patterns

### Problem: Long execution time (> 6 hours)

**Causes:**
- Sequential execution on Windows (no cluster setup)
- Low core count
- Slow convergence in optimization

**Fixes:**
1. Set up `parallel::makeCluster()` with maximum cores
2. Use defaults (iter = 10000 is usually sufficient)
3. Increase `history_size` to 700-1000 for faster convergence
4. Use HPC cluster if available

### Problem: CV loss curve is flat

**Interpretation:** Model is insensitive to σ_sum_w in this range.

**Actions:**
1. Check if skewness penalty (λ_skew) is too weak or too strong
2. Expand grid beyond [0.5, 2.0] if needed
3. Validate that authenticity screening is working (check w distribution)

---

## References

**Documentation:**
- [models/SKEWNESS_PENALIZED_AUTHENTICITY.md](../../../models/SKEWNESS_PENALIZED_AUTHENTICITY.md) - Model specification and rationale
- [docs/authenticity_screening/](../../../docs/authenticity_screening/) - General authenticity screening documentation

**Dependencies:**
- R 4.5.1+
- rstan 2.32.6+
- dplyr 1.1.4+
- parallel (base R)
- fastGHQuad 1.0+

---

**Questions or Issues?** Check git history or contact the development team.

**Status:** Ready for production use on real data. Model compilation verified, all scripts tested.

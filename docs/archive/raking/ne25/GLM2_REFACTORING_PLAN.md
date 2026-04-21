# Raking Targets Pipeline Refactoring Plan
## Migration from `svyglm()` to `glm2()` with Efficient Bootstrap

**Created:** January 2025
**Status:** 📋 PLANNING
**Objective:** Simplify raking targets pipeline by using `glm2::glm2()` with bootstrap replicate weights instead of survey objects

---

## Core Principle

**Bootstrap replicate weights encode survey design complexity.** Once we have them, standard GLM with weights is sufficient—no need for `svyglm()` machinery.

### Current Approach (Complex)
```r
# Fit 4096 models using survey objects
for (i in 1:4096) {
  temp_design <- boot_design
  temp_design$pweights <- boot_design$repweights[, i]
  model <- survey::svyglm(formula, design = temp_design, family = quasibinomial())
  predictions[, i] <- predict(model, newdata = pred_data, type = "response")
}
```

### Refactored Approach (Simple)
```r
# Step 1: Fit main model and get starting values
main_model <- glm2(formula, data = acs_data, weights = PERWT,
                   family = binomial())
start_coef <- coef(main_model)

# Step 2: Fit 4096 models using starting values (FASTER)
for (i in 1:4096) {
  boot_model <- glm2(formula, data = acs_data,
                     weights = replicate_weights[, i],
                     family = binomial(),
                     start = start_coef)  # ← Speed boost
  predictions[, i] <- predict(boot_model, newdata = pred_data, type = "response")
}
```

**Benefits:**
- ✅ Simpler code (no survey design objects after bootstrap creation)
- ✅ Faster execution (starting values reduce iterations)
- ✅ Same statistical validity (replicate weights encode design)

---

## Requirements

### (a) Efficiency: Starting Values
- Fit model once with main design weights
- Extract coefficients: `start_coef <- coef(main_model)`
- Pass to bootstrap fits: `glm2(..., start = start_coef)`
- **Expected speedup:** 30-50% reduction in execution time

### (b) Multinomial Logistic Regression
**Current (INCORRECT):** FPL and PUMA use 5 and 14 separate binary logistic regressions, then normalize

**Refactored (CORRECT):** Use `nnet::multinom()` for true multinomial models
```r
# FPL: 5 categories (0-99%, 100-199%, 200-299%, 300-399%, 400%+)
fpl_model <- multinom(fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
                      data = acs_data,
                      weights = PERWT)

# PUMA: 14 categories (one per Nebraska PUMA)
puma_model <- multinom(PUMA ~ AGE + MULTYEAR + AGE:MULTYEAR,
                       data = acs_data,
                       weights = PERWT)
```

**Advantages:**
- Predictions automatically sum to 1.0 (no post-hoc normalization)
- Statistically more efficient (models category correlations)
- Fewer models to fit (1 multinomial vs. 5/14 binary)

### (c) Testing Strategy
Each phase includes:
1. **Unit test:** Test helper function with toy data (n=100)
2. **Minimal example:** Run on subset of real data (n=500, 10 bootstrap replicates)
3. **Validation:** Compare to original approach (expect ~same results)

### (d) Task Management
- Each phase ends with verification task
- Verification loads next phase into Claude todo list
- Example: "Verify Phase 1 complete → Load Phase 2 tasks"

### (e) Single Source of Truth: `n_boot`
**Current problem:** `n_boot` defined in 3 places (01a, 12a, 17a)

**Solution:** Centralized configuration file
```r
# config/bootstrap_config.R
BOOTSTRAP_CONFIG <- list(
  n_boot = 4096,              # Production: 4096, Testing: 96
  method = "Rao-Wu-Yue-Beaumont",
  parallel_workers = 16
)
```

All scripts source this file: `source("config/bootstrap_config.R")`

---

## Implementation Phases

### Phase 0: Infrastructure & Configuration
**Duration:** 1-2 hours
**Goal:** Set up tools and centralized configuration

**Tasks:**
1. Create `config/bootstrap_config.R` with centralized `n_boot`
2. Install `glm2` package: `install.packages("glm2")`
3. Create minimal test: Verify `glm2()` works with starting values
4. Create minimal test: Verify `multinom()` works with weights
5. **Verify Phase 0:** All infrastructure ready → Load Phase 1 tasks

**Deliverable:** Configuration file + 2 minimal test scripts

---

### Phase 1: Refactor Helper Functions
**Duration:** 2-3 hours
**Goal:** Update `estimation_helpers.R` and `bootstrap_helpers.R`

**Tasks:**

**1.1 Create `estimation_helpers_glm2.R`** (new file)
```r
# Binary GLM with glm2
fit_glm2_estimates <- function(data, formula, weights, pred_data,
                               ages = 0:5, predict_year = 2023) {
  # Fit main model
  main_model <- glm2::glm2(formula, data = data, weights = weights,
                           family = binomial())

  # Predict
  newdata <- data.frame(AGE = ages, MULTYEAR = predict_year)
  predictions <- predict(main_model, newdata = newdata, type = "response")

  data.frame(age = ages, estimate = as.numeric(predictions))
}

# Multinomial logistic with nnet
fit_multinom_estimates <- function(data, outcome_var, formula, weights,
                                   pred_data, ages = 0:5) {
  # Fit multinomial model
  model <- nnet::multinom(formula, data = data, weights = weights, trace = FALSE)

  # Predict probabilities
  probs <- predict(model, newdata = pred_data, type = "probs")

  # Format results
  # ... (return data frame with age, category, estimate)
}
```

**1.2 Create `bootstrap_helpers_glm2.R`** (new file)
```r
generate_bootstrap_glm2 <- function(data, formula, replicate_weights,
                                    pred_data, family = binomial()) {
  n_boot <- ncol(replicate_weights)

  # Step 1: Fit main model with original weights
  main_weights <- rowMeans(replicate_weights)  # Or use design weights
  main_model <- glm2::glm2(formula, data = data, weights = main_weights,
                           family = family)
  start_coef <- coef(main_model)

  # Step 2: Fit bootstrap models with starting values
  boot_estimates <- future.apply::future_lapply(1:n_boot, function(i) {
    boot_model <- glm2::glm2(formula, data = data,
                             weights = replicate_weights[, i],
                             family = family,
                             start = start_coef)  # ← EFFICIENCY
    as.numeric(predict(boot_model, newdata = pred_data, type = "response"))
  }, future.seed = TRUE)

  do.call(cbind, boot_estimates)
}

generate_bootstrap_multinom <- function(data, formula, replicate_weights,
                                        pred_data) {
  # Similar structure but using nnet::multinom()
  # ...
}
```

**1.3 Unit Tests**
- Test `fit_glm2_estimates()` on toy data (n=100)
- Test `fit_multinom_estimates()` on toy categorical data
- Test bootstrap helpers with 10 replicates

**1.4 Verify Phase 1 Complete → Load Phase 2 Tasks**

**Deliverables:**
- `config/bootstrap_config.R`
- `scripts/raking/ne25/estimation_helpers_glm2.R`
- `scripts/raking/ne25/bootstrap_helpers_glm2.R`
- `scripts/raking/ne25/tests/test_glm2_helpers.R`

---

### Phase 2: Migrate Binary Estimands (Sex, Race, Education, Marital)
**Duration:** 3-4 hours
**Goal:** Refactor scripts 02, 03, 06, 07 to use glm2

**Tasks:**

**2.1 Refactor `02_estimate_sex.R`**
- Replace `svyglm()` with `glm2::glm2()`
- Use `generate_bootstrap_glm2()` for bootstrap estimates
- Minimal test: Compare to original with 10 bootstrap replicates
- Expected: Point estimates within 0.001, SE within 5%

**2.2 Refactor `03_estimate_race_ethnicity.R`**
- Same pattern as 02 (3 binary models: white_nh, hispanic, other)
- Use starting values for each race category

**2.3 Refactor `06_estimate_mother_education.R`**
- Binary model: bachelor's degree or higher
- Use starting values

**2.4 Refactor `07_estimate_mother_marital_status.R`**
- Binary model: currently married
- Use starting values

**2.5 Verify Phase 2 Complete → Load Phase 3 Tasks**

**Deliverables:** 4 refactored estimation scripts + validation reports

---

### Phase 3: Migrate Multinomial Estimands (FPL & PUMA)
**Duration:** 4-5 hours
**Goal:** Replace separate binary models with true multinomial regression

**Tasks:**

**3.1 Refactor `04_estimate_fpl.R`**
**Current:** 5 separate binary logistic models + normalization
**Refactored:** 1 multinomial logistic model

```r
# Create FPL category factor
acs_data$fpl_category <- cut(acs_data$POVERTY,
                              breaks = c(0, 100, 200, 300, 400, 600),
                              labels = c("0-99%", "100-199%", "200-299%",
                                         "300-399%", "400%+"))

# Fit multinomial model (NO separate binary models)
fpl_model <- nnet::multinom(
  fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
  data = acs_data,
  weights = PERWT,
  trace = FALSE
)

# Predictions automatically sum to 1.0 (no normalization needed)
fpl_predictions <- predict(fpl_model, newdata = pred_data, type = "probs")
```

**Bootstrap for multinomial:**
```r
generate_bootstrap_multinom <- function(data, formula, replicate_weights, pred_data) {
  # Fit main model
  main_model <- multinom(formula, data = data, weights = rowMeans(replicate_weights),
                         trace = FALSE)
  start_wts <- main_model$wts  # Starting weights (not coefficients)

  # Bootstrap replicates
  boot_estimates <- lapply(1:ncol(replicate_weights), function(i) {
    boot_model <- multinom(formula, data = data,
                           weights = replicate_weights[, i],
                           Wts = start_wts,  # ← Starting weights for speed
                           trace = FALSE)
    predict(boot_model, newdata = pred_data, type = "probs")
  })

  # Return array: (n_ages, n_categories, n_boot)
  simplify2array(boot_estimates)
}
```

**3.2 Refactor `05_estimate_puma.R`**
**Current:** 14 separate binary logistic models + normalization
**Refactored:** 1 multinomial logistic model (14 categories)

```r
puma_model <- nnet::multinom(
  factor(PUMA) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  data = acs_data,
  weights = PERWT,
  trace = FALSE
)
```

**3.3 Validation**
- Compare multinomial predictions to normalized binary predictions
- Expected: Point estimates within 1% (slight differences due to model structure)
- Verify: Predictions automatically sum to 1.0 (no normalization artifacts)

**3.4 Verify Phase 3 Complete → Load Phase 4 Tasks**

**Deliverables:**
- Refactored `04_estimate_fpl.R` and `05_estimate_puma.R`
- Validation report comparing multinomial vs. binary approaches

---

### Phase 4: Migrate NHIS & NSCH Pipelines
**Duration:** 2-3 hours
**Goal:** Apply glm2 refactoring to NHIS and NSCH estimands

**Tasks:**

**4.1 Refactor `13_estimate_phq2.R` (NHIS)**
- Replace `svyglm()` with `glm2::glm2()`
- Use NHIS bootstrap replicate weights from `12a_create_nhis_bootstrap_design.R`
- Apply starting values approach

**4.2 Refactor `18_estimate_nsch_outcomes.R` (NSCH)**
- Replace `svyglm()` with `glm2::glm2()`
- Handle 4 outcomes: ACE 2+, flourishing, healthcare access, developmental screening
- Use NSCH bootstrap replicate weights from `17a_create_nsch_bootstrap_design.R`

**4.3 Update bootstrap design scripts (01a, 12a, 17a)**
- Source `config/bootstrap_config.R` for centralized `n_boot`
- Replace hardcoded `n_boot <- 96` with `n_boot <- BOOTSTRAP_CONFIG$n_boot`

**4.4 Verify Phase 4 Complete → Load Phase 5 Tasks**

**Deliverables:**
- Refactored NHIS and NSCH estimation scripts
- Updated bootstrap design scripts with centralized config

---

### Phase 5: Integration, Validation & Documentation
**Duration:** 2-3 hours
**Goal:** End-to-end testing and validation

**Tasks:**

**5.1 Update consolidation scripts**
- `21a_consolidate_acs_bootstrap.R` (verify works with glm2 output)
- `21b_consolidate_nsch_boot.R`
- `22_consolidate_all_boot_replicates.R`

**5.2 End-to-end pipeline test**
```r
# Run full pipeline with n_boot = 96 (test mode)
source("config/bootstrap_config.R")
BOOTSTRAP_CONFIG$n_boot <- 96  # Override for testing

source("scripts/raking/ne25/run_bootstrap_pipeline.R")
```

**5.3 Validation: Compare to original pipeline**
```r
# Load original results (with svyglm)
original <- readRDS("data/raking/ne25/acs_bootstrap_consolidated_original.rds")

# Load refactored results (with glm2)
refactored <- readRDS("data/raking/ne25/acs_bootstrap_consolidated.rds")

# Compare point estimates and standard errors
validation_report <- compare_pipelines(original, refactored)
# Expected: Point estimates within 0.1%, SE within 2%
```

**5.4 Performance benchmarking**
```r
# Original approach timing
original_time <- benchmark_original_pipeline(n_boot = 96)

# Refactored approach timing
refactored_time <- benchmark_refactored_pipeline(n_boot = 96)

# Report speedup
cat("Speedup factor:", original_time / refactored_time, "\n")
# Expected: 1.3x - 1.5x faster with starting values
```

**5.5 Update documentation**
- Update `docs/raking/ne25/BOOTSTRAP_IMPLEMENTATION_PLAN.md`
- Add section: "Why glm2 Instead of svyglm"
- Document multinomial logistic regression approach

**5.6 Verify Phase 5 Complete → Refactoring Finished**

**Deliverables:**
- Working end-to-end pipeline with glm2
- Validation report (original vs. refactored)
- Performance benchmark results
- Updated documentation

---

## Configuration Management

### Single Source of Truth: `config/bootstrap_config.R`

```r
# config/bootstrap_config.R
# Bootstrap Replicate Configuration for NE25 Raking Targets
# Single source of truth for n_boot across all pipelines

BOOTSTRAP_CONFIG <- list(
  # Number of bootstrap replicates
  n_boot = 4096,  # Production: 4096, Testing: 96, Development: 10

  # Bootstrap method
  method = "Rao-Wu-Yue-Beaumont",

  # Parallel processing
  parallel_workers = 16,  # Half of 32 logical processors

  # Memory settings
  max_globals_gb = 128,

  # Paths
  data_dir = "data/raking/ne25",

  # Mode indicators
  is_production = function() BOOTSTRAP_CONFIG$n_boot >= 4096,
  is_testing = function() BOOTSTRAP_CONFIG$n_boot < 100
)

# Helper function to check mode
get_bootstrap_mode <- function() {
  if (BOOTSTRAP_CONFIG$is_production()) {
    return("PRODUCTION")
  } else if (BOOTSTRAP_CONFIG$is_testing()) {
    return("TESTING")
  } else {
    return("DEVELOPMENT")
  }
}

# Print configuration on load
cat("\n========================================\n")
cat("Bootstrap Configuration Loaded\n")
cat("========================================\n")
cat("Mode:", get_bootstrap_mode(), "\n")
cat("n_boot:", BOOTSTRAP_CONFIG$n_boot, "\n")
cat("Method:", BOOTSTRAP_CONFIG$method, "\n")
cat("Workers:", BOOTSTRAP_CONFIG$parallel_workers, "\n")
cat("========================================\n\n")
```

**Usage in scripts:**
```r
# At top of 01a_create_acs_bootstrap_design.R
source("config/bootstrap_config.R")
n_boot <- BOOTSTRAP_CONFIG$n_boot

# At top of bootstrap_helpers_glm2.R
source("config/bootstrap_config.R")
n_workers <- BOOTSTRAP_CONFIG$parallel_workers
```

---

## Testing Strategy

### Unit Tests (Small, Fast)
```r
# tests/test_glm2_helpers.R
test_glm2_binary <- function() {
  # Create toy data
  set.seed(123)
  n <- 100
  toy_data <- data.frame(
    outcome = rbinom(n, 1, 0.3),
    AGE = sample(0:5, n, replace = TRUE),
    MULTYEAR = sample(2019:2023, n, replace = TRUE),
    weights = runif(n, 0.5, 2.0)
  )

  # Fit model
  result <- fit_glm2_estimates(
    data = toy_data,
    formula = outcome ~ AGE + MULTYEAR,
    weights = toy_data$weights,
    pred_data = data.frame(AGE = 0:5, MULTYEAR = 2023)
  )

  # Checks
  stopifnot(nrow(result) == 6)
  stopifnot(all(result$estimate >= 0 & result$estimate <= 1))

  cat("[PASS] test_glm2_binary\n")
}

test_multinom_categorical <- function() {
  # Create toy categorical data
  set.seed(456)
  n <- 200
  toy_data <- data.frame(
    category = sample(c("A", "B", "C", "D", "E"), n, replace = TRUE),
    AGE = sample(0:5, n, replace = TRUE),
    MULTYEAR = sample(2019:2023, n, replace = TRUE),
    weights = runif(n, 0.5, 2.0)
  )

  # Fit multinomial
  result <- fit_multinom_estimates(
    data = toy_data,
    formula = category ~ AGE + MULTYEAR,
    weights = toy_data$weights,
    pred_data = data.frame(AGE = 0:5, MULTYEAR = 2023)
  )

  # Checks: Should sum to 1.0 within each age
  sums_by_age <- tapply(result$estimate, result$age, sum)
  stopifnot(all(abs(sums_by_age - 1.0) < 0.01))

  cat("[PASS] test_multinom_categorical\n")
}

# Run tests
test_glm2_binary()
test_multinom_categorical()
```

### Minimal Examples (Real Data, Small Scale)
```r
# tests/minimal_example_fpl.R
# Test FPL multinomial on subset of real data with 10 bootstrap replicates

source("config/bootstrap_config.R")
BOOTSTRAP_CONFIG$n_boot <- 10  # Override for minimal test

# Load subset of ACS data
acs_design <- readRDS("data/raking/ne25/acs_design.rds")
acs_subset <- acs_design$variables[1:500, ]  # First 500 observations

# Create bootstrap design (10 replicates only)
boot_design_minimal <- as_bootstrap_design(
  svydesign(ids = ~CLUSTER, strata = ~STRATA, weights = ~PERWT,
            data = acs_subset, nest = TRUE),
  type = "Rao-Wu-Yue-Beaumont",
  replicates = 10
)

# Extract replicate weights
replicate_weights <- boot_design_minimal$repweights

# Fit multinomial FPL model
acs_subset$fpl_category <- cut(acs_subset$POVERTY,
                                breaks = c(0, 100, 200, 300, 400, 600),
                                labels = c("0-99%", "100-199%", "200-299%",
                                           "300-399%", "400%+"))

fpl_model <- nnet::multinom(
  fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
  data = acs_subset,
  weights = acs_subset$PERWT,
  trace = FALSE
)

# Generate 10 bootstrap estimates
boot_estimates <- generate_bootstrap_multinom(
  data = acs_subset,
  formula = fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
  replicate_weights = replicate_weights,
  pred_data = data.frame(AGE = 0:5, MULTYEAR = 2023)
)

# Validate: All predictions sum to 1.0
for (i in 1:10) {
  sums <- rowSums(boot_estimates[, , i])
  stopifnot(all(abs(sums - 1.0) < 0.01))
}

cat("[PASS] Minimal example: FPL multinomial with 10 bootstrap replicates\n")
```

---

## Key Differences: Original vs. Refactored

| Aspect | Original (svyglm) | Refactored (glm2) |
|--------|------------------|-------------------|
| **Estimation function** | `survey::svyglm()` | `glm2::glm2()` |
| **Design objects** | `svydesign()` objects throughout | Only for creating replicate weights |
| **Bootstrap fitting** | 4096 fits with survey design objects | 4096 fits with numeric weight vectors |
| **Starting values** | Not used (cold start each fit) | Used (warm start from main model) |
| **FPL/PUMA** | 5/14 separate binary models + normalize | 1 multinomial model (auto-normalized) |
| **Code complexity** | High (design object management) | Low (standard GLM with weights) |
| **Speed** | Baseline | 1.3-1.5x faster with starting values |
| **Statistical validity** | Valid | Equally valid (replicate weights encode design) |

---

## Expected Outcomes

### Performance
- **30-50% faster execution** with starting values
- **Reduced memory usage** (no survey design objects in parallel workers)
- **Simpler parallelization** (pass numeric matrices, not S3 objects)

### Statistical
- **Point estimates:** Within 0.1% of original (numerical precision)
- **Standard errors:** Within 2% of original (same bootstrap replicates)
- **Confidence intervals:** Nearly identical (same percentile method)
- **FPL/PUMA predictions:** Automatically sum to 1.0 (no normalization artifacts)

### Code Quality
- **-40% lines of code** (remove survey object management)
- **Easier to understand** (standard GLM, not survey-specific)
- **Centralized configuration** (single `n_boot` definition)
- **Better testability** (unit tests with toy data)

---

## Risk Assessment

### Low Risk
✅ **Binary estimands (sex, race, education, marital):** Straightforward GLM replacement
✅ **Bootstrap replicate creation:** Keep existing survey package code
✅ **Starting values:** Well-established optimization technique

### Medium Risk
⚠️ **Multinomial logistic regression:** Different model structure than separate binaries
- **Mitigation:** Validate predictions sum to 1.0, compare to normalized binary approach
- **Fallback:** Keep separate binary models if multinomial fails validation

⚠️ **Numerical differences:** GLM2 uses different convergence criteria than svyglm
- **Mitigation:** Test with tight tolerance (< 0.1% difference)
- **Fallback:** Adjust glm2 control parameters to match svyglm

### Low Probability, High Impact
🔴 **Bootstrap replicates incompatible with glm2:** Convergence issues with some weights
- **Mitigation:** Extensive testing in Phase 1
- **Fallback:** Use survey package only for problematic replicates

---

## Success Criteria

### Phase Completion
- [ ] Phase 0: Configuration file created, glm2/multinom tested
- [ ] Phase 1: Helper functions refactored, unit tests pass
- [ ] Phase 2: Binary estimands migrated, validation < 0.1% difference
- [ ] Phase 3: Multinomial estimands working, predictions sum to 1.0
- [ ] Phase 4: NHIS/NSCH migrated, centralized config applied
- [ ] Phase 5: End-to-end pipeline runs, validation report complete

### Overall Success
- ✅ All 30 estimands produce results within 0.1% of original
- ✅ Bootstrap SE within 2% of original (same replicates)
- ✅ Execution time reduced by 30%+ with starting values
- ✅ FPL/PUMA predictions automatically sum to 1.0
- ✅ Single `n_boot` configuration across all scripts
- ✅ All unit tests and minimal examples pass
- ✅ Documentation updated

---

## Next Steps

1. **Review this plan** with domain expert (Marcus)
2. **Approve Phase 0** to begin infrastructure setup
3. **Create project branch:** `refactor/glm2-bootstrap`
4. **Begin Phase 0 tasks** with centralized configuration

---

**Total Estimated Effort:** 14-20 hours across 5 phases
**Expected Completion:** 2-3 working days
**Primary Benefit:** Simpler, faster, equally valid raking targets pipeline

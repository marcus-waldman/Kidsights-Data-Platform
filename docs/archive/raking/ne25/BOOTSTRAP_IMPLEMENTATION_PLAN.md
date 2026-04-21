# Bootstrap Replicate Weights Implementation Plan
## Correcting NSCH Survey Design + Implementing Bootstrap for All Data Sources

**Created:** October 2025
**Status:** ✅ COMPLETE (October 6, 2025)
**Production Run:** n_boot = 4096 (737,280 bootstrap replicates)

---

## Problem Identified

**Current NSCH approach is INCORRECT**:
- Using `lme4::glmer()` with state random effects on nationwide data
- Treating this as a mixed model problem rather than survey design
- **Missing**: Multi-year data pooling (2020-2023) for increased precision
- **Missing**: Proper survey design with STRATUM and HHID variables
- **Missing**: Temporal modeling (age × year interaction)

**Correct NSCH survey design** (revised specification):
```r
# Pool Nebraska data from 2020-2023
nsch_ne_multi <- DBI::dbGetQuery(con, "
  SELECT *, YEAR as survey_year
  FROM nsch_2020_raw WHERE FIPSST = 31 AND SC_AGE_YEARS <= 5
  UNION ALL
  SELECT *, YEAR as survey_year
  FROM nsch_2021_raw WHERE FIPSST = 31 AND SC_AGE_YEARS <= 5
  UNION ALL
  SELECT *, YEAR as survey_year
  FROM nsch_2022_raw WHERE FIPSST = 31 AND SC_AGE_YEARS <= 5
  UNION ALL
  SELECT *, YEAR as survey_year
  FROM nsch_2023_raw WHERE FIPSST = 31 AND SC_AGE_YEARS <= 5
")

# Create survey design with proper specification
nsch_design <- svydesign(
  ids = ~HHID,                           # Cluster: household
  strata = ~interaction(FIPSST, STRATUM), # Strata: state × household type
  weights = ~FWC,                         # Weight: final child weight
  data = nsch_ne_multi,
  nest = TRUE
)

# Fit GLM with age factor, year linear, and age × year interaction
model <- svyglm(
  outcome ~ as.factor(SC_AGE_YEARS) + survey_year + as.factor(SC_AGE_YEARS):survey_year,
  design = nsch_design,
  family = quasibinomial()
)
```

---

## Implementation Plan

### Phase 1: Fix NSCH Survey Design (Critical Fix)

#### 1.1 Update to Multi-Year Data Pooling (2020-2023)

**Files to update**:
- `17_filter_nsch_nebraska.R` (if needed for validation)
- `18_estimate_nsch_outcomes.R` (MAJOR REWRITE)

**NEW approach - Pool 4 years of Nebraska data**:
```r
# Load multi-year NSCH data for Nebraska (2020-2023)
cat("[1] Loading multi-year NSCH data for Nebraska (2020-2023)...\\n")

nsch_ne_multi <- DBI::dbGetQuery(con, "
  SELECT *, 2020 as survey_year
  FROM nsch_2020_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL
  UNION ALL
  SELECT *, 2021 as survey_year
  FROM nsch_2021_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL
  UNION ALL
  SELECT *, 2022 as survey_year
  FROM nsch_2022_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL
  UNION ALL
  SELECT *, 2023 as survey_year
  FROM nsch_2023_raw
  WHERE FIPSST = 31
    AND SC_AGE_YEARS <= 5
    AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    AND STRATUM IS NOT NULL
    AND HHID IS NOT NULL
    AND FWC IS NOT NULL
")

cat("    Total Nebraska children (2020-2023):", nrow(nsch_ne_multi), "\\n")
cat("    Years:", paste(sort(unique(nsch_ne_multi$survey_year)), collapse = ", "), "\\n")
```

**Rationale**:
- Single-year Nebraska samples are small (~300-400 per year)
- Pooling 4 years yields ~1,200-1,600 per age bin
- Temporal modeling captures trends (e.g., post-pandemic changes)

#### 1.2 Replace GLMM with Survey-Weighted GLM + Temporal Trends

**File**: `18_estimate_nsch_outcomes.R`

**MAJOR REWRITE** - Replace entire estimation approach:

**OLD approach (INCORRECT)**:
```r
# Nationwide data + mixed model
nsch_all <- DBI::dbGetQuery(con, "SELECT ... FROM nsch_2023_raw ...")
ace_model <- lme4::glmer(
  ace_1plus ~ age_factor + (1|state_factor),
  data = ace_data,
  family = binomial,
  weights = FWC  # weights parameter in glmer ≠ survey weights
)
# Predict Nebraska BLUP
```

**NEW approach (CORRECT)**:
```r
library(survey)
library(dplyr)

# 1. Prepare outcome variables (defensive coding for missing)
cat("[2] Preparing outcome variables...\\n")

nsch_ne_multi <- nsch_ne_multi %>%
  dplyr::mutate(
    # Outcome 1: Child ACE exposure (1+ ACEs)
    ace_1plus = dplyr::case_when(
      ACEct_23 >= 1 & ACEct_23 <= 10 ~ 1,
      ACEct_23 == 0 ~ 0,
      TRUE ~ NA_real_
    ),
    # Outcome 2: Emotional/behavioral problems (ages 3+ only)
    emot_behav_prob = dplyr::case_when(
      MEDB10ScrQ5_23 == 1 ~ 1,
      MEDB10ScrQ5_23 == 2 ~ 0,
      TRUE ~ NA_real_
    ),
    # Outcome 3: Excellent health
    excellent_health = dplyr::case_when(
      K2Q01 == 1 ~ 1,
      K2Q01 %in% 2:5 ~ 0,
      TRUE ~ NA_real_
    ),
    # Child care 10+ hrs (use 2022 data only if available)
    # [If variable exists in 2022 data]
    age_factor = factor(SC_AGE_YEARS)
  )

# 2. Create survey design
cat("[3] Creating survey design object...\\n")

nsch_design <- survey::svydesign(
  ids = ~HHID,
  strata = ~interaction(FIPSST, STRATUM),  # Composite strata
  weights = ~FWC,
  data = nsch_ne_multi %>% dplyr::filter(!is.na(ace_1plus)),  # Filter to complete cases
  nest = TRUE
)

# 3. Fit survey-weighted GLM with age + year + age×year
cat("[4] Fitting survey-weighted GLM for ACE exposure...\\n")

# Full model with interaction
ace_model_full <- survey::svyglm(
  ace_1plus ~ age_factor + survey_year + age_factor:survey_year,
  design = nsch_design,
  family = quasibinomial()
)

# Main effects model
ace_model_main <- survey::svyglm(
  ace_1plus ~ age_factor + survey_year,
  design = nsch_design,
  family = quasibinomial()
)

# Test interaction significance
interaction_test <- anova(ace_model_main, ace_model_full)
use_interaction <- interaction_test$p[2] < 0.05

cat("    Interaction significant:", use_interaction, "\\n")

# Select model
ace_model <- if(use_interaction) ace_model_full else ace_model_main

# 4. Predict at year 2023 for each age
cat("[5] Predicting at year 2023...\\n")

pred_data <- data.frame(
  age_factor = factor(0:5),
  survey_year = 2023
)

ace_estimates <- predict(ace_model, newdata = pred_data, type = "response")

ace_pred <- data.frame(
  age = 0:5,
  estimand = "Child ACE Exposure (1+ ACEs)",
  estimate = as.numeric(ace_estimates)
)

cat("    Estimates (ages 0-5):", paste(round(ace_pred$estimate, 3), collapse = ", "), "\\n\\n")
```

**Apply same pattern** to:
- Emotional/Behavioral model (predict at 2023, ages 3-5 only, NA for ages 0-2)
- Excellent Health model (predict at 2023, ages 0-5)
- Child care model (predict at 2022, ages 0-5 - last year with valid data)

---

### Phase 2: Implement Bootstrap Replicate Weights for All Data Sources

#### 2.1 ACS Bootstrap (25 estimands)

**Files to modify**: `02_estimate_sex_final.R`, `03_estimate_race_ethnicity.R`, `04_estimate_fpl.R`, `05_estimate_puma.R`, `06_estimate_mother_education.R`, `07_estimate_mother_marital_status.R`

**Pattern for each script**:

**After loading ACS design** (~line 13):
```r
# Load existing design
acs_design <- readRDS("data/raking/ne25/acs_design.rds")

# Convert to bootstrap design (4096 replicates)
library(svrep)
acs_boot <- as_bootstrap_design(
  design = acs_design,
  type = "Rao-Wu-Yue-Beaumont",  # Handles complex sampling
  replicates = 4096,
  mse = TRUE
)

cat("  Bootstrap design: 4096 replicates created\n")
```

**Replace GLM fitting** to use bootstrap design:
```r
# Fit model using bootstrap design
model <- survey::svyglm(
  outcome ~ AGE + MULTYEAR + ...,
  design = acs_boot,  # Use bootstrap design instead
  family = quasibinomial()
)
```

**Extract bootstrap replicates using withReplicates**:
```r
# After getting predictions, extract bootstrap distribution
boot_results <- survey::withReplicates(
  design = acs_boot,
  theta = function(wts, data) {
    # Recreate design with current replicate weights
    rep_design <- survey::svydesign(
      ids = ~CLUSTER,
      strata = ~STRATA,
      weights = wts,
      data = data,
      nest = TRUE
    )

    # Refit model
    rep_model <- survey::svyglm(
      outcome ~ AGE + MULTYEAR + ...,
      design = rep_design,
      family = quasibinomial()
    )

    # Return predictions for ages 0-5
    predict(rep_model, newdata = pred_data, type = "response")
  },
  return.replicates = TRUE
)

# boot_results$theta = point estimates (6 values, ages 0-5)
# boot_results$replicates = 4096 × 6 matrix of bootstrap estimates
```

**Save both outputs**:
```r
# Point estimates (existing output for pipeline)
results <- data.frame(
  age = 0:5,
  estimand = "estimand_name",
  estimate = boot_results$theta
)
saveRDS(results, "data/raking/ne25/{estimand}_estimates.rds")

# Bootstrap replicates (NEW)
boot_df <- data.frame(
  replicate = rep(1:4096, each = 6),
  age = rep(0:5, times = 4096),
  estimand = "estimand_name",
  estimate = as.vector(t(boot_results$replicates))  # Transpose for age-major order
)
saveRDS(boot_df, "data/raking/ne25/{estimand}_boot_replicates.rds")
```

#### 2.2 NHIS Bootstrap (1 estimand)

**File**: `13_estimate_phq2.R`

**After creating survey design** (line ~96):
```r
# Create survey design (existing)
phq_design <- survey::svydesign(
  ids = ~PSU_child,
  strata = ~STRATA_child,
  weights = ~SAMPWEIGHT_parent,
  data = phq_data,
  nest = TRUE
)

# NEW: Convert to bootstrap design
library(svrep)
phq_boot <- as_bootstrap_design(
  design = phq_design,
  type = "Rao-Wu-Yue-Beaumont",
  replicates = 4096,
  mse = TRUE
)
```

**Modify GLM** (line ~113):
```r
# Use bootstrap design
model_phq2 <- survey::svyglm(
  phq2_positive ~ YEAR,
  design = phq_boot,  # Changed from phq_design
  family = quasibinomial()
)
```

**Extract bootstrap estimates**:
```r
# Bootstrap estimates with year covariate
boot_results <- survey::withReplicates(
  design = phq_boot,
  theta = function(wts, data) {
    rep_design <- survey::svydesign(
      ids = ~PSU_child,
      strata = ~STRATA_child,
      weights = wts,
      data = data,
      nest = TRUE
    )

    rep_model <- survey::svyglm(
      phq2_positive ~ YEAR,
      design = rep_design,
      family = quasibinomial()
    )

    # Predict at 2023, replicate for ages 0-5
    rep(predict(rep_model, newdata = data.frame(YEAR = 2023), type = "response"), 6)
  },
  return.replicates = TRUE
)

# Save as before
```

#### 2.3 NSCH Bootstrap (4 estimands) - AFTER fixing survey design

**File**: `18_estimate_nsch_outcomes.R` (after rewrite from Phase 1)

**After creating survey design**:
```r
# Create survey design (from Phase 1 fix)
nsch_design <- survey::svydesign(
  ids = ~HHID,
  strata = ~interaction(FIPSST, STRATUM),
  weights = ~FWC,
  data = ace_data,
  nest = TRUE
)

# NEW: Convert to bootstrap design
library(svrep)
nsch_boot <- as_bootstrap_design(
  design = nsch_design,
  type = "Rao-Wu-Yue-Beaumont",
  replicates = 4096,
  mse = TRUE
)
```

**Modify GLM**:
```r
# Use bootstrap design
ace_model <- survey::svyglm(
  ace_1plus ~ as.factor(SC_AGE_YEARS),
  design = nsch_boot,  # Changed
  family = quasibinomial()
)
```

**Extract bootstrap estimates**:
```r
# Bootstrap for NSCH outcomes
boot_results <- survey::withReplicates(
  design = nsch_boot,
  theta = function(wts, data) {
    rep_design <- survey::svydesign(
      ids = ~HHID,
      strata = ~interaction(FIPSST, STRATUM),
      weights = wts,
      data = data,
      nest = TRUE
    )

    rep_model <- survey::svyglm(
      ace_1plus ~ as.factor(SC_AGE_YEARS),
      design = rep_design,
      family = quasibinomial()
    )

    predict(rep_model, newdata = data.frame(SC_AGE_YEARS = 0:5), type = "response")
  },
  return.replicates = TRUE
)

# Save as before
```

---

### Phase 3: Consolidation Scripts

#### 3.1 Create Bootstrap Consolidation Script

**NEW FILE**: `scripts/raking/ne25/21b_consolidate_boot_replicates.R`

```r
library(dplyr)

cat("\n========================================\n")
cat("Consolidate Bootstrap Replicates\n")
cat("========================================\n\n")

# Define estimands and their file names
acs_estimands <- c(
  "male", "black", "hispanic", "white_nh",
  "fpl_0_99", "fpl_100_199", "fpl_200_299", "fpl_300_399", "fpl_400_plus",
  paste0("puma_", c("100", "200", "300", "400", "500", "600",
                     "701", "702", "801", "802", "901", "902", "903", "904")),
  "mother_bachelors", "mother_married"
)

nhis_estimands <- c("phq2")
nsch_estimands <- c("ace", "emot_behav", "health", "childcare")

# Load and combine all bootstrap replicates
all_boot <- list()

# ACS (25 estimands)
for (est in acs_estimands) {
  file <- paste0("data/raking/ne25/", est, "_boot_replicates.rds")
  if (file.exists(file)) {
    all_boot[[est]] <- readRDS(file)
    cat("  Loaded", est, "\n")
  }
}

# NHIS (1 estimand)
for (est in nhis_estimands) {
  file <- paste0("data/raking/ne25/", est, "_boot_replicates.rds")
  if (file.exists(file)) {
    all_boot[[est]] <- readRDS(file)
    cat("  Loaded", est, "\n")
  }
}

# NSCH (4 estimands)
for (est in nsch_estimands) {
  file <- paste0("data/raking/ne25/", est, "_boot_replicates.rds")
  if (file.exists(file)) {
    all_boot[[est]] <- readRDS(file)
    cat("  Loaded", est, "\n")
  }
}

# Combine
boot_consolidated <- dplyr::bind_rows(all_boot)

cat("\nTotal bootstrap estimates:", nrow(boot_consolidated), "\n")
cat("  Expected: 4096 replicates × 180 targets = 737,280\n")
cat("  Actual:", nrow(boot_consolidated), "\n")

# Save
saveRDS(boot_consolidated, "data/raking/ne25/all_boot_replicates.rds")
cat("\nSaved to: data/raking/ne25/all_boot_replicates.rds\n")
```

#### 3.2 Update Master Pipeline Script

**File**: `run_raking_targets_pipeline.R`

**Add after Phase 5 consolidation**:
```r
# Consolidate bootstrap replicates
cat("  [5.10] Consolidating bootstrap replicates...\n")
source("scripts/raking/ne25/21b_consolidate_boot_replicates.R")
```

---

### Phase 4: Database Integration

#### 4.1 Create Bootstrap Replicates Table

**File**: `24_create_database_table.py`

**Add new table creation**:
```python
# After creating main raking_targets_ne25 table

# Create bootstrap replicates table
create_boot_table_sql = """
CREATE TABLE IF NOT EXISTS raking_targets_boot_replicates (
    replicate_id INTEGER NOT NULL,
    target_id INTEGER NOT NULL,
    age_years INTEGER NOT NULL,
    estimand VARCHAR NOT NULL,
    estimate DOUBLE NOT NULL,
    PRIMARY KEY (replicate_id, target_id),
    FOREIGN KEY (target_id) REFERENCES raking_targets_ne25(target_id)
)
"""

with db.get_connection() as conn:
    conn.execute(create_boot_table_sql)

print("[OK] Bootstrap replicates table created")

# Load bootstrap data
boot_df = feather.read_feather("data/raking/ne25/all_boot_replicates_temp.feather")

# Join with main targets to get target_id
# Insert into database...
```

**Create indexes**:
```python
boot_indexes = [
    "CREATE INDEX IF NOT EXISTS idx_boot_replicate ON raking_targets_boot_replicates(replicate_id)",
    "CREATE INDEX IF NOT EXISTS idx_boot_target ON raking_targets_boot_replicates(target_id)",
    "CREATE INDEX IF NOT EXISTS idx_boot_estimand ON raking_targets_boot_replicates(estimand, age_years)"
]
```

---

### Phase 5: Update Documentation

#### 5.1 Statistical Methods Document

**File**: `docs/raking/ne25/STATISTICAL_METHODS_RAKING_TARGETS.md`

**Add new section**:
```markdown
## Bootstrap Variance Estimation

### Method
- Rao-Wu-Yue-Beaumont bootstrap for complex surveys
- 4096 bootstrap replicates per estimand
- Respects stratification, clustering, and unequal weights

### Implementation
- `svrep::as_bootstrap_design()` converts survey designs
- `survey::withReplicates()` extracts replicate estimates
- Empirical distribution provides:
  - Bootstrap standard errors
  - 95% confidence intervals (percentile method)
  - Full sampling distribution

### Advantages
- No normality assumption
- Captures complex survey features
- Provides empirical distribution for raking targets
```

#### 5.2 Pipeline Documentation

**File**: `docs/raking/NE25_RAKING_TARGETS_PIPELINE.md`

**Update outputs section**:
```markdown
## Outputs

### Per-Estimand Files
- Point estimates: `{estimand}_estimates.rds` (6 rows)
- **Bootstrap replicates**: `{estimand}_boot_replicates.rds` (24,576 rows = 4096 × 6)

### Database Tables
- `raking_targets_ne25` (180 rows) - Point estimates
- `raking_targets_boot_replicates` (737,280 rows) - Bootstrap distributions
```

---

### Phase 6: Verification

#### 6.1 Add Bootstrap Validation

**File**: `verify_pipeline.R`

**Add new check**:
```r
# Check bootstrap replicates
cat("[8] Checking bootstrap replicates...\n")

boot_data <- readRDS("data/raking/ne25/all_boot_replicates.rds")

expected_rows <- 4096 * 180
actual_rows <- nrow(boot_data)

cat("  Bootstrap rows:", actual_rows, "(expected:", expected_rows, ")")
if (actual_rows == expected_rows) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
  verification_passed <- FALSE
}

# Check database
db_boot_count <- DBI::dbGetQuery(con,
  "SELECT COUNT(*) as n FROM raking_targets_boot_replicates")$n

cat("  Database bootstrap rows:", db_boot_count, "(expected:", expected_rows, ")")
if (db_boot_count == expected_rows) {
  cat(" ✓\n")
} else {
  cat(" ✗\n")
}
```

---

## Critical Changes Summary

### NSCH Survey Design Fix (HIGH PRIORITY)

1. **Query Changes**: Add `STRATUM`, `HHID` to all NSCH data loads
2. **Model Changes**: Replace `lme4::glmer()` with `survey::svyglm()`
3. **Design Changes**: Use `svydesign(ids = ~HHID, strata = ~FIPSST + STRATUM, weights = ~FWC)`

### Bootstrap Implementation (ALL DATA SOURCES)

1. **After loading design**: Call `as_bootstrap_design(replicates = 4096)`
2. **During estimation**: Use bootstrap design in GLM
3. **After estimation**: Call `withReplicates(return.replicates = TRUE)`
4. **Save outputs**: Both point estimates (existing) + bootstrap replicates (new)

### Files Modified

- **NSCH**: 3 files (17, 18, 20)
- **ACS**: 6 files (02, 03, 04, 05, 06, 07)
- **NHIS**: 1 file (13)
- **Consolidation**: 1 new file (21b), 1 modified (run_pipeline)
- **Database**: 1 file (24)
- **Verification**: 1 file (verify)
- **Documentation**: 2 files

### Computational Impact

- **Time**: Adds ~1-2 hours to pipeline (one-time cost)
- **Storage**: +6 MB RDS files, +~50 MB database
- **Memory**: ~100 MB peak during bootstrap generation

---

## Expected Outputs

### Point Estimates (Unchanged)
- 180 targets with point estimates
- Existing pipeline compatibility maintained

### Bootstrap Distributions (New)
- 737,280 bootstrap estimates (4096 × 180)
- Enables uncertainty quantification
- Empirical distributions for each target
- Standard errors and confidence intervals

---

## Open Questions

1. **NSCH State Random Effects**: Should we include state random effects in NSCH models, or rely solely on survey design with state as part of strata?
   - Current plan: No random effects, use survey design framework
   - Alternative: Combine survey design with mixed models (more complex)

2. **Nebraska-Specific Estimates**: How to extract Nebraska-specific estimates from nationwide NSCH survey design?
   - Option A: Subset to Nebraska after creating design
   - Option B: Use domain estimation (`svyby()` with domain indicator)
   - Option C: Post-stratification approach

3. **Bootstrap Method for NSCH**: Should NSCH use same bootstrap method as ACS/NHIS?
   - ✅ Resolved: Rao-Wu-Yue-Beaumont used for all three sources

---

## Implementation Summary (October 6, 2025)

### ✅ All Phases Complete

**Phase 1:** NSCH Survey Design Corrected
- Multi-year pooling (2020-2023) implemented
- Proper survey design with STRATUM, HHID, FWC
- Temporal modeling with age × year interaction

**Phase 2:** ACS Bootstrap Implementation
- Shared bootstrap design created (6657 observations × 4096 replicates)
- All 25 ACS estimands using shared replicate weights
- Filtered samples (mother education/marital) properly subset with `survey::subset()`

**Phase 3:** NHIS Bootstrap Implementation
- Bootstrap design for North Central region parent sample
- PHQ-2 estimates with 4096 replicates

**Phase 4:** NSCH Bootstrap Implementation
- Multi-year design with 4096 replicates
- State-level Nebraska subsetting maintains proper survey structure

**Phase 5:** Database Integration
- `raking_targets_boot_replicates` table created
- 737,280 rows (30 estimands × 6 ages × 4096 replicates)
- Indexed for efficient querying

### Production Run Configuration

**Environment Setup:**
- Python path configured via `.env` file (cross-platform portable)
- See: `docs/setup/ENVIRONMENT_SETUP.md`

**Execution:**
```powershell
# PowerShell (with monitoring)
.\scripts\raking\ne25\run_bootstrap_production.ps1

# R (direct)
"C:\Program Files\R\R-4.5.1\bin\R.exe" -f scripts/raking/ne25/run_bootstrap_pipeline.R
```

**Performance:**
- Execution time: ~15-20 minutes
- Storage: ~60 MB (compressed)
- Memory peak: ~2 GB during ACS bootstrap generation

### Validation Results

✅ All 737,280 bootstrap replicates generated successfully
✅ Shared bootstrap structure verified (strong correlations within sources)
✅ Standard errors computed and validated
✅ Database queries execute in <2ms with indexes

### Related Documentation

- **Statistical Methods:** `STATISTICAL_METHODS_RAKING_TARGETS.md`
- **Usage Guide:** `BOOTSTRAP_USAGE_GUIDE.md` (practical examples)
- **Environment Config:** `docs/setup/ENVIRONMENT_SETUP.md`
- **Main Pipeline:** `docs/raking/NE25_RAKING_TARGETS_PIPELINE.md`

---

*Implementation Complete: October 6, 2025*
*This document is now archived for reference.*

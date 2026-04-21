# GAD-2 Positive Anxiety Estimand - Insertion Plan

**Date:** 2025-10-08
**Status:** Planning
**Purpose:** Add GAD-2 positive anxiety screen as 31st raking target estimand

---

## Overview

### Background

The GAD-2 (Generalized Anxiety Disorder 2-item) is a brief screening tool comprising the first two items of the GAD-7 scale. Like PHQ-2 for depression, it provides an efficient screener for anxiety disorders using only two questions:
1. **GADANX** - "Feeling nervous, anxious, or on edge"
2. **GADWORCTRL** - "Not being able to stop or control worrying"

### Scoring & Clinical Interpretation

- **Range:** 0-6 (sum of two items, each rated 0-3)
- **Cutoff:** ≥3 indicates positive screen for anxiety disorder
- **Performance:** Sensitivity 86%, Specificity 83% for GAD diagnosis
- **Years Available:** 2019, 2022 (same as PHQ-2 in NHIS)

### Implementation Strategy

Use **identical methodology** as PHQ-2 implementation:
- NHIS North Central region parents with children ages 0-5
- glm2 binomial model with YEAR main effects
- Shared NHIS bootstrap design (Rao-Wu-Yue-Beaumont, 4096 replicates)
- Constant estimate across child ages 0-5 (parent characteristic)

### Expected Impact

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| **Total Estimands** | 30 | 31 | +1 |
| **NHIS Estimands** | 1 (PHQ-2) | 2 (PHQ-2, GAD-2) | +1 |
| **Raking Target Rows** | 180 | 186 | +6 |
| **Bootstrap Rows (NHIS)** | 24,576 | 49,152 | +24,576 |

---

## Phase 1: Add GAD-2 Variables to Parent Filtering

**Goal:** Extract GAD-2 items alongside PHQ-2 items during NHIS parent-child linkage.

### Task 1.1: Modify `12_filter_nhis_parents.R`

**File:** `scripts/raking/ne25/12_filter_nhis_parents.R`

**Changes:**

1. **Line 101-104** - Add GAD-2 variables to parent_pool selection:
   ```r
   parent_pool <- nhis_north_central %>%
     dplyr::filter(AGE >= 18) %>%
     dplyr::select(SERIAL, PERNUM, AGE, SEX, YEAR,
                   PHQINTR, PHQDEP,
                   GADANX, GADWORCTRL,  # ADD THIS LINE
                   VIOLENEV, JAILEV, MENTDEPEV, ALCDRUGEV,
                   ADLTPUTDOWN, UNFAIRRACE, UNFAIRSEXOR, BASENEED,
                   SAMPWEIGHT, PSU, STRATA)
   ```

2. **After line 162** - Add GAD-2 data availability check:
   ```r
   # 9a. Check GAD-2 data availability
   cat("\n[9a] Checking GAD-2 data availability...\n")

   gad_data <- nhis_parent_child %>%
     dplyr::filter(!is.na(GADANX_parent) & !is.na(GADWORCTRL_parent))

   cat("    Total parent-child pairs with GAD-2:", nrow(gad_data), "\n")
   cat("    Years with GAD-2:", paste(sort(unique(gad_data$YEAR)), collapse = ", "), "\n")
   ```

3. **After line 188** - Save GAD-2 subset:
   ```r
   # Save GAD-2 subset
   saveRDS(gad_data, "data/raking/ne25/nhis_gad2_data.rds")
   cat("    ✓ Saved to: data/raking/ne25/nhis_gad2_data.rds\n")
   ```

4. **Lines 194-201** - Update summary to include GAD-2:
   ```r
   cat("\nSummary:\n")
   cat("  - Region: North Central (REGION = 2)\n")
   cat("  - Children ages 0-5:", nrow(nhis_children), "\n")
   cat("  - Parent-child pairs:", nrow(nhis_parent_child), "\n")
   cat("  - PHQ-2 available:", nrow(phq_data), "pairs\n")
   cat("  - GAD-2 available:", nrow(gad_data), "pairs\n")  # ADD THIS LINE
   cat("  - ACE available:", nrow(ace_data), "pairs\n")
   cat("  - Years: ", paste(sort(unique(nhis_parent_child$YEAR)), collapse = ", "), "\n")
   cat("\nReady for estimation tasks 3.2-3.3\n\n")
   ```

### Task 1.2: Test Modified Filtering Script

**Command:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/12_filter_nhis_parents.R
```

**Expected Output:**
- File created: `data/raking/ne25/nhis_gad2_data.rds`
- GAD-2 availability matches PHQ-2 (years 2019, 2022)
- Sample size should match PHQ-2 (~similar N)

**Validation:**
```r
# Quick check
gad_data <- readRDS("data/raking/ne25/nhis_gad2_data.rds")
phq_data <- readRDS("data/raking/ne25/nhis_phq2_data.rds")

cat("GAD-2 sample size:", nrow(gad_data), "\n")
cat("PHQ-2 sample size:", nrow(phq_data), "\n")
cat("Years (GAD-2):", paste(sort(unique(gad_data$YEAR)), collapse = ", "), "\n")
cat("Years (PHQ-2):", paste(sort(unique(phq_data$YEAR)), collapse = ", "), "\n")
```

### Task 1.3: Load Phase 2 Tasks into Todo List

**Action:** At completion of Phase 1, create todo list with Phase 2 tasks.

---

## Phase 2: Create GAD-2 Scoring Script

**Goal:** Calculate GAD-2 total scores and create binary positive indicator, then save scored data for bootstrap design creation.

### Task 2.1: Create `12b_score_gad2.R`

**File:** `scripts/raking/ne25/12b_score_gad2.R` (NEW FILE)

**Purpose:** Score GAD-2 items and create binary positive indicator (≥3)

**Template:** Copy from `scripts/raking/ne25/12b_score_phq2.R` and adapt

**Key Steps:**
1. Load `data/raking/ne25/nhis_gad2_data.rds`
2. Check GADANX_parent and GADWORCTRL_parent distributions
3. Recode items (IPUMS codes 0-3 are valid, 7-9 are missing)
4. Calculate GAD-2 total score (0-6)
5. Create binary indicator: `gad2_positive = as.numeric(gad2_total >= 3)`
6. Filter to complete cases only
7. Save scored data: `data/raking/ne25/nhis_gad2_scored.rds`

**Expected Output File:**
- `data/raking/ne25/nhis_gad2_scored.rds`
- Should contain columns: all parent-child variables + `gadanx_recoded`, `gadworctrl_recoded`, `gad2_total`, `gad2_positive`

### Task 2.2: Test GAD-2 Scoring Script

**Command:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/12b_score_gad2.R
```

**Validation:**
```r
# Load scored data
gad_scored <- readRDS("data/raking/ne25/nhis_gad2_scored.rds")

# Check structure
cat("Sample size:", nrow(gad_scored), "\n")
cat("GAD-2 total range:", range(gad_scored$gad2_total, na.rm = TRUE), "\n")
cat("Positive screens (unweighted):", sum(gad_scored$gad2_positive), "\n")
cat("Proportion positive (unweighted):",
    round(mean(gad_scored$gad2_positive), 3), "\n")

# Should be no missing values in complete-case dataset
cat("Missing GAD-2 totals:", sum(is.na(gad_scored$gad2_total)), "\n")
```

### Task 2.3: Create Bootstrap Design for GAD-2

**Decision Point:** We have two options:

**Option A: Shared Bootstrap Design (RECOMMENDED)**
- Use existing `nhis_bootstrap_design.rds` created from PHQ-2 data
- Requires GAD-2 and PHQ-2 datasets to have **identical rows** (same parent-child pairs)
- Advantage: No additional bootstrap generation needed, perfectly correlated replicates

**Option B: GAD-2-Specific Bootstrap Design**
- Create new bootstrap design from `nhis_gad2_scored.rds`
- Use if GAD-2 and PHQ-2 have different sample sizes (different missingness patterns)
- Requires new script: `12c_create_gad2_bootstrap_design.R`

**Validation Check:**
```r
# Check if PHQ-2 and GAD-2 have identical samples
phq_scored <- readRDS("data/raking/ne25/nhis_phq2_scored.rds")
gad_scored <- readRDS("data/raking/ne25/nhis_gad2_scored.rds")

# Check row counts
cat("PHQ-2 complete cases:", nrow(phq_scored), "\n")
cat("GAD-2 complete cases:", nrow(gad_scored), "\n")

# Check if same parent-child pairs
if (nrow(phq_scored) == nrow(gad_scored)) {
  # Check SERIAL + PERNUM match
  phq_ids <- paste(phq_scored$SERIAL, phq_scored$PERNUM_child, phq_scored$YEAR)
  gad_ids <- paste(gad_scored$SERIAL, gad_scored$PERNUM_child, gad_scored$YEAR)

  match_rate <- mean(phq_ids %in% gad_ids)
  cat("ID match rate:", round(match_rate * 100, 1), "%\n")

  if (match_rate == 1.0) {
    cat("✓ Can use shared bootstrap design (Option A)\n")
  } else {
    cat("✗ Need GAD-2-specific bootstrap design (Option B)\n")
  }
} else {
  cat("✗ Need GAD-2-specific bootstrap design (Option B)\n")
}
```

**Implementation:** If Option B is needed, create `12c_create_gad2_bootstrap_design.R` following the same structure as `12a_create_nhis_bootstrap_design.R`.

### Task 2.4: Load Phase 3 Tasks into Todo List

**Action:** At completion of Phase 2, create todo list with Phase 3 tasks.

---

## Phase 3: Estimate GAD-2 Positive Rate with Bootstrap

**Goal:** Fit glm2 model and generate bootstrap replicates for GAD-2 positive anxiety rate.

### Task 3.1: Create `13b_estimate_gad2_glm2.R`

**File:** `scripts/raking/ne25/13b_estimate_gad2_glm2.R` (NEW FILE)

**Purpose:** Estimate GAD-2 positive rate using glm2 with bootstrap variance estimation

**Template:** Copy from `scripts/raking/ne25/13_estimate_phq2_glm2.R` and adapt

**Key Changes from PHQ-2 Script:**
1. Load `nhis_gad2_data.rds` instead of `nhis_phq2_data.rds`
2. Variable names: `GADANX_parent`, `GADWORCTRL_parent` (instead of PHQINTR, PHQDEP)
3. Outcome variable: `gad2_positive` (instead of phq2_positive)
4. Output files: `gad2_estimate_glm2.rds`, `gad2_estimate_boot_glm2.rds`
5. Estimand name: "GAD-2 Positive" (instead of "PHQ-2 Positive")

**Model Specification:**
```r
# Load GAD-2 data
gad_data <- readRDS("data/raking/ne25/nhis_gad2_data.rds")

# Recode GAD-2 items (0-3 valid, 7-9 missing)
gad_data <- gad_data %>%
  dplyr::mutate(
    gadanx_recoded = dplyr::if_else(GADANX_parent >= 0 & GADANX_parent <= 3,
                                    GADANX_parent, NA_real_),
    gadworctrl_recoded = dplyr::if_else(GADWORCTRL_parent >= 0 & GADWORCTRL_parent <= 3,
                                        GADWORCTRL_parent, NA_real_)
  )

# Calculate GAD-2 total
gad_data <- gad_data %>%
  dplyr::mutate(
    gad2_total = dplyr::if_else(!is.na(gadanx_recoded) & !is.na(gadworctrl_recoded),
                                gadanx_recoded + gadworctrl_recoded,
                                NA_real_)
  ) %>%
  dplyr::filter(!is.na(gad2_total)) %>%
  dplyr::mutate(gad2_positive = as.numeric(gad2_total >= 3))

# Create modeling dataset
modeling_data <- gad_data
modeling_data$.weights <- gad_data$SAMPWEIGHT_parent

# Fit glm2 model
model_gad2 <- glm2::glm2(
  gad2_positive ~ YEAR,
  data = modeling_data,
  weights = modeling_data$.weights,
  family = binomial()
)

# Predict at 2023
pred_data <- data.frame(YEAR = 2023)
gad2_estimate <- predict(model_gad2, newdata = pred_data, type = "response")[1]

# Create results (constant across ages 0-5)
gad2_result <- data.frame(
  age = 0:5,
  estimand = "GAD-2 Positive",
  estimate = rep(gad2_estimate, 6)
)
```

**Bootstrap Generation:**
```r
# Load shared NHIS bootstrap design (or GAD-2-specific if needed)
boot_design_full <- readRDS("data/raking/ne25/nhis_bootstrap_design.rds")
replicate_weights_full <- boot_design_full$repweights

# Verify row count match
if (nrow(replicate_weights_full) != nrow(gad_data)) {
  stop("ERROR: Bootstrap design row count does not match GAD-2 data!")
}

# Generate bootstrap using helper function
boot_result <- generate_bootstrap_glm2(
  data = modeling_data,
  formula = gad2_positive ~ YEAR,
  replicate_weights = replicate_weights_full,
  pred_data = pred_data
)

# Format bootstrap replicates (replicate across 6 ages)
ages <- 0:5
n_boot <- ncol(boot_result$boot_estimates)

gad2_boot <- data.frame(
  age = rep(ages, times = n_boot),
  estimand = "gad2_positive",
  replicate = rep(1:n_boot, each = length(ages)),
  estimate = rep(as.numeric(boot_result$boot_estimates[1, ]), each = length(ages))
)

# Save outputs
saveRDS(gad2_result, "data/raking/ne25/gad2_estimate_glm2.rds")
saveRDS(gad2_boot, "data/raking/ne25/gad2_estimate_boot_glm2.rds")
```

**Expected Output Files:**
- `data/raking/ne25/gad2_estimate_glm2.rds` (6 rows)
- `data/raking/ne25/gad2_estimate_boot_glm2.rds` (24,576 rows = 6 ages × 4096 replicates)

### Task 3.2: Test GAD-2 Estimation Script

**Command:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/13b_estimate_gad2_glm2.R
```

**Validation:**
```r
# Load point estimates
gad2_est <- readRDS("data/raking/ne25/gad2_estimate_glm2.rds")

cat("Point Estimates:\n")
print(gad2_est)

# Should have 6 rows (ages 0-5)
stopifnot(nrow(gad2_est) == 6)

# All ages should have same estimate (parent characteristic)
stopifnot(length(unique(gad2_est$estimate)) == 1)

# Estimate should be in [0, 1]
stopifnot(all(gad2_est$estimate >= 0 & gad2_est$estimate <= 1))

# Plausibility check (typical GAD-2 positive rates: 5-20%)
if (gad2_est$estimate[1] < 0.03 || gad2_est$estimate[1] > 0.25) {
  warning("GAD-2 estimate outside typical range (3-25%)")
}

# Load bootstrap replicates
gad2_boot <- readRDS("data/raking/ne25/gad2_estimate_boot_glm2.rds")

cat("\nBootstrap Replicates:\n")
cat("  Total rows:", nrow(gad2_boot), "\n")
cat("  Number of replicates:", length(unique(gad2_boot$replicate)), "\n")
cat("  Expected:", 6 * 4096, "=", 24576, "\n")

# Should have 24,576 rows (6 ages × 4096 replicates)
stopifnot(nrow(gad2_boot) == 24576)
```

### Task 3.3: Compare GAD-2 to PHQ-2 Estimates

**Validation Script:**
```r
# Compare GAD-2 and PHQ-2 point estimates
phq2_est <- readRDS("data/raking/ne25/phq2_estimate_glm2.rds")
gad2_est <- readRDS("data/raking/ne25/gad2_estimate_glm2.rds")

cat("Mental Health Estimates (North Central Parents):\n")
cat("  PHQ-2 Positive (Depression):",
    round(phq2_est$estimate[1] * 100, 1), "%\n")
cat("  GAD-2 Positive (Anxiety):",
    round(gad2_est$estimate[1] * 100, 1), "%\n")

# Anxiety typically slightly higher than depression in general population
# But not always - acceptable if within reasonable range
```

### Task 3.4: Load Phase 4 Tasks into Todo List

**Action:** At completion of Phase 3, create todo list with Phase 4 tasks.

---

## Phase 4: Integrate GAD-2 into Consolidation Pipeline

**Goal:** Combine GAD-2 estimates with existing raking targets and bootstrap replicates.

### Task 4.1: Modify `21_consolidate_estimates.R`

**File:** `scripts/raking/ne25/21_consolidate_estimates.R`

**Changes:**

1. **Line 11-18** - Load GAD-2 estimates alongside PHQ-2:
   ```r
   # 1. Load all estimate files
   cat("[1] Loading estimate files...\n")

   acs_est <- readRDS("data/raking/ne25/acs_estimates.rds")
   phq2_est <- readRDS("data/raking/ne25/phq2_estimate_glm2.rds")  # CHANGE FROM nhis_estimates.rds
   gad2_est <- readRDS("data/raking/ne25/gad2_estimate_glm2.rds")  # ADD THIS LINE
   nsch_main_est <- readRDS("data/raking/ne25/nsch_estimates_raw.rds")
   childcare_est <- readRDS("data/raking/ne25/childcare_2022_estimates.rds")

   # Combine NHIS outcomes
   nhis_est <- dplyr::bind_rows(phq2_est, gad2_est)  # ADD THIS LINE

   # Combine NSCH outcomes
   nsch_est <- dplyr::bind_rows(nsch_main_est, childcare_est)
   ```

2. **Lines 22-36** - Update expected row counts:
   ```r
   cat("    ACS estimates:", nrow(acs_est), "rows\n")
   cat("    NHIS estimates:", nrow(nhis_est), "rows\n")  # Should show 12
   cat("    NSCH estimates:", nrow(nsch_est), "rows\n")
   cat("    Expected total: 186 rows\n\n")  # CHANGE FROM 180

   # Verify row counts
   if (nrow(acs_est) != 150) {
     stop("ERROR: ACS should have 150 rows (25 estimands × 6 ages), got ", nrow(acs_est))
   }
   if (nrow(nhis_est) != 12) {  # CHANGE FROM 6
     stop("ERROR: NHIS should have 12 rows (2 estimands × 6 ages), got ", nrow(nhis_est))
   }
   if (nrow(nsch_est) != 24) {
     stop("ERROR: NSCH should have 24 rows (4 estimands × 6 ages), got ", nrow(nsch_est))
   }
   ```

3. **Line 71** - Update total row count check:
   ```r
   # Verify total
   if (nrow(all_estimates) != 186) {  # CHANGE FROM 180
     stop("ERROR: Expected 186 total rows, got ", nrow(all_estimates))
   }
   ```

4. **Line 126-140** - Update summary statistics:
   ```r
   cat("\n========================================\n")
   cat("Phase 5: Summary\n")
   cat("========================================\n\n")

   summary_stats <- all_estimates %>%
     dplyr::group_by(data_source) %>%
     dplyr::summarise(
       n_rows = dplyr::n(),
       n_estimands = length(unique(estimand)),
       .groups = "drop"
     )

   print(summary_stats)
   # Should show: ACS 150 rows (25 estimands), NHIS 12 rows (2 estimands), NSCH 24 rows (4 estimands)

   cat("\nTotal rows:", nrow(all_estimates), "\n")        # 186
   cat("Total estimands:", length(unique(all_estimates$estimand)), "\n")  # 31
   ```

### Task 4.2: Test Modified Consolidation Script

**Command:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/21_consolidate_estimates.R
```

**Expected Output:**
```
[1] Loading estimate files...
    ACS estimates: 150 rows
    NHIS estimates: 12 rows
    NSCH estimates: 24 rows
    Expected total: 186 rows

    [OK] All row counts verified

...

Phase 5: Summary
========================================

# A tibble: 3 × 3
  data_source n_rows n_estimands
  <chr>        <int>       <int>
1 ACS            150          25
2 NHIS            12           2
3 NSCH            24           4

Total rows: 186
Total estimands: 31
```

### Task 4.3: Modify `21b_consolidate_nsch_boot.R`

**File:** `scripts/raking/ne25/21b_consolidate_nsch_boot.R`

**Changes:**

1. **Load GAD-2 bootstrap replicates alongside PHQ-2:**
   ```r
   # Load bootstrap replicates from each source
   cat("[1] Loading bootstrap replicate files...\n")

   acs_boot <- readRDS("data/raking/ne25/acs_estimates_boot_glm2.rds")
   phq2_boot <- readRDS("data/raking/ne25/phq2_estimate_boot_glm2.rds")  # CHANGE NAME
   gad2_boot <- readRDS("data/raking/ne25/gad2_estimate_boot_glm2.rds")  # ADD THIS
   nsch_boot <- readRDS("data/raking/ne25/nsch_estimates_boot_glm2.rds")

   # Combine NHIS bootstrap replicates
   nhis_boot <- dplyr::bind_rows(phq2_boot, gad2_boot)  # ADD THIS
   ```

2. **Update expected row counts:**
   ```r
   cat("    ACS bootstrap:", nrow(acs_boot), "rows\n")
   cat("    NHIS bootstrap:", nrow(nhis_boot), "rows\n")  # Should show 49,152
   cat("    NSCH bootstrap:", nrow(nsch_boot), "rows\n")

   # Verify row counts
   if (nrow(acs_boot) != 614400) {  # 150 rows × 4096 replicates
     stop("ERROR: Expected 614,400 ACS bootstrap rows, got ", nrow(acs_boot))
   }
   if (nrow(nhis_boot) != 49152) {  # CHANGE FROM 24,576 (12 rows × 4096 replicates)
     stop("ERROR: Expected 49,152 NHIS bootstrap rows, got ", nrow(nhis_boot))
   }
   if (nrow(nsch_boot) != 98304) {  # 24 rows × 4096 replicates
     stop("ERROR: Expected 98,304 NSCH bootstrap rows, got ", nrow(nsch_boot))
   }
   ```

3. **Update total row count:**
   ```r
   # Verify total
   expected_total <- 614400 + 49152 + 98304  # = 761,856  (CHANGE FROM 737,280)
   if (nrow(all_boot) != expected_total) {
     stop("ERROR: Expected ", expected_total, " total bootstrap rows, got ", nrow(all_boot))
   }
   ```

### Task 4.4: Test Bootstrap Consolidation Script

**Command:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/21b_consolidate_nsch_boot.R
```

**Expected Output:**
```
[1] Loading bootstrap replicate files...
    ACS bootstrap: 614400 rows
    NHIS bootstrap: 49152 rows
    NSCH bootstrap: 98304 rows

    [OK] All row counts verified

...

Total bootstrap rows: 761856
```

### Task 4.5: Load Phase 5 Tasks into Todo List

**Action:** At completion of Phase 4, create todo list with Phase 5 tasks.

---

## Phase 5: Update Pipeline Orchestration & Documentation

**Goal:** Integrate GAD-2 estimation into main pipeline script and update documentation.

### Task 5.1: Modify `run_raking_targets_pipeline.R`

**File:** `scripts/raking/ne25/run_raking_targets_pipeline.R`

**Changes:**

Add GAD-2 estimation step after PHQ-2:

```r
# Phase 3: NHIS Estimates
cat("\n" ,"=".repeat(50), "\n", sep = "")
cat("PHASE 3: NHIS ESTIMATES\n")
cat("=".repeat(50), "\n\n", sep = "")

cat("Task 3.1: Filter NHIS Parents (North Central Region)\n")
source("scripts/raking/ne25/12_filter_nhis_parents.R")

cat("\nTask 3.1a: Create Shared NHIS Bootstrap Design\n")
source("scripts/raking/ne25/12a_create_nhis_bootstrap_design.R")

cat("\nTask 3.2: Estimate PHQ-2 Depression (GLM2 with Bootstrap)\n")
source("scripts/raking/ne25/13_estimate_phq2_glm2.R")

# ADD THIS SECTION
cat("\nTask 3.3: Estimate GAD-2 Anxiety (GLM2 with Bootstrap)\n")
source("scripts/raking/ne25/13b_estimate_gad2_glm2.R")
```

**Note:** Task numbering may need adjustment - PHQ-2 is currently 4.1, so GAD-2 should be 4.2.

### Task 5.2: Test Full Pipeline End-to-End

**Command:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R
```

**Validation Checks:**
1. Pipeline completes without errors
2. Final database table has 186 rows (not 180)
3. 31 unique estimands (not 30)
4. Both "PHQ-2 Positive" and "GAD-2 Positive" estimands present

### Task 5.3: Update Documentation

**Files to Update:**

1. **`docs/raking/ne25/RAKING_TARGETS_ESTIMATION_PLAN.md`**
   - Update overview: 31 estimands (not 30), 186 rows (not 180)
   - Add new section "Phase 3B: NHIS GAD-2 Anxiety Estimate (1 estimand)"
   - Update data sources table
   - Add GAD-2 variables and scoring description

2. **`docs/raking/ne25/GLM2_REFACTORING_PROGRESS.md`**
   - Add GAD-2 to completed estimands list
   - Update summary statistics

3. **`docs/QUICK_REFERENCE.md`** (if needed)
   - Update raking targets pipeline description

4. **`CLAUDE.md`** (project root)
   - Update "Raking Targets Pipeline - Complete" section
   - Change from "180 raking targets (30 estimands)" to "186 raking targets (31 estimands)"
   - Update NHIS description to mention both PHQ-2 and GAD-2

**Example Documentation Update:**

````markdown
## Phase 3B: NHIS GAD-2 Anxiety Estimate (1 estimand)

### Data Source
- **Table:** `nhis_raw`
- **Sample:** ~15,000 North Central region parents with children 0-5 (years 2019, 2022)
- **Weights:** `SAMPWEIGHT` (parent adult weight)
- **Filter:** `REGION = 2` (North Central/Midwest)

### Estimation Method: glm2 Binomial Model

**Approach:** Same methodology as PHQ-2 (parent mental health characteristic)

### Variables

**GAD-2 Items:**
- **GADANX** - "Feeling nervous, anxious, or on edge"
- **GADWORCTRL** - "Not being able to stop or control worrying"

**Coding:** 0-3 scale (0=Not at all, 1=Several days, 2=More than half, 3=Nearly every day)

**Scoring:**
- GAD-2 Total = GADANX + GADWORCTRL (range 0-6)
- Positive screen = GAD-2 ≥ 3
- Clinical interpretation: Sensitivity 86%, Specificity 83% for GAD

### Estimand

**"GAD-2 Positive"** - Proportion of parents with positive anxiety screen (GAD-2 ≥3)

**Model Specification:**
```r
model_gad2 <- glm2::glm2(
  gad2_positive ~ YEAR,
  data = modeling_data,
  weights = SAMPWEIGHT_parent,
  family = binomial()
)

# Predict at YEAR = 2023 for ages 0-5
pred_data <- data.frame(YEAR = 2023)
gad2_estimate <- predict(model_gad2, newdata = pred_data, type = "response")
```

**Bootstrap:** Rao-Wu-Yue-Beaumont bootstrap (4096 replicates) using shared NHIS design

**Constant across child ages 0-5** (parent characteristic)

**Fills rows:** Age 0-5 (6 values, all identical)
````

### Task 5.4: Final Validation

**Comprehensive End-to-End Test:**

```r
# 1. Load final raking targets
library(DBI)
library(duckdb)

con <- DBI::dbConnect(
  duckdb::duckdb(),
  dbdir = "data/duckdb/kidsights_local.duckdb",
  read_only = TRUE
)

targets <- DBI::dbGetQuery(con, "SELECT * FROM raking_targets_ne25")
DBI::dbDisconnect(con, shutdown = TRUE)

# 2. Verify GAD-2 presence
cat("Total rows:", nrow(targets), "\n")  # Should be 186
cat("Total estimands:", length(unique(targets$estimand)), "\n")  # Should be 31

# 3. Check GAD-2 specifically
gad2_targets <- targets %>% dplyr::filter(estimand == "GAD-2 Positive")

cat("\nGAD-2 Positive Targets:\n")
print(gad2_targets %>% dplyr::select(age_years, estimand, estimate, data_source))

# Should show 6 rows (ages 0-5) with identical estimates

# 4. Compare mental health estimands
mh_targets <- targets %>%
  dplyr::filter(estimand %in% c("PHQ-2 Positive", "GAD-2 Positive"))

cat("\nMental Health Estimands:\n")
print(mh_targets %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(
    n_ages = dplyr::n(),
    mean_est = mean(estimate),
    .groups = "drop"
  ))

# Both should have 6 ages, estimates in reasonable range (3-20%)
```

### Task 5.5: Create Completion Summary

**Generate Final Report:**

```markdown
# GAD-2 Insertion - Completion Summary

**Date:** [INSERT DATE]
**Status:** ✓ Complete

## Implementation Results

### Files Created
- `scripts/raking/ne25/12b_score_gad2.R` (if needed for Option B)
- `scripts/raking/ne25/13b_estimate_gad2_glm2.R`
- `docs/raking/ne25/GAD2_INSERTION_PLAN.md`

### Files Modified
- `scripts/raking/ne25/12_filter_nhis_parents.R` - Added GAD-2 variable extraction
- `scripts/raking/ne25/21_consolidate_estimates.R` - Integrated GAD-2 point estimates
- `scripts/raking/ne25/21b_consolidate_nsch_boot.R` - Integrated GAD-2 bootstrap replicates
- `scripts/raking/ne25/run_raking_targets_pipeline.R` - Added GAD-2 estimation step
- Documentation files (RAKING_TARGETS_ESTIMATION_PLAN.md, GLM2_REFACTORING_PROGRESS.md, CLAUDE.md)

### Data Files Created
- `data/raking/ne25/nhis_gad2_data.rds` - Filtered parent-child pairs with GAD-2
- `data/raking/ne25/nhis_gad2_scored.rds` - Scored GAD-2 data (if separate from estimation)
- `data/raking/ne25/gad2_estimate_glm2.rds` - Point estimates (6 rows)
- `data/raking/ne25/gad2_estimate_boot_glm2.rds` - Bootstrap replicates (24,576 rows)

### Database Updates
- `raking_targets_ne25` table: 180→186 rows
- Bootstrap replicates: 737,280→761,856 rows

## Final Statistics

| Metric | Value |
|--------|-------|
| **Total Raking Targets** | 186 rows |
| **Total Estimands** | 31 |
| **NHIS Estimands** | 2 (PHQ-2, GAD-2) |
| **GAD-2 Sample Size** | ~[INSERT N] parents |
| **GAD-2 Positive Rate** | [INSERT %] |
| **Bootstrap Replicates** | 4,096 |
| **Total Bootstrap Rows** | 761,856 |

## Validation Checks

- [x] Pipeline executes without errors
- [x] GAD-2 estimates in plausible range (3-20%)
- [x] Bootstrap replicates properly formatted
- [x] Database updated correctly
- [x] Documentation updated
- [x] All tests pass

## Next Steps

None - GAD-2 integration complete and ready for production use.
```

---

## Testing Strategy

### Incremental Testing Approach

Each phase includes validation steps to catch errors early:

| Phase | Test Type | Key Checks |
|-------|-----------|------------|
| **Phase 1** | Data availability | GAD-2 variables present, sample size matches PHQ-2 |
| **Phase 2** | Scoring validation | GAD-2 totals in range 0-6, positive rate plausible |
| **Phase 3** | Model estimation | Point estimates in [0,1], bootstrap replicates generated |
| **Phase 4** | Integration | Row counts correct, no duplicate keys |
| **Phase 5** | End-to-end | Full pipeline runs, database updated correctly |

### Rollback Plan

If issues are encountered:

1. **Phase 1-2 Issues:** Check NHIS data extraction, verify GAD variables present
2. **Phase 3 Issues:** Compare to PHQ-2 script line-by-line, check for typos
3. **Phase 4 Issues:** Verify file paths, check row count arithmetic
4. **Phase 5 Issues:** Run individual scripts to isolate failure point

---

## Summary

This plan breaks GAD-2 insertion into 5 incremental phases with testing at each stage. The implementation closely mirrors the existing PHQ-2 pipeline, minimizing risk of errors. Total estimated time: 2-3 hours for implementation + testing.

**Key Success Factors:**
1. Reuse existing PHQ-2 code as template (proven approach)
2. Test incrementally after each phase
3. Validate sample sizes match expectations
4. Check plausibility of estimates (anxiety typically 5-20% in general population)
5. Verify bootstrap row counts match expected (6 ages × 4096 replicates = 24,576)

**Final Deliverable:** 186 raking targets (31 estimands) with full bootstrap variance estimation, ready for post-stratification weighting of NE25 survey data.

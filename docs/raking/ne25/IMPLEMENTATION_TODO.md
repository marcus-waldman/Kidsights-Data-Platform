# NE25 Raking Targets Implementation - Task List

**Purpose:** Complete implementation of raking targets estimation for NE25 survey data post-stratification

**Last Updated:** 2025-10-03
**Status:** Phase 1 - Not Started

---

## Overview

This document tracks the implementation of 34 raking target estimands (204 total rows) from three data sources:
- **ACS:** 26 estimands (156 rows) - Demographics, SES
- **NHIS:** 4 estimands (24 rows) - Parent mental health, ACEs
- **NSCH:** 4 estimands (24 rows) - Child health outcomes

**Total Deliverable:** Database table `raking_targets_ne25` with 204 rows + metadata

---

## Phase 1: Setup and Data Preparation

**Goal:** Load data, verify quality, prepare analysis environment

### Tasks

- [ ] **1.1: Create project directory structure**
  - Create `scripts/raking/ne25/` directory
  - Create `data/raking/ne25/` directory for intermediate outputs
  - Create `validation/raking/ne25/` directory for validation reports

- [ ] **1.2: Load and verify ACS data**
  - Load Nebraska ACS data (2019-2023) from database
  - Verify expected sample size (6,657 children ages 0-5)
  - Check for missing values in key variables (POVERTY, PUMA, EDUC_MOM, MARST_HEAD)
  - Verify CLUSTER, STRATA, PERWT variables present

- [ ] **1.3: Load and verify NHIS data**
  - Load NHIS data (2019-2024) from database
  - Perform household linkage (parents → children 0-5)
  - Filter to North Central region (REGION = 2)
  - Verify expected sample sizes:
    - PHQ-2 data (2019, 2022): ~4,022 parents
    - ACE data (2019, 2021-2023): ~7,657 parents
  - Check for missing values in PHQ items (PHQINTR, PHQDEP)

- [ ] **1.4: Load and verify NSCH data**
  - Load NSCH 2023 data from database
  - Filter to Nebraska (FIPSST = 31) and ages 0-5
  - Verify expected sample size (~21,524 children)
  - Check variable availability by age (MEDB10ScrQ5_23 only ages 3+)

- [ ] **1.5: Create analysis helper functions**
  - Write `fit_glm_estimates()` function (binary GLM with age × year interaction)
  - Write `fit_multinomial_estimates()` function (survey-weighted multinomial)
  - Write validation functions for checking estimates

- [ ] **1.6: Document data preparation**
  - Create `data/raking/ne25/data_preparation_log.md`
  - Document sample sizes, exclusions, missing data patterns
  - Record any data quality issues discovered

- [ ] **1.7: PHASE 1 VERIFICATION**
  - ✓ Verify all Phase 1 tasks marked complete
  - ✓ Review data preparation log for completeness
  - ✓ Load Phase 2 tasks into Claude todo list
  - ✓ Update status header to "Phase 2 - In Progress"

---

## Phase 2: ACS Estimates (26 estimands, 156 rows)

**Goal:** Compute all ACS-based raking targets using survey-weighted models

### Tasks

- [ ] **2.1: Create survey design object**
  - Create `svydesign()` object with CLUSTER, STRATA, PERWT
  - Filter to Nebraska children ages 0-5
  - Save design object for reuse

- [ ] **2.2: Estimate sex distribution (1 estimand)**
  - Fit GLM: `I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR`
  - Test interaction significance
  - Extract predictions at 2023 for ages 0-5
  - Expected: ~51% male (constant across ages)

- [ ] **2.3: Estimate race/ethnicity (3 estimands)**
  - White non-Hispanic: `I((RACE == 1) & (HISPAN == 0))`
  - Black any: `I(RACE == 2)`
  - Hispanic any: `I(HISPAN >= 1)`
  - Fit 3 separate GLMs with age × year interaction
  - Verify estimates are plausible for Nebraska

- [ ] **2.4: Estimate Federal Poverty Level (5 estimands, multinomial)**
  - Create FPL category variable (5 levels: 0-99%, 100-199%, 200-299%, 300-399%, 400%+)
  - Filter POVERTY < 600 (exclude missing)
  - Fit `survey::svymultinom(fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR)`
  - Extract 6×5 matrix of predictions (ages × categories)
  - **Validate:** Each row sums to 1.0

- [ ] **2.5: Estimate PUMA geography (14 estimands, multinomial)**
  - Create PUMA factor with all 14 Nebraska PUMAs
  - Fit `survey::svymultinom(puma_factor ~ AGE + MULTYEAR + AGE:MULTYEAR)`
  - Extract 6×14 matrix of predictions
  - **Validate:** Each row sums to 1.0

- [ ] **2.6: Estimate mother's education (1 estimand, age-stratified)**
  - Filter to children with mother linked (MOMLOC > 0)
  - Fit GLM: `I(EDUC_MOM >= 10) ~ AGE + MULTYEAR + AGE:MULTYEAR`
  - Extract 6 age-specific predictions
  - Expected: 44-47% across ages (varies by age)

- [ ] **2.7: Estimate mother's marital status (1 estimand, age-stratified)**
  - Filter to children with mother linked (MOMLOC > 0)
  - Fit GLM: `I(MARST_HEAD == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR`
  - Extract 6 age-specific predictions
  - Expected: 79-84% married across ages (varies by age)

- [ ] **2.8: Compile ACS estimates**
  - Combine all estimates into single data structure
  - Create age × estimand matrix (6 rows, 26 columns)
  - Expand to full 156 rows (replicating constant estimates across ages)

- [ ] **2.9: Validate ACS estimates**
  - Range check: All values in [0, 1]
  - Sum checks: FPL sums to 1.0, PUMA sums to 1.0
  - Age pattern check: 24 estimands constant, 2 vary by age
  - Compare to published ACS tables (sex, race, poverty for "Under 5" category)

- [ ] **2.10: Save ACS estimates**
  - Save as `data/raking/ne25/acs_estimates.rds`
  - Include both estimates and model objects
  - Document which models used interactions vs. main effects only

- [ ] **2.11: PHASE 2 VERIFICATION**
  - ✓ Verify all Phase 2 tasks marked complete
  - ✓ Review ACS validation report
  - ✓ Confirm 156 rows generated with plausible values
  - ✓ Load Phase 3 tasks into Claude todo list
  - ✓ Update status header to "Phase 3 - In Progress"

---

## Phase 3: NHIS Estimates (4 estimands, 24 rows)

**Goal:** Compute NHIS-based parent mental health and ACE targets

### Tasks

- [ ] **3.1: Filter to North Central region parents**
  - Perform household linkage (parents → children 0-5)
  - Filter to REGION = 2 (North Central)
  - Filter to ISPARENTSC = 1, CSTATFLG = 0
  - Document final sample size by year

- [ ] **3.2: Estimate PHQ-2 depression (1 estimand, binary)**
  - Filter to 2019, 2022 (years with PHQ items)
  - Recode PHQINTR and PHQDEP from 1-4 scale to 0-3 scale
  - Calculate PHQ-2 total (0-6)
  - Create binary outcome: PHQ-2 ≥3 (positive screen)
  - Create survey design with PSU, STRATA, SAMPWEIGHT
  - Fit `svyglm(phq2_positive ~ 1, family = quasibinomial())`
  - Extract single probability estimate
  - Expected: 5-15% positive (based on national rates)

- [ ] **3.3: Estimate maternal ACEs (3 estimands, multinomial)**
  - Filter to 2019, 2021, 2022, 2023 (years with ACE items)
  - Calculate ACE total from 8 items (VIOLENEV, JAILEV, etc.)
  - Create 3-category variable: 0 ACEs, 1 ACE, 2+ ACEs
  - Create survey design
  - Fit `survey::svymultinom(ace_category ~ 1)`
  - Extract 3 probability estimates
  - **Validate:** Sum to 1.0
  - Expected distribution: ~40-50% zero, ~25-30% one, ~20-30% 2+

- [ ] **3.4: Compile NHIS estimates**
  - Combine PHQ-2 and ACE estimates
  - Expand to 24 rows (4 estimands × 6 ages)
  - Note: All NHIS estimates constant across child ages

- [ ] **3.5: Validate NHIS estimates**
  - Range check: All values in [0, 1]
  - Sum check: ACE categories sum to 1.0
  - Age pattern check: All 4 estimands constant across ages
  - Compare PHQ-2 rate to published NHIS depression statistics (if available)

- [ ] **3.6: Save NHIS estimates**
  - Save as `data/raking/ne25/nhis_estimates.rds`
  - Include model objects and sample sizes by year
  - Document regional vs. state limitation

- [ ] **3.7: PHASE 3 VERIFICATION**
  - ✓ Verify all Phase 3 tasks marked complete
  - ✓ Review NHIS validation report
  - ✓ Confirm 24 rows generated with plausible values
  - ✓ Load Phase 4 tasks into Claude todo list
  - ✓ Update status header to "Phase 4 - In Progress"

---

## Phase 4: NSCH Estimates (4 estimands, 24 rows)

**Goal:** Compute NSCH-based child health and developmental targets

### Tasks

- [ ] **4.1: Filter to Nebraska children ages 0-5**
  - Load NSCH 2023 data
  - Filter to FIPSST = 31, ages 0-5
  - Verify sample size by age bin
  - Identify appropriate survey weight variable

- [ ] **4.2: Estimate child ACE exposure (1 estimand, age-stratified)**
  - Use composite indicator `ACE1more_23` (or build from items)
  - Fit separate model for each age 0-5
  - Model: State-level mixed model with `(1|FIPSST)`
  - Extract 6 age-specific predictions for Nebraska
  - Expected: Increases with age (older children have more exposure time)

- [ ] **4.3: Estimate emotional/behavioral problems (1 estimand, ages 3-5 only)**
  - Use `MEDB10ScrQ5_23` variable
  - Note: Only available for ages 3-17
  - Fit models for ages 3, 4, 5 only
  - Set ages 0, 1, 2 to NA (not measured)
  - Extract 3 non-missing predictions

- [ ] **4.4: Estimate excellent health (1 estimand, age-stratified)**
  - Use `K2Q01 == 1` (Excellent health rating)
  - Fit separate model for each age 0-5
  - Extract 6 age-specific predictions
  - Expected: 50-70% rated excellent, may decrease slightly with age

- [ ] **4.5: Estimate child care utilization (1 estimand, age-stratified)**
  - Use `Care10hrs_23` (10+ hours/week non-parental care)
  - Fit separate model for each age 0-5
  - Extract 6 age-specific predictions
  - Expected: Increases with age (more children in preschool/daycare)

- [ ] **4.6: Compile NSCH estimates**
  - Combine all 4 estimands
  - Create 6×4 matrix (ages × estimands)
  - Handle NA values for emotional/behavioral (ages 0-2)

- [ ] **4.7: Validate NSCH estimates**
  - Range check: All values in [0, 1] or NA
  - Age pattern check: All should vary by age (not constant)
  - Compare to published NSCH Nebraska state profiles
  - Verify NA pattern for emotional/behavioral (only ages 0-2)

- [ ] **4.8: Save NSCH estimates**
  - Save as `data/raking/ne25/nsch_estimates.rds`
  - Include model objects and age-specific sample sizes
  - Document NA handling for emotional/behavioral variable

- [ ] **4.9: PHASE 4 VERIFICATION**
  - ✓ Verify all Phase 4 tasks marked complete
  - ✓ Review NSCH validation report
  - ✓ Confirm 24 rows generated (some with NA)
  - ✓ Load Phase 5 tasks into Claude todo list
  - ✓ Update status header to "Phase 5 - In Progress"

---

## Phase 5: Consolidation and Database Storage

**Goal:** Combine all estimates, create database table, ensure data quality

### Tasks

- [ ] **5.1: Load all estimate files**
  - Load `acs_estimates.rds` (156 rows)
  - Load `nhis_estimates.rds` (24 rows)
  - Load `nsch_estimates.rds` (24 rows)
  - Verify total = 204 rows

- [ ] **5.2: Create unified raking targets data frame**
  - Create data.frame with columns:
    - `target_id` (1-204, primary key)
    - `survey` (character: "ne25")
    - `age_years` (integer: 0-5)
    - `estimand` (character: description)
    - `data_source` (character: "ACS", "NHIS", "NSCH")
    - `estimator` (character: "GLM", "Multinomial", "GLMM")
    - `estimate` (numeric: probability 0-1 or NA)
    - `se` (numeric: standard error, if available)
    - `lower_ci` (numeric: 95% lower bound)
    - `upper_ci` (numeric: 95% upper bound)
    - `sample_size` (integer: effective sample size)
    - `estimation_date` (date: when computed)
    - `notes` (character: any special considerations)

- [ ] **5.3: Populate estimand descriptions**
  - Match estimates to standardized descriptions
  - Examples:
    - "Proportion of children who are male"
    - "Proportion at 0-99% Federal Poverty Level"
    - "Proportion of mothers with moderate/severe depression (PHQ-2 ≥3)"
  - Ensure descriptions are consistent and informative

- [ ] **5.4: Add confidence intervals**
  - Extract SE from model objects where available
  - Calculate 95% CI: estimate ± 1.96*SE on logit scale, back-transform
  - Note: Some multinomial estimates may need special CI calculation

- [ ] **5.5: Perform final validation**
  - **Completeness:** 204 rows, all required columns present
  - **Range:** All estimates in [0, 1] or NA (for NSCH emotional ages 0-2)
  - **Consistency:**
    - FPL categories sum to 1.0 for each age
    - PUMA categories sum to 1.0 for each age
    - ACE categories sum to 1.0 for each age
  - **Age patterns:**
    - ACS (24 estimands): constant across ages, except mother ed/marital
    - NHIS (4 estimands): constant across ages
    - NSCH (4 estimands): vary by age
  - **Missing data:** Only 18 NA values (NSCH emotional, ages 0-2)

- [ ] **5.6: Create database table schema**
  - Write SQL DDL for `raking_targets_ne25` table
  - Define appropriate data types
  - Set `target_id` as primary key
  - Add indexes on: `estimand`, `data_source`, `age_years`
  - Add CHECK constraint: `estimate BETWEEN 0 AND 1 OR estimate IS NULL`

- [ ] **5.7: Insert data into database**
  - Connect to DuckDB: `kidsights_local.duckdb`
  - Create table using schema
  - Insert 204 rows from data frame
  - Verify row count: `SELECT COUNT(*) FROM raking_targets_ne25`
  - Verify no duplicates on `(survey, age_years, estimand)`

- [ ] **5.8: Create database indexes**
  - `CREATE INDEX idx_raking_ne25_estimand ON raking_targets_ne25(estimand)`
  - `CREATE INDEX idx_raking_ne25_source ON raking_targets_ne25(data_source)`
  - `CREATE INDEX idx_raking_ne25_age ON raking_targets_ne25(age_years)`

- [ ] **5.9: Test database queries**
  - Query all ACS estimates
  - Query estimates for a specific age
  - Query estimates for a specific estimand across all ages
  - Verify joins work with other tables if needed

- [ ] **5.10: PHASE 5 VERIFICATION**
  - ✓ Verify all Phase 5 tasks marked complete
  - ✓ Confirm database table exists with 204 rows
  - ✓ Run and pass all validation queries
  - ✓ Load Phase 6 tasks into Claude todo list
  - ✓ Update status header to "Phase 6 - In Progress"

---

## Phase 6: Metadata and Documentation

**Goal:** Document methodology, create metadata, generate validation reports

### Tasks

- [ ] **6.1: Create table metadata file**
  - Create `docs/raking/ne25/table_metadata.json`
  - Include:
    - Table name, creation date, purpose
    - Column descriptions (all 13 columns)
    - Estimation methodology summary
    - Data source details (ACS 2019-2023, NHIS 2019-2024, NSCH 2023)
    - Known limitations (NHIS regional proxy, NSCH age restrictions)

- [ ] **6.2: Generate validation report**
  - Create `validation/raking/ne25/validation_report.md`
  - Include:
    - Summary statistics (mean, min, max by data source)
    - Validation test results (sum checks, range checks, pattern checks)
    - Comparison to external benchmarks where available
    - Flags for any estimates requiring review
    - Plots: Distribution of estimates by source, age patterns

- [ ] **6.3: Document estimation procedures**
  - Create `docs/raking/ne25/ESTIMATION_PROCEDURES.md`
  - Include:
    - Step-by-step walkthrough of each phase
    - R code snippets for key models
    - Decisions made during implementation
    - Deviations from original plan (if any)
    - Lessons learned for future surveys

- [ ] **6.4: Create data dictionary**
  - Create `docs/raking/ne25/data_dictionary.md`
  - Document each of the 34 estimands:
    - Full description
    - Data source and years
    - Sample size
    - Estimation method
    - Expected value range
    - Any age variation
    - Known limitations

- [ ] **6.5: Generate summary statistics**
  - Create `validation/raking/ne25/summary_statistics.csv`
  - For each estimand:
    - Min, max, mean estimate across ages
    - Standard deviation of estimate across ages
    - Median SE (if available)
    - Sample size

- [ ] **6.6: Create comparison plots**
  - Generate plots comparing:
    - ACS estimates vs. published ACS tables (where possible)
    - NSCH estimates vs. published state profiles (where possible)
    - Age patterns for age-varying estimands
  - Save as PNG in `validation/raking/ne25/plots/`

- [ ] **6.7: Update main documentation**
  - Update `README.md` in `docs/raking/ne25/`
  - Add quick reference guide for using the raking targets
  - Link to all documentation files
  - Provide example queries for common use cases

- [ ] **6.8: Create user guide**
  - Create `docs/raking/ne25/USER_GUIDE.md`
  - Explain:
    - What raking targets are and why they matter
    - How to query the database table
    - How to interpret the estimates
    - How to apply raking to NE25 survey data
    - Troubleshooting common issues

- [ ] **6.9: Archive intermediate files**
  - Move all `.rds` files to `data/raking/ne25/archive/`
  - Keep only final database table as source of truth
  - Document what's archived and why

- [ ] **6.10: Create project completion report**
  - Create `docs/raking/ne25/COMPLETION_REPORT.md`
  - Include:
    - Summary of deliverables
    - Timeline of phases
    - Key findings and insights
    - Quality metrics (all validation checks passed)
    - Next steps (applying to NE25 data)
    - Recommendations for future iterations

- [ ] **6.11: PHASE 6 VERIFICATION**
  - ✓ Verify all Phase 6 tasks marked complete
  - ✓ Review all documentation files for completeness
  - ✓ Confirm all validation reports generated
  - ✓ Run final smoke test (query database, verify results)
  - ✓ Mark project as COMPLETE

---

## Phase 7: Final Review and Handoff

**Goal:** Final quality checks, peer review, project handoff

### Tasks

- [ ] **7.1: Conduct internal peer review**
  - Have colleague review methodology documentation
  - Review statistical methods document
  - Check for any errors or inconsistencies
  - Incorporate feedback

- [ ] **7.2: Test end-to-end raking procedure**
  - Load NE25 survey data
  - Load raking targets from database
  - Run sample raking algorithm
  - Verify weights adjust to match targets
  - Document any issues encountered

- [ ] **7.3: Create reproducibility checklist**
  - Document all software versions used
  - List all R/Python packages with versions
  - Provide environment setup instructions
  - Test reproduction on clean environment

- [ ] **7.4: Final database backup**
  - Export `raking_targets_ne25` table to CSV
  - Save as `data/raking/ne25/raking_targets_ne25_final.csv`
  - Create database dump for archival

- [ ] **7.5: Update project-level documentation**
  - Update `CLAUDE.md` with raking targets info
  - Update `docs/QUICK_REFERENCE.md` with raking queries
  - Add entry to `docs/architecture/PIPELINE_OVERVIEW.md`

- [ ] **7.6: Create presentation materials**
  - Create slides summarizing methodology
  - Prepare 5-min overview for team meeting
  - Highlight key findings and quality metrics

- [ ] **7.7: FINAL VERIFICATION**
  - ✓ All 7 phases complete
  - ✓ Database table verified (204 rows)
  - ✓ All documentation complete
  - ✓ Reproducibility tested
  - ✓ Project marked COMPLETE
  - ✓ Update status header to "COMPLETE"

---

## Progress Tracking

### Phase Status
- [ ] Phase 1: Setup and Data Preparation
- [ ] Phase 2: ACS Estimates
- [ ] Phase 3: NHIS Estimates
- [ ] Phase 4: NSCH Estimates
- [ ] Phase 5: Consolidation and Database
- [ ] Phase 6: Metadata and Documentation
- [ ] Phase 7: Final Review and Handoff

### Key Metrics
- **Total Tasks:** 71
- **Completed:** 0
- **In Progress:** 0
- **Blocked:** 0
- **Estimated Duration:** 8-12 hours across 2-3 days

### Current Blockers
*(None - Ready to start)*

---

## Notes and Decisions Log

### 2025-10-03
- Created comprehensive 7-phase implementation plan
- Total scope: 71 tasks across data wrangling, estimation, database, metadata, and documentation
- Key decision: Use PHQ-2 binary (not PHQ-8) to match NE25 survey measure
- Key decision: NHIS uses direct regional filtering (not random effects)
- Key decision: Multinomial logit for all categorical variables (FPL, PUMA, ACEs)

---

**Next Action:** Begin Phase 1, Task 1.1 - Create project directory structure

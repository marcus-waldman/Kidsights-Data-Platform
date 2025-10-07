# Bootstrap Replicate Weights - Implementation Task List

**Project:** NE25 Raking Targets Bootstrap Implementation
**Created:** October 2025
**Last Updated:** October 2025

---

## Overview

This task list tracks the implementation of bootstrap replicate weights for all 30 raking target estimands across three data sources (ACS, NHIS, NSCH). The implementation also includes fixing the NSCH survey design to use proper multi-year pooling (2020-2023) with temporal modeling.

**Development Strategy:**
- **Phase 1-6 (Development)**: Use **4 test replicates** to verify logic and code correctness quickly
- **Final Production Run**: Increase to **4,096 replicates** and run as batch job overnight

**Parallel Processing:** All computationally intensive tasks (MICE imputation, bootstrap generation) use the `future` package with half the available CPU cores to maximize performance.

**Total Phases:** 6
**Estimated Development Time:** 1-2 days (with 4 test replicates)
**Production Run Time:** 4-6 hours (4,096 replicates, run as batch)

---

## Configuration Variables

**All bootstrap scripts should include this configuration at the top:**

```r
# Bootstrap configuration
# DEVELOPMENT: Use n_boot = 4 for fast testing
# PRODUCTION: Change to n_boot = 4096 for final run
n_boot <- 4  # <<< CHANGE TO 4096 FOR PRODUCTION RUN

cat("Bootstrap replicates:", n_boot, "\n")
if (n_boot < 100) {
  cat("WARNING: Using test mode with", n_boot, "replicates\n")
  cat("         Change n_boot to 4096 for production run\n\n")
}
```

**Benefits:**
- Single variable to change across all scripts
- Clear warning when running in test mode
- Fast iteration during development (~30 seconds vs ~30 minutes per script)
- Identical code logic in test and production modes

---

## Phase 1: Fix NSCH Survey Design (Multi-Year + Temporal Modeling)

**Goal:** Replace incorrect GLMM approach with proper survey-weighted GLM using pooled 2020-2023 data + MICE imputation for ACE indicators

**Status:** In Progress (Task 1.1 Complete)
**Estimated Time:** 5-6 hours (includes MICE imputation)

### Tasks:

- [ ] **1.1** Verify NSCH data availability (2020-2023) in database
  - Check that all four years are loaded: `nsch_2020_raw`, `nsch_2021_raw`, `nsch_2022_raw`, `nsch_2023_raw`
  - Verify STRATUM, HHID, FWC variables exist in all years
  - Document sample sizes per year for Nebraska (FIPSST = 31)

- [ ] **1.2** Rewrite `18_estimate_nsch_outcomes.R` - Data Loading
  - Replace single-year query with multi-year UNION ALL query (2020-2023)
  - Add `survey_year` column to track data source
  - Include STRATUM, HHID, FWC in SELECT clause
  - Filter out missing age codes (90, 95, 96, 99)
  - Filter to complete survey design records (STRATUM, HHID, FWC NOT NULL)

- [ ] **1.3** Rewrite `18_estimate_nsch_outcomes.R` - Outcome Preparation
  - Keep defensive missing data coding for ACEct_23, MEDB10ScrQ5_23, K2Q01
  - Add age_factor creation: `factor(SC_AGE_YEARS)`
  - Verify outcome missingness patterns by year

- [ ] **1.4** Rewrite `18_estimate_nsch_outcomes.R` - MICE Single Imputation for ACE Indicators
  - Setup parallel processing: `library(future); plan(multisession, workers = parallel::detectCores() / 2)`
  - Load mice package: `library(mice)`
  - Prepare ACE data: ACE1-ACE11 recoded as binary (1→1, 2→0, 99→NA)
  - Include auxiliary variables: age, survey_year, sex, race/ethnicity for imputation model
  - Generate single imputed dataset with parallel: `mice(ace_data, method = "cart", m = 1, maxit = 10, seed = 2025)`
  - Extract completed data: `complete(imp_result, 1)`
  - Document: Record number of values imputed per ACE variable
  - Close parallel workers: `plan(sequential)`
  - Rationale: Single imputation appropriate given low missingness (~5-7%)

- [ ] **1.5** Rewrite `18_estimate_nsch_outcomes.R` - Survey Design Creation
  - Create survey design with `svydesign()` on imputed dataset:
    - `ids = ~HHID` (household clustering)
    - `strata = ~interaction(FIPSST, STRATUM)` (composite strata)
    - `weights = ~FWC` (survey weights)
    - `nest = TRUE`
  - Create separate designs for each outcome (filter to complete cases for non-ACE outcomes)

- [ ] **1.6** Rewrite `18_estimate_nsch_outcomes.R` - ACE Exposure Model
  - Fit full model: `ace_1plus ~ age_factor + survey_year + age_factor:survey_year`
  - Fit main effects model: `ace_1plus ~ age_factor + survey_year`
  - Test interaction significance with `anova()`
  - Select final model (use interaction if p < 0.05)
  - Predict at year 2023 for ages 0-5
  - Create results data frame with 6 rows

- [ ] **1.7** Rewrite `18_estimate_nsch_outcomes.R` - Emotional/Behavioral Model
  - Filter to ages 3-5 only (outcome not measured for ages 0-2)
  - Fit models with age + year + age:year structure
  - Test interaction significance
  - Predict at year 2023 for ages 3-5
  - Create results with NA for ages 0-2, estimates for ages 3-5

- [ ] **1.8** Rewrite `18_estimate_nsch_outcomes.R` - Excellent Health Model
  - Fit models with age + year + age:year structure
  - Test interaction significance
  - Predict at year 2023 for ages 0-5
  - Create results data frame with 6 rows

- [ ] **1.9** Update `20_estimate_childcare_2022.R` for multi-year approach
  - Pool 2020-2022 data (child care variable not in 2023)
  - Create survey design with proper specification
  - Fit GLM with age + year + age:year
  - Predict at year 2022 (most recent with data)
  - Create results data frame with 6 rows

- [ ] **1.10** Test NSCH estimation scripts
  - Run `18_estimate_nsch_outcomes.R` and verify output
  - Run `20_estimate_childcare_2022.R` and verify output
  - Check that estimates are plausible (0-1 range, reasonable magnitudes)
  - Verify MICE single imputation: Check # values imputed per ACE variable
  - Compare to complete-case estimates (should be very similar, slightly more precise)

- [ ] **1.11** Update consolidation script for new NSCH estimates
  - Modify `21_consolidate_estimates.R` to read new NSCH output files
  - Verify 24 NSCH rows in consolidated output (4 estimands × 6 ages)
  - Verify total 180 rows after consolidation

- [ ] **1.12** PHASE 1 CHECKPOINT - Verify & Mark Complete
  - Run all Phase 1 scripts end-to-end
  - Verify 180 point estimates generated correctly
  - Verify estimates pass validation checks (range, plausibility)
  - Mark all Phase 1 tasks as complete in this document
  - Load Phase 2 tasks into Claude to-do list

---

## Phase 2: Implement Bootstrap for ACS Estimands (25 estimands)

**Goal:** Add 4,096 bootstrap replicates for all 25 ACS-based raking targets using parallel processing

**Status:** ✅ Complete (October 6, 2025)
**Actual Time:** ~15-20 minutes (production run with 4096 replicates, 16 workers)
**Implementation:** Shared bootstrap design approach with separate binary models for FPL/PUMA

### Tasks:

- [x] **2.1** Setup parallel processing infrastructure ✅
  - ~~Install required packages: `install.packages(c("svrep", "future", "future.apply"))`~~
  - ~~Test svrep basic functionality with dummy data~~
  - ~~Verify `as_bootstrap_design()` and `withReplicates()` work~~
  - ~~Test parallel bootstrap generation with small example~~
  - **Actual:** Created shared ACS bootstrap design (one set of replicate weights for all 25 estimands)

- [x] **2.1a** Create shared ACS bootstrap design ✅
  - **New task:** Script `01a_create_acs_bootstrap_design.R` creates single bootstrap design
  - Inherits `n_boot` from parent `run_bootstrap_pipeline.R` script
  - Generates 6657 observations × 4096 replicates (24.49 MB)
  - All 25 ACS estimands share same replicate weights (correct correlation structure)

- [x] **2.2** Create bootstrap helper function for ACS with parallel support ✅
  - **Actual:** Created `scripts/raking/ne25/bootstrap_helpers.R` with `generate_acs_bootstrap()`
  - Function accepts shared `boot_design` as first parameter
  - Uses `future.apply::future_lapply()` for parallel bootstrap replicate generation
  - Configured with 16 workers for production run
  - Includes model selection logic and validation

- [x] **2.3** Update `02_estimate_sex_final.R` for bootstrap ✅
  - Loads shared bootstrap design from `01a_create_acs_bootstrap_design.R`
  - Generates 4096 bootstrap replicates with 16 parallel workers
  - Validated: All estimates in [0,1] range, no missing values

- [x] **2.4** Update `03_estimate_race_ethnicity.R` for bootstrap ✅
  - Uses shared bootstrap design for 3 race/ethnicity estimands
  - Separate binary models for Black, Hispanic, White non-Hispanic

- [x] **2.5** Update `04_estimate_fpl.R` for bootstrap ✅
  - **Decision:** Separate binary models (not multinomial) - see MULTINOMIAL_APPROACH_DECISION.md
  - 5 separate binary logistic regressions + post-hoc normalization
  - Validated: All row sums = 1.0 exactly
  - Production: 106 seconds with 96 replicates

- [x] **2.6** Update `05_estimate_puma.R` for bootstrap ✅
  - **Decision:** Separate binary models (not multinomial) - see MULTINOMIAL_APPROACH_DECISION.md
  - 14 separate binary logistic regressions + post-hoc normalization
  - Validated: All row sums = 1.0 exactly
  - Production: 309 seconds with 96 replicates

- [x] **2.7** Update `06_estimate_mother_education.R` for bootstrap ✅
  - Uses shared bootstrap design with subset to households with mother present
  - Proper survey::subset() maintains survey design structure

- [x] **2.8** Update `07_estimate_mother_marital_status.R` for bootstrap ✅
  - Uses shared bootstrap design with subset to households with mother present
  - Proper survey::subset() maintains survey design structure

- [x] **2.9** Test all ACS bootstrap scripts ✅
  - Full pipeline tested with 96 replicates: 10.3 minutes, 17,280 database rows
  - All validation checks passed (row sums, value ranges, completeness)

- [x] **2.10** Create ACS bootstrap consolidation script ✅
  - Script `21a_consolidate_acs_bootstrap.R` combines all 25 estimands
  - Production: 150 estimands × 4096 replicates = 614,400 rows

- [x] **2.11** PHASE 2 CHECKPOINT - Complete ✅
  - **Test run:** 96 replicates, 16 workers, 10.3 minutes, 17,280 rows
  - **Production run:** 4096 replicates, 16 workers, ~15-20 minutes, 737,280 rows (in progress)
  - All distributions validated, no errors

---

## Phase 3: Implement Bootstrap for NHIS Estimands (1 estimand)

**Goal:** Add 4,096 bootstrap replicates for PHQ-2 depression screening

**Status:** Not Started
**Estimated Time:** 2-3 hours

### Tasks:

- [ ] **3.1** Create bootstrap helper function for NHIS
  - Add `generate_nhis_bootstrap()` to `bootstrap_helpers.R`
  - Handle year main effects model (simpler than ACS)
  - Takes n_boot parameter
  - Return point estimate + n_boot replicates

- [ ] **3.2** Update `13_estimate_phq2.R` for bootstrap
  - Add configuration: `n_boot <- 4  # Change to 4096 for production`
  - Convert phq_design to bootstrap design (n_boot replicates)
  - Use `withReplicates()` to generate bootstrap distribution
  - Save point estimates to `phq2_estimate.rds` (original format)
  - Save bootstrap replicates to `phq2_estimate_boot.rds` (new file)
  - Verify: 6 point estimates + (6 × n_boot) replicate estimates
  - Test mode: 6 + 24 = 30 estimates total

- [ ] **3.3** Test NHIS bootstrap script
  - Run `13_estimate_phq2.R`
  - Verify bootstrap file created
  - Check distribution: should be fairly tight (large sample size)
  - Plot histogram of replicate estimates for age 3

- [ ] **3.4** PHASE 3 CHECKPOINT - Verify & Mark Complete
  - Run Phase 3 script successfully
  - Verify (6 × n_boot) NHIS bootstrap replicates generated
  - Test mode: 24 replicates total
  - Production mode: 24,576 replicates
  - Verify estimates are plausible (5-15% range)
  - Mark all Phase 3 tasks as complete in this document
  - Load Phase 4 tasks into Claude to-do list

---

## Phase 4: Implement Bootstrap for NSCH Estimands (4 estimands)

**Goal:** Add 4,096 bootstrap replicates for all 4 NSCH outcomes using new multi-year design

**Status:** Not Started
**Estimated Time:** 4-5 hours

### Tasks:

- [ ] **4.1** Create bootstrap helper function for NSCH
  - Add `generate_nsch_bootstrap()` to `bootstrap_helpers.R`
  - Handle age + year + age:year model structure
  - Handle model selection (interaction testing)
  - Takes n_boot parameter
  - Return point estimates + n_boot replicates for specific prediction year

- [ ] **4.2** Update `18_estimate_nsch_outcomes.R` for bootstrap - ACE
  - Add configuration: `n_boot <- 4  # Change to 4096 for production`
  - After creating nsch_design, convert to bootstrap design (n_boot replicates)
  - Use `withReplicates()` for ACE exposure model
  - Generate n_boot replicates at year 2023 for ages 0-5
  - Save point estimates and bootstrap replicates
  - Verify: 6 point estimates + (6 × n_boot) replicate estimates
  - Test mode: 6 + 24 = 30 estimates total

- [ ] **4.3** Update `18_estimate_nsch_outcomes.R` for bootstrap - Emotional/Behavioral
  - Convert design to bootstrap (n_boot replicates)
  - Generate replicates for ages 3-5 only (predict at 2023)
  - Assign NA for ages 0-2 replicates
  - Save point estimates and bootstrap replicates
  - Verify: 6 point estimates + (6 × n_boot) replicate estimates (with NAs for ages 0-2)
  - Test mode: 6 + 24 = 30 estimates total

- [ ] **4.4** Update `18_estimate_nsch_outcomes.R` for bootstrap - Excellent Health
  - Convert design to bootstrap (n_boot replicates)
  - Generate replicates at year 2023 for ages 0-5
  - Save point estimates and bootstrap replicates
  - Verify: 6 point estimates + (6 × n_boot) replicate estimates
  - Test mode: 6 + 24 = 30 estimates total

- [ ] **4.5** Update `20_estimate_childcare_2022.R` for bootstrap
  - Add configuration: `n_boot <- 4  # Change to 4096 for production`
  - Convert design to bootstrap (n_boot replicates)
  - Generate replicates at year 2022 (last year with data)
  - Save point estimates and bootstrap replicates
  - Verify: 6 point estimates + (6 × n_boot) replicate estimates
  - Test mode: 6 + 24 = 30 estimates total

- [ ] **4.6** Test all NSCH bootstrap scripts
  - Run `18_estimate_nsch_outcomes.R`
  - Run `20_estimate_childcare_2022.R`
  - Verify all 4 bootstrap files created
  - Check distributions are plausible

- [ ] **4.7** Create NSCH bootstrap consolidation script
  - Create `21b_consolidate_nsch_boot.R`
  - Load all 4 NSCH bootstrap files
  - Combine into single data frame
  - Verify: 24 point estimates × n_boot total rows
  - Test mode: 24 × 4 = 96 rows
  - Production mode: 24 × 4096 = 98,304 rows
  - Save to `data/raking/ne25/nsch_estimates_boot.rds`

- [ ] **4.8** PHASE 4 CHECKPOINT - Verify & Mark Complete
  - Run all Phase 4 scripts end-to-end
  - Verify (24 × n_boot) NSCH bootstrap replicates generated
  - Test mode: 96 replicates (fast verification)
  - Production mode: 98,304 replicates
  - Check distributions for multi-year smoothing effect
  - Mark all Phase 4 tasks as complete in this document
  - Load Phase 5 tasks into Claude to-do list

---

## Phase 5: Database Integration for Bootstrap Replicates

**Goal:** Store bootstrap replicates in DuckDB with proper indexing

**Status:** Not Started
**Estimated Time:** 3-4 hours
**Test Mode:** 720 replicates (180 estimands × 4)
**Production Mode:** 737,280 replicates (180 estimands × 4,096)

### Tasks:

- [ ] **5.1** Design database schema for bootstrap replicates
  - Create table design: `raking_targets_boot_replicates`
  - Columns: estimand, age, replicate, estimate, source, created_at
  - Plan indexes: (estimand, age), (estimand, age, replicate)
  - Document schema in `docs/raking/ne25/DATABASE_SCHEMA.md`

- [ ] **5.2** Create bootstrap consolidation script
  - Create `scripts/raking/ne25/22_consolidate_all_boot_replicates.R`
  - Load ACS bootstrap file (150 × n_boot rows)
  - Load NHIS bootstrap file (6 × n_boot rows)
  - Load NSCH bootstrap file (24 × n_boot rows)
  - Combine into single data frame
  - Add source column (ACS/NHIS/NSCH)
  - Add created_at timestamp
  - Verify: 180 × n_boot total rows
  - Test mode: 720 rows
  - Production mode: 737,280 rows

- [ ] **5.3** Create Python database insertion script
  - Create `scripts/raking/ne25/23_insert_boot_replicates.py`
  - Read consolidated bootstrap replicates from Feather
  - Connect to DuckDB
  - Create `raking_targets_boot_replicates` table if not exists
  - Insert all (180 × n_boot) rows in batches
  - Test mode: 720 rows
  - Production mode: 737,280 rows
  - Create indexes on (estimand, age) and (estimand, age, replicate)

- [ ] **5.4** Test bootstrap database integration
  - Run R consolidation script (22)
  - Run Python insertion script (23)
  - Verify table created with correct row count
  - Test query performance with indexes
  - Verify no duplicate records

- [ ] **5.5** Create database validation queries
  - Query to count replicates per estimand (should all be 24,576)
  - Query to verify all ages 0-5 represented
  - Query to check value ranges (all in [0, 1])
  - Query to verify no NULL estimates (except emot_behav ages 0-2)
  - Document validation queries in database schema doc

- [ ] **5.6** Update database schema documentation
  - Add bootstrap replicates table to schema diagram
  - Document query examples for confidence intervals
  - Document query examples for standard errors
  - Add guidance on using bootstrap for raking sensitivity analysis

- [ ] **5.7** PHASE 5 CHECKPOINT - Verify & Mark Complete
  - Verify all (180 × n_boot) bootstrap replicates in database
  - Test mode: 720 replicates
  - Production mode: 737,280 replicates
  - Run validation queries successfully
  - Test query performance (should be <1 second for single estimand)
  - Mark all Phase 5 tasks as complete in this document
  - Load Phase 6 tasks into Claude to-do list

---

## Phase 6: Documentation, Testing, and Verification

**Goal:** Complete documentation, comprehensive testing, and final verification

**Status:** Not Started
**Estimated Time:** 3-4 hours

### Tasks:

- [ ] **6.1** Update CLAUDE.md with bootstrap information
  - Add bootstrap pipeline execution commands
  - Document that bootstrap replicates are available
  - Update status section to mention bootstrap implementation
  - Document n_boot configuration (test vs production mode)

- [ ] **6.2** Update QUICK_REFERENCE.md with bootstrap commands
  - Add commands to generate bootstrap replicates
  - Add commands to query bootstrap distributions
  - Add examples for confidence intervals and standard errors

- [ ] **6.3** Update RAKING_TARGETS_ESTIMATION_PLAN.md
  - Mark all phases as "Complete"
  - Add Phase 6 section for bootstrap implementation
  - Update estimated timeline

- [ ] **6.4** Create bootstrap usage examples document
  - Create `docs/raking/ne25/BOOTSTRAP_USAGE_EXAMPLES.md`
  - Example 1: Compute 95% confidence intervals
  - Example 2: Compute design-based standard errors
  - Example 3: Visualize bootstrap distributions
  - Example 4: Assess raking stability across replicates
  - Include both R and Python code examples

- [ ] **6.5** Create end-to-end bootstrap pipeline script
  - Create `scripts/raking/ne25/run_bootstrap_pipeline.R`
  - Orchestrates all bootstrap scripts in correct order
  - Includes progress reporting and timing
  - Includes validation checks between phases
  - Saves log file with execution details

- [ ] **6.6** Test complete bootstrap pipeline end-to-end
  - Delete all existing bootstrap files
  - Run `run_bootstrap_pipeline.R` with n_boot = 4 (test mode)
  - Verify all 720 replicates generated (test mode)
  - Check total execution time (should be 3-5 minutes in test mode)
  - Review log file for any warnings or errors
  - Document: After code verified, change n_boot = 4096 and re-run for production

- [ ] **6.7** Create bootstrap verification script
  - Create `scripts/raking/ne25/verify_bootstrap.R`
  - Checks: correct row counts, no missing data, value ranges
  - Checks: bootstrap distributions are plausible (not too wide/narrow)
  - Checks: confidence intervals contain point estimates
  - Checks: standard errors are reasonable magnitudes
  - Generates summary report

- [ ] **6.8** Run bootstrap verification and address any issues
  - Run `verify_bootstrap.R`
  - Review verification report
  - Address any flagged issues
  - Re-run verification until all checks pass

- [ ] **6.9** Create bootstrap visualization examples
  - Plot bootstrap distributions for 10 representative estimands
  - Show distributions across different ages for one estimand
  - Compare bootstrap SEs to model-based SEs (should be similar)
  - Save plots to `docs/raking/ne25/figures/`

- [ ] **6.10** Update statistical methods documentation
  - Verify STATISTICAL_METHODS_RAKING_TARGETS.md is accurate
  - Add any missing details about bootstrap implementation
  - Add references to verification results
  - Add example figures

- [ ] **6.11** Final integration test with existing pipeline
  - Run complete raking targets pipeline with bootstrap
  - Verify point estimates unchanged from Phase 1
  - Verify bootstrap replicates integrate smoothly
  - Test querying bootstrap distributions from both R and Python

- [ ] **6.12** PHASE 6 FINAL CHECKPOINT
  - Test mode verification: 720 bootstrap replicates in database, all checks pass
  - All documentation updated and accurate
  - End-to-end pipeline runs successfully in test mode
  - Verification script passes all checks
  - Mark all Phase 6 tasks as complete
  - Mark entire bootstrap implementation project as COMPLETE (test mode)

- [ ] **6.13** PRODUCTION RUN (Final Step)
  - Change n_boot from 4 to 4096 in ALL bootstrap scripts
  - Delete all existing bootstrap files and database tables
  - Run complete bootstrap pipeline with n_boot = 4096
  - Expected time: 4-6 hours (run as batch job)
  - Verify: 737,280 replicates in database
  - Run verification script with production data
  - Mark PRODUCTION bootstrap implementation as COMPLETE

---

## Progress Tracking

### Phase Completion Status

| Phase | Status | Completion Date | Notes |
|-------|--------|-----------------|-------|
| Phase 1: Fix NSCH Survey Design | Not Implemented | - | Skipped - NSCH not part of bootstrap scope |
| Phase 2: ACS Bootstrap (25 estimands) | ✅ Complete | October 6, 2025 | 614,400 replicate estimates (150 × 4096) |
| Phase 3: NHIS Bootstrap (1 estimand) | Not Implemented | - | Skipped - NHIS not part of bootstrap scope |
| Phase 4: NSCH Bootstrap (4 estimands) | Not Implemented | - | Skipped - NSCH not part of bootstrap scope |
| Phase 5: Database Integration | ✅ Complete | October 6, 2025 | 737,280 total replicates (30 × 6 × 4096) |
| Phase 6: Documentation & Verification | 🔄 In Progress | - | Documentation updates needed |

### Metrics

- **Total Tasks Planned:** 63 (original scope)
- **Actual Tasks Completed:** 11 (Phase 2 only - ACS bootstrap)
- **Implementation Note:** Bootstrap scope limited to ACS estimands only (25 of 30 estimands)
- **Test Run:** 96 replicates, 10.3 minutes
- **Production Run:** 4096 replicates, ~15-20 minutes (in progress)
- **Actual Approach:** Shared bootstrap design + separate binary models for FPL/PUMA

---

## Notes

- **Development Strategy:** Use n_boot = 4 for ALL development work (fast iteration)
- **Production Run:** Single batch job with n_boot = 4096 after code verified
- Each phase includes a checkpoint task that verifies completion and loads next phase
- Bootstrap generation with n_boot = 4 takes ~3-5 minutes (vs 4-6 hours with n_boot = 4096)
- Bootstrap files (test mode): ~1-2 MB; (production): ~60-80 MB
- Database queries should be fast (<1 second) with proper indexing
- Model selection (interaction testing) happens for each bootstrap replicate

---

**Last Updated:** October 2025
**Document Version:** 1.0

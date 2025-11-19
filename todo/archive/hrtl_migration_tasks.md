# HRTL Scoring Migration - Task Breakdown

**Status:** Phase 1 Complete ✅ | Phase 2 In Progress
**Start Date:** 2025-01-13
**Last Updated:** 2025-01-13
**Estimated Completion:** 1-2 weeks (accelerated from original 2-3 weeks)

---

## Progress Summary

### ✅ Completed (2025-01-13)
- **Phase 1:** Data Preparation & Investigation - **100% COMPLETE**
  - All 27 HRTL items verified in NE25 codebook
  - Codebook updated to v2.12 with complete HRTL metadata
  - Canonical HRTL naming preserved via lexicon arrays
  - HRTL domain classifications added (`domains.hrtl22`)
  - Age-specific thresholds integrated (`hrtl_thresholds.years`)
  - **Key Innovation:** Codebook-centric approach eliminates separate tables/CSVs

### 🚧 In Progress
- **Phase 2:** Scoring Function Development - **0% COMPLETE**
  - Next: Create R/hrtl directory and port scoring functions
  - Simplified by codebook integration (no separate data files needed)

### ⏳ Remaining
- **Phase 2:** Scoring Function Development (4-6 days estimated)
- **Phase 3:** Pipeline Integration (2-3 days)
- **Phase 4:** Validation & QA (2-3 days)
- **Phase 5:** Documentation (1-2 days)
- **Phase 6:** Testing & Deployment (1-2 days)

---

## Overview

Migrate HRTL (Healthy & Ready to Learn) scoring from standalone HRTL-2016-2022 repository to Kidsights Data Platform. NE25 has 100% HRTL item coverage via CAHMI standardized items.

**Target:** Score ages 3-5 NE25 children across 5 developmental domains → overall school readiness classification

**Architecture Decision:** Codebook-centric approach with all HRTL metadata (items, domains, thresholds) embedded in `codebook.json` for single source of truth.

---

## Phase 1: Data Preparation & Investigation ✅ COMPLETE

**Timeline:** Day 1 (2025-01-13)
**Goal:** Establish data infrastructure and validate item availability
**Status:** ✅ **COMPLETE** - Codebook-centric approach implemented

### 1.1 Codebook Analysis ✅ COMPLETE
- [x] ✅ Verified all 27 HRTL items present in NE25 codebook (100% coverage)
- [x] ✅ Updated lexicon codes to include canonical HRTL names as arrays
  - Example: `cahmi22: ["DRAWCIRCLE", "DRAWACIRCLE"]`
- [x] ✅ Added `domains.hrtl22` field to all 27 items
  - 9 Early Learning, 6 Social-Emotional, 5 Self-Regulation, 4 Motor, 3 Health
- [x] ✅ Identified 8 items with naming variations (now preserved in arrays)
- [x] ✅ Reverse-coded items documented in codebook

### 1.2 Age-Specific Thresholds Integration ✅ COMPLETE
- [x] ✅ Read `HRTL-2022-Scoring-Thresholds.xlsx` (81 rows: 27 items × 3 ages)
- [x] ✅ Added `hrtl_thresholds.years` to all 27 items in codebook.json
  - Structure: `{years: {3: {on_track, emerging}, 4: {...}, 5: {...}}}`
- [x] ~~Create DuckDB table~~ **SKIPPED** - Thresholds embedded in codebook instead
- [x] ✅ Verified all threshold data loaded correctly

### 1.3 NE25-HRTL Variable Mapping ✅ COMPLETE
- [x] ✅ Complete mapping verified (27/27 items matched)
- [x] ✅ Naming exceptions handled via lexicon arrays
  - DRAWCIRCLE/DRAWACIRCLE, RECOGLETTER/RECOGABC, etc.
- [x] ✅ Health items mapped (K2Q01→CQFA002, K2Q01_D→NOM046X, DAILYACT→CQR014X)
- [x] ~~Create mapping CSV~~ **SKIPPED** - Mapping embedded in codebook instead
- [x] ~~Create DuckDB table~~ **SKIPPED** - Not needed with codebook approach

### 1.4 Sample Size Estimation
- [ ] Query NE25: Count children ages 3-5 where `meets_inclusion = TRUE`
- [ ] Check age distribution (ages 3, 4, 5)
- [ ] Assess CAHMI item completeness rates by age
- [ ] Document expected N for HRTL scoring (~500-800 estimated)

**Phase 1 Deliverables:**
- [x] ✅ **Codebook v2.12** with complete HRTL metadata (27 items)
  - Canonical HRTL lexicon names (lexicons.cahmi22/cahmi21 arrays)
  - HRTL domain classifications (domains.hrtl22)
  - Age-specific thresholds (hrtl_thresholds.years)
- [ ] Sample size report (N by age) - **PENDING**

**Key Decision:** Codebook-centric approach eliminates need for separate DuckDB tables and CSV files

---

## Phase 2: Scoring Function Development

**Timeline:** Days 4-7
**Goal:** Port and adapt HRTL scoring algorithm for Kidsights architecture

### 2.1 Create R Module Directory
- [ ] Create directory: `R/hrtl/`
- [ ] Initialize with README documenting module purpose

### 2.2 Port Core HRTL Functions
**File:** `R/hrtl/hrtl_scoring.R`

- [ ] Port `recode_cahmi2ifa()` function
  - [ ] Read codebook.json to get response_sets for each HRTL item
  - [ ] Input: data.frame with NE25 CAHMI variables (27 items)
  - [ ] Output: data.frame with IFA-coded values (0-indexed)
  - [ ] Apply reverse coding based on codebook metadata
  - [ ] Force K2Q01_D value 6 → NA (dental "Don't Know")
  - [ ] Use explicit `dplyr::` namespacing throughout

- [ ] Port `classify_items()` function
  - [ ] Input: IFA scores + age_years + codebook metadata
  - [ ] Extract thresholds from codebook `hrtl_thresholds.years`
  - [ ] Use `safe_left_join()` to merge thresholds by age
  - [ ] Output: 3-level classification (On-Track/Emerging/Needs-Support)
  - [ ] Classification logic: `on_track ≥ threshold` → "On-Track", `emerging ≥ threshold` → "Emerging", else "Needs-Support"
  - [ ] Handle missing values → item classification = NA

- [ ] Port `aggregate_domains()` function
  - [ ] Group by child ID + domain (use codebook `domains.hrtl22`)
  - [ ] Calculate mean of item classifications (coded 3/2/1)
  - [ ] Apply domain cutoffs: ≥2.5 = On-Track, ≥2.0 = Emerging, <2.0 = Needs-Support
  - [ ] Use `na.rm = TRUE` for partial item responses
  - [ ] All items missing → domain = NA

- [ ] Create `determine_hrtl()` function
  - [ ] Count domains by classification (n_on_track, n_emerging, n_needs_support)
  - [ ] Apply HRTL logic: `(n_on_track >= 4) AND (n_needs_support == 0)`
  - [ ] Missing domains don't count toward 4-domain requirement
  - [ ] Output: hrtl (TRUE/FALSE/NA)

- [ ] Create main wrapper `score_hrtl_ne25()`
  - [ ] Load codebook.json to get HRTL item list
  - [ ] Read ne25_derived table, filter to ages 3-5 + meets_inclusion
  - [ ] Select 27 HRTL items (by querying codebook for items with `domains.hrtl22`)
  - [ ] Call recoding → classification → aggregation → determination pipeline
  - [ ] Return: list(overall, by_domain) as data.frames
  - [ ] Write to Feather files for Python insertion

### 2.3 Helper Utilities
**File:** `R/hrtl/hrtl_utils.R`

- [ ] Create `load_hrtl_codebook()` - Read codebook.json and extract HRTL items
- [ ] Create `get_hrtl_items()` - Extract 27 items with `domains.hrtl22` field
- [ ] Create `get_item_thresholds()` - Extract `hrtl_thresholds.years` for an item
- [ ] Create `validate_hrtl_logic()` - Check n_on_track + n_emerging + n_needs_support ≤ 5

### 2.4 Coding Standards Compliance
- [ ] All dplyr functions use `dplyr::` prefix
- [ ] All arrow functions use `arrow::` prefix
- [ ] All joins use `safe_left_join()` wrapper
- [ ] Apply `recode_missing()` before transformations (if needed)
- [ ] No hardcoded "python" - use `get_python_path()` if calling Python

**Phase 2 Deliverables:**
- ✅ R/hrtl/hrtl_scoring.R (5 functions)
- ✅ R/hrtl/hrtl_utils.R (4 helper functions)
- ✅ Unit tests for IFA recoding and domain aggregation

---

## Phase 3: Pipeline Integration

**Timeline:** Days 8-10
**Goal:** Integrate HRTL scoring into NE25 automated pipeline

### 3.1 Add Step 12 to NE25 Pipeline
**File:** `run_ne25_pipeline.R`

- [ ] Add after Step 11 (calibration dataset creation)
- [ ] Source R/hrtl/hrtl_scoring.R
- [ ] Call score_hrtl_ne25() with age filter c(3,4,5)
- [ ] Write results to tempdir feather files:
  - [ ] `ne25_hrtl_overall.feather` (1 row per child)
  - [ ] `ne25_hrtl_by_domain.feather` (5 rows per child)
- [ ] Add logging: "Step 12: HRTL Scoring (Ages 3-5)"
- [ ] Print summary: Total children scored, HRTL prevalence

### 3.2 Database Schema Creation
**File:** `scripts/database/add_hrtl_tables.py`

- [ ] Create table `ne25_hrtl_overall`:
  - [ ] Columns: id (INT), years (INT), hrtl (BOOL), n_on_track (INT), n_emerging (INT), n_needs_support (INT)
  - [ ] Primary key: (id, years)
  - [ ] Indexes: id, years, hrtl

- [ ] Create table `ne25_hrtl_by_domain`:
  - [ ] Columns: id (INT), years (INT), domain (VARCHAR), classification (VARCHAR)
  - [ ] Primary key: (id, years, domain)
  - [ ] Indexes: id, domain

- [ ] Run schema creation once (manual execution)

### 3.3 Python Insertion Script
**File:** `python/hrtl/insert_hrtl_scores.py`

- [ ] Import DatabaseManager
- [ ] Read `ne25_hrtl_overall.feather`
- [ ] Read `ne25_hrtl_by_domain.feather`
- [ ] Insert to DuckDB tables (REPLACE mode for idempotency)
- [ ] Validate row counts match R output
- [ ] Print summary: Rows inserted, HRTL prevalence
- [ ] Use ASCII-only print statements (no Unicode symbols)

### 3.4 Call Python from Pipeline
**File:** `run_ne25_pipeline.R` (continued)

- [ ] Use `get_python_path()` to get Python executable
- [ ] Call system2() to run insert_hrtl_scores.py
- [ ] Check exit code (0 = success)
- [ ] Log: "HRTL scores inserted to database"

**Phase 3 Deliverables:**
- ✅ Step 12 added to run_ne25_pipeline.R
- ✅ Database tables created (ne25_hrtl_overall, ne25_hrtl_by_domain)
- ✅ Python insertion script working
- ✅ End-to-end pipeline runs successfully

---

## Phase 4: Validation & Quality Assurance

**Timeline:** Days 11-13
**Goal:** Validate HRTL scores against benchmarks and edge cases

### 4.1 Internal Consistency Checks
**File:** `scripts/hrtl/validate_hrtl_internal.R`

- [ ] Query all HRTL scores from DuckDB
- [ ] Check HRTL logic: hrtl = TRUE only if (n_on_track >= 4 AND n_needs_support = 0)
- [ ] Verify domain counts: n_on_track + n_emerging + n_needs_support ≤ 5
- [ ] Check age filter: All years in {3, 4, 5}
- [ ] Identify logic violations (should be 0)
- [ ] Print validation report

### 4.2 Domain Prevalence Validation
**File:** `scripts/hrtl/validate_hrtl_benchmarks.R`

- [ ] Calculate weighted prevalence of HRTL = TRUE (use FWC weight if available)
- [ ] Calculate domain-level "On-Track" prevalences (5 domains)
- [ ] Compare to NSCH 2022 benchmarks (Ghandour et al. 2024):
  - [ ] Overall HRTL: ~63.6%
  - [ ] Early Learning: ~68.8%
  - [ ] Social-Emotional: ~84.3%
  - [ ] Self-Regulation: ~73.2%
  - [ ] Motor: ~81.0%
  - [ ] Health: ~86.5%
- [ ] Flag deviations > 10 percentage points
- [ ] Document regional differences (Nebraska vs. national)

### 4.3 Edge Case Testing
**File:** `tests/test_hrtl_edge_cases.R`

- [ ] Test case: All 5 domains missing → hrtl = NA
- [ ] Test case: Exactly 4 domains on-track, 1 emerging → hrtl = TRUE
- [ ] Test case: 4 on-track, 1 needs-support → hrtl = FALSE
- [ ] Test case: 5 on-track, 0 needs-support → hrtl = TRUE
- [ ] Test case: Child age 2 or 6 → excluded (not scored)
- [ ] Test case: All items missing in domain → domain = NA
- [ ] Create synthetic test data for each case
- [ ] Run through scoring function
- [ ] Assert expected outputs

### 4.4 Item-Level Validation
**File:** `scripts/hrtl/validate_hrtl_items.R`

- [ ] Check IFA recoding: Values in expected range (0-4 for 5-category)
- [ ] Verify reverse coding: Higher IFA = better performance for ALL items
- [ ] Compare item means to published NSCH values (if available)
- [ ] Check threshold application: On-track assignments increase with age
- [ ] Identify items with high missing rates (>20%)

**Phase 4 Deliverables:**
- ✅ Validation report (internal consistency)
- ✅ Benchmark comparison report
- ✅ Edge case tests passing
- ✅ Item-level diagnostics

---

## Phase 5: Documentation

**Timeline:** Days 14-16
**Goal:** Comprehensive documentation for HRTL scoring system

### 5.1 Create HRTL Documentation Directory
- [ ] Create `docs/hrtl/` directory
- [ ] Initialize with README.md overview

### 5.2 Core Documentation Files

**File:** `docs/hrtl/HRTL_OVERVIEW.md`
- [ ] What is HRTL? (school readiness assessment)
- [ ] Psychometric foundation (IFA/IRT)
- [ ] 5 developmental domains description
- [ ] Clinical interpretation (strict conjunctive standard)
- [ ] Policy applications (Title V National Outcome Measure)

**File:** `docs/hrtl/HRTL_SCORING_ALGORITHM.md`
- [ ] Step-by-step algorithm (4 steps: recode → classify → aggregate → determine)
- [ ] IFA recoding explanation (0-indexing, reverse coding)
- [ ] Age-specific thresholds (3 ages × 28 items)
- [ ] Domain aggregation (mean with na.rm=TRUE)
- [ ] Overall HRTL logic (4+ on-track, 0 needs-support)
- [ ] Code examples from R/hrtl/hrtl_scoring.R

**File:** `docs/hrtl/HRTL_NE25_MAPPING.md`
- [ ] Complete 27-item crosswalk table
- [ ] CAHMI codes and lexicon
- [ ] NE25 variable names
- [ ] Response formats by item
- [ ] Reverse-coded items (5 identified)
- [ ] RECOGLETTER → NOM026X naming exception

**File:** `docs/hrtl/HRTL_VALIDATION.md`
- [ ] NSCH 2022 benchmarks (Ghandour et al. 2024)
- [ ] NE25 validation results (prevalences by domain)
- [ ] Regional differences (Nebraska vs. national)
- [ ] Quality checks and acceptance criteria
- [ ] Edge case testing results

### 5.3 Update Main Documentation

**File:** `docs/QUICK_REFERENCE.md`
- [ ] Add HRTL section under "Common Tasks"
- [ ] Query examples (get HRTL scores by age)
- [ ] Command to run HRTL scoring standalone

**File:** `CLAUDE.md`
- [ ] Update "Current Status" section
- [ ] Add HRTL Pipeline as complete
- [ ] Document Step 12 in NE25 pipeline
- [ ] Add to pipeline list (7th pipeline)

**File:** `docs/guides/DERIVED_VARIABLES_SYSTEM.md`
- [ ] Add HRTL scores as derived variables (6 new: hrtl + 5 domains)
- [ ] Document dependencies (27 CAHMI items)

### 5.4 Codebook Integration

**File:** `codebook/data/codebook.json`
- [ ] Add `domain_hrtl` field to 27 CAHMI items
- [ ] Values: "early_learning", "social_emotional", "self_regulation", "motor", "health"
- [ ] Update codebook version number

**File:** `codebook/README.md`
- [ ] Document HRTL domain field
- [ ] Add HRTL scoring example

**Phase 5 Deliverables:**
- ✅ 4 HRTL documentation files in docs/hrtl/
- ✅ Updated main documentation (3 files)
- ✅ Codebook integration complete

---

## Phase 6: Testing & Deployment

**Timeline:** Days 17-18
**Goal:** Comprehensive testing and production deployment

### 6.1 Unit Tests
**File:** `tests/test_hrtl_scoring.R`

- [ ] Test recode_cahmi2ifa() with known inputs/outputs
- [ ] Test classify_items() with threshold edges
- [ ] Test aggregate_domains() with missing data patterns
- [ ] Test determine_hrtl() with all edge cases
- [ ] Run with testthat framework

### 6.2 Integration Tests
**File:** `tests/test_hrtl_integration.R`

- [ ] Run full NE25 pipeline from start to Step 12
- [ ] Verify database tables created
- [ ] Query HRTL results from DuckDB
- [ ] Check row counts match expected N
- [ ] Validate no NA values in critical fields

### 6.3 Sample Size Verification
- [ ] Query final N scored (ages 3-5)
- [ ] Break down by age (3, 4, 5)
- [ ] Calculate % of NE25 dataset
- [ ] Verify sufficient N for analysis (>100 per age group)

### 6.4 Production Deployment Checklist
- [ ] All tests passing (unit + integration)
- [ ] Validation reports reviewed
- [ ] Documentation complete
- [ ] Database indexes created
- [ ] Pipeline logging adequate
- [ ] Error handling robust (missing data, age filters)
- [ ] Performance acceptable (<30 seconds for Step 12)

### 6.5 Final Execution
- [ ] Run full NE25 pipeline: `"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R`
- [ ] Verify Step 12 completes successfully
- [ ] Check database: `SELECT COUNT(*) FROM ne25_hrtl_overall`
- [ ] Generate summary report (prevalences, N by domain)

**Phase 6 Deliverables:**
- ✅ All tests passing
- ✅ Production deployment successful
- ✅ HRTL scores available in database
- ✅ Summary report generated

---

## Future Enhancements (Optional Phase 7)

**Not in scope for initial migration, consider for future iterations:**

### 7.1 Developmental Item Imputation
- Impute missing CAHMI items using MICE or random forest
- Re-score HRTL on imputed data
- Compare pre/post imputation prevalences
- Goal: Maximize children with complete HRTL scores

### 7.2 NSCH HRTL Pipeline
- Score HRTL on 7 years of NSCH data (2017-2023)
- Create `nsch_hrtl` tables
- National benchmarking for NE25 comparison
- Trend analysis (has HRTL prevalence changed over time?)

### 7.3 Longitudinal Analysis
- Track individual children across ages 3→4→5
- HRTL transitions (not ready → ready)
- Domain-level trajectories
- Predictors of school readiness gains

### 7.4 IRT Calibration Integration
- Add 27 HRTL items to multi-study IRT calibration dataset
- Domain-specific graded response models
- Update thresholds based on NE25 + NSCH combined calibration
- Store IRT parameters in codebook

### 7.5 Weighted Prevalences
- Apply raking weights (from raking_targets_ne25)
- Population-representative HRTL estimates
- Stratified analysis (by income, race, education)
- Compare weighted vs. unweighted prevalences

---

## Success Criteria

### Functional Requirements
- ✅ HRTL scores generated for all NE25 children ages 3-5 with sufficient data
- ✅ Database tables `ne25_hrtl_overall` and `ne25_hrtl_by_domain` populated
- ✅ Pipeline Step 12 runs end-to-end without errors
- ✅ Results queryable from DuckDB

### Quality Requirements
- ✅ Domain prevalences within ±10pp of NSCH 2022 benchmarks (regional variation acceptable)
- ✅ Zero HRTL logic violations (domain count checks pass)
- ✅ Edge cases handled correctly (missing domains, boundaries)
- ✅ Item-level IFA recoding validated (correct ranges, reverse coding)

### Documentation Requirements
- ✅ Complete HRTL documentation in docs/hrtl/ (4 files)
- ✅ Codebook integration with domain_hrtl fields
- ✅ Main documentation updated (CLAUDE.md, QUICK_REFERENCE.md)
- ✅ Examples and validation protocols documented

---

## Progress Tracking

**Started:** 2025-01-13
**Current Phase:** Phase 1 - Data Preparation
**Last Updated:** 2025-01-13

### Completed Tasks
- ✅ HRTL repository analysis
- ✅ NE25 codebook item mapping analysis
- ✅ Migration plan approved

### In Progress
- [ ] Phase 1.1 - Codebook CAHMI items investigation

### Blocked/Issues
- None currently

---

## References

1. **HRTL Source Repository:** `C:\Users\marcu\git-repositories\HRTL-2016-2022`
2. **Ghandour et al. (2024):** HRTL benchmarks and methodology
3. **NE25 Codebook:** `codebook/data/codebook.json`
4. **HRTL Thresholds:** `HRTL-2016-2022/datasets/intermediate/HRTL-2022-Scoring-Thresholds.xlsx`
5. **Kidsights CLAUDE.md:** Platform coding standards and architecture

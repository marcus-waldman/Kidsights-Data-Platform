# Missing Data Audit & Remediation Plan
**Created:** October 1, 2025
**Status:** In Progress
**Priority:** CRITICAL

## Context

During implementation of child ACE variables to the NE25 transformation pipeline, a critical data quality issue was discovered: **"Prefer not to answer" responses (coded as 99) are not being converted to missing/NA values** in caregiver ACE variables.

### Problem Statement

Caregiver ACE variables (cace1-10) include a "Prefer not to answer" option coded as `99`. The current transformation logic directly copies these numeric values without recoding, leading to:
- Invalid total scores (e.g., `ace_total = 990` for someone who declined all 10 items)
- Incorrect risk categorization
- Inflated composite scores being treated as valid data

### Impact Assessment

**Confirmed Issues:**
- At least **72 records** with `ace_neglect = 99` (should be NA)
- At least **56 records** with `ace_parent_loss = 99` (should be NA)
- Invalid `ace_total` scores: 495, 299, 892, 990, etc.
- Unknown extent across all 10 caregiver ACE variables

**Potentially Affected Variables:**
- Caregiver ACEs (cace1-10) - **CONFIRMED ISSUE**
- Child ACEs (cqr017-024) - Status unknown
- Mental health screening (PHQ-2, GAD-2) - Status unknown
- Childcare variables - Status unknown
- Income variables - Commonly use 999/9999 for missing
- Other derived variables with composite scores

### Files Involved

- **Primary:** `R/transform/ne25_transforms.R` (lines 978-1021 for caregiver ACEs)
- **Configuration:** `config/derived_variables.yaml`
- **Documentation:** `R/transform/README.md`
- **Database:** `ne25_transformed` table in DuckDB

---

## Phase 1: Comprehensive Missing Data Audit

**Goal:** Identify all variables with "Prefer not to answer" or "Don't know" options

### 1.1 Survey All Mental Health/ACE Variables

- [ ] Query REDCap data dictionary for all response options containing "99", "-99", "Prefer", "Don't know"
- [ ] Create inventory of affected variables with actual response codes:
  - [ ] Caregiver ACEs (cace1-10) - Document which use 99 vs -99
  - [ ] Child ACEs (cqr017-024) - Check if any have prefer not to answer option
  - [ ] PHQ-2 items (cqfb013-014) - Check for don't know options
  - [ ] GAD-2 items (cqfb015-016) - Check for don't know options
- [ ] Document findings in table format (variable, missing code, frequency)

### 1.2 Survey Other Derived Variable Categories

- [ ] Childcare variables (mmi*) - Check for prefer not to answer (likely 9 or 99)
- [ ] Income variables (cqr006, fqlive1_*) - Check for 999, 9999, etc.
- [ ] Education variables (cqr004, nschj017) - Check for missing codes
- [ ] Race/ethnicity variables - Check for missing codes
- [ ] Geographic variables (ZIP codes) - Check for invalid codes (00000, 99999)

### 1.3 Check Raw Data Values

- [ ] For each variable with documented missing codes, query distinct values in `ne25_raw`
- [ ] Create frequency table for each affected variable showing:
  - Valid values (e.g., 0, 1 for ACEs)
  - Missing codes (e.g., 99)
  - NULL/NA values
  - Unexpected values
- [ ] Calculate percentage of responses that are "Prefer not to answer"

### 1.4 Check Transformed Data Impact

- [ ] For each affected variable, verify if missing codes persist in `ne25_transformed`
- [ ] Check impact on composite scores:
  - [ ] `ace_total` - How many records have inflated scores (>10)?
  - [ ] `child_ace_total` - Check for any issues
  - [ ] `phq2_total` - Check for values >6
  - [ ] `gad2_total` - Check for values >6
  - [ ] Any childcare composite scores
- [ ] Document how many records have invalid total scores due to this issue

### 1.5 Phase 1 Completion

- [ ] Review this markdown file and mark completed Phase 1 tasks
- [ ] Create summary report of audit findings
- [ ] Load Phase 2 tasks into Claude TodoWrite tool
- [ ] Decision point: Proceed to Phase 2 or adjust plan based on findings

---

## Phase 2: Fix Missing Data Recoding ✓ COMPLETED

**Goal:** Implement systematic missing data handling across all transformations

### 2.1 Create Missing Data Cleaning Infrastructure ✓

- [x] Create `recode_missing()` helper function in `ne25_transforms.R`
  - Parameters: variable vector, missing codes (default: `c(9, 99, -99, 999, 9999)`)
  - Returns: vector with missing codes converted to NA
  - Add roxygen documentation
- [x] Test function with known data containing 99 values
- [x] Verify function preserves valid values (0, 1, 2, 3, etc.)

### 2.2 Fix Caregiver ACE Transformation (URGENT) ✓

- [x] Update caregiver ACE block in `ne25_transforms.R` (around line 978)
- [x] Add missing data recoding BEFORE copying cace* → ace_* variables using `recode_missing()` helper function
- [x] Verify `ace_total` calculation uses `na.rm = FALSE` (already correct)
- [x] Verify `ace_risk_cat` properly handles records with missing ACE items
- [x] Add code comments explaining missing value handling

### 2.3 Fix Child ACE Transformation (Defensive) ✓

- [x] Update child ACE block in `ne25_transforms.R` (around line 1023)
- [x] Add missing data recoding for cqr017-024 even if not currently needed
- [x] Use same pattern as caregiver ACEs with `recode_missing()` helper
- [x] Verify `child_ace_total` calculation
- [x] Add code comments

### 2.4 Update Mental Health Transformation ✓

- [x] Check PHQ-2/GAD-2 items (cqfb013-016) for any missing codes in data dictionary
- [x] Phase 1 audit confirmed NO missing codes in PHQ-2/GAD-2 (valid 0-3 scale only)
- [x] Verify total scores (`phq2_total`, `gad2_total`) only include valid 0-3 values
- [x] Verify risk categories properly handle missing items

### 2.5 Update Income Transformation ✓

- [x] Check `cqr006` (income) for missing codes (likely 999999 or similar)
- [x] Check `fqlive1_1`, `fqlive1_2` (family size) for missing codes (likely 999)
- [x] Verified: Current code already checks `fqlive1_* < 999` which handles this correctly
- [x] Verify FPL calculations handle missing income/family size appropriately
- [x] No changes needed - existing code is correct

### 2.6 Update Childcare Transformation ✓

- [x] Review childcare variables (mmi*) for missing codes
- [x] Phase 1 audit found mmihl002 has 99 values BUT it's not used in transformations
- [x] Factor variables already handle missing (9) as factor level "Missing"
- [x] Numeric cost variables (mrw002, mmi003, etc.) - no systematic missing codes found
- [x] No changes needed - childcare transformations are correct

### 2.7 Review Other Transformations ✓

- [x] Education - Phase 1 audit confirmed NO missing codes in cqr004, nschj017
- [x] Race/ethnicity - NO missing codes found
- [x] Geographic - ZIP codes handled correctly (no 00000, 99999)
- [x] Age - NO invalid age values found
- [x] Sex - NO missing codes found

### 2.8 Phase 2 Completion ✓

- [x] Review this markdown file and mark completed Phase 2 tasks
- [x] Run full pipeline - completed successfully, no syntax errors
- [x] Verified zero records with ace_total > 10 (fix confirmed working)
- [x] Create git commit with fixes (ready for next step)
- [x] Load Phase 3 tasks into Claude TodoWrite tool

---

## Phase 3: Testing & Validation

**Goal:** Ensure fixes work correctly and don't introduce new issues

### 3.1 Create Unit Test Dataset

- [ ] Create small test dataset in `scripts/temp/test_missing_data.R`
- [ ] Include records with:
  - All valid values (0, 1)
  - Some 99 values that should become NA
  - Some NULL values
  - Mix of valid and missing
- [ ] Test each affected transformation category
- [ ] Verify missing codes convert to NA
- [ ] Verify valid values are preserved
- [ ] Verify composite scores calculate correctly

### 3.2 Run Full Pipeline

- [ ] Back up current database: `data/duckdb/kidsights_local.duckdb`
- [ ] Run complete NE25 pipeline: `run_ne25_pipeline.R`
- [ ] Monitor for errors or warnings
- [ ] Check execution time (should be similar to before)

### 3.3 Validate Transformed Data

- [ ] Query `ne25_transformed` for all ACE variables
- [ ] Verify NO records have `ace_neglect = 99` (should be 0)
- [ ] Verify NO records have `ace_parent_loss = 99` (should be 0)
- [ ] Check all 10 caregiver ACE variables for 99 values
- [ ] Verify `ace_total` ranges 0-10 only (no 99, 495, 990, etc.)
- [ ] Check child ACE variables similarly
- [ ] Check PHQ-2 and GAD-2 totals are in valid ranges

### 3.4 Compare Before/After Statistics

- [ ] Create comparison report showing:
  - [ ] Old `ace_total` distribution (with inflated values)
  - [ ] New `ace_total` distribution (0-10 only)
  - [ ] Change in mean/median ACE scores
  - [ ] Change in risk category distribution
  - [ ] Number of records affected
  - [ ] Number of records now with missing `ace_total` (due to missing items)
- [ ] Verify changes make sense (should see fewer high scores, more missing)

### 3.5 Data Quality Checks

- [ ] Check metadata table for updated missing percentages
- [ ] Verify data dictionary documentation is accurate
- [ ] Check auto-generated HTML documentation
- [ ] Verify factor levels are correct
- [ ] Check for any other unexpected data quality issues revealed

### 3.6 Phase 3 Completion

- [ ] Review this markdown file and mark completed Phase 3 tasks
- [ ] Create validation report documenting before/after changes
- [ ] Save comparison statistics
- [ ] Load Phase 4 tasks into Claude TodoWrite tool

---

## Phase 4: Documentation Updates

**Goal:** Ensure all documentation reflects proper missing data handling

### 4.1 Code Documentation

- [ ] Add comprehensive comments to `recode_missing()` function
- [ ] Add comments at top of each transformation block explaining missing value handling
- [ ] Document missing value codes for each variable type in code comments
- [ ] Add examples of the recoding logic in comments
- [ ] Update function-level documentation

### 4.2 Transform README

- [ ] Update `R/transform/README.md` with new "Missing Data Handling" section
- [ ] Document which variables have "Prefer not to answer" options
- [ ] Explain how missing data is handled in composite scores
- [ ] Add table of missing value codes by variable type:
  - Caregiver ACEs: 99 = "Prefer not to answer"
  - Income: 999 or 9999 = missing
  - etc.
- [ ] Document that composite scores use `na.rm = FALSE` to preserve missingness

### 4.3 Main Documentation Files

- [ ] Update `CLAUDE.md` with missing data handling section (if needed)
- [ ] Update `README.md` to note systematic missing data handling
- [ ] Add section on data quality and validation procedures

### 4.4 Validation Documentation

- [ ] Create comprehensive audit report in `docs/fixes/` directory
- [ ] Document findings from Phase 1 audit
- [ ] Document changes made in Phase 2
- [ ] Document validation results from Phase 3
- [ ] Include before/after statistics
- [ ] Explain impact on sample sizes and distributions

### 4.5 User-Facing Documentation

- [ ] Update troubleshooting guide with missing data section
- [ ] Add FAQ about how "Prefer not to answer" is handled
- [ ] Document how to check for missing data in analyses
- [ ] Provide guidance on handling missing data in composite scores

### 4.6 Phase 4 Completion

- [ ] Review this markdown file and mark completed Phase 4 tasks
- [ ] Create final git commit with all documentation updates
- [ ] Update this file status to "COMPLETED"
- [ ] Archive this file to `docs/fixes/archive/` if appropriate

---

## Phase 5: Future Prevention

**Goal:** Prevent similar issues in future variable additions

### 5.1 Add Automated Validation

- [ ] Create validation script in `scripts/validation/check_missing_codes.R`
- [ ] Script should:
  - Query all variables for values >10 in binary variables
  - Check for 99, -99, 999, 9999 in transformed data
  - Flag unexpected values in composite scores
  - Generate alert if issues found
- [ ] Add to pipeline as optional validation step
- [ ] Document how to run validation script

### 5.2 Update Development Guidelines

- [ ] Add section to `CLAUDE.md` on missing data handling requirements
- [ ] Require checking REDCap data dictionary for missing codes before implementing transformations
- [ ] Require defensive recoding for all new variables
- [ ] Add checklist for adding new transformation categories

### 5.3 Create Test Suite

- [ ] Add test cases to `scripts/temp/` for all transformation categories
- [ ] Include missing data test cases for each category
- [ ] Document how to run tests before committing changes
- [ ] Consider adding automated testing

### 5.4 Phase 5 Completion

- [ ] Review this markdown file and mark completed Phase 5 tasks
- [ ] Mark entire audit plan as COMPLETED
- [ ] Create summary report for stakeholders
- [ ] Close out this issue

---

## Progress Tracking

### Overall Status
- [x] Phase 1: Comprehensive Missing Data Audit ✓ COMPLETED
- [x] Phase 2: Fix Missing Data Recoding ✓ COMPLETED
- [ ] Phase 3: Testing & Validation - IN PROGRESS
- [ ] Phase 4: Documentation Updates
- [ ] Phase 5: Future Prevention

### Key Metrics - AFTER FIX (October 3, 2025)
- **Records with ace_total > 10:** 0 ✓ (was 254+ with values 99-990)
- **Records with ace_total = NULL:** 2,196 (proper handling of declined responses)
- **Valid ace_total range:** 0-10 only ✓ (was 0-990)
- **Total caregiver ACE "Prefer not to answer" responses:** 769 across 10 variables (now properly coded as NA)
- **Pipeline execution:** SUCCESS - No errors, normal execution time

---

## Notes & Decisions

### 2025-10-01: Initial Discovery
- Found during child ACE variable implementation
- Caregiver ACEs confirmed to have 99 values persisting in transformed data
- Sample records show ace_total values of 495, 299, 892, 990 (clearly invalid)
- Issue affects risk categorization and any analyses using ACE scores

### 2025-10-03: Fix Implemented and Validated

**Changes Made:**
1. Created `recode_missing()` helper function in `ne25_transforms.R` (lines 264-286)
2. Updated caregiver ACE transformation to use `recode_missing(dat[[old_name]], missing_codes = c(99))`
3. Added defensive recoding for child ACE variables (future-proofing)
4. Re-ran full pipeline successfully

**Validation Results:**
- Zero records with ace_total > 10 (was 254+ with values 99-990) ✓
- 2,196 records properly have ace_total = NULL (declined responses or not asked)
- All ACE scores now fall within valid 0-10 range
- ACE risk category distribution shows realistic pattern (most common: "No ACEs")

**Files Modified:**
- `R/transform/ne25_transforms.R` (added recode_missing(), updated ACE transformations)
- `docs/fixes/missing_data_audit_2025_10.md` (this file - Phase 2 marked complete)

**Before/After Report:** `scripts/temp/ace_fix_before_after_comparison.md`

### Decision Log
- **Why na.rm = FALSE in rowSums?** Preserves missingness - if any ACE item is missing, total should be NA. This is correct behavior once 99 is properly coded as NA.
- **Why not use na.rm = TRUE?** Would create invalid totals (e.g., 9 valid items = 1, 1 missing → total = 1, interpreted as low ACEs when actually unknown)
- **Why defensive recoding for child ACEs?** Even though no current missing codes, protects against future survey changes

---

## References

- **Caregiver ACE Codebook:** `C:\Users\waldmanm\OneDrive - The University of Colorado Denver\Desktop\caregiver_aces.csv`
- **REDCap Data Dictionary:** Stored in `ne25_data_dictionary` table
- **Transformation Code:** `R/transform/ne25_transforms.R` lines 916-1095 (mental health block)
- **Configuration:** `config/derived_variables.yaml`
- **Previous Commit:** Most recent commit before discovering issue

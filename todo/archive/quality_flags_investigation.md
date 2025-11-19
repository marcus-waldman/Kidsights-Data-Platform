# Data Quality Flags Investigation

**Created:** 2025-11-11
**Status:** Not Started
**Total Flags:** 194 (2 category mismatch, 78 negative correlation, 114 non-sequential)

---

## Phase 1: Category Mismatch Investigation (2 flags)

**Objective:** Investigate items with < 2 observed categories (Mplus requirement)

### Tasks

- [ ] Query CC85 (NE20) observed values and distribution by study
  - Expected: 0,1 (dichotomous)
  - Observed: Only 1 category (n=9, 99.98% missing)
  - Script: `scripts/temp/investigate_cc85_mismatch.py`

- [ ] Query NOM044 (NE25) observed values and distribution by study
  - Expected: 0,1,2 (3 categories)
  - Observed: Only 1 category (n=1, 99.97% missing)
  - Already known: Should be excluded from calibration

- [ ] Cross-reference codebook for expected categories
  - Check `psychometric.expected_categories` field
  - Verify against item_response_crosstab.csv

- [ ] Make exclusion recommendation
  - If < 2 categories observed: Recommend exclusion
  - If data quality issue: Investigate upstream source
  - Document decision rationale

- [ ] Load Phase 2 tasks into Claude todo list
  - Use TodoWrite tool to add Phase 2 tasks
  - Mark Phase 1 as complete

---

## Phase 2: Negative Correlation Analysis (78 flags)

**Objective:** Determine if negative age-response correlations are valid or problematic

### Part 2A: NSCH Strong Negative Correlations (16 flags, r ≤ -0.30)

**CRITICAL**: 10 NSCH items with r < -0.81

- [ ] Investigate DD299 (NSCH21: r=-0.827, NSCH22: r=-0.818)
  - Query age distribution by response value
  - Check codebook for item wording and expected trajectory
  - Verify if item is age-restricted or reverse-coded

- [ ] Investigate EG24a (NSCH21: r=-0.825)
  - Query age distribution by response value
  - Check codebook for item wording

- [ ] Investigate EG26a (NSCH21: r=-0.825)
  - Query age distribution by response value
  - Check codebook for item wording

- [ ] Investigate EG20b_2 (NSCH21: r=-0.824)
  - Query age distribution by response value
  - Check codebook for item wording

- [ ] Investigate DD207, EG30a, EG32a, EG33a (NSCH22: r < -0.82)
  - Batch query for all 4 items
  - Check if these are related constructs (same domain)
  - Review NSCH helper function for potential reverse coding bug

- [ ] Investigate remaining strong correlations (6 items)
  - AA65 (NE20: r=-0.366, NE25: r=-0.141)
  - CC25 (NE25: r=-0.258)
  - CC26 (NE25: r=-0.297)
  - EG7_2 (NE25: r=-0.277)
  - EG33a (NE25: r=-0.247)
  - Create age × response scatter plots

- [ ] Determine validity threshold
  - Which correlations are developmentally valid? (e.g., crawling)
  - Which indicate data quality issues?
  - Document decision criteria

### Part 2B: NE25 Moderate Correlations (55 flags, -0.30 < r ≤ -0.10)

- [ ] Categorize by domain
  - AA items (early developmental milestones): Expected negative correlation?
  - CC items (cognitive/communication): Expected negative correlation?
  - EG items (engagement): Unexpected negative correlation
  - PS items (parenting stress): Review expected direction

- [ ] Sample investigation (10 highest magnitude items)
  - Query age distribution for 10 items with r closest to -0.30
  - Check if items are infant-specific (0-12 months)
  - Verify reverse coding in `scripts/irt_scoring/ne25_helper_functions.R`

- [ ] Batch statistical test
  - Test if correlations differ significantly from zero
  - Calculate confidence intervals
  - Flag items where CI excludes developmental validity range

### Part 2C: Minor Correlations (32 flags, r > -0.10)

- [ ] Review for false positives
  - Weak correlations (r > -0.05): Likely noise
  - Sample size considerations: Large n inflates significance
  - Decision: Accept or flag for further review?

- [ ] Document acceptance criteria
  - Define threshold for acceptable negative correlation
  - Justify based on developmental theory and sample size

- [ ] Load Phase 3 tasks into Claude todo list
  - Use TodoWrite tool to add Phase 3 tasks
  - Mark Phase 2 as complete

---

## Phase 3: Non-Sequential Values Investigation (114 flags)

**Objective:** Verify if non-sequential values are intentional or data quality issues

### Part 3A: NE25 PS Items (46 flags)

**Pattern:** All PS items show `0,1,2,9` (9 = "Prefer not to answer")

- [ ] Query PS001-PS049 raw values from ne25_raw table
  - Check if 9 exists in raw data
  - Count n with value = 9

- [ ] Check NE25 helper function missing code handling
  - Review `scripts/irt_scoring/ne25_helper_functions.R`
  - Verify if 9 is recoded to NA for PS items
  - Line reference: PS recoding section

- [ ] Cross-reference with item_response_crosstab.csv
  - Check if y9 column exists for PS items
  - Count of responses with value = 9

- [ ] Decision: Accept or recode?
  - If 9 intentionally retained: Update validation logic to accept
  - If 9 should be NA: Fix helper function
  - Document rationale

### Part 3B: NE25 Authenticity Weight (1 flag)

**Pattern:** `wgt` shows `0.42, 1.0, 1.22, 1.45, 1.63, 1.96`

- [ ] Confirm wgt is authenticity weight, not a category
  - Review authenticity screening documentation
  - Verify wgt is continuous, not categorical

- [ ] Exclude wgt from sequential value checks
  - Update validation logic in Step 12 of calibration pipeline
  - Add metadata_cols list to exempt wgt from checks

### Part 3C: NSCH Missing Codes (67 flags)

**Patterns:** `0,4,94,95,96,97,98` or `0,4,97,98`

- [ ] Review Issue #6 fixes
  - Verify NSCH helper functions recode 94-98 to NA
  - Check `scripts/irt_scoring/nsch_helper_functions.R`
  - Line references: Missing code handling sections

- [ ] Query 5 sample items (DD103, DD201, DD207, EG2_2, EG3_2)
  - Get raw values from nsch_2021_raw and nsch_2022_raw
  - Get transformed values from calibration_dataset_2020_2025
  - Compare to verify missing codes removed

- [ ] Batch validation
  - Query all 67 flagged NSCH items
  - Count records where value >= 90
  - Should be 0 if Issue #6 fixes worked

- [ ] If missing codes still present:
  - Identify which helper function is responsible
  - Review forward/reverse coding logic
  - Apply Issue #6 fix pattern (recode >= 90 to NA before transformation)

- [ ] Re-run calibration pipeline if fixes needed
  - Execute: `prepare_calibration_dataset.R`
  - Verify quality_flags.csv updated
  - Check item_response_crosstab.csv for 94-98 columns (should be absent)

- [ ] Load Phase 4 tasks into Claude todo list
  - Use TodoWrite tool to add Phase 4 tasks
  - Mark Phase 3 as complete

---

## Phase 4: Documentation & Recommendations

**Objective:** Summarize findings and implement pipeline improvements

### Tasks

- [ ] Create investigation report
  - File: `docs/irt_scoring/quality_flags_investigation_report.md`
  - Sections:
    - Executive summary
    - Category mismatch findings (2 items)
    - Negative correlation findings (78 items) with accept/reject decisions
    - Non-sequential value findings (114 items)
    - Recommendations for each flag type

- [ ] Generate exclusion list (if applicable)
  - File: `mplus/excluded_items.txt`
  - Format: One item per line with reason
  - Update codebook.json: Set `calibration_item = false` for excluded items

- [ ] Update calibration pipeline validation logic
  - Exempt wgt from sequential value checks
  - Add developmental validity threshold for negative correlations
  - Document validation criteria in code comments

- [ ] Update quality validation function (Step 12)
  - File: `scripts/irt_scoring/prepare_calibration_dataset.R`
  - Enhancements:
    - Separate flags by severity (ERROR vs WARNING vs INFO)
    - Add developmental validity check for negative correlations
    - Exclude weight variables from categorical checks
    - Add cross-study consistency checks

- [ ] Update codebook with developmental trajectory flags
  - Add `psychometric.expected_age_correlation` field
  - Values: "positive", "negative", "none", "u_shaped"
  - Document items with valid negative correlations

- [ ] Create reusable investigation scripts
  - `scripts/temp/query_item_by_age.R` - Age distribution plots
  - `scripts/temp/query_missing_code_handling.py` - Raw vs transformed comparison
  - `scripts/temp/validate_helper_functions.R` - Unit tests for helper functions

- [ ] Re-run calibration pipeline with fixes
  - Execute: `prepare_calibration_dataset.R`
  - Verify reduced flag count in quality_flags.csv
  - Update CLAUDE.md with new flag counts

- [ ] Archive this task list
  - Move to: `todo/archive/quality_flags_investigation.md`
  - Add completion date and summary

- [ ] Git commit investigation results
  - Commit message: "Complete data quality flag investigation and pipeline improvements"
  - Include: Report, updated validation logic, helper function fixes

---

## Notes

**Flag Count Summary:**
- Category Mismatch: 2 flags (NE20: 1, NE25: 1)
- Negative Correlation: 78 flags (NE20: 4, NE22: 1, NE25: 55, NSCH21: 4, NSCH22: 11, USA24: 3)
- Non-Sequential: 114 flags (NE25: 47, NSCH21: 30, NSCH22: 37)

**Key Questions:**
1. Are strong negative correlations (r < -0.81) in NSCH data due to age restrictions or data quality?
2. Should "Prefer not to answer" (9) be retained or recoded to NA for PS items?
3. Did Issue #6 fixes fully resolve NSCH missing code contamination?

**Dependencies:**
- Codebook JSON for expected categories and item wording
- calibration_dataset_2020_2025 table for queries
- item_response_crosstab.csv for response distribution verification
- Helper functions for missing code recoding logic

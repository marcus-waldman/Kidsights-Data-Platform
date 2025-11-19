# Optimize NE25 Calibration Dataset and Integrate into Pipeline

## Summary

The `ne25_calibration` table currently stores **667 columns** (items + demographics + geography + ACEs + childcare), consuming unnecessary database space. It should be optimized to store only essential calibration data: **id, years, and item columns** (matching the codebook equate structure).

Additionally, the NE25 calibration dataset creation is **not currently part of the NE25 pipeline** and should be integrated as an automatic step.

---

## Current State

### NE25 Calibration Table Structure
- **Table:** `ne25_calibration`
- **Rows:** 3,507
- **Columns:** 667
- **Includes:**
  - Structural: id, years
  - Items: ~200-250 developmental items
  - Demographics: age_in_days, female, race, education, income, fpl
  - Geography: puma, county, tract (+ afact flags)
  - ACE variables: 22 columns
  - Childcare variables: 21 columns
  - Other metadata: language, extraction_id, etc.

### Comparison with Other Study Tables

| Study | Rows | Columns | Structure |
|-------|------|---------|-----------|
| ne20_calibration | 37,546 | 243 | id, years + 241 items |
| ne22_calibration | 2,431 | 243 | id, years + 241 items |
| usa24_calibration | 1,600 | 243 | id, years + 241 items |
| **ne25_calibration** | **3,507** | **667** | **id, years + items + covariates** |
| nsch21_calibration | 20,719 | 32 | id, years + 30 items |
| nsch22_calibration | 19,741 | 39 | id, years + 37 items |

**Issue:** NE25 is the only study-specific table storing full covariates, making it 2.7x larger than necessary.

---

## Proposed Changes

### 1. Optimize NE25 Calibration Dataset Structure

**New Structure:**
```
ne25_calibration (optimized):
├─ id (key variable)
├─ study (study identifier = "NE25")
├─ years (child's age)
├─ authenticity_weight (for weighted IRT estimation)
└─ [codebook items with equate lexicon, in order]
```

**Benefits:**
- Reduces from **667 columns → ~304 columns** (id, study, years, authenticity_weight + 300 items)
- Saves database storage space (~55% reduction)
- Includes authenticity weights for weighted calibration
- Items ordered consistently with codebook.json metadata

**Rationale:**
- Covariates (demographics, geography, ACEs, childcare) are already stored in `ne25_transformed` table
- Calibration workflow needs items + age + weights for weighted IRT parameter estimation
- `authenticity_weight` allows downweighting inauthentic responses in Mplus
- Combined calibration dataset needs unified `wgt` column across all studies

### 2. Integrate Calibration Dataset Creation into NE25 Pipeline

**Current Workflow:**
- NE25 pipeline runs → stores data in `ne25_raw`, `ne25_eligibility`, `ne25_transformed`
- Calibration dataset creation is **separate manual step** via `scripts/irt_scoring/prepare_calibration_dataset.R`

**Proposed Workflow:**
Add Step 10 to NE25 pipeline:
```r
#' Pipeline Steps:
#'   1. Load API credentials
#'   2. Extract REDCap data
#'   3. Minimal data processing
#'   4. Store raw data in DuckDB
#'   5. Data transformation (geographic variables)
#'   6. Eligibility validation
#'   6.5. Authenticity screening & weighting
#'   7. Store transformed data
#'   8. Generate variable metadata
#'   9. Generate data dictionary
#'   10. Create NE25 calibration dataset (NEW)
```

**Implementation:**
- Source `scripts/irt_scoring/create_ne25_calibration_table.R` (new helper script)
- Extract id, study, years, authenticity_weight, and codebook items from `ne25_transformed`
- Filter: `WHERE meets_inclusion = TRUE` (2,831 participants)
  - Includes authentic + eligible (2,635 with weight=1.0)
  - Includes inauthentic + eligible with quality weights (196 with weight=0.42-1.96)
  - Excludes inauthentic with <5 items (authenticity_weight=NA)
- Store in `ne25_calibration` table with optimized structure

### 3. Update Combined Calibration Dataset with Unified Weights

**Current Combined Dataset:**
- `calibration_dataset_2020_2025_restructured` (302 columns)
- Columns: id, study, years + 299 items
- No weight column

**Updated Combined Dataset:**
```
calibration_dataset_2020_2025_restructured (optimized + weighted):
├─ id (key variable)
├─ study (study identifier)
├─ years (child's age)
├─ wgt (unified sample weight)
└─ [codebook items with equate lexicon, in order]
```

**Weight Column Logic:**
```r
wgt = case_when(
  study == "NE25" ~ authenticity_weight,  # 0.42-1.96 for inauthentic, 1.0 for authentic
  TRUE ~ 1.0                               # All other studies (NE20, NE22, USA24, NSCH21, NSCH22)
)
```

**Purpose:**
- Unified `wgt` column enables weighted IRT estimation in Mplus
- Downweights inauthentic NE25 responses (196 participants with 0.42-1.96 weights)
- Treats all other study data as equal weight (1.0)
- Preserves sample size while accounting for response quality uncertainty

---

## Implementation Tasks

- [ ] **Create helper script:** `scripts/irt_scoring/create_ne25_calibration_table.R`
  - Load codebook.json to get equate items in order
  - Query `ne25_transformed` for id, study="NE25", years, authenticity_weight, and item columns
  - Filter: `WHERE meets_inclusion = TRUE` (2,831 participants)
  - Create/replace `ne25_calibration` table with optimized structure (304 columns)

- [ ] **Integrate into NE25 pipeline:** `pipelines/orchestration/ne25_pipeline.R`
  - Add Step 10 after data dictionary generation
  - Call calibration table creation function
  - Add execution metrics (calibration_duration, records_in_calibration)

- [ ] **Update combined calibration dataset creation:** `scripts/irt_scoring/prepare_calibration_dataset.R`
  - Add `wgt` column to combined dataset
  - Logic: `wgt = IF(study == "NE25", authenticity_weight, 1.0)`
  - Update restructured dataset to include wgt column (303 columns: id, study, years, wgt + 299 items)

- [ ] **Update documentation:**
  - `CLAUDE.md`: Note NE25 calibration dataset is auto-created in pipeline
  - `docs/irt_scoring/CALIBRATION_PIPELINE_USAGE.md`: Update to reflect NE25 auto-creation
  - `docs/architecture/PIPELINE_STEPS.md`: Add Step 10 to NE25 pipeline

- [ ] **Test changes:**
  - Run full NE25 pipeline with calibration creation
  - Verify `ne25_calibration` table has 304 columns (id, study, years, authenticity_weight + 300 items)
  - Validate column order matches codebook.json
  - Verify authenticity_weight values: 1.0 for authentic, 0.42-1.96 for inauthentic, range [0.42, 1.96]
  - Verify meets_inclusion filter: 2,831 participants
  - Regenerate combined calibration dataset with wgt column
  - Verify combined dataset has 303 columns (id, study, years, wgt + 299 items)
  - Validate wgt column: 1.0 for all studies except NE25 (which has authenticity_weight values)

---

## Expected Outcome

After implementation:

1. **Space Savings:**
   - NE25 calibration: 667 → 304 columns (~54% reduction)
   - Database size reduction: ~4-5 MB saved

2. **Weighted IRT Calibration:**
   - NE25 includes `authenticity_weight` column for weighted estimation
   - Combined dataset has unified `wgt` column (1.0 for all studies, authenticity_weight for NE25)
   - Mplus can use wgt column for weighted parameter estimation
   - Preserves 2,831 NE25 participants while accounting for response quality

3. **Automation:**
   - NE25 pipeline automatically creates optimized calibration dataset
   - No manual step needed for calibration data preparation

4. **Consistency:**
   - All study-specific calibration tables have similar structure (id, study, years, [weight], items)
   - NE25 structure matches other studies + authenticity weighting
   - Combined dataset has unified weight column for cross-study analysis

5. **Maintainability:**
   - Single source of truth for item selection (codebook.json)
   - Calibration dataset always up-to-date with latest NE25 data
   - meets_inclusion filter ensures consistency with imputation pipeline

---

## Notes

- The combined calibration dataset (`calibration_dataset_2020_2025_restructured`) will be updated to 303 columns (adding `wgt`)
- This issue focuses on making the **study-specific** `ne25_calibration` table consistent + adding weighting capability
- Covariates remain available in `ne25_transformed` for other analyses
- The `wgt` column enables weighted IRT estimation in Mplus, accounting for authenticity screening uncertainty
- `meets_inclusion` filter (2,831 participants) is consistent with imputation pipeline approach
- Authenticity weights range from 0.42-1.96 for inauthentic responses, 1.0 for authentic responses

---

**Priority:** Medium
**Effort:** Small (2-3 hours)
**Impact:** Improves database efficiency and pipeline automation

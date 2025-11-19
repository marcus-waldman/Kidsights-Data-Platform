# Codebook Response_Sets Fix - Task List

**Created:** 2025-11-08
**Last Updated:** 2025-11-08
**Status:** Phase 1 Starting

**Goal:** Add response_sets for 104 items (58 NOM + 46 PS), update transformation pipeline, re-run NE25 pipeline, and prepare 230-item dataset for authenticity screening

---

## Phase 1: Codebook Updates

### 1.1 Validate Generated Response_Sets
- [ ] Review `data/temp/generated_response_sets.json` (104 response_sets)
- [ ] Verify all response_sets have correct structure
- [ ] Confirm sentinel values flagged (46 items with value 9)
- [ ] Confirm 1-indexed items flagged (2 items: EG16a_1, EG16a_2)

### 1.2 Add Response_Sets to Codebook
- [ ] Load current `codebook/data/codebook.json`
- [ ] Load generated response_sets from `data/temp/generated_response_sets.json`
- [ ] Merge 104 new response_sets into codebook's `response_sets` section
- [ ] Validate JSON structure after merge
- [ ] Save updated codebook (backup original first)

### 1.3 Update Item Response_Options References
- [ ] For each of 104 items, update `content.response_options.ne25` to point to new response_set
- [ ] Pattern: `item.content.response_options.ne25 = "ne25_{equate_name_lower}"`
- [ ] Validate all 104 items now have response_options.ne25 defined
- [ ] Verify response_set names match exactly

### 1.4 Validate Updated Codebook
- [ ] Run codebook validation script (if exists)
- [ ] Verify codebook.json is valid JSON
- [ ] Verify all 276 items with lex_equate now have response_options
- [ ] Create backup: `codebook/data/codebook_backup_2025_11_08.json`

### 1.5 Phase 1 Completion
- [ ] Document changes in `todo/codebook_response_sets_fix.md`
- [ ] Commit codebook changes to git
- [ ] **Load Phase 2 tasks into Claude todo list**

---

## Phase 2: Transformation Pipeline Updates

### 2.1 Add PS Items Sentinel Value Recoding
- [ ] Identify transformation category for PS items (check codebook)
- [ ] Add recode logic: `9 → NA` for all 46 PS items
- [ ] Create transformation function or update existing transformer
- [ ] Test transformation on sample PS item (PS001)
- [ ] Verify 9 values are converted to NA

### 2.2 Add 1-Indexed to 0-Indexed Recoding
- [ ] Identify transformation category for EG16a_1 and EG16a_2
- [ ] Add recode logic: `1→0, 2→1, 3→2, 4→3`
- [ ] Test transformation on both items
- [ ] Verify values shifted correctly

### 2.3 Update NE25 Transformer Configuration
- [ ] Add missing_codes definition if needed
- [ ] Ensure recode_missing() is called for PS items
- [ ] Ensure 1-indexed transformation applied to EG items
- [ ] Update transformation documentation

### 2.4 Test Transformations
- [ ] Create test script: `scripts/temp/test_104_item_transformations.R`
- [ ] Load sample of raw data with PS items and EG items
- [ ] Apply transformations
- [ ] Verify sentinel 9 → NA (46 PS items)
- [ ] Verify 1-indexed → 0-indexed (2 EG items)
- [ ] Check for no unintended side effects on other items

### 2.5 Phase 2 Completion
- [ ] Document transformation changes
- [ ] Commit transformation code to git
- [ ] **Load Phase 3 tasks into Claude todo list**

---

## Phase 3: Pipeline Re-run & Validation

### 3.1 Re-run NE25 Pipeline
- [ ] Backup current `ne25_transformed` table
- [ ] Run: `"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R`
- [ ] Monitor for errors during transformation
- [ ] Verify pipeline completes successfully

### 3.2 Validate Transformed Data
- [ ] Query all 276 items from `ne25_transformed`
- [ ] Verify PS items no longer have value 9
- [ ] Verify EG16a items now start at 0 instead of 1
- [ ] Check original 172 items unchanged
- [ ] Verify 58 NOM items have clean values
- [ ] Create validation report

### 3.3 Update Authenticity Screening Data Prep
- [ ] Modify `scripts/authenticity_screening/01_prepare_data.R`
- [ ] Add filter to **EXCLUDE** PS items from item extraction
- [ ] Pattern: `filter(!grepl("^PS", ne25_name))`
- [ ] Verify script now extracts 230 items (172 + 58 NOM)
- [ ] Ensure PS items are excluded

### 3.4 Re-run Data Preparation
- [ ] Run: `scripts/authenticity_screening/01_prepare_data.R`
- [ ] Verify output: N=2,635, J=230, M=? observations
- [ ] Check Stan data structure valid
- [ ] Verify K[j] calculated correctly for all 230 items
- [ ] Save new Stan data files

### 3.5 Re-fit Stan Model
- [ ] Run: `scripts/authenticity_screening/02_fit_full_model.R`
- [ ] Monitor convergence (expect similar to 172-item model)
- [ ] Check parameter estimates reasonable
- [ ] Compare results to 172-item model
- [ ] Save results for 230-item model

### 3.6 Update GitHub Issue #4
- [ ] Document resolution approach
- [ ] Summary: Added response_sets for 58 NOM items, excluded 46 PS items
- [ ] Link to commits
- [ ] Close issue

### 3.7 Phase 3 Completion
- [ ] Document full pipeline fix in `todo/codebook_response_sets_fix.md`
- [ ] Create completion summary
- [ ] Commit all changes
- [ ] **Return to authenticity screening LOOCV tasks** (load from `todo/authenticity_screening_tasks.md`)

---

## Summary Statistics

**Items:**
- Original validated: 172
- NOM items to add: 58
- PS items (excluded from Stan): 46
- **Total for Stan model: 230**
- Total in database (clean): 276

**Transformations Needed:**
- PS items (9 → NA): 46
- EG items (1-indexed → 0-indexed): 2

**Expected Outcomes:**
- Clean database: All 276 items validated
- Stan model input: 230 items (172 + 58 NOM)
- Increased item coverage: +34% items for authenticity screening

---

## Files Created/Modified

### Phase 1
- `codebook/data/codebook.json` (MODIFIED - add 104 response_sets)
- `codebook/data/codebook_backup_2025_11_08.json` (BACKUP)

### Phase 2
- Transformation scripts (MODIFIED - add recoding logic)
- Transformer configuration (MODIFIED)

### Phase 3
- `ne25_transformed` table (UPDATED)
- `scripts/authenticity_screening/01_prepare_data.R` (MODIFIED - exclude PS)
- `data/temp/stan_data_authentic.rds` (UPDATED - 230 items)
- `data/temp/stan_data_inauthentic.rds` (UPDATED - 230 items)
- `results/full_model_params.rds` (UPDATED - 230 items)

---

## Technical Notes

### Response_Set Naming Convention
- Pattern: `ne25_{equate_name_lower}`
- Example: Item CC79y → response_set "ne25_cc79y"

### Item Response_Options Update
```json
{
  "content": {
    "response_options": {
      "ne25": "ne25_cc79y"
    }
  }
}
```

### Transformation Logic Additions
```r
# PS items: Recode 9 → NA
recode_missing(ps_item, missing_codes = c(9))

# EG items: Shift 1-indexed to 0-indexed
recode_1indexed_to_0indexed(eg_item)
```

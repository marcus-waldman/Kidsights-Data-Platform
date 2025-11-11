# Phase 3: Update Combined Calibration Dataset with wgt Column

**Issue:** #5 - Optimize NE25 Calibration Dataset and Integrate into Pipeline
**Status:** Not Started
**Estimated Time:** 40-50 minutes
**Created:** 2025-11-10

---

## Objective

Add unified `wgt` column to combined calibration dataset for weighted IRT estimation in Mplus:
- NE25: `wgt = authenticity_weight` (0.42-1.96 for inauthentic, 1.0 for authentic)
- Other studies: `wgt = 1.0` (NE20, NE22, USA24, NSCH21, NSCH22)
- Update restructured dataset: 302 → 303 columns (id, study, years, wgt + 299 items)

---

## Prerequisites

- [x] Phase 1 completed: Helper script created
- [x] Phase 2 completed: Pipeline integration done
- [x] `ne25_calibration` table has `authenticity_weight` column
- [x] Combined calibration dataset exists: `calibration_dataset_2020_2025_restructured`

---

## Tasks

### 1. Update Restructure Script: Add wgt Column Logic
- [ ] Open `scripts/temp/restructure_calibration_dataset.py`
- [ ] Locate section where columns are selected from original dataset
- [ ] Add wgt column creation logic:
  ```python
  # Add wgt column:
  # - For NE25: use authenticity_weight (if available)
  # - For all other studies: wgt = 1.0

  # After loading calibration_dataset_2020_2025
  calibration_data['wgt'] = calibration_data.apply(
      lambda row: row['authenticity_weight']
                  if row['study'] == 'NE25' and 'authenticity_weight' in row and pd.notna(row['authenticity_weight'])
                  else 1.0,
      axis=1
  )
  ```
- [ ] Update column ordering: `columns_ordered = ['id', 'study', 'years', 'wgt'] + equate_items_present`
- [ ] Update documentation comment: "302 columns" → "303 columns"

### 2. Run Restructure Script
- [ ] Execute restructure script:
  ```bash
  py scripts/temp/restructure_calibration_dataset.py
  ```
- [ ] Monitor output for wgt column creation
- [ ] Verify no errors during execution
- [ ] Check success message shows 303 columns

### 3. Validate Combined Dataset Structure
- [ ] Connect to database and check column count:
  ```python
  import duckdb
  con = duckdb.connect('data/duckdb/kidsights_local.duckdb')
  cols = con.execute('DESCRIBE calibration_dataset_2020_2025_restructured').fetchall()
  print(f'Columns: {len(cols)}')  # Should be 303
  ```
- [ ] Expected: 303 columns
  - id (1)
  - study (1)
  - years (1)
  - wgt (1)  ← NEW
  - items (299)
- [ ] Verify wgt is 4th column (after years, before items)

### 4. Validate wgt Column Values for NE25
- [ ] Query NE25 weight distribution:
  ```sql
  SELECT
    MIN(wgt) as min_wgt,
    MAX(wgt) as max_wgt,
    AVG(wgt) as avg_wgt,
    COUNT(CASE WHEN wgt = 1.0 THEN 1 END) as count_authentic,
    COUNT(CASE WHEN wgt < 1.0 THEN 1 END) as count_weighted
  FROM calibration_dataset_2020_2025_restructured
  WHERE study = 'NE25'
  ```
- [ ] Expected results:
  - min_wgt: ~0.42
  - max_wgt: ~1.96
  - count_authentic: ~2,635
  - count_weighted: ~196

### 5. Validate wgt Column for Other Studies
- [ ] Query non-NE25 studies:
  ```sql
  SELECT
    study,
    COUNT(*) as total_records,
    COUNT(CASE WHEN wgt = 1.0 THEN 1 END) as wgt_equals_1,
    COUNT(CASE WHEN wgt != 1.0 THEN 1 END) as wgt_not_1
  FROM calibration_dataset_2020_2025_restructured
  WHERE study != 'NE25'
  GROUP BY study
  ORDER BY study
  ```
- [ ] Expected: All studies (NE20, NE22, USA24, NSCH21, NSCH22) have wgt = 1.0 for ALL records

### 6. Verify Total Record Count
- [ ] Query total records:
  ```sql
  SELECT COUNT(*) as total FROM calibration_dataset_2020_2025_restructured
  ```
- [ ] Expected: 85,544 records (unchanged from before)
- [ ] Breakdown by study:
  - NE20: 37,546
  - NSCH21: 20,719
  - NSCH22: 19,741
  - NE25: 3,507 (if using eligible filter) OR 2,831 (if using meets_inclusion)
  - NE22: 2,431
  - USA24: 1,600

### 7. Test Sample wgt Values
- [ ] Extract sample of NE25 records:
  ```sql
  SELECT id, study, years, wgt, authentic, authenticity_weight
  FROM calibration_dataset_2020_2025_restructured
  WHERE study = 'NE25'
  ORDER BY wgt ASC
  LIMIT 10
  ```
- [ ] Verify wgt matches authenticity_weight for NE25 records
- [ ] Check lowest wgt values (~0.42) correspond to inauthentic participants

### 8. Update Column Documentation
- [ ] Update script comments to reflect new structure
- [ ] Update any inline documentation showing column counts
- [ ] Note: "302 columns" → "303 columns (added wgt)"

### 9. Create Validation Report
- [ ] Run validation query:
  ```sql
  SELECT
    study,
    COUNT(*) as n_records,
    MIN(wgt) as min_wgt,
    MAX(wgt) as max_wgt,
    AVG(wgt) as avg_wgt,
    COUNT(CASE WHEN wgt = 1.0 THEN 1 END) as n_wgt_1,
    COUNT(CASE WHEN wgt != 1.0 THEN 1 END) as n_wgt_other
  FROM calibration_dataset_2020_2025_restructured
  GROUP BY study
  ORDER BY study
  ```
- [ ] Save output to verify all studies correct
- [ ] Document in Phase 3 completion notes

### 10. Load Phase 4 Tasks
- [ ] **FINAL TASK:** Load `todo/ne25_calibration_phase4_quality_and_docs.md` tasks into Claude todo list

---

## Validation Criteria

**Success:**
- ✅ Combined dataset has 303 columns (id, study, years, wgt + 299 items)
- ✅ wgt column is 4th column (after years)
- ✅ NE25 study has wgt range [0.42, 1.96]
- ✅ NE25 has ~2,635 records with wgt=1.0 (authentic)
- ✅ NE25 has ~196 records with wgt<1.0 (weighted inauthentic)
- ✅ All other studies have wgt=1.0 for ALL records
- ✅ Total record count unchanged: 85,544

**Failure conditions:**
- ❌ Column count != 303
- ❌ wgt column missing or in wrong position
- ❌ NE25 records have wgt=1.0 for all (authenticity_weight not copied)
- ❌ Non-NE25 studies have wgt != 1.0

---

## Expected Output

### Restructure Script Output
```
[INFO] Loading codebook...
[INFO] Extracting equate names in codebook order...
[INFO] Found 309 items with equate lexicon
[INFO] Connecting to database...
[INFO] Current calibration dataset has 809 columns
[INFO] Equate items present in dataset: 299
[INFO] Equate items missing from dataset: 10

[INFO] Creating new calibration dataset with ordered columns...
[INFO] New column order: id, study, years, wgt, + 299 items

[INFO] Adding wgt column:
      - NE25: wgt = authenticity_weight
      - Other studies: wgt = 1.0

[INFO] Executing SQL query...

================================================================================
RESTRUCTURING COMPLETE
================================================================================

Table name: calibration_dataset_2020_2025_restructured
Rows: 85,544
Columns: 303

Column order:
  1. id (key)
  2. study (study)
  3. years (age)
  4. wgt (weight)  ← NEW
  5-303. 299 items in codebook order

Weight distribution:
  NE25:
    - min: 0.42
    - max: 1.96
    - mean: 0.97
    - count wgt=1.0: 2,635
    - count wgt<1.0: 196
  Other studies: wgt=1.0 for all records

[OK] Calibration dataset restructured successfully!
```

### Validation Query Output
```
study     n_records  min_wgt  max_wgt  avg_wgt  n_wgt_1   n_wgt_other
--------  ---------  -------  -------  -------  --------  -----------
NE20      37,546     1.00     1.00     1.00     37,546    0
NE22      2,431      1.00     1.00     1.00     2,431     0
NE25      3,507      0.42     1.96     0.97     2,635     196
NSCH21    20,719     1.00     1.00     1.00     20,719    0
NSCH22    19,741     1.00     1.00     1.00     19,741    0
USA24     1,600      1.00     1.00     1.00     1,600     0
--------  ---------  -------  -------  -------  --------  -----------
TOTAL     85,544     0.42     1.96     0.998    82,672    196
```

---

## Code Changes Summary

**File:** `scripts/temp/restructure_calibration_dataset.py`

**Change 1:** Add wgt column creation (after loading data)
```python
# Add wgt column for weighted IRT estimation
# NE25: use authenticity_weight if available
# Other studies: wgt = 1.0
calibration_data['wgt'] = calibration_data.apply(
    lambda row: row.get('authenticity_weight', 1.0)
                if row['study'] == 'NE25' and pd.notna(row.get('authenticity_weight'))
                else 1.0,
    axis=1
)
```

**Change 2:** Update column ordering
```python
# OLD: columns_ordered = ['id', 'study', 'years'] + equate_items_present
# NEW:
columns_ordered = ['id', 'study', 'years', 'wgt'] + equate_items_present
```

**Change 3:** Update documentation
```python
# OLD: "302 columns"
# NEW: "303 columns (id, study, years, wgt + 299 items)"
```

---

## Notes

- wgt column enables weighted IRT estimation in Mplus
- NE25 authenticity_weight values (0.42-1.96) represent response quality uncertainty
- All other studies have no authenticity screening, so wgt=1.0 (equal weighting)
- Total sample size preserved (85,544 records)
- Column position important: wgt must be 4th column (after years, before items)

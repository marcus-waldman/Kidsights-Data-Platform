# Phase 1: Create NE25 Calibration Helper Script

**Issue:** #5 - Optimize NE25 Calibration Dataset and Integrate into Pipeline
**Status:** Not Started
**Estimated Time:** 45-60 minutes
**Created:** 2025-11-10

---

## Objective

Create a standalone helper script (`scripts/irt_scoring/create_ne25_calibration_table.R`) that:
- Extracts 24 calibration items from codebook.json
- Queries `ne25_transformed` with `meets_inclusion=TRUE` filter (2,831 records)
- Creates optimized `ne25_calibration` table with 27 columns (id, years, authenticity_weight + 24 items)
- Replaces bloated 667-column table (~97% size reduction)

---

## Prerequisites

- [x] `ne25_transformed` table exists with `meets_inclusion` column
- [x] `ne25_transformed` table has `authenticity_weight` column
- [x] Codebook.json has 24 items marked with `calibration_item: true`
- [x] Database: `data/duckdb/kidsights_local.duckdb`

---

## Tasks

### 1. Create Script File Structure
- [ ] Create new file: `scripts/irt_scoring/create_ne25_calibration_table.R`
- [ ] Add roxygen2 header documentation
  - Purpose: Create optimized NE25 calibration table
  - Parameters: codebook_path, db_path, verbose
  - Return: Invisible list with metrics
  - Examples: Standalone usage

### 2. Implement Codebook Parsing
- [ ] Load codebook.json with `jsonlite::fromJSON()`
- [ ] Extract items where `psychometric.calibration_item == true`
- [ ] Build mapping: `ne25` lexicon → `equate` lexicon
- [ ] Expected: 24 calibration items
- [ ] Log item count and sample item names

### 3. Implement Database Connection
- [ ] Connect to DuckDB (read-write mode)
- [ ] Verify `ne25_transformed` table exists
- [ ] Check required columns: `meets_inclusion`, `authenticity_weight`, `years_old`
- [ ] Handle connection errors gracefully

### 4. Implement Data Query
- [ ] SQL query:
  ```sql
  SELECT record_id, pid, years_old, authenticity_weight,
         {24 calibration item columns}
  FROM ne25_transformed
  WHERE meets_inclusion = TRUE
  ```
- [ ] Expected: 2,831 records
- [ ] Log record count

### 5. Implement Data Transformation
- [ ] Rename calibration items from `ne25` lexicon to `equate` lexicon (uppercase)
- [ ] Create integer IDs: `250311000001` to `250311002831`
  - Format: `250311` (prefix) + `pid` (6 digits) + `record_id` (5 digits)
- [ ] Rename `years_old` → `years`
- [ ] Keep only: `id`, `years`, `authenticity_weight`, {24 items}
- [ ] Final column count: 27 (3 metadata + 24 items)

### 6. Implement Database Write
- [ ] Drop existing `ne25_calibration` table if exists
- [ ] Insert optimized table (27 columns, 2,831 records)
- [ ] Create index on `id` column
- [ ] Create index on `years` column
- [ ] Commit transaction

### 7. Implement Validation Checks
- [ ] Verify record count: exactly 2,831
- [ ] Verify column count: exactly 27
- [ ] Check `authenticity_weight` range: [0.42, 1.96]
- [ ] Check age range: reasonable values (0-6 years)
- [ ] Validate no missing values in `id`, `years`
- [ ] Log validation results

### 8. Test Standalone Execution
- [ ] Run script from command line:
  ```bash
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/create_ne25_calibration_table.R
  ```
- [ ] Verify output logs show:
  - "Loaded 24 calibration items from codebook"
  - "Queried 2,831 records with meets_inclusion=TRUE"
  - "Created ne25_calibration table: 27 columns"
  - Validation checks passed

### 9. Verify Database Output
- [ ] Query table structure:
  ```sql
  PRAGMA table_info(ne25_calibration);
  ```
- [ ] Expected columns (27 total):
  - id (INTEGER)
  - years (DOUBLE)
  - authenticity_weight (DOUBLE)
  - {24 calibration items in equate lexicon}
- [ ] Check indexes exist on `id` and `years`
- [ ] Verify table size: ~0.5 MB (vs 15 MB bloated version)

### 10. Load Phase 2 Tasks
- [ ] **FINAL TASK:** Load `todo/ne25_calibration_phase2_pipeline_integration.md` tasks into Claude todo list

---

## Validation Criteria

**Success:**
- ✅ Script executes without errors
- ✅ `ne25_calibration` table has exactly 27 columns
- ✅ `ne25_calibration` table has exactly 2,831 records
- ✅ `authenticity_weight` range: [0.42, 1.96]
- ✅ Column names match equate lexicon (uppercase)
- ✅ Indexes created on id and years

**Failure conditions:**
- ❌ Record count != 2,831 (filter issue)
- ❌ Column count != 27 (item extraction issue)
- ❌ Missing `authenticity_weight` column
- ❌ Database write fails

---

## Expected Output

```
================================================================================
CREATE NE25 CALIBRATION TABLE
================================================================================

[1/7] Loading codebook from: codebook/data/codebook.json
      Loaded 24 calibration items from codebook
      Sample items: DD205, DD207, DD299, EG5a, EG15_2

[2/7] Connecting to database: data/duckdb/kidsights_local.duckdb
      Verified ne25_transformed table exists
      Required columns present: meets_inclusion, authenticity_weight, years_old

[3/7] Querying NE25 data with meets_inclusion filter
      Loaded 2,831 records (meets_inclusion=TRUE)

[4/7] Transforming data
      Renamed 24 items to equate lexicon
      Created integer IDs (250311000001 to 250311002831)
      Final structure: 27 columns (id, years, authenticity_weight, 24 items)

[5/7] Writing to database
      Dropped existing ne25_calibration table
      Inserted 2,831 records with 27 columns
      Created indexes on id and years

[6/7] Validating output
      Record count: 2,831 ✓
      Column count: 27 ✓
      Weight range: [0.4218, 1.9615] ✓
      Age range: [0.03, 5.98] ✓

[7/7] Complete
      Table: ne25_calibration
      Size: ~0.5 MB (97% reduction from bloated version)
      Records: 2,831
      Columns: 27

================================================================================
```

---

## Reference Files

- **Codebook:** `codebook/data/codebook.json`
- **Database:** `data/duckdb/kidsights_local.duckdb`
- **Source table:** `ne25_transformed` (meets_inclusion column)
- **Target table:** `ne25_calibration` (optimized)

---

## Notes

- This helper script is designed for standalone execution AND pipeline integration
- Uses `meets_inclusion=TRUE` filter (consistent with imputation pipeline)
- Includes 2,831 participants: 2,635 authentic + 196 weighted inauthentic
- Excludes 2,127 inauthentic with <5 items (authenticity_weight=NA)
- Storage reduction: 667 columns → 27 columns (~97% smaller)

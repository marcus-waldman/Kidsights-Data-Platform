# NSCH Harmonization Implementation

**Created:** 2025-11-13
**Status:** Phase 1 - In Progress
**Goal:** Add harmonization stage to NSCH pipeline to create lex_equate columns with 0-based, reverse-coded values

---

## Overview

This project adds a harmonization transformation step to the NSCH pipeline that:
- Appends harmonized columns with lex_equate names (e.g., DD201, DD299) to existing NSCH tables
- Applies 0-based encoding (minimum value = 0)
- Applies study-specific reverse coding from codebook (`reverse_by_study.cahmi21`, `reverse_by_study.cahmi22`)
- Uses codebook response_sets as single source of truth for missing value recoding
- Preserves all records (no age filtering)
- Integrates as Step 5 in main NSCH pipeline

**Table Changes:**
- Rename: `nsch_2021_raw` → `nsch_2021`
- Rename: `nsch_2022_raw` → `nsch_2022`
- Add ~30 harmonized columns to `nsch_2021`
- Add ~42 harmonized columns to `nsch_2022`

---

## Phase 1: Archive & Setup

**Goal:** Prepare codebase and database for harmonization work

### Tasks

- [x] Archive existing todo/*.md files to todo/archive/
- [x] Create todo/nsch_harmonization_phases.md (this file)
- [ ] Rename database table: nsch_2021_raw → nsch_2021
- [ ] Rename database table: nsch_2022_raw → nsch_2022
- [ ] Update pipelines/python/nsch/insert_nsch_database.py (table name references)
- [ ] Update scripts/irt_scoring/recode_nsch_2021.R (table name references)
- [ ] Update scripts/irt_scoring/recode_nsch_2022.R (table name references)
- [ ] Search for any other references to `nsch_20XX_raw` and update
- [ ] Test that renamed tables work correctly
- [ ] **Load Phase 2 tasks into Claude todo list**

**Deliverables:**
- ✅ Archived todo files
- ✅ Phased tasklist created
- Database tables renamed
- All code updated to use new table names
- Phase 2 tasks loaded in Claude

---

## Phase 2: Core Harmonization (R Functions)

**Goal:** Create reusable R functions for codebook-driven harmonization

### Tasks

- [ ] Create directory: R/transform/nsch/
- [ ] Create R/transform/nsch/harmonize_nsch_core.R with:
  - Codebook loading from codebook/data/codebook.json
  - Extract items with lexicons for specified study (cahmi21/cahmi22)
  - Load raw NSCH data from DuckDB (nsch_{year} table)
  - For each item:
    - Get response_set name from codebook
    - Recode missing values (only keep values in response_set)
    - Get reverse flag from `reverse_by_study.{study}` (with fallback to default)
    - Apply transformation: forward (y-min) or reverse (y-min then abs(y-max))
    - Store with lex_equate name
  - Return data frame with HHID + harmonized columns
- [ ] Create R/transform/nsch/harmonize_nsch_2021.R wrapper
  - Calls harmonize_nsch_core(year=2021, study="cahmi21")
  - Default db_path parameter
- [ ] Create R/transform/nsch/harmonize_nsch_2022.R wrapper
  - Calls harmonize_nsch_core(year=2022, study="cahmi22")
  - Default db_path parameter
- [ ] Create scripts/nsch/test_harmonization.R for manual testing
  - Load harmonized data for 2021 and 2022
  - Check column count (30 for 2021, 42 for 2022)
  - Check min values = 0 for all harmonized columns
  - Check reverse coding spot checks (DD299, DD103)
- [ ] Run test script and verify transformations work correctly
- [ ] **Load Phase 3 tasks into Claude todo list**

**Deliverables:**
- Core harmonization function (codebook-driven)
- Year-specific wrappers for 2021 and 2022
- Test script showing transformations work
- Phase 3 tasks loaded in Claude

**Key Logic:**
```r
# Missing value recoding (response_set driven)
response_set_name <- codebook$items[[item]]$content$response_options[[study]]
valid_values <- sapply(codebook$response_sets[[response_set_name]], function(x) x$value)
y <- ifelse(y %in% valid_values, y, NA_real_)

# Reverse coding (study-specific)
reverse_flag <- codebook$items[[item]]$scoring$reverse_by_study[[study]]
if (is.null(reverse_flag)) reverse_flag <- codebook$items[[item]]$scoring$reverse %||% FALSE

if (reverse_flag) {
  y <- y - min(y, na.rm=T)           # Make 0-based
  y <- abs(y - max(y, na.rm=T))      # Reverse
} else {
  y <- y - min(y, na.rm=T)           # Just 0-based
}
```

---

## Phase 3: Pipeline Integration (Python)

**Goal:** Integrate harmonization into NSCH pipeline and database

### Tasks

- [ ] Create pipelines/python/nsch/harmonize_nsch_data.py:
  - Takes --year parameter (2021 or 2022)
  - Calls R harmonization function via R Executor utility
  - Receives data frame with HHID + harmonized columns
  - For each harmonized column:
    - ALTER TABLE nsch_{year} ADD COLUMN {col} DOUBLE (if not exists)
    - UPDATE nsch_{year} SET {col} = value FROM harmonized_df WHERE HHID matches
  - Create indexes on harmonized columns
  - Log results (columns added, records updated)
- [ ] Create scripts/nsch/harmonize_nsch.py standalone utility:
  - Wrapper script for easy command-line usage
  - python scripts/nsch/harmonize_nsch.py --year 2021
  - python scripts/nsch/harmonize_nsch.py --year 2022
- [ ] Update scripts/nsch/process_all_years.py:
  - Add HARMONIZE_YEARS = [2021, 2022] constant
  - Add Step 5 after step4_insert_raw()
  - if year in HARMONIZE_YEARS: step5_harmonize(year)
  - Log harmonization step (or skip message for other years)
- [ ] Test standalone harmonization script on 2021
- [ ] Verify harmonized columns added to nsch_2021 table
- [ ] Test standalone harmonization script on 2022
- [ ] Verify harmonized columns added to nsch_2022 table
- [ ] **Load Phase 4 tasks into Claude todo list**

**Deliverables:**
- Python database integration script
- Standalone harmonization utility
- Updated main pipeline with Step 5
- Harmonized columns added to both tables
- Phase 4 tasks loaded in Claude

**Database Operations:**
```sql
-- Add columns
ALTER TABLE nsch_2021 ADD COLUMN IF NOT EXISTS DD201 DOUBLE;
ALTER TABLE nsch_2021 ADD COLUMN IF NOT EXISTS DD299 DOUBLE;
-- ... (repeat for all ~30 columns)

-- Update values
UPDATE nsch_2021
SET DD201 = harmonized.DD201
FROM harmonized_values AS harmonized
WHERE nsch_2021.HHID = harmonized.HHID;
```

---

## Phase 4: Validation & Documentation

**Goal:** Validate harmonization correctness and optimize calibration workflow

### Tasks

- [ ] Create scripts/nsch/validate_harmonization.R validation script:
  - **Check 1: Column Count**
    - nsch_2021: Should have 30 new harmonized columns
    - nsch_2022: Should have 42 new harmonized columns
  - **Check 2: Zero-Based Encoding**
    - All harmonized columns: min(col, na.rm=T) == 0
  - **Check 3: Reverse Coding Verification**
    - DD299 (cahmi21 reverse=False): Positive correlation with raw DISTRACTED
    - DD103 (cahmi21 reverse=True): Negative correlation with raw SIMPLEINST
    - Spot check 5-10 items per year
  - **Check 4: Missing Value Handling**
    - Count NAs in harmonized columns
    - Verify values >= 90 in raw → NA in harmonized (for applicable items)
  - **Check 5: Correlation Test**
    - For sample items, manually compute expected transformation
    - Verify harmonized column matches exactly (cor ~ 1.0)
  - Generate validation report (pass/fail for each check)
- [ ] Update scripts/irt_scoring/recode_nsch_2021.R:
  - Check if harmonized columns exist in nsch_2021 table
  - If yes: Load pre-harmonized columns directly (fast path)
  - If no: Run on-demand transformation with warning (backward compatibility)
  - Add message showing which path was used
- [ ] Update scripts/irt_scoring/recode_nsch_2022.R:
  - Same logic as 2021 (fast path vs. backward compatibility)
- [ ] Run validation script on nsch_2021
- [ ] Run validation script on nsch_2022
- [ ] Verify all validation checks pass
- [ ] Test calibration workflow with pre-harmonized columns
- [ ] Measure speedup (should be 6-18x faster)
- [ ] Create docs/nsch/HARMONIZATION.md documentation:
  - Overview of harmonization process
  - Transformation logic (0-based, reverse coding)
  - Codebook integration (response_sets, reverse_by_study)
  - How to run harmonization
  - How to validate results
  - Extending to future years
- [ ] **Mark project complete**

**Deliverables:**
- Validation script with 5 checks
- Updated calibration scripts (fast path using pre-harmonized columns)
- All validation checks passing
- Performance improvement measured and documented
- Complete HARMONIZATION.md documentation
- Project complete!

**Expected Validation Output:**
```
[OK] nsch_2021: 30 harmonized columns found
[OK] nsch_2022: 42 harmonized columns found
[OK] All columns 0-based (min=0)
[OK] DD299: Reverse coding correct (cor=0.98, expected positive)
[OK] DD103: Reverse coding correct (cor=-0.98, expected negative)
[OK] Missing values: 1,234 raw values >= 90 → NA in harmonized
[OK] Correlation test: All items match expected transformation
[OK] Validation complete - ALL CHECKS PASSED
```

---

## Notes

**Codebook Requirements (Verified):**
- ✅ 30 CAHMI21 items have complete metadata (lexicons, response_options, reverse_by_study)
- ✅ 42 CAHMI22 items have complete metadata
- ✅ 8 CAHMI21 response_sets defined
- ✅ 14 CAHMI22 response_sets defined
- ✅ 28 items have study-specific reverse coding

**Performance Estimates:**
- Initial harmonization: ~30-45 seconds per year
- Calibration workflow speedup: 6-18x faster (2-3 min → 10-20 sec)
- Disk overhead: +10-15 MB per year (minimal)

**Design Principles:**
- ✅ Codebook is single source of truth (no hardcoded values)
- ✅ Study-specific overrides (reverse_by_study.cahmi21/cahmi22)
- ✅ 0-based encoding (min=0 for all harmonized columns)
- ✅ No age filtering (preserve all records)
- ✅ No column prefix (use bare lex_equate names like DD201)
- ✅ Extensible to future years (codebook updates + wrapper function)

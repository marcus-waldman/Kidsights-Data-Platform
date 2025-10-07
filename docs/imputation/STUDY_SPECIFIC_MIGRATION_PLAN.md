# Imputation Pipeline: Study-Specific Migration Plan

**Goal:** Refactor imputation pipeline to support multiple studies (ne25, future ia26, co27, etc.) by adopting study-specific naming conventions for files, directories, and database tables.

**Strategy:** Drop existing tables and rerun pipeline to validate changes (cleaner than migration).

**Status:** Planning Phase
**Created:** October 2025

---

## Overview

### Current State (Study-Agnostic)
```
scripts/imputation/
├── 01_impute_geography.py
├── 02_impute_sociodemographic.R
├── 02b_insert_sociodem_imputations.py
└── run_full_imputation_pipeline.R

data/imputation/
└── sociodem_feather/

Database tables:
├── imputed_female
├── imputed_puma
└── ... (10 tables total)
```

### Target State (Study-Specific)
```
scripts/imputation/
├── ne25/                          # Study-specific scripts
│   ├── 01_impute_geography.py
│   ├── 02_impute_sociodemographic.R
│   ├── 02b_insert_sociodem_imputations.py
│   └── run_full_imputation_pipeline.R
└── 00_setup_imputation_schema.py # Multi-study schema setup

data/imputation/
└── ne25/                          # Study-specific data
    └── sociodem_feather/

config/imputation/
├── ne25_config.yaml               # Study-specific config
└── imputation_config.yaml         # Deprecated (or becomes default)

Database tables:
├── ne25_imputed_female
├── ne25_imputed_puma
└── ... (10 tables with ne25_ prefix)
```

---

## Phase 1: Directory Structure & File Organization

**Goal:** Create study-specific directories and move files (no code changes yet).

### Tasks

- [ ] **Task 1.1:** Create `scripts/imputation/ne25/` directory
- [ ] **Task 1.2:** Move scripts to ne25/ subdirectory:
  - `01_impute_geography.py`
  - `02_impute_sociodemographic.R`
  - `02b_insert_sociodem_imputations.py`
  - `run_full_imputation_pipeline.R`
- [ ] **Task 1.3:** Keep `00_setup_imputation_schema.py` at root (multi-study)
- [ ] **Task 1.4:** Create `data/imputation/ne25/` directory
- [ ] **Task 1.5:** Move `data/imputation/sociodem_feather/` → `data/imputation/ne25/sociodem_feather/`
- [ ] **Task 1.6:** Update git tracking for moved files

**Verification:**
```bash
ls scripts/imputation/ne25/  # Should show 4 scripts
ls data/imputation/ne25/     # Should show sociodem_feather/
```

---

## Phase 2: Configuration System

**Goal:** Create study-specific configuration with table prefix settings.

### Tasks

- [ ] **Task 2.1:** Create `config/imputation/ne25_config.yaml` from existing `imputation_config.yaml`
- [ ] **Task 2.2:** Add study-specific settings to ne25_config.yaml:
  ```yaml
  # Study identification
  study_id: "ne25"
  study_name: "Nebraska 2025"

  # Paths (study-specific)
  data_dir: "data/imputation/ne25"
  scripts_dir: "scripts/imputation/ne25"

  # Database table prefix
  table_prefix: "ne25_imputed"
  ```
- [ ] **Task 2.3:** Update `python/imputation/config.py`:
  - Add `get_study_config(study_id)` function
  - Add `get_table_prefix(study_id)` function
  - Support both `ne25_config.yaml` and legacy `imputation_config.yaml`
- [ ] **Task 2.4:** Update `R/imputation/config.R`:
  - Add `get_study_config()` function
  - Add `get_table_name()` helper for dynamic table names
  - Update paths to use study-specific directories

**Verification:**
```python
from python.imputation.config import get_study_config, get_table_prefix
config = get_study_config('ne25')
assert config['table_prefix'] == 'ne25_imputed'
assert get_table_prefix('ne25') == 'ne25_imputed'
```

---

## Phase 3: SQL Schema Updates

**Goal:** Update table creation to use study-specific prefixes.

### Tasks

- [ ] **Task 3.1:** Update `sql/imputation/create_sociodem_imputation_tables.sql`:
  - Replace `imputed_female` → `ne25_imputed_female`
  - Replace `imputed_raceG` → `ne25_imputed_raceG`
  - Update all 7 sociodemographic tables
- [ ] **Task 3.2:** Update `sql/imputation/create_imputation_tables.sql`:
  - Replace `imputed_puma` → `ne25_imputed_puma`
  - Replace `imputed_county` → `ne25_imputed_county`
  - Replace `imputed_census_tract` → `ne25_imputed_census_tract`
- [ ] **Task 3.3:** Update `scripts/imputation/00_setup_imputation_schema.py`:
  - Add `--study-id` command-line argument
  - Parameterize table names by study_id
  - Support creating schemas for multiple studies
- [ ] **Task 3.4:** Update `imputation_metadata` table schema:
  - Add `study_id` column (if not already present)
  - Update indexes to include study_id

**Verification:**
```bash
py scripts/imputation/00_setup_imputation_schema.py --study-id ne25
# Check that ne25_imputed_* tables are created
```

---

## Phase 4: Python Scripts Updates

**Goal:** Update Python scripts to use study-specific table names and paths.

### Tasks

- [ ] **Task 4.1:** Update `scripts/imputation/ne25/01_impute_geography.py`:
  - Update feather output path: `data/imputation/ne25/geo_feather/`
  - Update table references: `ne25_imputed_puma`, etc.
  - Add study_id to all INSERT statements
- [ ] **Task 4.2:** Update `scripts/imputation/ne25/02b_insert_sociodem_imputations.py`:
  - Update feather input path: `data/imputation/ne25/sociodem_feather/`
  - Update table references: `ne25_imputed_female`, etc.
  - Load study_id from config
- [ ] **Task 4.3:** Update `python/imputation/helpers.py`:
  - Add `study_id` parameter to `get_completed_dataset()`
  - Add `study_id` parameter to `get_imputed_variable_summary()`
  - Parameterize all table references: `f"{study_id}_imputed_{var}"`
  - Update docstrings with multi-study examples
- [ ] **Task 4.4:** Update helper function imports in `python/imputation/__init__.py`

**Verification:**
```python
from python.imputation.helpers import get_completed_dataset
df = get_completed_dataset(study_id='ne25', imputation_m=1, variables=['female', 'puma'])
assert 'female' in df.columns
```

---

## Phase 5: R Scripts Updates

**Goal:** Update R scripts to use study-specific table names and paths.

### Tasks

- [ ] **Task 5.1:** Update `scripts/imputation/ne25/02_impute_sociodemographic.R`:
  - Load config from `config/imputation/ne25_config.yaml`
  - Update feather output path: `data/imputation/ne25/sociodem_feather/`
  - Read study_id from config
- [ ] **Task 5.2:** Update `scripts/imputation/ne25/run_full_imputation_pipeline.R`:
  - Add study_id parameter
  - Pass study_id to all scripts
  - Update path references
- [ ] **Task 5.3:** Update `R/imputation/helpers.R` (if it exists):
  - Add table name helper functions
  - Parameterize by study_id

**Verification:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/02_impute_sociodemographic.R
# Check feather files created in data/imputation/ne25/sociodem_feather/
```

---

## Phase 6: Database Migration

**Goal:** Drop old tables and prepare for clean pipeline run.

### Tasks

- [ ] **Task 6.1:** Backup existing imputation data (optional, for reference):
  ```sql
  -- Export existing data to CSV (if needed)
  COPY imputed_female TO 'backup/imputed_female.csv' WITH (FORMAT CSV, HEADER);
  -- Repeat for all 10 tables
  ```
- [ ] **Task 6.2:** Drop old imputation tables:
  ```sql
  DROP TABLE IF EXISTS imputed_female;
  DROP TABLE IF EXISTS imputed_raceG;
  DROP TABLE IF EXISTS imputed_educ_mom;
  DROP TABLE IF EXISTS imputed_educ_a2;
  DROP TABLE IF EXISTS imputed_income;
  DROP TABLE IF EXISTS imputed_family_size;
  DROP TABLE IF EXISTS imputed_fplcat;
  DROP TABLE IF EXISTS imputed_puma;
  DROP TABLE IF EXISTS imputed_county;
  DROP TABLE IF EXISTS imputed_census_tract;
  ```
- [ ] **Task 6.3:** Create new ne25-specific tables:
  ```bash
  py scripts/imputation/00_setup_imputation_schema.py --study-id ne25
  ```
- [ ] **Task 6.4:** Verify table structure:
  ```sql
  SELECT table_name FROM information_schema.tables
  WHERE table_name LIKE 'ne25_imputed%' ORDER BY table_name;
  ```

**Verification:**
- No `imputed_*` tables exist (without prefix)
- 10 `ne25_imputed_*` tables exist
- All tables have correct schema with study_id column

---

## Phase 7: End-to-End Pipeline Test

**Goal:** Run full imputation pipeline with new study-specific structure.

### Tasks

- [ ] **Task 7.1:** Run geography imputation:
  ```bash
  py scripts/imputation/ne25/01_impute_geography.py
  ```
  - Verify: `ne25_imputed_puma`, `ne25_imputed_county`, `ne25_imputed_census_tract` tables populated
  - Expected: ~25,000 rows total (5 imputations × ~5,000 ambiguous records)
- [ ] **Task 7.2:** Run sociodemographic imputation:
  ```bash
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/02_impute_sociodemographic.R
  ```
  - Verify: Feather files created in `data/imputation/ne25/sociodem_feather/`
  - Expected: 7 variables × 5 imputations = 35 feather files
- [ ] **Task 7.3:** Insert sociodemographic imputations:
  ```bash
  py scripts/imputation/ne25/02b_insert_sociodem_imputations.py
  ```
  - Verify: 7 `ne25_imputed_*` sociodem tables populated
  - Expected: ~68,000 rows total
- [ ] **Task 7.4:** Validate with helper functions:
  ```python
  from python.imputation.helpers import get_completed_dataset, get_imputed_variable_summary

  # Test completed dataset
  df = get_completed_dataset(study_id='ne25', imputation_m=1, variables=['female', 'raceG', 'puma'])
  print(f"Completed dataset: {len(df)} rows")

  # Test variable summary
  for var in ['female', 'raceG', 'puma']:
      summary = get_imputed_variable_summary(study_id='ne25', variable_name=var)
      print(f"{var}: {summary}")
  ```
- [ ] **Task 7.5:** Run full pipeline script:
  ```bash
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R
  ```

**Success Criteria:**
- All 10 tables populated with correct row counts
- Helper functions work with `study_id='ne25'` parameter
- Feather files in correct directory structure
- No errors in pipeline execution

---

## Phase 8: Documentation Updates

**Goal:** Update all documentation to reflect study-specific conventions.

### Tasks

- [ ] **Task 8.1:** Update `docs/imputation/CART_IMPUTATION_IMPLEMENTATION_PLAN.md`:
  - Add study_id references throughout
  - Update table names to ne25_imputed_*
  - Update file paths to study-specific directories
- [ ] **Task 8.2:** Update `docs/imputation/USING_IMPUTATION_AGENT.md`:
  - Update example queries with study_id parameter
  - Update table names in examples
- [ ] **Task 8.3:** Update `docs/imputation/IMPUTATION_PIPELINE.md` (if exists):
  - Update architecture diagrams
  - Document multi-study support
- [ ] **Task 8.4:** Create `docs/imputation/MULTI_STUDY_GUIDE.md`:
  - Document how to add new studies (ia26, co27, etc.)
  - Provide template for new study configs
  - Document naming conventions
- [ ] **Task 8.5:** Update main `CLAUDE.md`:
  - Update imputation pipeline section
  - Update example commands with study_id

**Verification:**
- All documentation examples use `ne25_imputed_*` table names
- Helper function examples include `study_id='ne25'`
- File paths reference `scripts/imputation/ne25/` and `data/imputation/ne25/`

---

## Phase 9: Git Commit & Cleanup

**Goal:** Commit changes and clean up deprecated files.

### Tasks

- [ ] **Task 9.1:** Remove old files from git:
  ```bash
  git rm scripts/imputation/01_impute_geography.py
  git rm scripts/imputation/02_impute_sociodemographic.R
  git rm scripts/imputation/02b_insert_sociodem_imputations.py
  git rm scripts/imputation/run_full_imputation_pipeline.R
  ```
- [ ] **Task 9.2:** Stage new files:
  ```bash
  git add scripts/imputation/ne25/
  git add config/imputation/ne25_config.yaml
  git add data/imputation/ne25/  # If tracking
  ```
- [ ] **Task 9.3:** Stage modified files:
  ```bash
  git add python/imputation/
  git add R/imputation/
  git add sql/imputation/
  git add docs/imputation/
  ```
- [ ] **Task 9.4:** Review changes:
  ```bash
  git status
  git diff --staged
  ```
- [ ] **Task 9.5:** Create commit:
  ```bash
  git commit -m "Refactor imputation pipeline for multi-study support (ne25-specific naming)"
  ```
- [ ] **Task 9.6:** Deprecate old config (optional):
  - Rename `imputation_config.yaml` → `imputation_config.yaml.deprecated`
  - Or keep as default template for new studies

**Verification:**
- Git history shows file moves (not deletions + additions)
- No broken imports or missing files
- Clean git status

---

## Phase 10: Future Studies Setup

**Goal:** Document process for adding new studies.

### Tasks

- [ ] **Task 10.1:** Create study setup template:
  ```bash
  # Template for adding new study (e.g., ia26)
  mkdir scripts/imputation/ia26
  mkdir data/imputation/ia26
  cp config/imputation/ne25_config.yaml config/imputation/ia26_config.yaml
  # Edit ia26_config.yaml with study-specific settings
  ```
- [ ] **Task 10.2:** Document study-specific configuration:
  - What needs to change for each study?
  - Variable lists (may differ by study)
  - Auxiliary variables (may differ by study)
  - MICE methods (may differ by variable availability)
- [ ] **Task 10.3:** Create validation checklist for new studies
- [ ] **Task 10.4:** Add multi-study query examples:
  ```python
  # Compare imputations across studies
  from python.imputation.helpers import get_completed_dataset

  ne25_df = get_completed_dataset(study_id='ne25', imputation_m=1)
  ia26_df = get_completed_dataset(study_id='ia26', imputation_m=1)
  ```

---

## Rollback Plan (If Needed)

**If migration fails, revert using:**

1. **Restore old file structure:**
   ```bash
   git checkout HEAD~1 scripts/imputation/
   git checkout HEAD~1 config/imputation/
   ```

2. **Restore old tables from backup:**
   ```sql
   COPY imputed_female FROM 'backup/imputed_female.csv' WITH (FORMAT CSV, HEADER);
   -- Repeat for all tables
   ```

3. **Revert code changes:**
   ```bash
   git reset --hard HEAD~1
   ```

---

## Success Metrics

- ✅ All 10 imputation tables use `ne25_` prefix
- ✅ Scripts organized in `scripts/imputation/ne25/` directory
- ✅ Data files in `data/imputation/ne25/` directory
- ✅ Full pipeline runs successfully with new structure
- ✅ Helper functions work with `study_id='ne25'` parameter
- ✅ Documentation updated with study-specific examples
- ✅ Ready to add new studies (ia26, co27, etc.) using same pattern

---

## Estimated Timeline

- **Phase 1:** 15 minutes (directory structure)
- **Phase 2:** 30 minutes (configuration)
- **Phase 3:** 30 minutes (SQL updates)
- **Phase 4:** 45 minutes (Python updates)
- **Phase 5:** 30 minutes (R updates)
- **Phase 6:** 15 minutes (database migration)
- **Phase 7:** 45 minutes (testing)
- **Phase 8:** 30 minutes (documentation)
- **Phase 9:** 15 minutes (git commit)
- **Phase 10:** 15 minutes (future setup)

**Total:** ~4 hours (includes testing and validation)

---

## Notes

- This migration follows the existing pattern from `scripts/raking/ne25/`
- No data loss: tables are dropped and regenerated, but source data (ne25_transformed) is unchanged
- Helper functions maintain backward compatibility during transition
- Future studies (ia26, co27) will follow identical pattern

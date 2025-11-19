# IRT Calibration Migration - Phase 1: Core Function Migration

**Status:** Pending
**Timeline:** Week 1-2
**Goal:** Migrate write_syntax2 and write_syntax2_hrtl functions from Update-KidsightsPublic with minimal modifications

---

## Tasks

### 1.1 Create Directory Structure
- [ ] Create `scripts/irt_scoring/calibration/` directory
- [ ] Create `scripts/irt_scoring/calibration/helpers/` subdirectory
- [ ] Create `scripts/irt_scoring/calibration/README.md` documenting calibration vs scoring distinction

### 1.2 Migrate write_syntax2.R
- [ ] Copy `write_syntax2()` function from `C:\Users\marcu\git-repositories\Update-KidsightsPublic\utils\write_model_constraint_syntax.R` (lines 391-623)
- [ ] Add explicit namespace prefixes:
  - [ ] Replace `select()` → `dplyr::select()`
  - [ ] Replace `filter()` → `dplyr::filter()`
  - [ ] Replace `mutate()` → `dplyr::mutate()`
  - [ ] Replace `str_detect()` → `stringr::str_detect()`
  - [ ] Replace `str_split()` → `stringr::str_split()`
  - [ ] Replace `str_extract()` → `stringr::str_extract()`
  - [ ] Replace `map()` → `purrr::map()`
  - [ ] Replace `map_df()` → `purrr::map_df()`
- [ ] Update function signature to accept parameters instead of global objects:
  ```r
  write_syntax2 <- function(
    codebook_df,           # Data frame with jid, lex_equate, param_constraints
    calibdat,              # Calibration dataset (items only)
    output_xlsx = "mplus/generated_syntax.xlsx",
    verbose = TRUE
  )
  ```
- [ ] Replace hardcoded output path with `output_xlsx` parameter
- [ ] Add return statement with list containing MODEL, CONSTRAINT, PRIOR sections
- [ ] Save to `scripts/irt_scoring/calibration/write_syntax2.R`

### 1.3 Migrate Helper Functions
- [ ] Copy `extract_EG()` function to `scripts/irt_scoring/calibration/write_syntax2.R`
- [ ] Copy `extract_tau()` function to `scripts/irt_scoring/calibration/write_syntax2.R`
- [ ] Add namespace prefixes to helper functions

### 1.4 Migrate write_syntax2_hrtl.R
- [ ] Copy `write_syntax2_hrtl()` function from same file (lines 1-384)
- [ ] Add explicit namespace prefixes (same pattern as write_syntax2)
- [ ] Update function signature to accept parameters:
  ```r
  write_syntax2_hrtl <- function(
    codebook_df,
    calibdat,
    domains,               # List of domain configurations
    output_xlsx = "mplus/generated_syntax_hrtl.xlsx",
    verbose = TRUE
  )
  ```
- [ ] Save to `scripts/irt_scoring/calibration/write_syntax2_hrtl.R`

### 1.5 Create build_equate_table.R Helper
- [ ] Create `scripts/irt_scoring/calibration/helpers/build_equate_table.R`
- [ ] Implement `build_equate_table_from_codebook()` function:
  ```r
  build_equate_table_from_codebook <- function(
    codebook_path = "codebook/data/codebook.json"
  ) {
    # Extract jid and lex_equate from codebook$items
    # Return data frame with columns: jid, lex_equate, lex_kidsight
  }
  ```
- [ ] Test with actual codebook.json

### 1.6 Create Main Orchestrator
- [ ] Create `scripts/irt_scoring/calibration/generate_model_syntax.R`
- [ ] Implement `generate_kidsights_model_syntax()` function:
  ```r
  generate_kidsights_model_syntax <- function(
    scale_name = "kidsights",
    codebook_path = "codebook/data/codebook.json",
    db_path = "data/duckdb/kidsights_local.duckdb",
    output_xlsx = "mplus/generated_syntax.xlsx",
    verbose = TRUE
  ) {
    # 1. Load codebook and build equate table
    # 2. Load calibration dataset from DuckDB
    # 3. Build codebook_df with param_constraints
    # 4. Call write_syntax2()
    # 5. Return syntax result
  }
  ```
- [ ] Add function to build codebook_df from codebook JSON:
  ```r
  build_codebook_df_from_json <- function(codebook, equate, scale_name) {
    # Extract items for scale
    # Build data frame with jid, lex_equate, param_constraints columns
  }
  ```

### 1.7 Update Codebook Structure
- [ ] Review current `codebook/data/codebook.json` structure
- [ ] Check if `constraints` field exists in irt_parameters
- [ ] Rename `constraints` → `param_constraints` (global search/replace)
- [ ] Update `scripts/irt_scoring/update_irt_parameters.R` to use `param_constraints` field
- [ ] Add validation in `scripts/irt_scoring/validate_irt_structure.R` for `param_constraints` field

### 1.8 Test Core Migration
- [ ] Create test script `scripts/temp/test_write_syntax2_migration.R`
- [ ] Test with minimal codebook_df (5-10 items):
  ```r
  codebook_df <- tibble::tibble(
    jid = c(1, 2, 3),
    lex_equate = c("AA102", "AA104", "AA105"),
    param_constraints = c("", "Constrain all to AA102", "")
  )
  ```
- [ ] Test with subset of calibration dataset
- [ ] Verify Excel output has MODEL, CONSTRAINT, PRIOR sheets
- [ ] Verify no namespace errors

### 1.9 Package Dependencies
- [ ] Check if `purrr` package is installed
- [ ] Check if `writexl` package is installed
- [ ] Add installation notes to README if packages missing
- [ ] Document required packages in `scripts/irt_scoring/calibration/README.md`

### 1.10 Documentation
- [ ] Create `scripts/irt_scoring/calibration/README.md`:
  - Explain calibration vs scoring distinction
  - Document write_syntax2 and write_syntax2_hrtl functions
  - List dependencies
  - Provide basic usage examples
- [ ] Add docstrings to all migrated functions
- [ ] Document constraint format (same as Update-KidsightsPublic)

### 1.11 Load Phase 2 Tasks
- [ ] Load tasks from `todo/irt_calibration_migration_phase2.md` into Claude todo list
- [ ] Mark Phase 1 as complete

---

## Success Criteria

✅ write_syntax2 and write_syntax2_hrtl migrated with Kidsights coding standards (explicit namespacing)

✅ Functions accept parameters instead of using global objects

✅ build_equate_table_from_codebook() extracts jid and lex_equate from codebook.json

✅ generate_kidsights_model_syntax() orchestrates end-to-end syntax generation

✅ Test script runs without namespace errors

✅ Excel output matches Update-KidsightsPublic format (MODEL, CONSTRAINT, PRIOR sheets)

---

## Notes

- Keep constraint handling exactly as in Update-KidsightsPublic (text-based param_constraints)
- No YAML translation layer in Phase 1 - this is pure migration
- Focus on getting functions working with minimal changes
- Namespace prefixes are CRITICAL per Kidsights coding standards (CLAUDE.md)

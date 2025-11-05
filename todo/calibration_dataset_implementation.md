# Calibration Dataset Implementation - Task List

**Goal:** Create `calibdat` combining historical Nebraska studies (NE20, NE22, USA24), current NE25 data, and NSCH national benchmarking samples for Kidsights scale recalibration in Mplus.

**Target Output:**
- Mplus .dat file: `mplus/calibdat.dat`
- DuckDB table: `calibration_dataset_2020_2025`

---

## Phase 1: Migrate NSCH Harmonization Functions

**Status:** Not Started
**Estimated Time:** 2-3 hours

### Tasks

- [ ] **1.1** Create `scripts/irt_scoring/helpers/recode_nsch_2021.R`
  - Migrate from `Update-KidsightsPublic/utils/recode_nsch_2021.R`
  - Replace Dropbox Stata file path with `data/nsch/2021/raw.feather`
  - Update to load codebook from `codebook/data/codebook.json`
  - Use `lex_cahmi21` lexicon to map NSCH variables to lex_equate names
  - Return data frame: `id`, `years`, `study="NSCH21"`, {lex_equate items}
  - Add function parameters: `codebook_path`, `nsch_data_path`
  - Handle reverse-coded items (preserve original logic)
  - Add roxygen documentation

- [ ] **1.2** Create `scripts/irt_scoring/helpers/recode_nsch_2022.R`
  - Migrate from `Update-KidsightsPublic/utils/recode_nsch_2022.R`
  - Replace Dropbox Stata file path with `data/nsch/2022/raw.feather`
  - Update to load codebook from `codebook/data/codebook.json`
  - Use `lex_cahmi22` lexicon to map NSCH variables to lex_equate names
  - Return data frame: `id`, `years`, `study="NSCH22"`, {lex_equate items}
  - Add function parameters: `codebook_path`, `nsch_data_path`
  - Add roxygen documentation

- [ ] **1.3** Test NSCH recode functions
  - Source both recode functions
  - Test `recode_nsch_2021()` with actual data
  - Test `recode_nsch_2022()` with actual data
  - Verify output structure: columns present, data types correct
  - Check item coverage: which lex_equate items have data
  - Document any issues or missing data patterns

- [ ] **1.4** Load Phase 2 tasks into Claude todo list
  - Mark Phase 1 as complete
  - Prepare to begin Phase 2

---

## Phase 2: Fix Age Filter Bug & Import Historical Data

**Status:** Not Started
**Estimated Time:** 1-2 hours

### Tasks

- [ ] **2.1** Fix age filter column in `mplus_dataset_prep.R`
  - Open `scripts/irt_scoring/helpers/mplus_dataset_prep.R`
  - Locate lines 234-245 (age filter section)
  - Change `age_in_months` to `months_old` (3 occurrences)
  - Test with age range filter: `age_range = c(0, 72)`
  - Verify no errors when age filter applied

- [ ] **2.2** Create `scripts/irt_scoring/import_historical_calibration.R`
  - Load historical data from KidsightsPublic package: `library(KidsightsPublic); data(calibdat)`
  - Filter to studies: `NE20`, `NE22`, `USA24` (exclude NE25, NSCH)
  - Verify columns: `study`, `id`, `years`, {lex_equate items}
  - Connect to DuckDB: `data/duckdb/kidsights_local.duckdb`
  - Drop table if exists: `historical_calibration_2020_2024`
  - Insert filtered data into table
  - Create indexes on: `study`, `id`
  - Report summary: record counts per study, item missingness by study

- [ ] **2.3** Run historical data import script
  - Execute: `Rscript scripts/irt_scoring/import_historical_calibration.R`
  - Verify DuckDB table created successfully
  - Check record counts: NE20 (expected: ~X), NE22 (~Y), USA24 (~Z)
  - Inspect sample records from each study
  - Document any data quality issues

- [ ] **2.4** Load Phase 3 tasks into Claude todo list
  - Mark Phase 2 as complete
  - Prepare to begin Phase 3

---

## Phase 3: Build Main Calibration Dataset Preparation Script

**Status:** Not Started
**Estimated Time:** 4-5 hours

### Tasks

- [ ] **3.1** Create script skeleton: `scripts/irt_scoring/prepare_calibration_dataset.R`
  - Add header comments: purpose, inputs, outputs
  - Source dependencies: `mplus_dataset_prep.R`, `recode_nsch_2021.R`, `recode_nsch_2022.R`
  - Define main function: `prepare_calibration_dataset()`
  - Set up interactive workflow structure (9 steps)

- [ ] **3.2** Implement Step 1: Load Historical Data
  - Connect to DuckDB: `data/duckdb/kidsights_local.duckdb`
  - Query `historical_calibration_2020_2024` table
  - Display record counts per study (NE20, NE22, USA24)
  - Store in `historical_data` variable

- [ ] **3.3** Implement Step 2: Load NE25 Data
  - Query DuckDB `ne25_transformed` table
  - Apply filter: `eligible = TRUE` (expected: 3,507 records)
  - Load codebook.json to get lex_equate mappings
  - Map items: lowercase database columns → uppercase lex_equate
  - Create composite ID: `paste0("31", "2025", pid, str_pad(record_id, 5, "left", "0"))`
  - Create `years` from `years_old` column
  - Add `study = "NE25"` column
  - Select columns: `study`, `id`, `years`, {203 lex_equate items}
  - Store in `ne25_data` variable

- [ ] **3.4** Implement Step 3: NSCH Sample Size Prompt
  - Prompt user: "NSCH sample size per year (1000 recommended, Inf for all): "
  - Default: 1000
  - Validate: positive integer or Inf
  - Store in `nsch_sample_size` variable

- [ ] **3.5** Implement Step 4: Load NSCH 2021 Data
  - Call `recode_nsch_2021(codebook_path = "codebook/data/codebook.json", nsch_data_path = "data/nsch/2021/raw.feather")`
  - If `nsch_sample_size < Inf`: apply `dplyr::sample_n(nsch_sample_size)`
  - Verify output: `study="NSCH21"`, `id`, `years`, {lex_equate items}
  - Store in `nsch21_data` variable

- [ ] **3.6** Implement Step 5: Load NSCH 2022 Data
  - Call `recode_nsch_2022(codebook_path = "codebook/data/codebook.json", nsch_data_path = "data/nsch/2022/raw.feather")`
  - If `nsch_sample_size < Inf`: apply `dplyr::sample_n(nsch_sample_size)`
  - Verify output: `study="NSCH22"`, `id`, `years`, {lex_equate items}
  - Store in `nsch22_data` variable

- [ ] **3.7** Implement Step 6: Combine & Create Study Indicator
  - Bind rows: `historical_data`, `ne25_data`, `nsch21_data`, `nsch22_data`
  - Create numeric study indicator:
    ```r
    study_num = case_when(
      study == "NE20" ~ 1,
      study == "NE22" ~ 2,
      study == "NE25" ~ 3,
      study == "USA24" ~ 7,
      study == "NSCH21" ~ 5,
      study == "NSCH22" ~ 6
    )
    ```
  - Relocate columns: `study`, `study_num`, `id`, `years`, {items alphabetically}
  - Report dimensions: total records, records per study
  - Calculate missingness: % missing per item, % missing per study
  - Store in `calibdat` variable

- [ ] **3.8** Implement Step 7: Output File Paths Prompt
  - Prompt: "Output .dat file path (default: mplus/calibdat.dat): "
  - Validate path, create directory if needed
  - Store in `dat_file_path` variable

- [ ] **3.9** Implement Step 8: Write Mplus .dat File
  - Use `MplusAutomation::prepareMplusData()` OR `write_mplus_data.R` functions
  - Format: space-delimited, no headers, missing as "."
  - Columns: `study_num`, `id`, `years`, {203 lex_equate items alphabetically}
  - Write to `dat_file_path`
  - Report file size and location

- [ ] **3.10** Implement Step 9: Insert into DuckDB
  - Connect to `data/duckdb/kidsights_local.duckdb`
  - Drop table if exists: `calibration_dataset_2020_2025`
  - Insert `calibdat` data
  - Create indexes: `study`, `study_num`, `id`
  - Report table name and record count

- [ ] **3.11** Implement Step 10: Summary Report
  - Display final record counts by study
  - Display item coverage summary (% present per item)
  - Display file paths written (.dat file, DuckDB table)
  - Display next steps: "Run Mplus calibration with: mplus/calibdat.dat"

- [ ] **3.12** Add error handling and validation
  - Wrap each step in tryCatch for graceful error handling
  - Validate data structure at each step
  - Add informative error messages
  - Add option to resume from checkpoint if error occurs

- [ ] **3.13** Load Phase 4 tasks into Claude todo list
  - Mark Phase 3 as complete
  - Prepare to begin Phase 4

---

## Phase 4: Testing & Validation

**Status:** Not Started
**Estimated Time:** 2-3 hours

### Tasks

- [ ] **4.1** Create test script: `scripts/temp/test_calibration_workflow.R`
  - Set up test environment
  - Source all required functions
  - Define expected outcomes for each test

- [ ] **4.2** Test historical data import
  - Run `import_historical_calibration.R`
  - Verify DuckDB table `historical_calibration_2020_2024` exists
  - Check record counts: NE20, NE22, USA24
  - Inspect first 10 records from each study
  - Verify column structure matches expectations

- [ ] **4.3** Test NSCH recode functions
  - Test `recode_nsch_2021()` returns expected structure
  - Test `recode_nsch_2022()` returns expected structure
  - Check ID uniqueness within each NSCH year
  - Verify `years` column in valid range (0-17)
  - Check item coverage: which items have data

- [ ] **4.4** Test complete calibration workflow
  - Run `prepare_calibration_dataset.R` with NSCH sample size = 100 (small test)
  - Verify `.dat` file created at specified path
  - Verify DuckDB table `calibration_dataset_2020_2025` created
  - Check file size is reasonable (~few MB for test)

- [ ] **4.5** Validate output structure
  - Load `.dat` file and inspect first 20 rows
  - Verify columns: `study_num`, `id`, `years`, {203 items}
  - Check study_num values: 1, 2, 3, 5, 6, 7 (no 4)
  - Verify IDs are unique within study
  - Check `years` in valid range (mostly 0-6, some older for NSCH)

- [ ] **4.6** Compare with Update-KidsightsPublic results
  - Load original calibdat from KidsightsPublic package
  - Compare record counts by study (exclude NE25 from comparison)
  - Compare item coverage patterns
  - Spot-check a few records manually for consistency
  - Document any discrepancies

- [ ] **4.7** Validate item missingness patterns
  - Calculate % missing per item across all studies
  - Calculate % missing per item within NE25 only
  - Verify NE25 has ~21 items with substantial data
  - Identify items with 100% missing in NE25
  - Document expected missingness patterns

- [ ] **4.8** Test Mplus compatibility
  - Attempt to load `.dat` file in Mplus (if available)
  - OR inspect file format manually:
    - Space-delimited values
    - Missing values as "."
    - No column headers
    - Numeric values only
  - Verify file can be read by `read.table()` in R

- [ ] **4.9** Run full-scale test
  - Run `prepare_calibration_dataset.R` with NSCH sample size = 1000
  - Verify execution completes in reasonable time (< 10 minutes)
  - Check final file size (~20-25 MB expected)
  - Verify all studies present in output
  - Document performance metrics

- [ ] **4.10** Document validation results
  - Create summary document: `todo/calibration_dataset_validation_summary.md`
  - Record all test results (pass/fail for each test)
  - Document any issues or unexpected patterns
  - List any remaining limitations or known issues
  - Provide recommendations for production use

- [ ] **4.11** Load Phase 5 tasks into Claude todo list
  - Mark Phase 4 as complete
  - Prepare to begin Phase 5

---

## Phase 5: Documentation & Finalization

**Status:** Not Started
**Estimated Time:** 2-3 hours

### Tasks

- [ ] **5.1** Update CLAUDE.md
  - Add section: "IRT Recalibration Workflow"
  - Document how to create calibration dataset
  - Reference `prepare_calibration_dataset.R`
  - Document expected outputs (.dat file, DuckDB table)
  - Add to Quick Reference section

- [ ] **5.2** Create workflow documentation
  - Create: `docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md`
  - Document complete workflow: data prep → Mplus execution → parameter extraction
  - Include example commands
  - Document dataset structure and study indicators
  - Add troubleshooting section

- [ ] **5.3** Update Pipeline Overview
  - Edit: `docs/architecture/PIPELINE_OVERVIEW.md`
  - Add documentation for calibration dataset creation
  - Explain relationship to IRT scoring pipeline
  - Document data flow: historical data → calibdat → Mplus → updated parameters

- [ ] **5.4** Document helper functions
  - Add roxygen documentation to `recode_nsch_2021.R`
  - Add roxygen documentation to `recode_nsch_2022.R`
  - Add roxygen documentation to `import_historical_calibration.R`
  - Add roxygen documentation to `prepare_calibration_dataset.R`

- [ ] **5.5** Create example usage guide
  - Create: `docs/irt_scoring/CALIBRATION_DATASET_EXAMPLE.md`
  - Provide step-by-step walkthrough with screenshots/output examples
  - Document common use cases
  - Provide troubleshooting tips
  - Add FAQ section

- [ ] **5.6** Update Quick Reference
  - Edit: `docs/QUICK_REFERENCE.md`
  - Add commands for calibration dataset creation
  - Add commands for testing validation
  - Add database query examples for calibration tables

- [ ] **5.7** Git commit all changes
  - Review all modified and new files
  - Create comprehensive commit message
  - Commit to local repository
  - Verify commit includes all expected files

- [ ] **5.8** Create implementation summary
  - Create: `todo/calibration_dataset_completion_summary.md`
  - Document all deliverables created
  - Record test results and validation outcomes
  - List known limitations
  - Provide next steps for Mplus calibration
  - Archive this task list

- [ ] **5.9** Final validation
  - Verify all files committed to git
  - Verify all documentation updated
  - Verify test scripts run successfully
  - Confirm system is ready for production use

---

## Summary Statistics (To Be Updated)

**Total Tasks:** 56 tasks across 5 phases

**Phase Breakdown:**
- Phase 1: 4 tasks (NSCH migration)
- Phase 2: 4 tasks (bug fix + historical import)
- Phase 3: 13 tasks (main script development)
- Phase 4: 11 tasks (testing & validation)
- Phase 5: 9 tasks (documentation)

**Estimated Total Time:** 11-16 hours

**Key Deliverables:**
- 5 new R scripts (1,000+ lines total)
- 2 new DuckDB tables
- 1 Mplus .dat file
- 1 bug fix
- 5+ documentation updates
- Comprehensive test suite

---

## Notes

- Each phase builds on previous phases - complete in order
- Test early and often (don't wait until Phase 4)
- Document issues as they arise
- Use temp scripts for experimentation
- Keep single source of truth: `codebook/data/codebook.json`

---

**Last Updated:** [Current Date]
**Status:** Ready to begin Phase 1

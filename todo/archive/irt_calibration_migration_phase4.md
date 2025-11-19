# IRT Calibration Migration - Phase 4: Testing, Validation & Finalization

**Status:** Pending
**Timeline:** Week 5
**Goal:** Comprehensive testing, Mplus validation, and production readiness

---

## Tasks

### 4.1 Unit Tests for Core Functions
- [ ] Create `tests/testthat/test_write_syntax2.R`
- [ ] Test write_syntax2() with minimal codebook_df:
  - [ ] Unconstrained items generate correct MODEL syntax
  - [ ] Constrained items share parameter labels correctly
  - [ ] 1-PL constraints generated for unconstrained items
  - [ ] Excel output has 3 sheets
  - [ ] Return value has model, constraint, prior components
- [ ] Test constraint parsing for each type:
  - [ ] "Constrain all to X" → shared a and tau labels
  - [ ] "Constrain slope to X" → shared a, different tau
  - [ ] Greater than constraint → correct MODEL CONSTRAINT
  - [ ] Simplex constraint → New(p*) and interpolation equation
- [ ] Test edge cases:
  - [ ] Empty param_constraints (unconstrained item)
  - [ ] Multiple constraints separated by semicolons
  - [ ] Invalid item references in constraints

### 4.2 Unit Tests for Helper Functions
- [ ] Create `tests/testthat/test_build_equate_table.R`
- [ ] Test build_equate_table_from_codebook():
  - [ ] Extracts jid and lex_equate correctly
  - [ ] Filters out items without equate lexicon
  - [ ] Returns data frame with correct columns
- [ ] Create `tests/testthat/test_combine_inp_sections.R`
- [ ] Test combine_inp_sections():
  - [ ] Generates valid TITLE/DATA/VARIABLE when template_inp is NULL
  - [ ] Replaces MODEL section in existing template
  - [ ] Writes .inp file with correct structure
  - [ ] All sections end with semicolons

### 4.3 Integration Tests with Real Data
- [ ] Create `tests/integration/test_kidsights_calibration.R`
- [ ] Test with real calibration_dataset_2020_2025_restructured:
  - [ ] Load full dataset from DuckDB
  - [ ] Generate syntax for kidsights scale
  - [ ] Verify all 416 items present in output
  - [ ] Check MODEL section has correct number of BY statements
  - [ ] Check CONSTRAINT section has expected constraint count
- [ ] Create `tests/integration/test_hrtl_calibration.R`
- [ ] Test write_syntax2_hrtl() with HRTL domains:
  - [ ] Multi-factor MODEL syntax generated
  - [ ] Domain-specific constraints applied
  - [ ] Validate against expected output structure

### 4.4 Mplus Syntax Validation
- [ ] Create `tests/validation/test_mplus_syntax_validity.R`
- [ ] Parse generated .inp file to check:
  - [ ] No syntax errors (balanced parentheses, semicolons)
  - [ ] Variable names in NAMES match MODEL section
  - [ ] CATEGORICAL lists all items
  - [ ] Parameter labels follow naming convention (a_jid, tk_jid)
  - [ ] Constraints reference valid parameter labels
- [ ] If Mplus available, test actual execution:
  - [ ] Run generated .inp in Mplus
  - [ ] Check for ERRORS in .out file
  - [ ] Verify model converges (or document expected warnings)

### 4.5 Constraint System Validation
- [ ] Create `tests/validation/test_constraint_translation.R`
- [ ] Test each constraint type end-to-end:
  - [ ] Create codebook_df with known constraints
  - [ ] Generate syntax
  - [ ] Parse generated MODEL and CONSTRAINT sections
  - [ ] Verify expected Mplus syntax produced
- [ ] Create validation dataset with examples from Update-KidsightsPublic:
  - [ ] Extract constraint examples from Update-KidsightsPublic codebook.xlsx
  - [ ] Generate syntax with migrated write_syntax2
  - [ ] Compare output to Update-KidsightsPublic generated_syntax.xlsx
  - [ ] Verify parameter labels match

### 4.6 Performance Benchmarking
- [ ] Create `tests/performance/benchmark_syntax_generation.R`
- [ ] Benchmark with full calibration dataset (47,084 records, 416 items):
  - [ ] Time write_syntax2() execution
  - [ ] Time Excel file writing
  - [ ] Time .inp file generation
  - [ ] Total workflow time (should be < 60 seconds)
- [ ] Profile memory usage
- [ ] Document performance metrics in README

### 4.7 Error Handling and Messages
- [ ] Review all functions for error handling:
  - [ ] Missing required columns in codebook_df
  - [ ] Invalid constraint syntax in param_constraints
  - [ ] Reference items not found
  - [ ] Empty calibration dataset
  - [ ] Output directory doesn't exist
- [ ] Add informative error messages with suggestions
- [ ] Test error handling with invalid inputs

### 4.8 Cross-Repository Validation
- [ ] Generate .inp from Kidsights-Data-Platform for kidsights scale
- [ ] Generate .inp from Update-KidsightsPublic for same items
- [ ] Compare MODEL sections (should be identical for same constraints)
- [ ] Compare CONSTRAINT sections
- [ ] Document any differences and reasons
- [ ] If differences found, validate which is correct

### 4.9 Documentation Finalization
- [ ] Review all documentation for accuracy:
  - [ ] `scripts/irt_scoring/calibration/README.md`
  - [ ] `docs/irt_scoring/CONSTRAINT_SPECIFICATION.md`
  - [ ] `docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md`
  - [ ] Updated sections in QUICK_REFERENCE.md and CLAUDE.md
- [ ] Ensure all examples are tested and working
- [ ] Add troubleshooting section based on testing findings
- [ ] Create FAQ section for common issues

### 4.10 Production Readiness Checklist
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Mplus syntax validation passing
- [ ] Performance benchmarks acceptable (< 60s for full dataset)
- [ ] Error handling comprehensive
- [ ] Documentation complete and accurate
- [ ] Examples working and documented
- [ ] Code follows Kidsights coding standards (namespace prefixes, etc.)
- [ ] No TODOs or FIXMEs in production code
- [ ] Version documented in CLAUDE.md

### 4.11 Git Commit and Documentation
- [ ] Stage all new and modified files
- [ ] Create comprehensive commit message:
  ```
  Migrate write_syntax2 IRT calibration syntax generation

  Migrates write_syntax2 and write_syntax2_hrtl functions from
  Update-KidsightsPublic repository to enable automated Mplus MODEL
  syntax generation for IRT item calibration.

  Changes:
  - Add scripts/irt_scoring/calibration/ directory structure
  - Migrate write_syntax2.R with Kidsights coding standards
  - Migrate write_syntax2_hrtl.R for HRTL domain models
  - Create helper functions (build_equate_table, combine_inp_sections)
  - Create generate_model_syntax.R orchestrator
  - Add run_calibration_workflow.R interactive workflow
  - Update codebook structure (constraints → param_constraints)
  - Create comprehensive documentation and examples
  - Add unit, integration, and validation tests

  Benefits:
  - Automated MODEL syntax generation (was 30-60 min manual, now <1 min)
  - Both Excel (review) and .inp (execution) outputs
  - Constraint system matches Update-KidsightsPublic (proven approach)
  - Full test coverage for reliability

  Testing:
  - All unit tests passing
  - Integration tests with full calibration dataset (47,084 records)
  - Mplus syntax validation successful
  - Cross-repository validation with Update-KidsightsPublic

  Documentation:
  - scripts/irt_scoring/calibration/README.md
  - docs/irt_scoring/CONSTRAINT_SPECIFICATION.md
  - Updated: MPLUS_CALIBRATION_WORKFLOW.md, QUICK_REFERENCE.md, CLAUDE.md

  🤖 Generated with [Claude Code](https://claude.com/claude-code)

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```
- [ ] Commit all changes
- [ ] Update CLAUDE.md with new version number if applicable

### 4.12 Finalization
- [ ] Mark all phase task files as complete
- [ ] Archive phase task files to `todo/archive/irt_calibration_migration/`
- [ ] Create summary document in archive documenting migration outcomes
- [ ] Clear Claude todo list

---

## Success Criteria

✅ All tests passing (unit, integration, validation)

✅ Performance benchmarks meet targets (< 60s for full dataset)

✅ Cross-repository validation confirms syntax equivalence with Update-KidsightsPublic

✅ Mplus syntax validation successful (no errors when run in Mplus)

✅ Comprehensive error handling with informative messages

✅ Documentation complete, accurate, and tested

✅ Code follows all Kidsights coding standards

✅ Production-ready commit created with comprehensive message

---

## Notes

- Testing is critical - this code generates Mplus syntax that affects research results
- Cross-repository validation ensures migration didn't introduce bugs
- Performance matters - full dataset should process quickly
- Error messages should guide users to solutions, not just report problems
- Documentation should enable new users to understand constraint system

# IRT Calibration Migration - Phase 2: .inp File Generation

**Status:** Pending
**Timeline:** Week 3
**Goal:** Combine generated MODEL syntax with template sections to create complete .inp files

---

## Tasks

### 2.1 Create combine_inp_sections.R Helper
- [ ] Create `scripts/irt_scoring/calibration/helpers/combine_inp_sections.R`
- [ ] Implement `combine_inp_sections()` function:
  ```r
  combine_inp_sections <- function(
    template_inp = NULL,   # Optional base template
    model_syntax,          # Character vector from write_syntax2
    constraint_syntax,     # Character vector from write_syntax2
    prior_syntax,          # Character vector from write_syntax2
    data_file_path,        # Path to .dat file
    variable_names,        # Character vector of variable names
    output_inp             # Output .inp path
  )
  ```
- [ ] If template_inp is NULL, generate basic TITLE/DATA/VARIABLE sections
- [ ] If template_inp provided, parse and replace MODEL section using `modify_mplus_template.R` functions
- [ ] Write combined .inp file

### 2.2 Create Template Generation Function
- [ ] Add `generate_basic_mplus_template()` function to combine_inp_sections.R:
  ```r
  generate_basic_mplus_template <- function(
    data_file_path,
    variable_names,
    title = "Kidsights IRT Calibration"
  ) {
    # Generate TITLE section
    # Generate DATA section (FILE = ...)
    # Generate VARIABLE section (NAMES = ..., MISSING = ALL (.), CATEGORICAL = ...)
    # Generate ANALYSIS section (TYPE = GENERAL, ESTIMATOR = WLSMV, ...)
    # Return character vector
  }
  ```
- [ ] Use existing variable name formatting from `scripts/irt_scoring/helpers/write_mplus_data.R`
- [ ] Set standard ANALYSIS section parameters for IRT calibration

### 2.3 Update generate_model_syntax.R to Create .inp Files
- [ ] Add `output_inp` parameter to `generate_kidsights_model_syntax()`:
  ```r
  generate_kidsights_model_syntax <- function(
    scale_name = "kidsights",
    codebook_path = "codebook/data/codebook.json",
    db_path = "data/duckdb/kidsights_local.duckdb",
    output_xlsx = "mplus/generated_syntax.xlsx",
    output_inp = "mplus/calibration.inp",  # NEW
    template_inp = NULL,                    # NEW
    verbose = TRUE
  )
  ```
- [ ] After calling write_syntax2(), call combine_inp_sections() if output_inp is not NULL
- [ ] Extract variable names from calibration dataset
- [ ] Pass .dat file path (should match what's created by prepare_calibration_dataset.R)

### 2.4 Test .inp Generation
- [ ] Create test script `scripts/temp/test_inp_generation.R`
- [ ] Generate .inp file for kidsights scale with subset of items
- [ ] Validate .inp file structure:
  - [ ] TITLE section exists
  - [ ] DATA section has correct FILE path
  - [ ] VARIABLE section has all item names
  - [ ] ANALYSIS section has correct parameters
  - [ ] MODEL section has factor loadings and thresholds
  - [ ] MODEL CONSTRAINT section has constraint equations
  - [ ] MODEL PRIOR section has priors
- [ ] Test with and without template_inp parameter

### 2.5 Integrate with prepare_calibration_dataset.R
- [ ] Review `scripts/irt_scoring/prepare_calibration_dataset.R`
- [ ] Check what .dat file path it uses (default: `mplus/calibdat.dat`)
- [ ] Ensure generate_model_syntax.R uses same path
- [ ] Test end-to-end: prepare_calibration_dataset → generate_model_syntax

### 2.6 Create Example .inp Files
- [ ] Generate example .inp for kidsights scale (unidimensional)
- [ ] Generate example .inp for subset of items (testing)
- [ ] Save examples to `scripts/irt_scoring/calibration/examples/`
- [ ] Document in README

### 2.7 Mplus Compatibility Validation
- [ ] Use `scripts/irt_scoring/test_mplus_compatibility.R` as reference
- [ ] Create `scripts/irt_scoring/calibration/helpers/validate_inp_syntax.R`
- [ ] Implement basic syntax checks:
  - [ ] All sections end with semicolons
  - [ ] Variable names in NAMES match those in MODEL
  - [ ] No duplicate variable names
  - [ ] CATEGORICAL lists all ordinal items
- [ ] Add validation call to generate_model_syntax.R

### 2.8 Update write_syntax2 Return Format
- [ ] Modify write_syntax2.R to return structured list:
  ```r
  return(list(
    model = model_syntax_vector,
    constraint = constraint_syntax_vector,
    prior = prior_syntax_vector,
    excel_path = output_xlsx
  ))
  ```
- [ ] Update write_syntax2_hrtl.R with same return format
- [ ] Update generate_model_syntax.R to use new return format

### 2.9 Documentation Updates
- [ ] Update `scripts/irt_scoring/calibration/README.md`:
  - Add .inp generation examples
  - Document template_inp parameter usage
  - Explain when to use template vs auto-generation
- [ ] Add docstrings to combine_inp_sections() and generate_basic_mplus_template()

### 2.10 Load Phase 3 Tasks
- [ ] Load tasks from `todo/irt_calibration_migration_phase3.md` into Claude todo list
- [ ] Mark Phase 2 as complete

---

## Success Criteria

✅ combine_inp_sections() creates complete .inp files from syntax components

✅ generate_basic_mplus_template() creates valid TITLE/DATA/VARIABLE/ANALYSIS sections

✅ generate_kidsights_model_syntax() outputs both Excel AND .inp files

✅ Generated .inp files pass basic syntax validation

✅ .inp files use correct .dat file path from prepare_calibration_dataset.R

✅ Examples created for kidsights scale

---

## Notes

- Both Excel (.xlsx) and .inp files should be generated by default
- Excel for human review/documentation, .inp for immediate Mplus execution
- Validation should catch common syntax errors before Mplus execution
- Template parameter allows advanced users to customize TITLE/DATA/VARIABLE sections

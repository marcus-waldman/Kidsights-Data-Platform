# IRT Calibration Migration - Phase 3: Workflow Integration & Documentation

**Status:** Pending
**Timeline:** Week 4
**Goal:** Create interactive workflow, update documentation, and integrate with existing pipeline

---

## Tasks

### 3.1 Create Interactive Calibration Workflow
- [ ] Create `scripts/irt_scoring/run_calibration_workflow.R`
- [ ] Implement interactive prompts:
  - [ ] Select scale (kidsights, psychosocial, hrtl_domains)
  - [ ] Confirm calibration dataset details
  - [ ] Specify output paths (with sensible defaults)
  - [ ] Option to review Excel before creating .inp
- [ ] Add progress indicators for each step
- [ ] Display summary of generated files
- [ ] Provide next steps guidance (review Excel, run Mplus)

### 3.2 Add Calibration Step to prepare_calibration_dataset.R
- [ ] Review `scripts/irt_scoring/prepare_calibration_dataset.R`
- [ ] Add optional parameter `generate_syntax = TRUE`
- [ ] If TRUE, automatically call generate_kidsights_model_syntax() after data export
- [ ] Allow user to specify which scales to generate syntax for

### 3.3 Update MPLUS_CALIBRATION_WORKFLOW.md
- [ ] Open `docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md`
- [ ] Add new Section 2.1 "Generate Mplus Syntax (Automated)" before existing Section 2.1
- [ ] Document interactive workflow usage:
  ```r
  source("scripts/irt_scoring/run_calibration_workflow.R")
  run_calibration_workflow()
  ```
- [ ] Document programmatic usage:
  ```r
  generate_kidsights_model_syntax(
    scale_name = "kidsights",
    output_xlsx = "mplus/generated_syntax.xlsx",
    output_inp = "mplus/calibration.inp"
  )
  ```
- [ ] Add section on reviewing generated Excel file
- [ ] Update time estimates (was 30-60 minutes manual, now ~30 seconds automated)
- [ ] Rename old Section 2.1 to "Generate Mplus Syntax (Manual - Legacy)"
- [ ] Keep manual instructions for reference but mark as legacy approach

### 3.4 Update QUICK_REFERENCE.md
- [ ] Open `docs/QUICK_REFERENCE.md`
- [ ] Find IRT Calibration Pipeline section (around line 245)
- [ ] Add new subsection "Generate Mplus MODEL Syntax":
  ```markdown
  ### Generate Mplus MODEL Syntax

  # Interactive workflow
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_workflow.R

  # Programmatic (kidsights scale)
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" -e "source('scripts/irt_scoring/calibration/generate_model_syntax.R'); generate_kidsights_model_syntax(scale_name='kidsights')"

  # Output: mplus/generated_syntax.xlsx + mplus/calibration.inp
  ```

### 3.5 Update CLAUDE.md Status Section
- [ ] Open `CLAUDE.md`
- [ ] Find "IRT Calibration Pipeline" section (around line 452)
- [ ] Add bullet point about automated MODEL syntax generation:
  ```markdown
  - **MODEL Syntax Generation:** Automated via write_syntax2 (migrated from Update-KidsightsPublic)
  - **Output:** Excel file (review) + complete .inp file (ready for Mplus)
  - **Constraint System:** Text-based param_constraints in codebook
  ```

### 3.6 Create Constraint Specification Guide
- [ ] Create `docs/irt_scoring/CONSTRAINT_SPECIFICATION.md`
- [ ] Document param_constraints field format
- [ ] Provide examples of each constraint type:
  - [ ] "Constrain all to ITEM_NAME" (complete equality)
  - [ ] "Constrain slope to ITEM_NAME" (discrimination only)
  - [ ] "Constrain tau$K to be greater than ITEM_NAME$K" (threshold ordering)
  - [ ] "Constrain tau$K to be less than ITEM_NAME$K" (reverse ordering)
  - [ ] "Constrain tau$K to be a simplex between ITEM1$K and ITEM2$K" (interpolation)
- [ ] Document how constraints translate to Mplus syntax
- [ ] Provide examples from Update-KidsightsPublic codebook
- [ ] Add references to Mplus IRT documentation

### 3.7 Create Examples Directory
- [ ] Create `scripts/irt_scoring/calibration/examples/` directory
- [ ] Generate example .inp for kidsights (full scale)
- [ ] Generate example .inp for psychosocial (bifactor - if using write_syntax2_hrtl)
- [ ] Create example codebook_df CSV showing constraint specifications
- [ ] Create README in examples/ explaining each example

### 3.8 Add Usage Examples to README
- [ ] Update `scripts/irt_scoring/calibration/README.md`
- [ ] Add "Quick Start" section
- [ ] Add "Common Use Cases" section:
  - [ ] Generate syntax for single scale
  - [ ] Generate syntax for multiple scales
  - [ ] Use custom template
  - [ ] Review constraints before generation
- [ ] Add "Troubleshooting" section:
  - [ ] Missing param_constraints field
  - [ ] Invalid constraint syntax
  - [ ] Variable name mismatches

### 3.9 Integration Testing
- [ ] Create `tests/test_calibration_integration.R`
- [ ] Test end-to-end workflow:
  ```r
  # 1. Prepare calibration dataset (assume already done)
  # 2. Generate syntax
  generate_kidsights_model_syntax(
    scale_name = "kidsights",
    output_xlsx = "tests/output/integration_test.xlsx",
    output_inp = "tests/output/integration_test.inp"
  )
  # 3. Validate outputs exist
  # 4. Validate .inp structure
  # 5. Check Excel has 3 sheets (MODEL, CONSTRAINT, PRIOR)
  ```
- [ ] Run test and fix any issues

### 3.10 Load Phase 4 Tasks
- [ ] Load tasks from `todo/irt_calibration_migration_phase4.md` into Claude todo list
- [ ] Mark Phase 3 as complete

---

## Success Criteria

✅ run_calibration_workflow.R provides interactive syntax generation

✅ Documentation updated across all relevant files (MPLUS_CALIBRATION_WORKFLOW.md, QUICK_REFERENCE.md, CLAUDE.md)

✅ CONSTRAINT_SPECIFICATION.md documents all constraint types with examples

✅ Examples directory provides working .inp files for reference

✅ Integration test passes for end-to-end workflow

---

## Notes

- Focus on user experience - workflow should be intuitive
- Documentation should clearly distinguish automated vs manual approaches
- Examples critical for onboarding new users to constraint system
- Keep legacy manual instructions for reference but mark clearly as old approach

# Phase 4: Re-run Quality Validation & Update Documentation

**Issue:** #5 - Optimize NE25 Calibration Dataset and Integrate into Pipeline
**Status:** Not Started
**Estimated Time:** 45-60 minutes
**Created:** 2025-11-10

---

## Objective

Complete the NE25 calibration optimization by:
- Re-running data quality validation on restructured dataset (303 columns with wgt)
- Updating all relevant documentation
- Creating git commit and closing GitHub issue #5

---

## Prerequisites

- [x] Phase 1 completed: Helper script created and tested
- [x] Phase 2 completed: Pipeline integration done
- [x] Phase 3 completed: Combined dataset has wgt column (303 columns)
- [x] Quality validation script updated (from earlier work)

---

## Tasks

### 1. Re-run Quality Validation Script
- [ ] Execute quality validation:
  ```bash
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/validate_calibration_quality.R
  ```
- [ ] Verify script uses `calibration_dataset_2020_2025_restructured` (303 columns)
- [ ] Check console output shows:
  - "Loaded 303 columns" (confirms using restructured dataset)
  - "Kidsights Measurement Tool items: 263"
  - "GSED-PF items: 46"
  - "FLAG 2: NEGATIVE AGE-RESPONSE CORRELATION (Kidsights Measurement Tool items only)"
- [ ] Verify script completes without errors

### 2. Verify Quality Flags Output
- [ ] Check `docs/irt_scoring/quality_flags.csv` was updated
- [ ] Verify file timestamp is recent
- [ ] Check total flag count
- [ ] Confirm 0 PS items in negative correlation flags:
  ```bash
  grep "PS0" docs/irt_scoring/quality_flags.csv | grep "NEGATIVE_CORRELATION" | wc -l
  ```
  Expected: 0 (PS items excluded from age checks)

### 3. Re-render Quality Report
- [ ] Render Quarto report:
  ```bash
  "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe" render docs/irt_scoring/calibration_quality_report.qmd
  ```
- [ ] Check HTML file created: `docs/irt_scoring/calibration_quality_report.html`
- [ ] Verify file size: ~6 MB
- [ ] Check timestamp is recent

### 4. Validate Quality Report Contents
- [ ] Open `calibration_quality_report.html` in browser
- [ ] Verify "FLAG 2" documentation mentions "Kidsights Measurement Tool items only"
- [ ] Check instrument column appears in detailed flags table
- [ ] Verify color coding:
  - Light blue for "Kidsights Measurement Tool"
  - Light orange for "GSED-PF"
- [ ] Check interpretation guide shows instrument legend
- [ ] Verify dataset summary shows 303 columns (if included)

### 5. Update CLAUDE.md
- [ ] Open `CLAUDE.md`
- [ ] Locate "Current Status (October 2025)" section (line ~120)
- [ ] After "### ✅ IRT Calibration Pipeline - Production Ready" section
- [ ] Add new section:
  ```markdown
  ### ✅ NE25 Calibration Table - Optimized (November 2025)
  - **Automated Creation:** Step 11 in NE25 pipeline (no manual intervention)
  - **Streamlined Schema:** 27 columns (id, years, authenticity_weight, 24 calibration items)
  - **Storage Efficiency:** ~0.5 MB (vs 15 MB bloated version, 97% reduction)
  - **Inclusion Filter:** `meets_inclusion=TRUE` (2,831 participants)
  - **Weighted Calibration:** authenticity_weight column (0.42-1.96) for IRT estimation
  - **Database:** `ne25_calibration` table with 2 indexes (id, years)
  - **Execution Time:** ~5-10 seconds (Step 11)
  ```

### 6. Update PIPELINE_STEPS.md
- [ ] Open `docs/architecture/PIPELINE_STEPS.md`
- [ ] Locate NE25 Pipeline section
- [ ] After "Step 10: Generate Interactive Dictionary" (line ~620)
- [ ] Add new step:
  ```markdown
  #### 11. NE25 Calibration Table Creation
  **Executed by:** `scripts/irt_scoring/create_ne25_calibration_table.R`

  **What it does:**
  - Extracts 24 calibration items from codebook.json
  - Queries ne25_transformed with `meets_inclusion=TRUE` filter (2,831 records)
  - Creates optimized table: id, years, authenticity_weight, 24 items (27 columns)
  - Stores in `ne25_calibration` table with indexes
  - Execution time: ~5-10 seconds

  **Output:**
  - `ne25_calibration` table (~0.5 MB, 2,831 records, 27 columns)
  - Ready for IRT calibration dataset export
  - Includes authenticity_weight for weighted estimation
  ```

### 7. Update QUICK_REFERENCE.md
- [ ] Open `docs/guides/QUICK_REFERENCE.md`
- [ ] Locate IRT Calibration section
- [ ] Add standalone calibration table command:
  ```markdown
  ### Create NE25 Calibration Table (Standalone)
  ```bash
  # Run standalone (outside pipeline)
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/create_ne25_calibration_table.R
  ```
  **Note:** Automatically created by NE25 pipeline (Step 11) - manual execution rarely needed
  ```

### 8. Update Combined Calibration Dataset Documentation
- [ ] In CLAUDE.md, locate IRT Calibration Pipeline section
- [ ] Update description to mention wgt column:
  ```markdown
  - **Output:** `mplus/calibdat.dat` (id, study, years, wgt, 416 items)
  - **Weighted Estimation:** wgt column (1.0 for all studies, authenticity_weight for NE25)
  ```

### 9. Create Git Commit
- [ ] Stage all modified files:
  ```bash
  git add scripts/irt_scoring/create_ne25_calibration_table.R
  git add pipelines/orchestration/ne25_pipeline.R
  git add scripts/temp/restructure_calibration_dataset.py
  git add docs/irt_scoring/quality_flags.csv
  git add docs/irt_scoring/calibration_quality_report.html
  git add CLAUDE.md
  git add docs/architecture/PIPELINE_STEPS.md
  git add docs/guides/QUICK_REFERENCE.md
  ```
- [ ] Create commit with message:
  ```bash
  git commit -m "$(cat <<'EOF'
  Implement NE25 calibration optimization (Issue #5)

  Changes:
  - Create optimized ne25_calibration table (27 columns, 2,831 records)
  - Integrate as Step 11 in NE25 pipeline (automated creation)
  - Add authenticity_weight column for weighted IRT estimation
  - Add wgt column to combined calibration dataset (303 columns)
  - Re-run quality validation on restructured dataset
  - Update documentation (CLAUDE.md, PIPELINE_STEPS.md, QUICK_REFERENCE.md)

  Benefits:
  - 97% storage reduction (15 MB → 0.5 MB)
  - Automated table refresh on every pipeline run
  - Weighted IRT calibration support (authenticity_weight)
  - Consistent meets_inclusion filter (2,831 participants)

  Closes #5

  🤖 Generated with [Claude Code](https://claude.com/claude-code)

  Co-Authored-By: Claude <noreply@anthropic.com>
  EOF
  )"
  ```

### 10. Close GitHub Issue
- [ ] Verify commit includes "Closes #5"
- [ ] Push commit to remote:
  ```bash
  git push
  ```
- [ ] Verify issue #5 automatically closed on GitHub
- [ ] Or manually close with comment if not auto-closed

### 11. Final Verification
- [ ] Run complete NE25 pipeline one more time
- [ ] Verify all steps complete successfully
- [ ] Check `ne25_calibration` table created (2,831 records, 27 columns)
- [ ] Verify combined dataset has wgt column
- [ ] Confirm quality report shows instrument filtering

### 12. Clear Todo List
- [ ] **FINAL TASK:** Clear Claude todo list (all phases complete)
- [ ] Archive Phase 1-4 task files to `todo/archive/`
- [ ] Document completion in Phase 4 completion summary

---

## Validation Criteria

**Success:**
- ✅ Quality validation runs successfully
- ✅ Quality flags updated with instrument filtering
- ✅ Quality report rendered with visual indicators
- ✅ All documentation updated (CLAUDE.md, PIPELINE_STEPS.md, QUICK_REFERENCE.md)
- ✅ Git commit created with comprehensive message
- ✅ Issue #5 closed on GitHub
- ✅ Full pipeline run succeeds

**Failure conditions:**
- ❌ Quality validation fails or errors
- ❌ Documentation missing updates
- ❌ Commit message incomplete
- ❌ Pipeline run fails

---

## Expected Quality Validation Output

```
================================================================================
CALIBRATION DATA QUALITY VALIDATION
================================================================================

[SETUP] Loading required packages
        Packages loaded successfully

================================================================================
LOADING DATA
================================================================================

[1/3] Loading codebook from: codebook/data/codebook.json
      Items: 309
      Response sets: 111

[2/3] Connecting to DuckDB: data/duckdb/kidsights_local.duckdb
      Loading calibration_dataset_2020_2025_restructured table
      Records: 85,544
      Columns: 303  ← Confirms using restructured dataset with wgt

[3/3] Data loading complete
      Items to validate: 299
      Studies: NE20, NE22, NE25, NSCH21, NSCH22, USA24

================================================================================
EXTRACTING EXPECTED RESPONSE CATEGORIES
================================================================================

[OK] Extracted expected categories for 172 items

================================================================================
EXTRACTING INSTRUMENT MAPPING
================================================================================

[OK] Extracted instruments for 309 items
      Kidsights Measurement Tool items: 263
      GSED-PF items: 46

================================================================================
FLAG 1: CATEGORY MISMATCH DETECTION
================================================================================

[FLAG 1] Detected X category mismatches

================================================================================
FLAG 2: NEGATIVE AGE-RESPONSE CORRELATION
         (Kidsights Measurement Tool items only)
================================================================================

[FLAG 2] Detected X negative correlations

================================================================================
FLAG 3: NON-SEQUENTIAL RESPONSE VALUES
================================================================================

[FLAG 3] Detected X non-sequential value patterns

================================================================================
EXPORTING RESULTS
================================================================================

[OK] Quality flags exported to: docs/irt_scoring/quality_flags.csv
     Total flags: X

================================================================================
VALIDATION COMPLETE
================================================================================
```

---

## Documentation Summary

### Files Updated
1. **CLAUDE.md** - Added NE25 Calibration Table status section
2. **PIPELINE_STEPS.md** - Added Step 11 documentation
3. **QUICK_REFERENCE.md** - Added standalone calibration command
4. **quality_flags.csv** - Updated with latest validation results
5. **calibration_quality_report.html** - Re-rendered with instrument indicators

### Key Documentation Points
- NE25 calibration table now auto-created in pipeline (Step 11)
- 27 columns: id, years, authenticity_weight + 24 calibration items
- 97% storage reduction (15 MB → 0.5 MB)
- meets_inclusion filter: 2,831 participants
- Weighted IRT estimation supported via authenticity_weight
- Combined dataset has wgt column (303 columns total)

---

## Completion Checklist

- [ ] Quality validation re-run successfully
- [ ] Quality report re-rendered
- [ ] CLAUDE.md updated
- [ ] PIPELINE_STEPS.md updated
- [ ] QUICK_REFERENCE.md updated
- [ ] Git commit created with all changes
- [ ] Commit pushed to remote
- [ ] Issue #5 closed
- [ ] Full pipeline run verified
- [ ] Phase 1-4 task files archived
- [ ] Todo list cleared

---

## Notes

- This phase completes the full implementation of GitHub Issue #5
- All 4 phases must be completed in order for successful implementation
- Total implementation time: ~2.5-3 hours across all phases
- Storage savings: 97% reduction (15 MB → 0.5 MB)
- Pipeline overhead: +5-10 seconds (acceptable)
- Weighted calibration: Preserves 196 inauthentic responses with quality downweighting

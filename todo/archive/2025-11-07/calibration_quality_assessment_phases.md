# Calibration Quality Assessment - Implementation Phases

**Project:** IRT Calibration Data Quality Assessment System
**Created:** November 2025
**Status:** Phase 1 In Progress

---

## Phase 1: Validation Function Development

**Goal:** Create automated flag detection function

**Tasks:**
- [ ] Create `validate_calibration_quality.R` function skeleton with parameters
- [ ] Implement Flag 1: Category mismatch detection (fewer AND different categories)
- [ ] Implement Flag 2: Negative age-response correlation detection
- [ ] Implement Flag 3: Non-sequential response values detection (diff check)
- [ ] Add codebook `response_sets` extraction logic
- [ ] Test validation function on `calibration_dataset_2020_2025` table
- [ ] Generate `quality_flags.csv` output and verify format
- [ ] **Load Phase 2 tasks: Quarto Report Structure**

**Deliverable:** `scripts/irt_scoring/validate_calibration_quality.R` + `docs/irt_scoring/quality_flags.csv`

**Estimated Time:** 60 minutes

---

## Phase 2: Quarto Report Structure

**Goal:** Set up interactive report framework with executive summary

**Tasks:**
- [ ] Create `calibration_quality_report.qmd` with YAML header and setup chunk
- [ ] Load calibration data and quality flags from Phase 1 outputs
- [ ] Build Section 1: Executive Summary (records by study, flag count bar chart)
- [ ] Build Section 2: Detailed Flag Report (interactive DT datatable)
- [ ] Add filtering controls (study, flag_type, severity)
- [ ] Test report rendering and export to HTML
- [ ] Add CSS styling for professional appearance
- [ ] **Load Phase 3 tasks: Interactive Item Explorer**

**Deliverable:** `docs/irt_scoring/calibration_quality_report.qmd` (Sections 1-2 complete)

**Estimated Time:** 60 minutes

---

## Phase 3: Interactive Item Explorer

**Goal:** Create interactive age-response visualization system

**Tasks:**
- [ ] Add Section 3 header: Interactive Item Explorer
- [ ] Create dropdown widget 1: Item selection (lex_equate names)
- [ ] Create dropdown widget 2: Study filter (All Studies + 6 individual options)
- [ ] Implement reactive data filtering based on selections
- [ ] Build Plot 1: Age-Response scatter with study-specific smoothing (GAM/logistic)
- [ ] Build Plot 2: Response distribution histogram (faceted by study)
- [ ] Build Plot 3: Missing data by age bin (grouped bar chart)
- [ ] Add plotly interactivity with hover tooltips
- [ ] Test interactive functionality with multiple items/studies
- [ ] **Load Phase 4 tasks: Integration and Documentation**

**Deliverable:** `docs/irt_scoring/calibration_quality_report.qmd` (Section 3 complete, full report functional)

**Estimated Time:** 90 minutes

---

## Phase 4: Integration and Documentation

**Goal:** Integrate into pipeline and complete documentation

**Tasks:**
- [ ] Update `run_calibration_pipeline.R` to call validation function (optional step)
- [ ] Add command-line option: `--skip-quality-check` flag
- [ ] Test full pipeline execution with quality assessment enabled
- [ ] Spot-check flagged items to verify accuracy
- [ ] Update `CALIBRATION_PIPELINE_USAGE.md` with quality assessment section
- [ ] Add flag interpretation guide to report header
- [ ] Create example screenshots for documentation
- [ ] Commit all new files with comprehensive commit message
- [ ] Push to repository

**Deliverable:** Fully integrated quality assessment system with documentation

**Estimated Time:** 40 minutes

---

## Phase Summary

| Phase | Focus | Files Created/Modified | Time |
|-------|-------|----------------------|------|
| 1 | Validation Logic | `validate_calibration_quality.R` (new) | 60 min |
| 2 | Report Framework | `calibration_quality_report.qmd` (new) | 60 min |
| 3 | Interactive Plots | `calibration_quality_report.qmd` (modify) | 90 min |
| 4 | Integration | `run_calibration_pipeline.R`, docs (modify) | 40 min |
| **Total** | | **3 new files, 2 modified** | **3-4 hours** |

---

## Success Criteria

**Phase 1 Complete When:**
- ✅ Validation function executes without errors
- ✅ All 3 flag types detected correctly
- ✅ CSV output contains expected columns
- ✅ At least 10 flags detected across all studies

**Phase 2 Complete When:**
- ✅ Quarto report renders to HTML successfully
- ✅ Executive summary shows accurate counts
- ✅ DT datatable is searchable and sortable
- ✅ Flag severity color-coding works

**Phase 3 Complete When:**
- ✅ Item dropdown populated with all lex_equate items
- ✅ Study filter updates plots correctly
- ✅ Age-response plots show 6 study-specific curves
- ✅ Plotly hover tooltips display item values
- ✅ GAM/logistic model selection works based on item type

**Phase 4 Complete When:**
- ✅ Pipeline runs with `--skip-quality-check` flag
- ✅ Quality assessment integrates seamlessly
- ✅ Documentation updated with usage examples
- ✅ All files committed and pushed to GitHub

---

## Technical Notes

### Data Source
- **Table:** `calibration_dataset_2020_2025` (harmonized lex_equate names)
- **Records:** 85,544 total (varies by NSCH sampling)
- **Items:** 416 harmonized items
- **Studies:** 6 (NE20, NE22, NE25, NSCH21, NSCH22, USA24)

### Flag Definitions

**Flag 1: Category Mismatch**
- **Fewer:** `observed_set ⊂ expected_set` (e.g., {0,1} when {0,1,2} expected)
- **Different:** `observed_set ⊄ expected_set` (e.g., {0,1,9} when {0,1,2} expected)

**Flag 2: Negative Correlation**
- **Threshold:** `cor(age, response) < 0`
- **Interpretation:** Older children scoring lower (developmentally unexpected)

**Flag 3: Non-Sequential Values**
- **Check:** `unique(diff(sort(unique(values)))) != 1`
- **Example:** {0,1,9} has diff = {1,8}, not all 1's → FLAG

### Model Selection Logic
```r
item_type <- if (all(values %in% c(0,1))) "binary" else "ordinal"

if (item_type == "binary") {
  model <- glm(response ~ years, family = binomial())
} else {
  model <- mgcv::gam(response ~ s(years, k=4))
}
```

---

## Current Status

**Active Phase:** Phase 1 - Validation Function Development
**Next Milestone:** Generate first quality_flags.csv
**Blockers:** None

---

**Last Updated:** 2025-11-05
**Maintained By:** Calibration Pipeline Team

# NE25 Pipeline Refactoring Log

**Date Started**: December 6, 2025
**Purpose**: Clean up deprecated metrics and improve pipeline clarity after manual authenticity screening refactor

---

## Proposed Changes

### 1. Remove `included` metric ✅ AGREED
**Current behavior**:
- Computed as `include = eligible & authentic` (line 374 in ne25_eligibility.R)
- Reported in pipeline summary as `records_included`

**Rationale for removal**:
- `included` was designed for automated filtering: `eligible = TRUE AND authentic = TRUE`
- With manual authenticity screening, the concept of "included" is ambiguous:
  - Does it mean `eligible & !is_flagged`?
  - Does it mean `eligible & (authenticity == "Pass")`?
  - Should flagged observations with `is_flagged = TRUE` still count as "included"?
- Replacing with clearer metrics: `eligible` + `is_flagged` separately

**Action items**:
- [ ] Remove `include` column from `apply_ne25_eligibility()` (line 374)
- [ ] Remove `records_included` from pipeline metrics
- [ ] Remove `records_included` from pipeline summary output
- [ ] Update pipeline documentation to remove references to "included"
- [ ] Update README files in `scripts/authenticity_screening/` and `output/ne25/authenticity_screening/` to use "included" terminology correctly

---

### 2. Rename "Authenticity" category to "Data Quality" ✅ AGREED

**Current behavior**:
- `authentic` category checks CID6 (ZIP/county match) and CID7 (birthday confirmation)
- Stored as `authenticity = "Pass"` or `"Fail"` in eligibility summary
- Separate from manual authenticity flags (`is_flagged`)

**What `authenticity` currently checks**:
- **CID6**: ZIP code matches reported county (category: "Authenticity", action: "Exclusion")
- **CID7**: Child's birthday was confirmed (category: "Authenticity", action: "Exclusion")

**Decision**: Rename category from "Authenticity" to "Data Quality"
- CID6/CID7 are data quality checks, not response pattern analysis
- Distinguishes from manual influence-based screening
- Clear three-tier structure:
  - `eligible` = passed eligibility criteria (CID2-5)
  - `data_quality` = passed data quality checks (CID6-7)
  - `influential` = manually identified influential observations

**Action items**:
- [ ] Update `get_eligibility_criteria_definitions()` to change category from "Authenticity" to "Data Quality"
- [ ] Rename `authenticity` column to `data_quality` in eligibility summary
- [ ] Rename `authentic` variable to `data_quality` in `apply_ne25_eligibility()`
- [ ] Update pipeline metrics: `records_authentic` → `records_data_quality`
- [ ] Update pipeline summary output to show "Data quality validated" instead of "Authentic participants"

---

## Implementation Notes

- All changes should be tested with full pipeline run
- Update CLAUDE.md after changes are finalized
- Update pipeline documentation (PIPELINE_OVERVIEW.md, PIPELINE_STEPS.md)

---

### 3. Rename `is_flagged` to `influential` ✅ AGREED

**Current behavior**:
- Manual authenticity screening creates `is_flagged = TRUE/FALSE` column
- Companion column: `overall_influence_cutoff` (numeric influence score)
- Database table: `ne25_flagged_observations`

**Decision**: Rename `is_flagged` to `influential` for clarity
- More descriptive of what the flag represents (high Cook's D influence)
- Aligns with statistical methodology
- Clearer for documentation and publications

**Action items**:
- [ ] Rename `is_flagged` to `influential` in Step 6.5 of pipeline
- [ ] Update database table name: `ne25_flagged_observations` → `ne25_influential_observations`
- [ ] Update output directory: `output/ne25/authenticity_screening/` → `output/ne25/influential_observations/` OR keep as-is?
- [ ] Update CSV filenames: `incorrectly_coded_items_*.csv` stays, `ne25_flagged_observations_*.rds` → `ne25_influential_observations_*.rds`
- [ ] Update all README files to use "influential" terminology
- [ ] Update CLAUDE.md status section
- [ ] Update pipeline metrics: `records_flagged` → `records_influential`

**Directory renaming decision**:
- **Phase 1** (now): Keep directory names unchanged during initial implementation
- **Phase 2** (after testing): Rename directories once pipeline is verified working
  - `scripts/authenticity_screening/` → `scripts/influence_diagnostics/`
  - `output/ne25/authenticity_screening/` → `output/ne25/influential_observations/`

---

## Implementation Plan

### Phase 1: Column/Variable Renaming (Current)
1. Remove `included` metric from code
2. Rename "Authenticity" → "Data Quality" in eligibility criteria
3. Rename `is_flagged` → `influential` (column names, variable names, database table)
4. Test full pipeline to verify all changes work correctly
5. **DO NOT rename directories yet**

### Phase 2: Directory Renaming (After Phase 1 verification)
1. Rename `scripts/authenticity_screening/` → `scripts/influence_diagnostics/`
2. Rename `output/ne25/authenticity_screening/` → `output/ne25/influential_observations/`
3. Update all file paths in code
4. Retest full pipeline
5. Update all documentation (CLAUDE.md, READMEs, etc.)

---

## Change History

| Date | Change | Status |
|------|--------|--------|
| 2025-12-06 | Remove `included` metric | Agreed, pending implementation |
| 2025-12-06 | Rename "Authenticity" to "Data Quality" | Agreed, pending implementation |
| 2025-12-06 | Rename `is_flagged` to `influential` | Agreed, pending implementation |


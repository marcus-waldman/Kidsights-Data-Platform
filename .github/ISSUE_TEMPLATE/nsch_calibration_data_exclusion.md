---
name: NSCH Data Exclusion from Calibration Dataset
about: Document decision to exclude NSCH data from IRT calibration due to systematic negative age correlations
title: "[CALIBRATION] Exclude NSCH 2021/2022 from calibration dataset due to data quality concerns"
labels: calibration, data-quality, nsch
assignees: ''
---

## Problem Summary

NSCH 2021 and 2022 data show systematic negative age correlations for developmental milestone items, even after confirming correct reverse coding implementation. **26 of 30 NSCH 2021 items** show negative age correlations, many with strong magnitudes (|r| > 0.5).

## Background

During IRT calibration dataset preparation (November 2025), quality validation flagged extreme negative age correlations in NSCH items. Investigation revealed:

### Initial Hypothesis (REJECTED)
- **Suspected**: Sentinel codes (94-98, 99) contaminating data
- **Finding**: Sentinel codes are correctly recoded to NA (lines 236-246 in helper functions) ✓

### Secondary Hypothesis (REJECTED)
- **Suspected**: Coding direction mismatches between codebook and helper functions
- **Finding**:
  - Refactored both `recode_nsch_2021.R` and `recode_nsch_2022.R` to use codebook as single source of truth
  - Verified transformation logic is correct (reverse=TRUE → max-x, reverse=FALSE → x-min)
  - 9 items resolved (EG24a, EG41_1, etc. now show positive correlations)
  - But **50 NEW items** now show negative correlations after correct coding

### Current Assessment
Items with strongest negative correlations are **correctly coded ability items**:
- EG13b (TELLSTORY): r = -0.659, reverse=FALSE ✓
- EG28a (WRITENAME): r = -0.649, reverse=FALSE ✓
- EG4b_1 (ASKQUESTION2): r = -0.574, reverse=FALSE ✓

These are positive trait items ("Can tell a story", "Write first name") where higher values should indicate better development. The negative age correlations suggest fundamental measurement issues.

## Potential Causes

1. **"How often" response scale artifacts**: Parents may interpret frequency differently across age groups
2. **Floor/ceiling effects**: Items may saturate at younger ages, then decline in reported frequency
3. **Parental expectation shifts**: Novel behaviors reported as "always" for younger children, "sometimes" for older
4. **Age-restricted administration**: Some items may only be asked for certain age ranges (37% missing on many items)

## Impact on Calibration

Including NSCH data with systematic negative age correlations would:
- Distort IRT parameter estimates (discrimination and thresholds)
- Introduce bias into national benchmarking comparisons
- Compromise construct validity of developmental scales

## Decision

**EXCLUDE NSCH 2021 and NSCH 2022 data from calibration dataset** until data quality issues are resolved.

## Implementation

### Modified Pipeline
**File**: `scripts/irt_scoring/prepare_calibration_dataset.R`

Skip Steps 4-5 (NSCH data loading):
```r
# [STEPS 4-5 SKIPPED: NSCH data excluded due to quality concerns]
# See GitHub issue: nsch_calibration_data_exclusion.md
```

### Remaining Calibration Studies
- ✅ NE20: 37,546 records (historical)
- ✅ NE22: 2,431 records (historical)
- ✅ NE25: 2,635 records (current)
- ✅ USA24: 1,600 records (national sample)
- ❌ NSCH21: 1,000 records → **EXCLUDED**
- ❌ NSCH22: 1,000 records → **EXCLUDED**

**Total calibration records**: 44,212 (down from 46,212)

### Documentation Updates
- [x] Update `CLAUDE.md` IRT Calibration status section
- [x] Document exclusion rationale in calibration script comments
- [x] Add warning to quality validation output

## Future Work

### Option 1: Item-Level Exclusion
Instead of excluding all NSCH data, exclude only problematic items:
- Keep items with positive/near-zero age correlations (e.g., DD299, EG26a)
- Exclude 26 items with negative correlations from calibration
- Still provides national benchmark for 4-11 validated items

### Option 2: NSCH Data Investigation
- Contact CAHMI/Census Bureau about known measurement issues
- Examine NSCH technical documentation for age-restricted items
- Compare correlations across NSCH years (2016-2023) to identify consistent patterns
- Test alternative coding schemes (categorical vs continuous)

### Option 3: Separate NSCH Calibration
- Calibrate NSCH data separately with NSCH-specific constraints
- Use for national prevalence estimates only (not Kidsights scoring)
- Document as supplementary analysis with caveats

## References

**Modified Files:**
- `scripts/irt_scoring/helpers/recode_nsch_2021.R` (lines 186-257)
- `scripts/irt_scoring/helpers/recode_nsch_2022.R` (lines 186-257)
- `scripts/irt_scoring/prepare_calibration_dataset.R` (Steps 4-5)

**Quality Flags:**
- `docs/irt_scoring/quality_flags.csv` (127 quality issues, 56 NSCH items)
- `docs/irt_scoring/quality_flags_before_fix.csv` (archived)

**Investigation Scripts:**
- `scripts/temp/audit_nsch_coding.R`
- `scripts/temp/compare_nsch_correlations.R`
- `scripts/temp/verify_reverse_coding_logic.R`

## Resolution Criteria

NSCH data can be re-included when:
1. Negative age correlations explained and documented as expected patterns, OR
2. Alternative coding/scaling approach tested and validated, OR
3. External validation confirms NSCH data quality for age 0-6 samples

---

**Date Created**: November 12, 2025
**Status**: Open
**Priority**: High
**Milestone**: IRT Recalibration 2025

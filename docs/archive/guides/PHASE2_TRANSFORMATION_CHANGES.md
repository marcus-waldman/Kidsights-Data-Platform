# Phase 2: PS Item Transformation Changes

**Date:** 2025-11-08
**Status:** Complete
**Related Issue:** GitHub Issue #4

## Summary

Successfully implemented automatic sentinel value recoding for 46 PS (psychosocial) items through codebook-driven validation rather than explicit transformation code.

## Changes Made

### 1. Codebook Updates

**File:** `codebook/data/codebook.json`

- **Removed sentinel value 9** from all 46 PS item response_sets
- **Before:** PS response_sets had 4 values: `[0, 1, 2, 9]`
- **After:** PS response_sets have 3 values: `[0, 1, 2]`

**Items affected:** PS001 through PS049 (46 items total)

### 2. Validation Function Enhancement

**File:** `R/transform/validate_item_responses.R`

**Bug Fix:** Added `$ref:` prefix handling for response_set references

**Lines 113-134:** Added logic to strip `$ref:` prefix when resolving response_set references:

```r
# Handle $ref: prefix for response_set references
if (length(response_ref_char) == 1 && is.character(response_ref_char)) {
  # Strip $ref: prefix if present
  if (grepl("^\\$ref:", response_ref_char)) {
    response_ref_char <- sub("^\\$ref:", "", response_ref_char)
  }

  # Now check if it exists in response_sets
  if (response_ref_char %in% names(cb$response_sets)) {
    response_set <- cb$response_sets[[response_ref_char]]
    # ... extract valid values ...
  }
}
```

**Impact:** Function now correctly processes all 276 items with response_sets (was previously only processing 172 items with inline response arrays)

### 3. EG16a Items Investigation

**Finding:** EG16a_1 (NOM023X) and EG16a_2 (NOM024X) are already 0-indexed in the database
- Actual values: 0, 1, 2, 3, 4
- Response_sets correctly define: 0-4 range
- **No transformation needed**

## Transformation Mechanism

### How It Works

1. **Pipeline Execution:** When `recode_it()` runs, it calls `validate_item_responses()`
2. **Codebook Lookup:** Function loads codebook and extracts valid response values from response_sets
3. **Validation:** For each item, any value NOT in the valid response_set is marked invalid
4. **Automatic Conversion:** Invalid values (including sentinel 9 for PS items) are set to NA

### Data Flow

```
Raw Data (PS001 = 9)
    ↓
validate_item_responses()
    ↓
Check: Is 9 in valid_responses[PS001]?
    ↓
No → Set to NA
    ↓
Transformed Data (PS001 = NA)
```

## Testing

**Test Script:** `scripts/temp/test_ps_transformation.R`

**Test Results:**
- ✅ PS001: 2 sentinel 9 values → NA (100% conversion)
- ✅ PS002: 1 sentinel 9 value → NA (100% conversion)
- ✅ Valid values (0, 1, 2) preserved
- ✅ Total: 3/3 sentinel values converted

**Database Impact Estimate:**
- PS001 currently has 40 records with value 9 (will convert to NA)
- Other PS items likely have similar sentinel values
- Expected: ~100-200 total conversions across all 46 PS items

## Benefits of This Approach

### 1. Maintainability
- **Single Source of Truth:** Codebook defines valid responses
- **No Custom Code:** No item-specific transformation logic needed
- **Scalable:** Adding new items only requires codebook updates

### 2. Consistency
- **Uniform Validation:** All items validated the same way
- **Audit Trail:** Codebook documents which values are valid/invalid
- **Transparency:** Clear what values are being recoded

### 3. Flexibility
- **Easy Updates:** Change valid responses by editing codebook
- **Study-Specific:** Different lexicons can have different response_sets
- **Version Control:** Codebook changes tracked in git

## Impact on Authenticity Screening

### Before Phase 2
- 172 items available for Stan model (had response_options)
- 104 items blocked (PS and NOM items without response_options)

### After Phase 1 + Phase 2
- 276 items available for pipeline (100% coverage)
- 230 items for Stan model (276 - 46 PS items, per user decision)
- 40 records with PS001=9 will be recoded to NA (appropriate missing data handling)

## Next Steps (Phase 3)

1. **Re-run NE25 Pipeline:** Transform all data with updated codebook
2. **Validate Transformation:** Verify PS items no longer have value 9
3. **Update Data Prep:** Modify `01_prepare_data.R` to exclude PS items from Stan model
4. **Re-fit Model:** Run Stan model on 230 items (172 + 58 NOM)
5. **Compare Results:** Assess impact of adding 58 NOM items

## Files Modified

### Code Changes
- `R/transform/validate_item_responses.R` - Added $ref: prefix handling

### Codebook Changes
- `codebook/data/codebook.json` - Removed sentinel 9 from 46 PS response_sets

### Test Scripts (Temporary)
- `scripts/temp/test_ps_transformation.R` - Validation test
- `scripts/temp/remove_sentinel_9_from_ps_items.py` - Response_set cleanup
- `scripts/temp/check_eg16a_actual_values.py` - EG16a investigation

### Documentation
- `docs/guides/PHASE2_TRANSFORMATION_CHANGES.md` - This document
- `todo/codebook_response_sets_fix.md` - Task tracking

## Technical Notes

### REDCap vs Database Column Names
- **REDCap:** Uses lowercase field names (`ps001`, `nom009`)
- **Codebook:** Uses uppercase lexicon names (`PS001`, `NOM009`)
- **Database:** Uses lowercase column names (`ps001`, `nom009`)
- **Validation:** Handles case-insensitive matching

### Response_Set Reference Format
- **Format:** `"$ref:ne25_ps001"` (with prefix)
- **Resolution:** Strips prefix → looks up `"ne25_ps001"` in response_sets
- **Alternative:** Inline arrays (now deprecated, converted to references)

## Validation Checklist

- [x] Sentinel value 9 removed from all 46 PS response_sets
- [x] validate_item_responses handles $ref: prefix correctly
- [x] Test script verifies 9 → NA conversion
- [x] EG16a items confirmed as already 0-indexed
- [x] No transformation code needed (codebook-driven)
- [x] Documentation complete
- [ ] Pipeline re-run (Phase 3)
- [ ] Database validation (Phase 3)

---

**Generated:** 2025-11-08
**By:** Claude Code
**Session:** Phase 2 - Transformation Pipeline Updates

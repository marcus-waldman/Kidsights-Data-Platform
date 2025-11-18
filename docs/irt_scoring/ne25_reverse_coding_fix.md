# NE25 Reverse Coding Fix

**Date:** November 17, 2025
**Issue:** Four items in NE25 have inverted response coding compared to NE20/NE22

---

## Summary

Systematic analysis of 309 calibration items revealed **4 items with reverse coding in NE25**. These items show negative age correlations in NE25 (older children scoring lower) while showing positive correlations in NE20/NE22 (as expected developmentally).

---

## Affected Items

### 1. **EG30d** - "Can this child draw a: triangle?"
- **NE25 lexicon:** NOM028
- **Age correlation:**
  - NE25: r = -0.167 (n=333) ❌
  - NE22: r = +0.395 ✓
  - NE20: r = +0.569 ✓
  - **Pooled: r = +0.475** ✓
- **Developmental pattern in NE25:** Age 1 (0.33) → Age 2 (0.26) → Age 3 (0.14) → Age 4 (0.00) **DECREASES**
- **Expected pattern (NE22):** Age 3 (0.38) → Age 4 (0.60) → Age 5 (0.80) → Age 6 (0.87) **INCREASES**

### 2. **EG30e** - "Can this child draw a: square?"
- **NE25 lexicon:** NOM029
- **Age correlation:**
  - NE25: r = -0.113 (n=166) ❌
  - NE22: r = +0.441 ✓
  - NE20: r = +0.569 ✓
  - **Pooled: r = +0.503** ✓

### 3. **EG16a_2** - "How often does this child play well with others?"
- **NE25 lexicon:** NOM049
- **Age correlation:**
  - NE25: r = -0.083 (n=51) ❌
  - NE22: r = +0.138 ✓
  - NE20: r = +0.081 ✓
  - **Pooled: r = +0.088** ✓

### 4. **AA56** - "Can the child sit or play on his/her own for at least 20 minutes?"
- **NE25 lexicon:** CREDI020
- **Age correlation:**
  - NE25: r = -0.069 (n=214) ❌
  - NE22: r = +0.060 ✓
  - **Pooled: r = +0.120** ✓

---

## Root Cause

In NE25, these items are coded with inverted values:
- **0 = Yes (developmentally advanced response)** ← Should be 1
- **1 = No (developmentally delayed response)** ← Should be 0

The standard binary response set defines:
- **1 = "Yes"**
- **0 = "No"**

This causes older children to appear less developmentally advanced than younger children in NE25 data.

---

## Fix Applied

Added `reverse_coded: { ne25: true }` flags to all 4 items in `codebook/data/codebook.json`.

**Backup created:** `codebook/data/codebook_backup_20251117_150614.json`

**Example:**
```json
{
  "EG30d": {
    "id": 196,
    "reverse_coded": {
      "ne25": true
    },
    ...
  }
}
```

---

## Next Steps

1. **Rerun NE25 pipeline** with updated codebook to apply reverse coding transformations
2. **Regenerate calibration dataset** (`prepare_calibration_dataset.R`) to incorporate corrected NE25 data
3. **Verify fix** by checking age correlations are now positive for all 4 items in NE25

---

## Detection Method

Systematic cross-study validation:
1. Computed age correlations for all 309 items across NE25, NE22, NE20
2. Flagged items where:
   - NE25 correlation is negative (< -0.05)
   - NE22 or NE20 correlation is positive (> 0.05)
   - Pooled correlation is positive (majority of data is correct)
   - NE25 sample size ≥ 50

**Script:** `scripts/temp/detect_reverse_coding.R`
**Results:** `scripts/temp/reverse_coded_items.csv`

---

## References

- **Age Gradient Explorer:** Visual confirmation of inverted developmental trajectories
- **Codebook:** `codebook/data/codebook.json`
- **Detection Script:** `scripts/temp/detect_reverse_coding.R`
- **Fix Script:** `scripts/temp/add_reverse_coding.py`

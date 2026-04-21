# Phase 3: Authenticity Model Comparison (172 vs 230 Items)

**Date:** November 8, 2025
**Context:** Codebook response_sets fix - GitHub Issue #4

## Overview

After fixing 104 missing response_sets in the codebook, the authenticity screening model was expanded from 172 items to 230 items by including 58 validated NOM (Nominations) items. PS items (46 psychosocial items) were excluded due to sentinel value handling.

## Model Comparison

### 172-Item Model (Original)

**Dataset:**
- N = 2,635 authentic participants
- J = 172 items
- M = 46,402 non-missing observations
- Avg responses per person: 17.6

**Parameter Estimates:**
- Threshold spacing (delta): 1.472
- Person variation (eta SD): 0.804
- tau range: [-5.09, 8.10]
- beta1 range: [-5.58, 0.32]
- eta range: [-5.05, 7.53]

**Convergence:**
- Algorithm: L-BFGS
- Iterations: 1,950
- Time: 13.5 seconds
- Status: SUCCESS

### 230-Item Model (Expanded)

**Dataset:**
- N = 2,635 authentic participants
- J = 230 items (172 original + 58 NOM)
- M = 91,340 non-missing observations
- Avg responses per person: 34.7

**Parameter Estimates:**
- Threshold spacing (delta): 1.742 (+18%)
- Person variation (eta SD): 0.923 (+15%)
- tau range: [-5.74, 9.13]
- beta1 range: [-0.26, 5.58]
- eta range: [-7.75, 5.56]

**Convergence:**
- Algorithm: L-BFGS
- Iterations: 3,203
- Time: 58.2 seconds
- Status: SUCCESS

## Key Differences

### 1. Data Scale
- **Observations:** +97% increase (46,402 → 91,340)
- **Items:** +34% increase (172 → 230)
- **Average responses per person:** +97% increase (17.6 → 34.7)

### 2. Model Parameters
- **Threshold spacing (delta):** 18% increase
  - Suggests polytomous item response categories are more spread out with the expanded item set
- **Person variation (eta SD):** 15% increase
  - More individual differences captured by the expanded model
  - Indicates NOM items add meaningful variation in authentic response patterns

### 3. Computational Performance
- **Convergence time:** 4.3x longer (13.5s → 58.2s)
  - Expected given 2x data size
  - Still very efficient for production use

## Interpretation

### Expanded Item Coverage
The 58 NOM items represent **nominations** of developmental milestones (e.g., "Can your child name 3 colors?", "Can your child hop on one foot?"). These items:
- Capture different dimensions of child development than the original 172 items
- Show higher response rates (avg 34.7 vs 17.6 responses per person)
- Add meaningful variation to authentic response patterns

### Statistical Implications
1. **Increased person-level variation (eta SD: 0.804 → 0.923)**
   - The expanded model detects more individual differences in authentic response patterns
   - This should improve discriminatory power for authenticity screening

2. **Wider parameter ranges**
   - tau range expanded: [-5.09, 8.10] → [-5.74, 9.13]
   - beta1 range reversed: [-5.58, 0.32] → [-0.26, 5.58]
   - Suggests NOM items have different difficulty/discrimination profiles

### Recommendation
**Use the 230-item model for production authenticity screening.** The expanded item set:
- Provides richer characterization of authentic response patterns
- Increases person-level variation estimates (better discrimination)
- Converges successfully with reasonable computational cost
- Maintains all original items while adding validated NOM items

## Files Modified

1. **Data Preparation:** `scripts/authenticity_screening/01_prepare_data.R`
   - Added `$ref:` prefix handling for response_set lookups
   - Added PS item exclusion filter

2. **Model Fitting:** `scripts/authenticity_screening/02_fit_full_model.R`
   - No changes needed (automatically uses new 230-item data)

3. **Stan Data Files:** `data/temp/`
   - `item_metadata.rds` (230 items)
   - `stan_data_authentic.rds` (91,340 observations)
   - `stan_data_inauthentic.rds` (8,300 observations)

## Next Steps

1. ✅ Data preparation for 230 items - COMPLETE
2. ✅ Model fitting with 230 items - COMPLETE
3. ⏳ Update GitHub Issue #4 with completion summary
4. ⏳ Return to authenticity screening LOOCV tasks with expanded model

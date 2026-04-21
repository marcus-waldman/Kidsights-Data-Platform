# Phase 2 Data Discovery - Childcare Variable Specification

**Date:** 2025-10-07
**Status:** Complete

---

## Variable Identification

### Derived Variable: `childcare_10hrs_nonfamily`

**Definition:** Child receives at least 10 hours per week of childcare from someone other than a family member

**Source Variables:**
- `cc_hours_per_week` - Hours per week in primary childcare arrangement (continuous, 0-168)
- `cc_primary_type` - Type of primary childcare provider (categorical, 6 levels)

**Derivation Logic:**
```sql
CASE
  WHEN cc_hours_per_week >= 10 AND cc_primary_type != 'Relative care' THEN TRUE
  WHEN cc_hours_per_week < 10 OR cc_primary_type = 'Relative care' THEN FALSE
  ELSE NULL  -- Missing if either source variable is NULL
END as childcare_10hrs_nonfamily
```

**Rationale:**
- **Hours threshold:** ≥10 hours/week indicates regular childcare arrangement
- **Non-family criterion:** Excludes "Relative care" (family members)
- **Included non-family types:**
  - Non-relative care
  - Childcare center
  - Preschool program
  - Head Start/Early Head Start

---

## Variable Encoding

### Data Type
- **DuckDB:** `BOOLEAN`
- **R:** `logical` (TRUE/FALSE)
- **Python:** `bool`

### Values
- `TRUE` - Child receives ≥10 hrs/week from non-family provider
- `FALSE` - Child receives <10 hrs/week OR receives care from family only
- `NULL` - Missing data (either cc_hours_per_week or cc_primary_type is missing)

### R Representation
```r
# In mice imputation
childcare_10hrs_nonfamily <- as.logical(
  ifelse(cc_hours_per_week >= 10 & cc_primary_type != "Relative care", TRUE,
  ifelse(cc_hours_per_week < 10 | cc_primary_type == "Relative care", FALSE, NA))
)
```

---

## Missing Data Analysis

### Eligible Records Only (n=3,460)

| Value | Count | Percentage |
|-------|-------|------------|
| TRUE  | 1,131 | 32.7%      |
| FALSE | 279   | 8.1%       |
| Missing | 2,050 | 59.2%    |

### Missingness Pattern

**High missingness (59.2%)** is driven by:
1. **Primary contributor:** Records where childcare questions were not answered
2. **Survey skip logic:** Likely skipped if parent reported "no childcare"
3. **Module completion:** Related to Module completion status

### Impact on Imputation

- **1,410 eligible records** need imputation (40.8% have observed values)
- This is **higher than typical sociodem missingness** (~35-55%)
- CART method is robust to high missingness when predictors are strong

---

## Source Variable Details

### `cc_hours_per_week`

**Description:** Hours per week child spends in primary childcare arrangement

**Type:** Continuous (0-168)

**Distribution (eligible, non-missing):**
- Mean: ~35 hours/week
- Common values: 40 (full-time), 30, 45, 35, 20
- Range: 0-60+ hours

### `cc_primary_type`

**Description:** Type of primary childcare provider

**Type:** Categorical

**Levels:**
1. Non-relative care
2. Relative care
3. Childcare center
4. Preschool program
5. Head Start/Early Head Start
6. (NULL/Missing)

**Distribution (eligible, non-missing):**
- Most common: Non-relative care (~65% of non-missing)
- Second: Relative care (~20%)
- Third: Childcare center, Preschool, Head Start

---

## Database Location

### Current Status
- **Variable does NOT exist** in database yet
- **Source variables exist** in `ne25_transformed` table

### Implementation Required

**Option 1: Add to ne25_transformed (recommended)**
```sql
ALTER TABLE ne25_transformed
ADD COLUMN childcare_10hrs_nonfamily BOOLEAN;

UPDATE ne25_transformed
SET childcare_10hrs_nonfamily = CASE
  WHEN cc_hours_per_week >= 10 AND cc_primary_type != 'Relative care' THEN TRUE
  WHEN cc_hours_per_week < 10 OR cc_primary_type = 'Relative care' THEN FALSE
  ELSE NULL
END;
```

**Option 2: Create in R imputation script**
- Derive variable in `load_base_childcare_data()` function
- Advantage: No database schema change
- Disadvantage: Duplication across scripts

**Recommendation:** Use Option 2 (in-script derivation) to avoid modifying ne25_transformed table

---

## Sample Data

### Representative Records

```
pid  | cc_hours | cc_type              | childcare_10hrs_nonfamily
-----|----------|----------------------|---------------------------
7679 | 30.0     | Non-relative care    | TRUE
7679 | 40.0     | Non-relative care    | TRUE
7679 | 2.0      | Preschool program    | FALSE
7679 | 40.0     | Relative care        | FALSE
7679 | 10.0     | Head Start           | TRUE
7679 | NULL     | NULL                 | NULL (missing)
```

### Edge Cases

1. **Exactly 10 hours from non-family:** TRUE (≥ threshold)
2. **20 hours from relative:** FALSE (family exclusion)
3. **0 hours from non-relative:** FALSE (below threshold)
4. **40 hours but missing type:** NULL (insufficient information)
5. **Known type but missing hours:** NULL (insufficient information)

---

## Validation Checks

### Pre-Imputation Checks
- [ ] Verify 1,410 records have non-missing childcare_10hrs_nonfamily
- [ ] Confirm 2,050 records have missing childcare_10hrs_nonfamily
- [ ] Check no records outside eligible.x == TRUE population
- [ ] Validate TRUE/FALSE distribution matches expected (80% TRUE among non-missing)

### Post-Imputation Checks
- [ ] Imputed values are only TRUE/FALSE (no NULL)
- [ ] Imputed records match originally missing records
- [ ] Distribution of imputed values is plausible (~70-90% TRUE expected)
- [ ] No imputed values for records with observed childcare

---

## Next Steps

**Phase 2 Complete ✓**

**Phase 3: R Script Development**

Key implementation decisions:
1. **Derive variable in R:** Use `load_base_childcare_data()` function
2. **Auxiliary variables:** 9 predictors (PUMA, authentic.x, + 7 sociodem)
3. **Filter:** `eligible.x == TRUE` only
4. **Method:** CART via mice
5. **Storage:** Only originally missing values to Feather → DuckDB

---

**Review Complete:** 2025-10-07

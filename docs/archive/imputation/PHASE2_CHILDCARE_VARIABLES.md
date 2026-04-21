# Phase 2: Childcare Variables Specification

**Date:** 2025-10-07
**Status:** Complete

---

## Overview: 3-Stage Sequential Imputation

The childcare imputation follows a **conditional sequential pattern**:

1. **Stage 1:** Impute `cc_receives_care` (Yes/No)
2. **Stage 2:** Conditional imputation of `cc_primary_type` and `cc_hours_per_week` (only for cc_receives_care = "Yes")
3. **Stage 3:** Derive `childcare_10hrs_nonfamily` from completed variables

This approach respects the natural hierarchy: children who don't receive childcare (Stage 1 = "No") don't need type/hours imputed.

---

## Variable 1: `cc_receives_care`

### Definition
Does the child receive any childcare arrangement?

### Data Type
- **Database:** `VARCHAR` ("Yes", "No", NULL)
- **R:** `character` or `factor`
- **Imputation method:** CART

### Distribution (Eligible Records, n=3,460)

| Value | Count | Percentage |
|-------|-------|------------|
| Yes   | 1,754 | 50.7%      |
| No    | 1,215 | 35.1%      |
| Missing | 491 | 14.2%      |

### Missingness
- **14.2% missing (491 records)**
- Lowest missingness among the 3 childcare variables
- Foundation for conditional imputation in Stage 2

### Imputation Strategy
- **Auxiliary variables:** PUMA, authentic.x, + 7 sociodem variables
- **Method:** CART (binary outcome)
- **Result:** All 3,460 eligible records will have completed cc_receives_care

### Database Storage
**Table:** `ne25_imputed_cc_receives_care`

```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_cc_receives_care (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  cc_receives_care VARCHAR NOT NULL,  -- "Yes" or "No"
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```

**Expected rows:** 491 records × M imputations (only originally missing)

---

## Variable 2: `cc_primary_type`

### Definition
Type of primary childcare provider (for children who receive childcare)

### Data Type
- **Database:** `VARCHAR` (6 categories + NULL)
- **R:** `character` or `factor`
- **Imputation method:** CART (multi-level categorical)

### Levels
1. Non-relative care
2. Relative care
3. Childcare center
4. Preschool program
5. Head Start/Early Head Start
6. (NULL/Missing)

### Distribution (Among cc_receives_care = "Yes", n=1,754)

| Type | Count | Percentage |
|------|-------|------------|
| Non-relative care | 996 | 56.8% |
| **Missing** | **367** | **20.9%** |
| Relative care | 204 | 11.6% |
| Preschool program | 72 | 4.1% |
| Childcare center | 66 | 3.8% |
| Head Start/Early Head Start | 49 | 2.8% |

### Conditional Missingness
- **20.9% missing (367 records)** among those with cc_receives_care = "Yes"
- **Only imputed for records where cc_receives_care = "Yes"** (observed or imputed)
- Records with cc_receives_care = "No" will have cc_primary_type = NULL (not imputed)

### Imputation Strategy
- **Filter:** Only records with cc_receives_care = "Yes" from Stage 1
- **Auxiliary variables:** PUMA, authentic.x, + 7 sociodem + cc_receives_care
- **Method:** CART (categorical outcome with 5 levels)
- **Result:** ~1,754 + (imputed "Yes" from Stage 1) records will have completed cc_primary_type

### Database Storage
**Table:** `ne25_imputed_cc_primary_type`

```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_cc_primary_type (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  cc_primary_type VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```

**Expected rows:** ~367 records × M imputations (only originally missing, within cc_receives_care = "Yes")

---

## Variable 3: `cc_hours_per_week`

### Definition
Hours per week child spends in primary childcare arrangement

### Data Type
- **Database:** `DOUBLE` (continuous, 0-168)
- **R:** `numeric`
- **Imputation method:** CART (can handle continuous outcomes)

### Distribution (Among cc_receives_care = "Yes", n=1,754)

| Statistic | Value |
|-----------|-------|
| **Missing** | **34 (1.9%)** |
| Mean | 41.3 hours/week |
| Min | 0 |
| Max | 15,000 (outlier, likely data error) |
| Common values | 40, 45, 35, 30, 20 |

### Conditional Missingness
- **1.9% missing (34 records)** among those with cc_receives_care = "Yes"
- Very low missingness (nearly complete when childcare is received)
- **Only imputed for records where cc_receives_care = "Yes"**
- Records with cc_receives_care = "No" will have cc_hours_per_week = NULL

### Data Quality Note
- **Outlier detected:** Max value = 15,000 hours (impossible)
- **Recommendation:** Cap at 168 hours/week (24×7) during imputation
- **Likely cause:** Data entry error (extra zeros)

### Imputation Strategy
- **Filter:** Only records with cc_receives_care = "Yes" from Stage 1
- **Auxiliary variables:** PUMA, authentic.x, + 7 sociodem + cc_receives_care + **cc_primary_type** (from Stage 2)
- **Method:** CART (continuous outcome)
- **Post-imputation:** Cap values at 168 hours/week
- **Result:** ~1,754 + (imputed "Yes") records will have completed cc_hours_per_week

### Database Storage
**Table:** `ne25_imputed_cc_hours_per_week`

```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_cc_hours_per_week (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  cc_hours_per_week DOUBLE NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```

**Expected rows:** ~34 records × M imputations (only originally missing, within cc_receives_care = "Yes")

---

## Variable 4: `childcare_10hrs_nonfamily` (DERIVED)

### Definition
Child receives at least 10 hours/week of childcare from non-family member

### Data Type
- **Database:** `BOOLEAN` (TRUE/FALSE)
- **R:** `logical`
- **Derivation:** Not imputed, calculated from completed cc_primary_type + cc_hours_per_week

### Derivation Logic

```r
childcare_10hrs_nonfamily <- dplyr::case_when(
  # No childcare received
  cc_receives_care == "No" ~ FALSE,

  # Childcare from non-family, >= 10 hours
  cc_receives_care == "Yes" &
    cc_hours_per_week >= 10 &
    cc_primary_type != "Relative care" ~ TRUE,

  # Childcare from family OR < 10 hours
  cc_receives_care == "Yes" &
    (cc_hours_per_week < 10 | cc_primary_type == "Relative care") ~ FALSE,

  # Shouldn't occur after imputation, but handle edge case
  TRUE ~ NA
)
```

### Expected Distribution (After Imputation)
- **All 3,460 eligible records** will have completed childcare_10hrs_nonfamily
- **Expected:** ~70-80% TRUE (among those receiving childcare)
- **FALSE includes:**
  - Children receiving <10 hours/week from non-family
  - Children receiving care from relatives (any hours)
  - Children receiving no childcare at all

### Database Storage
**Table:** `ne25_imputed_childcare_10hrs_nonfamily`

```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_childcare_10hrs_nonfamily (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  childcare_10hrs_nonfamily BOOLEAN NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```

**Expected rows:** 3,460 records × M imputations (all eligible records, since this is the final outcome)

---

## Conditional Imputation Logic Summary

### Stage 1: All Eligible Records (n=3,460)
```
Impute: cc_receives_care
├─ Yes (observed or imputed) → Proceed to Stage 2
└─ No (observed or imputed) → Skip Stage 2, set childcare_10hrs_nonfamily = FALSE
```

### Stage 2: Conditional on cc_receives_care = "Yes" (~1,754 + imputed "Yes")
```
IF cc_receives_care == "Yes":
  Impute: cc_primary_type
  Impute: cc_hours_per_week
ELSE:
  cc_primary_type = NULL (not applicable)
  cc_hours_per_week = NULL (not applicable)
```

### Stage 3: Derive Final Outcome (n=3,460)
```
childcare_10hrs_nonfamily = CASE
  WHEN cc_receives_care = "No" THEN FALSE
  WHEN cc_hours_per_week >= 10 AND cc_primary_type != "Relative care" THEN TRUE
  ELSE FALSE
END
```

---

## Sample Data Flow (Single Record Across M=5 Imputations)

### Example 1: Missing childcare data

**Original:**
- cc_receives_care: NULL
- cc_primary_type: NULL
- cc_hours_per_week: NULL

**After Stage 1 (m=1):**
- cc_receives_care: "Yes" (imputed)

**After Stage 2 (m=1):**
- cc_primary_type: "Non-relative care" (imputed)
- cc_hours_per_week: 40 (imputed)

**After Stage 3 (m=1):**
- childcare_10hrs_nonfamily: TRUE (derived)

**Repeat for m=2, 3, 4, 5** with potentially different imputed values

---

### Example 2: Observed "No childcare"

**Original:**
- cc_receives_care: "No" (observed)
- cc_primary_type: NULL
- cc_hours_per_week: NULL

**After Stage 1:**
- cc_receives_care: "No" (observed, no imputation needed)

**After Stage 2:**
- **Skipped** (not in cc_receives_care = "Yes" filter)
- cc_primary_type: NULL (remains NULL)
- cc_hours_per_week: NULL (remains NULL)

**After Stage 3:**
- childcare_10hrs_nonfamily: FALSE (derived from cc_receives_care = "No")

**All M imputations will be identical** (no missing data to impute)

---

## Validation Checklist

### Pre-Imputation
- [ ] Verify 491 records missing cc_receives_care among eligible
- [ ] Verify ~367 records missing cc_primary_type among cc_receives_care = "Yes"
- [ ] Verify ~34 records missing cc_hours_per_week among cc_receives_care = "Yes"
- [ ] Check for outliers in cc_hours_per_week (identify values > 168)

### Post-Stage 1
- [ ] All 3,460 eligible records have cc_receives_care (no NULL)
- [ ] Only TRUE/FALSE or "Yes"/"No" values (no other categories)
- [ ] Distribution is plausible (~50% "Yes" expected)

### Post-Stage 2
- [ ] cc_primary_type imputed ONLY for cc_receives_care = "Yes" records
- [ ] cc_hours_per_week imputed ONLY for cc_receives_care = "Yes" records
- [ ] Records with cc_receives_care = "No" have NULL for type and hours
- [ ] No cc_hours_per_week values exceed 168

### Post-Stage 3
- [ ] All 3,460 eligible records have childcare_10hrs_nonfamily (no NULL)
- [ ] All records with cc_receives_care = "No" have childcare_10hrs_nonfamily = FALSE
- [ ] Distribution makes sense (~30-50% TRUE expected overall)
- [ ] Logic correct: TRUE only when hours >= 10 AND type != "Relative care"

---

**Phase 2 Complete:** 2025-10-07

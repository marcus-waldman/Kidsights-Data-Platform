# Childcare Imputation - Implementation Summary

**Date:** 2025-10-07
**Status:** Planning Complete, Ready for Implementation

---

## Executive Summary

This document summarizes the 3-stage sequential imputation approach for childcare variables in the NE25 imputation pipeline.

**Final Outcome:** `childcare_10hrs_nonfamily` - Child receives ≥10 hours/week childcare from non-family member

**Method:** Sequential chained imputation with conditional logic across 3 stages

**Database Tables Created:** 4 new tables (3 imputed variables + 1 derived outcome)

**Pipeline Stages Added:** 4 new stages (3 R scripts + 1 Python insertion)

---

## Why 3 Stages?

Childcare data has a **natural hierarchy**:

1. **Does child receive ANY childcare?** (cc_receives_care: Yes/No)
2. **IF YES:** What type and how many hours? (cc_primary_type, cc_hours_per_week)
3. **Derive outcome:** ≥10 hrs/week from non-family?

**Key insight:** Children without childcare (Stage 1 = "No") don't need type/hours imputed → conditional imputation saves computation and respects data structure.

---

## The 3 Stages

### Stage 1: Impute cc_receives_care
**Question:** Does child receive any childcare?

- **Variable:** `cc_receives_care` (Yes/No)
- **Missingness:** 14.2% (491 of 3,460 eligible records)
- **Method:** CART
- **Auxiliary:** PUMA + authentic.x + 7 sociodem variables
- **Output:** All 3,460 records have completed cc_receives_care

### Stage 2: Conditional Imputation (Only for cc_receives_care = "Yes")
**Question:** What TYPE of childcare and HOW MANY hours?

- **Variables:**
  - `cc_primary_type` (6 categories: Non-relative care, Relative care, etc.)
  - `cc_hours_per_week` (continuous: 0-168 hours)
- **Filter:** ONLY records with cc_receives_care = "Yes" (~1,754 + imputed "Yes")
- **Missingness:**
  - cc_primary_type: 20.9% (367 records) among "Yes" group
  - cc_hours_per_week: 1.9% (34 records) among "Yes" group
- **Method:** CART for both variables
- **Auxiliary:** PUMA + authentic.x + 7 sociodem + **cc_receives_care** (from Stage 1)
- **Output:** Completed type/hours for ~1,754+ records; NULL for records with cc_receives_care = "No"

### Stage 3: Derive Final Outcome
**Question:** Does child receive ≥10 hrs/week from NON-FAMILY?

- **Variable:** `childcare_10hrs_nonfamily` (TRUE/FALSE)
- **Logic:**
  - FALSE if cc_receives_care = "No"
  - TRUE if cc_hours_per_week ≥ 10 AND cc_primary_type ≠ "Relative care"
  - FALSE otherwise (< 10 hrs OR relative care)
- **Output:** All 3,460 eligible records have final outcome

---

## Variables Created

| Variable | Type | Missingness (Eligible) | Imputation Method | Database Table |
|----------|------|------------------------|-------------------|----------------|
| cc_receives_care | VARCHAR (Yes/No) | 14.2% (491) | CART | ne25_imputed_cc_receives_care |
| cc_primary_type | VARCHAR (6 levels) | 20.9% (367)* | CART (conditional) | ne25_imputed_cc_primary_type |
| cc_hours_per_week | DOUBLE | 1.9% (34)* | CART (conditional) | ne25_imputed_cc_hours_per_week |
| childcare_10hrs_nonfamily | BOOLEAN | 0% (derived) | Derivation | ne25_imputed_childcare_10hrs_nonfamily |

**\*Among records with cc_receives_care = "Yes"**

---

## Pipeline Flow

```
Start: 3,460 eligible records
│
├─ Stage 4 (New): Impute cc_receives_care
│  ├─ Input: 491 missing (14.2%)
│  └─ Output: All 3,460 completed
│      ├─ ~1,754+ "Yes" → Proceed to Stage 5
│      └─ ~1,200+ "No" → Skip Stage 5, go to Stage 6 with NULL type/hours
│
├─ Stage 5 (New): Conditional imputation (ONLY for "Yes" group)
│  ├─ Filter: cc_receives_care == "Yes" (~1,754 records)
│  ├─ Impute: cc_primary_type (367 missing)
│  ├─ Impute: cc_hours_per_week (34 missing)
│  └─ Output: ~1,754 completed type/hours
│
├─ Stage 6 (New): Derive childcare_10hrs_nonfamily
│  ├─ Merge: cc_receives_care + cc_primary_type + cc_hours_per_week
│  ├─ Derive: Apply logic (≥10 hrs from non-family?)
│  └─ Output: All 3,460 with final outcome (TRUE/FALSE)
│
└─ Stage 7 (New): Insert all 4 variables into database
   └─ Output: 4 new imputation tables
```

---

## Scripts to Create

### R Scripts (3 files)

1. **`scripts/imputation/ne25/03a_impute_cc_receives_care.R`**
   - Load base data (cc_receives_care from ne25_transformed, eligible.x == TRUE)
   - Load PUMA + 7 sociodem for imputation m
   - Impute cc_receives_care using CART (9 auxiliary variables)
   - Save to Feather: `cc_receives_care_m{1..M}.feather`
   - ~200 lines (similar to 02_impute_sociodemographic.R structure)

2. **`scripts/imputation/ne25/03b_impute_cc_type_hours.R`**
   - Load completed cc_receives_care from Stage 4
   - **Filter to cc_receives_care == "Yes"**
   - Load base data (cc_primary_type, cc_hours_per_week)
   - Load PUMA + 7 sociodem for imputation m
   - Impute both variables using CART
   - Cap cc_hours_per_week at 168 (24×7 max)
   - Save to Feather: `cc_primary_type_m{1..M}.feather`, `cc_hours_per_week_m{1..M}.feather`
   - ~250 lines (handles conditional filtering + 2 variables)

3. **`scripts/imputation/ne25/03c_derive_childcare_10hrs.R`**
   - Load completed cc_receives_care, cc_primary_type, cc_hours_per_week
   - Merge all 3 variables
   - Derive childcare_10hrs_nonfamily using case_when logic
   - Save to Feather: `childcare_10hrs_nonfamily_m{1..M}.feather`
   - ~150 lines (simple derivation + merge logic)

### Python Script (1 file)

4. **`scripts/imputation/ne25/04_insert_childcare_imputations.py`**
   - Load all 4 Feather variable sets
   - Create 4 database tables with indexes
   - Insert imputations (only originally missing for first 3 variables, all records for derived variable)
   - Update imputation_metadata for all 4 variables
   - ~400 lines (extends 02b_insert_sociodem_imputations.py pattern)

### Updated Orchestration

5. **Update `scripts/imputation/ne25/run_full_imputation_pipeline.R`**
   - Add Stages 4-7 after existing Stage 3
   - Add progress logging and timing for each new stage
   - Update final summary (14 total imputation tables)
   - ~50 additional lines

---

## Database Schema

### Table 1: ne25_imputed_cc_receives_care
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
**Expected rows:** 491 × M (only originally missing)

### Table 2: ne25_imputed_cc_primary_type
```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_cc_primary_type (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  cc_primary_type VARCHAR NOT NULL,  -- 5 categories
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```
**Expected rows:** ~367 × M (only originally missing, within cc_receives_care = "Yes")

### Table 3: ne25_imputed_cc_hours_per_week
```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_cc_hours_per_week (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  cc_hours_per_week DOUBLE NOT NULL,  -- 0-168
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```
**Expected rows:** ~34 × M (only originally missing, within cc_receives_care = "Yes")

### Table 4: ne25_imputed_childcare_10hrs_nonfamily
```sql
CREATE TABLE IF NOT EXISTS ne25_imputed_childcare_10hrs_nonfamily (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  childcare_10hrs_nonfamily BOOLEAN NOT NULL,  -- TRUE/FALSE
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```
**Expected rows:** 3,460 × M (all eligible records - this is the final analysis variable)

---

## Configuration Updates

Add to `config/imputation/imputation_config.yaml`:

```yaml
# Childcare imputation settings (3-stage sequential)
childcare:
  # Stage 1: Binary childcare receipt
  stage1:
    variable: cc_receives_care
    method: "cart"
    auxiliary_variables:
      - puma
      - authentic.x
      - female
      - raceG
      - educ_mom
      - educ_a2
      - income
      - family_size
      - fplcat

  # Stage 2: Conditional imputation (only for cc_receives_care = "Yes")
  stage2:
    variables:
      - cc_primary_type
      - cc_hours_per_week
    methods:
      cc_primary_type: "cart"
      cc_hours_per_week: "cart"
    conditional_filter: "cc_receives_care == 'Yes'"
    auxiliary_variables:
      - puma
      - authentic.x
      - female
      - raceG
      - educ_mom
      - educ_a2
      - income
      - family_size
      - fplcat
      - cc_receives_care  # From Stage 1
    constraints:
      cc_hours_per_week:
        max: 168  # Cap at 24×7 hours

  # Stage 3: Derived outcome
  stage3:
    variable: childcare_10hrs_nonfamily
    derivation: "cc_hours_per_week >= 10 AND cc_primary_type != 'Relative care'"

  # General settings
  eligible_only: true
  maxit: 5
  chained: true
```

---

## Validation Strategy

### Stage 1 Validation
- [ ] All 3,460 records have cc_receives_care (no NULL)
- [ ] Only "Yes" or "No" values
- [ ] Distribution plausible (~50% "Yes" expected)

### Stage 2 Validation
- [ ] cc_primary_type imputed ONLY for cc_receives_care = "Yes"
- [ ] cc_hours_per_week imputed ONLY for cc_receives_care = "Yes"
- [ ] Records with cc_receives_care = "No" have NULL for type/hours
- [ ] No cc_hours_per_week > 168

### Stage 3 Validation
- [ ] All 3,460 records have childcare_10hrs_nonfamily (no NULL)
- [ ] All cc_receives_care = "No" → childcare_10hrs_nonfamily = FALSE
- [ ] Distribution makes sense (~30-50% TRUE overall)
- [ ] Logic correct: TRUE only when hours ≥ 10 AND type ≠ "Relative care"

### Database Validation
- [ ] 4 new tables created with correct schemas
- [ ] Row counts match expected (491×M, ~367×M, ~34×M, 3460×M)
- [ ] No duplicate (pid, imputation_m) pairs
- [ ] Metadata updated for all 4 variables

---

## Next Steps

1. **Phase 3:** Implement 3 R scripts (03a, 03b, 03c)
2. **Phase 4:** Implement Python database insertion (04)
3. **Phase 5:** Update pipeline orchestration
4. **Phase 6:** Update helper functions for childcare queries
5. **Phase 7:** Test end-to-end with M=2
6. **Phase 8:** Full production run with M=5

---

## Related Documentation

- [CHILDCARE_IMPUTATION_IMPLEMENTATION.md](CHILDCARE_IMPUTATION_IMPLEMENTATION.md) - Detailed phase-by-phase tasks
- [PHASE1_ARCHITECTURE_REVIEW.md](PHASE1_ARCHITECTURE_REVIEW.md) - Architecture integration points
- [PHASE2_CHILDCARE_VARIABLES.md](PHASE2_CHILDCARE_VARIABLES.md) - Complete variable specifications

---

**Summary Complete:** 2025-10-07

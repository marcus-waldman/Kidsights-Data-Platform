# Imputation Stage Builder Agent - Test Scenarios

**Purpose:** Test cases for validating agent functionality

**Last Updated:** October 8, 2025 | **Version:** 1.0.0

---

## Overview

This document defines 3 comprehensive test scenarios for the `imputation-stage-builder` agent, covering the most common imputation patterns:

1. **Scenario 1:** Simple Unconditional Imputation
2. **Scenario 2:** Conditional Imputation
3. **Scenario 3:** Multi-Stage with Derived Variables

Each scenario includes expected inputs, agent behavior, and validation criteria.

---

## Scenario 1: Simple Unconditional Imputation

**Pattern:** All variables imputed unconditionally for all eligible records

**Example Domain:** Perceived Stress Scale (PSS-4)

### Input Specification

```yaml
stage_number: "07"
domain: "perceived_stress"
domain_title: "Perceived Stress"
domain_short: "ps"
study_id: "ne25"

variables:
  - name: "pss_1"
    type: "INTEGER"
    description: "Felt unable to control important things (0-4 scale)"
    value_range: "0-4"
  - name: "pss_2"
    type: "INTEGER"
    description: "Felt confident about handling problems (0-4 scale, reversed)"
    value_range: "0-4"
  - name: "pss_3"
    type: "INTEGER"
    description: "Felt things were going your way (0-4 scale, reversed)"
    value_range: "0-4"
  - name: "pss_4"
    type: "INTEGER"
    description: "Felt difficulties piling up (0-4 scale)"
    value_range: "0-4"

derived_variables:
  - name: "pss_total"
    type: "INTEGER"
    description: "PSS-4 total score (sum of 4 items)"
    formula: "pss_1 + pss_2 + pss_3 + pss_4"
    value_range: "0-16"
    missing_rule: "na.rm = FALSE"

mice_method: "cart"
mice_params:
  maxit: 5
  remove.collinear: false

auxiliary_variables:
  - "puma"
  - "female"
  - "age_years"
  - "raceG"
  - "income"
  - "educ_mom"
  - "phq2_positive"  # From previous stage

conditional_logic: false

variables_summary: "PSS-4 items + total"
```

### Expected Agent Behavior

**Step 1: Requirements Gathering**
```
Agent asks:
1. What stage number? → 07
2. What domain? → perceived_stress
3. What variables? → pss_1, pss_2, pss_3, pss_4
4. Data types? → All INTEGER (0-4 Likert)
5. MICE method? → cart
6. Derived variables? → pss_total (sum of 4 items)
7. Conditional? → No
8. Auxiliary variables? → puma, female, age_years, raceG, income, educ_mom, phq2_positive
9. Study ID? → ne25
```

**Step 2: Confirmation**
```
Agent confirms:
- Will create: scripts/imputation/ne25/07_impute_perceived_stress.R
- Will create: scripts/imputation/ne25/07b_insert_perceived_stress.py
- Will create: data/imputation/ne25/perceived_stress_feather/
- Variables: 4 items + 1 derived = 5 total
- Method: cart
- Conditional: No
```

**Step 3: File Generation**

Agent creates 3 items:
1. R script (07_impute_perceived_stress.R)
2. Python script (07b_insert_perceived_stress.py)
3. Output directory with .gitkeep

### Validation Criteria

**R Script Must Have:**
- ✅ Header with domain and variable descriptions
- ✅ `set.seed(seed + m)` inside for loop
- ✅ Defensive filtering in all DBI::dbGetQuery calls
- ✅ load_base_perceived_stress_data() function
- ✅ load_puma_imputation() function
- ✅ load_auxiliary_imputations_for_perceived_stress() function
- ✅ merge_imputed_data() function
- ✅ save_perceived_stress_feather() function
- ✅ TODO markers for predictor matrix configuration
- ✅ TODO markers for MICE method verification
- ✅ Derived variable calculation: pss_total <- rowSums(..., na.rm=FALSE)
- ✅ Save logic: only originally_missing records
- ✅ R namespacing: dplyr::, arrow::, mice::

**Python Script Must Have:**
- ✅ Header with domain and variable descriptions
- ✅ Project root setup (parent.parent.parent.parent)
- ✅ 5 table creation statements (4 items + 1 derived)
- ✅ Each table: PRIMARY KEY (study_id, pid, record_id, imputation_m)
- ✅ Each table: 2 indexes (pid/record_id, imputation_m)
- ✅ load_feather_files() function
- ✅ create_perceived_stress_tables() function
- ✅ insert_perceived_stress_imputations() function
- ✅ update_metadata() calls for all 5 variables
- ✅ validate_perceived_stress_tables() function
- ✅ NULL filtering before insertion
- ✅ TODO markers for data type verification
- ✅ TODO markers for validation rules

**TODO Markers Expected:**
- [DOMAIN LOGIC] Configure predictor matrix
- [STATISTICAL DECISION] Verify MICE method
- [STATISTICAL DECISION] Should target variables predict each other?
- [DATA TYPE] Verify INTEGER for 0-4 Likert
- [VALIDATION RULE] Check 0-4 range for items
- [VALIDATION RULE] Check 0-16 range for total

---

## Scenario 2: Conditional Imputation

**Pattern:** Some variables only imputed if gating variable equals specific value

**Example Domain:** Employment Status and Details

### Input Specification

```yaml
stage_number: "08"
domain: "employment"
domain_title: "Employment"
domain_short: "emp"
study_id: "ne25"

variables:
  - name: "employed"
    type: "INTEGER"
    description: "Currently employed (0=no, 1=yes)"
    value_range: "0-1"
    imputation: "unconditional"
  - name: "hours_per_week"
    type: "DOUBLE"
    description: "Hours worked per week (if employed)"
    value_range: "1-80"
    imputation: "conditional"
    condition: "employed = 1"
  - name: "job_type"
    type: "VARCHAR"
    description: "Type of employment (if employed)"
    categories: ["full_time", "part_time", "self_employed", "gig_work"]
    imputation: "conditional"
    condition: "employed = 1"

derived_variables:
  - name: "full_time_employed"
    type: "INTEGER"
    description: "Works 35+ hours per week"
    formula: "ifelse(hours_per_week >= 35, 1, 0)"
    value_range: "0-1"
    condition: "employed = 1"

mice_method:
  employed: "cart"
  hours_per_week: "pmm"
  job_type: "cart"

auxiliary_variables:
  - "puma"
  - "female"
  - "age_years"
  - "raceG"
  - "income"
  - "educ_a1"

conditional_logic: true
conditional_stages:
  - stage: 1
    variables: ["employed"]
    description: "Impute employment status unconditionally"
  - stage: 2
    variables: ["hours_per_week", "job_type"]
    condition: "employed == 1"
    description: "Impute details only for employed individuals"

variables_summary: "Employment status + details (conditional)"
```

### Expected Agent Behavior

**Step 1: Requirements Gathering**
```
Agent asks:
1. What stage number? → 08
2. What domain? → employment
3. What variables? → employed, hours_per_week, job_type
4. Data types? → employed (INTEGER binary), hours_per_week (DOUBLE), job_type (VARCHAR)
5. MICE method? → employed (cart), hours_per_week (pmm), job_type (cart)
6. Derived variables? → full_time_employed (hours >= 35)
7. Conditional? → Yes, hours and job_type only if employed = 1
8. Auxiliary variables? → puma, female, age_years, raceG, income, educ_a1
9. Study ID? → ne25
```

**Step 2: Conditional Logic Confirmation**
```
Agent confirms:
- Stage 1: Impute employed unconditionally
- Stage 2: Filter to employed == 1, then impute hours_per_week and job_type
- Will use conditional imputation pattern
- Will include nrow() check before MICE in stage 2
```

**Step 3: File Generation**

Agent warns about conditional complexity and creates files with additional TODOs for conditional logic.

### Validation Criteria

**R Script Must Have:**
- ✅ Two-stage imputation loop structure
- ✅ Stage 1: Impute employed for all records
- ✅ Stage 2: Filter to employed == 1, check nrow() > 0, then impute
- ✅ Conditional save logic: only save hours/job_type if employed == 1
- ✅ TODO markers for handling case where nrow() == 0
- ✅ Defensive filtering in both stages
- ✅ Different MICE methods for different variables

**Python Script Must Have:**
- ✅ 4 table creation statements (3 variables + 1 derived)
- ✅ Conditional file loading: required=False for hours_per_week and job_type
- ✅ Handle missing Feather files gracefully
- ✅ Only insert if files exist and have rows
- ✅ Only update metadata if data was inserted

**TODO Markers Expected:**
- [DOMAIN LOGIC] What if no one is employed in imputation m?
- [STATISTICAL DECISION] Should employed predict hours/job_type?
- [VALIDATION RULE] Check 1-80 range for hours_per_week
- [VALIDATION RULE] Check valid categories for job_type

---

## Scenario 3: Multi-Stage with Derived Variables

**Pattern:** Many related items imputed together, then derived variables calculated

**Example Domain:** Parenting Stress Index Short Form (PSI-SF 12 items)

### Input Specification

```yaml
stage_number: "09"
domain: "parenting_stress"
domain_title: "Parenting Stress"
domain_short: "psi"
study_id: "ne25"

variables:
  - name: "psi_1"
    type: "INTEGER"
    description: "PSI item 1 (1-5 scale)"
    value_range: "1-5"
  - name: "psi_2"
    type: "INTEGER"
    description: "PSI item 2 (1-5 scale)"
    value_range: "1-5"
  # ... repeat for psi_3 through psi_12
  - name: "psi_12"
    type: "INTEGER"
    description: "PSI item 12 (1-5 scale)"
    value_range: "1-5"

derived_variables:
  - name: "psi_total"
    type: "INTEGER"
    description: "PSI total score (sum of 12 items)"
    formula: "rowSums(select(psi_1:psi_12), na.rm=FALSE)"
    value_range: "12-60"
  - name: "psi_parental_distress"
    type: "INTEGER"
    description: "Parental distress subscale (items 1-4)"
    formula: "rowSums(select(psi_1:psi_4), na.rm=FALSE)"
    value_range: "4-20"
  - name: "psi_parent_child_interaction"
    type: "INTEGER"
    description: "Parent-child dysfunctional interaction (items 5-8)"
    formula: "rowSums(select(psi_5:psi_8), na.rm=FALSE)"
    value_range: "4-20"
  - name: "psi_difficult_child"
    type: "INTEGER"
    description: "Difficult child subscale (items 9-12)"
    formula: "rowSums(select(psi_9:psi_12), na.rm=FALSE)"
    value_range: "4-20"
  - name: "psi_high_stress"
    type: "INTEGER"
    description: "Total score >= 33 (clinical cutoff)"
    formula: "ifelse(psi_total >= 33, 1, 0)"
    value_range: "0-1"

mice_method: "rf"  # Random forest for complex interactions
mice_params:
  maxit: 10
  ntree: 10  # Reduced for performance

auxiliary_variables:
  - "puma"
  - "female"
  - "age_years"
  - "raceG"
  - "income"
  - "family_size"
  - "child_age_years"
  - "phq2_positive"
  - "gad2_positive"

conditional_logic: false

variables_summary: "PSI-12 items + 5 derived scores"
```

### Expected Agent Behavior

**Step 1: Requirements Gathering**
```
Agent asks:
1. What stage number? → 09
2. What domain? → parenting_stress
3. What variables? → psi_1 through psi_12 (12 items)
4. Data types? → All INTEGER (1-5 Likert)
5. MICE method? → rf (random forest)
6. Derived variables? → 5 derived (total, 3 subscales, high stress indicator)
7. Conditional? → No
8. Auxiliary variables? → puma, female, age, race, income, family_size, child_age, phq2_positive, gad2_positive
9. Study ID? → ne25
```

**Step 2: Random Forest Warning**
```
Agent warns:
- Random forest requires adequate sample size (N > 100 recommended)
- Computationally intensive with 12 variables
- Consider using ntree=10 for performance
- May need to increase maxit to 10 for convergence
```

**Step 3: File Generation**

Agent creates files with 17 total variables (12 items + 5 derived).

### Validation Criteria

**R Script Must Have:**
- ✅ 12 item variables in MICE configuration
- ✅ Random forest method specified
- ✅ Increased maxit parameter (10 instead of default 5)
- ✅ ntree parameter in MICE call
- ✅ Predictor matrix allowing items to predict each other
- ✅ 5 derived variable calculations after MICE
- ✅ All derived use na.rm=FALSE
- ✅ Save logic for all 17 variables
- ✅ TODO markers about sample size adequacy

**Python Script Must Have:**
- ✅ 17 table creation statements (12 items + 5 derived)
- ✅ Consistent INTEGER data type for all PSI variables
- ✅ 17 update_metadata() calls
- ✅ Validation for 1-5 range (items)
- ✅ Validation for subscale ranges (4-20)
- ✅ Validation for total range (12-60)
- ✅ Validation for binary high_stress (0-1)

**TODO Markers Expected:**
- [STATISTICAL DECISION] Is sample size adequate for RF? (N > 100)
- [STATISTICAL DECISION] Should all 12 items predict each other?
- [DOMAIN LOGIC] Verify subscale item groupings are correct
- [VALIDATION RULE] Check 1-5 range for all items
- [VALIDATION RULE] Check subscale sums are consistent

---

## Testing Process

For each scenario:

### 1. Agent Invocation
```
User: "I want to add [scenario domain] imputation to the pipeline"
```

### 2. Requirements Dialog
- Agent should ask all required questions
- User provides scenario-specific answers
- Agent confirms understanding

### 3. File Generation
- Agent creates R script, Python script, output directory
- Agent provides completion checklist

### 4. R Script Review
- Verify all required sections present
- Check pattern compliance (seeds, filtering, storage)
- Verify TODO markers are appropriate
- Confirm scenario-specific logic (conditional, RF params, etc.)

### 5. Python Script Review
- Verify table creation for all variables
- Check indexes and primary keys
- Verify metadata tracking
- Confirm NULL filtering

### 6. Validation Mode Test
- Introduce intentional error (e.g., `set.seed(seed)`)
- Run validation mode
- Verify error is caught and reported correctly

### 7. Integration Test
- Request pipeline integration
- Verify orchestrator code is correct
- Verify helper function is correct
- Check documentation snippets

---

## Success Criteria

**Overall Success:** Agent passes all 3 scenarios

**Per-Scenario Success:**
- ✅ Generates correct file structure
- ✅ All critical patterns enforced
- ✅ TODO markers appropriate for scenario
- ✅ Scenario-specific logic handled correctly
- ✅ Validation mode catches intentional errors
- ✅ Integration code is accurate

---

## Notes

**Scenario Selection Rationale:**
- **Scenario 1:** Most common pattern, baseline functionality
- **Scenario 2:** Tests conditional logic handling (common complexity)
- **Scenario 3:** Tests multi-item scales, derived variables, RF method (maximum complexity)

**Coverage:** These 3 scenarios cover ~90% of real-world imputation stage patterns in the Kidsights platform.

# Mother's Education - Missing Raking Target

**Issue Identified:** Mother's education (Bachelor's degree or higher) is missing from the current raking_targets.csv file.

**Date:** 2025-10-03

---

## Why This Matters

Mother's education is a **critical socioeconomic indicator** for post-stratification raking because:

1. **Strong predictor** of child outcomes and survey participation
2. **Shows age variation** (44-47% across ages 0-5) - requires stratification
3. **Well-measured in ACS** - 94.8% coverage via household linkage
4. **Standard raking variable** - commonly used in survey methodology

---

## Data Source: ACS

### Variable Information

**Primary Variable:** `EDUC_MOM` (mother's educational attainment)

**Coding:**
- 0-6: Less than Bachelor's degree
- 7: High school graduate or GED
- 8: Some college, no degree
- **10: Bachelor's degree**
- **11: Master's degree**
- 12-13: Professional/Doctoral degree

**Definition:** Bachelor's or higher = `EDUC_MOM >= 10`

### Current Nebraska Values (ACS 2019-2023)

| Child Age | Total Children | Mother Bachelor's+ | Percentage |
|-----------|---------------|-------------------|------------|
| 0 | 1,029 | 472 | 45.9% |
| 1 | 1,026 | 470 | 45.8% |
| 2 | 1,084 | 479 | 44.2% |
| 3 | 1,105 | 524 | 47.4% |
| 4 | 1,229 | 570 | 46.4% |
| 5 | 1,184 | 544 | 45.9% |

**Coverage:** 94.8% of children have mother in household (`MOMLOC > 0`)

---

## Rows to Add to raking_targets.csv

Add these **6 rows** to the CSV file (one for each age 0-5):

```csv
age_years (floor),estimand,dataset,estimator,est
0,"Proportion of children whose mother has Bachelor's degree or higher",ACS NE 5-year,GLM,
1,"Proportion of children whose mother has Bachelor's degree or higher",ACS NE 5-year,GLM,
2,"Proportion of children whose mother has Bachelor's degree or higher",ACS NE 5-year,GLM,
3,"Proportion of children whose mother has Bachelor's degree or higher",ACS NE 5-year,GLM,
4,"Proportion of children whose mother has Bachelor's degree or higher",ACS NE 5-year,GLM,
5,"Proportion of children whose mother has Bachelor's degree or higher",ACS NE 5-year,GLM,
```

**Note:** The `est` column will be filled by the estimation script.

---

## Expected Estimates

Based on current ACS data, the estimates should be approximately:

```
Age 0: 0.459 (45.9%)
Age 1: 0.458 (45.8%)
Age 2: 0.442 (44.2%)
Age 3: 0.474 (47.4%)
Age 4: 0.464 (46.4%)
Age 5: 0.459 (45.9%)
```

---

## R Code to Calculate Estimates

```r
library(dplyr)
library(DBI)
library(duckdb)

# Connect to database
conn <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")

# Load ACS data
acs_data <- dbGetQuery(conn, "
  SELECT AGE, EDUC_MOM, PERWT, MOMLOC
  FROM acs_data
  WHERE state = 'nebraska'
  AND AGE BETWEEN 0 AND 5
")

# Calculate mother's education (Bachelor's+) by child age
mom_educ_estimates <- acs_data %>%
  group_by(AGE) %>%
  summarise(
    total_children = n(),
    prop_bachelors_plus = weighted.mean(
      EDUC_MOM >= 10,
      w = PERWT,
      na.rm = TRUE  # Exclude children with no mother link
    ),
    .groups = 'drop'
  )

print(mom_educ_estimates)

# Extract as vector for raking targets
mom_educ_by_age <- setNames(
  mom_educ_estimates$prop_bachelors_plus,
  paste0("age_", mom_educ_estimates$AGE)
)

print(mom_educ_by_age)
```

---

## Integration with Raking Procedure

### Current Raking Targets (Before Addition)

**Total:** 186 rows (31 estimands)

- ACS: 24 estimands × 6 ages = 144 rows (all constant)
- NHIS: 4 estimands × 6 ages = 24 rows (all constant)
- NSCH: 4 estimands × 6 ages = 24 rows (varies by age)

### Updated Raking Targets (After Addition)

**After mother's education:** 192 rows (32 estimands)
**After mother's education + marital status:** 204 rows (34 estimands)

- ACS: **26 estimands** × 6 ages = **156 rows** (24 constant + **2 vary**)
  - Mother's education: 6 rows (varies by age)
  - Mother's marital status: 6 rows (varies by age) - see `MOTHER_MARITAL_STATUS_ADDITION.md`
- NHIS: 4 estimands × 6 ages = 24 rows (all constant)
- NSCH: 4 estimands × 6 ages = 24 rows (varies by age)

### Why Age-Stratified?

Mother's education shows **meaningful variation by child age** (range: 44.2% to 47.4%):

1. **Cohort effects:** Mothers of older children may have different education profiles
2. **Birth timing:** Education level may correlate with timing of childbearing
3. **Sample composition:** Younger children may have younger/older mothers

**Decision:** Stratify by age to capture this variation in the raking procedure.

---

## Validation Checks

After adding the rows and calculating estimates:

1. **Range check:** All estimates should be between 0.40 and 0.50 (40-50%)
2. **Missing data:** ~5% missing (children with no mother link) - should be excluded with `na.rm = TRUE`
3. **Weighted vs unweighted:** Weighted estimates should use `PERWT` for accurate population estimates
4. **Age pattern:** Should show slight variation across ages (not identical values)

---

## References

- **ACS Variable Documentation:** https://usa.ipums.org/usa-action/variables/EDUC_MOM
- **ACS Transformation Guide:** `docs/acs/transformation_mappings.md`
- **Main Raking Plan:** `docs/raking/RAKING_TARGETS_ESTIMATION_PLAN.md`

---

**Action Required:**
1. Add 6 rows to `raking_targets.csv` (see "Rows to Add" section above)
2. Update estimation script to include mother's education calculation
3. Verify estimates match expected values (~44-47%)

**Status:** Documentation complete, awaiting CSV update

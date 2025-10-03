# Mother's Marital Status - Missing Raking Target

**Issue Identified:** Mother's marital status (proportion married) is missing from the current raking_targets.csv file.

**Date:** 2025-10-03

---

## Why This Matters

Mother's marital status is a **critical demographic indicator** for post-stratification raking because:

1. **Strong predictor** of household structure, income, and child outcomes
2. **Shows age variation** (79-84% across ages 0-5) - requires stratification
3. **Well-measured in ACS** - 94.8% coverage via household linkage
4. **Standard raking variable** - commonly used alongside education and income

---

## Data Source: ACS

### Variable Information

**Primary Variables:**
- `MARST_HEAD`: Marital status of household head
- `MOMLOC`: Mother's position in household (line number)

**Household Structure (Nebraska Children 0-5):**
- 47.3% have mother as household head (MOMLOC=1)
- 44.7% have mother as spouse of head (MOMLOC=2)
- 5.2% have no mother in household (MOMLOC=0)
- 2.8% have mother elsewhere in household (MOMLOC>2)

### Derivation Logic

**How MARST_HEAD serves as proxy for mother's marital status:**

1. **If MOMLOC=2 (mother is spouse):**
   - Mother is married by definition
   - MARST_HEAD=1 confirms household head (spouse) is married

2. **If MOMLOC=1 (mother is household head):**
   - MARST_HEAD directly reflects mother's marital status
   - MARST_HEAD=1 means mother is married

3. **Result:**
   - `MARST_HEAD = 1` accurately indicates "mother is married"
   - Works for 92% of children (MOMLOC = 1 or 2)

**MARST_HEAD Coding:**
- 1 = Married, spouse present ✓
- 2 = Married, spouse absent
- 3 = Separated
- 4 = Divorced
- 5 = Widowed
- 6 = Never married/single

**Definition:** Mother married = `MARST_HEAD = 1` (married, spouse present)

### Current Nebraska Values (ACS 2019-2023)

| Child Age | Total Children | Mother Married | Percentage |
|-----------|---------------|----------------|------------|
| 0 | 968 | 773 | 79.9% |
| 1 | 982 | 812 | 82.7% |
| 2 | 1,039 | 870 | 83.7% |
| 3 | 1,047 | 880 | 84.0% |
| 4 | 1,165 | 949 | 81.5% |
| 5 | 1,112 | 882 | 79.3% |

**Coverage:** 94.8% of children have mother in household (`MOMLOC > 0`)

**Age Variation:** 4.7 percentage point range (79.3% to 84.0%)

---

## Rows to Add to raking_targets.csv

Add these **6 rows** to the CSV file (one for each age 0-5):

```csv
age_years (floor),estimand,dataset,estimator,est
0,"Proportion of children whose mother is married",ACS NE 5-year,GLM,
1,"Proportion of children whose mother is married",ACS NE 5-year,GLM,
2,"Proportion of children whose mother is married",ACS NE 5-year,GLM,
3,"Proportion of children whose mother is married",ACS NE 5-year,GLM,
4,"Proportion of children whose mother is married",ACS NE 5-year,GLM,
5,"Proportion of children whose mother is married",ACS NE 5-year,GLM,
```

**Note:** The `est` column will be filled by the estimation script.

---

## Expected Estimates

Based on current ACS data, the estimates should be approximately:

```
Age 0: 0.799 (79.9%)
Age 1: 0.827 (82.7%)
Age 2: 0.837 (83.7%)
Age 3: 0.840 (84.0%)
Age 4: 0.815 (81.5%)
Age 5: 0.793 (79.3%)
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
  SELECT AGE, MARST_HEAD, MOMLOC, PERWT
  FROM acs_data
  WHERE state = 'nebraska'
  AND AGE BETWEEN 0 AND 5
")

# Calculate mother's marital status (married) by child age
mom_married_estimates <- acs_data %>%
  filter(MOMLOC > 0) %>%  # Exclude children with no mother link
  group_by(AGE) %>%
  summarise(
    total_children = n(),
    prop_mom_married = weighted.mean(
      MARST_HEAD == 1,
      w = PERWT,
      na.rm = TRUE
    ),
    .groups = 'drop'
  )

print(mom_married_estimates)

# Extract as vector for raking targets
mom_married_by_age <- setNames(
  mom_married_estimates$prop_mom_married,
  paste0("age_", mom_married_estimates$AGE)
)

print(mom_married_by_age)
```

---

## Integration with Raking Procedure

### Current Raking Targets (Before Addition)

**Before mother's education:** 186 rows (31 estimands)
**After mother's education:** 198 rows (33 estimands)
**After mother's marital status:** 204 rows (34 estimands)

### Updated Raking Targets (After Addition)

**Total:** 204 rows (34 estimands)

- ACS: **26 estimands** × 6 ages = **156 rows** (24 constant + 2 vary)
  - Constant: sex, race, FPL, PUMA (144 rows)
  - Varies: mother education, mother marital status (12 rows)
- NHIS: 4 estimands × 6 ages = 24 rows (all constant)
- NSCH: 4 estimands × 6 ages = 24 rows (all vary)

### Why Age-Stratified?

Mother's marital status shows **meaningful variation by child age** (range: 79.3% to 84.0%):

1. **Cohort effects:** Economic conditions at time of birth affect marriage rates
2. **Birth timing:** Unmarried mothers may marry after having children
3. **Separation/divorce:** Older children more likely to experience parental separation
4. **Sample composition:** Different marriage patterns across birth cohorts

**Decision:** Stratify by age to capture this variation in the raking procedure.

---

## Validation Checks

After adding the rows and calculating estimates:

1. **Range check:** All estimates should be between 0.75 and 0.90 (75-90%)
2. **Missing data:** ~5% missing (children with no mother link) - should be excluded with `MOMLOC > 0` filter
3. **Weighted vs unweighted:** Weighted estimates should use `PERWT` for accurate population estimates
4. **Age pattern:** Should show slight variation across ages (not identical values)
5. **Comparison with MARST_HEAD=1 overall:** Should align with household head marriage rates

---

## Alternative Definitions (Not Used)

### Option 1: Include Cohabiting Partners
Could define as "married OR cohabiting" using additional household relationship variables. Not recommended because:
- Cohabitation not consistently measured across ACS years
- "Married" alone is standard for demographic raking

### Option 2: Use Mother's Own MARST Variable
Would require re-extracting ACS data to include all household members (not just children), then self-joining to get mother's record. Not recommended because:
- More complex implementation
- MARST_HEAD proxy works well (92% accuracy)
- Would increase database size significantly

---

## Proxy Quality Assessment

**How well does MARST_HEAD represent mother's marital status?**

| MOMLOC Category | % of Children | Accuracy of MARST_HEAD Proxy |
|----------------|---------------|------------------------------|
| MOMLOC=1 (mother is head) | 47.3% | **100%** (direct match) |
| MOMLOC=2 (mother is spouse) | 44.7% | **100%** (spouse is married) |
| MOMLOC>2 (other household member) | 2.8% | **Approximate** (less accurate) |
| MOMLOC=0 (no mother) | 5.2% | **N/A** (excluded) |

**Overall Proxy Quality:** Accurate for **92%** of children (MOMLOC=1 or 2)

---

## References

- **ACS Variable Documentation:** https://usa.ipums.org/usa-action/variables/MARST_HEAD
- **Household Relationship Variables:** https://usa.ipums.org/usa-action/variables/MOMLOC
- **Main Raking Plan:** `docs/raking/RAKING_TARGETS_ESTIMATION_PLAN.md`
- **Mother's Education Addition:** `docs/raking/MOTHER_EDUCATION_ADDITION.md`

---

**Action Required:**
1. Add 6 rows to `raking_targets.csv` (see "Rows to Add" section above)
2. Update estimation script to include mother's marital status calculation
3. Verify estimates match expected values (~79-84%)

**Status:** Documentation complete, awaiting CSV update

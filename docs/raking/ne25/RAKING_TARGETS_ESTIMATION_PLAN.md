# Raking Targets Estimation Plan

**Purpose:** Compute population-level estimates to fill the `est` column in `raking_targets.csv` for post-stratification raking of Nebraska NE25 survey data.

**Date:** 2025-10-03
**Status:** Planning Phase

---

## Overview

### File Structure

The `raking_targets.csv` file contains:
- **192 total rows** = 32 unique estimands × 6 age bins (0-5 years)
- **Columns:**
  - `age_years (floor)`: Child age in years (0, 1, 2, 3, 4, 5)
  - `estimand`: Description of the population estimate
  - `dataset`: Data source (ACS NE 5-year, NHIS, NSCH)
  - `estimator`: Statistical method (GLM, Mixed model)
  - `est`: **TARGET COLUMN TO FILL** (currently empty)

### Data Sources

| Dataset | Records Available | Age Coverage | Nebraska Filter | Estimation Method |
|---------|------------------|--------------|-----------------|-------------------|
| **ACS** | 24,449 children ages 0-5<br>(6,657 from 5 survey years) | All ages 0-5 | `STATEFIP = 31` | **GLM with age × year interaction** |
| **NHIS** | 15,208 parents with children 0-5<br>(from 229,609 total records) | Household-linked | `REGION = 2` (North Central) | Mixed model, regional random effects |
| **NSCH** | 21,524 children ages 0-5 | Age-specific | `FIPSST = 31` | Mixed model, state random effects, age-stratified |

### Key Insight: Age Variation Pattern

**From the CSV structure:**
- **ACS and NHIS estimates repeat identically for all 6 age bins** (same value ages 0-5)
- **NSCH estimates vary by age** (different values for each age 0-5)

**Reason:**
- ACS/NHIS provide demographic/parent-level estimates (constant across child ages)
- NSCH provides child-specific developmental outcomes (age-dependent)

---

## Phase 1: ACS Estimates (26 estimands)

### Data Source
- **Table:** `acs_data`
- **Sample:** 6,657 Nebraska children ages 0-5 (across 5 survey years: 2019-2023)
- **Weights:** `PERWT` (person weight for population estimates)
- **Survey Design Variables:** `CLUSTER`, `STRATA` (for complex survey design)
- **Filter:** `state = 'nebraska'` AND `AGE BETWEEN 0 AND 5`

### Estimation Method: Generalized Linear Models (GLM)

**Approach:** Model-based estimation using survey-weighted GLM with age, survey year, and interaction effects.

**Rationale:**
1. **Efficiency:** Borrows strength across 5 survey years (2019-2023) for more precise estimates
2. **Trend Smoothing:** Reduces year-to-year sampling variability
3. **Principled Uncertainty:** Provides proper standard errors accounting for survey design
4. **Consistency:** Aligns with NHIS/NSCH model-based approaches

### CRITICAL: Defensive Coding for Missing Data

**⚠️ Problem:** IPUMS ACS variables contain special missing data codes that can corrupt estimates if not explicitly filtered.

**Solution:** All data preparation steps MUST explicitly exclude missing codes before creating binary/categorical outcomes.

**IPUMS ACS Missing Data Codes:**
| Variable | Missing Codes | Valid Range | Defensive Filter |
|----------|--------------|-------------|------------------|
| SEX | 9 (Missing/blank) | 1-2 | `SEX %in% c(1, 2)` |
| HISPAN | 9 (Not Reported), 498-499 (Other) | 0-4 | `HISPAN %in% 0:4` |
| RACE | 997 (Unknown), 996, 363, 380 | 1-9 (excluding missing) | `RACE %in% 1:9 & !(RACE %in% c(363, 380, 996, 997))` |
| POVERTY | 000 (N/A) | 1-501 | `POVERTY >= 1 & POVERTY <= 501` |
| EDUC | 999 (Missing), 001 (N/A) | 2-998 | `EDUC >= 2 & EDUC <= 998` |
| MARST | 9 (Blank, missing) | 1-6 | `MARST %in% 1:6` |
| PUMA | 77777 (Special code) | 5-digit valid codes | Check state-specific valid codes |

**Example - WRONG vs RIGHT:**
```r
# ❌ WRONG - Includes HISPAN=9 (Not Reported)
I(HISPAN >= 1)

# ✅ RIGHT - Explicitly filters to valid Hispanic codes
I(HISPAN >= 1 & HISPAN <= 4)

# ❌ WRONG - Includes RACE=997 (Unknown)
I(RACE == 2)

# ✅ RIGHT - Filters valid RACE values first
acs_data_clean <- acs_data %>%
  dplyr::filter(RACE %in% 1:9, !(RACE %in% c(363, 380, 996, 997)))

# Then use clean data
I(RACE == 2)
```

**Implementation Strategy:**
1. **Filter missing codes BEFORE creating survey design object** (preferred)
2. Apply defensive filters to all binary outcomes: `I((condition) & valid_range_check)`
3. Document which codes were excluded in script comments

**Model Specification:**
```r
library(survey)

# STEP 1: Filter out missing data codes BEFORE creating survey design
acs_data_clean <- acs_data %>%
  dplyr::filter(
    # Exclude missing codes for core demographics
    SEX %in% c(1, 2),                                    # Valid sex codes
    HISPAN %in% 0:4,                                     # Valid Hispanic codes (exclude 9, 498-499)
    RACE %in% 1:9,                                       # Valid race codes
    !(RACE %in% c(363, 380, 996, 997)),                 # Exclude special missing codes
    POVERTY >= 1 & POVERTY <= 501,                      # Valid poverty ratio (exclude 000)
    AGE >= 0 & AGE <= 5                                 # Target age range
  )

# STEP 2: Create survey design object from clean data
acs_design <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_clean
)

# STEP 3: Fit weighted logistic regression
model <- svyglm(
  outcome ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design,
  family = quasibinomial()
)

# STEP 4: Predict at MULTYEAR=2023 (most recent year) for each age
pred_data <- data.frame(AGE = 0:5, MULTYEAR = 2023)
estimates <- predict(model, newdata = pred_data, type = "response", se.fit = TRUE)
```

**Key Variables:**
- `AGE`: Child age (0-5 years)
- `MULTYEAR`: Actual survey year (2019-2023, not publication year)
- `AGE:MULTYEAR`: Interaction term to capture differential trends by age

**Prediction Strategy:**
- Estimate at `MULTYEAR = 2023` (most recent year) for all ages
- This provides most current population estimates while borrowing information across years

### Estimands to Calculate

#### 1. Sex (1 estimand)
**Estimand:** "Proportion of children identifying as male"

**Variable:** `SEX`
- 1 = Male
- 2 = Female
- 9 = Missing/blank ⚠️ EXCLUDE

**Calculation (GLM with defensive coding):**
```r
# Data already filtered for SEX %in% c(1, 2) in acs_data_clean

# Fit model
model_sex <- svyglm(
  I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design,  # Uses acs_data_clean
  family = quasibinomial()
)

# Predict at 2023 for each age
pred_sex <- predict(model_sex,
                    newdata = data.frame(AGE = 0:5, MULTYEAR = 2023),
                    type = "response")
```

**Note:** Sex ratio typically constant across ages, so interaction may not be significant. Consider simplifying to main effects only if interaction p > 0.05.

**Fills rows:** Age 0-5 (6 values - GLM estimates at 2023)

---

#### 2. Race/Ethnicity (3 estimands)

**Estimand 1:** "Proportion of children identifying as white alone, non-Hispanic"

**Variables:** `RACE`, `HISPAN`
- `RACE = 1` (White)
- `HISPAN = 0` (Not Hispanic)
- ⚠️ EXCLUDE: HISPAN 9, 498-499 (missing); RACE 363, 380, 996, 997 (missing)

**Calculation (GLM with defensive coding):**
```r
# Data already filtered in acs_data_clean
# HISPAN %in% 0:4, RACE %in% 1:9, !(RACE %in% c(363, 380, 996, 997))

model_white_nh <- svyglm(
  I((RACE == 1) & (HISPAN == 0)) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design,  # Uses acs_data_clean
  family = quasibinomial()
)

pred_white_nh <- predict(model_white_nh,
                         newdata = data.frame(AGE = 0:5, MULTYEAR = 2023),
                         type = "response")
```

**Estimand 2:** "Proportion of children identifying as Black, including those that listed more than one race and also Hispanic"

**Logic:** Any person with `RACE = 2` (Black), regardless of `HISPAN` value

**Calculation (GLM with defensive coding):**
```r
# Data already filtered in acs_data_clean for valid RACE codes

model_black <- svyglm(
  I(RACE == 2) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design,  # Uses acs_data_clean
  family = quasibinomial()
)

pred_black <- predict(model_black,
                      newdata = data.frame(AGE = 0:5, MULTYEAR = 2023),
                      type = "response")
```

**Estimand 3:** "Proportion of children identifying as Hispanic (any race)"

**Variable:** `HISPAN` (1-4 = Hispanic origins)
- ⚠️ DEFENSIVE: Must use `HISPAN >= 1 & HISPAN <= 4` (NOT `HISPAN >= 1`)
- This excludes HISPAN=9 (Not Reported), 498, 499 (Other)

**Calculation (GLM with defensive coding):**
```r
# Data already filtered in acs_data_clean for HISPAN %in% 0:4

model_hispanic <- svyglm(
  I(HISPAN >= 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,  # Safe because filtered to 0-4
  design = acs_design,  # Uses acs_data_clean
  family = quasibinomial()
)

pred_hispanic <- predict(model_hispanic,
                         newdata = data.frame(AGE = 0:5, MULTYEAR = 2023),
                         type = "response")
```

**Fills rows:** Age 0-5 (same value × 6 for each = 18 total rows)

---

#### 3. Federal Poverty Level (5 estimands)

**Variables:** `POVERTY` (income as percentage of poverty threshold, 1-501)
- Valid codes: 001-501 (1% or less to 501%+)
- ⚠️ EXCLUDE: 000 (N/A - not applicable)

**Estimands:**
1. "Proportion of children in household at 0-99% Federal Poverty Level"
2. "Proportion of children in households at 100-199% Federal Poverty Level"
3. "Proportion of children at household in 200-299% Federal Poverty Level"
4. "Proportion of children in household at 300-399% Federal Poverty Level"
5. "Proportion of children in household at 400+ % Federal Poverty Level"

**Calculation (Survey-Weighted Multinomial Logit with defensive coding):**
```r
# Data already filtered in acs_data_clean for POVERTY >= 1 & POVERTY <= 501

# Create FPL category variable
acs_data_fpl <- acs_data_clean %>%
  dplyr::mutate(
    fpl_category = dplyr::case_when(
      POVERTY < 100 ~ "0-99%",
      POVERTY < 200 ~ "100-199%",
      POVERTY < 300 ~ "200-299%",
      POVERTY < 400 ~ "300-399%",
      POVERTY >= 400 ~ "400%+",
      TRUE ~ NA_character_
    ),
    fpl_category = factor(fpl_category,
                          levels = c("0-99%", "100-199%", "200-299%", "300-399%", "400%+"))
  )

# Create survey design from FPL-specific data
acs_design_fpl <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_fpl
)

# Fit multinomial logit model with age × year interaction
library(nnet)
model_fpl <- survey::svymultinom(
  fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design_fpl,  # Uses clean data
  trace = FALSE
)

# Predict at 2023 for each age
pred_data <- data.frame(AGE = 0:5, MULTYEAR = 2023)
fpl_predictions <- predict(model_fpl, newdata = pred_data, type = "probs")
# Result: 6 rows (ages) × 5 columns (FPL categories)
```

**Validation:** Multinomial model guarantees proportions sum to 1.0 for each age

**Fills rows:** Age 0-5 (same value × 6 for each category = 30 total rows)

---

#### 4. PUMA Geography (14 estimands)

**Variable:** `PUMA` (Public Use Microdata Area code)

**Nebraska PUMAs:**
1. 3100100
2. 3100200
3. 3100300
4. 3100400
5. 3100500
6. 3100600
7. 3100701
8. 3100702
9. 3100801
10. 3100802
11. 3100901
12. 3100902
13. 3100903
14. 3100904

**Calculation (Survey-Weighted Multinomial Logit with defensive coding):**
```r
# Data already filtered in acs_data_clean (no special missing code checks needed for PUMA)
# Nebraska-specific PUMA codes should all be valid 7-digit codes

# Ensure PUMA is a factor with all 14 Nebraska categories
puma_list <- c(3100100, 3100200, 3100300, 3100400, 3100500, 3100600,
               3100701, 3100702, 3100801, 3100802, 3100901, 3100902, 3100903, 3100904)

acs_data_puma <- acs_data_clean %>%
  dplyr::mutate(
    puma_factor = factor(PUMA, levels = puma_list)
  )

# Create survey design
acs_design_puma <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_puma
)

# Fit multinomial logit model with age × year interaction
model_puma <- survey::svymultinom(
  puma_factor ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design_puma,  # Uses clean data
  trace = FALSE
)

# Predict at 2023 for each age
pred_data <- data.frame(AGE = 0:5, MULTYEAR = 2023)
puma_predictions <- predict(model_puma, newdata = pred_data, type = "probs")
# Result: 6 rows (ages) × 14 columns (PUMA categories)
```

**Validation:** Multinomial model guarantees proportions sum to 1.0 for each age

**Fills rows:** Age 0-5 (same value × 6 for each PUMA = 84 total rows)

---

#### 5. Mother's Education (1 estimand, AGE-STRATIFIED) ⚠️ NEW

**Estimand:** "Proportion of children whose mother has Bachelor's degree or higher"

**Variables:** `EDUC_MOM` (mother's education), `MOMLOC` (mother location in household)

**Mother Education Coding:**
- Valid: 2-998 (educational attainment levels)
- 0-6: Less than Bachelor's
- 7: High school graduate/GED
- 8: Some college, no degree
- 10: Bachelor's degree
- 11: Master's degree
- 12-13: Professional/Doctoral degree
- ⚠️ EXCLUDE: 999 (Missing), 001 (N/A)

**Definition:** Bachelor's or higher = `EDUC_MOM >= 10`

**Calculation (GLM with Temporal Trends and defensive coding):**
```r
# Filter to children with valid mother education data
acs_data_mom_educ <- acs_data_clean %>%
  dplyr::filter(
    MOMLOC > 0,                          # Mother in household
    !is.na(EDUC_MOM),                    # EDUC_MOM exists
    EDUC_MOM >= 2 & EDUC_MOM <= 998      # Valid education codes
  )

# Create survey design
acs_design_mom_educ <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_mom_educ
)

# Fit model
model_mom_educ <- svyglm(
  I(EDUC_MOM >= 10) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design_mom_educ,
  family = quasibinomial()
)

# Predict at 2023 for each age
pred_mom_educ <- predict(model_mom_educ,
                         newdata = data.frame(AGE = 0:5, MULTYEAR = 2023),
                         type = "response")
```

**Model Selection:**
```r
# Test interaction significance
model_main <- svyglm(
  I(EDUC_MOM >= 10) ~ AGE + MULTYEAR,
  design = acs_design_mom_educ,
  family = quasibinomial()
)

# Compare models
anova(model_main, model_mom_educ, test = "F")
# Use simpler model if p > 0.05
```

**Coverage:** 94.8% of children have mother linked in household (`MOMLOC > 0`)

**Expected Values (Nebraska):**
- Age 0: ~45.9%
- Age 1: ~45.8%
- Age 2: ~44.2%
- Age 3: ~47.4%
- Age 4: ~46.4%
- Age 5: ~45.9%

**Fills rows:** Age 0-5 (6 different values - varies by age)

**⚠️ Important Notes:**
1. **Age-varying:** Unlike other ACS variables, mother's education shows age variation (likely due to cohort effects)
2. **Missing data:** ~5% of children have no mother link - handle with `na.rm = TRUE`
3. **Critical for raking:** Mother's education is a key SES indicator and should be included in raking procedure

---

#### 6. Mother's Marital Status (1 estimand, AGE-STRATIFIED) ⚠️ NEW

**Estimand:** "Proportion of children whose mother is married"

**Variables:** `MARST_HEAD` (household head marital status), `MOMLOC` (mother location in household)

**Household Structure Context:**
- 47.3% of children: Mother IS household head (MOMLOC=1)
- 44.7% of children: Mother is spouse of head (MOMLOC=2)
- 5.2% of children: No mother in household (MOMLOC=0)
- 2.8% of children: Mother is other household member (MOMLOC>2)

**Derivation Logic:**
- **If MOMLOC=2:** Mother is spouse → she is married
- **If MOMLOC=1:** Mother is head → use MARST_HEAD to determine if married
- **Result:** `MARST_HEAD = 1` serves as proxy for "mother is married"

**MARST_HEAD Coding:**
- Valid: 1-6 (marital status categories)
- 1 = Married, spouse present ✓
- 2 = Married, spouse absent
- 3 = Separated
- 4 = Divorced
- 5 = Widowed
- 6 = Never married/single
- ⚠️ EXCLUDE: 9 (Blank, missing)

**Definition:** Mother married = `MARST_HEAD = 1` (married, spouse present)

**Calculation (GLM with Temporal Trends and defensive coding):**
```r
# Filter to children with valid mother marital status data
acs_data_mom_marst <- acs_data_clean %>%
  dplyr::filter(
    MOMLOC > 0,                          # Mother in household
    MARST_HEAD %in% 1:6                  # Valid marital status codes (exclude 9)
  )

# Create survey design
acs_design_mom_marst <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_mom_marst
)

# Fit model
model_mom_married <- svyglm(
  I(MARST_HEAD == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design_mom_marst,
  family = quasibinomial()
)

# Predict at 2023 for each age
pred_mom_married <- predict(model_mom_married,
                            newdata = data.frame(AGE = 0:5, MULTYEAR = 2023),
                            type = "response")
```

**Model Selection:**
```r
# Test interaction significance
model_main <- svyglm(
  I(MARST_HEAD == 1) ~ AGE + MULTYEAR,
  design = acs_design_mom_marst,
  family = quasibinomial()
)

# Compare models
anova(model_main, model_mom_married, test = "F")
# Use simpler model if p > 0.05
```

**Coverage:** 94.8% of children have mother in household (`MOMLOC > 0`)

**Expected Values (Nebraska):**
- Age 0: ~79.9%
- Age 1: ~82.7%
- Age 2: ~83.7%
- Age 3: ~84.0%
- Age 4: ~81.5%
- Age 5: ~79.3%

**Fills rows:** Age 0-5 (6 different values - varies by age)

**⚠️ Important Notes:**
1. **Proxy quality:** MARST_HEAD accurately reflects mother's marital status for 92% of children (MOMLOC=1 or 2)
2. **Age-varying:** Shows 4.7 percentage point range (79.3% to 84.0%) across ages
3. **Missing data:** ~5% of children have no mother link - exclude with `MOMLOC > 0` filter
4. **Alternative definition:** Could include cohabiting partners, but "married" alone is standard for raking

---

## Phase 2: NHIS Estimates (4 estimands)

### Data Source
- **Table:** `nhis_raw`
- **Total Sample:** 229,609 records (all ages, nationwide)
- **Filtered Sample:** 15,208 parent records linked to children ages 0-5
- **Weights:** `SAMPWEIGHT` (survey sampling weight)

### Critical Filtering: Linking Parents to Young Children

**Challenge:** NHIS parent records don't directly contain child's age. Requires household-based join.

**Solution - Two-Step Process:**

**Step 1:** Identify households with sample children ages 0-5
```sql
SELECT DISTINCT NHISHID, AGE as child_age
FROM nhis_raw
WHERE CSTATFLG = 1   -- Sample child flag
  AND AGE <= 5
```

**Step 2:** Join to parent records in those households
```sql
SELECT p.*, c.child_age
FROM nhis_raw p
INNER JOIN (
    SELECT DISTINCT NHISHID, AGE as child_age
    FROM nhis_raw
    WHERE CSTATFLG = 1 AND AGE <= 5
) c ON p.NHISHID = c.NHISHID
WHERE p.ISPARENTSC = 1  -- Is parent of sample child
  AND p.CSTATFLG = 0    -- Not the child record itself
```

### Validation: Available Sample Sizes

| Metric | Count |
|--------|-------|
| **Sample children ages 0-5** | 14,498 |
| **Households with children 0-5** | 11,964 |
| **Parent records (linked to children 0-5)** | 15,208 |
| **Parents in North Central region** | 3,476 (23%) |

**Data Availability by Year (Parents with Children 0-5):**

| Year | Parent Records | PHQ-8 Available | ACE Variables Available |
|------|---------------|-----------------|------------------------|
| 2019 | 2,200 | ✓ (100%) | ✓ (100%) |
| 2020 | 1,366 | ✗ | ✗ |
| 2021 | 1,962 | ✗ | ✓ (100%) |
| 2022 | 1,822 | ✓ (100%) | ✓ (100%) |
| 2023 | 1,873 | ✗ | ✓ (100%) |
| 2024 | 5,985 | ✗ | ✗ |

**Recommendation:**
- Use **2019 and 2022** for depression estimates (PHQ-8 available)
- Use **2019, 2021, 2022, 2023** for ACE estimates (combine years for larger sample)

### Estimation Method: Survey-Weighted Estimates for North Central Region

**Approach:** Filter to North Central region (REGION = 2) and compute survey-weighted estimates directly, without random effects.

**Rationale:**
- Nebraska is in North Central region (includes IA, KS, MN, MO, NE, ND, SD)
- Simple filtering provides direct regional estimates
- More transparent than modeling across all 4 regions
- NHIS doesn't identify states, so regional estimate is best available proxy

**Model specification:**
```r
library(survey)

# Filter to parents with children 0-5 in North Central region
nhis_parents_nc <- nhis_data %>%
  dplyr::inner_join(
    nhis_data %>%
      dplyr::filter(CSTATFLG == 1, AGE <= 5) %>%
      dplyr::select(NHISHID, child_age = AGE),
    by = "NHISHID"
  ) %>%
  dplyr::filter(ISPARENTSC == 1, CSTATFLG == 0, REGION == 2)

# Create survey design object for North Central region only
nhis_design_nc <- svydesign(
  ids = ~PSU,           # Primary sampling unit
  strata = ~STRATA,     # Stratification variable
  weights = ~SAMPWEIGHT,
  data = nhis_parents_nc,
  nest = TRUE
)

# Survey-weighted logistic regression (intercept-only model)
model <- svyglm(outcome ~ 1, design = nhis_design_nc, family = quasibinomial())

# Extract predicted probability
nc_estimate <- predict(model, type = "response")
```

### Estimands to Calculate

#### 1. Maternal Depression (1 estimand - PHQ-2)

**Estimand:**
- "Proportion of mothers with moderate/severe depressive symptoms (PHQ-2: 3-6)" [positive screen]

**Data Source:** NHIS 2019, 2022 (PHQ-2 items available, N=4,022 parents with children 0-5)

**Variables:**
- `PHQINTR`: Little interest or pleasure in doing things (0-3 scale)
- `PHQDEP`: Feeling down, depressed, or hopeless (0-3 scale)

**Rationale:** NE25 survey only includes PHQ-2 (2 items), not full PHQ-8. Raking targets must match the measure used in the target survey. Binary categorization uses standard PHQ-2 clinical cutpoint (≥3 = positive depression screen).

**Calculation (Survey-Weighted Binary Logistic Regression):**
```r
# Filter to parents with children 0-5, PHQ data (2019, 2022), and North Central region
nhis_phq_nc <- nhis_data %>%
  dplyr::inner_join(
    nhis_data %>%
      dplyr::filter(CSTATFLG == 1, AGE <= 5) %>%
      dplyr::select(NHISHID, child_age = AGE),
    by = "NHISHID"
  ) %>%
  dplyr::filter(ISPARENTSC == 1,
                CSTATFLG == 0,
                REGION == 2,
                YEAR %in% c(2019, 2022),
                !is.na(PHQINTR), !is.na(PHQDEP)) %>%
  dplyr::mutate(
    # Recode from 1-4 scale to 0-3 scale (1=Not at all → 0 points, 4=Nearly every day → 3 points)
    phq2_interest = dplyr::case_when(
      PHQINTR == 1 ~ 0,
      PHQINTR == 2 ~ 1,
      PHQINTR == 3 ~ 2,
      PHQINTR == 4 ~ 3,
      TRUE ~ NA_real_
    ),
    phq2_depressed = dplyr::case_when(
      PHQDEP == 1 ~ 0,
      PHQDEP == 2 ~ 1,
      PHQDEP == 3 ~ 2,
      PHQDEP == 4 ~ 3,
      TRUE ~ NA_real_
    ),
    # PHQ-2 total (0-6)
    phq2_total = phq2_interest + phq2_depressed,
    # PHQ-2 positive screen (≥3)
    phq2_positive = (phq2_total >= 3)
  )

# Create survey design
nhis_phq_design <- svydesign(
  ids = ~PSU, strata = ~STRATA, weights = ~SAMPWEIGHT,
  data = nhis_phq_nc, nest = TRUE
)

# Fit survey-weighted logistic regression
model_phq2 <- svyglm(phq2_positive ~ 1,
                     design = nhis_phq_design,
                     family = quasibinomial())

# Extract probability
prop_phq2_positive <- predict(model_phq2, type = "response")[1]
```

**Fills rows:** Age 0-5 (same value × 6)

---

#### 3. Maternal ACE Exposure (3 estimands)

**Estimands:**
- "Proportion of mothers exposed to zero adverse childhood experiences"
- "Proportion of mothers exposed to one adverse childhood experience"
- "Proportion of mothers exposed to 2 or more adverse childhood experiences"

**Data Source:** NHIS 2019, 2021, 2022, 2023 (ACE variables available, N=7,657 parents with children 0-5)

**Variables (8 ACE items):**
- `VIOLENEV`: Lived with violent person
- `JAILEV`: Lived with incarcerated person
- `MENTDEPEV`: Lived with mentally ill person
- `ALCDRUGEV`: Lived with substance user
- `ADLTPUTDOWN`: Physical abuse
- `UNFAIRRACE`: Discrimination (race)
- `UNFAIRSEXOR`: Discrimination (sex/orientation)
- `BASENEED`: Couldn't afford basic needs

**Calculation (Survey-Weighted Multinomial Logit):**
```r
# Filter to parents with children 0-5, ACE data (2019, 2021-2023), and North Central region
nhis_ace_nc <- nhis_data %>%
  dplyr::inner_join(
    nhis_data %>%
      dplyr::filter(CSTATFLG == 1, AGE <= 5) %>%
      dplyr::select(NHISHID, child_age = AGE),
    by = "NHISHID"
  ) %>%
  dplyr::filter(ISPARENTSC == 1,
                CSTATFLG == 0,
                REGION == 2,
                YEAR %in% c(2019, 2021, 2022, 2023)) %>%
  dplyr::mutate(
    ace_total = rowSums(dplyr::select(., VIOLENEV, JAILEV, MENTDEPEV, ALCDRUGEV,
                                      ADLTPUTDOWN, UNFAIRRACE, UNFAIRSEXOR, BASENEED) == 1,
                        na.rm = FALSE),
    ace_category = dplyr::case_when(
      ace_total == 0 ~ "0_ACEs",
      ace_total == 1 ~ "1_ACE",
      ace_total >= 2 ~ "2plus_ACEs",
      TRUE ~ NA_character_
    ),
    ace_category = factor(ace_category, levels = c("0_ACEs", "1_ACE", "2plus_ACEs"))
  )

# Create survey design for North Central region
nhis_ace_design <- svydesign(
  ids = ~PSU, strata = ~STRATA, weights = ~SAMPWEIGHT,
  data = nhis_ace_nc, nest = TRUE
)

# Fit survey-weighted multinomial logit
library(nnet)
model_ace <- survey::svymultinom(
  ace_category ~ 1,
  design = nhis_ace_design,
  trace = FALSE
)

# Predict probabilities (intercept-only model gives marginal proportions)
ace_predictions <- predict(model_ace, type = "probs")[1,]
# Result: Named vector with probabilities for 0_ACEs, 1_ACE, 2plus_ACEs (sum to 1.0)
```

**Validation:** Multinomial model guarantees proportions sum to 1.0

**Fills rows:** Age 0-5 (same value × 6 for each category = 18 total rows)

---

## Phase 3: NSCH Estimates (4 estimands)

### Data Source
- **Table:** `nsch_2023_raw`
- **Sample:** 21,524 Nebraska children ages 0-5
- **Weights:** Survey weights (variable name TBD - likely `FWC` or similar)
- **Filter:** `FIPSST = 31` (Nebraska) AND `SC_AGE_YEARS` in 0-5

### Estimation Method: Age-Stratified Mixed Models

**Model specification:**
```r
# Separate model for each age
for(age in 0:5) {
  age_data <- nsch_data %>% filter(SC_AGE_YEARS == age)

  # Fit state-level mixed model
  model <- glmer(outcome ~ 1 + (1|FIPSST),
                 data = age_data,
                 family = binomial,
                 weights = survey_weight)

  # Predict for Nebraska (FIPSST = 31)
  estimates[age + 1] <- predict(model,
                                newdata = data.frame(FIPSST = 31),
                                type = "response")
}
```

**Result:** 6 different estimates (one per age 0-5)

### Estimands to Calculate

#### 1. Child ACE Exposure (1 estimand)
**Estimand:** "Child Exposure to at least one adverse childhood experience"

**Variable:** `ACE1more_23` or calculate from raw ACE items

**Calculation:**
```r
# Option 1: Use derived variable
nsch_ne <- nsch_2023_raw %>%
  filter(FIPSST == 31, SC_AGE_YEARS <= 5)

ace_estimates <- sapply(0:5, function(age) {
  age_data <- nsch_ne %>% filter(SC_AGE_YEARS == age)

  model <- glmer(ACE1more_23 ~ 1 + (1|FIPSST),
                 data = age_data,
                 family = binomial)

  predict(model, newdata = data.frame(FIPSST = 31), type = "response")
})
```

**Fills rows:** Age 0-5 (6 different values)

---

#### 2. Emotional/Developmental/Behavioral Problem (1 estimand)
**Estimand:** "Child has emotional, developmental, or behavioral problem for which he or she needs treatment or counseling"

**Variable:** `MEDB10ScrQ5_23`

**Note:** This variable is for ages 3-17. For ages 0-2, estimate may be NA or use alternative indicator.

**Calculation:**
```r
medb_estimates <- sapply(0:5, function(age) {
  age_data <- nsch_ne %>% filter(SC_AGE_YEARS == age)

  if(age < 3) {
    # Use alternative developmental screening variable for ages 0-2
    # Or return NA
    return(NA)
  }

  model <- glmer(MEDB10ScrQ5_23 ~ 1 + (1|FIPSST),
                 data = age_data,
                 family = binomial)

  predict(model, newdata = data.frame(FIPSST = 31), type = "response")
})
```

**Fills rows:** Age 0-5 (6 values, may be NA for ages 0-2)

---

#### 3. Health Excellent (1 estimand)
**Estimand:** "Describes child's health as excellent"

**Variable:** `K2Q01` (General Health)
- 1 = Excellent
- 2 = Very good
- 3 = Good
- 4 = Fair
- 5 = Poor

**Calculation:**
```r
health_estimates <- sapply(0:5, function(age) {
  age_data <- nsch_ne %>% filter(SC_AGE_YEARS == age)

  model <- glmer(I(K2Q01 == 1) ~ 1 + (1|FIPSST),
                 data = age_data,
                 family = binomial)

  predict(model, newdata = data.frame(FIPSST = 31), type = "response")
})
```

**Fills rows:** Age 0-5 (6 different values)

---

#### 4. Childcare 10+ Hours/Week (1 estimand)
**Estimand:** "Receives child care for at least 10 hours per week from someone other than a parent or guardian"

**Variable:** `Care10hrs_23` (Indicator 6.21)

**Note:** This is specifically for ages 0-5 (matches our target population exactly)

**Calculation:**
```r
care_estimates <- sapply(0:5, function(age) {
  age_data <- nsch_ne %>% filter(SC_AGE_YEARS == age)

  model <- glmer(Care10hrs_23 ~ 1 + (1|FIPSST),
                 data = age_data,
                 family = binomial)

  predict(model, newdata = data.frame(FIPSST = 31), type = "response")
})
```

**Fills rows:** Age 0-5 (6 different values)

---

## Phase 4: Implementation Steps

### Step 1: Create R Script for ACS Estimates
**File:** `scripts/raking/estimate_acs_targets.R`

```r
library(dplyr)
library(survey)
library(DBI)
library(duckdb)

# Load ACS data
conn <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")
acs_data_raw <- dbGetQuery(conn, "
  SELECT * FROM acs_data
  WHERE state = 'nebraska'
  AND AGE BETWEEN 0 AND 5
")

# DEFENSIVE CODING: Filter out missing data codes
acs_data_clean <- acs_data_raw %>%
  dplyr::filter(
    # Core demographics - exclude missing codes
    SEX %in% c(1, 2),                                    # Valid sex codes
    HISPAN %in% 0:4,                                     # Valid Hispanic codes (exclude 9, 498-499)
    RACE %in% 1:9,                                       # Valid race codes
    !(RACE %in% c(363, 380, 996, 997)),                 # Exclude special missing race codes
    POVERTY >= 1 & POVERTY <= 501                        # Valid poverty ratio (exclude 000)
  )

cat(sprintf("[OK] Filtered ACS data: %d -> %d records\n",
            nrow(acs_data_raw), nrow(acs_data_clean)))

# Create survey design object from clean data
acs_design <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_clean
)

# Helper function to fit GLM and extract predictions
fit_glm_estimates <- function(formula, design, ages = 0:5, year = 2023) {
  # Fit model with interaction
  model_full <- svyglm(formula, design = design, family = quasibinomial())

  # Test if interaction is significant
  formula_main <- update(formula, . ~ . - AGE:MULTYEAR)
  model_main <- svyglm(formula_main, design = design, family = quasibinomial())

  anova_result <- anova(model_main, model_full, test = "F")
  use_interaction <- (anova_result[2, "Pr(>F)"] < 0.05)

  # Use appropriate model
  final_model <- if(use_interaction) model_full else model_main

  # Predict at most recent year
  pred_data <- data.frame(AGE = ages, MULTYEAR = year)
  predictions <- predict(final_model, newdata = pred_data, type = "response")

  return(list(
    estimates = predictions,
    model = final_model,
    interaction_significant = use_interaction
  ))
}

# Fit all models
results <- list(
  # Sex
  sex_male = fit_glm_estimates(
    I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design
  ),

  # Race/ethnicity
  race_white_nh = fit_glm_estimates(
    I((RACE == 1) & (HISPAN == 0)) ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design
  ),
  race_black = fit_glm_estimates(
    I(RACE == 2) ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design
  ),
  race_hispanic = fit_glm_estimates(
    I(HISPAN >= 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design
  )
)

# FPL categories - multinomial logit model (data already filtered)
acs_data_fpl <- acs_data_clean %>%
  dplyr::mutate(
    fpl_category = dplyr::case_when(
      POVERTY < 100 ~ "0-99%",
      POVERTY < 200 ~ "100-199%",
      POVERTY < 300 ~ "200-299%",
      POVERTY < 400 ~ "300-399%",
      POVERTY >= 400 ~ "400%+",
      TRUE ~ NA_character_
    ),
    fpl_category = factor(fpl_category,
                          levels = c("0-99%", "100-199%", "200-299%", "300-399%", "400%+"))
  )

acs_design_fpl <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_fpl
)

model_fpl <- survey::svymultinom(
  fpl_category ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design_fpl,
  trace = FALSE
)

pred_data <- data.frame(AGE = 0:5, MULTYEAR = 2023)
fpl_predictions <- predict(model_fpl, newdata = pred_data, type = "probs")

# PUMA geography - multinomial logit model (data already filtered)
puma_list <- c(3100100, 3100200, 3100300, 3100400, 3100500, 3100600,
               3100701, 3100702, 3100801, 3100802, 3100901, 3100902, 3100903, 3100904)

acs_data_puma <- acs_data_clean %>%
  dplyr::mutate(puma_factor = factor(PUMA, levels = puma_list))

acs_design_puma <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_puma
)

model_puma <- survey::svymultinom(
  puma_factor ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design_puma,
  trace = FALSE
)

puma_predictions <- predict(model_puma, newdata = pred_data, type = "probs")

# Mother variables - need additional filtering for EDUC and MARST
acs_data_mom_educ <- acs_data_clean %>%
  dplyr::filter(
    MOMLOC > 0,                          # Mother in household
    !is.na(EDUC_MOM),                    # EDUC_MOM exists
    EDUC_MOM >= 2 & EDUC_MOM <= 998      # Valid education codes (exclude 999, 001)
  )

acs_design_mom_educ <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_mom_educ
)

acs_data_mom_marst <- acs_data_clean %>%
  dplyr::filter(
    MOMLOC > 0,                          # Mother in household
    MARST_HEAD %in% 1:6                  # Valid marital status codes (exclude 9)
  )

acs_design_mom_marst <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data_mom_marst
)

# Binary GLMs for mother variables
results_binary <- list(
  # Mother's education (Bachelor's+)
  mom_educ_bachelors = fit_glm_estimates(
    I(EDUC_MOM >= 10) ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design_mom_educ
  ),

  # Mother's marital status (married)
  mom_married = fit_glm_estimates(
    I(MARST_HEAD == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = acs_design_mom_marst
  )
)

# Extract estimates from binary models
acs_estimates_binary <- lapply(results_binary, function(x) x$estimates)

# Combine all estimates
acs_estimates <- c(
  acs_estimates_binary,
  list(
    fpl_0_99 = fpl_predictions[, "0-99%"],
    fpl_100_199 = fpl_predictions[, "100-199%"],
    fpl_200_299 = fpl_predictions[, "200-299%"],
    fpl_300_399 = fpl_predictions[, "300-399%"],
    fpl_400_plus = fpl_predictions[, "400%+"],
    puma_3100100 = puma_predictions[, "3100100"],
    puma_3100200 = puma_predictions[, "3100200"],
    puma_3100300 = puma_predictions[, "3100300"],
    puma_3100400 = puma_predictions[, "3100400"],
    puma_3100500 = puma_predictions[, "3100500"],
    puma_3100600 = puma_predictions[, "3100600"],
    puma_3100701 = puma_predictions[, "3100701"],
    puma_3100702 = puma_predictions[, "3100702"],
    puma_3100801 = puma_predictions[, "3100801"],
    puma_3100802 = puma_predictions[, "3100802"],
    puma_3100901 = puma_predictions[, "3100901"],
    puma_3100902 = puma_predictions[, "3100902"],
    puma_3100903 = puma_predictions[, "3100903"],
    puma_3100904 = puma_predictions[, "3100904"]
  )
)

# Save results
saveRDS(list(
  estimates = acs_estimates,
  binary_models = lapply(results_binary, function(x) x$model),
  multinomial_models = list(fpl = model_fpl, puma = model_puma),
  interaction_tests = lapply(results_binary, function(x) x$interaction_significant)
), "scripts/raking/acs_estimates.rds")

# Print summary
cat("ACS Estimation Summary:\n")
cat("======================\n")
cat("\nBinary GLM models (with age x year interaction tests):\n")
for(name in names(results_binary)) {
  cat(sprintf("  %s: Interaction %s\n",
              name,
              ifelse(results_binary[[name]]$interaction_significant, "significant", "not significant")))
}
cat("\nMultinomial logit models:\n")
cat("  FPL (5 categories): Age x year interaction included\n")
cat("  PUMA (14 categories): Age x year interaction included\n")
cat(sprintf("\nTotal estimands: %d (4 binary + 5 FPL + 14 PUMA + 2 mother vars = 25)\n", length(acs_estimates)))
```

---

### Step 2: Create R Script for NHIS Estimates
**File:** `scripts/raking/estimate_nhis_targets.R`

```r
library(dplyr)
library(survey)
library(nnet)
library(DBI)
library(duckdb)

# Load NHIS data
conn <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")
nhis_data <- dbGetQuery(conn, "SELECT * FROM nhis_raw")

# CRITICAL: Filter to parents with children ages 0-5 in North Central region
nhis_parents_nc <- nhis_data %>%
  dplyr::inner_join(
    nhis_data %>%
      dplyr::filter(CSTATFLG == 1, AGE <= 5) %>%
      dplyr::select(NHISHID, child_age = AGE),
    by = "NHISHID"
  ) %>%
  dplyr::filter(ISPARENTSC == 1, CSTATFLG == 0, REGION == 2)

# Depression estimates (2019, 2022; North Central region) - PHQ-2 binary
nhis_phq_nc <- nhis_parents_nc %>%
  dplyr::filter(YEAR %in% c(2019, 2022), !is.na(PHQINTR), !is.na(PHQDEP)) %>%
  dplyr::mutate(
    # Recode from 1-4 to 0-3 scale
    phq2_interest = dplyr::case_when(
      PHQINTR == 1 ~ 0, PHQINTR == 2 ~ 1, PHQINTR == 3 ~ 2, PHQINTR == 4 ~ 3,
      TRUE ~ NA_real_
    ),
    phq2_depressed = dplyr::case_when(
      PHQDEP == 1 ~ 0, PHQDEP == 2 ~ 1, PHQDEP == 3 ~ 2, PHQDEP == 4 ~ 3,
      TRUE ~ NA_real_
    ),
    phq2_total = phq2_interest + phq2_depressed,
    phq2_positive = (phq2_total >= 3)
  )

nhis_phq_design <- svydesign(
  ids = ~PSU, strata = ~STRATA, weights = ~SAMPWEIGHT,
  data = nhis_phq_nc, nest = TRUE
)

model_phq2 <- svyglm(phq2_positive ~ 1, design = nhis_phq_design, family = quasibinomial())

# ACE estimates (2019, 2021-2023; North Central region) - multinomial logit
nhis_ace_nc <- nhis_parents_nc %>%
  dplyr::filter(YEAR %in% c(2019, 2021, 2022, 2023)) %>%
  dplyr::mutate(
    ace_total = rowSums(dplyr::select(., VIOLENEV, JAILEV, MENTDEPEV, ALCDRUGEV,
                                      ADLTPUTDOWN, UNFAIRRACE, UNFAIRSEXOR, BASENEED) == 1,
                        na.rm = FALSE),
    ace_category = dplyr::case_when(
      ace_total == 0 ~ "0_ACEs",
      ace_total == 1 ~ "1_ACE",
      ace_total >= 2 ~ "2plus_ACEs",
      TRUE ~ NA_character_
    ),
    ace_category = factor(ace_category, levels = c("0_ACEs", "1_ACE", "2plus_ACEs"))
  )

nhis_ace_design <- svydesign(
  ids = ~PSU, strata = ~STRATA, weights = ~SAMPWEIGHT,
  data = nhis_ace_nc, nest = TRUE
)

model_ace <- survey::svymultinom(
  ace_category ~ 1,
  design = nhis_ace_design,
  trace = FALSE
)

# Extract predictions (intercept-only models give marginal proportions)
ace_predictions <- predict(model_ace, type = "probs")[1,]

nhis_estimates <- list(
  prop_phq2_positive = predict(model_phq2, type = "response")[1],
  prop_ace_0 = ace_predictions["0_ACEs"],
  prop_ace_1 = ace_predictions["1_ACE"],
  prop_ace_2plus = ace_predictions["2plus_ACEs"]
)

saveRDS(nhis_estimates, "scripts/raking/nhis_estimates.rds")
```

---

### Step 3: Create R Script for NSCH Estimates
**File:** `scripts/raking/estimate_nsch_targets.R`

```r
library(dplyr)
library(lme4)
library(DBI)
library(duckdb)

# Load NSCH 2023 data
conn <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")
nsch_data <- dbGetQuery(conn, "
  SELECT * FROM nsch_2023_raw
  WHERE FIPSST = 31
  AND SC_AGE_YEARS <= 5
")

# Age-stratified estimates (0-5)
nsch_estimates <- list(
  ace_by_age = sapply(0:5, function(age) { ... }),
  medb_by_age = sapply(0:5, function(age) { ... }),
  health_excellent_by_age = sapply(0:5, function(age) { ... }),
  care10hrs_by_age = sapply(0:5, function(age) { ... })
)

saveRDS(nsch_estimates, "scripts/raking/nsch_estimates.rds")
```

---

### Step 4: Create Python Script to Fill CSV
**File:** `scripts/raking/fill_raking_targets.py`

```python
import pandas as pd
import json

# Load original CSV
raking_targets = pd.read_csv("C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Desktop/raking_targets.csv")

# Load estimates from R
acs_estimates = # Read from RDS
nhis_estimates = # Read from RDS
nsch_estimates = # Read from RDS

# Fill est column by matching:
# - age_years
# - estimand (text description)
# - dataset

for idx, row in raking_targets.iterrows():
    age = row['age_years (floor)']
    estimand = row['estimand']
    dataset = row['dataset']

    if 'ACS' in dataset:
        # Match to ACS estimate (same for all ages)
        est_value = # lookup in acs_estimates
    elif 'NHIS' in dataset:
        # Match to NHIS estimate (same for all ages)
        est_value = # lookup in nhis_estimates
    elif 'NSCH' in dataset:
        # Match to NSCH estimate (varies by age)
        est_value = # lookup in nsch_estimates[age]

    raking_targets.at[idx, 'est'] = est_value

# Save updated CSV
raking_targets.to_csv("C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Desktop/raking_targets_filled.csv", index=False)
```

---

## Phase 5: Validation

### Validation Checks

1. **Completeness:** All 210 rows have non-missing `est` values
2. **Range:** All estimates are between 0 and 1
3. **Consistency within categories:**
   - ACS: 5 FPL categories sum to 1.0 (guaranteed by multinomial model)
   - ACS: 14 PUMA categories sum to 1.0 (guaranteed by multinomial model)
   - NHIS: 3 maternal ACE categories sum to 1.0 (guaranteed by multinomial model)
4. **Age patterns:**
   - ACS/NHIS estimates identical across ages 0-5
   - NSCH estimates vary by age
5. **Face validity:** Estimates align with known Nebraska demographics

**Validation Script:** `scripts/raking/validate_targets.R`

```r
targets <- read.csv("raking_targets_filled.csv")

# Check completeness
stopifnot(all(!is.na(targets$est)))

# Check range
stopifnot(all(targets$est >= 0 & targets$est <= 1))

# Check FPL sums
fpl_check <- targets %>%
  filter(grepl("Federal Poverty", estimand)) %>%
  group_by(age_years) %>%
  summarise(total = sum(est))
stopifnot(all(abs(fpl_check$total - 1.0) < 0.01))

# Check PUMA sums
puma_check <- targets %>%
  dplyr::filter(grepl("Public-Use Micro Area", estimand)) %>%
  dplyr::group_by(age_years) %>%
  dplyr::summarise(total = sum(est))
stopifnot(all(abs(puma_check$total - 1.0) < 0.01))

# Check maternal ACE sums
ace_check <- targets %>%
  dplyr::filter(grepl("adverse childhood experience", estimand) & dataset == "NHIS") %>%
  dplyr::group_by(age_years) %>%
  dplyr::summarise(total = sum(est))
stopifnot(all(abs(ace_check$total - 1.0) < 0.01))

# Check ACS consistency across ages
acs_check <- targets %>%
  dplyr::filter(dataset == "ACS NE 5-year") %>%
  dplyr::group_by(estimand) %>%
  dplyr::summarise(unique_values = n_distinct(est))
stopifnot(all(acs_check$unique_values == 1))

cat("✓ All validation checks passed!\n")
```

---

## Summary

### Estimands by Source

| Source | Estimands | Age Variation | Total Rows |
|--------|-----------|---------------|------------|
| ACS | 26 (sex, race, FPL, PUMA, **mother education, mother marital status**) | 24 constant + **2 vary** | 24 × 6 + 12 = **156** |
| NHIS | 4 (**PHQ-2 positive 1**, **ACE 3**) | Constant | 4 × 6 = **24** |
| NSCH | 4 (child ACE, behavioral, health, childcare) | Varies | 4 × 6 = 24 |
| **Total** | **34** | - | **204** |

**⚠️ Note:** Original raking_targets.csv has only 186 rows (31 estimands). Need to add:
- Mother's education (6 rows)
- Mother's marital status (6 rows)
- Maternal ACE - 0 ACEs (6 rows, **new category**)
Total new rows: 18

### Key Considerations

1. **⚠️ CRITICAL: NHIS Parent-Child Linkage (Problem Solved)**
   - **Issue:** Parent records don't directly contain child's age - required household-based join
   - **Solution:** Two-step filtering using `NHISHID` household identifier
   - **Impact:** Reduced from 229,609 total records to 15,208 parents with children 0-5
   - **Sample Sizes:**
     - Depression (2019, 2022): 4,022 parents
     - ACE (2019, 2021-2023): 7,657 parents
     - North Central region: 3,476 parents (23% of sample)
   - **Implementation:** Must use household join (see Phase 2 for SQL code)

2. **Missing NHIS State Identifiers:** NHIS only provides census region, not individual states. North Central region (includes Nebraska) used as proxy.

3. **NSCH Age Restrictions:** Some variables (e.g., `MEDB10ScrQ5_23`) only apply to ages 3-17. For ages 0-2, may need alternative indicators or NA values.

4. **Survey Weights:**
   - ACS: `PERWT` (person weight)
   - NHIS: `SAMPWEIGHT` (sampling weight)
   - NSCH: Identify appropriate survey weight variable

5. **Mixed Model Complexity:** NHIS/NSCH mixed models may require adjustment for:
   - Convergence issues
   - Small sample sizes within age bins
   - Survey design features (strata, PSU)

### Next Steps

1. ✓ Create detailed documentation (this file)
2. ☐ **Add new rows to raking_targets.csv** (18 new rows total):
   - **Mother's education** (6 rows, ages 0-5):
     - Estimand: "Proportion of children whose mother has Bachelor's degree or higher"
     - Dataset: "ACS NE 5-year", Estimator: "Multinomial/GLM"
   - **Mother's marital status** (6 rows, ages 0-5):
     - Estimand: "Proportion of children whose mother is married"
     - Dataset: "ACS NE 5-year", Estimator: "Multinomial/GLM"
   - **Maternal ACE - 0 ACEs** (6 rows, ages 0-5):
     - Estimand: "Proportion of mothers exposed to zero adverse childhood experiences"
     - Dataset: "NHIS", Estimator: "Multinomial GLMM"
   - **New total:** 210 rows (was 186)
3. ☐ Implement ACS estimation script (26 estimands: multinomial for FPL/PUMA, GLM for others)
4. ☐ Implement NHIS estimation script (4 estimands: 1 PHQ-2 binary, 3 ACE multinomial)
5. ☐ Implement NSCH estimation script (4 estimands)
6. ☐ Create CSV filling script (handles 204 total rows)
7. ☐ Run validation checks
8. ☐ Review estimates with subject matter experts
9. ☐ Finalize raking targets for use in post-stratification

---

**Contact:** Kidsights Data Platform Team
**Documentation:** `docs/raking/RAKING_TARGETS_ESTIMATION_PLAN.md`

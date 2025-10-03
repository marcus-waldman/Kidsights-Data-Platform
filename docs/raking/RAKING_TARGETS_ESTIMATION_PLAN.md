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

**Model Specification:**
```r
library(survey)

# Create survey design object
acs_design <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data
)

# Fit weighted logistic regression
model <- svyglm(
  outcome ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design,
  family = quasibinomial()
)

# Predict at MULTYEAR=2023 (most recent year) for each age
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

**Calculation (GLM):**
```r
# Fit model
model_sex <- svyglm(
  I(SEX == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = acs_design,
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
- `HISPAN = 0` (Not Hispanic)
- `RACE = 1` (White)

**Calculation:**
```r
from python.acs.harmonization import harmonize_race_ethnicity

# Harmonize race/ethnicity
acs_data['ne25_race'] = harmonize_race_ethnicity(acs_data, 'RACE', 'HISPAN')

# Calculate proportion white non-Hispanic
white_nh = (acs_data['ne25_race'] == 'White') & (acs_data['HISPAN'] == 0)
prop_white_nh = np.average(white_nh, weights=acs_data['PERWT'])
```

**Estimand 2:** "Proportion of children identifying as Black, including those that listed more than one race and also Hispanic"

**Logic:** Any person with `RACE = 2` (Black), regardless of `HISPAN` value

**Calculation:**
```r
black_any = acs_data['RACE'] == 2
prop_black = np.average(black_any, weights=acs_data['PERWT'])
```

**Estimand 3:** "Proportion of children identifying as Hispanic (any race)"

**Variable:** `HISPAN ≥ 1` (any Hispanic origin)

**Calculation:**
```r
hispanic_any = acs_data['HISPAN'] >= 1
prop_hispanic = np.average(hispanic_any, weights=acs_data['PERWT'])
```

**Fills rows:** Age 0-5 (same value × 6 for each)

---

#### 3. Federal Poverty Level (5 estimands)

**Variables:** `POVERTY` (income as percentage of poverty threshold, 0-500)

**Estimands:**
1. "Proportion of children in household at 0-99% Federal Poverty Level"
2. "Proportion of children in households at 100-199% Federal Poverty Level"
3. "Proportion of children at household in 200-299% Federal Poverty Level"
4. "Proportion of children in household at 300-399% Federal Poverty Level"
5. "Proportion of children in household at 400+ % Federal Poverty Level"

**Calculation:**
```r
# Filter valid poverty values (exclude missing: 996-998)
acs_valid <- acs_data[acs_data$POVERTY < 600, ]

# Calculate proportions
fpl_0_99 <- np.average(acs_valid['POVERTY'] < 100, weights=acs_valid['PERWT'])
fpl_100_199 <- np.average((acs_valid['POVERTY'] >= 100) & (acs_valid['POVERTY'] < 200), weights=acs_valid['PERWT'])
fpl_200_299 <- np.average((acs_valid['POVERTY'] >= 200) & (acs_valid['POVERTY'] < 300), weights=acs_valid['PERWT'])
fpl_300_399 <- np.average((acs_valid['POVERTY'] >= 300) & (acs_valid['POVERTY'] < 400), weights=acs_valid['PERWT'])
fpl_400_plus <- np.average(acs_valid['POVERTY'] >= 400, weights=acs_valid['PERWT'])
```

**Validation:** Sum of 5 proportions should = 1.0

**Fills rows:** Age 0-5 (same value × 6 for each)

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

**Calculation:**
```r
# For each PUMA
puma_list <- c(3100100, 3100200, 3100300, 3100400, 3100500, 3100600,
               3100701, 3100702, 3100801, 3100802, 3100901, 3100902, 3100903, 3100914)

puma_props <- sapply(puma_list, function(p) {
  np.average(acs_data['PUMA'] == p, weights=acs_data['PERWT'])
})
```

**Validation:** Sum of 14 proportions should = 1.0

**Fills rows:** Age 0-5 (same value × 6 for each)

---

#### 5. Mother's Education (1 estimand, AGE-STRATIFIED) ⚠️ NEW

**Estimand:** "Proportion of children whose mother has Bachelor's degree or higher"

**Variables:** `EDUC_MOM` (mother's education), `MOMLOC` (mother location in household)

**Mother Education Coding:**
- 0-6: Less than Bachelor's
- 7: High school graduate/GED
- 8: Some college, no degree
- 10: Bachelor's degree
- 11: Master's degree
- 12-13: Professional/Doctoral degree

**Definition:** Bachelor's or higher = `EDUC_MOM >= 10`

**Calculation (GLM with Temporal Trends):**
```r
# Fit model (exclude missing mother links)
model_mom_educ <- svyglm(
  I(EDUC_MOM >= 10) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = subset(acs_design, !is.na(EDUC_MOM) & MOMLOC > 0),
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
  design = subset(acs_design, !is.na(EDUC_MOM) & MOMLOC > 0),
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
- 1 = Married, spouse present ✓
- 2 = Married, spouse absent
- 3 = Separated
- 4 = Divorced
- 5 = Widowed
- 6 = Never married/single

**Definition:** Mother married = `MARST_HEAD = 1` (married, spouse present)

**Calculation (GLM with Temporal Trends):**
```r
# Fit model (exclude children with no mother link)
model_mom_married <- svyglm(
  I(MARST_HEAD == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
  design = subset(acs_design, MOMLOC > 0),
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
  design = subset(acs_design, MOMLOC > 0),
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

### Estimation Method: Mixed Models with Regional Random Effects

**Model specification:**
```r
library(lme4)

# Filter to parents with children 0-5
nhis_parents_young <- nhis_data %>%
  inner_join(
    nhis_data %>%
      filter(CSTATFLG == 1, AGE <= 5) %>%
      select(NHISHID, child_age = AGE),
    by = "NHISHID"
  ) %>%
  filter(ISPARENTSC == 1, CSTATFLG == 0)

# Logistic mixed model with regional random intercept
model <- glmer(outcome ~ 1 + (1|REGION),
               data = nhis_parents_young,
               family = binomial,
               weights = SAMPWEIGHT)

# Extract Nebraska prediction (REGION = 2, North Central)
nebraska_pred <- predict(model, newdata = data.frame(REGION = 2), type = "response")
```

**Note:** NHIS doesn't identify individual states, only census regions. Nebraska is in Region 2 (North Central). Regional estimate serves as proxy for Nebraska.

### Estimands to Calculate

#### 1. Depression - No Symptoms (1 estimand)
**Estimand:** "Proportion of mothers describing no depressive symptoms"

**Data Source:** NHIS 2019, 2022 (PHQ-8 available, N=4,022 parents with children 0-5)

**Variables:**
- `PHQCAT`: PHQ-8 severity category
  - 1 = None/minimal (0-4)
  - 2 = Mild (5-9)
  - 3 = Moderate (10-14)
  - 4 = Moderately severe/severe (15+)

**Calculation:**
```r
# Filter to parents with children 0-5 and PHQ data (2019, 2022)
nhis_phq <- nhis_data %>%
  inner_join(
    nhis_data %>%
      filter(CSTATFLG == 1, AGE <= 5) %>%
      select(NHISHID, child_age = AGE),
    by = "NHISHID"
  ) %>%
  filter(ISPARENTSC == 1,
         CSTATFLG == 0,
         YEAR %in% c(2019, 2022),
         !is.na(PHQCAT))

# Fit mixed model (n=4,022)
model_phq_none <- glmer(I(PHQCAT == 1) ~ 1 + (1|REGION),
                        data = nhis_phq,
                        family = binomial,
                        weights = SAMPWEIGHT)

# Predict for North Central region
prop_no_depression <- predict(model_phq_none,
                               newdata = data.frame(REGION = 2),
                               type = "response")
```

**Fills rows:** Age 0-5 (same value × 6)

---

#### 2. Depression - Severe Symptoms (1 estimand)
**Estimand:** "Proportion of mothers describing severe depressive symptoms"

**Variable:** `PHQCAT = 4` (moderately severe/severe)

**Calculation:**
```r
# Use same filtered dataset (nhis_phq from above)
model_phq_severe <- glmer(I(PHQCAT == 4) ~ 1 + (1|REGION),
                          data = nhis_phq,
                          family = binomial,
                          weights = SAMPWEIGHT)

prop_severe_depression <- predict(model_phq_severe,
                                   newdata = data.frame(REGION = 2),
                                   type = "response")
```

**Fills rows:** Age 0-5 (same value × 6)

---

#### 3. ACE Exposure - 1 ACE (1 estimand)
**Estimand:** "Proportion of mothers exposed to one adverse childhood experience"

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

**Calculation:**
```r
# Filter to parents with children 0-5 and ACE data (2019, 2021-2023)
nhis_ace <- nhis_data %>%
  inner_join(
    nhis_data %>%
      filter(CSTATFLG == 1, AGE <= 5) %>%
      select(NHISHID, child_age = AGE),
    by = "NHISHID"
  ) %>%
  filter(ISPARENTSC == 1,
         CSTATFLG == 0,
         YEAR %in% c(2019, 2021, 2022, 2023)) %>%
  mutate(
    ace_total = rowSums(select(., VIOLENEV, JAILEV, MENTDEPEV, ALCDRUGEV,
                                ADLTPUTDOWN, UNFAIRRACE, UNFAIRSEXOR, BASENEED) == 1,
                        na.rm = FALSE)
  )

# Fit mixed model for exactly 1 ACE (n=7,657)
model_ace_1 <- glmer(I(ace_total == 1) ~ 1 + (1|REGION),
                     data = nhis_ace,
                     family = binomial,
                     weights = SAMPWEIGHT)

prop_ace_1 <- predict(model_ace_1,
                      newdata = data.frame(REGION = 2),
                      type = "response")
```

**Fills rows:** Age 0-5 (same value × 6)

---

#### 4. ACE Exposure - 2+ ACEs (1 estimand)
**Estimand:** "Proportion of mothers exposed to 2 or more adverse childhood experiences"

**Calculation:**
```r
# Use same filtered dataset (nhis_ace from above)
model_ace_2plus <- glmer(I(ace_total >= 2) ~ 1 + (1|REGION),
                         data = nhis_ace,
                         family = binomial,
                         weights = SAMPWEIGHT)

prop_ace_2plus <- predict(model_ace_2plus,
                          newdata = data.frame(REGION = 2),
                          type = "response")
```

**Fills rows:** Age 0-5 (same value × 6)

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
acs_data <- dbGetQuery(conn, "
  SELECT * FROM acs_data
  WHERE state = 'nebraska'
  AND AGE BETWEEN 0 AND 5
")

# Create survey design object
acs_design <- svydesign(
  ids = ~CLUSTER,
  strata = ~STRATA,
  weights = ~PERWT,
  data = acs_data
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
  ),

  # FPL categories (add all 5)
  # PUMAs (add all 14)

  # Mother's education (Bachelor's+)
  mom_educ_bachelors = fit_glm_estimates(
    I(EDUC_MOM >= 10) ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = subset(acs_design, !is.na(EDUC_MOM) & MOMLOC > 0)
  ),

  # Mother's marital status (married)
  mom_married = fit_glm_estimates(
    I(MARST_HEAD == 1) ~ AGE + MULTYEAR + AGE:MULTYEAR,
    design = subset(acs_design, MOMLOC > 0)
  )
)

# Extract estimates
acs_estimates <- lapply(results, function(x) x$estimates)

# Save results
saveRDS(list(
  estimates = acs_estimates,
  models = lapply(results, function(x) x$model),
  interaction_tests = lapply(results, function(x) x$interaction_significant)
), "scripts/raking/acs_estimates.rds")

# Print summary
cat("ACS GLM Estimation Summary:\n")
cat("===========================\n")
for(name in names(results)) {
  cat(sprintf("%s: Interaction %s\n",
              name,
              ifelse(results[[name]]$interaction_significant, "significant", "not significant")))
}
```

---

### Step 2: Create R Script for NHIS Estimates
**File:** `scripts/raking/estimate_nhis_targets.R`

```r
library(dplyr)
library(lme4)
library(DBI)
library(duckdb)

# Load NHIS data
conn <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")
nhis_data <- dbGetQuery(conn, "SELECT * FROM nhis_raw")

# CRITICAL: Filter to parents with children ages 0-5
nhis_parents_young <- nhis_data %>%
  inner_join(
    nhis_data %>%
      filter(CSTATFLG == 1, AGE <= 5) %>%
      select(NHISHID, child_age = AGE),
    by = "NHISHID"
  ) %>%
  filter(ISPARENTSC == 1, CSTATFLG == 0)

# Depression estimates (2019, 2022; n=4,022)
nhis_phq <- nhis_parents_young %>%
  filter(YEAR %in% c(2019, 2022), !is.na(PHQCAT))

model_phq_none <- glmer(I(PHQCAT == 1) ~ 1 + (1|REGION),
                        data = nhis_phq, family = binomial,
                        weights = SAMPWEIGHT)
model_phq_severe <- glmer(I(PHQCAT == 4) ~ 1 + (1|REGION),
                          data = nhis_phq, family = binomial,
                          weights = SAMPWEIGHT)

# ACE estimates (2019, 2021-2023; n=7,657)
nhis_ace <- nhis_parents_young %>%
  filter(YEAR %in% c(2019, 2021, 2022, 2023)) %>%
  mutate(ace_total = rowSums(select(., VIOLENEV, JAILEV, MENTDEPEV, ALCDRUGEV,
                                    ADLTPUTDOWN, UNFAIRRACE, UNFAIRSEXOR, BASENEED) == 1,
                            na.rm = FALSE))

model_ace_1 <- glmer(I(ace_total == 1) ~ 1 + (1|REGION),
                     data = nhis_ace, family = binomial,
                     weights = SAMPWEIGHT)
model_ace_2plus <- glmer(I(ace_total >= 2) ~ 1 + (1|REGION),
                         data = nhis_ace, family = binomial,
                         weights = SAMPWEIGHT)

# Extract predictions for North Central region (REGION = 2)
nhis_estimates <- list(
  prop_no_depression = predict(model_phq_none, newdata = data.frame(REGION = 2), type = "response"),
  prop_severe_depression = predict(model_phq_severe, newdata = data.frame(REGION = 2), type = "response"),
  prop_ace_1 = predict(model_ace_1, newdata = data.frame(REGION = 2), type = "response"),
  prop_ace_2plus = predict(model_ace_2plus, newdata = data.frame(REGION = 2), type = "response")
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

1. **Completeness:** All 192 rows have non-missing `est` values
2. **Range:** All estimates are between 0 and 1
3. **Consistency within categories:**
   - 5 FPL categories sum to 1.0 (within each age)
   - 14 PUMA categories sum to 1.0 (within each age)
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
  filter(grepl("Public-Use Micro Area", estimand)) %>%
  group_by(age_years) %>%
  summarise(total = sum(est))
stopifnot(all(abs(puma_check$total - 1.0) < 0.01))

# Check ACS consistency across ages
acs_check <- targets %>%
  filter(dataset == "ACS NE 5-year") %>%
  group_by(estimand) %>%
  summarise(unique_values = n_distinct(est))
stopifnot(all(acs_check$unique_values == 1))

cat("✓ All validation checks passed!\n")
```

---

## Summary

### Estimands by Source

| Source | Estimands | Age Variation | Total Rows |
|--------|-----------|---------------|------------|
| ACS | 26 (sex, race, FPL, PUMA, **mother education, mother marital status**) | 24 constant + **2 vary** | 24 × 6 + 12 = **156** |
| NHIS | 4 (depression, ACE) | Constant | 4 × 6 = 24 |
| NSCH | 4 (child ACE, behavioral, health, childcare) | Varies | 4 × 6 = 24 |
| **Total** | **34** | - | **204** |

**⚠️ Note:** Original raking_targets.csv has only 186 rows (31 estimands) - mother's education and marital status are **missing** and need to be added (12 new rows total).

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
2. ☐ **Add new rows to raking_targets.csv** (12 new rows total):
   - **Mother's education** (6 rows, ages 0-5):
     - Estimand: "Proportion of children whose mother has Bachelor's degree or higher"
     - Dataset: "ACS NE 5-year", Estimator: "GLM"
   - **Mother's marital status** (6 rows, ages 0-5):
     - Estimand: "Proportion of children whose mother is married"
     - Dataset: "ACS NE 5-year", Estimator: "GLM"
   - **New total:** 204 rows (was 186)
3. ☐ Implement ACS estimation script (26 estimands including mother education and marital status)
4. ☐ Implement NHIS estimation script (4 estimands)
5. ☐ Implement NSCH estimation script (4 estimands)
6. ☐ Create CSV filling script (handles 204 total rows)
7. ☐ Run validation checks
8. ☐ Review estimates with subject matter experts
9. ☐ Finalize raking targets for use in post-stratification

---

**Contact:** Kidsights Data Platform Team
**Documentation:** `docs/raking/RAKING_TARGETS_ESTIMATION_PLAN.md`

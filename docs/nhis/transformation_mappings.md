# NHIS → NE25 Transformation Mappings

Guide for harmonizing NHIS variables with NE25 Kidsights variables for comparative analysis and population benchmarking.

---

## Overview

### Purpose

This document outlines potential harmonization between NHIS (National Health Interview Survey) and NE25 (Nebraska 2025 Kidsights study) variables to enable:

1. **Population Benchmarking:** Compare NE25 sample to national NHIS estimates
2. **Variable Harmonization:** Create consistent constructs across datasets
3. **Raking/Weighting:** Use NHIS as population reference for post-stratification

### Status

**Current:** Documentation only (Phase 5)
**Future:** Implementation planned for Phase 12+ (Raking Module)
**Location:** `R/utils/raking_utils.R` (deferred)

### Harmonization Strategy

**NHIS → NE25 Direction:**
- NHIS provides population estimates (benchmark)
- NE25 provides detailed local data (sample)
- Harmonize NE25 categories to match NHIS for comparability

---

## Variable Mapping Summary

| Domain | NHIS Variables | NE25 Variables | Harmonization Status |
|--------|----------------|----------------|----------------------|
| [ACEs](#aces-harmonization) | 8 ACE items | 11 ACE items + total | **High Priority** - Direct overlap |
| [Mental Health](#mental-health-harmonization) | GAD-7, PHQ-8 | PHQ-2, GAD-2 | **Medium Priority** - Subset scales |
| [Demographics](#demographics-harmonization) | AGE, SEX | `age_c`, `a1_sex` | **High Priority** - Direct mapping |
| [Race/Ethnicity](#raceethnicity-harmonization) | RACENEW, HISPETH | `hisp`, `race`, `raceG` | **High Priority** - Category alignment |
| [Education](#education-harmonization) | EDUC, EDUCPARENT | `educ_max`, `educ_a1` | **High Priority** - Education levels |
| [Income](#income-harmonization) | FAMTOTINC, POVERTY | `income`, `fpl`, `fplcat` | **High Priority** - FPL calculation |
| [Geography](#geography-harmonization) | REGION, URBRRL | `urban_rural`, `county` | **Medium Priority** - Geographic linkage |
| [Parent Info](#parent-characteristics-harmonization) | PAR1AGE, PAR2AGE, etc. | `a1_age`, `a2_age`, etc. | **Low Priority** - Already harmonized |

---

## ACEs Harmonization

### Variable Mapping

| NHIS Variable | NHIS Description | NE25 Variable | NE25 Description | Harmonization Notes |
|---------------|------------------|---------------|------------------|---------------------|
| VIOLENEV | Lived with violent person | `ace_domestic_violence` | Domestic violence | **Direct match** |
| JAILEV | Lived with incarcerated person | `ace_incarceration` | Parent incarcerated | **Direct match** |
| MENTDEPEV | Lived with mentally ill person | `ace_mental_illness` | Parent mental illness | **Direct match** |
| ALCDRUGEV | Lived with substance user | `ace_substance_use` | Parent substance use | **Direct match** |
| ADLTPUTDOWN | Physical abuse | `ace_physical_abuse` | Physical abuse | **Direct match** |
| UNFAIRRACE | Discrimination (race) | `ace_discrimination` | Discrimination (any) | **Partial match** (NE25 broader) |
| UNFAIRSEXOR | Discrimination (sex/orientation) | `ace_discrimination` | Discrimination (any) | **Partial match** (NE25 broader) |
| BASENEED | Couldn't afford basic needs | `ace_neglect` | Neglect | **Conceptual match** |
| - | - | `ace_parent_loss` | Parent death/divorce | **NE25 only** |
| - | - | `ace_verbal_abuse` | Verbal abuse | **NE25 only** |
| - | - | `ace_emotional_neglect` | Emotional neglect | **NE25 only** |
| - | - | `ace_sexual_abuse` | Sexual abuse | **NE25 only** |

### NHIS Coding (All ACE Variables)

```
0 = Not in universe
1 = Yes
2 = No
7 = Refused
8 = Not ascertained
9 = Don't know
```

### NE25 Coding (All ACE Variables)

```
0 = No
1 = Yes
99 = Prefer not to answer (recoded to NA)
```

### Harmonization Function (Proposed)

```r
#' Harmonize ACE Variables: NHIS → NE25
#'
#' @param nhis_data NHIS data with raw ACE variables
#' @return Data frame with harmonized ACE variables matching NE25 schema
harmonize_nhis_aces <- function(nhis_data) {

  library(dplyr)

  nhis_data %>%
    dplyr::mutate(
      # Direct mappings (NHIS → NE25)
      ace_domestic_violence = dplyr::case_when(
        VIOLENEV == 1 ~ 1L,  # Yes
        VIOLENEV == 2 ~ 0L,  # No
        VIOLENEV %in% c(0, 7, 8, 9) ~ NA_integer_  # Missing
      ),

      ace_incarceration = dplyr::case_when(
        JAILEV == 1 ~ 1L,
        JAILEV == 2 ~ 0L,
        JAILEV %in% c(0, 7, 8, 9) ~ NA_integer_
      ),

      ace_mental_illness = dplyr::case_when(
        MENTDEPEV == 1 ~ 1L,
        MENTDEPEV == 2 ~ 0L,
        MENTDEPEV %in% c(0, 7, 8, 9) ~ NA_integer_
      ),

      ace_substance_use = dplyr::case_when(
        ALCDRUGEV == 1 ~ 1L,
        ALCDRUGEV == 2 ~ 0L,
        ALCDRUGEV %in% c(0, 7, 8, 9) ~ NA_integer_
      ),

      ace_physical_abuse = dplyr::case_when(
        ADLTPUTDOWN == 1 ~ 1L,
        ADLTPUTDOWN == 2 ~ 0L,
        ADLTPUTDOWN %in% c(0, 7, 8, 9) ~ NA_integer_
      ),

      # Partial mappings (combine NHIS variables for NE25 construct)
      ace_discrimination = dplyr::case_when(
        UNFAIRRACE == 1 | UNFAIRSEXOR == 1 ~ 1L,  # Any discrimination
        UNFAIRRACE == 2 & UNFAIRSEXOR == 2 ~ 0L,  # No discrimination
        TRUE ~ NA_integer_  # Missing if either is missing
      ),

      # Conceptual mapping (basic needs ≈ neglect)
      ace_neglect = dplyr::case_when(
        BASENEED == 1 ~ 1L,
        BASENEED == 2 ~ 0L,
        BASENEED %in% c(0, 7, 8, 9) ~ NA_integer_
      ),

      # Calculate ACE total (NHIS items only, comparable to NE25)
      # Only include items with valid responses
      ace_total_nhis = rowSums(
        dplyr::select(., dplyr::starts_with("ace_")),
        na.rm = FALSE  # NA if any item missing (conservative)
      ),

      # ACE risk category (same as NE25)
      ace_risk_cat = dplyr::case_when(
        is.na(ace_total_nhis) ~ NA_character_,
        ace_total_nhis == 0 ~ "No ACEs",
        ace_total_nhis >= 1 & ace_total_nhis <= 3 ~ "1-3 ACEs",
        ace_total_nhis >= 4 ~ "4+ ACEs"
      )
    )
}
```

### Usage Example

```r
# Load NHIS data
nhis_data <- load_nhis_feather("2019-2024")

# Harmonize ACE variables
nhis_harmonized <- harmonize_nhis_aces(nhis_data)

# Compare with NE25
library(duckdb)
conn <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")

ne25_ace_prev <- dbGetQuery(conn, "
  SELECT
    AVG(CASE WHEN ace_total >= 1 THEN 1.0 ELSE 0.0 END) as any_ace,
    AVG(CASE WHEN ace_total >= 4 THEN 1.0 ELSE 0.0 END) as high_ace
  FROM ne25_transformed
  WHERE age_c < 18
")

nhis_ace_prev <- nhis_harmonized %>%
  dplyr::filter(AGE < 18) %>%
  dplyr::summarise(
    any_ace = mean(ace_total_nhis >= 1, na.rm = TRUE),
    high_ace = mean(ace_total_nhis >= 4, na.rm = TRUE)
  )

print(ne25_ace_prev)
print(nhis_ace_prev)
```

---

## Mental Health Harmonization

### Scale Comparison

| Scale | NHIS | NE25 | Harmonization |
|-------|------|------|---------------|
| **PHQ (Depression)** | PHQ-8 (8 items) | PHQ-2 (2 items) | **NE25 subset of NHIS** |
| **GAD (Anxiety)** | GAD-7 (7 items) | GAD-2 (2 items) | **NE25 subset of NHIS** |

### PHQ Harmonization

**NHIS Variables:**
- PHQINTR, PHQDEP, PHQSLEEP, PHQENGY, PHQEAT, PHQBAD, PHQCONC, PHQMOVE
- PHQCAT (severity category)

**NE25 Variables:**
- `phq2_interest` (maps to PHQINTR)
- `phq2_depressed` (maps to PHQDEP)
- `phq2_total`, `phq2_positive`, `phq2_risk_cat`

**Harmonization Strategy:**

```r
#' Extract PHQ-2 from NHIS PHQ-8
#'
#' @param nhis_data NHIS data with PHQ-8 variables (2019, 2022 only)
#' @return Data frame with PHQ-2 variables matching NE25 schema
harmonize_nhis_phq2 <- function(nhis_data) {

  # Filter to years with PHQ-8
  nhis_data <- nhis_data %>%
    dplyr::filter(YEAR %in% c(2019, 2022))

  nhis_data %>%
    dplyr::mutate(
      # Recode NHIS PHQ-8 items to NE25 PHQ-2 coding
      # NHIS: 1=Not at all, 2=Several days, 3=More than half, 4=Nearly every day
      # NE25: 0=Not at all, 1=Several days, 2=More than half, 3=Nearly every day

      phq2_interest = dplyr::case_when(
        PHQINTR == 1 ~ 0L,  # Not at all
        PHQINTR == 2 ~ 1L,  # Several days
        PHQINTR == 3 ~ 2L,  # More than half
        PHQINTR == 4 ~ 3L,  # Nearly every day
        PHQINTR %in% c(0, 7, 8, 9) ~ NA_integer_  # Missing
      ),

      phq2_depressed = dplyr::case_when(
        PHQDEP == 1 ~ 0L,
        PHQDEP == 2 ~ 1L,
        PHQDEP == 3 ~ 2L,
        PHQDEP == 4 ~ 3L,
        PHQDEP %in% c(0, 7, 8, 9) ~ NA_integer_
      ),

      # Calculate PHQ-2 total (same as NE25)
      phq2_total = phq2_interest + phq2_depressed,

      # PHQ-2 positive screen (same as NE25: total >= 3)
      phq2_positive = dplyr::case_when(
        is.na(phq2_total) ~ NA_integer_,
        phq2_total >= 3 ~ 1L,
        TRUE ~ 0L
      ),

      # PHQ-2 risk category (same as NE25)
      phq2_risk_cat = dplyr::case_when(
        is.na(phq2_total) ~ NA_character_,
        phq2_total < 3 ~ "Low risk",
        phq2_total >= 3 ~ "At risk"
      )
    )
}
```

### GAD Harmonization

**Similar approach for GAD-2 extraction from GAD-7:**

```r
harmonize_nhis_gad2 <- function(nhis_data) {
  nhis_data %>%
    dplyr::filter(YEAR %in% c(2019, 2022)) %>%
    dplyr::mutate(
      gad2_nervous = dplyr::case_when(
        GADANX == 1 ~ 0L,
        GADANX == 2 ~ 1L,
        GADANX == 3 ~ 2L,
        GADANX == 4 ~ 3L,
        GADANX %in% c(0, 7, 8, 9) ~ NA_integer_
      ),

      gad2_worry = dplyr::case_when(
        GADWORCTRL == 1 ~ 0L,
        GADWORCTRL == 2 ~ 1L,
        GADWORCTRL == 3 ~ 2L,
        GADWORCTRL == 4 ~ 3L,
        GADWORCTRL %in% c(0, 7, 8, 9) ~ NA_integer_
      ),

      gad2_total = gad2_nervous + gad2_worry,

      gad2_positive = dplyr::case_when(
        is.na(gad2_total) ~ NA_integer_,
        gad2_total >= 3 ~ 1L,
        TRUE ~ 0L
      ),

      gad2_risk_cat = dplyr::case_when(
        is.na(gad2_total) ~ NA_character_,
        gad2_total < 3 ~ "Low risk",
        gad2_total >= 3 ~ "At risk"
      )
    )
}
```

---

## Demographics Harmonization

### Age

| NHIS | NE25 | Harmonization |
|------|------|---------------|
| AGE (0-85+) | `age_c` (child age, 0-17) | **Direct mapping** for children |
| - | `a1_age` (adult 1 age) | **Conceptual mapping** to parent age |

**Mapping:**
```r
# Direct child age mapping
age_c <- AGE  # For children (AGE < 18)

# Parent age estimation (approximate)
# NHIS has PAR1AGE, PAR2AGE for sample children
# NE25 has a1_age, a2_age for adults
a1_age <- PAR1AGE  # If sample child record
```

### Sex

| NHIS | NE25 | Harmonization |
|------|------|---------------|
| SEX (1=Male, 2=Female) | `a1_sex` (1=Male, 2=Female, 3=Other) | **Recode required** |

**Mapping:**
```r
a1_sex <- dplyr::case_when(
  SEX == 1 ~ 1L,  # Male
  SEX == 2 ~ 2L,  # Female
  # NHIS lacks "Other" category - treat as missing for comparability
  TRUE ~ NA_integer_
)
```

---

## Race/Ethnicity Harmonization

### Variable Comparison

| NHIS | NE25 | Harmonization |
|------|------|---------------|
| HISPETH (detailed Hispanic) | `hisp` (0/1 binary) | **Collapse NHIS categories** |
| RACENEW (detailed race) | `race` (6 categories) | **Recode NHIS to match** |
| - | `raceG` (4 broad groups) | **Aggregate from NHIS** |

### Hispanic Ethnicity

**NHIS → NE25 Mapping:**

```r
# NHIS HISPETH:
# 10 = Not Hispanic
# 20 = Hispanic, type not specified
# 21 = Mexican
# 22 = Mexican American
# 23 = Central/South American
# 24 = Puerto Rican
# 25 = Cuban/Cuban American
# 26 = Dominican
# 27 = Other Hispanic

# NE25 hisp: 0 = Not Hispanic, 1 = Hispanic

hisp <- dplyr::case_when(
  HISPETH == 10 ~ 0L,  # Not Hispanic
  HISPETH >= 20 & HISPETH <= 27 ~ 1L,  # Hispanic (any type)
  TRUE ~ NA_integer_
)
```

### Race

**NHIS → NE25 Race Mapping:**

```r
# NHIS RACENEW:
# 100 = White only
# 200 = Black/African American only
# 300-320 = American Indian/Alaska Native
# 400-470 = Asian (detailed)
# 500 = Native Hawaiian/Pacific Islander
# 600 = Multiple races

# NE25 race:
# 1 = White
# 2 = Black/African American
# 3 = Asian
# 4 = American Indian/Alaska Native
# 5 = Native Hawaiian/Pacific Islander
# 6 = Multiple races

race <- dplyr::case_when(
  RACENEW == 100 ~ 1L,  # White
  RACENEW == 200 ~ 2L,  # Black
  RACENEW >= 400 & RACENEW < 500 ~ 3L,  # Asian (collapse all Asian categories)
  RACENEW >= 300 & RACENEW < 400 ~ 4L,  # AIAN
  RACENEW >= 500 & RACENEW < 600 ~ 5L,  # NHPI
  RACENEW == 600 ~ 6L,  # Multiple races
  TRUE ~ NA_integer_
)
```

### Broad Race/Ethnicity Groups

**NHIS → NE25 raceG Mapping:**

```r
# NE25 raceG:
# 1 = White, non-Hispanic
# 2 = Black, non-Hispanic
# 3 = Hispanic (any race)
# 4 = Other, non-Hispanic

raceG <- dplyr::case_when(
  hisp == 1 ~ 3L,  # Hispanic (any race)
  race == 1 & hisp == 0 ~ 1L,  # White, non-Hispanic
  race == 2 & hisp == 0 ~ 2L,  # Black, non-Hispanic
  hisp == 0 ~ 4L,  # Other, non-Hispanic
  TRUE ~ NA_integer_
)
```

---

## Education Harmonization

### Variable Comparison

| NHIS | NE25 | Harmonization |
|------|------|---------------|
| EDUC (9 categories) | `educ_max` (8/4/6 category versions) | **Recode to match** |
| EDUCPARENT (9 categories) | `educ_a1`, `educ_mom` | **Direct mapping** |

### Education Levels

**NHIS → NE25 8-Category Mapping:**

```r
# NHIS EDUC:
# 1 = Never attended/kindergarten only
# 2 = Grades 1-11
# 3 = 12th grade, no diploma
# 4 = High school graduate or GED
# 5 = Some college, no degree
# 6 = Associate's degree
# 7 = Bachelor's degree
# 8 = Master's degree
# 9 = Professional/doctoral degree

# NE25 educ_max (8 categories):
# 1 = Less than high school
# 2 = High school graduate/GED
# 3 = Some college
# 4 = Associate's degree
# 5 = Bachelor's degree
# 6 = Master's degree
# 7 = Professional degree
# 8 = Doctoral degree

educ_max <- dplyr::case_when(
  EDUC %in% c(1, 2, 3) ~ 1L,  # Less than HS
  EDUC == 4 ~ 2L,  # HS grad/GED
  EDUC == 5 ~ 3L,  # Some college
  EDUC == 6 ~ 4L,  # Associate's
  EDUC == 7 ~ 5L,  # Bachelor's
  EDUC == 8 ~ 6L,  # Master's
  EDUC == 9 ~ 7L,  # Professional/Doctoral (NHIS combines)
  # Note: NE25 separates professional (7) and doctoral (8)
  # NHIS combines them - assign to professional for comparability
  TRUE ~ NA_integer_
)
```

**NE25 4-Category Mapping:**

```r
# NE25 educ_max_4cat:
# 1 = Less than high school
# 2 = High school graduate
# 3 = Some college
# 4 = Bachelor's degree or higher

educ_max_4cat <- dplyr::case_when(
  educ_max == 1 ~ 1L,
  educ_max == 2 ~ 2L,
  educ_max %in% c(3, 4) ~ 3L,  # Some college or Associate's
  educ_max >= 5 ~ 4L,  # Bachelor's+
  TRUE ~ NA_integer_
)
```

---

## Income Harmonization

### Variable Comparison

| NHIS | NE25 | Harmonization |
|------|------|---------------|
| FAMTOTINC (categorical) | `income` (13 categories) | **Recode categories** |
| POVERTY (FPL ratio) | `fpl` (FPL percentage) | **Direct match (scale difference)** |
| - | `fplcat` (FPL categories) | **Create from POVERTY** |

### Family Income

**NHIS → NE25 Income Categories:**

```r
# NHIS FAMTOTINC:
# 1 = Less than $35,000
# 2 = $35,000-$49,999
# 3 = $50,000-$74,999
# 4 = $75,000-$99,999
# 5 = $100,000 or more

# NE25 income (13 categories):
# 1-13 represent detailed income brackets

# Note: NHIS categories are broader than NE25
# Map to closest NE25 categories
income <- dplyr::case_when(
  FAMTOTINC == 1 ~ 5L,  # <$35k → $25-$34.9k (approximate)
  FAMTOTINC == 2 ~ 7L,  # $35-49.9k → $35-$49.9k (exact match)
  FAMTOTINC == 3 ~ 9L,  # $50-74.9k → $50-$74.9k (exact match)
  FAMTOTINC == 4 ~ 11L,  # $75-99.9k → $75-$99.9k (exact match)
  FAMTOTINC == 5 ~ 12L,  # $100k+ → $100-$149.9k (approximate)
  FAMTOTINC %in% c(96, 97, 98) ~ NA_integer_,  # Missing
  TRUE ~ NA_integer_
)
```

### Federal Poverty Level

**NHIS → NE25 FPL Mapping:**

```r
# NHIS POVERTY:
# 0-499 = Income as percentage of poverty threshold
# 500 = 500% or more of poverty threshold
# 996-998 = Missing/unknown

# NE25 fpl:
# Continuous variable (percentage of FPL)

# Direct mapping (NHIS already in percentage format)
fpl <- dplyr::case_when(
  POVERTY >= 0 & POVERTY <= 500 ~ POVERTY,
  POVERTY %in% c(996, 997, 998) ~ NA_real_,
  TRUE ~ NA_real_
)

# NE25 fplcat (FPL categories):
# 1 = <100% FPL
# 2 = 100-199% FPL
# 3 = 200-399% FPL
# 4 = 400%+ FPL

fplcat <- dplyr::case_when(
  is.na(fpl) ~ NA_integer_,
  fpl < 100 ~ 1L,
  fpl >= 100 & fpl < 200 ~ 2L,
  fpl >= 200 & fpl < 400 ~ 3L,
  fpl >= 400 ~ 4L
)
```

---

## Geography Harmonization

### Variable Comparison

| NHIS | NE25 | Harmonization |
|------|------|---------------|
| REGION (4 regions) | `county` (Nebraska counties) | **Not directly comparable** |
| URBRRL (urban/rural) | `urban_rural` (6 categories) | **Recode to match** |

### Urban/Rural Classification

**NHIS → NE25 Urban/Rural Mapping:**

```r
# NHIS URBRRL:
# 1 = Large central metropolitan
# 2 = Large fringe metropolitan
# 3 = Medium and small metropolitan
# 4 = Nonmetropolitan

# NE25 urban_rural (from ZIP crosswalk):
# 1 = Urbanized Area
# 2 = Urban Cluster
# 3 = Rural

# Approximate mapping
urban_rural <- dplyr::case_when(
  URBRRL == 1 ~ 1L,  # Large central metro → Urbanized Area
  URBRRL == 2 ~ 1L,  # Large fringe metro → Urbanized Area
  URBRRL == 3 ~ 2L,  # Medium/small metro → Urban Cluster
  URBRRL == 4 ~ 3L,  # Nonmetropolitan → Rural
  TRUE ~ NA_integer_
)
```

---

## Parent Characteristics Harmonization

### Variable Comparison

| NHIS | NE25 | Harmonization |
|------|------|---------------|
| PAR1AGE, PAR2AGE | `a1_age`, `a2_age` | **Direct mapping** |
| PAR1SEX, PAR2SEX | `a1_sex`, `a2_sex` | **Direct mapping** |
| PAR1MARST, PAR2MARST | Marital status variables | **Recode to match** |
| EDUCPARENT | `educ_max` (parent education) | **Use education harmonization** |
| PARRELTYPE | - | **NE25 lacks direct equivalent** |

**Most parent variables have direct conceptual mappings and require minimal harmonization beyond data type alignment.**

---

## Implementation Roadmap

### Phase 12+: Raking Module (Future)

**File:** `R/utils/raking_utils.R`

**Functions to Implement:**

1. `harmonize_nhis_to_ne25()` - Master harmonization function
2. `create_raking_targets()` - Generate population targets from NHIS
3. `rake_ne25_weights()` - Apply raking to NE25 sampling weights
4. `validate_raked_weights()` - Check weight distributions

### Example Workflow (Proposed)

```r
# Load both datasets
nhis_data <- load_nhis_feather("2019-2024")
ne25_data <- dbGetQuery(conn, "SELECT * FROM ne25_transformed")

# Harmonize NHIS to NE25 schema
nhis_harmonized <- harmonize_nhis_to_ne25(nhis_data)

# Create raking targets from NHIS (population benchmark)
raking_targets <- create_raking_targets(
  nhis_data = nhis_harmonized,
  target_vars = c("raceG", "urban_rural", "fplcat"),
  weights = "SAMPWEIGHT"
)

# Apply raking to NE25 weights
ne25_raked <- rake_ne25_weights(
  ne25_data = ne25_data,
  raking_targets = raking_targets,
  raking_vars = c("raceG", "urban_rural", "fplcat")
)

# Validate
validate_raked_weights(ne25_raked)
```

---

## Data Quality Considerations

### Missing Data

**NHIS:**
- Standard missing codes: 0 (NIU), 7 (Refused), 8 (Not ascertained), 9 (Don't know)
- Mental health variables only in 2019, 2022
- Top-coding for age (85+) and poverty (500%)

**NE25:**
- Missing code: 99 (Prefer not to answer)
- All recoded to NA before harmonization

**Harmonization Impact:**
- Always recode missing to NA before comparison
- Document differential missingness patterns
- Consider multiple imputation for raking

### Sample Design Differences

| Feature | NHIS | NE25 | Impact |
|---------|------|------|--------|
| **Geography** | Nationwide | Nebraska only | Limit NHIS to North Central region for comparison |
| **Sampling** | Multistage probability | Convenience (REDCap) | Raking essential for generalizability |
| **Weights** | SAMPWEIGHT (survey design) | None | Use NHIS weights for population estimates |
| **Age Range** | All ages | Children 0-17 (focus) | Filter NHIS to children |

### Recommended Filtering

```r
# Filter NHIS for NE25 comparability
nhis_comparable <- nhis_data %>%
  dplyr::filter(
    AGE < 18,  # Children only
    REGION == 2,  # North Central region (includes Nebraska)
    YEAR >= 2019  # Recent years
  )
```

---

## Citations & Resources

**IPUMS NHIS:**
```
Lynn A. Blewett, Julia A. Rivera Drew, Miriam L. King and Kari C.W. Williams.
IPUMS Health Surveys: National Health Interview Survey, Version 7.3 [dataset].
Minneapolis, MN: IPUMS, 2021. https://doi.org/10.18128/D070.V7.3
```

**NHIS Documentation:**
- Main site: https://www.cdc.gov/nchs/nhis/
- Questionnaires: https://www.cdc.gov/nchs/nhis/data-questionnaires-documentation.htm
- Variance estimation: https://www.cdc.gov/nchs/nhis/variance.htm

**Raking/Post-Stratification References:**
- Battaglia et al. (2009). "Practical Considerations in Raking Survey Data"
- Valliant & Dever (2018). "Survey Weights: A Step-by-Step Guide"

---

**Status:** Documentation Complete (Phase 5)
**Implementation:** Deferred to Phase 12+ (Raking Module)
**Last Updated:** 2025-10-03

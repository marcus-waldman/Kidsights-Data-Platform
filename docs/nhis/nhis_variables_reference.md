# NHIS Variables Reference

Complete reference for all 64 NHIS variables extracted from IPUMS Health Surveys, organized by category with IPUMS coding schemes, availability by year, and usage notes.

---

## Overview

**Total Variables:** 64
**Variable Groups:** 11
**Years Available:** 2019-2024 (6 years)
**Data Source:** [IPUMS Health Surveys](https://healthsurveys.ipums.org/)
**Collection:** NHIS (National Health Interview Survey)

---

## Variable Groups

1. [Identifiers & Sampling (9)](#identifiers--sampling-9-variables)
2. [Geographic (2)](#geographic-2-variables)
3. [Demographics (2)](#demographics-2-variables)
4. [Parent Information (13)](#parent-information-13-variables)
5. [Race/Ethnicity (2)](#raceethnicity-2-variables)
6. [Education (1)](#education-1-variable)
7. [Economic (5)](#economic-5-variables)
8. [ACEs & Adversity (8)](#aces--adversity-8-variables)
9. [Mental Health - GAD-7 Anxiety (8)](#mental-health---gad-7-anxiety-8-variables)
10. [Mental Health - PHQ-8 Depression (9)](#mental-health---phq-8-depression-9-variables)
11. [Flags (5)](#flags-5-variables)

---

## Identifiers & Sampling (9 variables)

### YEAR
**Description:** Survey year
**Type:** Integer
**Range:** 2019-2024
**Availability:** All years
**IPUMS Link:** [YEAR](https://nhis.ipums.org/nhis-action/variables/YEAR)

**Coding:**
- 2019 = Survey year 2019
- 2020 = Survey year 2020
- 2021 = Survey year 2021
- 2022 = Survey year 2022
- 2023 = Survey year 2023
- 2024 = Survey year 2024

---

### SERIAL
**Description:** Household serial number
**Type:** Integer
**Range:** 1-999999
**Availability:** All years
**IPUMS Link:** [SERIAL](https://nhis.ipums.org/nhis-action/variables/SERIAL)

**Usage:**
- Unique household identifier within year
- Combine with YEAR for across-year unique household ID
- Use with PERNUM for unique person ID

---

### STRATA
**Description:** Variance estimation stratum
**Type:** Integer
**Range:** 1-999
**Availability:** All years
**IPUMS Link:** [STRATA](https://nhis.ipums.org/nhis-action/variables/STRATA)

**Usage:**
- Required for variance estimation in complex surveys
- Use with PSU and SAMPWEIGHT in survey analysis
- R package: `survey::svydesign(strata = ~STRATA, ...)`

---

### PSU
**Description:** Primary sampling unit
**Type:** Integer
**Range:** 1-999
**Availability:** All years
**IPUMS Link:** [PSU](https://nhis.ipums.org/nhis-action/variables/PSU)

**Usage:**
- Clustering variable for variance estimation
- Use with STRATA and SAMPWEIGHT
- R package: `survey::svydesign(ids = ~PSU, ...)`

---

### NHISHID
**Description:** NHIS household identifier
**Type:** String
**Range:** Alphanumeric
**Availability:** All years
**IPUMS Link:** [NHISHID](https://nhis.ipums.org/nhis-action/variables/NHISHID)

**Usage:**
- Official NHIS household ID
- Can be used to link to public-use NHIS files
- More stable than SERIAL across IPUMS extracts

---

### PERNUM
**Description:** Person number in household
**Type:** Integer
**Range:** 1-99
**Availability:** All years
**IPUMS Link:** [PERNUM](https://nhis.ipums.org/nhis-action/variables/PERNUM)

**Usage:**
- Unique person identifier within household
- Combine with SERIAL+YEAR for unique person ID
- Primary key: (SERIAL, PERNUM)

---

### NHISPID
**Description:** NHIS person identifier
**Type:** String
**Range:** Alphanumeric
**Availability:** All years
**IPUMS Link:** [NHISPID](https://nhis.ipums.org/nhis-action/variables/NHISPID)

**Usage:**
- Official NHIS person ID
- Can be used to link to public-use NHIS files

---

### HHX
**Description:** Household number
**Type:** Integer
**Range:** 1-999999
**Availability:** All years
**IPUMS Link:** [HHX](https://nhis.ipums.org/nhis-action/variables/HHX)

**Usage:**
- Alternative household identifier
- Used in some NHIS documentation

---

### SAMPWEIGHT
**Description:** Sample weight
**Type:** Float
**Range:** 0.01-99999.99
**Availability:** All years
**IPUMS Link:** [SAMPWEIGHT](https://nhis.ipums.org/nhis-action/variables/SAMPWEIGHT)

**Usage:**
- **PRIMARY WEIGHT** for population estimates
- Always use for descriptive statistics
- R: `survey::svydesign(weights = ~SAMPWEIGHT, ...)`

**Example:**
```r
# Weighted mean
weighted.mean(data$AGE, weights = data$SAMPWEIGHT)
```

---

## Geographic (2 variables)

### REGION
**Description:** Census region
**Type:** Integer
**Range:** 1-4
**Availability:** All years
**IPUMS Link:** [REGION](https://nhis.ipums.org/nhis-action/variables/REGION)

**Coding:**
- 1 = Northeast
- 2 = North Central/Midwest
- 3 = South
- 4 = West

---

### URBRRL
**Description:** Urban/rural classification
**Type:** Integer
**Range:** 1-3
**Availability:** All years
**IPUMS Link:** [URBRRL](https://nhis.ipums.org/nhis-action/variables/URBRRL)

**Coding:**
- 1 = Large central metropolitan
- 2 = Large fringe metropolitan
- 3 = Medium and small metropolitan
- 4 = Nonmetropolitan

---

## Demographics (2 variables)

### AGE
**Description:** Age in years
**Type:** Integer
**Range:** 0-85
**Availability:** All years
**IPUMS Link:** [AGE](https://nhis.ipums.org/nhis-action/variables/AGE)

**Coding:**
- 0 = Under 1 year
- 1-84 = Age in years
- 85 = 85+ years (top-coded for confidentiality)

---

### SEX
**Description:** Sex
**Type:** Integer
**Range:** 1-2
**Availability:** All years
**IPUMS Link:** [SEX](https://nhis.ipums.org/nhis-action/variables/SEX)

**Coding:**
- 1 = Male
- 2 = Female

---

## Parent Information (13 variables)

### ISPARENTSC
**Description:** Is this person a sample child's parent?
**Type:** Integer
**Range:** 1-2
**Availability:** All years
**IPUMS Link:** [ISPARENTSC](https://nhis.ipums.org/nhis-action/variables/ISPARENTSC)

**Coding:**
- 1 = Yes
- 2 = No

---

### PAR1REL
**Description:** Parent 1 relationship to sample child
**Type:** Integer
**Range:** 1-10
**Availability:** All years
**IPUMS Link:** [PAR1REL](https://nhis.ipums.org/nhis-action/variables/PAR1REL)

**Coding:**
- 1 = Biological parent
- 2 = Adoptive parent
- 3 = Step parent
- 4 = Foster parent
- 5 = Grandparent
- 6 = Other relative
- 7 = Non-relative
- 8 = Unknown
- 9 = Not in universe

---

### PAR2REL
**Description:** Parent 2 relationship to sample child
**Type:** Integer
**Range:** 1-10
**Availability:** All years
**IPUMS Link:** [PAR2REL](https://nhis.ipums.org/nhis-action/variables/PAR2REL)

**Coding:** Same as PAR1REL

---

### PAR1AGE
**Description:** Parent 1 age in years
**Type:** Integer
**Range:** 0-85
**Availability:** All years
**IPUMS Link:** [PAR1AGE](https://nhis.ipums.org/nhis-action/variables/PAR1AGE)

**Coding:**
- 0-84 = Age in years
- 85 = 85+ years
- 97 = Refused
- 98 = Not ascertained
- 99 = Don't know

---

### PAR2AGE
**Description:** Parent 2 age in years
**Type:** Integer
**Range:** 0-85
**Availability:** All years
**IPUMS Link:** [PAR2AGE](https://nhis.ipums.org/nhis-action/variables/PAR2AGE)

**Coding:** Same as PAR1AGE

---

### PAR1SEX
**Description:** Parent 1 sex
**Type:** Integer
**Range:** 1-2
**Availability:** All years
**IPUMS Link:** [PAR1SEX](https://nhis.ipums.org/nhis-action/variables/PAR1SEX)

**Coding:**
- 1 = Male
- 2 = Female

---

### PAR2SEX
**Description:** Parent 2 sex
**Type:** Integer
**Range:** 1-2
**Availability:** All years
**IPUMS Link:** [PAR2SEX](https://nhis.ipums.org/nhis-action/variables/PAR2SEX)

**Coding:** Same as PAR1SEX

---

### PARRELTYPE
**Description:** Parent relationship type
**Type:** Integer
**Range:** 1-5
**Availability:** All years
**IPUMS Link:** [PARRELTYPE](https://nhis.ipums.org/nhis-action/variables/PARRELTYPE)

**Coding:**
- 1 = Two biological or adopted parents
- 2 = Two parents, at least one step/foster
- 3 = One biological or adopted parent
- 4 = One step/foster parent
- 5 = No parents in household

---

### PAR1MARST
**Description:** Parent 1 marital status
**Type:** Integer
**Range:** 1-6
**Availability:** All years
**IPUMS Link:** [PAR1MARST](https://nhis.ipums.org/nhis-action/variables/PAR1MARST)

**Coding:**
- 1 = Married - spouse in household
- 2 = Married - spouse not in household
- 3 = Married - spouse in household unknown
- 4 = Widowed
- 5 = Divorced
- 6 = Separated
- 7 = Never married
- 8 = Living with partner
- 9 = Unknown

---

### PAR2MARST
**Description:** Parent 2 marital status
**Type:** Integer
**Range:** 1-9
**Availability:** All years
**IPUMS Link:** [PAR2MARST](https://nhis.ipums.org/nhis-action/variables/PAR2MARST)

**Coding:** Same as PAR1MARST

---

### PAR1MARSTAT
**Description:** Parent 1 detailed marital status
**Type:** Integer
**Range:** 1-9
**Availability:** All years
**IPUMS Link:** [PAR1MARSTAT](https://nhis.ipums.org/nhis-action/variables/PAR1MARSTAT)

**Coding:** (Similar to PAR1MARST with more detail)

---

### PAR2MARSTAT
**Description:** Parent 2 detailed marital status
**Type:** Integer
**Range:** 1-9
**Availability:** All years
**IPUMS Link:** [PAR2MARSTAT](https://nhis.ipums.org/nhis-action/variables/PAR2MARSTAT)

**Coding:** (Similar to PAR2MARST with more detail)

---

### EDUCPARENT
**Description:** Highest education among parents
**Type:** Integer
**Range:** 1-9
**Availability:** All years
**IPUMS Link:** [EDUCPARENT](https://nhis.ipums.org/nhis-action/variables/EDUCPARENT)

**Coding:**
- 1 = Less than high school
- 2 = High school graduate or GED
- 3 = Some college
- 4 = Bachelor's degree
- 5 = Master's degree
- 6 = Professional degree
- 7 = Doctoral degree
- 8 = Unknown
- 9 = Not in universe

---

## Race/Ethnicity (2 variables)

### RACENEW
**Description:** Race (detailed)
**Type:** Integer
**Range:** 100-900
**Availability:** All years
**IPUMS Link:** [RACENEW](https://nhis.ipums.org/nhis-action/variables/RACENEW)

**Coding:**
- 100 = White only
- 200 = Black/African American only
- 300 = American Indian or Alaska Native only
- 310 = American Indian/Alaska Native, tribe not specified
- 320 = American Indian/Alaska Native, tribe specified
- 400 = Asian only
- 410 = Asian Indian
- 420 = Chinese
- 430 = Filipino
- 440 = Korean
- 450 = Vietnamese
- 460 = Japanese
- 470 = Other Asian
- 500 = Native Hawaiian/Pacific Islander only
- 600 = Multiple races

---

### HISPETH
**Description:** Hispanic ethnicity (detailed)
**Type:** Integer
**Range:** 10-40
**Availability:** All years
**IPUMS Link:** [HISPETH](https://nhis.ipums.org/nhis-action/variables/HISPETH)

**Coding:**
- 10 = Not Hispanic
- 20 = Hispanic, type not specified
- 21 = Mexican
- 22 = Mexican American
- 23 = Central/South American
- 24 = Puerto Rican
- 25 = Cuban/Cuban American
- 26 = Dominican
- 27 = Other Hispanic

---

## Education (1 variable)

### EDUC
**Description:** Educational attainment
**Type:** Integer
**Range:** 1-9
**Availability:** All years
**IPUMS Link:** [EDUC](https://nhis.ipums.org/nhis-action/variables/EDUC)

**Coding:**
- 1 = Never attended/kindergarten only
- 2 = Grades 1-11
- 3 = 12th grade, no diploma
- 4 = High school graduate or GED
- 5 = Some college, no degree
- 6 = Associate's degree
- 7 = Bachelor's degree
- 8 = Master's degree
- 9 = Professional/doctoral degree

---

## Economic (5 variables)

### FAMTOTINC
**Description:** Total family income (categorical)
**Type:** Integer
**Range:** 1-11
**Availability:** All years
**IPUMS Link:** [FAMTOTINC](https://nhis.ipums.org/nhis-action/variables/FAMTOTINC)

**Coding:**
- 1 = Less than $35,000
- 2 = $35,000-$49,999
- 3 = $50,000-$74,999
- 4 = $75,000-$99,999
- 5 = $100,000 or more
- 96 = Refused
- 97 = Not ascertained
- 98 = Don't know

---

### POVERTY
**Description:** Ratio of family income to poverty threshold
**Type:** Float
**Range:** 0-500
**Availability:** All years
**IPUMS Link:** [POVERTY](https://nhis.ipums.org/nhis-action/variables/POVERTY)

**Coding:**
- 0-499 = Income as percentage of poverty threshold
- 500 = 500% or more of poverty threshold
- 996 = Unknown - but income < $20,000
- 997 = Unknown - but income $20,000+
- 998 = Unknown

**Example:**
- 100 = At poverty threshold (100%)
- 50 = 50% of poverty threshold
- 200 = 200% of poverty threshold (twice threshold)

---

### FSATELESS
**Description:** Worried food would run out
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [FSATELESS](https://nhis.ipums.org/nhis-action/variables/FSATELESS)

**Coding:**
- 0 = Not in universe
- 1 = Often true
- 2 = Sometimes true
- 3 = Never true
- 7 = Refused
- 8 = Not ascertained
- 9 = Don't know

---

### FSBALANC
**Description:** Food bought didn't last
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [FSBALANC](https://nhis.ipums.org/nhis-action/variables/FSBALANC)

**Coding:** Same as FSATELESS

---

### OWNERSHIP
**Description:** Home ownership status
**Type:** Integer
**Range:** 1-3
**Availability:** All years
**IPUMS Link:** [OWNERSHIP](https://nhis.ipums.org/nhis-action/variables/OWNERSHIP)

**Coding:**
- 1 = Owned or being bought
- 2 = Rented
- 3 = Other arrangement

---

## ACEs & Adversity (8 variables)

**NOTE:** All ACE variables use the following general coding:
- 0 = Not in universe (not asked)
- 1 = Yes
- 2 = No
- 7 = Refused
- 8 = Not ascertained
- 9 = Don't know

### VIOLENEV
**Description:** Ever lived with someone who was violent
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [VIOLENEV](https://nhis.ipums.org/nhis-action/variables/VIOLENEV)

---

### JAILEV
**Description:** Ever lived with someone who served time in jail/prison
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [JAILEV](https://nhis.ipums.org/nhis-action/variables/JAILEV)

---

### MENTDEPEV
**Description:** Ever lived with someone who was mentally ill/depressed
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [MENTDEPEV](https://nhis.ipums.org/nhis-action/variables/MENTDEPEV)

---

### ALCDRUGEV
**Description:** Ever lived with someone who had alcohol/drug problem
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [ALCDRUGEV](https://nhis.ipums.org/nhis-action/variables/ALCDRUGEV)

---

### ADLTPUTDOWN
**Description:** Adults slapped, hit, kicked, or punched you
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [ADLTPUTDOWN](https://nhis.ipums.org/nhis-action/variables/ADLTPUTDOWN)

---

### UNFAIRRACE
**Description:** Treated unfairly because of race/ethnicity
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [UNFAIRRACE](https://nhis.ipums.org/nhis-action/variables/UNFAIRRACE)

---

### UNFAIRSEXOR
**Description:** Treated unfairly because of sex/sexual orientation
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [UNFAIRSEXOR](https://nhis.ipums.org/nhis-action/variables/UNFAIRSEXOR)

---

### BASENEED
**Description:** Parents couldn't afford food, clothing, housing
**Type:** Integer
**Range:** 0-9
**Availability:** All years
**IPUMS Link:** [BASENEED](https://nhis.ipums.org/nhis-action/variables/BASENEED)

---

## Mental Health - GAD-7 Anxiety (8 variables)

**IMPORTANT:** GAD-7 variables only available in **2019 and 2022**

**General Coding (items GADANX-GADFEAR):**
- 0 = Not in universe
- 1 = Not at all
- 2 = Several days
- 3 = More than half the days
- 4 = Nearly every day
- 7 = Refused
- 8 = Not ascertained
- 9 = Don't know

### GADANX
**Description:** Feeling nervous, anxious, or on edge (GAD-7 item 1)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [GADANX](https://nhis.ipums.org/nhis-action/variables/GADANX)

---

### GADWORCTRL
**Description:** Not being able to stop or control worrying (GAD-7 item 2)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [GADWORCTRL](https://nhis.ipums.org/nhis-action/variables/GADWORCTRL)

---

### GADWORMUCH
**Description:** Worrying too much about different things (GAD-7 item 3)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [GADWORMUCH](https://nhis.ipums.org/nhis-action/variables/GADWORMUCH)

---

### GADRELAX
**Description:** Trouble relaxing (GAD-7 item 4)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [GADRELAX](https://nhis.ipums.org/nhis-action/variables/GADRELAX)

---

### GADRSTLS
**Description:** Being so restless that it's hard to sit still (GAD-7 item 5)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [GADRSTLS](https://nhis.ipums.org/nhis-action/variables/GADRSTLS)

---

### GADANNOY
**Description:** Becoming easily annoyed or irritable (GAD-7 item 6)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [GADANNOY](https://nhis.ipums.org/nhis-action/variables/GADANNOY)

---

### GADFEAR
**Description:** Feeling afraid as if something awful might happen (GAD-7 item 7)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [GADFEAR](https://nhis.ipums.org/nhis-action/variables/GADFEAR)

---

### GADCAT
**Description:** GAD-7 anxiety severity category
**Type:** Integer
**Range:** 0-4
**Availability:** 2019, 2022
**IPUMS Link:** [GADCAT](https://nhis.ipums.org/nhis-action/variables/GADCAT)

**Coding:**
- 0 = Not in universe
- 1 = Minimal anxiety (score 0-4)
- 2 = Mild anxiety (score 5-9)
- 3 = Moderate anxiety (score 10-14)
- 4 = Severe anxiety (score 15-21)

**Interpretation:**
- Score ≥10 (categories 3-4) = Positive screen for anxiety disorder
- Recommend clinical evaluation

---

## Mental Health - PHQ-8 Depression (9 variables)

**IMPORTANT:** PHQ-8 variables only available in **2019 and 2022**

**General Coding (items PHQINTR-PHQMOVE):**
- 0 = Not in universe
- 1 = Not at all
- 2 = Several days
- 3 = More than half the days
- 4 = Nearly every day
- 7 = Refused
- 8 = Not ascertained
- 9 = Don't know

### PHQINTR
**Description:** Little interest or pleasure in doing things (PHQ-8 item 1)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [PHQINTR](https://nhis.ipums.org/nhis-action/variables/PHQINTR)

---

### PHQDEP
**Description:** Feeling down, depressed, or hopeless (PHQ-8 item 2)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [PHQDEP](https://nhis.ipums.org/nhis-action/variables/PHQDEP)

---

### PHQSLEEP
**Description:** Trouble falling/staying asleep, or sleeping too much (PHQ-8 item 3)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [PHQSLEEP](https://nhis.ipums.org/nhis-action/variables/PHQSLEEP)

---

### PHQENGY
**Description:** Feeling tired or having little energy (PHQ-8 item 4)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [PHQENGY](https://nhis.ipums.org/nhis-action/variables/PHQENGY)

---

### PHQEAT
**Description:** Poor appetite or overeating (PHQ-8 item 5)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [PHQEAT](https://nhis.ipums.org/nhis-action/variables/PHQEAT)

---

### PHQBAD
**Description:** Feeling bad about yourself or that you're a failure (PHQ-8 item 6)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [PHQBAD](https://nhis.ipums.org/nhis-action/variables/PHQBAD)

---

### PHQCONC
**Description:** Trouble concentrating on things (PHQ-8 item 7)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [PHQCONC](https://nhis.ipums.org/nhis-action/variables/PHQCONC)

---

### PHQMOVE
**Description:** Moving or speaking slowly, or being fidgety/restless (PHQ-8 item 8)
**Type:** Integer
**Range:** 0-9
**Availability:** 2019, 2022
**IPUMS Link:** [PHQMOVE](https://nhis.ipums.org/nhis-action/variables/PHQMOVE)

**Note:** PHQ-8 omits PHQ-9 item on self-harm ideation

---

### PHQCAT
**Description:** PHQ-8 depression severity category
**Type:** Integer
**Range:** 0-4
**Availability:** 2019, 2022
**IPUMS Link:** [PHQCAT](https://nhis.ipums.org/nhis-action/variables/PHQCAT)

**Coding:**
- 0 = Not in universe
- 1 = Minimal depression (score 0-4)
- 2 = Mild depression (score 5-9)
- 3 = Moderate depression (score 10-14)
- 4 = Moderately severe/severe depression (score 15-24)

**Interpretation:**
- Score ≥10 (categories 3-4) = Positive screen for major depression
- Recommend clinical evaluation

---

## Flags (5 variables)

### SASCRESP
**Description:** Sample adult or sample child respondent
**Type:** Integer
**Range:** 1-2
**Availability:** All years
**IPUMS Link:** [SASCRESP](https://nhis.ipums.org/nhis-action/variables/SASCRESP)

**Coding:**
- 1 = Sample adult
- 2 = Sample child

---

### ASTATFLG
**Description:** Adult file record flag
**Type:** Integer
**Range:** 1-3
**Availability:** All years
**IPUMS Link:** [ASTATFLG](https://nhis.ipums.org/nhis-action/variables/ASTATFLG)

**Coding:**
- 1 = Sample adult, has record in adult file
- 2 = Not sample adult
- 3 = Sample adult, does not have record in adult file

---

### CSTATFLG
**Description:** Child file record flag
**Type:** Integer
**Range:** 1-3
**Availability:** All years
**IPUMS Link:** [CSTATFLG](https://nhis.ipums.org/nhis-action/variables/CSTATFLG)

**Coding:**
- 1 = Sample child, has record in child file
- 2 = Not sample child
- 3 = Sample child, does not have record in child file

---

### HHRESP
**Description:** Household respondent type
**Type:** Integer
**Range:** 1-10
**Availability:** All years
**IPUMS Link:** [HHRESP](https://nhis.ipums.org/nhis-action/variables/HHRESP)

**Coding:**
- 1 = Household respondent, family respondent
- 2 = Household respondent, not family respondent
- 3 = Not household respondent, family respondent
- 4 = Not household respondent, not family respondent
- 9 = Unknown

---

### RELATIVERESPC
**Description:** Relative of sample child respondent
**Type:** Integer
**Range:** 1-2
**Availability:** All years
**IPUMS Link:** [RELATIVERESPC](https://nhis.ipums.org/nhis-action/variables/RELATIVERESPC)

**Coding:**
- 1 = Related to sample child
- 2 = Not related to sample child

---

## Variable Availability Matrix

| Variable Group | 2019 | 2020 | 2021 | 2022 | 2023 | 2024 |
|----------------|------|------|------|------|------|------|
| Identifiers (11) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Geographic (2) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Demographics (2) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Parent Info (13) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Race/Ethnicity (2) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Education (1) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Economic (5) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| ACEs (8) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **GAD-7 (8)** | **✓** | **✗** | **✗** | **✓** | **✗** | **✗** |
| **PHQ-8 (9)** | **✓** | **✗** | **✗** | **✓** | **✗** | **✗** |
| Flags (5) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Key:**
- ✓ = Available
- ✗ = Not available
- **Bold** = Limited availability (GAD-7/PHQ-8 only in 2019, 2022)

---

## Common Data Quality Issues

### Missing Data Codes

**Standard Missing Codes:**
- 0 = Not in universe (question not asked)
- 7 = Refused
- 8 = Not ascertained
- 9 = Don't know
- 96-99 = Various missing codes (variable-specific)

**Handling Missing Data:**
```r
# Recode missing to NA
library(dplyr)
nhis_data <- nhis_data %>%
  dplyr::mutate(
    VIOLENEV_clean = dplyr::case_when(
      VIOLENEV %in% c(0, 7, 8, 9) ~ NA_integer_,
      TRUE ~ VIOLENEV
    )
  )
```

### Top-Coding

**AGE:**
- 85+ years coded as 85 (to protect confidentiality)
- Use 85 as midpoint for analyses or create 85+ category

**POVERTY:**
- 500+ percent of poverty coded as 500
- Most analyses use 500 as cutoff or create 500+ category

### Year-Specific Availability

**Mental Health Scales:**
- GAD-7 and PHQ-8 only in 2019 and 2022
- Always check YEAR before analyzing these variables
- Example:
  ```r
  mh_data <- nhis_data %>%
    dplyr::filter(YEAR %in% c(2019, 2022))
  ```

---

## Additional Resources

**IPUMS NHIS Documentation:**
- Main site: https://healthsurveys.ipums.org/
- Variable search: https://nhis.ipums.org/nhis-action/variables/group
- User guide: https://nhis.ipums.org/nhis/userguide.shtml

**NCHS NHIS Resources:**
- Main site: https://www.cdc.gov/nchs/nhis/
- Questionnaires: https://www.cdc.gov/nchs/nhis/data-questionnaires-documentation.htm
- Variance estimation: https://www.cdc.gov/nchs/nhis/variance.htm

**Citation:**
```
Lynn A. Blewett, Julia A. Rivera Drew, Miriam L. King and Kari C.W. Williams. IPUMS Health Surveys: National Health Interview Survey, Version 7.3 [dataset]. Minneapolis, MN: IPUMS, 2021. https://doi.org/10.18128/D070.V7.3
```

---

**Last Updated:** 2025-10-03
**Pipeline Version:** 1.0.0

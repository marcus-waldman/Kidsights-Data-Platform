# IPUMS Variables Reference - ACS Data Pipeline

**Purpose**: Reference documentation for IPUMS USA variables extracted for statistical raking.

**Important**: This document describes **raw IPUMS variables only**. No harmonization or recoding is applied. All variables use original IPUMS coding schemes.

---

## Table of Contents

- [Core Identifiers](#core-identifiers)
- [Sampling Weights](#sampling-weights)
- [Demographics](#demographics)
- [Education Variables](#education-variables)
- [Geographic Variables](#geographic-variables)
- [Economic Variables](#economic-variables)
- [Government Programs](#government-programs)
- [Household Composition](#household-composition)
- [Attached Characteristics](#attached-characteristics)
- [IPUMS Coding Conventions](#ipums-coding-conventions)

---

## Core Identifiers

These variables uniquely identify households and persons within the ACS sample.

### SERIAL
- **Type**: Integer (64-bit)
- **Label**: Household serial number
- **Description**: Unique identifier for each household in the sample. Combined with PERNUM to uniquely identify individuals.
- **Range**: Varies by year
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/SERIAL

### PERNUM
- **Type**: Integer
- **Label**: Person number within household
- **Description**: Sequential numbering of persons within each household. Combined with SERIAL to create unique person identifier.
- **Range**: 1-20+ (varies by household size)
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/PERNUM

### STATEFIP
- **Type**: Integer
- **Label**: State FIPS code
- **Description**: Two-digit FIPS code identifying the state.
- **Example Values**:
  - 19 = Iowa
  - 20 = Kansas
  - 31 = Nebraska
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/STATEFIP

---

## Sampling Weights

Critical for producing population estimates and conducting raking procedures.

### HHWT
- **Type**: Double precision
- **Label**: Household weight
- **Description**: Number of households in the U.S. population represented by each household in the sample.
- **Usage**: Use for household-level analyses
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/HHWT

### PERWT
- **Type**: Double precision
- **Label**: Person weight
- **Description**: Number of persons in the U.S. population represented by each person in the sample.
- **Usage**: **PRIMARY WEIGHT for raking** - use for person-level analyses
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/PERWT

---

## Demographics

Core demographic characteristics used for statistical raking.

### AGE
- **Type**: Integer
- **Label**: Age in years
- **Description**: Age of individual at time of survey
- **Filter Applied**: Data limited to ages 0-5 (children only)
- **Coding**:
  - 0 = Under 1 year old
  - 1-5 = Age in years
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/AGE

### SEX
- **Type**: Integer
- **Label**: Sex
- **Description**: Biological sex of individual
- **Coding**:
  - 1 = Male
  - 2 = Female
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/SEX

### RACE
- **Type**: Integer
- **Label**: Race (detailed version)
- **Description**: Detailed racial categories using IPUMS coding
- **Coding** (selected values):
  - 1 = White
  - 2 = Black/African American
  - 3 = American Indian or Alaska Native
  - 4-6 = Various Asian categories
  - 7 = Other race
  - 8-9 = Two or more races
- **Note**: Detailed codes vary by year. See IPUMS documentation for complete coding.
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/RACE

### HISPAN
- **Type**: Integer
- **Label**: Hispanic origin
- **Description**: Hispanic/Latino ethnicity
- **Coding**:
  - 0 = Not Hispanic
  - 1-4 = Various Hispanic origin categories
  - 9 = Not reported
- **Note**: Hispanic origin is separate from race (can be any race)
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/HISPAN

---

## Education Variables

Parent education is critical for raking. Uses **attached characteristics** to link children to parents.

### EDUC
- **Type**: Integer
- **Label**: Educational attainment (general version)
- **Description**: Highest educational attainment using general coding (10 categories)
- **Coding**:
  - 0 = N/A or no schooling
  - 1 = Nursery school to grade 4
  - 2 = Grade 5, 6, 7, or 8
  - 3 = Grade 9
  - 4 = Grade 10
  - 5 = Grade 11
  - 6 = Grade 12 (no diploma)
  - 7 = High school graduate
  - 8 = Some college
  - 9 = Associate degree
  - 10 = Bachelor's degree
  - 11 = Master's degree
  - 12 = Professional degree beyond bachelor's
  - 13 = Doctoral degree
- **Attached Characteristics**: EDUC_mom, EDUC_pop
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/EDUC

### EDUCD
- **Type**: Integer
- **Label**: Educational attainment (detailed version)
- **Description**: Highest educational attainment using detailed coding (100+ categories)
- **Note**: More granular than EDUC. Use EDUC for most analyses.
- **Attached Characteristics**: EDUCD_mom, EDUCD_pop
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/EDUCD

---

## Geographic Variables

Geographic identifiers for regional analyses and urban/rural classification.

### PUMA
- **Type**: Integer
- **Label**: Public Use Microdata Area
- **Description**: Geographic unit with minimum population of 100,000 (5-year ACS)
- **Usage**: Finest geographic detail available in public ACS data
- **Note**: PUMA boundaries change over time
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/PUMA

### METRO
- **Type**: Integer
- **Label**: Metropolitan status
- **Description**: Classification of metropolitan vs. non-metropolitan areas
- **Coding**:
  - 0 = Not identifiable
  - 1 = Not in metropolitan area
  - 2 = In metropolitan area, central city
  - 3 = In metropolitan area, outside central city
  - 4 = In metropolitan area, central city status unknown
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/METRO

---

## Economic Variables

Household income and poverty indicators for socioeconomic raking dimensions.

### HHINCOME
- **Type**: Integer
- **Label**: Total household income
- **Description**: Total pre-tax household income in past 12 months (dollars)
- **Note**: Includes all household members, not just family
- **Special Codes**:
  - 9999999 = N/A (GQ or vacant)
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/HHINCOME

### FTOTINC
- **Type**: Integer
- **Label**: Total family income
- **Description**: Total pre-tax family income in past 12 months (dollars)
- **Note**: Family members only (related by birth, marriage, adoption)
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/FTOTINC

### POVERTY
- **Type**: Integer
- **Label**: Poverty status
- **Description**: Family income as percentage of poverty threshold
- **Coding**:
  - 1-500 = Percentage of poverty threshold (e.g., 100 = at threshold, 200 = 2x threshold)
  - 0 = N/A
- **Example**: 150 = family income is 150% of poverty threshold
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/POVERTY

### GRPIP
- **Type**: Integer
- **Label**: Gross rent as percentage of household income
- **Description**: Monthly gross rent as percentage of monthly household income
- **Range**: 0-100+ (capped at 101 for 101%+)
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/GRPIP

---

## Government Programs

Participation in government assistance programs.

### FOODSTMP
- **Type**: Integer
- **Label**: Food stamp/SNAP participation
- **Description**: Household receipt of food stamps/SNAP in past 12 months
- **Coding**:
  - 0 = N/A
  - 1 = No
  - 2 = Yes
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/FOODSTMP

### HINSCAID
- **Type**: Integer
- **Label**: Medicaid coverage
- **Description**: Individual covered by Medicaid
- **Coding**:
  - 0 = N/A
  - 1 = No Medicaid coverage
  - 2 = Has Medicaid coverage
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/HINSCAID

### HCOVANY
- **Type**: Integer
- **Label**: Any health insurance coverage
- **Description**: Individual has any type of health insurance
- **Coding**:
  - 0 = N/A
  - 1 = No health insurance
  - 2 = Has health insurance
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/HCOVANY

---

## Household Composition

Relationships and household structure.

### RELATE
- **Type**: Integer
- **Label**: Relationship to household head
- **Description**: Relationship of individual to head of household
- **Coding** (selected values):
  - 1 = Head/householder
  - 2 = Spouse
  - 3 = Child
  - 4 = Child-in-law
  - 5 = Parent
  - 6 = Parent-in-law
  - 7-10 = Other relatives
  - 11-13 = Non-relatives
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/RELATE

### MARST
- **Type**: Integer
- **Label**: Marital status
- **Description**: Current marital status
- **Coding**:
  - 1 = Married, spouse present
  - 2 = Married, spouse absent
  - 3 = Separated
  - 4 = Divorced
  - 5 = Widowed
  - 6 = Never married/single
- **Attached Characteristics**: MARST_head (marital status of household head)
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/MARST

### MOMLOC
- **Type**: Integer
- **Label**: Mother's location in household
- **Description**: Person number (PERNUM) of individual's mother if present in household
- **Coding**:
  - 0 = Mother not present in household
  - 1-20+ = PERNUM of mother
- **Usage**: Used to link children to mothers for attached characteristics
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/MOMLOC

### POPLOC
- **Type**: Integer
- **Label**: Father's location in household
- **Description**: Person number (PERNUM) of individual's father if present in household
- **Coding**:
  - 0 = Father not present in household
  - 1-20+ = PERNUM of father
- **Usage**: Used to link children to fathers for attached characteristics
- **IPUMS URL**: https://usa.ipums.org/usa-action/variables/POPLOC

---

## Attached Characteristics

**What are attached characteristics?**

Attached characteristics are IPUMS-generated variables that automatically link a person's characteristics to related household members. For children, this provides parent education, marital status, etc. without manual linking.

### How They Work

When you request a variable like `EDUC` with attached characteristics for `mother` and `father`, IPUMS creates:
- **EDUC**: Child's own education (typically N/A for children 0-5)
- **EDUC_mom**: Mother's education (linked via MOMLOC)
- **EDUC_pop**: Father's education (linked via POPLOC)

### Attached Characteristics in This Pipeline

| Base Variable | Attached Characteristics | Variables Created |
|--------------|-------------------------|-------------------|
| **EDUC** | mother, father | EDUC_mom, EDUC_pop |
| **EDUCD** | mother, father | EDUCD_mom, EDUCD_pop |
| **MARST** | head | MARST_head |

### Variable Naming Convention

- **_mom**: Mother's value (linked via MOMLOC)
- **_pop**: Father's value (linked via POPLOC)
- **_head**: Household head's value (RELATE=1)

### Missing Values for Attached Characteristics

If a parent or household head is not present in the household:
- Variable will be coded as missing/N/A according to that variable's coding scheme
- Check MOMLOC=0 (mother absent) or POPLOC=0 (father absent)

### IPUMS Documentation

For more information on attached characteristics:
https://usa.ipums.org/usa/attach_characteristics.shtml

---

## IPUMS Coding Conventions

### Missing Data Codes

IPUMS uses different missing data codes depending on the variable:

| Code | Meaning | Common Variables |
|------|---------|------------------|
| **0** | N/A (not applicable) | Most variables |
| **9** | Missing/Unknown (1 digit) | SEX, RACE |
| **99** | Missing/Unknown (2 digit) | AGE (if applicable) |
| **999** | Missing/Unknown (3 digit) | Income variables |
| **9999999** | N/A | HHINCOME (GQ/vacant) |

**Important**: Check each variable's codebook for specific missing data conventions.

### Top Coding

Some continuous variables are **top coded** to protect privacy:

- **Income variables**: Very high incomes are capped at maximum reported value
- **Age**: Typically 90+ grouped together (not applicable for our 0-5 filter)

### General Quarters (GQ)

Some variables are N/A for individuals in group quarters (institutions, college dorms, etc.):
- Household-level income variables
- Family relationship variables

**Note**: Our age filter (0-5) and household sampling should minimize GQ records.

### Year-to-Year Comparability

**Important considerations**:

1. **Variable definitions change**: Some variables have different codes across years
2. **PUMA boundaries**: Geographic boundaries change periodically
3. **Race categories**: Detailed race coding expanded over time
4. **Sample design**: 5-year ACS pools data, smoothing year-to-year changes

**Recommendation**: When comparing across time periods, carefully review IPUMS comparability statements for each variable.

### IPUMS Documentation Resources

- **Main Documentation**: https://usa.ipums.org/usa/
- **Variable Index**: https://usa.ipums.org/usa-action/variables/group
- **Comparability Issues**: Check individual variable pages for "Comparability" section
- **User Forum**: https://forum.ipums.org/

---

## Variable Summary Table

Quick reference of all extracted variables:

| Variable | Type | Description | Attached Chars |
|----------|------|-------------|----------------|
| **Identifiers** | | | |
| SERIAL | Integer | Household serial number | - |
| PERNUM | Integer | Person number | - |
| STATEFIP | Integer | State FIPS code | - |
| **Weights** | | | |
| HHWT | Double | Household weight | - |
| PERWT | Double | Person weight | - |
| **Demographics** | | | |
| AGE | Integer | Age in years (0-5) | - |
| SEX | Integer | Sex (1=M, 2=F) | - |
| RACE | Integer | Race (detailed) | - |
| HISPAN | Integer | Hispanic origin | - |
| **Education** | | | |
| EDUC | Integer | Education (general) | ✓ (_mom, _pop) |
| EDUCD | Integer | Education (detailed) | ✓ (_mom, _pop) |
| **Geography** | | | |
| PUMA | Integer | Public use microdata area | - |
| METRO | Integer | Metropolitan status | - |
| **Economics** | | | |
| HHINCOME | Integer | Household income | - |
| FTOTINC | Integer | Family income | - |
| POVERTY | Integer | Poverty percentage | - |
| GRPIP | Integer | Rent as % income | - |
| **Programs** | | | |
| FOODSTMP | Integer | SNAP participation | - |
| HINSCAID | Integer | Medicaid coverage | - |
| HCOVANY | Integer | Any insurance | - |
| **Household** | | | |
| RELATE | Integer | Relationship to head | - |
| MARST | Integer | Marital status | ✓ (_head) |
| MOMLOC | Integer | Mother's PERNUM | - |
| POPLOC | Integer | Father's PERNUM | - |

**Total**: 25 base variables + 5 attached characteristic variables = **30 total variables**

---

## Notes for Users

1. **No Harmonization**: All variables use raw IPUMS coding. Consult IPUMS documentation for interpretation.

2. **Age Filter**: Data limited to children ages 0-5. Parent characteristics accessed via attached characteristics.

3. **Sampling Weights**: Always use PERWT for person-level analyses and raking.

4. **Missing Data**: Check variable-specific coding for missing data conventions.

5. **Multi-Year**: When combining multiple time periods, verify variable comparability.

6. **State Identification**: Use `state` column (not STATEFIP) for multi-state queries in database.

---

**Last Updated**: 2025-09-30
**Pipeline Version**: 1.0.0
**IPUMS Citation**: Steven Ruggles, Sarah Flood, Matthew Sobek, et al. IPUMS USA: Version 15.0 [dataset]. Minneapolis, MN: IPUMS, 2024. https://doi.org/10.18128/D010.V15.0

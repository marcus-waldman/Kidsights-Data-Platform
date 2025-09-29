# NE25 Data Dictionary

**Generated:** 2025-09-15 22:53:00  
**Total Records:** 3903  
**Total Variables:** 28  
**Categories:** 5  

## Overview

This data dictionary describes all variables in the NE25 transformed dataset. 
The data comes from REDCap surveys and has been processed through the Kidsights 
data transformation pipeline, which applies standardized harmonization rules 
for race/ethnicity, education categories, and other demographic variables.

## Table of Contents

- [Race](#race) (6 variables)
- [Caregiver Relationship](#caregiver-relationship) (4 variables)
- [Education](#education) (12 variables)
- [Sex](#sex) (2 variables)
- [Age](#age) (4 variables)

## Race

**Description:** Race and ethnicity variables for children and primary caregivers, including harmonized categories

**Variables:** 6  
**Average Missing:** 37.3%  
**Data Types:** 6 factors, 0 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `a1_hisp` | Primary caregiver Hispanic/Latino ethnicity | factor | 37.9% | non-Hisp. (1950), Hispanic (474), 3 (1479) |
| `a1_race` | Primary caregiver race (collapsed categories) | factor | 37.2% | White (1893), American Indian or Alaska Native (22), Asian or Pacific Islander (80), Black or African American (177), Other Asian (28)... |
| `a1_raceG` | Primary caregiver race/ethnicity combined | factor | 37.9% | White, non-Hisp. (1573), American Indian or Alaska Native, non-Hisp. (11), Asian or Pacific Islander, non-Hisp. (102), Black or African American, non-Hisp. (159), Hispanic (474)... |
| `hisp` | Child Hispanic/Latino ethnicity | factor | 37.2% | non-Hisp. (1931), Hispanic (521), 3 (1451) |
| `race` | Child race (collapsed categories) | factor | 36.3% | White (1828), American Indian or Alaska Native (25), Asian or Pacific Islander (54), Black or African American (191), Other Asian (32)... |
| `raceG` | Child race/ethnicity combined | factor | 37.2% | White, non-Hisp. (1483), American Indian or Alaska Native, non-Hisp. (13), Asian or Pacific Islander, non-Hisp. (82), Black or African American, non-Hisp. (164), Hispanic (521)... |

## Caregiver Relationship

**Description:** Variables describing relationships between caregivers and children, including gender and maternal status

**Variables:** 4  
**Average Missing:** 36.6%  
**Data Types:** 2 factors, 0 numeric, 2 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `female_a1` | Primary caregiver is female | logical | 33.0% | True: 2154, False: 463 |
| `mom_a1` | Primary caregiver is mother | logical | 33.5% | True: 2093, False: 503 |
| `relation1` | Primary caregiver relationship to child | factor | 33.3% | Biological or Adoptive Parent (2527), Foster Parent (21), Grandparent (23), Other: Non-Relative (6), Other: Relative (8)... |
| `relation2` | Secondary caregiver relationship to child | factor | 46.7% | Biological or Adoptive Parent (1988), Foster Parent (7), Grandparent (43), Other: Non-Relative (8), Other: Relative (13)... |

## Education

**Description:** Education level variables using multiple categorization systems (4, 6, and 8 categories)

**Variables:** 12  
**Average Missing:** 40.8%  
**Data Types:** 12 factors, 0 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `educ4_a1` | Primary caregiver education level (4 categories) | factor | 33.0% | College Degree (1559), Less than High School Graduate (153), High School Graduate (including Equivalency) (316), Some College or Associate's Degree (588), 5 (1287) |
| `educ4_a2` | Secondary caregiver education level (4 categories) | factor | 46.8% | College Degree (1017), Less than High School Graduate (143), High School Graduate (including Equivalency) (298), Some College or Associate's Degree (618), 5 (1827) |
| `educ4_max` | Maximum education level among caregivers (4 categories) | factor | 32.7% | College Degree (1654), Less than High School Graduate (126), High School Graduate (including Equivalency) (293), Some College or Associate's Degree (555), 5 (1275) |
| `educ4_mom` | Maternal education level (4 categories) | factor | 50.7% | Less than High School Graduate (14), High School Graduate (including Equivalency) (47), Some College or Associate's Degree (558), College Degree (1304), 5 (1980) |
| `educ6_a1` | Primary caregiver education level (6 categories) | factor | 33.0% | Bachelor's Degree (863), Less than High School Graduate (153), High School Graduate (including Equivalency) (316), Some College or Associate's Degree (588), Master's Degree (507)... |
| `educ6_a2` | Secondary caregiver education level (6 categories) | factor | 46.8% | Bachelor's Degree (618), Less than High School Graduate (143), High School Graduate (including Equivalency) (298), Some College or Associate's Degree (618), Master's Degree (276)... |
| `educ6_max` | Maximum education level among caregivers (6 categories) | factor | 32.7% | Bachelor's Degree (779), Less than High School Graduate (126), High School Graduate (including Equivalency) (293), Some College or Associate's Degree (555), Master's Degree (606)... |
| `educ6_mom` | Maternal education level (6 categories) | factor | 50.7% | Less than High School Graduate (14), High School Graduate (including Equivalency) (47), Some College or Associate's Degree (558), Bachelor's Degree (165), Master's Degree (700)... |
| `educ_a1` | Primary caregiver education level (8 categories) | factor | 33.0% | Bachelor's Degree (BA, BS, AB) (863), 8th grade or less (48), 9th-12th grade, No diploma (105), High School Graduate or GED Completed (316), Completed a vocational, trade, or business school program (54)... |
| `educ_a2` | Secondary caregiver education level (8 categories) | factor | 46.8% | Bachelor's Degree (BA, BS, AB) (618), 8th grade or less (56), 9th-12th grade, No diploma (87), High School Graduate or GED Completed (298), Completed a vocational, trade, or business school program (77)... |
| `educ_max` | Maximum education level among caregivers (8 categories) | factor | 32.7% | Bachelor's Degree (BA, BS, AB) (779), 8th grade or less (42), 9th-12th grade, No diploma (84), High School Graduate or GED Completed (293), Completed a vocational, trade, or business school program (47)... |
| `educ_mom` | Maternal education level (8 categories) | factor | 50.7% | 9th-12th grade, No diploma (14), High School Graduate or GED Completed (47), Completed a vocational, trade, or business school program (248), Some College Credit, but No Degree (48), Associate Degree (AA, AS) (262)... |

## Sex

**Description:** Child's biological sex and gender indicator variables

**Variables:** 2  
**Average Missing:** 36.4%  
**Data Types:** 1 factors, 0 numeric, 1 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `female` | Child is female | logical | 36.4% | True: 1221, False: 1261 |
| `sex` | Child's sex | factor | 36.4% | Female (1221), Male (1261), 3 (1421) |

## Age

**Description:** Age variables for children and caregivers in different units (days, months, years)

**Variables:** 4  
**Average Missing:** 26.2%  
**Data Types:** 0 factors, 4 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `a1_years_old` | Primary caregiver age (years) | numeric | 34.0% | Min: 0, Max: 60, Mean: 32.97 |
| `days_old` | Child's age (days) | numeric | 23.7% | Min: 0, Max: 13175, Mean: 1360.54 |
| `months_old` | Child's age (months) | numeric | 23.7% | Min: 0, Max: 432.8542, Mean: 44.70 |
| `years_old` | Child's age (years) | numeric | 23.7% | Min: 0, Max: 36.0712, Mean: 3.73 |

---

## Notes

- **Missing percentages** are calculated as (missing values / total records) × 100
- **Factor variables** show the most common levels with their counts
- **Numeric variables** display min, max, and mean values where available
- **Logical variables** show counts of TRUE and FALSE values

*Generated automatically from metadata on 2025-09-15 by the Kidsights Data Platform*

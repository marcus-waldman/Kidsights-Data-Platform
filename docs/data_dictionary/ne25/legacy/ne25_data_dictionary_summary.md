# NE25 Data Dictionary

**Generated:** 2025-09-15 22:52:48  
**Total Records:** 3903  
**Total Variables:** 28  
**Categories:** 5  

## Overview

This data dictionary describes all variables in the NE25 transformed dataset. 
The data comes from REDCap surveys and has been processed through the Kidsights 
data transformation pipeline, which applies standardized harmonization rules 
for race/ethnicity, education categories, and other demographic variables.

## Race

**Description:** Race and ethnicity variables for children and primary caregivers, including harmonized categories

**Variables:** 6  
**Average Missing:** 37.3%  
**Data Types:** 6 factors, 0 numeric, 0 logical, 0 character

**Variables:** `a1_hisp`, `a1_race`, `a1_raceG`, `hisp`, `race`, `raceG`

## Caregiver Relationship

**Description:** Variables describing relationships between caregivers and children, including gender and maternal status

**Variables:** 4  
**Average Missing:** 36.6%  
**Data Types:** 2 factors, 0 numeric, 2 logical, 0 character

**Variables:** `female_a1`, `mom_a1`, `relation1`, `relation2`

## Education

**Description:** Education level variables using multiple categorization systems (4, 6, and 8 categories)

**Variables:** 12  
**Average Missing:** 40.8%  
**Data Types:** 12 factors, 0 numeric, 0 logical, 0 character

**Variables:** `educ4_a1`, `educ4_a2`, `educ4_max`, `educ4_mom`, `educ6_a1`, `educ6_a2`, `educ6_max`, `educ6_mom`, `educ_a1`, `educ_a2`, `educ_max`, `educ_mom`

## Sex

**Description:** Child's biological sex and gender indicator variables

**Variables:** 2  
**Average Missing:** 36.4%  
**Data Types:** 1 factors, 0 numeric, 1 logical, 0 character

**Variables:** `female`, `sex`

## Age

**Description:** Age variables for children and caregivers in different units (days, months, years)

**Variables:** 4  
**Average Missing:** 26.2%  
**Data Types:** 0 factors, 4 numeric, 0 logical, 0 character

**Variables:** `a1_years_old`, `days_old`, `months_old`, `years_old`

---

## Notes

- **Missing percentages** are calculated as (missing values / total records) × 100
- **Factor variables** show the most common levels with their counts
- **Numeric variables** display min, max, and mean values where available
- **Logical variables** show counts of TRUE and FALSE values

*Generated automatically from metadata on 2025-09-15 by the Kidsights Data Platform*

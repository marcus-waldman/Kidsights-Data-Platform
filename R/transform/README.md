# NE25 Data Transformations

This directory contains R functions for transforming raw REDCap data into analysis-ready variables for the NE25 study. The transformation system creates 99 derived variables across 10 categories through the `recode_it()` function.

## Architecture Overview

The transformation system follows a modular design pattern:

```
Raw REDCap Data → recode_it() → Category Transformations → Derived Variables
       ↓              ↓                ↓                      ↓
   588 columns   Master function   10 transformation   99 derived variables
   3,906 records    orchestrates     categories         with labels & levels
```

## Core Functions

### `recode_it(dat, dict, my_API = NULL, what = "all")`

**Master transformation function** that orchestrates all variable transformations.

**Parameters**:
- `dat`: Raw data frame from REDCap extraction
- `dict`: REDCap data dictionary for value labels
- `my_API`: API configuration (optional)
- `what`: Transformation categories to apply (default: "all")

**Usage**:
```r
# Apply all transformations
transformed_data <- recode_it(raw_data, redcap_dict)

# Apply specific transformations
race_vars <- recode_it(raw_data, redcap_dict, what = "race")
educ_vars <- recode_it(raw_data, redcap_dict, what = "education")

# Apply multiple specific transformations
demo_vars <- recode_it(raw_data, redcap_dict, what = c("race", "education", "sex"))
```

**Output**: Data frame with original data plus 21 new derived variables with appropriate factor levels and variable labels.

### `recode__(dat, dict, my_API = NULL, what = NULL, relevel_it = TRUE, add_labels = TRUE)`

**Internal transformation function** that handles individual transformation categories.

**Parameters**:
- `relevel_it`: Whether to set reference levels for factors (default: TRUE)
- `add_labels`: Whether to add variable labels using `labelled` package (default: TRUE)

## Transformation Categories

### 1. **Inclusion and Eligibility** (`what = "include"`)

Creates logical variables to determine study eligibility based on 9 CID criteria.

**Input Variables**:
- `eligibility`: Pass/fail status from CID screening
- `authenticity`: Pass/fail status from authenticity checks

**Output Variables** (3):
```r
eligible   # Logical: TRUE if eligibility == "Pass"
authentic  # Logical: TRUE if authenticity == "Pass"
include    # Logical: TRUE if both eligible AND authentic
```

**Variable Labels**:
- `eligible`: "Meets study inclusion criteria"
- `authentic`: "Passes authenticity screening"
- `include`: "Meets inclusion criteria (inclusion + authenticity)"

**Usage Example**:
```r
# Generate inclusion variables
inclusion_data <- recode_it(raw_data, dict, what = "include")

# Check eligibility rates
table(inclusion_data$eligible)  # FALSE: 234, TRUE: 3672
table(inclusion_data$include)   # Final inclusion after authenticity
```

### 2. **Race and Ethnicity** (`what = "race"`)

Harmonizes race and ethnicity data with collapsed categories for both child and primary caregiver.

**Input Variables**:
- Child: `cqr011` (Hispanic), `cqr010_*` (race checkboxes)
- Caregiver: `sq003` (Hispanic), `sq002_*` (race checkboxes)

**Output Variables** (6):
```r
# Child race/ethnicity
hisp     # Factor: "Hispanic" vs "non-Hisp."
race     # Factor: "White", "Black", "Asian or Pacific Islander", "Some Other Race", "Two or More"
raceG    # Factor: Combined race/ethnicity ("White, non-Hisp.", "Hispanic", etc.)

# Primary caregiver race/ethnicity
a1_hisp  # Factor: "Hispanic" vs "non-Hisp."
a1_race  # Factor: Same categories as child race
a1_raceG # Factor: Combined race/ethnicity for caregiver
```

**Category Mapping**:
```r
# Race category collapsing
"Asian Indian", "Chinese", "Filipino", "Japanese", "Korean", "Vietnamese",
"Native Hawaiian", "Guamanian or Chamorro", "Samoan", "Other Pacific Islander"
→ "Asian or Pacific Islander"

"Middle Eastern", "Some other race" → "Some Other Race"

# Multiple race selections → "Two or More"
```

**Reference Levels**:
- `hisp`, `a1_hisp`: Reference = "non-Hisp."
- `race`, `a1_race`: Reference = "White"
- `raceG`, `a1_raceG`: Reference = "White, non-Hisp."

**Variable Labels**:
- `hisp`: "Child Hispanic/Latino ethnicity"
- `race`: "Child race (collapsed categories)"
- `raceG`: "Child race/ethnicity combined"
- `a1_hisp`: "Primary caregiver Hispanic/Latino ethnicity"
- `a1_race`: "Primary caregiver race (collapsed categories)"
- `a1_raceG`: "Primary caregiver race/ethnicity combined"

### 3. **Education Levels** (`what = "education"`)

Creates education variables with 3 different category structures (4, 6, and 8 categories) for flexible analysis.

**Input Variables**:
- `cqr004`: Primary caregiver education
- `nschj017`: Secondary caregiver education
- `mom_a1`: Whether primary caregiver is mother (from relationship transformation)

**Output Variables** (12):
```r
# 8-category education (detailed)
educ_max   # Maximum education between caregivers
educ_a1    # Primary caregiver education
educ_a2    # Secondary caregiver education
educ_mom   # Maternal education (if primary caregiver is mother)

# 4-category education (simplified)
educ4_max, educ4_a1, educ4_a2, educ4_mom

# 6-category education (intermediate)
educ6_max, educ6_a1, educ6_a2, educ6_mom
```

**Category Structures**:

**8 Categories (detailed)**:
1. "Less than 9th grade"
2. "9th to 12th grade, no diploma"
3. "High school graduate (including equivalency)"
4. "Some college, no degree"
5. "Associate's degree"
6. "Bachelor's degree"
7. "Master's degree"
8. "Doctorate or professional degree"

**4 Categories (simplified)**:
1. "Less than High School Graduate" (8-cat: 1-2)
2. "High School Graduate (including Equivalency)" (8-cat: 3)
3. "Some College or Associate's Degree" (8-cat: 4-5)
4. "College Degree" (8-cat: 6-8)

**6 Categories (intermediate)**:
1. "Less than High School Graduate" (8-cat: 1-2)
2. "High School Graduate (including Equivalency)" (8-cat: 3)
3. "Some College or Associate's Degree" (8-cat: 4-5)
4. "Bachelor's Degree" (8-cat: 6)
5. "Master's Degree" (8-cat: 7)
6. "Doctorate or Professional Degree" (8-cat: 8)

**Reference Level**: "Bachelor's degree" (position 7 in 8-category scale)

**Variable Labels**:
- `educ_max`: "Maximum education level among caregivers (8 categories)"
- `educ_a1`: "Primary caregiver education level (8 categories)"
- `educ4_max`: "Maximum education level among caregivers (4 categories)"
- `educ6_a1`: "Primary caregiver education level (6 categories)"
- etc.

### 4. **Caregiver Relationships** (`what = "caregiver relationship"`)

Determines caregiver relationships and gender for family structure analysis.

**Input Variables**:
- `cqr008`: Primary caregiver relationship to child
- `nschj013`: Secondary caregiver relationship to child
- `cqr002`: Primary caregiver gender

**Output Variables** (4):
```r
relation1  # Factor: Primary caregiver relationship
relation2  # Factor: Secondary caregiver relationship
female_a1  # Logical: Primary caregiver is female
mom_a1     # Logical: Primary caregiver is mother
```

**Variable Labels**:
- `relation1`: "Primary caregiver relationship to child"
- `relation2`: "Secondary caregiver relationship to child"
- `female_a1`: "Primary caregiver is female"
- `mom_a1`: "Primary caregiver is mother"

### 5. **Sex** (`what = "sex"`)

Child's sex with both categorical and logical representations.

**Input Variables**:
- `cqr009`: Child's sex

**Output Variables** (2):
```r
sex     # Factor: "Female", "Male" (reference: "Female")
female  # Logical: TRUE if child is female
```

**Variable Labels**:
- `sex`: "Child's sex"
- `female`: "Child is female"

### 6. **Age** (`what = "age"`)

Age calculations in multiple units for child and primary caregiver.

**Input Variables**:
- `age_in_days`: Child's age in days
- `cqr003`: Primary caregiver age in years

**Output Variables** (4):
```r
days_old     # Numeric: Child's age in days
years_old    # Numeric: Child's age in years (days/365.25)
months_old   # Numeric: Child's age in months (years*12)
a1_years_old # Numeric: Primary caregiver age in years
```

**Variable Labels**:
- `days_old`: "Child's age (days)"
- `years_old`: "Child's age (years)"
- `months_old`: "Child's age (months)"
- `a1_years_old`: "Primary caregiver age (years)"

### 7. **Income** (`what = "income"`)

Income and poverty level calculations with CPI adjustments.

**Input Variables**:
- `consent_date`: Date of consent for CPI adjustment
- `cqr006`: Household annual income
- `fqlive1_1`, `fqlive1_2`: Family size components

**Output Variables** (6):
```r
income                    # Numeric: Annual income (nominal dollars)
inc99                    # Numeric: Income adjusted to 1999 dollars
family_size              # Numeric: Number of people in household
federal_poverty_threshold # Numeric: FPL threshold for family size
fpl                      # Numeric: Income as % of federal poverty level
fplcat                   # Factor: FPL categories ("<100% FPL", "100-199% FPL", etc.)
```

**FPL Categories**:
- "<100% FPL"
- "100-199% FPL"
- "200-299% FPL"
- "300-399% FPL"
- "400+% FPL" (reference level)

**Variable Labels**:
- `income`: "Household annual income (nominal dollars)"
- `inc99`: "Household annual income (1999 dollars)"
- `family_size`: "Family size (number of people in household)"
- `federal_poverty_threshold`: "Federal poverty threshold for family size"
- `fpl_derivation_flag`: "Flag indicating how federal poverty level was derived"
- `fpl`: "Household income as percentage of federal poverty level"
- `fplcat`: "Household income as percentage of federal poverty level (categories)"

### 8. **Geographic Variables** (`what = "geographic"`)

Creates 25 geographic variables from ZIP code using database-backed crosswalk tables.

**Input Variables**:
- `sq001`: ZIP code

**Output Variables** (25):
```r
# PUMA (Public Use Microdata Areas)
puma, puma_afact

# County
county, county_name, county_afact

# Census Tract
tract, tract_afact

# Core-Based Statistical Areas
cbsa, cbsa_name, cbsa_afact

# Urban/Rural Classification
urban_rural, urban_rural_afact, urban_pct

# School Districts
school_dist, school_name, school_afact

# State Legislative Districts
sldl, sldl_afact      # Lower/House
sldu, sldu_afact      # Upper/Senate

# US Congressional Districts
congress_dist, congress_afact

# Native Lands (AIANNH)
aiannh_code, aiannh_name, aiannh_afact
```

**Key Features**:
- **Semicolon-separated format**: Preserves multiple assignments for ZIP codes spanning multiple geographies
- **Allocation factors**: Proportion of ZIP population in each geography
- **Database-backed**: Queries 10 crosswalk tables (126K rows) via Python hybrid approach

**Variable Labels**: See `config/derived_variables.yaml` lines 330-353

### 9. **Mental Health and ACE Variables** (`what = "mental health"` or `what = "ace"`)

Creates mental health screening scores and Adverse Childhood Experiences (ACE) variables for both caregivers and children.

**Input Variables**:
- PHQ-2: `cqfb013`, `cqfb014` (depression screening)
- GAD-2: `cqfb015`, `cqfb016` (anxiety screening)
- Caregiver ACEs: `cace1`-`cace10` (caregiver's own childhood experiences)
- Child ACEs: `cqr017`-`cqr024` (child's experiences as reported by caregiver)

**Output Variables** (32):

**PHQ-2 Depression Screening (5)**:
```r
phq2_interest   # Numeric (0-3): Little interest/pleasure in activities
phq2_depressed  # Numeric (0-3): Feeling down, depressed, hopeless
phq2_total      # Numeric (0-6): Sum of two items
phq2_positive   # Numeric (0-1): Positive screen (≥3)
phq2_risk_cat   # Factor: Minimal/None (0-1), Mild (2), Moderate/Severe (3-6)
```

**GAD-2 Anxiety Screening (5)**:
```r
gad2_nervous    # Numeric (0-3): Feeling nervous, anxious, on edge
gad2_worry      # Numeric (0-3): Unable to stop/control worrying
gad2_total      # Numeric (0-6): Sum of two items
gad2_positive   # Numeric (0-1): Positive screen (≥3)
gad2_risk_cat   # Factor: Minimal/None (0-1), Mild (2), Moderate (3-4), Severe (5-6)
```

**Caregiver ACEs (12)** - Caregiver's own childhood experiences (first 18 years):
```r
# Individual ACE items (binary 0/1)
ace_neglect              # Physical/emotional neglect
ace_parent_loss          # Lost parent (divorce, death, abandonment)
ace_mental_illness       # Lived with mentally ill/suicidal person
ace_substance_use        # Lived with person with alcohol/drug problems
ace_domestic_violence    # Witnessed domestic violence between parents/adults
ace_incarceration        # Lived with someone who went to jail/prison
ace_verbal_abuse         # Experienced verbal/emotional abuse from parent/adult
ace_physical_abuse       # Experienced physical abuse from parent/adult
ace_emotional_neglect    # Felt unloved or not special in family
ace_sexual_abuse         # Experienced unwanted sexual contact

# Composite scores
ace_total       # Numeric (0-10): Total count of ACEs
ace_risk_cat    # Factor: No ACEs, 1 ACE, 2-3 ACEs, 4+ ACEs
```

**Child ACEs (10)** - Child's adverse experiences as reported by caregiver:
```r
# Individual ACE items (binary 0/1)
child_ace_parent_divorce          # Parent/guardian divorced or separated
child_ace_parent_death            # Parent/guardian died
child_ace_parent_jail             # Parent/guardian served time in jail
child_ace_domestic_violence       # Saw/heard parents/adults hit each other
child_ace_neighborhood_violence   # Victim/witnessed neighborhood violence
child_ace_mental_illness          # Lived with mentally ill/suicidal person
child_ace_substance_use           # Lived with person with alcohol/drug problems
child_ace_discrimination          # Treated unfairly due to race/ethnicity

# Composite scores
child_ace_total      # Numeric (0-8): Total count of child ACEs
child_ace_risk_cat   # Factor: No ACEs, 1 ACE, 2-3 ACEs, 4+ ACEs
```

**Clinical Cutoffs**:
- **PHQ-2 ≥3**: Indicates likely depression, further evaluation needed
- **GAD-2 ≥3**: Indicates likely anxiety, further evaluation needed
- **ACE Risk**: 4+ ACEs associated with significantly elevated health risks

**Reference Levels**:
- `phq2_risk_cat`: "Minimal/None" (reference)
- `gad2_risk_cat`: "Minimal/None" (reference)
- `ace_risk_cat`: "No ACEs" (reference)
- `child_ace_risk_cat`: "No ACEs" (reference)

**Variable Labels**: See `config/derived_variables.yaml` lines 277-315

### 10. **Childcare Variables** (`what = "childcare"`)

Creates 21 variables covering childcare access, costs, quality, subsidies, and derived indicators.

**Input Variables**:
- Access: `mmi013`, `mmi014` (difficulty finding care, reasons)
- Type: `mmi009`, `mmi010` (primary arrangement, hours)
- Costs: `mmi011`, `mmi012`, `mmi015` (weekly costs for different arrangements)
- Quality: `mmi016`, `mmi018` (quality ratings)
- Subsidies: `mmi021`, `mmi020` (subsidy receipt, family support)

**Output Variables** (21):
```r
# Access and Difficulty
cc_access_difficulty   # Factor: Difficulty finding care (past 12 months)
cc_difficulty_reason   # Factor: Main reason care was difficult to find

# Receipt and Type
cc_receives_care       # Factor: Child currently receives non-parental care
cc_primary_type        # Factor: Primary childcare arrangement type
cc_hours_per_week      # Numeric: Hours per week in primary arrangement

# Costs
cc_weekly_cost_all     # Numeric: Weekly household childcare costs (all children)
cc_weekly_cost_primary # Numeric: Weekly cost for primary arrangement (this child)
cc_weekly_cost_total   # Numeric: Total weekly cost for all arrangements (this child)

# Quality
cc_quality_rating      # Factor: Quality rating of primary arrangement
cc_quality_importance  # Factor: Importance of quality in choosing care

# Subsidies and Support
cc_subsidy             # Factor: Receives childcare subsidy
cc_family_support      # Factor: Receives financial support from family

# Derived Variables
cc_formal_care         # Factor: Uses formal care (center/preschool/Head Start)
cc_intensity           # Factor: Care intensity (part-time/full-time/extended)
cc_any_support         # Factor: Receives any financial support (family or subsidy)
```

**Reference Levels**:
- `cc_receives_care`: "No" (reference)
- `cc_formal_care`: "No" (reference)
- `cc_any_support`: "No" (reference)

**Variable Labels**: See `config/derived_variables.yaml` lines 305-330

## Missing Data Handling

### Overview

The transformation system includes systematic missing data handling to ensure "Prefer not to answer" and "Don't know" responses are properly converted to `NA` before calculating composite scores. This prevents invalid values (like 99, -99, 999) from contaminating derived variables.

**Critical Issue Resolved (October 2025):** Prior to implementation of `recode_missing()`, caregiver ACE variables had "Prefer not to answer" responses coded as 99, which were being summed in `ace_total` calculations. This created invalid scores ranging from 99-990 instead of the valid 0-10 range, affecting 254+ records (5.2% of dataset with ACE data). The `recode_missing()` helper function was added to systematically prevent this class of errors.

### `recode_missing(x, missing_codes = c(99, -99, 999, -999, 9999, -9999, 9))`

**Systematic missing value recoding function** that converts sentinel missing value codes to `NA` before transformations.

**Parameters**:
- `x`: Vector of values (numeric or character)
- `missing_codes`: Vector of codes to convert to NA (default: common missing codes)

**Returns**: Vector with missing codes replaced by `NA`

**Common Missing Value Codes**:
- `99`: "Prefer not to answer" (most common)
- `9`: "Don't know"
- `-99`, `999`, `9999`: Alternative missing codes used in some variables
- `-999`, `-9999`: Extreme missing codes

**Usage**:
```r
# Basic usage - recode 99 to NA
clean_values <- recode_missing(raw_values, missing_codes = c(99))

# Multiple missing codes
clean_values <- recode_missing(raw_values, missing_codes = c(99, 9, -99))

# Default covers common patterns
clean_values <- recode_missing(raw_values)
```

**Character Handling**: Automatically converts numeric characters ("99") to numeric before recoding

### Variables with Missing Data Codes

**Caregiver ACEs (cace1-10)**: Use 99 = "Prefer not to answer"
```r
# Example: Before recoding
ace_neglect = c(0, 1, 1, 99, 0)  # 99 should be NA

# After recoding with recode_missing()
ace_neglect = c(0, 1, 1, NA, 0)  # Properly coded
```

**Frequency of "Prefer not to answer" in NE25 Data**:
| Variable | Description | Count of 99 |
|----------|-------------|-------------|
| cace1 | Neglect | 72 |
| cace2 | Parent loss | 71 |
| cace3 | Mental illness | 83 |
| cace4 | Substance use | 93 |
| cace5 | Domestic violence | 93 |
| cace6 | Incarceration | 91 |
| cace7 | Verbal abuse | 76 |
| cace8 | Physical abuse | 73 |
| cace9 | Emotional neglect | 59 |
| cace10 | Sexual abuse | 58 |
| **TOTAL** | | **769** |

**Other Variables**: Most other variables either have no missing codes or handle missing through factor levels (e.g., childcare variables use "Missing" as a factor level for value 9).

### Composite Score Calculation with Missing Data

All composite scores use `na.rm = FALSE` in `rowSums()` to preserve missingness:

```r
# ACE Total Score
ace_total <- rowSums(
  mental_health_df[ace_cols],
  na.rm = FALSE  # If ANY item is NA, total is NA
)
```

**Rationale for `na.rm = FALSE`**:
- **Preserves data quality**: If any ACE item is missing, we don't know the true total
- **Prevents misleading scores**: With `na.rm = TRUE`, someone who answered 1 item (score=1) and declined 9 items would have `ace_total = 1`, incorrectly suggesting low ACE burden when the true total is unknown
- **Conservative approach**: Marks incomplete data as missing rather than creating potentially misleading partial scores

### Impact Example: ACE Variables

**Before Fix** (invalid handling):
```r
# Person declined 5 ACE items (coded as 99) and answered 5 items (scored 0-1)
ace_neglect = 99         # Should be NA
ace_parent_loss = 1
ace_mental_illness = 99  # Should be NA
ace_substance_use = 0
ace_domestic_violence = 99  # Should be NA
# ... etc.

# WRONG calculation (without recode_missing):
ace_total = 99 + 1 + 99 + 0 + 99 + ... = 495  # Invalid!
```

**After Fix** (proper handling):
```r
# Same person with recode_missing() applied
ace_neglect = NA         # Properly recoded
ace_parent_loss = 1
ace_mental_illness = NA  # Properly recoded
ace_substance_use = 0
ace_domestic_violence = NA  # Properly recoded
# ... etc.

# CORRECT calculation (with recode_missing + na.rm=FALSE):
ace_total = NA  # Incomplete data, total is unknown
```

**Result**:
- Before: 254+ records had invalid `ace_total` scores (99-990)
- After: 0 records have invalid scores; 2,196 records properly have `ace_total = NA`

### Validation

To verify missing data is properly handled:

```r
# Check for persisting sentinel values in transformed data
library(dplyr)
library(duckdb)

conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Should return 0 for all ACE variables
dbGetQuery(conn, "
  SELECT
    COUNT(*) as invalid_records
  FROM ne25_transformed
  WHERE ace_total > 10
")

# Check NULL counts (people who declined or weren't asked)
dbGetQuery(conn, "
  SELECT
    COUNT(*) as null_records
  FROM ne25_transformed
  WHERE ace_total IS NULL
")
```

**Documentation**: See `docs/fixes/missing_data_audit_2025_10.md` for complete audit and validation results.

## Helper Functions

### `value_labels(lex, dict, varname = "lex_ne25")`

Extracts value labels from REDCap data dictionary for a specific variable.

**Parameters**:
- `lex`: Variable name in REDCap dictionary
- `dict`: REDCap data dictionary
- `varname`: Column name for variable identifier in output

**Returns**: Data frame with value codes and labels

**Usage**:
```r
# Get race value labels
race_labels <- value_labels("cqr010", redcap_dict)
# Output: data.frame with lex_ne25, value, label columns
```

### `cpi_ratio_1999(date_vector)`

**Simplified CPI adjustment function** (placeholder implementation).

**Current Implementation**: Returns 1.0 for all dates
**Full Implementation**: Would download CPI data from FRED API

### `get_poverty_threshold(dates, family_size)`

**Federal poverty threshold lookup** based on family size.

**Implementation**: Uses 2024 poverty thresholds:
```r
thresholds <- c(15060, 20440, 25820, 31200, 36580, 41960, 47340, 52720)
# For family sizes 1-8, defaults to family of 4 ($31,200) for larger families
```

## Data Flow Architecture

### Complete Transformation Pipeline

```r
# 1. Load raw data and dictionary
raw_data <- extract_redcap_data()
redcap_dict <- load_redcap_dictionary()

# 2. Apply all transformations
transformed_data <- recode_it(raw_data, redcap_dict)

# 3. Result: Original 588 columns + 21 derived variables
# Total: 609 columns with proper factor levels and labels
```

### Incremental Transformation

```r
# Apply transformations incrementally
base_data <- raw_data

# Step 1: Inclusion eligibility
base_data <- base_data %>%
  left_join(recode_it(raw_data, dict, what = "include"), by = c("pid", "record_id"))

# Step 2: Demographics
base_data <- base_data %>%
  left_join(recode_it(raw_data, dict, what = "race"), by = c("pid", "record_id")) %>%
  left_join(recode_it(raw_data, dict, what = "sex"), by = c("pid", "record_id"))

# Step 3: Socioeconomic variables
base_data <- base_data %>%
  left_join(recode_it(raw_data, dict, what = "education"), by = c("pid", "record_id")) %>%
  left_join(recode_it(raw_data, dict, what = "income"), by = c("pid", "record_id"))
```

## Integration with Pipeline

### Usage in NE25 Pipeline

```r
# In pipelines/orchestration/ne25_pipeline.R

# After raw data extraction and harmonization
message("Applying dashboard transformations...")
transformed_data <- recode_it(
  dat = harmonized_data,
  dict = combined_dictionary,
  what = "all"
)

# Result: 588 original + 99 derived = 687 total variables
message(sprintf("Transformation complete: %d variables → %d variables",
                ncol(harmonized_data), ncol(transformed_data)))
```

### Error Handling

The `recode_it()` function includes comprehensive error handling:

```r
# Individual transformation errors are caught and logged
tryCatch({
  recode_result <- recode__(dat = dat, dict = dict, what = v)
  if(!is.null(recode_result)) {
    recoded_dat <- recoded_dat %>%
      dplyr::left_join(recode_result, by = c("pid", "record_id"))
  }
}, error = function(e) {
  message(paste("Warning: Failed to process", v, ":", e$message))
})
```

**Benefits**:
- Pipeline continues even if individual transformations fail
- Clear error messages identify problematic transformations
- Partial results are still returned for successful transformations

## Factor Level Management

### Reference Level Setting

All categorical variables have meaningful reference levels set for statistical analysis:

```r
# Race/ethnicity: Reference = majority group
hisp: "non-Hisp." (reference)
race: "White" (reference)
raceG: "White, non-Hisp." (reference)

# Education: Reference = college degree
educ_max: "Bachelor's degree" (reference)
educ4_max: "College Degree" (reference)
educ6_max: "Bachelor's Degree" (reference)

# Income: Reference = highest income group
fplcat: "400+% FPL" (reference)

# Sex: Reference = female
sex: "Female" (reference)
```

### Label Management

Variable labels are applied using the `labelled` package for enhanced metadata:

```r
# Check variable labels
library(labelled)
var_label(transformed_data$eligible)  # "Meets study inclusion criteria"
var_label(transformed_data$raceG)     # "Child race/ethnicity combined"
var_label(transformed_data$educ4_max) # "Maximum education level among caregivers (4 categories)"
```

## Performance Characteristics

### Typical Execution Times

For NE25 dataset (3,906 records):
- **Include transformation**: ~0.1 seconds
- **Race transformation**: ~2.5 seconds (complex pivoting)
- **Education transformation**: ~1.8 seconds (multiple category mappings)
- **Complete pipeline**: ~5-7 seconds total

### Memory Usage

- **Input**: ~45 MB (588 columns × 3,906 rows)
- **Output**: ~48 MB (609 columns × 3,906 rows)
- **Peak**: ~65 MB during transformation processing

## Quality Checks

### Validation Steps

```r
# Check transformation success
validate_transformations <- function(original_data, transformed_data) {
  # 1. Record count preservation
  stopifnot(nrow(original_data) == nrow(transformed_data))

  # 2. Key columns preserved
  stopifnot(all(c("pid", "record_id") %in% names(transformed_data)))

  # 3. Expected derived variables present
  derived_vars <- c("eligible", "authentic", "include", "hisp", "race", "raceG",
                   "a1_hisp", "a1_race", "a1_raceG", paste0("educ", c("", "4", "6"),
                   rep(c("_max", "_a1", "_a2", "_mom"), each = 3)))
  missing_vars <- setdiff(derived_vars, names(transformed_data))
  if(length(missing_vars) > 0) {
    warning("Missing derived variables: ", paste(missing_vars, collapse = ", "))
  }

  # 4. Factor levels properly set
  if("raceG" %in% names(transformed_data)) {
    stopifnot(levels(transformed_data$raceG)[1] == "White, non-Hisp.")
  }
}

# Run validation
validate_transformations(raw_data, transformed_data)
```

### Common Issues and Solutions

**Issue**: Education transformation fails due to missing relationship variables
**Solution**: Education transformation internally calls caregiver relationship transformation

**Issue**: Factor levels not properly ordered
**Solution**: Use `relevel_it = TRUE` (default) to set appropriate reference levels

**Issue**: Variable labels not applied
**Solution**: Ensure `labelled` package is installed and `add_labels = TRUE` (default)

**Issue**: Income calculation errors due to missing dates
**Solution**: CPI adjustment function handles missing dates gracefully

## Development Guidelines

### Adding New Transformations

1. **Create transformation logic** in `recode__()` function:
```r
if(what == "new_transformation") {
  new_vars_df <- dat %>%
    select(pid, record_id, input_vars) %>%
    mutate(
      new_var1 = transformation_logic1,
      new_var2 = transformation_logic2
    )

  # Add labels
  if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
    labelled::var_label(new_vars_df$new_var1) <- "Description of new_var1"
    labelled::var_label(new_vars_df$new_var2) <- "Description of new_var2"
  }

  recodes_df <- new_vars_df
}
```

2. **Add to master function** in `recode_it()`:
```r
if(what == "all") {
  vars <- c("include", "race", "caregiver relationship", "education",
           "sex", "age", "income", "geographic", "mental health", "childcare",
           "new_transformation")
}
```

3. **Update configuration** in `config/derived_variables.yaml`:
```yaml
all_derived_variables:
  # ... existing variables
  - new_var1
  - new_var2

variable_labels:
  new_var1: "Description of new_var1"
  new_var2: "Description of new_var2"
```

4. **Test transformation**:
```r
# Test individual transformation
test_result <- recode_it(sample_data, dict, what = "new_transformation")

# Test integration with full pipeline
full_result <- recode_it(sample_data, dict, what = "all")
```

### Code Style Guidelines

1. **Consistent naming**: Use underscore_case for all variable names
2. **Clear labels**: Provide descriptive variable labels for all derived variables
3. **Reference levels**: Set meaningful reference levels for all factors
4. **Error handling**: Use `tryCatch()` for robust transformation logic
5. **Documentation**: Comment complex transformation logic
6. **Validation**: Include data validation checks for new transformations

## Related Documentation

- **Pipeline Integration**: `pipelines/orchestration/README.md`
- **Derived Variables Config**: `config/README.md` (derived_variables.yaml section)
- **Python Metadata Generation**: `pipelines/python/README.md`
- **Database Storage**: `python/db/README.md`
- **Data Dictionary**: `docs/data_dictionary/ne25/README.md`

---

*Last Updated: September 17, 2025*
*Version: 2.1.0 - Comprehensive transformation documentation*
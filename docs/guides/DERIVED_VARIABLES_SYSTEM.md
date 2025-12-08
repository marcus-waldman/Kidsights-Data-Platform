# Derived Variables System

**Last Updated:** October 2025

This document provides comprehensive documentation for the derived variables system in the Kidsights Data Platform. The NE25 pipeline creates 99 derived variables from raw REDCap survey data using the `recode_it()` transformation framework.

---

## Table of Contents

1. [Overview](#overview)
2. [Variable Categories](#variable-categories)
3. [Configuration System](#configuration-system)
4. [Transformation Pipeline](#transformation-pipeline)
5. [Documentation Generation](#documentation-generation)
6. [Adding New Variables](#adding-new-variables)

---

## Overview

### What are Derived Variables?

**Derived variables** are variables created through transformation of raw survey data. They include:
- **Recoded variables:** Collapsing response categories (e.g., 8-category → 4-category education)
- **Computed variables:** Calculating new values (e.g., age in years from age in days)
- **Composite scores:** Summing item responses (e.g., PHQ-2 total from 2 depression items)
- **Categorical indicators:** Creating binary/categorical flags (e.g., PHQ-2 positive screen)
- **Geocoded variables:** Translating ZIP codes to geographic units

### The recode_it() Framework

All derived variables are created using the **`recode_it()`** function in `R/transform/ne25_transforms.R`.

**Key features:**
- **Systematic transformation:** Consistent patterns across all variables
- **Missing data handling:** Defensive recoding of sentinel values (99, 9, etc.)
- **Type preservation:** Maintains appropriate data types (factor, numeric, character)
- **Label preservation:** Keeps variable and value labels for analysis

### Total Count: 99 Derived Variables

The NE25 pipeline creates **99 derived variables** organized into 10 categories:

| Category | Count | Examples |
|----------|-------|----------|
| Eligibility | 3 | eligible, authentic, include |
| Race/Ethnicity | 6 | race, raceG, hisp |
| Education | 12 | educ_max_8cat, educ_a1_4cat |
| Income/FPL | 6 | fpl, fplcat, family_size |
| Mental Health (PHQ-2) | 5 | phq2_total, phq2_positive |
| Mental Health (GAD-2) | 5 | gad2_total, gad2_positive |
| Caregiver ACEs | 12 | ace_total, ace_risk_cat |
| Child ACEs | 10 | child_ace_total, child_ace_risk_cat |
| Childcare | 21 | cc_access, cc_weekly_cost |
| Geographic | 25 | county, puma, urban_rural |

**Note:** See `config/derived_variables.yaml` for complete variable list with definitions.

---

## Variable Categories

### 1. Eligibility Variables (3)

**Purpose:** Determine which records are included in analysis based on 8 criteria (CID1-7 + completion).

| Variable | Type | Description |
|----------|------|-------------|
| `eligible` | Factor (3 levels) | Overall eligibility status (Eligible, Ineligible, Uncertain) |
| `authentic` | Logical | Passes authenticity checks (CID6: not duplicate/suspicious) |
| `include` | Logical | Final inclusion flag (eligible AND authentic) |

**Criteria:**
- **CID1:** Nebraska resident
- **CID2:** Child age 0-5 years
- **CID3:** English or Spanish speaker
- **CID4:** Not institutionalized
- **CID5:** Biological/adoptive/foster parent
- **CID6:** Authentic response (not duplicate/spam)
- **CID7:** Consent provided
- **CID8 (removed):** Previously IRT-based quality check (now removed for stability)
- **Completion:** Survey >50% complete

**Documentation:** See `docs/ne25_eligibility_criteria.md` for detailed criteria definitions.

---

### 2. Race/Ethnicity Variables (6)

**Purpose:** Harmonize race/ethnicity to standard 7-category classification.

| Variable | Type | Categories | Description |
|----------|------|------------|-------------|
| `hisp` | Factor (2) | Hispanic, Not Hispanic | Hispanic ethnicity |
| `race` | Factor (7) | AIAN, Asian, Black, NHOPI, White, Multiracial, Other | Race (7 categories) |
| `raceG` | Factor (5) | AIAN/NHOPI, Asian, Black, White, Multiracial/Other | Grouped race (5 categories) |
| `a1_hisp` | Factor (2) | Hispanic, Not Hispanic | Adult 1 Hispanic ethnicity |
| `a1_race` | Factor (7) | (same as race) | Adult 1 race |
| `a1_raceG` | Factor (5) | (same as raceG) | Adult 1 grouped race |

**Mapping:** Census OMB race/ethnicity categories

**Note:** `a1_*` variables are for primary caregiver demographics.

---

### 3. Education Variables (12)

**Purpose:** Multiple categorizations of education level for flexibility in analysis.

**Pattern:** 4 education sources × 3 category schemes = 12 variables

**Education sources:**
- `educ_max` - Maximum education across all adults in household
- `educ_a1` - Adult 1 (primary caregiver) education
- `educ_a2` - Adult 2 (secondary caregiver) education
- `educ_mom` - Mother's education (if available)

**Category schemes:**
- **8-category:** Less than HS, HS/GED, Some college, Associate's, Bachelor's, Master's, Professional, Doctorate
- **4-category:** Less than HS, HS/GED, Some college/Associate's, Bachelor's or higher
- **6-category:** Hybrid scheme (varies by source)

**Examples:**
- `educ_max_8cat` - Maximum household education (8 categories)
- `educ_a1_4cat` - Adult 1 education (4 categories)
- `educ_mom_6cat` - Mother's education (6 categories)

---

### 4. Income/Federal Poverty Level Variables (6)

**Purpose:** Calculate federal poverty level (FPL) percentage for economic analysis.

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `income` | Numeric | 0-∞ | Annual household income (dollars) |
| `inc99` | Factor | Income brackets + "Prefer not to answer" | Income with missing preserved |
| `family_size` | Numeric | 1-99 | Household size (adults + children + 1) |
| `federal_poverty_threshold` | Numeric | $-$$ | FPL threshold for family size (2025 guidelines) |
| `fpl` | Numeric | 0-∞ | Income as % of FPL (income / threshold × 100) |
| `fplcat` | Factor (5) | <100%, 100-199%, 200-299%, 300-399%, ≥400% | FPL categories |
| `fpl_derivation_flag` | Logical | TRUE/FALSE | Indicates if FPL was derived vs directly reported |

**Formula:** `fpl = (income / federal_poverty_threshold) × 100`

**Example:**
- Family of 4 with income $50,000
- 2025 FPL threshold for family of 4 = $31,200
- FPL = ($50,000 / $31,200) × 100 = 160.3% → "100-199%" category

---

### 5. Mental Health - PHQ-2 Variables (5)

**Purpose:** Depression screening using 2-item Patient Health Questionnaire.

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `phq2_interest` | Numeric | 0-3 | Little interest or pleasure in doing things |
| `phq2_depressed` | Numeric | 0-3 | Feeling down, depressed, or hopeless |
| `phq2_total` | Numeric | 0-6 | Sum of 2 items (na.rm = FALSE) |
| `phq2_positive` | Logical | TRUE/FALSE | Positive screen (total ≥ 3) |
| `phq2_risk_cat` | Factor (3) | None (0-2), Mild (3-4), Moderate-Severe (5-6) | Risk categorization |

**Scoring:**
- **0-2:** Minimal depression symptoms
- **3-6:** Positive screen, warrants further assessment

**Missing data:** If ANY item is NA, total is NA (conservative approach)

---

### 6. Mental Health - GAD-2 Variables (5)

**Purpose:** Anxiety screening using 2-item Generalized Anxiety Disorder scale.

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `gad2_nervous` | Numeric | 0-3 | Feeling nervous, anxious, or on edge |
| `gad2_worry` | Numeric | 0-3 | Not being able to stop or control worrying |
| `gad2_total` | Numeric | 0-6 | Sum of 2 items (na.rm = FALSE) |
| `gad2_positive` | Logical | TRUE/FALSE | Positive screen (total ≥ 3) |
| `gad2_risk_cat` | Factor (3) | None (0-2), Mild (3-4), Moderate-Severe (5-6) | Risk categorization |

**Scoring:**
- **0-2:** Minimal anxiety symptoms
- **3-6:** Positive screen, warrants further assessment

**Missing data:** If ANY item is NA, total is NA (conservative approach)

---

### 7. Caregiver ACEs Variables (12)

**Purpose:** Adverse Childhood Experiences for primary caregiver.

**Individual ACE items (10):**
- `ace_neglect` - Emotional/physical neglect
- `ace_parent_loss` - Parent loss (divorce/death/separation)
- `ace_mental_illness` - Household mental illness
- `ace_substance_use` - Household substance abuse
- `ace_domestic_violence` - Witnessed domestic violence
- `ace_incarceration` - Household member incarcerated
- `ace_verbal_abuse` - Verbal/emotional abuse
- `ace_physical_abuse` - Physical abuse
- `ace_emotional_neglect` - Emotional neglect
- `ace_sexual_abuse` - Sexual abuse

**Summary variables (2):**
- `ace_total` - Sum of 10 ACE items (0-10, na.rm = FALSE)
- `ace_risk_cat` - Factor (4 levels): None (0), Low (1-2), Moderate (3-4), High (5+)

**Missing data:** Defensive recoding of 99 ("Prefer not to answer") before calculation.

---

### 8. Child ACEs Variables (10)

**Purpose:** Adverse Childhood Experiences for focal child.

**Individual ACE items (8):**
- `child_ace_parent_divorce` - Parent divorce/separation
- `child_ace_parent_death` - Parent death
- `child_ace_parent_jail` - Parent incarceration
- `child_ace_domestic_violence` - Witnessed domestic violence
- `child_ace_neighborhood_violence` - Witnessed neighborhood violence
- `child_ace_mental_illness` - Household mental illness
- `child_ace_substance_use` - Household substance abuse
- `child_ace_discrimination` - Experienced discrimination

**Summary variables (2):**
- `child_ace_total` - Sum of 8 ACE items (0-8, na.rm = FALSE)
- `child_ace_risk_cat` - Factor (4 levels): None (0), Low (1-2), Moderate (3-4), High (5+)

**Comparison to caregiver ACEs:** Child ACEs are current/recent, caregiver ACEs are retrospective.

---

### 9. Childcare Variables (21)

**Purpose:** Childcare access, costs, quality, and subsidy receipt.

**Access indicators (5):**
- Formal care usage (center, home-based)
- Informal care usage (family, friends)
- Care intensity (hours per week)
- Primary care type
- Multiple care arrangements

**Cost variables (8):**
- Weekly cost by type (center, home, informal)
- Total weekly cost
- Annual cost estimates
- Cost burden (% of income)

**Quality indicators (4):**
- Provider licensing status
- Accreditation
- Staff credentials
- Parent satisfaction

**Subsidy/Support (4):**
- Subsidy receipt (CCDF, vouchers)
- Family financial support
- Employer support
- Any support (composite)

**Note:** Many childcare variables have Factor level "Missing" for non-applicable cases.

---

### 10. Geographic Variables (25)

**Purpose:** Translate ZIP codes to various geographic units for spatial analysis.

See [GEOGRAPHIC_CROSSWALKS.md](GEOGRAPHIC_CROSSWALKS.md) for complete documentation.

**Geographic units (11):**
- PUMA (Public Use Microdata Area)
- County (FIPS code)
- Census Tract
- CBSA (Core-Based Statistical Area / metro area)
- Urban/Rural classification
- School district
- State legislative district (lower house)
- State legislative district (upper house/senate)
- US Congressional district
- Native lands (AIANNH areas)

**Variable types:**
- Code variables (e.g., `county` = "31055")
- Name variables (e.g., `county_name` = "Douglas County")
- Allocation factor variables (e.g., `county_afact` = "0.75;0.25")

**Total:** 11 geographies × ~2.3 variables per geography = 25 variables

**Format:** Semicolon-separated for ZIP codes spanning multiple geographies.

---

## Joined External Scores (Not Part of 99 Derived Variables)

The NE25 pipeline also joins **externally computed scores** that are NOT derived variables. These scores are created through separate specialized workflows and integrated into the final dataset via **Step 6.7** if the corresponding database tables exist.

### GSED Person-Fit Scores (14 columns)

**Source:** Manual 2023 scale calibration workflow
**Table:** `ne25_kidsights_gsed_pf_scores_2022_scale`
**Joined in:** NE25 Pipeline Step 6.7 (conditional - only if table exists)
**Created by:** `calibration/ne25/manual_2023_scale/run_manual_calibration.R`

**Purpose:** Item response theory (IRT) trait estimates for 7 GSED developmental domains calibrated to the 2023 scale baseline using fixed-item calibration in Mplus.

**Method:**
- **Fixed-item calibration:** 171 items anchored to 2023 mirt parameters, 53 new items estimated
- **Graded response model (GRM):** Ordinal categorical IRT model for developmental/behavioral items
- **Sample:** 2,785 NE25 participants with ≥5 item responses
- **Person-fit scores:** Conditional trait estimates (theta) for each participant on each domain
- **CSEM:** Conditional standard error of measurement for person-specific measurement precision

**Variables Added (14 columns):**

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `kidsights_2022` | Numeric | -4 to +4 | Overall Kidsights developmental score (2022 scale) |
| `kidsights_2022_csem` | Numeric | 0 to +2 | Conditional SEM for overall score |
| `general_gsed_pf_2022` | Numeric | -4 to +4 | General GSED domain score |
| `general_gsed_pf_2022_csem` | Numeric | 0 to +2 | CSEM for general GSED |
| `feeding_gsed_pf_2022` | Numeric | -4 to +4 | Feeding domain score |
| `feeding_gsed_pf_2022_csem` | Numeric | 0 to +2 | CSEM for feeding |
| `externalizing_gsed_pf_2022` | Numeric | -4 to +4 | Externalizing problems score |
| `externalizing_gsed_pf_2022_csem` | Numeric | 0 to +2 | CSEM for externalizing |
| `internalizing_gsed_pf_2022` | Numeric | -4 to +4 | Internalizing problems score |
| `internalizing_gsed_pf_2022_csem` | Numeric | 0 to +2 | CSEM for internalizing |
| `sleeping_gsed_pf_2022` | Numeric | -4 to +4 | Sleeping domain score |
| `sleeping_gsed_pf_2022_csem` | Numeric | 0 to +2 | CSEM for sleeping |
| `social_competency_gsed_pf_2022` | Numeric | -4 to +4 | Social competency score |
| `social_competency_gsed_pf_2022_csem` | Numeric | 0 to +2 | CSEM for social competency |

**Coverage:** 2,831 participants (56.1% of eligible sample) have person-fit scores

**Technical Details:**
- **Parameterization:** Threshold parameters converted from mirt (τ_Mplus = -d_mirt)
- **Reverse coding:** Psychosocial items (PS*) converted from behavioral problems scale to developmental outcome scale
- **Missing handling:** Participants with <5 valid item responses excluded (see `ne25_too_few_items` table)
- **IRT interpretation:** Higher scores indicate better developmental outcomes

**Related Exclusion Flags (3 columns):**

The pipeline also joins item insufficiency exclusion flags from `ne25_too_few_items`:

| Variable | Type | Description |
|----------|------|-------------|
| `too_few_item_responses` | Logical | TRUE if <5 valid item responses |
| `n_kidsight_psychosocial_responses` | Numeric | Count of valid responses |
| `exclusion_reason` | Character | "Fewer than 5 responses" |

**Note:** These person-fit scores are **not derived variables** because they are:
1. Computed external to the NE25 pipeline via a separate Mplus workflow
2. Based on IRT trait estimation (not simple linear transformations)
3. Anchored to historical 2023 scale parameters (not independently estimated from NE25 data alone)
4. Conditionally joined only if the calibration tables exist in the database

**Documentation:** See [Manual 2023 Scale Calibration](../../irt_scoring/MANUAL_2023_SCALE_CALIBRATION.md) for complete workflow details.

---

## Configuration System

### config/derived_variables.yaml

**Purpose:** Machine-readable variable definitions for documentation and validation.

**Structure:**
```yaml
derived_variables:
  eligibility:
    eligible:
      type: "factor"
      levels: ["Eligible", "Ineligible", "Uncertain"]
      description: "Overall eligibility status based on 8 criteria"
      source_variables: ["cid1", "cid2", "cid3", "cid4", "cid5", "cid6", "cid7", "completion"]

  composite_variables:
    phq2_total:
      is_composite: true
      components: ["phq2_interest", "phq2_depressed"]
      valid_range: [0, 6]
      missing_policy: "na.rm = FALSE"
      defensive_recoding: "c(99, 9)"
      category: "Mental Health"
```

**Uses:**
- Auto-generate data dictionary
- Validate transformed data
- Document missing data policies
- Track variable dependencies

**Location:** `config/derived_variables.yaml`

---

### R/transform/ne25_transforms.R

**Purpose:** Implementation of all derived variable transformations.

**Structure:**
```r
# 1. Eligibility variables (lines 50-150)
# 2. Race/ethnicity variables (lines 151-250)
# 3. Education variables (lines 251-350)
# 4. Income/FPL variables (lines 351-450)
# 5. Mental health variables (lines 451-550)
# 6. ACE variables (lines 551-650)
# 7. Childcare variables (lines 651-750)
# 8. Geographic variables (lines 751-850)
```

**Key functions:**
- `recode_missing()` - Recode sentinel values to NA
- `recode_it()` - Main transformation orchestrator
- `labelled::var_label()` - Add variable labels
- `labelled::val_labels()` - Add value labels

**Testing:** Use sample data with sentinel values (99, 9) to verify transformations.

---

## Transformation Pipeline

### Step-by-Step Process

**1. Load raw data**
```r
dat <- REDCapR::redcap_read_oneshot(redcap_uri, token)$data
```

**2. Apply recode_it() transformation**
```r
source("R/transform/ne25_transforms.R")
transformed <- recode_it(dat)
```

**3. Validate derived variables**
```r
# Check for sentinel values
stopifnot(all(transformed$phq2_total <= 6, na.rm = TRUE))

# Check for valid ranges
stopifnot(all(transformed$ace_total <= 10, na.rm = TRUE))
```

**4. Save to Feather**
```r
arrow::write_feather(transformed, "transformed.feather")
```

**5. Load to database (Python)**
```bash
python pipelines/python/insert_transformed_data.py
```

---

## Documentation Generation

### Transformed Variables Documentation

**Only derived variables** appear in the transformed-variables documentation:
- `docs/data_dictionary/ne25/transformed-variables.html`
- `docs/data_dictionary/ne25/transformed-variables.qmd`

**Raw variables** appear in:
- `docs/data_dictionary/ne25/raw-variables.html`

**Generation:**
```bash
python scripts/documentation/generate_html_documentation.py
```

**Output includes:**
- Variable name and type
- Description and valid range
- Value labels (for factors)
- Sample size and missingness
- Source variables (for composites)

---

## Adding New Variables

### Checklist for New Derived Variables

**1. Implementation**
- [ ] Add transformation code to `R/transform/ne25_transforms.R`
- [ ] Apply `recode_missing()` for defensive recoding
- [ ] Use `na.rm = FALSE` for composite scores
- [ ] Add variable label with `labelled::var_label()`
- [ ] Test with sample data containing sentinel values

**2. Configuration**
- [ ] Add variable to `config/derived_variables.yaml`
- [ ] Document valid range and missing policy
- [ ] List component variables (for composites)

**3. Validation**
- [ ] Create validation query to check valid range
- [ ] Verify no sentinel values persist
- [ ] Document missing data patterns

**4. Documentation**
- [ ] Update derived variable count (currently 99)
- [ ] Add to appropriate category in this document
- [ ] Update composite variables table if applicable

**Detailed guide:** See [MISSING_DATA_GUIDE.md#creating-new-composite-variables](MISSING_DATA_GUIDE.md#creating-new-composite-variables)

---

## Related Documentation

- **Missing Data Guide:** [MISSING_DATA_GUIDE.md](MISSING_DATA_GUIDE.md) - Critical standards for derived variables
- **Geographic Crosswalks:** [GEOGRAPHIC_CROSSWALKS.md](GEOGRAPHIC_CROSSWALKS.md) - Geographic variable details
- **Transformation Code:** `R/transform/README.md` - Implementation documentation
- **Configuration:** `config/derived_variables.yaml` - Machine-readable definitions

---

*Last Updated: October 2025*

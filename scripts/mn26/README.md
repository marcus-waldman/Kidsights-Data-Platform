# MN26 Sample Monitoring Scripts

Scripts for NORC researchers to monitor Minnesota 2026 (MN26) study recruitment progress and demographic distribution during data collection.

## Current Status

**TEMPLATE MODE**: These scripts currently use **NE25 data as a template** to demonstrate functionality. Once MN26 data collection begins, variables will need to be updated (marked with `[MN26 TODO]` comments throughout the code).

## Required REDCap API Access

**For Security/Data Governance:** The monitoring script requires access to the following **raw REDCap variables** through the API. These are the minimum variables needed for sample monitoring.

### Identifiers (Required)
- `pid` - Participant ID
- `record_id` - REDCap record ID

### Eligibility Screening (Required)
- `eq001` - Informed consent
- `eq002` - Primary caregiver status
- `eq003` - Parent/caregiver age (19+ years)
- `eqstate` - State residence (Minnesota for MN26, Nebraska for NE25 template)
- `age_in_days` - Child age in days (calculated from DOB by REDCap)

### Survey Completion Status (Required)
- `module_2_complete` - Module 2 completion status
- `module_3_complete` - Module 3 completion status
- `module_4_complete` - Module 4 completion status
- `module_5_complete` - Module 5 completion status
- `module_6_complete` - Module 6 completion status
- `module_7_complete` - Module 7 completion status
- `module_9_complete` - Module 9 completion status

**Note:** Module list may change for MN26 depending on final questionnaire structure.

### Child Demographics (Required)
- `age_in_days` - Child age (already listed above)
- `cqr009` - Child sex

### Parent/Caregiver Demographics (Required)
- `cqr002` - Respondent sex/gender
- `cqr003` - Respondent age in years
- `cqr004` - Respondent education level (8 categories)
- `sq002_*` - Respondent race (checkbox variables):
  - `sq002___1` through `sq002___15` (all race checkbox fields)
- `sq003` - Respondent Hispanic/Latino ethnicity
- `cqfa001` - Marital status

### Variable Count Summary
- **Total raw variables needed:** 28 variables
  - Identifiers: 2
  - Eligibility: 5
  - Survey completion: 7
  - Child demographics: 2 (1 overlap with eligibility)
  - Parent demographics: 19 (race checkboxes + 4 other demographics)

**[MN26 TODO]**: Verify these variable names match the MN26 REDCap data dictionary once finalized. Variable names may differ between studies.

### Important Note on Data Transformations

The current monitoring script **assumes access to transformed/derived variables** (e.g., `years_old`, `sex`, `a1_raceG`, `educ_a1`) from the Kidsights transformation pipeline.

**If NORC only has API access to raw REDCap variables**, the script will need modifications to include transformation logic for:

1. **Child sex** (`cqr009` → `sex` factor with "Female"/"Male" labels)
2. **Child age** (`age_in_days` → `years_old` = age_in_days / 365.25)
3. **Parent sex** (`cqr002` → `female_a1` boolean)
4. **Parent race/ethnicity** (`sq002_*` + `sq003` → `a1_raceG` combined race/ethnicity)
5. **Parent education** (`cqr004` → `educ_a1` with proper factor labels)
6. **Marital status** (`cqfa001` → labeled factor)

These transformations are currently handled by the `recode_it()` function in `R/transform/ne25_transforms.R`. The monitoring script can either:

**Option A**: NORC runs the full transformation pipeline before monitoring (requires more setup)
**Option B**: Add simplified transformation logic directly in the monitoring script (more standalone)

Contact Marcus Waldman to determine which approach fits NORC's workflow best.

## API Credentials Management

### CSV File Structure

The monitoring script uses a **CSV file** to manage REDCap API credentials, following the same pattern as the NE25 pipeline.

**Template:** `mn26_redcap_api_template.csv`

**Required Columns:**
- `project`: Descriptive project name (e.g., "mn26_main_survey")
- `pid`: REDCap project ID number (e.g., 7679)
- `api_code`: REDCap API token (long alphanumeric string)

**Example CSV:**
```csv
project,pid,api_code
mn26_main_survey,7679,ABC123XYZ456DEF789...
mn26_follow_up,8014,GHI012JKL345MNO678...
```

**Security Notes:**
- ⚠️ **NEVER commit this CSV file to git** (it contains sensitive API tokens)
- Store in a secure location outside the repository (e.g., `C:/Users/YOUR_USERNAME/my-APIs/`)
- The `.gitignore` is configured to exclude all CSV files with "api" in the name
- Each collaborator maintains their own local CSV file

### Multiple Projects

If MN26 has multiple REDCap projects (e.g., main survey, follow-up, email registration), add them as separate rows in the CSV:

```csv
project,pid,api_code
mn26_main_survey,7679,TOKEN_1_HERE
mn26_email_registration,7943,TOKEN_2_HERE
mn26_follow_up,8014,TOKEN_3_HERE
```

The monitoring script will automatically combine data from all projects.

### Simple Function Call

Just pass the CSV path directly to the function - no environment variables or config files needed:

```r
monitoring_data <- generate_monitoring_report(csv_path = "C:/path/to/your/credentials.csv")
```

That's it!

## Files

- `monitoring_report.R` - Main standalone script for generating monitoring reports
- `mn26_redcap_api_template.csv` - Template for API credentials CSV file
- `../config/sources/mn26.yaml` - MN26 study configuration file

## Quick Start

### 1. Create API Credentials CSV

Create a CSV file with your REDCap API credentials (use `mn26_redcap_api_template.csv` as a template):

**CSV Format:**
```csv
project,pid,api_code
mn26_main_survey,7679,ABC123XYZ456...
```

**Columns:**
- `project`: Project name (descriptive identifier)
- `pid`: REDCap project ID number
- `api_code`: REDCap API token for that project

**Save securely** (NOT in git repository):
```
C:/Users/YOUR_USERNAME/my-APIs/mn26_redcap_api.csv
```

### 2. Run the Monitoring Report

```r
# Load the script
source("scripts/mn26/monitoring_report.R")

# Generate monitoring report (pass CSV path)
monitoring_data <- generate_monitoring_report(
  csv_path = "C:/Users/YOUR_USERNAME/my-APIs/mn26_redcap_api.csv"
)

# Explore the results
View(monitoring_data$screener_status)
View(monitoring_data$eligibility)
View(monitoring_data$survey_completion)
View(monitoring_data$child_demographics)
View(monitoring_data$parent_demographics)
```

**Optional:** Specify a different REDCap URL (defaults to Nebraska URL):
```r
monitoring_data <- generate_monitoring_report(
  csv_path = "C:/path/to/mn26_api.csv",
  redcap_url = "https://redcap.umn.edu/api/"  # Minnesota REDCap URL
)
```

## Output Data Frames

The `generate_monitoring_report()` function returns a list with 5 data frames:

### 1. Screener Status
Tracks whether eligibility has been determined for each participant.

**Columns:**
- `pid`: Participant ID
- `record_id`: REDCap record ID
- `screener_complete`: TRUE if eligibility is known
- `screener_status`: "Complete" or "Incomplete"

**Example:**
```r
table(monitoring_data$screener_status$screener_status)
# Complete   Incomplete
#   2,645         1,263
```

### 2. Eligibility
Tracks the 4 eligibility criteria and overall eligibility determination.

**Columns:**
- `pid`, `record_id`: Identifiers
- `parent_age_eligible`: Parent age >= 19
- `child_age_eligible`: Child age 0-5 years
- `primary_caregiver_eligible`: Respondent is primary caregiver
- `state_eligible`: Participant lives in Minnesota
- `eligible`: Overall eligibility (all 4 criteria must be TRUE)

**Example:**
```r
# Overall eligibility summary
table(monitoring_data$eligibility$eligible)
# FALSE  TRUE
#  1,263  2,645

# Breakdown by criterion
colSums(monitoring_data$eligibility[, 3:6], na.rm = TRUE)
```

### 3. Survey Completion
Tracks whether all required survey modules have been completed.

**Columns:**
- `pid`, `record_id`: Identifiers
- `survey_complete`: TRUE if all required modules complete
- `survey_status`: "Complete" or "Incomplete"

**Example:**
```r
table(monitoring_data$survey_completion$survey_status)
# Complete   Incomplete
#   1,842         2,066
```

### 4. Child Demographics
Age and sex for each child participant.

**Columns:**
- `pid`, `record_id`: Identifiers
- `age_years`: Child's age in years (0-5)
- `sex`: Child's sex (Female/Male)

**Example:**
```r
# Age distribution
summary(monitoring_data$child_demographics$age_years)
hist(monitoring_data$child_demographics$age_years,
     main = "Child Age Distribution",
     xlab = "Age (years)")

# Sex distribution
table(monitoring_data$child_demographics$sex)
```

### 5. Parent Demographics
Demographics for the primary caregiver (respondent).

**Columns:**
- `pid`, `record_id`: Identifiers
- `age_years`: Primary caregiver age in years
- `female`: TRUE if female, FALSE if male
- `race_ethnicity`: Race/ethnicity (combined categories)
- `education`: Education level (8 categories)
- `marital_status`: Marital status code (1-6)
- `marital_status_label`: Marital status label ("Married", "Divorced", etc.)

**Example:**
```r
# Age distribution
summary(monitoring_data$parent_demographics$age_years)

# Sex distribution
table(monitoring_data$parent_demographics$female)

# Race/ethnicity distribution
table(monitoring_data$parent_demographics$race_ethnicity)

# Education distribution
table(monitoring_data$parent_demographics$education)

# Marital status distribution
table(monitoring_data$parent_demographics$marital_status_label)
```

## Eligibility Criteria

The script implements the 4 eligibility criteria identified by Kanru:

1. **Parent Age**: Respondent must be 19 years of age or older
2. **Child Age**: Child must be 0-5 years old (calculated from date of birth)
3. **Primary Caregiver**: Respondent must be a primary caregiver for the child
4. **State Residence**: Respondent and child must currently live in Minnesota

**Screener Completion**: Determined by whether eligibility is known (not missing). If all 4 criteria have been answered, screener is "Complete".

## Survey Completion

**Current Logic** (from NE25 template):
- Survey is "Complete" if modules 2, 3, 4, 5, 6, 7, and 9 are all marked as complete (REDCap status = 2)
- Module 8 is excluded (follow-up data)

**[MN26 TODO]**: Update module list to match MN26 survey structure once questionnaire is finalized.

## Adapting for MN26 Data

When MN26 data collection begins, update the following sections (search for `[MN26 TODO]` comments):

### 1. REDCap API Configuration
```r
# In pull_redcap_data() function
redcap_uri <- "YOUR_MN26_REDCAP_URL"  # Update to MN26 project URL
```

### 2. Eligibility Variable Names
```r
# In calculate_eligibility() function
# Update these variable names to match MN26 data dictionary:
eq003    # Parent age >= 19 question
age_in_days  # Child age calculation
eq002    # Primary caregiver question
eqstate  # Minnesota residence question (check state code!)
```

### 3. Survey Completion Modules
```r
# In calculate_survey_completion() function
# Update module list to match MN26 survey structure:
required_modules <- paste0("module_", c(...), "_complete")
```

### 4. Demographics Variable Names
```r
# In extract_child_demographics() and extract_parent_demographics()
# Verify these match MN26 transformed variable names:
years_old, sex, a1_years_old, female_a1, a1_raceG, educ_a1, cqfa001
```

### 5. Marital Status Response Options
```r
# In extract_parent_demographics()
# Update marital status labels to match MN26 questionnaire:
marital_status_label = dplyr::case_when(...)
```

### 6. Data Source
```r
# In generate_monitoring_report() function
# Replace NE25 database query with actual MN26 data transformation:
# - Remove database query for NE25 template
# - Add MN26 transformation pipeline call
# - Or use transformed_data from MN26 pipeline output
```

## Questions for Kanru (from email)

**Answered:**
- ✅ Eligibility questions confirmed (4 criteria: age 19+, child 0-5, primary caregiver, lives in MN)
- ✅ Screener completion = eligibility known/unknown

**Pending:**
- ❓ Will MN26 questionnaire change the eligibility questions?
- ❓ What defines "survey completion" for MN26? (Same module-based logic or different criteria?)

## Contact

For questions about adapting this script for MN26 data, contact Marcus Waldman.

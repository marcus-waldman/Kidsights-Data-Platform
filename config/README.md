# Configuration Documentation

This directory contains configuration files for the Kidsights Data Platform, including codebook validation rules, data source settings, and system parameters.

## Overview

The configuration system uses YAML files to define:
- **Codebook validation rules and response sets**
- **Data source configurations for pipelines**
- **Derived variables created by transformations**
- **System parameters and defaults**

## Configuration Files

### `codebook_config.yaml`

Comprehensive configuration for the JSON codebook system, including validation rules, response sets, and dashboard settings.

#### Structure Overview

```yaml
# File paths
paths:
  json_codebook: "codebook/data/codebook.json"
  csv_codebook: "codebook/data/codebook.csv"
  dashboard_output: "docs/codebook_dashboard"

# Validation rules
validation:
  required_fields: [...]
  domain_validation: {...}
  study_validation: {...}

# Standard response sets
response_sets: {...}

# Dashboard settings
dashboard: {...}

# IRT model configurations
irt_models: {...}

# CSV conversion settings
conversion: {...}
```

#### Validation Rules

##### Required Fields
```yaml
validation:
  required_fields:
    - "id"
    - "identifiers.kidsight"
    - "studies"
    - "classification.domain"
```

Defines mandatory fields that must be present in every codebook item.

##### Domain Validation
```yaml
domain_validation:
  valid_domains:
    - "socemo"                      # Social-emotional development
    - "motor"                       # Motor skills and physical development
    - "coglan"                      # Cognitive and language development
    - "psychosocial_problems_general"  # GSED_PF psychosocial items
    - "health"                      # HRTL health items from NSCH

  valid_hrtl_domains:
    - "social_emotional"
    - "motor"
    - "early_learning"
    - "self_regulation"
    - "health"
```

**Kidsights Domains:**
- Used for primary domain classification
- Each item must have a valid kidsights domain

**HRTL/CAHMI Domains:**
- Alternative classification system
- Optional for items with CAHMI study participation

##### Study Validation
```yaml
study_validation:
  valid_studies:
    - "NE25"        # Nebraska 2025 study
    - "NE22"        # Nebraska 2022 study
    - "NE20"        # Nebraska 2020 study
    - "CAHMI22"     # CAHMI 2022 study
    - "CAHMI21"     # CAHMI 2021 study
    - "ECDI"        # Early Childhood Development Index
    - "CREDI"       # Caregiver Reported Early Development Index
    - "GSED"        # Global Scales for Early Development
    - "GSED_PF"     # GSED Psychosocial Frequency (PS items)
```

Defines valid study names that items can participate in.

#### Response Sets

Reusable response option definitions to avoid duplication and ensure consistency.

##### Standard Binary
```yaml
response_sets:
  standard_binary:
    - value: 1
      label: "Yes"
    - value: 0
      label: "No"
    - value: -9
      label: "Don't Know"
      missing: true
```

Used for Yes/No questions with "Don't Know" option.

##### 5-Point Likert Scale
```yaml
likert_5:
  - value: 1
    label: "Never"
  - value: 2
    label: "Rarely"
  - value: 3
    label: "Sometimes"
  - value: 4
    label: "Often"
  - value: 5
    label: "Always"
```

Standard frequency scale for behavioral assessments.

##### PS Frequency Scale
```yaml
ps_frequency:
  - value: 0
    label: "Never or Almost Never"
  - value: 1
    label: "Sometimes"
  - value: 2
    label: "Often"
  - value: -9
    label: "Don't Know"
    missing: true
```

Specialized scale for GSED_PF psychosocial items.

#### Dashboard Settings

Configuration for the Quarto-based codebook dashboard.

```yaml
dashboard:
  title: "Kidsights Item Codebook"
  theme: "cosmo"
  items_per_page: 25
  export_formats: ["csv", "excel", "json"]

  # Color scheme for domains
  domain_colors:
    socemo: "#FF6B6B"      # Red
    motor: "#4ECDC4"       # Teal
    coglan: "#45B7D1"      # Blue
    default: "#95A5A6"     # Gray
```

**Settings:**
- **title**: Dashboard page title
- **theme**: Bootstrap theme for styling
- **items_per_page**: Pagination for large tables
- **export_formats**: Available data export options
- **domain_colors**: Color coding for visualizations

#### IRT Model Settings

Configuration for Item Response Theory parameters.

```yaml
irt_models:
  default_theta_range: [-4, 4]
  default_model_type: "2PL"

  supported_models:
    - "1PL"     # Rasch model
    - "2PL"     # Two-parameter logistic
    - "3PL"     # Three-parameter logistic
    - "GRM"     # Graded Response Model
    - "M2PL"    # Multidimensional 2PL
```

**Parameters:**
- **theta_range**: Ability parameter range for plots
- **default_model_type**: Default IRT model for analysis
- **supported_models**: Available IRT model types

#### Conversion Settings

Configuration for CSV-to-JSON conversion process.

```yaml
conversion:
  csv_encoding: "UTF-8"
  missing_values: ["", "NA", "NULL", "null"]

  # CSV column mappings
  csv_columns:
    jid: "id"
    lex_kidsight: "identifiers.kidsight"
    lex_ne25: "identifiers.ne25"
    # ... additional mappings
```

**Settings:**
- **csv_encoding**: Character encoding for CSV files
- **missing_values**: Values treated as missing data
- **csv_columns**: Mapping from CSV columns to JSON paths

### `derived_variables.yaml`

Configuration defining the 21 derived variables created by the recode_it() transformation process in the NE25 pipeline.

#### Structure Overview

```yaml
# Grouped configuration
derived_variables:
  include_eligibility:
    description: "Inclusion and eligibility variables"
    variables: [eligible, authentic, include]
    transformation: "include"

# Complete flat list for filtering
all_derived_variables:
  - eligible
  - authentic
  - include
  # ... 18 additional variables

# Human-readable labels
variable_labels:
  eligible: "Meets study inclusion criteria"
  authentic: "Passes authenticity screening"
  # ... additional labels

# Transformation categories
transformation_categories:
  include: "Inclusion and Eligibility"
  race: "Race and Ethnicity"
  education: "Education Levels"
```

#### Derived Variable Categories

##### **Inclusion and Eligibility (3 variables)**
```yaml
include_eligibility:
  variables:
    - eligible      # Meets study inclusion criteria
    - authentic     # Passes authenticity screening
    - include       # Combined inclusion + authenticity
```

These logical variables determine participant eligibility based on the 9 CID criteria.

##### **Race and Ethnicity (6 variables)**
```yaml
race_ethnicity:
  variables:
    - hisp, race, raceG           # Child race/ethnicity
    - a1_hisp, a1_race, a1_raceG  # Primary caregiver race/ethnicity
```

Harmonized race and ethnicity variables with collapsed categories for analysis.

##### **Education Levels (12 variables)**
```yaml
education_8_categories:
  variables: [educ_max, educ_a1, educ_a2, educ_mom]

education_4_categories:
  variables: [educ4_max, educ4_a1, educ4_a2, educ4_mom]

education_6_categories:
  variables: [educ6_max, educ6_a1, educ6_a2, educ6_mom]
```

Education variables with different category counts for various analysis needs:
- **8 categories**: Detailed educational attainment
- **4 categories**: Simplified for basic analysis
- **6 categories**: Intermediate level of detail

#### Usage in Python Scripts

```python
# Load derived variables configuration
import yaml
with open('config/derived_variables.yaml', 'r') as f:
    config = yaml.safe_load(f)

# Get all derived variable names
derived_vars = config['all_derived_variables']  # List of 21 variables

# Get variable labels
labels = config['variable_labels']
eligible_label = labels['eligible']  # "Meets study inclusion criteria"

# Filter metadata generation to derived variables only
python pipelines/python/generate_metadata.py \
  --source-table ne25_transformed \
  --derived-only \
  --derived-config config/derived_variables.yaml
```

#### Usage in R Scripts

```r
library(yaml)

# Load configuration
config <- read_yaml("config/derived_variables.yaml")

# Access derived variables by category
include_vars <- config$derived_variables$include_eligibility$variables
race_vars <- config$derived_variables$race_ethnicity$variables

# Get all derived variables
all_derived <- config$all_derived_variables

# Check if variable is derived
is_derived <- function(var_name) {
  return(var_name %in% config$all_derived_variables)
}

# Example usage
is_derived("eligible")    # TRUE
is_derived("record_id")   # FALSE
```

### `sources/ne25.yaml`

Configuration for the NE25 pipeline data extraction.

```yaml
redcap:
  url: "https://redcap.ucdenver.edu/api/"
  api_credentials_file: "C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv"

  projects:
    - name: "kidsights_data_survey"
      pid: 7679
      token_env: "KIDSIGHTS_API_TOKEN_7679"
    # ... additional projects

database:
  path: "C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB/kidsights.duckdb"

eligibility:
  criteria_count: 9
  required_cid_fields: ["cid1", "cid2", "cid3", "cid4", "cid5", "cid6", "cid7", "cid8", "cid9"]
```

## Usage Examples

### Loading Configuration

```r
library(yaml)

# Load codebook configuration
config <- read_yaml("config/codebook_config.yaml")

# Access response sets
binary_set <- config$response_sets$standard_binary
ps_set <- config$response_sets$ps_frequency

# Check valid domains
valid_domains <- config$validation$domain_validation$valid_domains
```

### Validation Usage

```r
# Validate domain
validate_domain <- function(domain) {
  valid_domains <- config$validation$domain_validation$valid_domains
  return(domain %in% valid_domains)
}

# Validate study
validate_study <- function(study) {
  valid_studies <- config$validation$study_validation$valid_studies
  return(study %in% valid_studies)
}

# Example usage
validate_domain("psychosocial_problems_general")  # TRUE
validate_study("GSED_PF")  # TRUE
validate_domain("invalid_domain")  # FALSE
```

### Response Set Access

```r
# Get response set definition
get_response_set <- function(set_name) {
  sets <- config$response_sets
  if (set_name %in% names(sets)) {
    return(sets[[set_name]])
  } else {
    warning("Response set '", set_name, "' not found")
    return(NULL)
  }
}

# Usage
ps_frequency <- get_response_set("ps_frequency")
print(ps_frequency)
```

## Adding New Configuration

### New Response Set

1. **Add to config:**
```yaml
response_sets:
  custom_scale:
    - value: 1
      label: "Low"
    - value: 2
      label: "Medium"
    - value: 3
      label: "High"
    - value: -9
      label: "Not Applicable"
      missing: true
```

2. **Add detection in conversion:**
```r
# In detect_response_set_or_parse()
if (str_detect(normalized, "1=low") && str_detect(normalized, "3=high")) {
  return("custom_scale")
}
```

### New Study

1. **Add to validation:**
```yaml
study_validation:
  valid_studies:
    - "NEW_STUDY_2025"
```

2. **Add column mapping:**
```yaml
csv_columns:
  lex_new_study: "identifiers.new_study"
```

3. **Update conversion logic:**
```r
study_mappings <- list(
  # ... existing mappings
  "NEW_STUDY_2025" = "lex_new_study"
)
```

### New Domain

1. **Add to validation:**
```yaml
domain_validation:
  valid_domains:
    - "new_development_area"
```

2. **Add color scheme:**
```yaml
dashboard:
  domain_colors:
    new_development_area: "#9B59B6"  # Purple
```

## Configuration Validation

The configuration files themselves can be validated:

```r
# Load and validate config
config <- read_yaml("config/codebook_config.yaml")

# Check required sections
required_sections <- c("validation", "response_sets", "dashboard")
missing_sections <- setdiff(required_sections, names(config))

if (length(missing_sections) > 0) {
  stop("Missing configuration sections: ", paste(missing_sections, collapse = ", "))
}

# Validate response sets structure
validate_response_sets <- function(sets) {
  for (set_name in names(sets)) {
    set_data <- sets[[set_name]]
    if (!is.list(set_data) || length(set_data) == 0) {
      warning("Invalid response set: ", set_name)
    }
  }
}

validate_response_sets(config$response_sets)
```

## Environment Variables

Some configurations reference environment variables for security:

```yaml
# In source configurations
projects:
  - name: "kidsights_data_survey"
    token_env: "KIDSIGHTS_API_TOKEN_7679"  # References env var
```

Set environment variables in `.env` file:
```bash
KIDSIGHTS_API_TOKEN_7679=your_api_token_here
```

## Best Practices

### Configuration Management
1. **Version Control**: Include all config files in git
2. **Documentation**: Comment complex configurations
3. **Validation**: Always validate configurations before use
4. **Environment**: Use environment variables for sensitive data

### Response Sets
1. **Consistency**: Use existing response sets when possible
2. **Missing Flags**: Mark missing/unknown values appropriately
3. **Ordering**: Order response options logically
4. **Labels**: Use clear, descriptive labels

### Validation Rules
1. **Comprehensive**: Cover all required fields
2. **Specific**: Use specific validation criteria
3. **Maintainable**: Keep validation rules updated with data changes
4. **Documented**: Document validation logic

## Troubleshooting

### Common Issues

**YAML parsing errors:**
```r
# Check YAML syntax
yaml::yaml.load_file("config/codebook_config.yaml")
```

**Missing response sets:**
```r
# Check available response sets
config <- read_yaml("config/codebook_config.yaml")
names(config$response_sets)
```

**Validation failures:**
```r
# Debug validation
valid_domains <- config$validation$domain_validation$valid_domains
print(valid_domains)
```

**File encoding issues:**
- Ensure YAML files are saved in UTF-8 encoding
- Check for invisible characters that break parsing

For more information, see the main documentation in `README.md` and `codebook/README.md`.
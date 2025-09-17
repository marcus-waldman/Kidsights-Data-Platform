# Codebook Conversion Scripts

This directory contains scripts for converting and maintaining the Kidsights JSON codebook system.

## Overview

The codebook conversion system transforms legacy CSV data and additional item sources into a comprehensive JSON-based codebook with 305 items from 8 studies.

## Files

### `initial_conversion.R`

Main conversion script that transforms the legacy CSV codebook and integrates additional study items into the JSON format.

### `update_ne22_irt_parameters.R`

Script to add empirical IRT parameter estimates from NE22 study calibration to the codebook JSON.

#### Key Functions

##### `update_ne22_irt_parameters(csv_path, codebook_path, output_path)`

Main function to update codebook with NE22 IRT parameter estimates from empirical calibration.

**Parameters:**
- `csv_path` (character): Path to NE22 parameter CSV file (default: "tmp/ne22_kidsights-parameter-vlaues.csv")
- `codebook_path` (character): Path to input codebook JSON (default: "codebook/data/codebook.json")
- `output_path` (character): Path for updated codebook (default: same as input)

**Input CSV Format:**
- `item`: Item identifier using kidsight lexicon (e.g., DD26, AA10)
- `name`: Parameter type - "a1" for loading, "d1"/"d2"/"d3" for thresholds
- `value`: Numeric parameter estimate

**Features:**
- Maps items using kidsight lexicon identifiers
- Validates NE22 study participation before updating
- Orders threshold parameters by d-suffix number (d1, d2, d3...)
- Sets factor to "kidsights" for unidimensional model
- Preserves existing constraints and other study parameters

**Example:**
```r
source("scripts/codebook/update_ne22_irt_parameters.R")

# Standard update
update_ne22_irt_parameters()

# Custom paths
update_ne22_irt_parameters(
  csv_path = "path/to/ne22_parameters.csv",
  codebook_path = "input/codebook.json",
  output_path = "output/updated_codebook.json"
)
```

**Output Structure:**
For item DD26 with parameters a1=1.166, d1=0.299, d2=-2.482, d3=-4.007:
```json
"irt_parameters": {
  "NE22": {
    "factors": ["kidsights"],
    "loadings": [1.166030995],
    "thresholds": [0.299360178, -2.481564743, -4.00652306],
    "constraints": []
  }
}
```

##### `load_ne22_parameters(csv_path)`

Loads and processes NE22 parameter CSV into structured format.

**Parameters:**
- `csv_path` (character): Path to CSV file

**Returns:**
- Data frame with columns: item, loading, thresholds (list), n_loadings, n_thresholds

**Processing:**
- Groups parameters by item identifier
- Extracts single a1 loading value per item
- Orders thresholds by numeric suffix (d1 < d2 < d3...)
- Validates parameter counts for quality control

##### `update_codebook_with_ne22(codebook_path, ne22_params)`

Updates codebook object with structured NE22 parameters.

**Parameters:**
- `codebook_path` (character): Path to codebook JSON
- `ne22_params` (data.frame): Structured parameters from load_ne22_parameters()

**Returns:**
- Updated codebook object with NE22 IRT parameters populated

**Process:**
1. Loads codebook JSON
2. For each parameter item:
   - Finds matching item by kidsight lexicon
   - Validates NE22 study participation
   - Updates NE22 IRT parameter structure
   - Preserves other study parameters
3. Returns updated codebook with metadata refresh

#### Additional Functions

##### `convert_csv_to_json(csv_path, json_path)`

Primary conversion function that orchestrates the entire CSV-to-JSON process.

**Parameters:**
- `csv_path` (character): Path to source CSV file (default: Update-KidsightsPublic CSV)
- `json_path` (character): Output path for JSON file (default: "codebook/data/codebook.json")

**Process:**
1. Load and clean CSV data with encoding handling
2. Convert each CSV row to structured JSON format
3. Integrate PS items from GSED_PF study
4. Apply natural alphanumeric sorting
5. Generate final JSON with metadata
6. Write to output file

**Example:**
```r
source("scripts/codebook/initial_conversion.R")

# Standard conversion
convert_csv_to_json()

# Custom paths
convert_csv_to_json(
  csv_path = "path/to/custom/codebook.csv",
  json_path = "output/custom_codebook.json"
)
```

##### `parse_ps_items(ps_csv_path)`

Parses 46 PS (Psychosocial) items from CSV for GSED_PF study integration.

**Parameters:**
- `ps_csv_path` (character): Path to PS items CSV (default: "tmp/ne25_ps_items.csv")

**Returns:**
- Named list of PS items in codebook JSON format

**Features:**
- Assigns unique integer IDs (2001-2046)
- Sets domain to "psychosocial_problems_general"
- References "ps_frequency" response set
- Includes tier_followup and item_order metadata

**Example:**
```r
# Parse PS items separately
ps_items <- parse_ps_items("tmp/ne25_ps_items.csv")
length(ps_items)  # 46

# Access first PS item
ps001 <- ps_items[["PS001"]]
print(ps001$content$stems$combined)
```

##### `detect_response_set_or_parse(resp_string)`

Intelligent response option parser that detects standard response sets or creates custom parsing.

**Parameters:**
- `resp_string` (character): Response options string from CSV

**Returns:**
- Character reference to standard response set, or parsed response list

**Supported Response Sets:**
- `"standard_binary"`: Yes/No/Don't Know pattern
- `"likert_5"`: 5-point Never to Always scale
- `"ps_frequency"`: PS frequency scale (Never or Almost Never/Sometimes/Often/Don't Know)

**Example:**
```r
# Detects standard binary
detect_response_set_or_parse("1 = Yes; 0 = No; -9 = Don't Know")
# Returns: "standard_binary"

# Detects PS frequency
detect_response_set_or_parse("0 = Never or Almost Never; 1 = Sometimes; 2 = Often; -9 = Don't Know")
# Returns: "ps_frequency"

# Custom parsing
detect_response_set_or_parse("1 = Always; 2 = Sometimes; 3 = Never")
# Returns: list of parsed options
```

##### `convert_csv_row_to_json(item_row)`

Converts a single CSV row to structured JSON item format.

**Parameters:**
- `item_row`: Single row data frame from CSV

**Returns:**
- List representing complete item structure

**Features:**
- Maps CSV columns to JSON hierarchy
- Applies reverse coding corrections
- Determines study participation
- Structures domains with study groups
- Handles missing data appropriately

##### `determine_studies(item_row)`

Determines which studies an item participates in based on CSV identifiers.

**Parameters:**
- `item_row`: Single row data frame from CSV

**Returns:**
- Character vector of study names

**Study Mappings:**
```r
study_mappings <- list(
  "NE25" = "lex_ne25",
  "NE22" = "lex_ne22",
  "NE20" = "lex_ne20",
  "CAHMI22" = "lex_cahmi22",
  "CAHMI21" = "lex_cahmi21",
  "ECDI" = "lex_ecdi",
  "CREDI" = "lex_credi",
  "GSED" = "lex_gsed"
)
```

##### `determine_reverse_coding(item_row)`

Determines correct reverse coding with manual corrections for specific items.

**Parameters:**
- `item_row`: Single row data frame from CSV

**Returns:**
- Logical indicating reverse coding status

**Manual Corrections:**
- DD221, EG25a, EG26a, EG26b: Set to TRUE (reverse coded)
- All PS items: Set to FALSE (not reverse coded)

##### `remove_na_recursive(x)`

Recursively removes NA values from nested list structures to keep JSON clean.

**Parameters:**
- `x`: List or vector

**Returns:**
- Clean list without NA values

## Usage Examples

### Basic Conversion

```r
# Load required libraries
library(tidyverse)
library(jsonlite)
library(yaml)

# Run conversion
source("scripts/codebook/initial_conversion.R")
convert_csv_to_json()

# Verify output
codebook <- fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)
length(codebook$items)  # Should be 305
```

### Development Workflow

```r
# 1. Modify conversion logic
source("scripts/codebook/initial_conversion.R")

# 2. Test PS items parsing
ps_items <- parse_ps_items()
length(ps_items)  # 46

# 3. Test response set detection
test_binary <- detect_response_set_or_parse("1 = Yes; 0 = No; -9 = Don't Know")
test_ps <- detect_response_set_or_parse("0 = Never or Almost Never; 1 = Sometimes; 2 = Often; -9 = Don't Know")

# 4. Run full conversion
convert_csv_to_json()

# 5. Validate results
source("R/codebook/load_codebook.R")
codebook <- load_codebook("codebook/data/codebook.json")
```

### Adding New Study Items

To add items from a new study:

1. **Create parser function:**
```r
parse_new_study_items <- function(csv_path) {
  # Read CSV
  data <- read_csv(csv_path)

  # Create items list
  items <- list()
  for (i in 1:nrow(data)) {
    item <- list(
      id = as.integer(i + 3000),  # Unique ID range
      studies = list("NEW_STUDY"),
      lexicons = list(
        equate = data$item_id[i]
      ),
      domains = list(
        kidsights = list(
          value = "new_domain",
          studies = list("NEW_STUDY")
        )
      ),
      # ... additional structure
    )
    items[[data$item_id[i]]] <- item
  }

  return(items)
}
```

2. **Update main conversion:**
```r
# Add to convert_csv_to_json() function
new_items <- parse_new_study_items("path/to/new_items.csv")
items_list <- c(items_list, new_items)
```

3. **Update configuration:**
```yaml
# In config/codebook_config.yaml
validation:
  study_validation:
    valid_studies:
      - "NEW_STUDY"
  domain_validation:
    valid_domains:
      - "new_domain"
```

### Custom Response Sets

To add a new response set:

1. **Define in config:**
```yaml
response_sets:
  custom_scale:
    - value: 1
      label: "Low"
    - value: 2
      label: "Medium"
    - value: 3
      label: "High"
```

2. **Add detection logic:**
```r
# In detect_response_set_or_parse()
if (str_detect(normalized, "1=low") && str_detect(normalized, "3=high")) {
  return("custom_scale")
}
```

## Data Flow

```
CSV Codebook (259 items)
    ↓
CSV Row Processing
    ↓
JSON Item Creation
    ↓
PS Items Integration (+46 items)
    ↓
Natural Sorting (gtools::mixedsort)
    ↓
JSON Output (305 items)
```

## Error Handling

The conversion script includes comprehensive error handling:

### Encoding Issues
```r
# Tries multiple encodings
csv_data <- tryCatch({
  read_csv(csv_path, locale = locale(encoding = "UTF-8"))
}, error = function(e) {
  message("UTF-8 failed, trying Windows-1252...")
  read_csv(csv_path, locale = locale(encoding = "Windows-1252"))
})
```

### Character Cleaning
```r
# Handles common encoding problems
cleaned <- str_replace_all(cleaned, "â€™", "'")  # Smart quote
cleaned <- str_replace_all(cleaned, "â€œ", "\"") # Left quote
cleaned <- str_replace_all(cleaned, "â€\u009d", "\"") # Right quote
```

### Missing Data
```r
# Safe handling with %||% operator
value <- item_row$field %||% NA
```

## Dependencies

Required R packages:
- `tidyverse`: Data manipulation and string processing
- `jsonlite`: JSON reading and writing
- `yaml`: Configuration file reading
- `lubridate`: Date handling
- `gtools`: Natural sorting

Install with:
```r
install.packages(c("tidyverse", "jsonlite", "yaml", "lubridate", "gtools"))
```

## Output Validation

The script generates comprehensive output:
- **Items**: 305 total (259 + 46 PS items)
- **Studies**: 8 studies supported
- **Domains**: 4 domains including psychosocial_problems_general
- **Response Sets**: 3 standard sets plus custom sets
- **Metadata**: Version, generation date, source tracking

## Configuration

The conversion process is configured via `config/codebook_config.yaml`:
- **Validation rules**: Required fields, valid domains/studies
- **Response sets**: Standard response option definitions
- **Column mappings**: CSV field to JSON path mappings

## Version History

- **Initial**: Basic CSV to JSON conversion
- **v2.0**: Enhanced structure with response sets and validation
- **v2.1**: GSED_PF PS items integration with psychosocial_problems_general domain
- **v2.2**: Study-specific IRT parameters with constraints field template
- **v2.3**: NE22 IRT parameter update script with empirical calibration data

For usage questions, see the main codebook documentation in `codebook/README.md`.
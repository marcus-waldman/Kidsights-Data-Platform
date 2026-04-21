# Codebook API Documentation

Complete API reference for the Kidsights JSON Codebook System.

## Table of Contents

- [Overview](#overview)
- [Data Structures](#data-structures)
- [Loading Functions](#loading-functions)
- [Query Functions](#query-functions)
- [Validation Functions](#validation-functions)
- [Visualization Functions](#visualization-functions)
- [Utility Functions](#utility-functions)
- [Error Handling](#error-handling)
- [Examples](#examples)

## Overview

The Kidsights Codebook API provides comprehensive functions for working with a JSON-based codebook containing 305 items from 8 studies. The API supports loading, querying, validating, and visualizing codebook data.

### Key Features
- **305 Items**: Complete metadata for items across multiple studies
- **8 Studies**: NE25, NE22, NE20, CAHMI22, CAHMI21, ECDI, CREDI, GSED_PF
- **4 Domains**: socemo, motor, coglan, psychosocial_problems_general
- **Response Sets**: Reusable response option definitions
- **Interactive Dashboard**: Quarto-based web explorer

## Data Structures

### Codebook Object

The main codebook object has class "codebook" and contains:

```r
codebook <- list(
  metadata = list(
    version = "2.1",
    generated_date = "2025-09-16",
    total_items = 305
  ),
  items = list(
    "AA4" = list(...),     # 305 items total
    "PS001" = list(...)
  ),
  response_sets = list(
    standard_binary = data.frame(...),
    likert_5 = data.frame(...),
    ps_frequency = data.frame(...)
  ),
  domains = list(...)
)
```

### Item Structure

Each item has the following structure:

```r
item <- list(
  id = 123,                          # Integer ID
  studies = c("NE25", "GSED_PF"),    # Study participation

  lexicons = list(                   # Study-specific identifiers
    equate = "PS001",                # Primary identifier
    kidsight = "PS001",
    ne25 = "PS001"
  ),

  domains = list(                    # Domain classification
    kidsights = list(
      value = "psychosocial_problems_general",
      studies = c("GSED_PF")
    ),
    cahmi = list(...)                # Optional CAHMI classification
  ),

  age_range = list(                  # Age applicability
    min_months = 0,
    max_months = 60
  ),

  content = list(                    # Item content
    stems = list(
      combined = "Do you have concerns...",
      ne25 = "..."                   # Study-specific versions
    ),
    response_options = list(
      ne25 = "ps_frequency"          # Reference to response set
    )
  ),

  scoring = list(                    # Scoring information
    reverse = FALSE,
    equate_group = "GSED_PF"
  ),

  psychometric = list(               # IRT and other parameters
    irt_parameters = list(...),
    calibration_item = FALSE
  )
)
```

## Loading Functions

### `load_codebook(json_path, validate = TRUE)`

Load and initialize a JSON codebook.

**Parameters:**
- `json_path` (character): Path to JSON codebook file
- `validate` (logical): Whether to run validation checks (default: TRUE)

**Returns:**
- Codebook object with class "codebook"

**Throws:**
- Error if file doesn't exist or JSON is invalid
- Warning if validation fails (when validate=TRUE)

**Example:**
```r
# Load with validation
codebook <- load_codebook("codebook/data/codebook.json")

# Load without validation (faster for large codebooks)
codebook <- load_codebook("codebook/data/codebook.json", validate = FALSE)

# Check loaded codebook
class(codebook)  # "codebook"
length(codebook$items)  # 305
```

### `get_codebook_summary(codebook)`

Get summary statistics for the codebook.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- Named list with summary statistics:
  - `total_items`: Total number of items
  - `studies`: Vector of study names
  - `domains`: Vector of domain names
  - `response_sets`: Vector of response set names
  - `version`: Codebook version

**Example:**
```r
summary <- get_codebook_summary(codebook)
summary$total_items  # 305
summary$studies      # c("NE25", "NE22", ..., "GSED_PF")
summary$domains      # c("socemo", "motor", "coglan", "psychosocial_problems_general")
```

## Query Functions

### `filter_items_by_domain(codebook, domain, study_group = "kidsights")`

Filter items by domain classification.

**Parameters:**
- `codebook`: Codebook object
- `domain` (character): Domain name
  - Valid kidsights domains: "socemo", "motor", "coglan", "psychosocial_problems_general"
  - Valid cahmi domains: "social_emotional", "motor", "early_learning", "self_regulation"
- `study_group` (character): Study group ("kidsights" or "cahmi")

**Returns:**
- Named list of items matching the domain (may be empty)

**Example:**
```r
# Get motor domain items
motor_items <- filter_items_by_domain(codebook, "motor")
length(motor_items)  # Number of motor items

# Get GSED_PF psychosocial items
ps_items <- filter_items_by_domain(codebook, "psychosocial_problems_general")
length(ps_items)  # 46

# Get CAHMI social-emotional items
cahmi_se <- filter_items_by_domain(codebook, "social_emotional", study_group = "cahmi")
```

### `filter_items_by_study(codebook, study)`

Filter items by study participation.

**Parameters:**
- `codebook`: Codebook object
- `study` (character): Study name
  - Valid studies: "NE25", "NE22", "NE20", "CAHMI22", "CAHMI21", "ECDI", "CREDI", "GSED_PF"

**Returns:**
- Named list of items from the specified study

**Example:**
```r
# Get all GSED_PF items (46 PS items)
gsed_items <- filter_items_by_study(codebook, "GSED_PF")
length(gsed_items)  # 46

# Get NE25 items
ne25_items <- filter_items_by_study(codebook, "NE25")

# Get CAHMI22 items
cahmi_items <- filter_items_by_study(codebook, "CAHMI22")
```

### `get_item(codebook, item_id)`

Retrieve a specific item by ID.

**Parameters:**
- `codebook`: Codebook object
- `item_id` (character): Item identifier (primary equate ID)

**Returns:**
- Single item object or NULL if not found

**Example:**
```r
# Get specific items
item_aa4 <- get_item(codebook, "AA4")
item_ps001 <- get_item(codebook, "PS001")

# Check if item exists
if (!is.null(item_ps001)) {
  print(item_ps001$content$stems$combined)
}

# Access item properties
domain <- item_aa4$domains$kidsights$value
studies <- item_aa4$studies
reverse <- item_aa4$scoring$reverse
```

### `search_items(codebook, pattern, field = "stem")`

Search items by text pattern.

**Parameters:**
- `codebook`: Codebook object
- `pattern` (character): Search pattern (regex supported)
- `field` (character): Field to search in
  - "stem": Search in combined stem text (default)
  - "all": Search in all text fields

**Returns:**
- Named list of matching items

**Example:**
```r
# Search for items about behavior
behavior_items <- search_items(codebook, "behav", field = "stem")

# Search for attention-related items (regex)
attention_items <- search_items(codebook, "attention|focus|concentrate", field = "stem")

# Search in all fields
social_items <- search_items(codebook, "social", field = "all")
```

### `items_to_dataframe(codebook, flatten_identifiers = TRUE)`

Convert items to a data frame for analysis.

**Parameters:**
- `codebook`: Codebook object
- `flatten_identifiers` (logical): Whether to flatten identifier columns

**Returns:**
- Data frame with one row per item and columns:
  - `item_id`: Primary identifier
  - `studies`: Semicolon-separated study list
  - `domain_kidsights`: Kidsights domain
  - `domain_cahmi`: CAHMI domain (if available)
  - `stem_combined`: Combined item text
  - `reverse`: Reverse coding flag
  - `has_response_opts`: Whether response options are defined
  - `has_irt_params`: Whether IRT parameters are available
  - Additional identifier columns (if flatten_identifiers=TRUE)

**Example:**
```r
# Convert to data frame
df <- items_to_dataframe(codebook)
nrow(df)  # 305

# Analyze by domain
table(df$domain_kidsights)

# Filter and analyze
gsed_df <- df[grepl("GSED_PF", df$studies), ]
table(gsed_df$reverse)  # All FALSE for PS items

# Export to CSV
write.csv(df, "codebook_items.csv", row.names = FALSE)
```

### `get_study_coverage(codebook)`

Get study coverage matrix showing which items appear in which studies.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- Matrix with items as rows and studies as columns (logical values)

**Example:**
```r
coverage <- get_study_coverage(codebook)
dim(coverage)  # 305 items × 8 studies

# Check which studies include specific items
coverage["PS001", ]  # Only GSED_PF should be TRUE
coverage["AA4", ]    # Multiple studies may be TRUE

# Count items per study
colSums(coverage)

# Count studies per item
rowSums(coverage)
```

### `get_domain_study_crosstab(codebook, hrtl_domain = FALSE)`

Create crosstab of domains by studies.

**Parameters:**
- `codebook`: Codebook object
- `hrtl_domain` (logical): Use CAHMI domains instead of Kidsights (default: FALSE)

**Returns:**
- Data frame crosstab with domains as rows and studies as columns

**Example:**
```r
# Kidsights domain × study crosstab
crosstab <- get_domain_study_crosstab(codebook)
print(crosstab)

# CAHMI domain × study crosstab
cahmi_crosstab <- get_domain_study_crosstab(codebook, hrtl_domain = TRUE)

# Find studies with psychosocial items
crosstab[crosstab$domain_kidsights == "psychosocial_problems_general", ]
```

## Validation Functions

### `validate_codebook_structure(codebook)`

Validate the overall codebook structure and required fields.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- List with validation results:
  - `valid` (logical): Whether validation passed
  - `errors` (character vector): Error messages if any
  - `warnings` (character vector): Warning messages if any

**Example:**
```r
validation <- validate_codebook_structure(codebook)

if (validation$valid) {
  message("Codebook structure is valid")
} else {
  cat("Errors found:\n")
  print(validation$errors)
}

if (length(validation$warnings) > 0) {
  cat("Warnings:\n")
  print(validation$warnings)
}
```

### `check_response_set_references(codebook)`

Validate that all response set references are defined.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- List with validation results:
  - `valid` (logical): Whether all references are valid
  - `undefined_refs` (character vector): Undefined reference names
  - `defined_sets` (character vector): Available response set names

**Example:**
```r
ref_check <- check_response_set_references(codebook)

if (ref_check$valid) {
  message("All response set references are valid")
} else {
  cat("Undefined references:\n")
  print(ref_check$undefined_refs)
}

# See available response sets
print(ref_check$defined_sets)  # c("standard_binary", "likert_5", "ps_frequency")
```

## Visualization Functions

### `plot_domain_distribution(codebook, hrtl_domain = FALSE)`

Create bar plot of item distribution by domain.

**Parameters:**
- `codebook`: Codebook object
- `hrtl_domain` (logical): Use CAHMI domains (default: FALSE for Kidsights)

**Returns:**
- ggplot object

**Dependencies:**
- ggplot2, dplyr

**Example:**
```r
library(ggplot2)

# Plot Kidsights domain distribution
p1 <- plot_domain_distribution(codebook)
print(p1)

# Plot CAHMI domain distribution
p2 <- plot_domain_distribution(codebook, hrtl_domain = TRUE)
print(p2)

# Save plot
ggsave("domain_distribution.png", p1, width = 8, height = 6)
```

### `plot_study_coverage(codebook, max_items = 50)`

Create heatmap of item coverage across studies.

**Parameters:**
- `codebook`: Codebook object
- `max_items` (numeric): Maximum items to display (default: 50)

**Returns:**
- ggplot object

**Example:**
```r
# Plot study coverage heatmap
coverage_plot <- plot_study_coverage(codebook, max_items = 100)
print(coverage_plot)

# Plot all items (may be large)
full_plot <- plot_study_coverage(codebook, max_items = Inf)
```

### `plot_domain_study_crosstab(codebook, hrtl_domain = FALSE)`

Create heatmap of domain by study crosstab.

**Parameters:**
- `codebook`: Codebook object
- `hrtl_domain` (logical): Use CAHMI domains

**Returns:**
- ggplot object

**Example:**
```r
# Plot domain × study heatmap
crosstab_plot <- plot_domain_study_crosstab(codebook)
print(crosstab_plot)

# CAHMI version
cahmi_plot <- plot_domain_study_crosstab(codebook, hrtl_domain = TRUE)
print(cahmi_plot)
```

### `plot_item_icc(item, theta_range = c(-4, 4), model_type = "unidimensional")`

Plot Item Characteristic Curve for IRT analysis.

**Parameters:**
- `item`: Single item object (from get_item())
- `theta_range` (numeric vector): Ability range to plot (default: c(-4, 4))
- `model_type` (character): IRT model type (default: "unidimensional")

**Returns:**
- plotly object (interactive plot)

**Dependencies:**
- plotly

**Example:**
```r
library(plotly)

# Get item with IRT parameters
item <- get_item(codebook, "AA102")

# Check if item has IRT parameters
if (!is.null(item$psychometric$irt_parameters)) {
  icc_plot <- plot_item_icc(item)
  print(icc_plot)
}
```

### `create_summary_plots(codebook)`

Create a set of summary plots for dashboard.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- Named list of ggplot objects:
  - `domain_dist`: Domain distribution plot
  - `study_coverage`: Study coverage summary
  - `response_coverage`: Response options coverage
  - `irt_coverage`: IRT parameters coverage

**Example:**
```r
plots <- create_summary_plots(codebook)

# Display individual plots
print(plots$domain_dist)
print(plots$study_coverage)
print(plots$response_coverage)
print(plots$irt_coverage)

# Arrange in grid
library(gridExtra)
grid.arrange(grobs = plots, ncol = 2)
```

## Utility Functions

### `get_response_set(codebook, set_name)`

Get response set definition by name.

**Parameters:**
- `codebook`: Codebook object
- `set_name` (character): Response set name

**Returns:**
- Data frame with response options or NULL if not found

**Example:**
```r
# Get PS frequency response set
ps_freq <- get_response_set(codebook, "ps_frequency")
print(ps_freq)
#   value                 label missing
# 1     0 Never or Almost Never   FALSE
# 2     1             Sometimes   FALSE
# 3     2                 Often   FALSE
# 4    -9            Don't Know    TRUE
```

### `list_available_domains(codebook, study_group = "kidsights")`

List all available domains in the codebook.

**Parameters:**
- `codebook`: Codebook object
- `study_group` (character): Study group ("kidsights" or "cahmi")

**Returns:**
- Character vector of domain names

**Example:**
```r
# Get Kidsights domains
kidsights_domains <- list_available_domains(codebook)
print(kidsights_domains)  # c("socemo", "motor", "coglan", "psychosocial_problems_general")

# Get CAHMI domains
cahmi_domains <- list_available_domains(codebook, study_group = "cahmi")
```

### `list_available_studies(codebook)`

List all available studies in the codebook.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- Character vector of study names

**Example:**
```r
studies <- list_available_studies(codebook)
print(studies)  # c("NE25", "NE22", "NE20", "CAHMI22", "CAHMI21", "ECDI", "CREDI", "GSED_PF")
```

## Error Handling

The API includes comprehensive error checking and informative messages:

### Common Error Scenarios

**Invalid file path:**
```r
# This will throw an error
codebook <- load_codebook("nonexistent.json")
# Error: File does not exist: nonexistent.json
```

**Invalid item ID:**
```r
# This returns NULL with warning
item <- get_item(codebook, "INVALID")
# Warning: Item 'INVALID' not found in codebook
# Returns: NULL
```

**Invalid domain:**
```r
# This returns empty list with warning
items <- filter_items_by_domain(codebook, "nonexistent")
# Warning: Domain 'nonexistent' not found
# Returns: list()
```

**Invalid study:**
```r
# This returns empty list with warning
items <- filter_items_by_study(codebook, "INVALID_STUDY")
# Warning: Study 'INVALID_STUDY' not found
# Returns: list()
```

**Validation failures:**
```r
validation <- validate_codebook_structure(codebook)
if (!validation$valid) {
  cat("Validation errors:\n")
  for (error in validation$errors) {
    cat("-", error, "\n")
  }
}
```

### Best Practices

1. **Always check return values:**
```r
item <- get_item(codebook, "PS001")
if (!is.null(item)) {
  # Safe to use item
  print(item$content$stems$combined)
}
```

2. **Use validation:**
```r
# Load with validation
codebook <- load_codebook("codebook.json", validate = TRUE)

# Or validate explicitly
validation <- validate_codebook_structure(codebook)
stopifnot(validation$valid)
```

3. **Handle empty results:**
```r
motor_items <- filter_items_by_domain(codebook, "motor")
if (length(motor_items) > 0) {
  # Process items
  df <- items_to_dataframe(list(items = motor_items))
}
```

## Examples

### Complete Analysis Workflow

```r
# Load and validate codebook
library(tidyverse)
library(ggplot2)
source("R/codebook/load_codebook.R")
source("R/codebook/query_codebook.R")
source("R/codebook/visualize_codebook.R")

codebook <- load_codebook("codebook/data/codebook.json")

# Get summary
summary <- get_codebook_summary(codebook)
cat("Loaded", summary$total_items, "items from", length(summary$studies), "studies\n")

# Analyze GSED_PF study
gsed_items <- filter_items_by_study(codebook, "GSED_PF")
cat("GSED_PF has", length(gsed_items), "items\n")

# Check domain distribution
ps_items <- filter_items_by_domain(codebook, "psychosocial_problems_general")
cat("Psychosocial domain has", length(ps_items), "items\n")

# Convert to data frame for analysis
df <- items_to_dataframe(codebook)
gsed_df <- df[grepl("GSED_PF", df$studies), ]

# Analyze reverse coding
table(gsed_df$reverse)  # All should be FALSE

# Create visualizations
domain_plot <- plot_domain_distribution(codebook)
print(domain_plot)

# Export results
write.csv(gsed_df, "gsed_pf_items.csv", row.names = FALSE)
```

### Search and Filter Example

```r
# Search for behavior-related items
behavior_items <- search_items(codebook, "behav", field = "stem")

# Get items from multiple studies
multi_study_items <- c(
  filter_items_by_study(codebook, "NE25"),
  filter_items_by_study(codebook, "GSED_PF")
)

# Filter by domain and study
motor_ne25 <- filter_items_by_domain(codebook, "motor") %>%
  Filter(function(item) "NE25" %in% item$studies, .)

# Complex filtering
complex_filter <- function(item) {
  is_motor <- item$domains$kidsights$value == "motor"
  is_ne25 <- "NE25" %in% item$studies
  has_irt <- !is.null(item$psychometric$irt_parameters)
  return(is_motor && is_ne25 && has_irt)
}

filtered_items <- Filter(complex_filter, codebook$items)
```

### Response Set Analysis

```r
# Examine response sets
ps_freq <- get_response_set(codebook, "ps_frequency")
print(ps_freq)

# Find items using ps_frequency
ps_freq_items <- Filter(function(item) {
  any(sapply(item$content$response_options, function(x) x == "ps_frequency"))
}, codebook$items)

length(ps_freq_items)  # Should be 46 (all PS items)
```

This completes the comprehensive API documentation for the Kidsights Codebook System.
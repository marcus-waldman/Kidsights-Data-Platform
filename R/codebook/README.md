# Codebook R Functions

This directory contains R functions for working with the Kidsights JSON codebook system. The functions provide a complete API for loading, querying, validating, and visualizing codebook data.

## Overview

The codebook R library provides four main modules:

- **`load_codebook.R`**: Loading and initialization functions
- **`query_codebook.R`**: Filtering and searching functions
- **`validate_codebook.R`**: Validation and integrity checking
- **`visualize_codebook.R`**: Plotting and visualization functions

## Quick Start

```r
# Load the library
source("R/codebook/load_codebook.R")
source("R/codebook/query_codebook.R")

# Load codebook
codebook <- load_codebook("codebook/data/codebook.json")

# Query items
motor_items <- filter_items_by_domain(codebook, "motor")
gsed_items <- filter_items_by_study(codebook, "GSED_PF")
```

## Function Reference

### load_codebook.R

#### `load_codebook(json_path, validate = TRUE)`

Load and initialize a JSON codebook.

**Parameters:**
- `json_path` (character): Path to JSON codebook file
- `validate` (logical): Whether to run validation checks (default: TRUE)

**Returns:**
- Codebook object with class "codebook"

**Example:**
```r
# Load with validation
codebook <- load_codebook("codebook/data/codebook.json")

# Load without validation (faster)
codebook <- load_codebook("codebook/data/codebook.json", validate = FALSE)
```

#### `get_codebook_summary(codebook)`

Get summary statistics for the codebook.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- Named list with summary statistics

**Example:**
```r
summary <- get_codebook_summary(codebook)
print(summary$total_items)  # 305
print(summary$studies)      # c("NE25", "NE22", "GSED_PF", ...)
```

### query_codebook.R

#### `filter_items_by_domain(codebook, domain, study_group = "kidsights")`

Filter items by domain classification.

**Parameters:**
- `codebook`: Codebook object
- `domain` (character): Domain name (e.g., "motor", "psychosocial_problems_general")
- `study_group` (character): Study group ("kidsights" or "cahmi")

**Returns:**
- Named list of items matching the domain

**Example:**
```r
# Get motor domain items
motor_items <- filter_items_by_domain(codebook, "motor")

# Get GSED_PF psychosocial items
ps_items <- filter_items_by_domain(codebook, "psychosocial_problems_general")

# Get CAHMI domain items
cahmi_motor <- filter_items_by_domain(codebook, "motor", study_group = "cahmi")
```

#### `filter_items_by_study(codebook, study)`

Filter items by study participation.

**Parameters:**
- `codebook`: Codebook object
- `study` (character): Study name (e.g., "NE25", "GSED_PF")

**Returns:**
- Named list of items from the specified study

**Example:**
```r
# Get all GSED_PF items (46 PS items)
gsed_items <- filter_items_by_study(codebook, "GSED_PF")

# Get NE25 items
ne25_items <- filter_items_by_study(codebook, "NE25")
```

#### `get_item(codebook, item_id)`

Retrieve a specific item by ID.

**Parameters:**
- `codebook`: Codebook object
- `item_id` (character): Item identifier (e.g., "AA4", "PS001")

**Returns:**
- Single item object or NULL if not found

**Example:**
```r
# Get specific items
item_aa4 <- get_item(codebook, "AA4")
item_ps001 <- get_item(codebook, "PS001")

# Check item properties
print(item_aa4$domains$kidsights$value)  # Domain
print(item_ps001$content$stems$combined)  # Item text

# Access IRT parameters by study
irt_ne25 <- item_aa4$psychometric$irt_parameters$NE25
irt_gsed <- item_ps001$psychometric$irt_parameters$GSED_PF
```

#### `get_irt_parameters(item, study = NULL)`

Get IRT parameters for an item by study.

**Parameters:**
- `item`: Single item object (from get_item())
- `study` (character): Study name (default: NULL returns all studies)

**Returns:**
- IRT parameters for specified study or all studies

**Example:**
```r
# Get item
item <- get_item(codebook, "AA4")

# Get IRT parameters for specific study
ne22_irt <- get_irt_parameters(item, "NE22")
print(ne22_irt$factors)    # "kidsights" (unidimensional model)
print(ne22_irt$loadings)   # [1.166031] (empirical loading estimate)
print(ne22_irt$thresholds) # [0.299, -2.482, -4.007] (ordered thresholds)
print(ne22_irt$constraints) # [] (empty for NE22, populated for NE25)

# Get all IRT parameters
all_irt <- get_irt_parameters(item)
print(names(all_irt))  # Available studies with IRT data
```

#### `filter_items_with_irt(codebook, study = NULL)`

Filter items that have IRT parameters for a specific study.

**Parameters:**
- `codebook`: Codebook object
- `study` (character): Study name (default: NULL for any study)

**Returns:**
- Named list of items with IRT parameters

**Example:**
```r
# Get items with IRT parameters for NE22 (203 items with empirical estimates)
ne22_irt_items <- filter_items_with_irt(codebook, "NE22")

# Get items with IRT parameters for NE25 (62 items with constraints)
ne25_irt_items <- filter_items_with_irt(codebook, "NE25")

# Get items with any IRT parameters
any_irt_items <- filter_items_with_irt(codebook)
cat("Items with IRT data:", length(any_irt_items), "\n")
```

#### `get_irt_coverage(codebook)`

Get IRT parameter coverage matrix showing which items have parameters for which studies.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- Matrix with items as rows and studies as columns (logical values)

**Example:**
```r
coverage <- get_irt_coverage(codebook)
print(dim(coverage))  # 305 items × studies

# Check coverage for specific item
print(coverage["DD26", ])  # Should show TRUE for NE22, NE25, etc.

# Count items with parameters per study
study_counts <- colSums(coverage)
print(study_counts)  # NE22: 203, NE25: 62 (constraints), etc.
```

#### `search_items(codebook, pattern, field = "stem")`

Search items by text pattern.

**Parameters:**
- `codebook`: Codebook object
- `pattern` (character): Search pattern (regex supported)
- `field` (character): Field to search in ("stem", "all")

**Returns:**
- Named list of matching items

**Example:**
```r
# Search for items about behavior
behavior_items <- search_items(codebook, "behav", field = "stem")

# Search for attention-related items
attention_items <- search_items(codebook, "attention|focus", field = "stem")
```

#### `items_to_dataframe(codebook, flatten_identifiers = TRUE)`

Convert items to a data frame for analysis.

**Parameters:**
- `codebook`: Codebook object
- `flatten_identifiers` (logical): Whether to flatten identifier columns

**Returns:**
- Data frame with one row per item

**Example:**
```r
# Convert to data frame
df <- items_to_dataframe(codebook)

# Analyze by domain
table(df$domain_kidsights)

# Filter and analyze
gsed_df <- df[df$studies == "GSED_PF", ]
```

#### `get_study_coverage(codebook)`

Get study coverage matrix showing which items appear in which studies.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- Matrix with items as rows and studies as columns

**Example:**
```r
coverage <- get_study_coverage(codebook)
print(coverage["PS001", ])  # Show which studies include PS001
```

#### `get_domain_study_crosstab(codebook, hrtl_domain = FALSE)`

Create crosstab of domains by studies.

**Parameters:**
- `codebook`: Codebook object
- `hrtl_domain` (logical): Use CAHMI domains instead of Kidsights

**Returns:**
- Data frame crosstab

**Example:**
```r
# Kidsights domain × study crosstab
crosstab <- get_domain_study_crosstab(codebook)

# CAHMI domain × study crosstab
cahmi_crosstab <- get_domain_study_crosstab(codebook, hrtl_domain = TRUE)
```

### validate_codebook.R

#### `validate_codebook_structure(codebook)`

Validate the overall codebook structure and required fields.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- List with validation results and any errors

**Example:**
```r
validation <- validate_codebook_structure(codebook)
if (validation$valid) {
  message("Codebook is valid")
} else {
  print(validation$errors)
}
```

#### `check_response_set_references(codebook)`

Validate that all response set references are defined.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- List with validation results

**Example:**
```r
ref_check <- check_response_set_references(codebook)
print(ref_check$undefined_refs)  # Should be empty
```

### visualize_codebook.R

#### `plot_domain_distribution(codebook, hrtl_domain = FALSE)`

Create bar plot of item distribution by domain.

**Parameters:**
- `codebook`: Codebook object
- `hrtl_domain` (logical): Use CAHMI domains (default: FALSE for Kidsights)

**Returns:**
- ggplot object

**Example:**
```r
library(ggplot2)

# Plot Kidsights domain distribution
p1 <- plot_domain_distribution(codebook)
print(p1)

# Plot CAHMI domain distribution
p2 <- plot_domain_distribution(codebook, hrtl_domain = TRUE)
print(p2)
```

#### `plot_study_coverage(codebook, max_items = 50)`

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
```

#### `plot_domain_study_crosstab(codebook, hrtl_domain = FALSE)`

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
```

#### `plot_item_icc(item, theta_range = c(-4, 4), model_type = "unidimensional")`

Plot Item Characteristic Curve for IRT analysis.

**Parameters:**
- `item`: Single item object (from get_item())
- `theta_range` (numeric): Ability range to plot
- `model_type` (character): IRT model type

**Returns:**
- plotly object (interactive plot)

**Example:**
```r
library(plotly)

# Get item and plot ICC
item <- get_item(codebook, "AA102")
icc_plot <- plot_item_icc(item)
print(icc_plot)
```

#### `create_summary_plots(codebook)`

Create a set of summary plots for dashboard.

**Parameters:**
- `codebook`: Codebook object

**Returns:**
- Named list of ggplot objects

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

## Common Workflows

### Basic Item Analysis
```r
# Load and summarize
codebook <- load_codebook("codebook/data/codebook.json")
summary <- get_codebook_summary(codebook)

# Get items by domain
motor_items <- filter_items_by_domain(codebook, "motor")
ps_items <- filter_items_by_domain(codebook, "psychosocial_problems_general")

# Convert to data frame for analysis
df <- items_to_dataframe(codebook)
```

### Study-Specific Analysis
```r
# Focus on GSED_PF study
gsed_items <- filter_items_by_study(codebook, "GSED_PF")
cat("GSED_PF has", length(gsed_items), "items\n")

# Examine first PS item
ps001 <- get_item(codebook, "PS001")
print(ps001$content$stems$combined)
print(ps001$content$response_options)
```

### Visualization Dashboard
```r
library(ggplot2)

# Create summary plots
plots <- create_summary_plots(codebook)

# Domain distribution
print(plots$domain_dist)

# Study coverage
coverage_plot <- plot_study_coverage(codebook)
print(coverage_plot)
```

### Data Export
```r
# Export to CSV for analysis
df <- items_to_dataframe(codebook)
write.csv(df, "codebook_items.csv", row.names = FALSE)

# Export specific study
gsed_df <- df[df$studies == "GSED_PF", ]
write.csv(gsed_df, "gsed_pf_items.csv", row.names = FALSE)
```

## Error Handling

All functions include error checking and will provide informative messages:

```r
# Invalid item ID
item <- get_item(codebook, "INVALID")  # Returns NULL with warning

# Invalid domain
items <- filter_items_by_domain(codebook, "nonexistent")  # Returns empty list

# Validation errors
validation <- validate_codebook_structure(codebook)
if (!validation$valid) {
  print(validation$errors)
}
```

## Dependencies

Required packages:
- `jsonlite`: JSON parsing
- `tidyverse`: Data manipulation and ggplot2
- `plotly`: Interactive plots
- `gtools`: Natural sorting

Install with:
```r
install.packages(c("jsonlite", "tidyverse", "plotly", "gtools"))
```
# Imputation Helpers - R

R interface to Python imputation helpers via reticulate. Provides seamless access to multiply imputed datasets for analysis in R.

## Overview

The R imputation helpers provide a **single source of truth** by calling Python functions via reticulate. This ensures:
- Consistent behavior across R and Python
- No code duplication
- Easy maintenance
- Multi-study support

## Quick Start

```r
# Load helper functions
source("R/imputation/helpers.R")

# Get completed dataset for imputation m=1
df <- get_completed_dataset(
  imputation_m = 1,
  variables = c("puma", "county", "female", "raceG"),
  study_id = "ne25"
)

# Use with survey package
library(survey)
design <- svydesign(ids = ~1, weights = ~weight, data = df)
svymean(~factor(puma), design)
```

## Core Functions

All functions call Python helpers via reticulate and automatically convert results to R data.frames.

### get_completed_dataset()

Get a single completed dataset with imputed + observed values.

```r
# Get imputation 3 with geography only
df <- get_completed_dataset(
  imputation_m = 3,
  variables = c("puma", "county"),
  base_table = "ne25_transformed",
  study_id = "ne25"
)

# Get all imputed variables for imputation 5
df <- get_completed_dataset(
  imputation_m = 5,
  study_id = "ne25"
)
```

**Parameters:**
- `imputation_m` (integer): Which imputation to retrieve (1 to M)
- `variables` (character vector): Imputed variables. NULL = all.
- `base_table` (character): Base table name. Default: "ne25_transformed"
- `study_id` (character): Study identifier. Default: "ne25"
- `include_observed` (logical): Include base data. Default: TRUE

**Returns:** data.frame with observed + imputed values

### get_all_imputations()

Get all M imputations in long format.

```r
# Get all geography imputations
df_long <- get_all_imputations(
  variables = c("puma", "county"),
  study_id = "ne25"
)

# Analyze across imputations
library(dplyr)
df_long %>%
  dplyr::group_by(imputation_m, puma) %>%
  dplyr::summarise(count = dplyr::n())
```

**Parameters:**
- `variables` (character vector): Variables to include. NULL = all.
- `base_table` (character): Base table. Default: "ne25_transformed"
- `study_id` (character): Study identifier. Default: "ne25"

**Returns:** data.frame with `imputation_m` column

### get_imputation_list()

Get list of M data.frames for use with survey/mitools packages.

```r
# Get list of 5 imputed datasets
imp_list <- get_imputation_list(
  variables = c("puma", "county", "female"),
  study_id = "ne25"
)

# Analyze with mitools
library(survey)
library(mitools)

results <- lapply(imp_list, function(df) {
  design <- svydesign(ids = ~1, weights = ~weight, data = df)
  svymean(~factor(puma), design)
})

combined <- mitools::MIcombine(results)
summary(combined)
```

**Parameters:**
- `variables` (character vector): Variables to include. NULL = all.
- `base_table` (character): Base table. Default: "ne25_transformed"
- `study_id` (character): Study identifier. Default: "ne25"
- `max_m` (integer): Max imputation number. NULL = auto-detect.

**Returns:** List of M data.frames

### get_imputation_metadata()

Get metadata about all imputed variables across all studies.

```r
meta <- get_imputation_metadata()

# Filter to ne25 study
ne25_meta <- meta[meta$study_id == "ne25", ]

# View summary
print(ne25_meta[, c("variable_name", "n_imputations", "imputation_method")])
```

**Returns:** data.frame with metadata for all studies

### get_imputed_variable_summary()

Get summary statistics for a variable across all imputations.

```r
summary <- get_imputed_variable_summary("puma", study_id = "ne25")
print(summary)
```

**Parameters:**
- `variable_name` (character): Name of imputed variable
- `study_id` (character): Study identifier. Default: "ne25"

**Returns:** data.frame with distribution across imputations

### validate_imputations()

Validate imputation tables for completeness and consistency.

```r
results <- validate_imputations(study_id = "ne25")

if (results$all_valid) {
  cat("All", results$variables_checked, "variables validated!\n")
} else {
  cat("Issues detected:\n")
  for (issue in results$issues) {
    cat("  -", issue, "\n")
  }
}
```

**Parameters:**
- `study_id` (character): Study identifier. Default: "ne25"

**Returns:** List with validation results

## Multi-Study Usage

All helper functions support the `study_id` parameter for working with multiple independent studies.

```r
# Get ne25 data
ne25_df <- get_completed_dataset(imputation_m = 1, study_id = "ne25")

# Get ia26 data (future study)
ia26_df <- get_completed_dataset(imputation_m = 1, study_id = "ia26")

# Validate each study separately
ne25_valid <- validate_imputations(study_id = "ne25")
ia26_valid <- validate_imputations(study_id = "ia26")
```

## Survey Analysis Examples

### Simple Survey Design

```r
library(survey)
source("R/imputation/helpers.R")

# Get completed dataset for imputation m=1
df <- get_completed_dataset(1, study_id = "ne25")

# Create survey design
design <- svydesign(
  ids = ~1,
  weights = ~weight,
  data = df
)

# Estimate means
svymean(~age_in_days, design)
svymean(~factor(female), design)
```

### Multiple Imputation with mitools

```r
library(survey)
library(mitools)
source("R/imputation/helpers.R")

# Get list of all M imputations
imp_list <- get_imputation_list(study_id = "ne25")

# Create survey designs for each imputation
designs <- lapply(imp_list, function(df) {
  svydesign(ids = ~1, weights = ~weight, data = df)
})

# Estimate with Rubin's rules
results <- lapply(designs, function(d) {
  svymean(~factor(raceG), d)
})

# Combine results
combined <- MIcombine(results)
summary(combined)
```

### Analyzing Variability Across Imputations

```r
library(dplyr)
source("R/imputation/helpers.R")

# Get all imputations in long format
df_long <- get_all_imputations(
  variables = c("puma", "county"),
  study_id = "ne25"
)

# Calculate variability for each record
variability <- df_long %>%
  dplyr::group_by(pid, record_id) %>%
  dplyr::summarise(
    n_puma_values = dplyr::n_distinct(puma),
    n_county_values = dplyr::n_distinct(county)
  )

# Records with geographic uncertainty
uncertain <- variability %>%
  dplyr::filter(n_puma_values > 1 | n_county_values > 1)

cat("Records with geographic uncertainty:", nrow(uncertain), "\n")
```

## Configuration

Helper functions automatically load configuration via `R/imputation/config.R`:

```r
source("R/imputation/config.R")

# Get number of imputations
M <- get_n_imputations()  # 5

# Get study config
config <- get_study_config("ne25")
print(config$study_name)  # "Nebraska 2025"
```

## Testing

Test helper functions interactively:

```r
source("R/imputation/helpers.R")

# The script tests functions when run interactively
# Expected output:
#   [OK] Metadata table has 10 variables
#   [OK] All 10 variables validated
```

## Dependencies

### R Packages
- `reticulate` - Python integration
- `dplyr` - Data manipulation (optional, for examples)
- `survey` - Survey analysis (optional, for examples)
- `mitools` - Multiple imputation (optional, for examples)

### Python Environment

The helpers use reticulate to call Python functions. Reticulate will automatically set up a Python environment.

**Required Python packages in reticulate environment:**
- `duckdb`
- `pandas`
- `pyyaml`
- `python-dotenv`
- `pyarrow` (required for reading feather files)

Install pyarrow if missing:

```r
# From R
reticulate::py_install("pyarrow")
```

Or from command line:

```bash
"C:/Users/{username}/.virtualenvs/r-reticulate/Scripts/python.exe" -m pip install pyarrow
```

## Troubleshooting

### Error: "Failed to import python.imputation.helpers module"

Make sure you're running from the project root directory:

```r
getwd()  # Should be: C:/Users/.../Kidsights-Data-Platform
setwd("path/to/Kidsights-Data-Platform")
```

### Error: "ImportError: Missing optional dependency 'pyarrow'"

Install pyarrow in the reticulate Python environment:

```r
reticulate::py_install("pyarrow")
```

### Error: "Package 'reticulate' is required"

Install reticulate:

```r
install.packages("reticulate")
```

## Implementation Details

### Single Source of Truth

All R functions call Python equivalents:

```r
get_completed_dataset <- function(...) {
  py_helpers <- .get_python_helpers()  # Import Python module
  df_py <- py_helpers$get_completed_dataset(...)  # Call Python
  df_r <- reticulate::py_to_r(df_py)  # Convert to R
  return(df_r)
}
```

This ensures:
- **No code duplication**: Python has the canonical implementation
- **Automatic consistency**: R always matches Python behavior
- **Easy updates**: Fix bugs once in Python, R inherits the fix

### Automatic Type Conversion

Reticulate automatically converts between R and Python types:

| Python | R |
|--------|---|
| `pandas.DataFrame` | `data.frame` |
| `dict` | `list` |
| `list` | `list` or `vector` |
| `int/float` | `numeric` |
| `str` | `character` |
| `None` | `NULL` |

## See Also

- [Python Imputation Helpers](../../python/imputation/README.md) - Python implementation
- [helpers.R source code](helpers.R) - R wrapper functions
- [config.R source code](config.R) - Configuration system

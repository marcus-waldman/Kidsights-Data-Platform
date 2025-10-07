# Imputation Helper Examples

Example scripts demonstrating how to use the Kidsights imputation system with multiple studies.

## Prerequisites

**Python Users:**
```bash
pip install duckdb pandas pyyaml python-dotenv
```

**R Users:**
```r
install.packages(c("reticulate", "dplyr", "survey", "mitools"))

# Install pyarrow in reticulate environment
reticulate::py_install("pyarrow")
```

## Running Examples

### Python Examples

**Basic Usage** - Core helper functions:
```bash
cd C:/Users/marcu/git-repositories/Kidsights-Data-Platform
python examples/imputation/01_basic_usage_python.py
```

This demonstrates:
- Getting a single completed dataset (`get_completed_dataset()`)
- Getting all M imputations in long format (`get_all_imputations()`)
- Variable summary statistics (`get_imputed_variable_summary()`)
- Imputation metadata (`get_imputation_metadata()`)
- Validation (`validate_imputations()`)

**Multi-Study Comparison** - Working with multiple independent studies:
```bash
python examples/imputation/03_multistudy_comparison.py
```

This demonstrates:
- Accessing data from different studies (ne25, ia26, co27)
- Comparing study configurations
- Getting metadata across all studies
- Validating multiple studies
- Study-specific analysis patterns

### R Examples

**Survey Analysis** - Using survey and mitools packages:
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" examples/imputation/02_survey_analysis_r.R
```

This demonstrates:
- Simple survey-weighted analysis (single imputation)
- Multiple imputation with Rubin's rules (mitools package)
- Analyzing geographic variability across imputations
- Metadata queries and validation from R

## Example Descriptions

### 01_basic_usage_python.py

**Purpose:** Introduction to core Python helper functions

**Key Topics:**
- Loading completed datasets with specific variables
- Working with long-format data (all M imputations)
- Calculating geographic uncertainty
- Getting variable distributions
- Metadata and validation

**Output:** Demonstrates data structure, row counts, and validation results

---

### 02_survey_analysis_r.R

**Purpose:** Survey-weighted analysis with multiple imputation in R

**Key Topics:**
- Creating survey designs with `survey` package
- Combining estimates with Rubin's rules (`mitools` package)
- Analyzing variability across imputations
- R-Python integration via `reticulate`

**Output:** Survey-weighted estimates with proper MI variance

---

### 03_multistudy_comparison.py

**Purpose:** Working with multiple independent studies

**Key Topics:**
- Accessing data from different studies via `study_id` parameter
- Comparing configurations across studies
- Querying metadata for all studies
- Independent validation per study
- Study-specific variable handling

**Output:** Cross-study summaries and validation results

---

### 04_advanced_multistudy_queries.py

**Purpose:** Advanced cross-study analysis patterns

**Key Topics:**
- Comparing sample sizes and variable availability
- Pooling data across studies
- Comparing imputation uncertainty across studies
- Study-specific analysis with common framework
- Meta-analysis setup with Rubin's rules
- Cross-study validation

**Output:** Advanced multi-study comparisons, pooled datasets, meta-analysis prep

## Multi-Study Architecture

The imputation system supports multiple independent studies (e.g., ne25, ia26, co27) using:

1. **Study-Specific Tables**: `{study_id}_imputed_{variable_name}`
2. **Study-Specific Config**: `config/imputation/studies/{study_id}.yaml`
3. **Study-Specific Scripts**: `scripts/imputation/{study_id}/`
4. **Shared Metadata**: `imputation_metadata` table with `study_id` column

### Adding a New Study

See the detailed guide in [python/imputation/README.md](../../python/imputation/README.md#adding-a-new-study) for step-by-step instructions on adding a new study (e.g., ia26 - Iowa 2026).

## Helper Functions Reference

### Python Functions

| Function | Purpose | Study-Specific |
|----------|---------|----------------|
| `get_completed_dataset()` | Get single imputation + observed data | Yes (`study_id` param) |
| `get_all_imputations()` | Get all M imputations in long format | Yes (`study_id` param) |
| `get_imputation_metadata()` | Get metadata for all studies | No (returns all) |
| `get_imputed_variable_summary()` | Get variable distribution | Yes (`study_id` param) |
| `validate_imputations()` | Validate imputation completeness | Yes (`study_id` param) |

**Documentation:** [python/imputation/README.md](../../python/imputation/README.md)

### R Functions

All R functions wrap Python equivalents via `reticulate`:

| Function | Purpose | Study-Specific |
|----------|---------|----------------|
| `get_completed_dataset()` | Get single imputation + observed data | Yes (`study_id` param) |
| `get_all_imputations()` | Get all M imputations in long format | Yes (`study_id` param) |
| `get_imputation_list()` | Get list of M data.frames for mitools | Yes (`study_id` param) |
| `get_imputation_metadata()` | Get metadata for all studies | No (returns all) |
| `get_imputed_variable_summary()` | Get variable distribution | Yes (`study_id` param) |
| `validate_imputations()` | Validate imputation completeness | Yes (`study_id` param) |

**Documentation:** [R/imputation/README.md](../../R/imputation/README.md)

## Typical Workflow

### 1. Run Imputation Pipeline (One-Time)

```bash
# Setup database schema (one-time, study-specific)
python scripts/imputation/00_setup_imputation_schema.py --study-id ne25

# Run full pipeline (geography + sociodem + database)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R
```

**Output:** Study-specific tables in DuckDB with M=5 imputations

### 2. Access Data for Analysis

**Python:**
```python
from python.imputation.helpers import get_completed_dataset

# Get imputation m=1
df = get_completed_dataset(imputation_m=1, study_id='ne25')
```

**R:**
```r
source("R/imputation/helpers.R")

# Get list of all M=5 imputations for mitools
imp_list <- get_imputation_list(study_id = 'ne25')
```

### 3. Analyze with Survey Weights

**R with mitools:**
```r
library(survey)
library(mitools)

# Create survey designs
designs <- lapply(imp_list, function(df) {
  svydesign(ids = ~1, weights = ~weight, data = df)
})

# Estimate with Rubin's rules
results <- lapply(designs, function(d) svymean(~age, d))
combined <- MIcombine(results)
summary(combined)
```

## Troubleshooting

### Python: ModuleNotFoundError

Make sure you're running from the project root:
```bash
cd C:/Users/marcu/git-repositories/Kidsights-Data-Platform
python examples/imputation/01_basic_usage_python.py
```

### R: Cannot find python.imputation module

Check working directory and source the helpers:
```r
getwd()  # Should be project root
setwd("C:/Users/marcu/git-repositories/Kidsights-Data-Platform")
source("R/imputation/helpers.R")
```

### R: ImportError: Missing optional dependency 'pyarrow'

Install pyarrow in the R reticulate environment:
```r
reticulate::py_install("pyarrow")
```

Or from command line:
```bash
"C:/Users/marcu/.virtualenvs/r-reticulate/Scripts/python.exe" -m pip install pyarrow
```

## See Also

- [Python Imputation Helpers](../../python/imputation/README.md) - Python module documentation
- [R Imputation Helpers](../../R/imputation/README.md) - R wrapper documentation
- [Imputation Config](../../config/imputation/README.md) - Configuration system
- [CLAUDE.md](../../CLAUDE.md) - Main project documentation

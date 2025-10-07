# Imputation Module - Python

Python implementation of the Kidsights multiple imputation system with multi-study support.

## Overview

The imputation module provides functionality for:
- **Geographic imputation**: Sampling from allocation factor (afact) probabilities for ambiguous geocoding
- **Sociodemographic imputation**: Multiple imputation using mice (R) with Python integration
- **Multi-study architecture**: Support for independent studies (ne25, ia26, co27, etc.)
- **Helper functions**: Querying completed datasets with imputed values

## Quick Start

```python
from python.imputation.helpers import get_completed_dataset, validate_imputations
from python.imputation.config import get_study_config

# Get completed dataset for imputation m=1
df = get_completed_dataset(
    imputation_m=1,
    variables=['puma', 'county', 'female', 'raceG'],
    study_id='ne25'
)

# Validate all imputations for a study
results = validate_imputations(study_id='ne25')
print(f"All valid: {results['all_valid']}")
```

## Multi-Study Architecture

### Study Configuration

Each study has its own configuration in `config/imputation/studies/{study_id}.yaml`:

```yaml
study_id: ne25
study_name: Nebraska 2025
table_prefix: ne25_imputed
n_imputations: 5
random_seed: 42

geography:
  variables:
    - puma
    - county
    - census_tract

sociodemographic:
  variables:
    - female
    - raceG
    - educ_mom
    - educ_a2
    - income
    - family_size
```

### Database Tables

Study-specific tables follow the naming pattern: `{study_id}_imputed_{variable_name}`

Examples for ne25:
- `ne25_imputed_puma`
- `ne25_imputed_county`
- `ne25_imputed_female`
- `ne25_imputed_raceG`

### Metadata Table

The `imputation_metadata` table tracks all imputations across studies:

| Column | Description |
|--------|-------------|
| `study_id` | Study identifier (e.g., 'ne25') |
| `variable_name` | Imputed variable name |
| `n_imputations` | Number of imputations (M) |
| `imputation_method` | Method used (e.g., 'cart', 'rf', 'probabilistic_allocation') |
| `created_date` | Timestamp of imputation |
| `created_by` | Script that created the imputation |

## Core Functions

### get_completed_dataset()

Construct a completed dataset by joining imputed values with observed data.

```python
from python.imputation.helpers import get_completed_dataset

# Get specific variables for imputation m=3
df = get_completed_dataset(
    imputation_m=3,
    variables=['puma', 'county', 'female'],
    base_table='ne25_transformed',
    study_id='ne25'
)

# Get ALL imputed variables for imputation m=1
df_all = get_completed_dataset(
    imputation_m=1,
    study_id='ne25'
)
```

**Parameters:**
- `imputation_m` (int): Which imputation to retrieve (1 to M)
- `variables` (list, optional): Specific variables to include. If None, includes all.
- `base_table` (str): Base table with observed data (default: 'ne25_transformed')
- `study_id` (str): Study identifier (default: 'ne25')
- `include_observed` (bool): Include base observed data (default: True)

**Returns:** pandas.DataFrame with observed + imputed values

### get_all_imputations()

Get all M imputations in long format for analysis across imputations.

```python
from python.imputation.helpers import get_all_imputations

# Get all imputations for geography variables
df_long = get_all_imputations(
    variables=['puma', 'county'],
    study_id='ne25'
)

# Analyze variability across imputations
import pandas as pd
variability = df_long.groupby(['pid', 'record_id'])['puma'].nunique()
print(f"Records with varying PUMA: {(variability > 1).sum()}")
```

### get_imputed_variable_summary()

Get summary statistics for an imputed variable across all imputations.

```python
from python.imputation.helpers import get_imputed_variable_summary

# Get PUMA distribution across imputations
summary = get_imputed_variable_summary('puma', study_id='ne25')
print(summary.head(10))
```

### validate_imputations()

Validate imputation tables for completeness and consistency.

```python
from python.imputation.helpers import validate_imputations

results = validate_imputations(study_id='ne25')

if results['all_valid']:
    print(f"All {results['variables_checked']} variables validated!")
else:
    print("Issues detected:")
    for issue in results['issues']:
        print(f"  - {issue}")
```

## Running Imputations

### Geography Imputation (Python)

```bash
# Generate M=5 geography imputations for ne25
python scripts/imputation/ne25/01_impute_geography.py
```

This script:
1. Queries `ne25_transformed` for records with semicolon-delimited afact values
2. Parses geography values and probabilities
3. Samples M imputations using afact probabilities
4. Inserts into `ne25_imputed_puma`, `ne25_imputed_county`, `ne25_imputed_census_tract`

### Sociodemographic Imputation (R + Python)

```bash
# Step 1: Run mice imputation in R (generates feather files)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/02_impute_sociodemographic.R

# Step 2: Insert feather files into database (Python)
python scripts/imputation/ne25/02b_insert_sociodem_imputations.py
```

### Full Pipeline (Orchestration)

```bash
# Run complete pipeline: geography + sociodem + database insertion
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R
```

**Pipeline Stages:**
1. **Stage 1**: Geographic imputation (Python) - ~4 seconds
2. **Stage 2**: Sociodemographic imputation (R/mice) - ~2 minutes
3. **Stage 3**: Database insertion (Python) - ~7 seconds

**Total Time**: ~2 minutes for M=5 imputations

## Configuration System

### Global Configuration

`config/imputation/config.yaml` contains shared settings:

```yaml
n_imputations: 5
random_seed: 42

database:
  db_path: data/duckdb/kidsights_local.duckdb
```

### Study-Specific Configuration

Each study has its own config file with:
- Study metadata (name, ID)
- Variables to impute
- Data directories
- Script locations

Access via:

```python
from python.imputation.config import get_study_config

config = get_study_config('ne25')
print(config['study_name'])  # "Nebraska 2025"
print(config['geography']['variables'])  # ['puma', 'county', 'census_tract']
```

## Helper Functions Reference

| Function | Purpose | Study-Specific |
|----------|---------|----------------|
| `get_completed_dataset()` | Get single imputation with observed data | Yes (`study_id` param) |
| `get_all_imputations()` | Get all M imputations in long format | Yes (`study_id` param) |
| `get_imputation_metadata()` | Get metadata for all studies | No (returns all) |
| `get_imputed_variable_summary()` | Get variable distribution | Yes (`study_id` param) |
| `validate_imputations()` | Validate imputation completeness | Yes (`study_id` param) |

## Database Schema

### Imputation Tables

Each variable has its own table: `{study_id}_imputed_{variable_name}`

**Schema:**
```sql
CREATE TABLE ne25_imputed_puma (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  puma VARCHAR,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```

**Indexes:**
- Primary key: `(study_id, pid, record_id, imputation_m)`
- Index on `study_id` for filtering
- Index on `imputation_m` for queries

### Metadata Table

```sql
CREATE TABLE imputation_metadata (
  study_id VARCHAR NOT NULL,
  variable_name VARCHAR NOT NULL,
  n_imputations INTEGER NOT NULL,
  imputation_method VARCHAR,
  predictors TEXT,
  created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by VARCHAR,
  software_version VARCHAR,
  notes TEXT,
  PRIMARY KEY (study_id, variable_name)
);
```

## Adding a New Study

To add a new study (e.g., ia26 - Iowa 2026):

### 1. Create Study Configuration

Create `config/imputation/studies/ia26.yaml`:

```yaml
study_id: ia26
study_name: Iowa 2026
table_prefix: ia26_imputed
n_imputations: 5
random_seed: 42

data_dir: data/imputation/ia26
scripts_dir: scripts/imputation/ia26

geography:
  variables:
    - puma
    - county
    - census_tract

sociodemographic:
  variables:
    - female
    - raceG
    - educ_mom
```

### 2. Create Database Schema

```bash
python scripts/imputation/00_setup_imputation_schema.py --study-id ia26
```

### 3. Create Study Scripts

Copy and adapt scripts from `scripts/imputation/ne25/` to `scripts/imputation/ia26/`:
- `01_impute_geography.py` - Update `study_id = "ia26"`
- `02_impute_sociodemographic.R` - Update study references
- `02b_insert_sociodem_imputations.py` - Update `study_id = "ia26"`
- `run_full_imputation_pipeline.R` - Update orchestration

### 4. Run Pipeline

```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ia26/run_full_imputation_pipeline.R
```

## Testing

Validate helper functions:

```bash
python -m python.imputation.helpers
```

Expected output:
```
[OK] Metadata table has 10 variables
[OK] All 10 variables validated
```

## Dependencies

- **Python**: duckdb, pandas, numpy, pyyaml, python-dotenv
- **R** (via reticulate): duckdb, mice, arrow, ranger
- **R reticulate Python env**: pyarrow (required for reading feather files)

Install pyarrow in R reticulate environment:

```bash
"C:/Users/{username}/.virtualenvs/r-reticulate/Scripts/python.exe" -m pip install pyarrow
```

## See Also

- [R Imputation Helpers](../../R/imputation/README.md) - R interface to Python helpers
- [Imputation Config](config.py) - Configuration system documentation
- [Helper Functions](helpers.py) - Source code with detailed docstrings

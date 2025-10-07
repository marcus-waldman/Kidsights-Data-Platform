# Python Utilities Guide

**Last Updated:** October 2025

This document provides comprehensive documentation for Python utility modules in the Kidsights Data Platform. These utilities simplify common operations like R script execution, database connections, and data validation.

---

## Table of Contents

1. [R Executor](#r-executor)
2. [Database Operations](#database-operations)
3. [Data Refresh Strategy](#data-refresh-strategy)
4. [Logging Utilities](#logging-utilities)
5. [Configuration Management](#configuration-management)
6. [Imputation Utilities](#imputation-utilities)
7. [Common Patterns](#common-patterns)

---

## R Executor

**Module:** `python/utils/r_executor.py`
**Purpose:** Safely execute R code by creating temporary script files, avoiding segmentation faults from inline `-e` commands.

### Why Use R Executor?

**Problem:** R.exe with `-e` inline commands causes segmentation faults (50% failure rate)
**Solution:** Write R code to temp file, execute with `--file` flag (100% reliability)

### Quick Start

```python
from python.utils.r_executor import execute_r_script

code = '''
library(dplyr)
library(arrow)

# Load data
data <- arrow::read_feather("input.feather")

# Transform
result <- data %>%
  dplyr::filter(age > 5) %>%
  dplyr::mutate(age_squared = age ^ 2)

# Save
arrow::write_feather(result, "output.feather")
cat("Processed", nrow(result), "records\\n")
'''

output, return_code = execute_r_script(code)

if return_code == 0:
    print(f"[OK] R script succeeded")
    print(f"Output: {output}")
else:
    print(f"[ERROR] R script failed with code {return_code}")
    print(f"Error output: {output}")
```

### Advanced Usage: RExecutor Class

For more control, use the `RExecutor` class directly:

```python
from python.utils.r_executor import RExecutor

# Initialize with custom R executable
executor = RExecutor(r_executable=r"C:\Program Files\R\R-4.5.1\bin\R.exe")

# Execute with custom timeout and working directory
code = '''
source("R/transform/ne25_transforms.R")
cat("Transform complete\\n")
'''

stdout, stderr, return_code = executor.execute_script(
    code=code,
    working_dir=".",        # Working directory for R
    timeout=600,            # 10 minutes timeout
    cleanup=True            # Delete temp file after execution
)

print(f"STDOUT: {stdout}")
print(f"STDERR: {stderr}")
print(f"Return code: {return_code}")
```

### Configuration Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `r_executable` | str | `C:\Program Files\R\R-4.5.1\bin\R.exe` | Path to R.exe |
| `working_dir` | str | None | Working directory for R execution |
| `timeout` | int | 300 | Timeout in seconds (5 minutes) |
| `cleanup` | bool | True | Delete temp file after execution |

### Temp File Management

- **Location:** `scripts/temp/r_exec_{timestamp}_{uuid}.R`
- **Auto-cleanup:** Enabled by default
- **Manual cleanup:** Set `cleanup=False` to inspect temp files for debugging

**Example: Preserve temp file for debugging**
```python
stdout, stderr, return_code = executor.execute_script(
    code=code,
    cleanup=False  # Keep temp file for inspection
)

# Temp file remains at scripts/temp/r_exec_1234567890_abc123.R
```

### Error Handling

```python
from python.utils.r_executor import execute_r_script

code = '''
library(nonexistent_package)  # This will fail
'''

try:
    output, return_code = execute_r_script(code)
    if return_code != 0:
        print(f"[ERROR] R script failed: {output}")
except FileNotFoundError as e:
    print(f"[ERROR] R executable not found: {e}")
except Exception as e:
    print(f"[ERROR] Unexpected error: {e}")
```

### Best Practices

1. **Always use double backslashes** in R strings: `cat("Hello\\n")` not `cat("Hello\n")`
2. **Escape quotes** carefully: Use triple quotes for multi-line strings
3. **Check return codes:** `if return_code == 0:` before assuming success
4. **Set appropriate timeouts:** Long-running scripts need higher timeout values
5. **Use explicit namespacing** in R code: `dplyr::select()` not `select()`

---

## Database Operations

**Module:** `python/db/connection.py`
**Purpose:** Centralized DuckDB connection management with automatic retries and error handling.

### DatabaseManager Class

The `DatabaseManager` provides a clean interface for all database operations.

### Quick Start

```python
from python.db.connection import DatabaseManager

# Initialize with default config (ne25.yaml)
db = DatabaseManager()

# Test connection
if db.test_connection():
    print("[OK] Database connection successful")
else:
    print("[ERROR] Database connection failed")

# Get database info
print(f"Database path: {db.database_path}")
print(f"Database exists: {db.database_exists()}")
print(f"Database size: {db.get_database_size_mb():.2f} MB")
```

### Custom Configuration

```python
# Initialize with custom config file
db = DatabaseManager(config_path="config/sources/acs/nebraska-2019-2023.yaml")

# Or programmatically override config
from python.db.config import load_config, get_database_path

config = load_config("config/sources/ne25.yaml")
config['database']['path'] = "data/duckdb/custom.duckdb"

db = DatabaseManager()  # Will use modified config
```

### Context Manager Pattern (Recommended)

Use `get_connection()` context manager for safe connection handling:

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Read-only connection
with db.get_connection(read_only=True) as conn:
    result = conn.execute("SELECT COUNT(*) FROM ne25_raw").fetchone()
    print(f"Record count: {result[0]}")
# Connection automatically closed

# Read-write connection
with db.get_connection(read_only=False) as conn:
    conn.execute("CREATE TABLE IF NOT EXISTS test (id INTEGER, name VARCHAR)")
    conn.execute("INSERT INTO test VALUES (1, 'Alice')")
    conn.commit()
# Connection automatically closed and committed
```

### Direct Query Execution

For simple queries, use `execute_query()`:

```python
db = DatabaseManager()

# SELECT query
result = db.execute_query(
    "SELECT * FROM ne25_transformed WHERE age > ?",
    params=(5,)
)
print(f"Found {len(result)} records")

# INSERT query
db.execute_query(
    "INSERT INTO test VALUES (?, ?)",
    params=(1, 'Alice'),
    fetch_results=False  # Don't fetch for INSERT/UPDATE/DELETE
)
```

### Bulk Operations

For inserting large datasets, use `insert_data()`:

```python
import pandas as pd

db = DatabaseManager()

# Load data
df = pd.read_feather("data.feather")

# Insert with progress tracking
success, rows_inserted = db.insert_data(
    table_name="ne25_raw",
    data=df,
    chunk_size=500,         # Insert 500 rows at a time
    mode="replace",         # replace, append, or fail
    show_progress=True      # Show progress bar
)

if success:
    print(f"[OK] Inserted {rows_inserted} rows")
else:
    print(f"[ERROR] Insert failed")
```

### Transaction Management

```python
db = DatabaseManager()

with db.get_connection() as conn:
    try:
        # Start transaction (implicit)
        conn.execute("INSERT INTO test VALUES (1, 'Alice')")
        conn.execute("INSERT INTO test VALUES (2, 'Bob')")

        # Commit transaction
        conn.commit()
        print("[OK] Transaction committed")
    except Exception as e:
        # Rollback on error
        conn.rollback()
        print(f"[ERROR] Transaction rolled back: {e}")
```

### Connection Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `read_only` | bool | False | Open in read-only mode |
| `timeout` | int | 30 | Connection timeout (seconds) |
| `retry_attempts` | int | 3 | Number of retry attempts on failure |

### Error Handling

The `DatabaseManager` includes automatic retry logic:

```python
db = DatabaseManager()

# Automatically retries up to 3 times on connection failure
with db.get_connection(retry_attempts=3) as conn:
    result = conn.execute("SELECT * FROM ne25_raw").fetchall()
```

**Custom error handling:**
```python
from duckdb import DatabaseError

db = DatabaseManager()

try:
    with db.get_connection() as conn:
        conn.execute("SELECT * FROM nonexistent_table")
except DatabaseError as e:
    print(f"[ERROR] Database error: {e}")
except Exception as e:
    print(f"[ERROR] Unexpected error: {e}")
```

### Database Operations Module

**Module:** `python/db/operations.py`
**Purpose:** High-level database operations for common tasks.

```python
from python.db.operations import (
    create_table_from_dataframe,
    export_table_to_feather,
    validate_table_schema
)

# Create table from DataFrame schema
create_table_from_dataframe(
    db_manager=db,
    table_name="ne25_raw",
    dataframe=df,
    if_exists="replace"
)

# Export table to Feather
export_table_to_feather(
    db_manager=db,
    table_name="ne25_transformed",
    output_path="output.feather"
)

# Validate table schema
is_valid = validate_table_schema(
    db_manager=db,
    table_name="ne25_raw",
    expected_columns=["pid", "record_id", "age"]
)
```

---

## Data Refresh Strategy

**Important:** The pipeline uses `replace` mode for database operations to ensure clean datasets without duplicates.

### Replace Mode (Default)

```python
db = DatabaseManager()

# This replaces the entire table
success, rows = db.insert_data(
    table_name="ne25_raw",
    data=df,
    mode="replace"  # Drops table if exists, creates new
)
```

**Why replace?**
- **No duplicates:** Fresh start on every pipeline run
- **Schema changes:** Automatically handles column additions/removals
- **Idempotent:** Running pipeline multiple times produces same result

### Append Mode

For additive operations (e.g., adding new survey responses):

```python
# Append new data without dropping table
success, rows = db.insert_data(
    table_name="ne25_raw",
    data=new_df,
    mode="append"  # Adds rows to existing table
)
```

### Fail Mode

For safety-critical operations:

```python
# Fail if table already exists
success, rows = db.insert_data(
    table_name="ne25_raw",
    data=df,
    mode="fail"  # Raises error if table exists
)
```

### Pipeline Refresh Pattern

**NE25 Pipeline:**
1. Drop all tables at start (fresh slate)
2. Insert raw data with `mode="replace"`
3. Insert transformed data with `mode="replace"`
4. Generate metadata

**ACS/NHIS/NSCH Pipelines:**
1. Check if data exists for state/year
2. Replace existing data with `mode="replace"`
3. Metadata tables use `mode="append"` (cumulative)

---

## Logging Utilities

**Module:** `python/utils/logging.py`
**Purpose:** Structured logging for pipeline operations.

### Quick Start

```python
import structlog

logger = structlog.get_logger()

# Structured logging
logger.info("data_loaded", records=3906, tables=11, size_mb=47.2)
logger.warning("missing_variables", variables=["age", "sex"], count=2)
logger.error("database_connection_failed", host="localhost", error="timeout")
```

### Context-Aware Logging

```python
from python.utils.logging import with_logging

@with_logging("extract_data")
def extract_data(project_id: str):
    logger = structlog.get_logger()
    logger.info("extraction_started", project_id=project_id)

    # ... extraction logic ...

    logger.info("extraction_completed", records=1000)
    return data

# Logs automatically include function name, execution time
```

### Performance Logging

```python
from python.utils.logging import PerformanceLogger

logger = structlog.get_logger()

with PerformanceLogger(logger, operation="database_insert", table="ne25_raw"):
    db.insert_data("ne25_raw", df)
# Logs execution time automatically
```

---

## Configuration Management

**Module:** `python/db/config.py`
**Purpose:** Load and manage YAML configuration files.

### Load Configuration

```python
from python.db.config import load_config, get_database_path

# Load config
config = load_config("config/sources/ne25.yaml")

# Get database path
db_path = get_database_path(config)
print(f"Database: {db_path}")

# Access config values
source = config['source']['name']
table_name = config['database']['tables']['raw']
```

### Configuration Structure

**Example: `config/sources/ne25.yaml`**
```yaml
source:
  name: "NE25"
  type: "redcap"

database:
  path: "data/duckdb/kidsights_local.duckdb"
  tables:
    raw: "ne25_raw"
    transformed: "ne25_transformed"

processing:
  chunk_size: 500
  replace_mode: true
```

### Environment-Specific Config

```python
import os

# Load config based on environment
env = os.getenv("ENVIRONMENT", "dev")
config_path = f"config/sources/ne25.{env}.yaml"
config = load_config(config_path)
```

---

## Imputation Utilities

**Module:** `python/imputation/`
**Purpose:** Multiple imputation system for handling geographic uncertainty in survey responses

### Overview

The imputation utilities provide a complete framework for generating, storing, and retrieving multiple imputations (M=5) of geographic variables with allocation factors (afact) < 1. The system uses a **variable-specific storage approach** with **single source of truth** configuration.

### Key Design Principles

1. **Store Realized Values:** Sampled geography assignments (not probabilities) for consistency across analyses
2. **Variable-Specific Tables:** Normalized storage (one table per imputed variable)
3. **Selective Storage:** Only ambiguous records stored (afact < 1), deterministic records use base table values
4. **Composite Primary Key:** `(study_id, pid, record_id, imputation_m)` for multi-study support
5. **Single Source of Truth:** R calls Python via reticulate (no code duplication)

### Quick Start

```python
from python.imputation import get_completed_dataset, get_all_imputations

# Get imputation 3 with geography variables
df3 = get_completed_dataset(3, variables=['puma', 'county'])

# Get all 5 imputations in long format
df_long = get_all_imputations(variables=['puma', 'county', 'census_tract'])

# Analyze distribution across imputations
df_long.groupby(['imputation_m', 'puma']).size()
```

### Configuration

**File:** `config/imputation/imputation_config.yaml`

```yaml
n_imputations: 5        # M = 5 (easily scalable to M=20+)
random_seed: 42         # For reproducibility
geography:
  variables:
    - puma
    - county
    - census_tract
  method: "probabilistic_allocation"
```

**Access in Python:**
```python
from python.imputation import get_n_imputations, get_random_seed

M = get_n_imputations()  # Returns 5
seed = get_random_seed()  # Returns 42
```

### Core Functions

#### `get_completed_dataset()`

Retrieve a single completed dataset for imputation m by combining observed data with imputed values.

```python
from python.imputation import get_completed_dataset

# Get imputation 3 with specific variables
df3 = get_completed_dataset(
    imputation_m=3,
    variables=['puma', 'county'],
    base_table='ne25_transformed',
    study_id='ne25'
)

# All imputed variables
df5 = get_completed_dataset(5)  # variables=None → all variables
```

**How it works:**
- LEFT JOIN imputed tables to base table
- COALESCE: Use imputed value if available, otherwise use base table value
- Only ambiguous records (afact < 1) have entries in imputation tables

#### `get_all_imputations()`

Get all M imputations in long format with `imputation_m` column.

```python
from python.imputation import get_all_imputations

# Long format across all M=5 imputations
df_long = get_all_imputations(variables=['puma', 'county'])

# Analyze variance across imputations
variance_by_record = df_long.groupby('record_id')['puma'].nunique()
high_variance = variance_by_record[variance_by_record > 1]
```

#### `get_imputation_metadata()`

Get metadata about imputed variables.

```python
from python.imputation import get_imputation_metadata

meta = get_imputation_metadata()
# Returns DataFrame:
#   variable_name  n_imputations  imputation_method  created_date
#   puma           5              probabilistic...   2025-10-06
#   county         5              probabilistic...   2025-10-06
```

#### `validate_imputations()`

Validate imputation tables for completeness and consistency.

```python
from python.imputation import validate_imputations

results = validate_imputations()
if results['all_valid']:
    print(f"[OK] All {results['variables_checked']} variables validated")
else:
    for issue in results['issues']:
        print(f"[WARN] {issue}")
```

### R Integration (via reticulate)

**File:** `R/imputation/helpers.R`

R functions call Python directly for single source of truth:

```r
library(reticulate)
source("R/imputation/helpers.R")

# Get imputation 3
df3 <- get_completed_dataset(3, variables = c("puma", "county"))

# Get list for mitools/survey package
imp_list <- get_imputation_list()

# Survey analysis
library(survey)
library(mitools)
results <- lapply(imp_list, function(df) {
  design <- svydesign(ids = ~1, weights = ~weight, data = df)
  svymean(~outcome, design)
})
combined <- mitools::MIcombine(results)
summary(combined)
```

### Database Schema

**Imputation Tables:**

```sql
CREATE TABLE imputed_puma (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  puma VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE TABLE imputation_metadata (
  variable_name VARCHAR PRIMARY KEY,
  n_imputations INTEGER NOT NULL,
  imputation_method VARCHAR,
  created_date TIMESTAMP,
  notes TEXT
);
```

**Current Status (NE25):**
- `imputed_puma`: 4,390 rows (878 records × 5 imputations)
- `imputed_county`: 5,270 rows (1,054 records × 5 imputations)
- `imputed_census_tract`: 15,820 rows (3,164 records × 5 imputations)
- `imputation_metadata`: 3 rows

**Total:** 25,483 rows (50%+ storage reduction vs storing all records)

### Usage Examples

#### Example 1: Compare PUMA Distribution Across Imputations

```python
from python.imputation import get_all_imputations
import pandas as pd

df = get_all_imputations(variables=['puma'])

# PUMA distribution by imputation
puma_dist = df.groupby(['imputation_m', 'puma']).size().unstack(fill_value=0)
print(puma_dist)

# Check variance for specific record
record_6 = df[df['record_id'] == 6][['imputation_m', 'puma']]
print(f"Record 6 PUMA assignments:\n{record_6}")
```

#### Example 2: Survey Analysis with Multiple Imputations

```python
from python.imputation import get_n_imputations, get_completed_dataset
import numpy as np

M = get_n_imputations()
estimates = []

for m in range(1, M+1):
    df_m = get_completed_dataset(m, variables=['puma', 'county'])

    # Analyze outcome by PUMA
    puma_means = df_m.groupby('puma')['outcome'].mean()
    estimates.append(puma_means)

# Combine estimates (Rubin's rules)
combined_mean = np.mean([est.mean() for est in estimates])
between_var = np.var([est.mean() for est in estimates], ddof=1)
within_var = np.mean([est.var() for est in estimates])

total_var = within_var + (1 + 1/M) * between_var
```

#### Example 3: Generate New Imputations

```python
from python.imputation import get_n_imputations
from python.db.connection import DatabaseManager
import pandas as pd
import numpy as np

# Load configuration
M = get_n_imputations()
random_state = np.random.RandomState(42)

# Get base data with ambiguous geography
db = DatabaseManager()
with db.get_connection(read_only=True) as conn:
    query = """
        SELECT study_id, pid, record_id, puma, puma_afact
        FROM ne25_transformed
        WHERE puma LIKE '%;%'  -- Multiple values
    """
    df = pd.read_sql(query, conn)

# Parse semicolon-delimited values
def sample_geography(values_str, probs_str, M, random_state):
    values = [v.strip() for v in values_str.split(';')]
    probs = [float(p.strip()) for p in probs_str.split(';')]
    probs = np.array(probs) / sum(probs)  # Normalize
    return random_state.choice(values, size=M, p=probs).tolist()

# Generate M imputations per record
imputation_data = []
for _, row in df.iterrows():
    samples = sample_geography(row['puma'], row['puma_afact'], M, random_state)
    for m, puma_value in enumerate(samples, start=1):
        imputation_data.append({
            'study_id': row['study_id'],
            'pid': row['pid'],
            'record_id': row['record_id'],
            'imputation_m': m,
            'puma': puma_value
        })

# Insert into database
imputed_df = pd.DataFrame(imputation_data)
with db.get_connection() as conn:
    conn.execute("DELETE FROM imputed_puma WHERE study_id = 'ne25'")
    conn.execute("INSERT INTO imputed_puma SELECT * FROM imputed_df")
```

### Pipeline Integration

**Setup (one-time):**
```bash
python scripts/imputation/00_setup_imputation_schema.py
```

**Generate imputations:**
```bash
python scripts/imputation/01_impute_geography.py
```

**Validate:**
```bash
python -m python.imputation.helpers
```

### Documentation

- **Architecture:** [docs/imputation/IMPUTATION_PIPELINE.md](../imputation/IMPUTATION_PIPELINE.md)
- **Usage Guide:** [docs/imputation/IMPUTATION_SETUP_COMPLETE.md](../imputation/IMPUTATION_SETUP_COMPLETE.md)
- **Quick Reference:** [docs/QUICK_REFERENCE.md](../QUICK_REFERENCE.md#imputation-pipeline)

---

## Common Patterns

### Pattern 1: Extract → Transform → Load (ETL)

```python
from python.utils.r_executor import execute_r_script
from python.db.connection import DatabaseManager
import pandas as pd

# 1. Extract (Python)
db = DatabaseManager()
with db.get_connection(read_only=True) as conn:
    raw_data = pd.read_sql("SELECT * FROM source_table", conn)

# 2. Transform (R)
r_code = f'''
library(dplyr)
library(arrow)

data <- arrow::read_feather("temp_input.feather")
result <- data %>%
  dplyr::filter(age > 0) %>%
  dplyr::mutate(age_years = age / 365.25)
arrow::write_feather(result, "temp_output.feather")
'''

raw_data.to_feather("temp_input.feather")
output, rc = execute_r_script(r_code)
transformed_data = pd.read_feather("temp_output.feather")

# 3. Load (Python)
db.insert_data("transformed_table", transformed_data, mode="replace")
```

### Pattern 2: Validation Pipeline

```python
from python.db.connection import DatabaseManager
import structlog

logger = structlog.get_logger()
db = DatabaseManager()

# Validation checks
checks = [
    ("Record count", "SELECT COUNT(*) FROM ne25_raw", 3906),
    ("No nulls in PID", "SELECT COUNT(*) FROM ne25_raw WHERE pid IS NULL", 0),
    ("Age range", "SELECT MAX(age) FROM ne25_raw WHERE age < 6", True)
]

for check_name, query, expected in checks:
    result = db.execute_query(query)[0][0]
    if result == expected:
        logger.info("validation_passed", check=check_name)
    else:
        logger.error("validation_failed", check=check_name,
                    expected=expected, actual=result)
```

### Pattern 3: Data Export

```python
from python.db.connection import DatabaseManager
import pandas as pd

db = DatabaseManager()

# Export to multiple formats
with db.get_connection(read_only=True) as conn:
    df = pd.read_sql("SELECT * FROM ne25_transformed", conn)

# Feather (fast, preserves types)
df.to_feather("export.feather")

# CSV (human-readable)
df.to_csv("export.csv", index=False)

# Parquet (compressed, columnar)
df.to_parquet("export.parquet", compression="snappy")
```

---

## Related Documentation

- **Coding Standards:** [CODING_STANDARDS.md](CODING_STANDARDS.md) - Python style guidelines
- **Pipeline Steps:** [../architecture/PIPELINE_STEPS.md](../architecture/PIPELINE_STEPS.md) - How utilities fit into pipelines
- **Database Schema:** [../architecture/PIPELINE_OVERVIEW.md](../architecture/PIPELINE_OVERVIEW.md) - Database structure

---

*Last Updated: October 2025*

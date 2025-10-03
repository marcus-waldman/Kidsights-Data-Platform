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

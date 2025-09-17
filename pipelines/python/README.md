# Python Pipeline Scripts

This directory contains Python scripts that handle database operations for the Kidsights Data Platform. These scripts were created to eliminate R DuckDB segmentation faults and provide robust, reliable database operations.

## Architecture Overview

The Python pipeline scripts implement a hybrid R-Python architecture:

```
R Pipeline (orchestration) → Python Scripts (database ops) → DuckDB Storage
        ↓                            ↓                           ↓
  - REDCap extraction           - Connection pooling         - Local database
  - Data transformations        - Error handling             - Table management
  - Type harmonization          - Chunked processing         - Metadata storage
  - Eligibility validation      - Performance monitoring     - Documentation
```

## Core Scripts

### `init_database.py`

**Purpose**: Initialize DuckDB database schema and tables for NE25 pipeline.

**Usage**:
```bash
python pipelines/python/init_database.py --config config/sources/ne25.yaml
```

**Features**:
- Creates all required NE25 tables with proper schema
- Handles table recreation with DROP/CREATE pattern
- Validates configuration file before execution
- Uses DatabaseManager for connection pooling

**Tables Created**:
- `ne25_raw` - Combined raw data from all projects
- `ne25_raw_pid{7679,7943,7999,8014}` - Project-specific raw data
- `ne25_transformed` - Data after recode_it() transformations
- `ne25_metadata` - Variable metadata and documentation
- `ne25_data_dictionary` - Field definitions by project
- `ne25_eligibility` - Eligibility determination results

**Example Configuration**:
```yaml
# config/sources/ne25.yaml
database:
  path: "data/duckdb/kidsights_local.duckdb"

tables:
  raw_data_table: "ne25_raw"
  transformed_table: "ne25_transformed"
  # ... additional table definitions
```

### `insert_raw_data.py`

**Purpose**: Bulk insertion of data into DuckDB tables with memory-efficient chunked processing.

**Usage**:
```bash
# Insert CSV data
python pipelines/python/insert_raw_data.py --data-file temp_data.csv --table-name ne25_raw

# Insert Parquet data (preferred)
python pipelines/python/insert_raw_data.py --data-file temp_data.parquet --table-name ne25_transformed

# Insert with custom chunk size
python pipelines/python/insert_raw_data.py --data-file data.csv --table-name ne25_raw --chunk-size 500
```

**Features**:
- **Format Support**: Both CSV and Parquet input files
- **Chunked Processing**: Memory-efficient insertion for large datasets
- **Error Recovery**: Automatic retry logic with exponential backoff
- **Performance Monitoring**: Detailed timing and progress logging
- **Connection Management**: Uses DatabaseManager for reliability

**Processing Flow**:
```
Data File → Format Detection → Chunked Reading → DuckDB Insertion → Verification
    ↓              ↓                 ↓               ↓              ↓
CSV/Parquet → pandas.read_* → Iterator chunks → TRUNCATE+INSERT → Row count check
```

**Performance Characteristics**:
- **Default chunk size**: 1000 rows
- **Memory usage**: ~50MB per chunk for typical NE25 data
- **Typical throughput**: 10,000+ rows/second for local DuckDB

### `generate_metadata.py`

**Purpose**: Comprehensive metadata generation and analysis for variables in the database.

**Usage**:
```bash
# Generate metadata for all variables
python pipelines/python/generate_metadata.py --source-table ne25_transformed

# Generate metadata for derived variables only
python pipelines/python/generate_metadata.py \
  --source-table ne25_transformed \
  --derived-only \
  --derived-config config/derived_variables.yaml

# Export to specific format
python pipelines/python/generate_metadata.py \
  --source-table ne25_transformed \
  --output-format feather \
  --output-file temp/ne25_metadata.feather
```

**Features**:
- **Comprehensive Analysis**: Missing data, unique values, data types, factor levels
- **Multiple Export Formats**: Feather, Parquet, CSV, JSON
- **Derived Variables Filter**: Focus on transformation outputs only
- **Factor Variable Support**: Extracts levels, labels, and value counts
- **Performance Optimized**: Uses chunked processing for large tables

**Metadata Fields Generated**:

| Field | Description | Example |
|-------|-------------|---------|
| `variable_name` | Column name | `"eligible"` |
| `variable_label` | Human-readable label | `"Meets study inclusion criteria"` |
| `category` | Variable category | `"eligibility"` |
| `data_type` | R/statistical data type | `"logical"` |
| `storage_mode` | Database storage type | `"BOOLEAN"` |
| `n_total` | Total observations | `3906` |
| `n_missing` | Missing values count | `0` |
| `missing_percentage` | Percentage missing | `0.0` |
| `unique_values` | Count of unique values | `2` |
| `factor_levels` | Categorical levels | `["FALSE", "TRUE"]` |
| `value_labels` | Value descriptions | `{"FALSE": "Not eligible", "TRUE": "Eligible"}` |
| `value_counts` | Frequency distribution | `{"FALSE": 234, "TRUE": 3672}` |
| `reference_level` | Base level for analysis | `"FALSE"` |
| `ordered_factor` | Is ordered categorical | `false` |
| `factor_type` | Factor classification | `"derived"` |
| `transformation_notes` | How variable was created | `"Created by recode_it()"` |
| `min_value` | Minimum (numeric) | `0.0` |
| `max_value` | Maximum (numeric) | `1.0` |
| `mean_value` | Mean (numeric) | `0.94` |
| `summary_statistics` | Additional stats | `{"sd": 0.24, "median": 1.0}` |

#### **Derived Variables Mode**

When using `--derived-only`, the script filters to the 21 variables created by transformations:

**Inclusion/Eligibility (3 vars)**:
- `eligible`, `authentic`, `include`

**Race/Ethnicity (6 vars)**:
- Child: `hisp`, `race`, `raceG`
- Caregiver: `a1_hisp`, `a1_race`, `a1_raceG`

**Education (12 vars)**:
- 8 categories: `educ_max`, `educ_a1`, `educ_a2`, `educ_mom`
- 4 categories: `educ4_max`, `educ4_a1`, `educ4_a2`, `educ4_mom`
- 6 categories: `educ6_max`, `educ6_a1`, `educ6_a2`, `educ6_mom`

#### **Factor Variable Analysis**

For categorical variables, the script performs detailed factor analysis:

```python
# Example factor analysis output
{
  "variable_name": "raceG",
  "factor_levels": ["White", "Black", "Hispanic", "Other", "Multiracial"],
  "value_labels": {
    "White": "Non-Hispanic White",
    "Black": "Non-Hispanic Black/African American",
    "Hispanic": "Hispanic/Latino (any race)",
    "Other": "Other single race",
    "Multiracial": "Multiple races selected"
  },
  "value_counts": {
    "White": 2156,
    "Black": 423,
    "Hispanic": 892,
    "Other": 187,
    "Multiracial": 248
  },
  "reference_level": "White",
  "ordered_factor": false,
  "factor_type": "derived"
}
```

## Database Integration

### DatabaseManager Integration

All scripts use the `python.db.DatabaseManager` class for consistent database operations:

```python
from python.db.connection import DatabaseManager

# Initialize with configuration
db_manager = DatabaseManager(db_path="data/duckdb/kidsights_local.duckdb")

# Test connection
if not db_manager.test_connection():
    raise RuntimeError("Database connection failed")

# Execute operations with automatic retry
with db_manager.get_connection() as conn:
    result = conn.execute("SELECT COUNT(*) FROM ne25_transformed").fetchone()
```

### Error Handling and Recovery

All scripts implement robust error handling:

1. **Connection Errors**: Automatic retry with exponential backoff
2. **Data Errors**: Detailed logging with problematic record identification
3. **Memory Errors**: Automatic chunk size reduction
4. **Schema Errors**: Clear error messages with suggested fixes

### Performance Monitoring

Scripts include comprehensive performance monitoring:

```python
# Example performance output
INFO - Starting metadata generation for ne25_transformed
INFO - Found 588 columns to analyze
INFO - Processing chunk 1/6 (100 columns)
INFO - Chunk 1 completed in 2.3 seconds
INFO - Factor analysis completed for 45 categorical variables
INFO - Generated metadata for 588 variables in 12.7 seconds
INFO - Exported 1.2MB Feather file to temp/metadata.feather
```

## Integration with R Pipeline

The Python scripts are designed to be called from the R pipeline orchestration:

### R Pipeline Integration

```r
# In pipelines/orchestration/ne25_pipeline.R

# Step 1: Initialize database
system_result <- system("python pipelines/python/init_database.py --config config/sources/ne25.yaml")
if (system_result != 0) stop("Database initialization failed")

# Step 2: Insert raw data
temp_file <- file.path(tempdir(), "ne25_raw.feather")
arrow::write_feather(raw_data, temp_file)
system_result <- system(paste("python pipelines/python/insert_raw_data.py --data-file", temp_file, "--table-name ne25_raw"))
if (system_result != 0) stop("Raw data insertion failed")

# Step 3: Generate metadata
system_result <- system("python pipelines/python/generate_metadata.py --source-table ne25_transformed --derived-only")
if (system_result != 0) stop("Metadata generation failed")
```

### Temporary File Management

The integration uses temporary files for data exchange:

```r
# R creates temporary files
temp_dir <- file.path(tempdir(), "ne25_pipeline")
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

# Export data for Python
feather_file <- file.path(temp_dir, "ne25_transformed.feather")
arrow::write_feather(transformed_data, feather_file)

# Python processes and stores in database
system(paste("python pipelines/python/insert_raw_data.py --data-file", feather_file, "--table-name ne25_transformed"))
```

## Configuration Management

### Database Configuration

Scripts use YAML configuration files for database settings:

```yaml
# config/sources/ne25.yaml
database:
  path: "data/duckdb/kidsights_local.duckdb"
  connection_pool_size: 5
  retry_attempts: 3
  timeout_seconds: 300

tables:
  raw_data_table: "ne25_raw"
  transformed_table: "ne25_transformed"
  metadata_table: "ne25_metadata"
```

### Derived Variables Configuration

The metadata generation script uses the derived variables configuration:

```yaml
# config/derived_variables.yaml
all_derived_variables:
  - eligible
  - authentic
  - include
  # ... 18 additional variables

variable_labels:
  eligible: "Meets study inclusion criteria"
  authentic: "Passes authenticity screening"
  # ... additional labels
```

## Troubleshooting

### Common Issues

#### **Database Connection Failures**
```bash
# Test database connection
python -c "from python.db.connection import DatabaseManager; print('Success' if DatabaseManager().test_connection() else 'Failed')"

# Check database file permissions
ls -la data/duckdb/kidsights_local.duckdb
```

#### **Memory Issues with Large Datasets**
```bash
# Reduce chunk size for memory-constrained environments
python pipelines/python/insert_raw_data.py --data-file large_data.csv --table-name ne25_raw --chunk-size 100
```

#### **Missing Dependencies**
```bash
# Install required Python packages
pip install duckdb pandas pyarrow pyyaml structlog
```

#### **Configuration Errors**
```bash
# Validate YAML configuration
python -c "import yaml; print(yaml.safe_load(open('config/sources/ne25.yaml')))"
```

### Performance Optimization

#### **For Large Datasets (>100k rows)**
1. Use Parquet format instead of CSV (3-5x faster)
2. Increase chunk size to 5000-10000 rows
3. Ensure adequate disk space (DuckDB uses temp files)

#### **For Memory-Constrained Environments**
1. Reduce chunk size to 100-500 rows
2. Close other applications to free memory
3. Use CSV format if Parquet causes memory issues

#### **For Network Storage**
1. Use local temporary directory for intermediate files
2. Copy database file locally before processing
3. Sync back to network storage after completion

### Debugging

#### **Enable Verbose Logging**
```bash
# Set environment variable for detailed logging
export PYTHONPATH="."
export LOG_LEVEL="DEBUG"
python pipelines/python/generate_metadata.py --source-table ne25_transformed
```

#### **Test Individual Components**
```python
# Test database connection
from python.db.connection import DatabaseManager
db = DatabaseManager()
print("Connection test:", db.test_connection())

# Test configuration loading
from python.db.config import load_config
config = load_config("config/sources/ne25.yaml")
print("Config loaded:", config is not None)

# Test data loading
import pandas as pd
df = pd.read_feather("temp/test_data.feather")
print("Data shape:", df.shape)
```

## Development Guidelines

### Adding New Scripts

1. **Follow naming convention**: `action_description.py`
2. **Use DatabaseManager**: Import from `python.db.connection`
3. **Implement error handling**: Use try-catch with detailed logging
4. **Add performance monitoring**: Log execution time and progress
5. **Include configuration**: Accept YAML config files where appropriate
6. **Document usage**: Add comprehensive docstrings and CLI help

### Code Style

```python
#!/usr/bin/env python3
"""
Brief description of script purpose.

Longer description including usage examples and important notes.
"""

import argparse
import sys
from pathlib import Path

from python.db.connection import DatabaseManager
from python.utils.logging import get_logger

logger = get_logger(__name__)

def main():
    """Main function with clear structure."""
    parser = argparse.ArgumentParser(description="Script description")
    parser.add_argument("--required-arg", required=True, help="Required argument")
    parser.add_argument("--optional-arg", default="default", help="Optional argument")

    args = parser.parse_args()

    try:
        # Main logic here
        logger.info("Starting operation")
        result = perform_operation(args)
        logger.info("Operation completed successfully")
        return 0
    except Exception as e:
        logger.error(f"Operation failed: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

### Testing

```bash
# Test script execution
python pipelines/python/your_script.py --help

# Test with minimal data
python pipelines/python/your_script.py --test-mode --data-file small_test.csv

# Validate output
python -c "import pandas as pd; print(pd.read_feather('output.feather').shape)"
```

## Related Documentation

- **Database Operations**: `python/db/README.md`
- **R Pipeline Integration**: `pipelines/orchestration/README.md`
- **Configuration Management**: `config/README.md`
- **Derived Variables System**: `CLAUDE.md` (Derived Variables section)
- **Error Handling**: `python/utils/README.md`

---

*Last Updated: September 17, 2025*
*For questions or issues, see the main project documentation in `README.md`*
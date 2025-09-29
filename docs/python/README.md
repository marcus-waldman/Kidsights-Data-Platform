# Python Components Documentation

This directory contains documentation for Python components of the hybrid R/Python architecture.

## Contents

- **`architecture.md`** - Detailed Python component architecture

## Python Module Structure

### Database Layer (`/python/db/`)
- **`connection.py`** - DatabaseManager class for DuckDB connections
- **`operations.py`** - Database CRUD operations (insert, update, query)

### Pipeline Executables (`/pipelines/python/`)
- **`init_database.py`** - Creates database schema from YAML config
- **`insert_raw_data.py`** - Stores raw data from Feather files
- **`insert_transformed_data.py`** - Stores derived variables

### Utilities (`/python/utils/`)
- **`r_executor.py`** - Execute R code from Python with proper error handling

## Why Python for Database Operations?

**Problem**: R's DuckDB package caused 50% pipeline failure rate with segmentation faults

**Solution**: Python handles all database I/O with benefits:
- 100% reliability (no more segfaults)
- Rich error context for debugging
- Efficient chunked processing for large datasets
- Perfect compatibility with Apache Feather format

## Usage Examples

### Database Connection
```python
from python.db.connection import DatabaseManager
dm = DatabaseManager()
success = dm.test_connection()
```

### R Script Execution
```python
from python.utils.r_executor import execute_r_script
code = '''
library(dplyr)
cat("Hello from R!\\n")
'''
output, return_code = execute_r_script(code)
```

### Database Initialization
```bash
python pipelines/python/init_database.py --config config/sources/ne25.yaml
```

## Related Files

- `/python/` - Source code directory
- `/docs/architecture/` - Overall system architecture
- Main `CLAUDE.md` - Development standards and quick start
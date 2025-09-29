# Pipeline Documentation

This directory contains documentation for the ETL pipeline architecture and workflows.

## Contents

- **`overview.md`** - Comprehensive pipeline architecture overview

## Pipeline Workflow

```
REDCap (4 projects) → R: Extract/Transform → Feather Files → Python: Database Ops → Local DuckDB
     3,906 records      REDCapR, recode_it()      arrow format      Chunked processing     47MB local
```

## Pipeline Components

### Orchestration Layer
- **Entry Point**: `run_ne25_pipeline.R`
- **Orchestration**: `/pipelines/orchestration/` - R scripts coordinating pipeline steps

### R Components
- **Extract**: `/R/extract/` - REDCapR-based data extraction
- **Harmonize**: `/R/harmonize/` - Cross-study data alignment
- **Transform**: `/R/transform/` - Derived variable creation (recode_it)
- **Utils**: `/R/utils/` - Shared utility functions

### Python Components
- **Database Init**: `pipelines/python/init_database.py`
- **Raw Data Storage**: `pipelines/python/insert_raw_data.py`
- **Operations**: `python/db/operations.py` - Database CRUD operations
- **Connection**: `python/db/connection.py` - DuckDB connection management

## Data Flow

1. **Database Init** - Creates schema in local DuckDB
2. **Extract** - R pulls data from 4 REDCap projects
3. **Raw Storage** - Python stores raw data via Feather files
4. **Transform** - R applies recode_it() for 21 derived variables
5. **Final Storage** - Python stores transformed data
6. **Documentation** - Auto-generates data dictionaries

## Configuration

- **Study Configs**: `/config/sources/*.yaml` - Project-specific settings
- **Database Config**: `/config/duckdb.yaml` - DuckDB connection settings
- **Derived Variables**: `/config/derived_variables.yaml` - Variable definitions

## Related Files

- `/docs/architecture/` - System architecture documentation
- Main `CLAUDE.md` - Pipeline execution guidelines
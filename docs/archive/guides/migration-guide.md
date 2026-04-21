# Migration Guide: R DuckDB to Python Architecture

This guide explains the migration from the original R DuckDB implementation to the new Python-based database architecture implemented in September 2025.

## Why We Migrated

### The Problem: R DuckDB Segmentation Faults
The original implementation used R's DuckDB package for all database operations. However, this led to persistent issues:

```r
# This would consistently crash:
con <- dbConnect(duckdb::duckdb(), "database.duckdb")
# *** Segmentation fault ***
```

### Impact
- **Pipeline Failures**: ~50% of pipeline runs failed with segmentation faults
- **Data Loss Risk**: Incomplete database operations
- **Debugging Difficulty**: No useful error messages from crashes
- **Production Instability**: Unreliable for automated runs

### The Solution: Hybrid Architecture
- **Keep R for**: Pipeline orchestration, REDCap extraction, data transformations
- **Use Python for**: All database operations, metadata generation, error handling

## What Changed

### Before (R DuckDB)
```r
# All database operations in R
library(DBI)
library(duckdb)

con <- dbConnect(duckdb::duckdb(), "database.duckdb")  # Segmentation fault risk
dbWriteTable(con, "table", data)                      # Segmentation fault risk
dbDisconnect(con)                                     # Segmentation fault risk
```

### After (Python Database + R Orchestration)
```r
# R handles orchestration, Python handles database
write.csv(data, "temp_data.csv")
system2("python", c("pipelines/python/insert_raw_data.py",
                    "--data-file", "temp_data.csv",
                    "--table-name", "table"))
```

## Migration Steps

### 1. Install Python Dependencies
```bash
pip install duckdb pandas pyyaml structlog
```

### 2. Update Configuration
Change database path from OneDrive to local:
```yaml
# Old (OneDrive)
database_path: "C:/Users/.../OneDrive/.../kidsights.duckdb"

# New (Local)
database_path: "data/duckdb/kidsights_local.duckdb"
```

### 3. Replace R DuckDB Calls

#### Database Initialization
```r
# Old (R - would crash)
con <- connect_kidsights_db()
init_ne25_schema(con)

# New (Python - stable)
system2("python", c("pipelines/python/init_database.py",
                    "--config", "config/sources/ne25.yaml"))
```

#### Data Insertion
```r
# Old (R - would crash)
insert_ne25_data(con, data, "table_name")

# New (Python - stable)
write.csv(data, "temp_data.csv")
system2("python", c("pipelines/python/insert_raw_data.py",
                    "--data-file", "temp_data.csv",
                    "--table-name", "table_name"))
```

#### Metadata Generation
```r
# Old (R - would crash)
metadata <- create_variable_metadata(data, dict)
insert_metadata(con, metadata)

# New (Python - stable)
system2("python", c("pipelines/python/generate_metadata.py",
                    "--source-table", "ne25_transformed"))
```

### 4. Update Documentation Functions
```r
# Old (required database connection)
generate_interactive_dictionary(con = con, output_dir = "docs/...")

# New (no database connection needed)
generate_interactive_dictionary(output_dir = "docs/...")
```

## Key Differences

### Error Handling
| Aspect | Old (R DuckDB) | New (Python) |
|--------|----------------|--------------|
| **Segmentation Faults** | Frequent | None |
| **Error Messages** | "Segmentation fault" | Detailed error context |
| **Retry Logic** | None | Exponential backoff |
| **Recovery** | Manual restart | Automatic recovery |

### Performance
| Metric | Old (R DuckDB) | New (Python) |
|--------|----------------|--------------|
| **Success Rate** | ~50% | 100% |
| **Memory Usage** | Uncontrolled | Chunked processing |
| **Error Recovery** | None | Automatic |
| **Logging** | Basic | Comprehensive |

### Development Experience
| Aspect | Old (R DuckDB) | New (Python) |
|--------|----------------|--------------|
| **Debugging** | Impossible (crashes) | Rich error context |
| **Testing** | Unreliable | Consistent |
| **Monitoring** | None | Performance metrics |
| **Maintenance** | Frustrating | Straightforward |

## Backwards Compatibility

### What Still Works
- **R Functions**: All transformation and extraction logic unchanged
- **Configuration**: Same YAML structure
- **API Tokens**: Same environment variables
- **Output Format**: Same data dictionary structure

### What Changed
- **Database Location**: Now local instead of OneDrive
- **Function Signatures**: Some functions no longer require `con` parameter
- **Error Messages**: Much more detailed and helpful

## Troubleshooting Migration

### Common Issues

#### 1. Python Import Errors
```bash
# Error: ModuleNotFoundError: No module named 'yaml'
# Solution:
pip install pyyaml duckdb pandas structlog
```

#### 2. Path Issues
```bash
# Error: sys.path.insert issues
# Solution: Run from project root directory
cd /path/to/Kidsights-Data-Platform
```

#### 3. Configuration Path
```bash
# Error: Config file not found
# Solution: Use relative paths from project root
--config config/sources/ne25.yaml  # Not absolute paths
```

### Validation Steps

#### 1. Test Python Scripts
```bash
# Test database initialization
python pipelines/python/init_database.py --config config/sources/ne25.yaml

# Should output: "Database initialization completed successfully"
```

#### 2. Test Pipeline
```bash
# Run full pipeline
Rscript run_ne25_pipeline.R

# Should complete without segmentation faults
```

#### 3. Verify Output
Check for these files:
- `data/duckdb/kidsights_local.duckdb` - Database file
- `docs/data_dictionary/ne25/index.html` - Interactive dictionary

## Performance Improvements

### Before Migration
- Pipeline success rate: ~50%
- Average runtime: N/A (frequent crashes)
- Error debugging: Impossible
- Memory usage: Uncontrolled

### After Migration
- Pipeline success rate: 100%
- Average runtime: 2-3 minutes (3,906 records)
- Error debugging: Rich context and logging
- Memory usage: Controlled with chunking

## Benefits Realized

### 🔒 **Reliability**
- Zero segmentation faults since migration
- 100% pipeline success rate
- Predictable execution times

### 🔍 **Debugging**
- Detailed error messages with context
- Performance metrics for all operations
- Clear distinction between retryable and fatal errors

### 📈 **Performance**
- Chunked processing for large datasets
- Connection pooling and retry logic
- Memory-efficient operations

### 🛠️ **Maintenance**
- Clear separation of concerns (R vs Python)
- Modular architecture
- Easy to extend and modify

## Future Considerations

### Potential Further Migrations
- **Full Python Pipeline**: Could migrate R components to Python
- **Cloud Database**: Could use cloud-hosted DuckDB
- **Streaming Processing**: Could add real-time capabilities

### Maintaining the Hybrid
- **R Strengths**: REDCap integration, statistical transformations
- **Python Strengths**: Database operations, metadata processing
- **Keep Best of Both**: Current architecture maximizes each language's strengths

## Getting Help

### Resources
- [Python Architecture Documentation](../python/architecture.md)
- [Pipeline Overview](../pipeline/overview.md)
- [Troubleshooting Guide](troubleshooting.md)

### Support
If you encounter issues during migration:
1. Check the error logs for detailed context
2. Verify Python dependencies are installed
3. Ensure you're running from the project root directory
4. Review the [troubleshooting guide](troubleshooting.md)

The migration to Python-based database operations has eliminated the reliability issues while maintaining all the functionality of the original pipeline.
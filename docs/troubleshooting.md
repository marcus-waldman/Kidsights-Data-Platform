# Troubleshooting

> **📢 Documentation Updated**
>
> This troubleshooting guide has been updated for the Python architecture (September 2025).
>
> - **Current Troubleshooting**: See sections below for Python architecture issues
> - **Legacy Issues**: [Archived R DuckDB Troubleshooting](archive/pre-python-migration/troubleshooting.md)

## 🐍 Python Architecture Issues

### Import Errors

#### ModuleNotFoundError
```bash
Error: ModuleNotFoundError: No module named 'yaml'
```
**Solution**:
```bash
pip install pyyaml duckdb pandas structlog
```

#### Path Issues
```bash
Error: attempted relative import beyond top-level package
```
**Solution**: Run from project root directory:
```bash
cd /path/to/Kidsights-Data-Platform
python pipelines/python/init_database.py
```

### Windows Python Path Issues

#### "'python' not found" Error

**Symptom**:
```bash
Error: '"python"' not found
Pipeline execution failed
```

**Root Cause**:
Windows uses the `py` launcher instead of adding `python.exe` directly to PATH. When R scripts use `system2("python", ...)`, the command fails because "python" isn't found.

**Solution**:
The platform uses `get_python_path()` function (in `R/utils/environment_config.R`) which automatically resolves the correct Python executable by checking:

1. **`.env` file** - `PYTHON_EXECUTABLE` variable (highest priority)
2. **Common Windows paths** - `C:/Users/USERNAME/AppData/Local/Programs/Python/Python313/python.exe`
3. **System PATH fallback** - `py` launcher (Windows), `python3` (Mac/Linux)

**Verification**:
```r
# In R console
source("R/utils/environment_config.R")
python_path <- get_python_path()
print(python_path)
# Should show: C:/Users/YOUR_USERNAME/AppData/Local/Programs/Python/Python313/python.exe
```

**Configure `.env` file** (recommended for new machines):
```bash
# Add to .env file
PYTHON_EXECUTABLE=C:/Users/YOUR_USERNAME/AppData/Local/Programs/Python/Python313/python.exe
```

**For Developers - Fix Hardcoded Python Calls**:

If you're writing R code that calls Python, NEVER hardcode `"python"`:

```r
# ❌ INCORRECT - Will fail on Windows
system2("python", args = c("script.py"))

# ✅ CORRECT - Works cross-platform
source("R/utils/environment_config.R")
python_path <- get_python_path()
system2(python_path, args = c("script.py"))
```

**Related**: See [INSTALLATION_GUIDE.md - PYTHON_EXECUTABLE Configuration](setup/INSTALLATION_GUIDE.md#python_executable-configuration)

### Database Connection Issues

#### Database File Not Found
```bash
Error: Database file not found: data/duckdb/kidsights_local.duckdb
```
**Solution**: Initialize database first:
```bash
python pipelines/python/init_database.py --config config/sources/ne25.yaml
```

#### Permission Errors
```bash
Error: No write access to database
```
**Solution**: Check file permissions:
```bash
chmod 755 data/duckdb/
chmod 644 data/duckdb/kidsights_local.duckdb
```

### Configuration Issues

#### Config File Not Found
```bash
Error: Configuration file not found: config/sources/ne25.yaml
```
**Solution**: Use relative path from project root:
```bash
--config config/sources/ne25.yaml  # Correct
# Not: --config /full/path/to/config/sources/ne25.yaml
```

#### Missing API Tokens
```bash
Error: API token not found in environment variable
```
**Solution**: Set environment variables:
```r
# In R
Sys.setenv(KIDSIGHTS_API_TOKEN_7679 = "your_token_here")
```

## 📊 Pipeline Issues

### Memory Issues

#### Large Dataset Errors
```bash
Error: Memory allocation failed
```
**Solution**: Reduce chunk size:
```bash
python pipelines/python/insert_raw_data.py --chunk-size 100
```

#### DataFrame Memory Usage
```python
# Check memory usage
df.memory_usage(deep=True).sum() / 1024 / 1024  # MB
```

### Performance Issues

#### Slow Database Operations
**Check**:
- Database file size
- Available disk space
- Chunk size settings

**Solution**: Optimize chunk size:
```python
# For large datasets, use smaller chunks
chunk_size = 100  # Instead of 1000
```

#### Connection Timeouts
**Solution**: Increase timeout:
```python
# In database operations
timeout = 60  # seconds
```

## 🔧 Development Issues

### Testing Errors

#### Unit Test Failures
```bash
# Test individual components
python -c "from db import DatabaseManager; print('Import successful')"
```

#### Integration Test Issues
```bash
# Test full workflow
python pipelines/python/init_database.py --config config/sources/ne25.yaml --log-level DEBUG
```

### Code Issues

#### Linting Errors
```bash
# Python code style
flake8 python/
```

#### Type Checking
```bash
# Optional type checking
mypy python/
```

## 📝 Logging and Debugging

### Enable Debug Logging
```bash
python pipelines/python/generate_metadata.py --log-level DEBUG
```

### Check Log Output
```python
# In Python scripts
logger.debug("Detailed debug information")
logger.info("Operation completed")
logger.error("Error occurred", extra={"context": "additional_info"})
```

### Performance Monitoring
```python
# Check operation timing
with PerformanceLogger(logger, "operation_name"):
    # Your operation here
    pass
```

## 🚨 Emergency Procedures

### Pipeline Completely Broken
1. **Check Python Installation**:
   ```bash
   python --version  # Should be 3.13+
   pip list | grep -E "(duckdb|pandas|pyyaml)"
   ```

2. **Reinitialize Database**:
   ```bash
   rm data/duckdb/kidsights_local.duckdb
   python pipelines/python/init_database.py --config config/sources/ne25.yaml
   ```

3. **Test Individual Components**:
   ```bash
   # Test database connection
   python -c "from db import DatabaseManager; dm = DatabaseManager(); print('Success' if dm.test_connection() else 'Failed')"
   ```

### Data Corruption
1. **Backup Current Database**:
   ```bash
   cp data/duckdb/kidsights_local.duckdb data/duckdb/backup_$(date +%Y%m%d).duckdb
   ```

2. **Reinitialize and Rerun**:
   ```bash
   python pipelines/python/init_database.py --config config/sources/ne25.yaml
   Rscript run_ne25_pipeline.R
   ```

## 🔄 Migration Issues

### Still Getting Segmentation Faults
If you still see segmentation faults, check:
1. **Are you still using R DuckDB calls?**
   ```r
   # Search for these in your code:
   grep -r "dbConnect.*duckdb" R/
   grep -r "DBI::" R/
   ```

2. **Update function calls**:
   ```r
   # Old (causes segfaults)
   con <- connect_kidsights_db()

   # New (uses Python)
   system2("python", "pipelines/python/init_database.py")
   ```

### Documentation Out of Date
- **Current docs**: [docs/python/](python/)
- **Archived docs**: [docs/archive/](archive/)
- **Migration guide**: [docs/guides/migration-guide.md](guides/migration-guide.md)

## 📞 Getting Help

### Self-Service
1. **Check logs** for detailed error context
2. **Review configuration** files for typos
3. **Verify Python dependencies** are installed
4. **Run from project root** directory

### Documentation
- [Python Architecture](python/architecture.md) - Technical overview
- [Pipeline Overview](pipeline/overview.md) - End-to-end documentation
- [Migration Guide](guides/migration-guide.md) - R DuckDB to Python

### Error Context
When reporting issues, include:
- **Full error message** with traceback
- **Command that failed**
- **Python and package versions**
- **Operating system**
- **Log output** with DEBUG level

The new Python architecture provides much better error messages and debugging capabilities compared to the legacy R DuckDB implementation that would just show "Segmentation fault".
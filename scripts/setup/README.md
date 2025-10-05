# Setup & Verification Scripts

This directory contains tools for setting up and verifying your Kidsights Data Platform installation.

---

## Quick Start

**Single command to verify everything:**
```bash
python scripts/setup/verify_installation.py
```

---

## Scripts

### `verify_installation.py`

**Automated installation verification script**

Performs comprehensive checks of your installation to ensure all components are properly configured.

**Usage:**
```bash
python scripts/setup/verify_installation.py
```

**What it checks:**
1. **Environment** - Python 3.13+, R 4.5.1+
2. **Python Packages** - duckdb, pandas, yaml, structlog, dotenv, ipumspy, pyreadstat
3. **R Packages** - dplyr, tidyr, stringr, yaml, REDCapR, arrow, duckdb
4. **Configuration** - .env file exists and has required variables
5. **API Keys** - IPUMS and REDCap key files exist and are readable
6. **Directory Structure** - Required data directories exist
7. **Database** - DuckDB connection works
8. **API Connectivity** - IPUMS API authentication works

**Exit codes:**
- `0` - All critical checks passed (ready to use)
- `1` - Critical checks failed (fix required)
- `2` - Warnings present (can proceed with caution)

**Example output:**
```
======================================================================
KIDSIGHTS DATA PLATFORM - INSTALLATION VERIFICATION
======================================================================

Project root: C:\Users\waldmanm\git-repositories\Kidsights-Data-Platform
Platform: Windows 10
Python: 3.13.0

======================================================================
1. ENVIRONMENT
======================================================================

  [OK]   Python version
         Python 3.13.0 (required: 3.13+)
  [OK]   R installation
         R version 4.5.1 (2025-01-15)

======================================================================
2. PYTHON PACKAGES
======================================================================

  [OK]   Python package: duckdb
         Database operations
  [OK]   Python package: pandas
         Data manipulation
  ...

======================================================================
VERIFICATION SUMMARY
======================================================================

  Total checks: 19
  Passed:  17
  Failed:  0
  Skipped: 2

  [OK] All critical checks passed!
  Your installation is ready to use.

Next steps:
  - Run NE25 pipeline: python run_ne25_pipeline.R
  - Run ACS pipeline: python pipelines/python/acs/extract_acs_data.py
  - See docs/QUICK_REFERENCE.md for more commands
```

---

## For Claude Installation Agent

Claude can use this script as an automated installation agent:

1. **Load the checklist:**
   ```
   Read docs/setup/INSTALLATION_CHECKLIST.md
   ```

2. **Run verification:**
   ```bash
   python scripts/setup/verify_installation.py
   ```

3. **Interpret results:**
   - `[OK]` - Check passed, mark todo as completed
   - `[FAIL]` - Check failed, show fix command from checklist
   - `[SKIP]` - Check skipped, mark todo as skipped

4. **Track progress:**
   Claude can convert the checklist into todo items and run each verification command sequentially, reporting status and providing fixes when checks fail.

---

## Manual Setup Workflow

**For human users following the installation guide:**

1. **Start with the guide:**
   ```
   docs/setup/INSTALLATION_GUIDE.md
   ```

2. **Use the checklist:**
   ```
   docs/setup/INSTALLATION_CHECKLIST.md
   ```

3. **Run verification after each section:**
   ```bash
   python scripts/setup/verify_installation.py
   ```

4. **Fix any failures** using the troubleshooting guidance in the checklist

5. **Repeat until all checks pass**

---

## Troubleshooting

### "Python not found"
- Ensure Python 3.13+ is installed
- Add Python to your PATH
- On Windows: Use `py -3.13` instead of `python`

### "Module not found: dotenv"
```bash
pip install python-dotenv
```

### ".env file not found"
```bash
cp .env.template .env
# Edit .env with your paths
```

### "IPUMS API key file not found"
1. Set `IPUMS_API_KEY_PATH` in `.env`
2. Create the file at that location
3. Get API key from https://account.ipums.org/api_keys
4. Save API key to the file (one line, no extra whitespace)

### "R not found"
- Windows: Install from https://cran.r-project.org/bin/windows/base/
- Mac: Install from https://cran.r-project.org/bin/macosx/
- Linux: `sudo apt-get install r-base`

### "Database connection failed"
- Ensure `data/duckdb/` directory exists: `mkdir -p data/duckdb`
- Check file permissions
- Verify database path: `python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().database_path)"`

---

## Advanced Usage

### Run only specific checks

**Check Python environment only:**
```python
from scripts.setup.verify_installation import check_python_version, check_python_packages
check_python_version()
check_python_packages()
```

**Check configuration only:**
```python
from scripts.setup.verify_installation import check_env_file, check_api_keys
env_exists, env_vars = check_env_file()
if env_exists:
    check_api_keys(env_vars)
```

### Integrate with CI/CD

```bash
# In your CI pipeline
python scripts/setup/verify_installation.py
if [ $? -eq 0 ]; then
    echo "Installation verified, proceeding with tests"
    python run_ne25_pipeline.R
else
    echo "Installation verification failed"
    exit 1
fi
```

---

## Related Documentation

- **Installation Guide:** `docs/setup/INSTALLATION_GUIDE.md`
- **Installation Checklist:** `docs/setup/INSTALLATION_CHECKLIST.md`
- **Quick Reference:** `docs/QUICK_REFERENCE.md`
- **Troubleshooting:** `docs/troubleshooting.md`

---

**Last Updated:** October 2025
**Version:** 1.0.0

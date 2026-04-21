# Kidsights Data Platform - Installation Guide

**Version:** 3.8.0 | **Last Updated:** April 2026 (drift-checked 2026-04-20)

This guide walks you through setting up the Kidsights Data Platform on a new machine or for a new collaborator. The platform is designed to be portable across Windows, macOS, and Linux systems.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Detailed Setup](#detailed-setup)
4. [Environment Configuration](#environment-configuration)
5. [API Key Setup](#api-key-setup)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

**R (version 4.5.1 or later)**
- **Windows:** Download from https://cran.r-project.org/bin/windows/base/
- **macOS:** Download from https://cran.r-project.org/bin/macosx/
- **Linux:** Use your package manager (e.g., `apt-get install r-base`)

**Python (version 3.13 or later)**
- Download from https://www.python.org/downloads/
- Ensure `pip` is installed

**Git**
- Download from https://git-scm.com/downloads

### Required R Packages

```r
# Install R packages (run in R console)
install.packages(c(
  "dplyr",
  "tidyr",
  "stringr",
  "yaml",
  "REDCapR",
  "arrow",
  "duckdb",
  "reticulate"  # Required for imputation pipeline (R-Python integration)
), dependencies = TRUE)
```

**⚠️ Important for R Users (Imputation Pipeline):**

If you plan to use the R imputation helpers (`R/imputation/helpers.R`), you must install `pyarrow` in the R reticulate Python environment:

```r
# Install pyarrow in reticulate environment
reticulate::py_install("pyarrow")
```

Or from command line:
```bash
# Windows
"C:/Users/YOUR_USERNAME/.virtualenvs/r-reticulate/Scripts/python.exe" -m pip install pyarrow

# Mac/Linux
~/.virtualenvs/r-reticulate/bin/python -m pip install pyarrow
```

**Why is pyarrow needed?** The imputation pipeline uses feather files for R-Python data exchange. Pandas requires pyarrow to read feather format. Without pyarrow, you'll see: `ImportError: Missing optional dependency 'pyarrow'`

### Required Python Packages

```bash
# Install Python packages
pip install duckdb pandas pyyaml structlog ipumspy pyreadstat python-dotenv
```

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/Kidsights-Data-Platform.git
cd Kidsights-Data-Platform
```

### 2. Configure Environment

```bash
# Copy the environment template
cp .env.template .env

# Edit .env with your local paths (see details below)
# Windows: notepad .env
# Mac/Linux: nano .env
```

### 3. Set Up API Keys

See [API Key Setup](#api-key-setup) section below.

### 4. Test Installation

```bash
# Test database connection
python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"
```

---

## Detailed Setup

### Step 1: Directory Structure

After cloning, your directory structure should look like:

```
Kidsights-Data-Platform/
├── .env                    # YOUR configuration (create from template, NOT in git)
├── .env.template          # Template for .env file
├── config/                # Configuration files
├── data/                  # Data storage (gitignored)
│   ├── acs/              # ACS data cache
│   ├── nhis/             # NHIS data cache
│   ├── nsch/             # NSCH data cache
│   └── duckdb/           # DuckDB database files
├── docs/                  # Documentation
├── pipelines/             # Pipeline scripts
├── python/                # Python modules
├── R/                     # R functions
└── scripts/               # Utility scripts
```

### Step 2: Create Data Directories

The data directories are gitignored. Create them manually:

```bash
# Windows (PowerShell or Command Prompt)
mkdir -p data\duckdb data\acs data\nhis data\nsch

# Mac/Linux
mkdir -p data/duckdb data/acs data/nhis data/nsch
```

---

## Environment Configuration

### Creating Your `.env` File

The `.env` file stores machine-specific and user-specific paths. **Never commit this file to git** (it's already in `.gitignore`).

**1. Copy the template:**

```bash
cp .env.template .env
```

**2. Edit `.env` with your paths:**

```bash
# Example .env for Windows
IPUMS_API_KEY_PATH=C:/Users/YOUR_USERNAME/my-APIs/IPUMS.txt
REDCAP_API_CREDENTIALS_PATH=C:/Users/YOUR_USERNAME/my-APIs/kidsights_redcap_api.csv

# Example .env for macOS
IPUMS_API_KEY_PATH=/Users/YOUR_USERNAME/.kidsights/IPUMS.txt
REDCAP_API_CREDENTIALS_PATH=/Users/YOUR_USERNAME/.kidsights/kidsights_redcap_api.csv

# Example .env for Linux
IPUMS_API_KEY_PATH=/home/YOUR_USERNAME/.kidsights/IPUMS.txt
REDCAP_API_CREDENTIALS_PATH=/home/YOUR_USERNAME/.kidsights/kidsights_redcap_api.csv
```

### Path Resolution Priority

The platform uses a **3-tier priority system** for configuration:

1. **Environment variables** (`.env` file) - HIGHEST PRIORITY
2. **Config YAML files** (`config/sources/*.yaml`)
3. **Hardcoded defaults** (cross-platform fallbacks) - LOWEST PRIORITY

**Example for IPUMS API key:**

```
Priority 1: IPUMS_API_KEY_PATH environment variable (from .env)
Priority 2: ~/.kidsights/IPUMS.txt (cross-platform home directory)
Priority 3: C:/Users/waldmanm/my-APIs/IPUMS.txt (legacy hardcoded path)
```

### PYTHON_EXECUTABLE Configuration

**Windows users often need to explicitly configure the Python executable path.**

#### Why This Matters

Windows uses the `py` launcher instead of adding `python.exe` directly to PATH. When R scripts call Python using `system2("python", ...)`, the command fails with:

```
Error: '"python"' not found
```

#### Solution: Configure in `.env`

Add the `PYTHON_EXECUTABLE` variable to your `.env` file:

```bash
# Windows - Find your Python installation
PYTHON_EXECUTABLE=C:/Users/YOUR_USERNAME/AppData/Local/Programs/Python/Python313/python.exe

# Mac (usually works without explicit config)
PYTHON_EXECUTABLE=/usr/local/bin/python3

# Linux (usually works without explicit config)
PYTHON_EXECUTABLE=/usr/bin/python3
```

#### How to Find Your Python Path

**Windows:**
```bash
# Method 1: Using py launcher
py -c "import sys; print(sys.executable)"

# Method 2: Using where command
where python
where py
```

**Mac/Linux:**
```bash
which python3
# Output: /usr/local/bin/python3
```

#### Verification

Test that Python is accessible:

```r
# In R console
source("R/utils/environment_config.R")
python_path <- get_python_path()
print(python_path)

# Should print something like:
# C:/Users/marcu/AppData/Local/Programs/Python/Python313/python.exe
```

#### Path Resolution Order

The `get_python_path()` function checks paths in this order:

1. **`.env` file** - `PYTHON_EXECUTABLE` variable (highest priority)
2. **Common installation paths**:
   - Windows: `C:/Users/USERNAME/AppData/Local/Programs/Python/Python313/python.exe`
   - Mac: `/usr/local/bin/python3`, `/opt/homebrew/bin/python3`
   - Linux: `/usr/bin/python3`
3. **System PATH** - `py` (Windows), `python3` (Mac/Linux)

**💡 Tip:** On a new Windows machine, always configure `PYTHON_EXECUTABLE` in `.env` to avoid path resolution issues.

---

## API Key Setup

### IPUMS API Key (for ACS and NHIS Pipelines)

**1. Register for IPUMS:**
- IPUMS USA: https://usa.ipums.org/usa/
- IPUMS NHIS: https://nhis.ipums.org/nhis/

**2. Get API Key:**
- Visit https://account.ipums.org/api_keys
- Generate a new API key
- Save the key (it's a long string, ~56 characters)

**3. Save to file:**

```bash
# Windows - Create directory and save key
mkdir C:\Users\YOUR_USERNAME\my-APIs
echo YOUR_API_KEY_HERE > C:\Users\YOUR_USERNAME\my-APIs\IPUMS.txt

# Mac/Linux - Recommended location
mkdir -p ~/.kidsights
echo YOUR_API_KEY_HERE > ~/.kidsights/IPUMS.txt
```

**4. Update `.env`:**

```bash
# Windows
IPUMS_API_KEY_PATH=C:/Users/YOUR_USERNAME/my-APIs/IPUMS.txt

# Mac/Linux
IPUMS_API_KEY_PATH=/home/YOUR_USERNAME/.kidsights/IPUMS.txt
```

### REDCap API Credentials (for NE25 Pipeline)

**1. Contact your REDCap administrator** to get API tokens for each project:
- Project 7679 (Kidsights Data Survey)
- Project 7943 (Email Registration)
- Project 7999 (Public)
- Project 8014 (Public Birth)

**2. Create CSV file** with this format:

```csv
project,pid,api_code
kidsights_data_survey,7679,YOUR_TOKEN_HERE
kidsights_email_registration,7943,YOUR_TOKEN_HERE
kidsights_public,7999,YOUR_TOKEN_HERE
kidsights_public_birth,8014,YOUR_TOKEN_HERE
```

**3. Save as `kidsights_redcap_api.csv`**

**4. Update `.env`:**

```bash
# Windows
REDCAP_API_CREDENTIALS_PATH=C:/Users/YOUR_USERNAME/my-APIs/kidsights_redcap_api.csv

# Mac/Linux
REDCAP_API_CREDENTIALS_PATH=/home/YOUR_USERNAME/.kidsights/kidsights_redcap_api.csv
```

### FRED API Key (for NE25 + MN26 Income Transformations)

The NE25 and MN26 pipelines use the FRED (Federal Reserve Economic Data) API to fetch CPI series for inflation-adjusting household income to a constant-dollar reference year. Without it, the income transformation in `R/utils/cpi_utils.R` cannot complete.

**1. Register and get API key:**
- Register at https://fred.stlouisfed.org/
- Get an API key from https://fredaccount.stlouisfed.org/apikeys

**2. Save to file:**

```bash
# Windows
echo YOUR_FRED_KEY > C:\Users\YOUR_USERNAME\my-APIs\FRED.txt

# Mac/Linux
echo YOUR_FRED_KEY > ~/.kidsights/FRED.txt
```

**3. Update `.env`:**

```bash
# Windows
FRED_API_KEY_PATH=C:/Users/YOUR_USERNAME/my-APIs/FRED.txt

# Mac/Linux
FRED_API_KEY_PATH=/home/YOUR_USERNAME/.kidsights/FRED.txt
```

---

## Verification

### Test 1: Python Environment

```bash
# Check Python packages
python -c "import duckdb, pandas, yaml, structlog; print('All packages installed')"
```

### Test 2: Database Connection

```bash
# Test DuckDB connection
python -c "from python.db.connection import DatabaseManager; print(DatabaseManager().test_connection())"
```

Expected output:
```
Database connection test successful
True
```

### Test 3: IPUMS API Connection

```bash
# Test IPUMS API (ACS pipeline)
cd scripts/acs
python test_ipums_api_connection.py
```

Expected output:
```
[OK] IPUMS API key loaded successfully
[OK] IPUMS API client initialized
[OK] Connection successful!
```

### Test 4: REDCap API Connection

```bash
# Test REDCap API (NE25 pipeline)
cd scripts/redcap  # (if script exists)
python test_redcap_connection.py
```

### Test 5: Run NE25 Pipeline

```bash
# Full pipeline test (requires valid REDCap credentials)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

---

## Troubleshooting

### Issue: "'python' not found" Error

**Symptom:**
```
Error: '"python"' not found
Pipeline execution failed
```

**Solution:** Configure `PYTHON_EXECUTABLE` in `.env` file

```bash
# Add to .env file
PYTHON_EXECUTABLE=C:/Users/YOUR_USERNAME/AppData/Local/Programs/Python/Python313/python.exe

# Find your Python path
py -c "import sys; print(sys.executable)"
```

**Details:** See [PYTHON_EXECUTABLE Configuration](#python_executable-configuration) and [troubleshooting.md - Windows Python Path Issues](../troubleshooting.md#windows-python-path-issues)

### Issue: "API key file not found"

**Solution:** Check your `.env` file paths

```bash
# Verify .env file exists
ls -la .env

# Check environment variables are loaded
python -c "import os; from dotenv import load_dotenv; load_dotenv(); print(os.getenv('IPUMS_API_KEY_PATH'))"
```

### Issue: "Database file not found"

**Solution:** Ensure data directory exists

```bash
# Create missing directories
mkdir -p data/duckdb

# Verify database path
python -c "from python.db.config import get_database_path; print(get_database_path())"
```

### Issue: "Module not found" errors

**Solution:** Install missing Python packages

```bash
pip install --upgrade duckdb pandas pyyaml structlog ipumspy pyreadstat python-dotenv
```

### Issue: R packages not found

**Solution:** Install missing R packages

```r
# In R console
install.packages(c("dplyr", "tidyr", "stringr", "yaml", "REDCapR", "arrow", "duckdb", "reticulate"))
```

### Issue: "ImportError: Missing optional dependency 'pyarrow'" (R Imputation Pipeline)

**Symptom:** When running imputation pipeline from R, you see:
```
ImportError: Missing optional dependency 'pyarrow'. pyarrow is required for feather support.
```

**Root Cause:** The R reticulate package uses a separate Python environment that doesn't have pyarrow installed.

**Solution:** Install pyarrow in the R reticulate Python environment

**Option 1 - From R (Recommended):**
```r
# Install pyarrow in reticulate environment
reticulate::py_install("pyarrow")
```

**Option 2 - From Command Line:**
```bash
# Windows - Find your reticulate Python path
"C:/Users/YOUR_USERNAME/.virtualenvs/r-reticulate/Scripts/python.exe" -m pip install pyarrow

# Mac - Common location
~/.virtualenvs/r-reticulate/bin/python -m pip install pyarrow

# Linux - Common location
~/.virtualenvs/r-reticulate/bin/python -m pip install pyarrow
```

**To find your reticulate Python path:**
```r
# In R console
reticulate::py_config()
# Look for "python:" line - that's your reticulate Python executable
```

**Verification:**
```r
# Test that pyarrow is available
reticulate::py_module_available("pyarrow")  # Should return TRUE
```

### Issue: Permission denied on API key file

**Solution:** Check file permissions

```bash
# Mac/Linux - Fix permissions
chmod 600 ~/.kidsights/IPUMS.txt

# Windows - Check file properties
# Right-click → Properties → Security
```

### Issue: Paths with spaces

**Solution:** Use quotes in `.env` file

```bash
# Correct - quotes for paths with spaces
IPUMS_API_KEY_PATH="C:/Users/John Doe/my-APIs/IPUMS.txt"

# Also correct - forward slashes on Windows
IPUMS_API_KEY_PATH=C:/Users/JohnDoe/my-APIs/IPUMS.txt
```

---

## Cross-Platform Notes

### Windows

- Use **forward slashes** (`/`) or **escaped backslashes** (`\\`) in paths
- R.exe location: `C:/Program Files/R/R-4.5.1/bin/R.exe`
- Recommended API key location: `C:/Users/YOUR_USERNAME/my-APIs/`

### macOS

- Use **forward slashes** (`/`) in paths
- R location: `/usr/local/bin/R` or `/opt/homebrew/bin/R`
- Recommended API key location: `~/.kidsights/`

### Linux

- Use **forward slashes** (`/`) in paths
- R location: `/usr/bin/R` (or check with `which R`)
- Recommended API key location: `~/.kidsights/`

---

## Next Steps

After completing installation:

1. **Read the Quick Reference:** `docs/QUICK_REFERENCE.md`
2. **Explore Pipeline Documentation** (8 pipelines):
   - NE25: `docs/architecture/PIPELINE_OVERVIEW.md` and `CLAUDE.md`
   - MN26: `docs/mn26/pipeline_guide.qmd`
   - ACS: `docs/acs/README.md`
   - NHIS: `docs/nhis/README.md`
   - NSCH: `docs/nsch/README.md`
   - Raking Targets: `docs/raking/`
   - Imputation: `docs/imputation/`
   - IRT Calibration: `docs/irt_scoring/`
3. **Review Coding Standards:** `docs/guides/CODING_STANDARDS.md`
4. **Read CLAUDE.md** — the authoritative current-state reference for the platform

---

## Getting Help

**Documentation:**
- Quick Reference: `docs/QUICK_REFERENCE.md`
- Pipeline Overview: `docs/architecture/PIPELINE_OVERVIEW.md`
- Troubleshooting: `docs/troubleshooting.md`

**Support:**
- Create an issue in the GitHub repository
- Contact the Kidsights Data Platform team

---

**Installation complete! You're ready to run the pipelines.**

---

## Verification Summary

**Last fact-check:** 2026-04-20 (Bucket C Tier 3 of doc audit)

### Corrections applied
- Version: 3.2.0 → 3.8.0; date: October 2025 → April 2026
- **Added missing FRED API key setup section** (was in `.env.template` but not documented; required for NE25 + MN26 income transformations via `R/utils/cpi_utils.R`)
- "Next Steps" pipeline list expanded from 4 pipelines to all 8 (added MN26, Raking Targets, Imputation, IRT Calibration)
- Added pointer to CLAUDE.md as authoritative current-state reference

### Confirmed
- All R/Python version requirements match current platform (R 4.5.1+, Python 3.13+)
- `.env`-based config approach matches `.env.template` (verified)
- pyarrow installation guidance for reticulate is accurate
- `scripts/setup/verify_installation.py` exists ✓
- `scripts/acs/test_ipums_api_connection.py` exists ✓
- Path resolution priority logic matches `R/utils/environment_config.R`

### Known remaining drift (not surgically fixed)
- "Test 4: REDCap API Connection" references `scripts/redcap/test_redcap_connection.py` with "(if script exists)" hedge — the directory does not exist; consider removing or pointing to actual REDCap test
- N_CORES env variable (parallel processing) is in `.env.template` but not documented in this guide

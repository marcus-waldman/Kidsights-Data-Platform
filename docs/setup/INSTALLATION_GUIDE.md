# Kidsights Data Platform - Installation Guide

**Version:** 3.2.0 | **Last Updated:** October 2025

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
  "duckdb"
), dependencies = TRUE)
```

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
install.packages(c("dplyr", "tidyr", "stringr", "yaml", "REDCapR", "arrow", "duckdb"))
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
2. **Explore Pipeline Documentation:**
   - NE25: `docs/architecture/PIPELINE_OVERVIEW.md`
   - ACS: `docs/acs/README.md`
   - NHIS: `docs/nhis/README.md`
   - NSCH: `docs/nsch/README.md`
3. **Review Coding Standards:** `docs/guides/CODING_STANDARDS.md`

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

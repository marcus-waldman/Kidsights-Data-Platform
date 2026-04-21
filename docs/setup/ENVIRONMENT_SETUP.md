# Environment Configuration Guide

**Last Updated:** April 2026 (drift-checked 2026-04-20)

This guide explains how to configure the Kidsights Data Platform for cross-platform portability using environment variables.

---

## Overview

The platform uses a **`.env` file** for machine-specific configuration, ensuring the codebase works seamlessly across different computers and operating systems without hardcoding paths.

### Configuration Hierarchy

1. **`.env` file** (project root) - Machine-specific settings (highest priority)
2. **System environment variables** - Fallback if .env missing
3. **Cross-platform defaults** - Built-in fallbacks for common locations

---

## Quick Setup

### 1. Copy Template File

```bash
# From project root
cp .env.template .env
```

### 2. Edit `.env` File

**Windows:**
```bash
notepad .env
```

**Mac/Linux:**
```bash
nano .env
```

### 3. Update Required Paths

```bash
# ============================================================================
# API CREDENTIALS (REQUIRED)
# ============================================================================

IPUMS_API_KEY_PATH=C:/Users/YOUR_USERNAME/my-APIs/IPUMS.txt
REDCAP_API_CREDENTIALS_PATH=C:/Users/YOUR_USERNAME/my-APIs/kidsights_redcap_api.csv

# ============================================================================
# SOFTWARE PATHS (REQUIRED for bootstrap pipeline)
# ============================================================================

PYTHON_EXECUTABLE=C:/Users/YOUR_USERNAME/AppData/Local/Programs/Python/Python313/python.exe
```

**Important:** Replace `YOUR_USERNAME` with your actual username!

---

## Configuration Variables

### Required Variables

#### `IPUMS_API_KEY_PATH`
- **Purpose:** Location of IPUMS API key file
- **Used by:** ACS and NHIS pipelines
- **Format:** Plain text file with API key (one line, no whitespace)
- **Example:** `C:/Users/marcu/my-APIs/IPUMS.txt`
- **How to get:** https://account.ipums.org/api_keys

#### `REDCAP_API_CREDENTIALS_PATH`
- **Purpose:** Location of REDCap API credentials CSV
- **Used by:** NE25 and MN26 pipelines
- **Format:** CSV with columns: `project,pid,api_code`
- **Example:** `C:/Users/marcu/my-APIs/kidsights_redcap_api.csv`
- **How to get:** Contact REDCap administrator

#### `FRED_API_KEY_PATH`
- **Purpose:** Location of FRED (Federal Reserve Economic Data) API key file
- **Used by:** NE25 and MN26 income transformations (CPI inflation adjustment in `R/utils/cpi_utils.R`)
- **Format:** Plain text file with single API key (one line, no whitespace)
- **Example:** `C:/Users/marcu/my-APIs/FRED.txt`
- **How to get:** Register at https://fred.stlouisfed.org/, then https://fredaccount.stlouisfed.org/apikeys

#### `PYTHON_EXECUTABLE`
- **Purpose:** Path to Python executable
- **Used by:** R scripts that call Python (e.g., bootstrap pipeline)
- **Example (Windows):** `C:/Users/marcu/AppData/Local/Programs/Python/Python313/python.exe`
- **Example (Mac):** `/usr/local/bin/python3`
- **Example (Linux):** `/usr/bin/python3`

---

### Optional Variables

#### `R_EXECUTABLE`
- **Purpose:** Path to R executable
- **Used by:** Future Python scripts that may call R
- **Default:** Uses current R installation
- **Example (Windows):** `C:/Program Files/R/R-4.5.1/bin/R.exe`

#### `KIDSIGHTS_DB_PATH`
- **Purpose:** Override default DuckDB location
- **Default:** `data/duckdb/kidsights_local.duckdb`
- **Only use if:** You need database on different drive/location

#### Pipeline Data Directories
```bash
ACS_DATA_DIR=data/acs          # ACS cache location
NHIS_DATA_DIR=data/nhis        # NHIS cache location
NSCH_DATA_DIR=data/nsch        # NSCH cache location
```

#### `N_CORES`
- **Purpose:** Number of CPU cores for parallel processing
- **Used by:** Authenticity screening LOOCV, bootstrap pipelines, raking weights, other parallel tasks
- **Default:** Half of available CPU cores (auto-detected; safe default that leaves headroom)
- **Examples:** `N_CORES=8` (full utilization on 8-core machine) or `N_CORES=4` (light background processing)

---

## Path Format Requirements

### Windows

**✅ Correct (forward slashes):**
```bash
PYTHON_EXECUTABLE=C:/Users/marcu/AppData/Local/Programs/Python/Python313/python.exe
```

**✅ Correct (escaped backslashes):**
```bash
PYTHON_EXECUTABLE=C:\\Users\\marcu\\AppData\\Local\\Programs\\Python\\Python313\\python.exe
```

**❌ Incorrect (single backslashes):**
```bash
PYTHON_EXECUTABLE=C:\Users\marcu\AppData\Local\Programs\Python\Python313\python.exe
```

**❌ Incorrect (Git Bash format):**
```bash
PYTHON_EXECUTABLE=/c/Users/marcu/AppData/Local/Programs/Python/Python313/python.exe
```

### Mac/Linux

**✅ Correct:**
```bash
PYTHON_EXECUTABLE=/usr/local/bin/python3
IPUMS_API_KEY_PATH=/Users/username/.kidsights/IPUMS.txt
```

---

## Testing Your Configuration

### Test Python Path

**From R:**
```r
source("R/utils/environment_config.R")
test_python_config()
```

Expected output:
```
Testing Python configuration...
  Path: C:/Users/marcu/AppData/Local/Programs/Python/Python313/python.exe
  Version: Python 3.13.2
  [OK] Python is accessible
```

**From PowerShell:**
```powershell
# Test .env file reading
$pythonPath = (Get-Content .env | Where-Object {$_ -match "^PYTHON_EXECUTABLE="} | ForEach-Object {$_ -replace "^PYTHON_EXECUTABLE=", ""})
& $pythonPath --version
```

### Test API Keys

**IPUMS:**
```python
from python.acs.auth import get_api_key
api_key = get_api_key()
print(f"API key loaded: {api_key[:10]}..." if api_key else "ERROR: Key not found")
```

**REDCap:**
```python
from python.db.config import get_api_credentials_file
from pathlib import Path
creds_path = get_api_credentials_file()
print(f"REDCap credentials file: {creds_path}")
print(f"File exists: {Path(creds_path).exists()}")
```

> **Note:** Earlier versions of this doc referenced `python.utils.environment_config` with functions `get_ipums_api_key()` and `get_redcap_credentials()` — those modules/functions do not exist. The canonical APIs are `python.acs.auth.get_api_key` (and `python.nhis.auth.get_api_key`) for IPUMS keys, and `python.db.config.get_api_credentials_file` for REDCap.

---

## How It Works

### Python Scripts

Python scripts use `python-dotenv` to automatically load `.env`:

```python
from dotenv import load_dotenv
import os

load_dotenv()  # Loads .env file

# Read configuration
ipums_key_path = os.getenv("IPUMS_API_KEY_PATH")
python_path = os.getenv("PYTHON_EXECUTABLE")
```

### R Scripts

R scripts use custom utility functions from `R/utils/environment_config.R`:

```r
source("R/utils/environment_config.R")

# Get Python path with automatic fallbacks
python_path <- get_python_path()

# Use in system calls
system2(python_path, args = "script.py")
```

### PowerShell Scripts

PowerShell scripts read `.env` directly:

```powershell
function Get-EnvVariable {
    param([string]$VarName)

    $envFile = ".env"
    if (Test-Path $envFile) {
        $content = Get-Content $envFile
        foreach ($line in $content) {
            if ($line -match "^$VarName=(.+)$") {
                return $matches[1].Trim('"').Trim("'")
            }
        }
    }
    return $null
}

$pythonPath = Get-EnvVariable "PYTHON_EXECUTABLE"
```

---

## Common Scenarios

### Moving to a New Computer

1. Copy repository
2. Create new `.env` file from template
3. Update paths to match new system:
   - Change username in paths
   - Update Python installation path
   - Update API key locations
4. Test configuration
5. Ready to run pipelines!

### Switching Between Development Machines

Each machine maintains its own `.env` file (gitignored, never committed). When you `git pull`, your local `.env` stays unchanged.

### Team Collaboration

1. Team members each have their own `.env` file
2. `.env.template` in git shows required variables
3. No conflicts - each developer's paths stay private
4. Code runs without modification across all machines

---

## Fallback Behavior

If a variable is not found in `.env`, the platform tries:

### Python Path
1. `.env` file: `PYTHON_EXECUTABLE`
2. System environment variable: `PYTHON_EXECUTABLE`
3. Windows defaults:
   - `C:/Users/{USERNAME}/AppData/Local/Programs/Python/Python313/python.exe`
   - `C:/Program Files/Python313/python.exe`
   - System PATH: `python.exe`
4. Mac/Linux defaults:
   - System PATH: `python3`
   - System PATH: `python`

### API Keys
1. `.env` file paths
2. `~/.kidsights/IPUMS.txt`
3. `~/.kidsights/kidsights_redcap_api.csv`

---

## Security Best Practices

### ✅ Do:
- Keep `.env` file local (never commit)
- Use absolute paths to API keys
- Store API keys outside project directory
- Update `.env.template` when adding new variables
- Test configuration after setup

### ❌ Don't:
- Commit `.env` file to git
- Hardcode paths in scripts
- Store API keys in code
- Share `.env` file via email/Slack
- Use relative paths for API keys

---

## Troubleshooting

### Error: "PYTHON_EXECUTABLE not found in .env file"

**Solution:** Add to `.env`:
```bash
PYTHON_EXECUTABLE=C:/Path/To/Your/python.exe
```

Find your Python path:
```bash
# Windows PowerShell
where.exe python

# Mac/Linux
which python3
```

### Error: "Python executable not found"

**Cause:** Path in `.env` doesn't exist

**Solution:** Verify path and update:
```powershell
# Windows - Test if path exists
Test-Path "C:/Users/YOUR_USERNAME/AppData/Local/Programs/Python/Python313/python.exe"

# If False, find correct path
where.exe python
```

### Error: "IPUMS API key not found"

**Cause:** `IPUMS_API_KEY_PATH` incorrect or file missing

**Solution:**
1. Check path in `.env`
2. Verify file exists at that location
3. Ensure file contains only the API key (no extra whitespace)

### Configuration Not Loading

**Cause:** Wrong file name or location

**Solution:**
1. File must be named exactly `.env` (with leading dot)
2. Must be in project root directory
3. Check with: `ls -la | grep .env` (Mac/Linux) or `dir /a` (Windows)

---

## Related Documentation

- [Installation Guide](INSTALLATION_GUIDE.md) - Complete setup instructions
- [Quick Reference](../QUICK_REFERENCE.md) - Command cheatsheet
- [CLAUDE.md](../../CLAUDE.md) - Development guidelines

---

**For questions or issues with environment configuration, consult the main documentation or create an issue on GitHub.**

---

## Verification Summary

**Last fact-check:** 2026-04-20 (Bucket C Tier 3 of doc audit)

### Corrections applied
- Date: October 2025 → April 2026
- **Added FRED_API_KEY_PATH section** (was in `.env.template` but not documented here; required for NE25 + MN26 income transformations)
- **Added N_CORES section** (was in `.env.template` but not documented here)
- Updated REDCap usage to mention both NE25 and MN26 pipelines (MN26 was added April 2026)
- **Fixed fabricated API references**: `from python.utils.environment_config import get_ipums_api_key/get_redcap_credentials` corrected to actual module paths (`python.acs.auth.get_api_key` and `python.db.config.get_api_credentials_file`). The original module/functions never existed.

### Confirmed against source
- All env variables documented match those in `.env.template`
- `R/utils/environment_config.R` exists and matches the documented behavior
- `python-dotenv` is the correct library for `.env` loading
- Path resolution priority logic is accurate

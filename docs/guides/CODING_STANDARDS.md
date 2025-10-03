# Coding Standards

**Last Updated:** October 2025

This document defines coding standards for the Kidsights Data Platform. Following these standards ensures code reliability, cross-platform compatibility, and maintainability.

---

## Table of Contents

1. [R Coding Standards](#r-coding-standards)
2. [Python Coding Standards](#python-coding-standards)
3. [File Naming Conventions](#file-naming-conventions)
4. [R Execution Guidelines](#r-execution-guidelines)
5. [Code Organization](#code-organization)

---

## R Coding Standards

### Explicit Package Namespacing (CRITICAL)

**Rule:** All R function calls MUST use explicit package namespacing (e.g., `dplyr::select()`, `tidyr::pivot_longer()`).

**Why?**
- **Prevents namespace conflicts:** Multiple packages export functions with same names (e.g., `select()` exists in dplyr, MASS, and others)
- **Improves readability:** Clear which package each function comes from
- **Enables debugging:** Easier to trace function source when issues arise
- **Explicit dependencies:** Makes package requirements obvious

### Correct Pattern

```r
# ✅ CORRECT - Explicit namespacing
library(dplyr)
library(tidyr)
library(arrow)

data %>%
  dplyr::select(pid, record_id) %>%
  dplyr::mutate(new_var = old_var * 2) %>%
  dplyr::filter(new_var > 0) %>%
  arrow::write_feather("output.feather")
```

### Incorrect Pattern

```r
# ❌ INCORRECT - Implicit function calls (causes namespace conflicts)
library(dplyr)

data %>%
  select(pid, record_id) %>%      # Which select()? dplyr? MASS?
  mutate(new_var = old_var * 2) %>%
  filter(new_var > 0)
```

**What can go wrong:**
```r
# If MASS is loaded after dplyr, select() is silently masked
library(dplyr)
library(MASS)  # Now MASS::select() masks dplyr::select()

data %>% select(pid)  # Uses MASS::select() - WRONG!
# Error: 'pid' is not a function, character or symbol
```

### Required Package Prefixes

| Package | Common Functions | Always Use Prefix |
|---------|-----------------|-------------------|
| `dplyr::` | select(), filter(), mutate(), summarise(), group_by(), left_join(), arrange(), rename() | ✅ Required |
| `tidyr::` | pivot_longer(), pivot_wider(), separate(), unite(), nest(), unnest() | ✅ Required |
| `stringr::` | str_split(), str_extract(), str_detect(), str_replace(), str_trim() | ✅ Required |
| `arrow::` | read_feather(), write_feather() | ✅ Required |
| `purrr::` | map(), map_df(), walk(), reduce() | ✅ Required |
| `readr::` | read_csv(), write_csv(), read_rds(), write_rds() | ✅ Required |
| `ggplot2::` | ggplot(), aes(), geom_*() | ✅ Required |
| `labelled::` | var_label(), val_labels() | ✅ Required |

### Exceptions

**Base R functions:** Do not need prefixes (they're always available)
```r
# ✅ OK - Base R functions
data <- data.frame(x = 1:10, y = 11:20)
result <- mean(data$x)
combined <- c(1, 2, 3)
subset_data <- subset(data, x > 5)
```

**Package-specific contexts:** When inside a package-specific function chain
```r
# ✅ OK - ggplot2 context is clear
ggplot2::ggplot(data, ggplot2::aes(x = age, y = score)) +
  geom_point() +  # OK, clearly ggplot2
  geom_smooth()   # OK, clearly ggplot2
```

### Enforcement

All R code is checked for namespace compliance during code review. Scripts violating this standard will not be merged.

---

## Python Coding Standards

### Windows Console Output (CRITICAL)

**Rule:** All Python print() statements MUST use ASCII characters only (no Unicode symbols).

**Why?**
- **Windows compatibility:** Windows console uses cp1252 encoding (not UTF-8)
- **Prevents UnicodeEncodeError:** Unicode symbols crash the pipeline on Windows
- **Cross-platform consistency:** ASCII works everywhere

### Correct Pattern

```python
# ✅ CORRECT - ASCII output (Windows-compatible)
print("[OK] Data loaded successfully")
print("[ERROR] Failed to connect to database")
print("[WARN] Missing variables detected: age, sex")
print("[INFO] Processing 3,906 records...")
print("[DEBUG] Variable count: 245")
```

### Incorrect Pattern

```python
# ❌ INCORRECT - Unicode symbols (causes UnicodeEncodeError on Windows)
print("✓ Data loaded successfully")        # U+2713 CHECK MARK
print("✗ Failed to connect")               # U+2717 BALLOT X
print("⚠ Missing variables")               # U+26A0 WARNING SIGN
print("ℹ Processing records...")           # U+2139 INFORMATION SOURCE
print("🔍 Searching database...")          # U+1F50D RIGHT-POINTING MAGNIFYING GLASS
```

**What can go wrong:**
```python
print("✓ Success")
# UnicodeEncodeError: 'charmap' codec can't encode character '\u2713'
# in position 0: character maps to <undefined>
```

### Standard ASCII Replacements

| Unicode Symbol | ASCII Replacement | Use Case |
|---------------|-------------------|----------|
| ✓ (U+2713) | `[OK]` | Success messages |
| ✗ (U+2717) | `[ERROR]` or `[FAIL]` | Error messages |
| ⚠ (U+26A0) | `[WARN]` | Warning messages |
| ℹ (U+2139) | `[INFO]` | Informational messages |
| 🔍 (U+1F50D) | `[SEARCH]` | Search operations |
| 📊 (U+1F4CA) | `[STATS]` | Statistics display |
| ⏱ (U+23F1) | `[TIME]` | Timing information |
| ▶ (U+25B6) | `[START]` | Process start |
| ■ (U+25A0) | `[STOP]` | Process stop |

### Structured Logging Pattern

For production code, use structured logging instead of print():

```python
import structlog

logger = structlog.get_logger()

# ✅ BEST PRACTICE - Structured logging
logger.info("data_loaded", records=3906, tables=11)
logger.error("database_connection_failed", host="localhost", port=5432)
logger.warning("missing_variables", variables=["age", "sex"], count=2)
```

### Enforcement

- All Python modules use ASCII-only output
- Unicode in user-facing strings (e.g., data values) is acceptable
- Unicode in print() statements for debugging/logging is forbidden

---

## File Naming Conventions

### R Files: `snake_case.R`

**Pattern:** Lowercase with underscores, `.R` extension

```
✅ CORRECT
R/extract/ne25_extract.R
R/transform/ne25_transforms.R
R/utils/query_geo_crosswalk.R
R/codebook/load_codebook.R

❌ INCORRECT
R/extract/NE25Extract.R          # PascalCase
R/transform/ne25-transforms.R    # kebab-case
R/utils/queryGeoCrosswalk.R      # camelCase
```

**Rationale:**
- R community convention (tidyverse style guide)
- Consistent with function naming (`load_codebook()`)
- Easy to read and type

### Python Files: `snake_case.py`

**Pattern:** Lowercase with underscores, `.py` extension

```
✅ CORRECT
python/db/connection.py
python/acs/extract_manager.py
pipelines/python/acs/extract_acs_data.py

❌ INCORRECT
python/db/Connection.py          # PascalCase
python/acs/extract-manager.py    # kebab-case
pipelines/python/acs/extractACSData.py  # camelCase
```

**Rationale:**
- PEP 8 convention
- Matches module import syntax (`from python.db.connection import DatabaseManager`)

### Configuration Files: `kebab-case.yaml`

**Pattern:** Lowercase with hyphens, `.yaml` extension

```
✅ CORRECT
config/sources/acs/nebraska-2019-2023.yaml
config/sources/nhis/nhis-2019-2024.yaml
config/duckdb.yaml

❌ INCORRECT
config/sources/acs/nebraska_2019_2023.yaml  # snake_case
config/sources/acs/Nebraska-2019-2023.yaml  # PascalCase
```

**Rationale:**
- Standard for configuration files (Docker, Kubernetes, etc.)
- Improves readability for non-code files
- Distinguishes config from code

### Documentation: `UPPER_CASE.md` or `Title_Case.md`

**Pattern:** Uppercase for key docs, Title Case for guides

```
✅ CORRECT (Key Documentation)
CLAUDE.md
README.md
CHANGELOG.md
docs/QUICK_REFERENCE.md
docs/DIRECTORY_STRUCTURE.md

✅ CORRECT (Guides)
docs/guides/migration-guide.md
docs/acs/pipeline_usage.md
docs/nhis/testing_guide.md

❌ INCORRECT
claude.md                        # Too generic
Readme.md                        # Inconsistent casing
docs/quick-reference.md          # Should be UPPER_CASE for key docs
```

**Rationale:**
- UPPER_CASE makes critical docs highly visible
- Title_Case with kebab-case for longer guide names
- Follows GitHub/open-source conventions

### Special Cases

**Executable Scripts:** Same as code files (snake_case)
```
scripts/acs/test_api_connection.py
scripts/nsch/process_all_years.py
```

**Data Files:** Use descriptive names with underscores
```
data/acs/nebraska/2019-2023/raw.feather
data/nsch/2023/metadata.json
```

**Temp Files:** Prefix with `temp_` and use snake_case
```
scripts/temp/temp_script.R
scripts/temp/temp_validation.py
```

---

## R Execution Guidelines

### Critical Rule: Never Use Inline `-e` Commands

⚠️ **Never use inline `-e` commands - they cause segmentation faults**

### Correct Pattern: Use Temp Script Files

```bash
# ✅ CORRECT - Write code to temp file, then execute
echo 'library(dplyr); cat("Success\n")' > scripts/temp/temp_script.R
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/temp/temp_script.R
```

**Step-by-step:**
1. Write R code to a `.R` file in `scripts/temp/`
2. Execute with `-f` flag (not `-e`)
3. Clean up temp file after execution (optional)

### Incorrect Pattern: Inline Commands

```bash
# ❌ INCORRECT - Causes segmentation faults
"C:\Program Files\R\R-4.5.1\bin\R.exe" -e "library(dplyr)"
"C:\Program Files\R\R-4.5.1\bin\R.exe" -e "cat('Hello\n')"
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" -e "source('script.R')"
```

**Why this fails:**
- The R DuckDB driver has stability issues with `-e` inline execution
- Causes segmentation faults (50% failure rate before hybrid architecture)
- No error context - just crashes

### Recommended R Execution Flags

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" \
  --arch x64              # Use 64-bit R (required for large datasets)
  --slave                 # Suppress startup messages
  --no-save               # Don't save workspace on exit
  --no-restore            # Don't restore .RData on startup
  --no-environ            # Don't read .Renviron
  -f script.R             # Execute script file
```

**For Rscript:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" \
  --no-save --no-restore \
  script.R
```

### Python Wrapper for R Execution

For programmatic R execution from Python, use `python/utils/r_executor.py`:

```python
from python.utils.r_executor import execute_r_script

code = '''
library(dplyr)
library(arrow)
data <- arrow::read_feather("input.feather")
result <- dplyr::filter(data, age > 5)
arrow::write_feather(result, "output.feather")
cat("Processed", nrow(result), "records\\n")
'''

output, return_code = execute_r_script(code)
if return_code == 0:
    print(f"[OK] R script succeeded: {output}")
else:
    print(f"[ERROR] R script failed: {output}")
```

**What it does:**
- Writes code to `scripts/temp/r_exec_{timestamp}.R`
- Executes with proper flags
- Captures output and return code
- Cleans up temp file

---

## Code Organization

### Directory Structure for New Modules

**R Modules:**
```
R/
├── extract/          # Data extraction from APIs
├── transform/        # Data transformations
├── harmonize/        # Cross-study harmonization
├── utils/            # Utility functions
│   ├── acs/          # ACS-specific utilities
│   ├── nhis/         # NHIS-specific utilities
│   └── nsch/         # NSCH-specific utilities
└── codebook/         # Codebook queries
```

**Python Modules:**
```
python/
├── db/               # Database operations
├── acs/              # ACS pipeline modules
├── nhis/             # NHIS pipeline modules
├── nsch/             # NSCH pipeline modules
└── utils/            # Shared utilities
```

### Module Size Guidelines

- **Keep modules focused:** One primary responsibility per file
- **Max lines:** Aim for <500 lines per module
- **Split when needed:** If module exceeds 500 lines, consider splitting

### Import Standards

**R:**
```r
# Load libraries at top of file
library(dplyr)
library(tidyr)
library(arrow)

# Source utilities if needed
source("R/utils/helper_functions.R")

# Then use explicit namespacing in all function calls
```

**Python:**
```python
# Standard library first
import os
import sys
from pathlib import Path

# Third-party imports
import pandas as pd
import duckdb

# Local imports
from python.db.connection import DatabaseManager
from python.utils.validators import validate_data
```

---

## Related Documentation

- **Missing Data Guide:** [MISSING_DATA_GUIDE.md](MISSING_DATA_GUIDE.md) - Standards for handling missing values
- **Python Utilities:** [PYTHON_UTILITIES.md](PYTHON_UTILITIES.md) - Python helper functions and utilities
- **Pipeline Steps:** [../architecture/PIPELINE_STEPS.md](../architecture/PIPELINE_STEPS.md) - Execution patterns
- **Quick Reference:** [../QUICK_REFERENCE.md](../QUICK_REFERENCE.md) - Command cheatsheet

---

*Last Updated: October 2025*

# Example Scripts

This folder contains ready-to-use example scripts for common data operations with the Kidsights Data Platform.

---

## Available Scripts

### `export_ne25_to_stata_spss.R`

**Purpose:** Export NE25 data from DuckDB to analysis-ready formats with full metadata.

**What it does:**
- Connects to `data/duckdb/kidsights_local.duckdb`
- Exports data dictionary (CSV) with complete variable documentation
- Exports NE25 tables to SPSS (.sav) and R native (.rds) formats
- Applies full variable labels and value labels from REDCap data dictionary
- Handles SPSS variable name length restrictions automatically (64 char limit)

**Usage:**
```r
# Run from R console or RStudio
source("example-scripts/export_ne25_to_stata_spss.R")
```

**Output files (5 total):**
1. `ne25_data_dictionary.csv` - Complete variable documentation (471 variables)
2. `ne25_raw.sav` - Raw REDCap data in SPSS format (4,962 records, 6 variables)
3. `ne25_raw.rds` - Raw REDCap data in R native format
4. `ne25_transformed.sav` - Derived variables in SPSS format (4,962 records, 641 variables)
5. `ne25_transformed.rds` - Derived variables in R native format

**Features:**
- **GUI directory picker** - Select export location via dialog window
- **Auto-installation** - Automatically installs required R packages if missing
- **Full labels** - Variable labels and value labels embedded in files
- **Cross-platform** - Works on Windows, macOS, and Linux
- **Error handling** - Graceful handling of type mismatches and format restrictions

**Requirements:**
- R 4.5.1+
- Packages: duckdb, DBI, haven, labelled, dplyr (auto-installed)
- Kidsights database must exist at `data/duckdb/kidsights_local.duckdb`

**Execution time:** ~10 seconds

---

## Adding New Example Scripts

When adding new example scripts to this folder:

1. **File naming:** Use descriptive snake_case names (e.g., `export_acs_to_csv.R`)
2. **Documentation header:** Include comprehensive roxygen-style documentation at the top
3. **Auto-installation:** Include automatic package installation for user convenience
4. **Error handling:** Use `tryCatch()` blocks for robust error handling
5. **User feedback:** Provide clear console output with `[INFO]`, `[OK]`, `[ERROR]` prefixes
6. **Update this README:** Document the new script's purpose, usage, and outputs

---

## Related Documentation

- **Data Dictionary System:** [docs/codebook/README.md](../docs/codebook/README.md)
- **Database Architecture:** [docs/architecture/PIPELINE_OVERVIEW.md](../docs/architecture/PIPELINE_OVERVIEW.md)
- **Quick Reference:** [docs/QUICK_REFERENCE.md](../docs/QUICK_REFERENCE.md)

---

**Last Updated:** October 2025

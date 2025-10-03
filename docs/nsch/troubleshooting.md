# NSCH Pipeline Troubleshooting Guide

Common issues and solutions for the NSCH data integration pipeline.

**Last Updated:** October 2025

---

## Table of Contents

1. [SPSS Loading Issues](#spss-loading-issues)
2. [R Validation Failures](#r-validation-failures)
3. [Database Issues](#database-issues)
4. [Python Environment Issues](#python-environment-issues)
5. [Performance Problems](#performance-problems)
6. [Data Quality Issues](#data-quality-issues)
7. [Batch Processing Errors](#batch-processing-errors)

---

## SPSS Loading Issues

### Error: "SPSS file not found"

**Symptom:**
```
FileNotFoundError: SPSS file not found: data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav
```

**Causes:**
1. SPSS file not downloaded
2. File in wrong directory
3. Incorrect filename

**Solutions:**

1. **Verify file exists:**
```bash
ls data/nsch/spss/
```

2. **Check filename exactly matches:**
- Filenames are case-sensitive
- Check for extra spaces
- Ensure `.sav` extension

3. **Download missing files:**
- Visit: https://www.census.gov/programs-surveys/nsch/data/datasets.html
- Select "Topical" dataset
- Choose "SPSS" format
- Download to `data/nsch/spss/`

### Error: "pyreadstat module not found"

**Symptom:**
```
ModuleNotFoundError: No module named 'pyreadstat'
```

**Solution:**
```bash
pip install pyreadstat
```

### Error: "Invalid SPSS file format"

**Symptom:**
```
ReadStatError: Unable to read SPSS file
```

**Causes:**
1. Corrupted download
2. Wrong file format
3. Zipped file not extracted

**Solutions:**

1. **Verify file is unzipped:**
```bash
# SPSS files should end in .sav, not .zip
file data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav
```

2. **Re-download if corrupted:**
- Check file size matches expected size
- Compare MD5/SHA checksums if available

3. **Ensure SPSS format (not CSV or SAS):**
- Download "SPSS" version, not "CSV" or "SAS"

### Error: "Out of memory during SPSS load"

**Symptom:**
```
MemoryError: Unable to allocate array
```

**Solutions:**

1. **Close other applications**

2. **Process one year at a time:**
```bash
# Instead of batch processing
python pipelines/python/nsch/load_nsch_spss.py --year 2023
```

3. **Increase system RAM (if possible)**

---

## R Validation Failures

### Error: "R script not found"

**Symptom:**
```
Error: Cannot find R script: pipelines/orchestration/run_nsch_pipeline.R
```

**Solution:**

Ensure you're running from project root directory:
```bash
# Check current directory
pwd

# Should be: /path/to/Kidsights-Data-Platform
# If not, cd to project root
```

### Error: "Package 'haven' not found"

**Symptom:**
```
Error in library(haven) : there is no package called 'haven'
```

**Solution:**
```r
install.packages(c("haven", "arrow", "dplyr", "tidyr", "stringr", "cli", "glue"))
```

### Error: "Feather file not found"

**Symptom:**
```
Error: Feather file not found: data/nsch/2023/raw.feather
```

**Solution:**

Run SPSS conversion first:
```bash
python pipelines/python/nsch/load_nsch_spss.py --year 2023
```

### Validation Check Failures

**Symptom:**
```
VALIDATION FAILED: 5/7 checks successful
[FAIL] hhid_missing: 10 records with missing HHID
```

**Solutions:**

1. **Review validation report:**
```bash
cat data/nsch/2023/validation_report.txt
```

2. **Check source SPSS file integrity:**
- Re-download if validation repeatedly fails
- Compare with official documentation

3. **Proceed with caution:**
- Some validation failures may be expected (e.g., 2016 schema differences)
- Document any persistent issues

---

## Database Issues

### Error: "Database locked"

**Symptom:**
```
duckdb.IOException: Could not set lock on file
```

**Causes:**
1. Another process has database open
2. Previous connection not closed

**Solutions:**

1. **Close existing connections:**

**Python:**
```python
conn.close()
```

**R:**
```r
dbDisconnect(conn, shutdown = TRUE)
```

2. **Check for open processes:**
```bash
# Windows
tasklist | findstr python
tasklist | findstr R

# Kill if necessary
taskkill /PID <pid> /F
```

3. **Restart if persistent:**
- Close all Python/R sessions
- Restart terminal

### Error: "Table does not exist"

**Symptom:**
```
Catalog Error: Table with name nsch_2023_raw does not exist
```

**Solutions:**

1. **Check table exists:**
```python
import duckdb
conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')
tables = conn.execute("SHOW TABLES").fetchall()
print(tables)
conn.close()
```

2. **Run data insertion:**
```bash
python pipelines/python/nsch/insert_nsch_database.py --year 2023
```

### Error: "Conversion error during insertion"

**Symptom:**
```
Conversion Error: Could not convert string 'T1' to INT32
```

**Known Issue:** 2016 data has schema incompatibility

**Solutions:**

1. **For 2016:** This is a known limitation
   - Table will be empty
   - Will be addressed in harmonization phase
   - Safe to skip 2016 for now

2. **For other years:** Report as bug
   - Check SPSS file is correct version
   - Verify Feather conversion succeeded

### Error: "Database file corrupted"

**Symptom:**
```
IOException: Failure during initialization of Database
```

**Solutions:**

1. **Delete and recreate database:**
```bash
# Backup existing database first!
cp data/duckdb/kidsights_local.duckdb data/duckdb/kidsights_local.duckdb.backup

# Delete corrupted database
rm data/duckdb/kidsights_local.duckdb

# Re-run pipeline
python scripts/nsch/process_all_years.py --years all
```

2. **Restore from backup if needed:**
```bash
cp data/duckdb/kidsights_local.duckdb.backup data/duckdb/kidsights_local.duckdb
```

---

## Python Environment Issues

### Error: "Module not found"

**Symptom:**
```
ModuleNotFoundError: No module named 'duckdb'
```

**Solutions:**

1. **Install required packages:**
```bash
pip install pandas pyreadstat structlog duckdb
```

2. **Verify installation:**
```bash
python -c "import pandas, pyreadstat, duckdb, structlog; print('All installed')"
```

3. **Check Python version:**
```bash
python --version  # Should be 3.13+
```

### Error: "Wrong Python interpreter"

**Symptom:**
```
ModuleNotFoundError: No module named 'pandas'
```
(Even though pandas is installed)

**Cause:** Multiple Python installations

**Solutions:**

1. **Check which Python:**
```bash
which python
python --version
```

2. **Use explicit Python path:**
```bash
# Use specific Python interpreter
/path/to/python3.13 pipelines/python/nsch/load_nsch_spss.py --year 2023
```

3. **Create virtual environment:**
```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install pandas pyreadstat structlog duckdb
```

### Error: "Permission denied"

**Symptom:**
```
PermissionError: [Errno 13] Permission denied: 'data/nsch/2023/raw.feather'
```

**Solutions:**

1. **Check file permissions:**
```bash
ls -l data/nsch/2023/
```

2. **Run with appropriate permissions**

3. **Close files if open in other programs**

---

## Performance Problems

### Slow SPSS Loading

**Symptom:** SPSS conversion takes >5 minutes per year

**Solutions:**

1. **Normal for first run:**
- SPSS files are large (100+ MB)
- 2-5 minutes is normal

2. **Check disk space:**
```bash
df -h  # Linux/Mac
wmic logicaldisk get size,freespace,caption  # Windows
```

3. **Use SSD if available:**
- Move data directory to SSD
- Much faster I/O

### Slow Queries

**Symptom:** Queries take >10 seconds

**Solutions:**

1. **Use LIMIT for exploration:**
```sql
SELECT * FROM nsch_2023_raw LIMIT 100;
```

2. **Select only needed columns:**
```sql
-- Good
SELECT HHID, SC_AGE_YEARS FROM nsch_2023_raw;

-- Bad
SELECT * FROM nsch_2023_raw;
```

3. **Filter early:**
```sql
-- Filter before aggregating
SELECT AVG(SC_AGE_YEARS)
FROM nsch_2023_raw
WHERE FIPSST = 31;
```

### High Memory Usage

**Symptom:** Python/R using >4 GB RAM

**Solutions:**

1. **Close database connections when done:**
```python
conn.close()
```

2. **Process one year at a time**

3. **Use streaming for large exports:**
```python
# Export in chunks
for chunk in pd.read_sql(..., chunksize=10000):
    chunk.to_csv('output.csv', mode='a')
```

---

## Data Quality Issues

### Unexpected Missing Values

**Symptom:** Many NULL or 99 values

**Cause:** Normal NSCH missing data codes

**Understanding Missing Codes:**
- `NULL` - No value recorded
- `90` - Not in universe (skip pattern)
- `95` - Logical skip
- `96` - Suppressed for confidentiality
- `99` - No valid response / Prefer not to answer

**Solutions:**

1. **Always exclude missing codes in analysis:**
```sql
WHERE variable NOT IN (90, 95, 96, 99)
  AND variable IS NOT NULL
```

2. **Check value labels:**
```sql
SELECT value, label
FROM nsch_value_labels
WHERE variable_name = 'YOUR_VARIABLE'
  AND year = 2023;
```

3. **Use appropriate statistical methods:**
- Multiple imputation
- Complete case analysis
- Listwise deletion

### Variables Not in Expected Year

**Symptom:** Variable exists in 2022 but not 2023

**Cause:** Survey questions change across years

**Solutions:**

1. **Check variable availability:**
```sql
SELECT year, COUNT(*) AS occurrences
FROM nsch_variables
WHERE variable_name = 'YOUR_VARIABLE'
GROUP BY year
ORDER BY year;
```

2. **Use crosswalk table (future):**
- Will map variable renames across years

3. **Review NSCH documentation:**
- Check questionnaire changes
- Look for replacement variables

### Inconsistent Value Labels

**Symptom:** Same variable has different response options across years

**Cause:** Survey revisions

**Solutions:**

1. **Check value labels by year:**
```sql
SELECT year, value, label
FROM nsch_value_labels
WHERE variable_name = 'YOUR_VARIABLE'
ORDER BY year, value;
```

2. **Harmonize manually if needed:**
```sql
-- Example: Recode to consistent categories
CASE
    WHEN year <= 2019 AND value IN (1, 2) THEN 'Category A'
    WHEN year >= 2020 AND value = 1 THEN 'Category A'
    ...
END
```

3. **Document harmonization decisions**

---

## Batch Processing Errors

### Error: "All years failed"

**Symptom:**
```
BATCH PROCESSING SUMMARY
Successful: 0
Failed: 8
```

**Solutions:**

1. **Check individual error messages:**
```bash
# Review log output
cat nsch_batch_output.log
```

2. **Test single year first:**
```bash
python scripts/nsch/process_all_years.py --years 2023
```

3. **Verify prerequisites:**
- Python packages installed
- R packages installed
- SPSS files present

### Error: "Processed.feather not found" during batch

**Symptom:**
```
FileNotFoundError: data/nsch/2023/processed.feather
```

**Cause:** R validation was skipped

**Solution:**

**Don't skip validation:**
```bash
# Remove --skip-validation flag
python scripts/nsch/process_all_years.py --years all
```

R validation creates the `processed.feather` file needed for database insertion.

### Partial Batch Failure

**Symptom:**
```
Successful: 5
Failed: 3
```

**Solutions:**

1. **Review which years failed:**
```
PER-YEAR RESULTS:
  [PASS] 2017: 15.9s
  [PASS] 2018: 16.8s
  [FAIL] 2019: 0.0s - Failed steps: data_insertion
```

2. **Reprocess failed years individually:**
```bash
python scripts/nsch/process_all_years.py --years 2019
```

3. **Check year-specific issues:**
- SPSS file integrity
- Schema differences
- Disk space

---

## Getting Help

### Before Reporting Issues

1. **Check existing documentation:**
- [README.md](README.md)
- [pipeline_usage.md](pipeline_usage.md)
- [database_schema.md](database_schema.md)

2. **Verify basic setup:**
```bash
# Python packages
python -c "import pandas, pyreadstat, duckdb, structlog"

# R packages
Rscript -e "library(haven); library(arrow); library(dplyr)"

# SPSS files
ls data/nsch/spss/
```

3. **Review logs:**
- Python error messages
- R console output
- Batch processing logs

### Diagnostic Information to Collect

When reporting issues, include:

1. **System information:**
```bash
python --version
Rscript --version
uname -a  # or Windows version
```

2. **Error message (full text)**

3. **Command that failed:**
```bash
python pipelines/python/nsch/load_nsch_spss.py --year 2023
```

4. **File existence:**
```bash
ls -lh data/nsch/2023/
```

5. **Database status:**
```python
import duckdb
conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')
print(conn.execute("SHOW TABLES").fetchall())
conn.close()
```

---

## Common Warnings (Not Errors)

### "2016 table empty"

**Message:**
```
[EMPTY] nsch_2016_raw: 0 records
```

**Status:** Known limitation, not an error

**Explanation:** 2016 has schema differences that will be addressed in harmonization phase

### "Validation check failed: column_count"

**Message:**
```
[WARNING] Column count mismatch: expected 895, got 896
```

**Cause:** Minor metadata differences

**Action:** Usually safe to proceed, but verify data integrity

### "Database size estimate unavailable"

**Message:**
```
[WARNING] Could not estimate table size
```

**Cause:** DuckDB internal limitation

**Action:** No impact on functionality, size will be estimated differently

---

## Performance Optimization Tips

### 1. Use Batch Processing

```bash
# Faster than individual years
python scripts/nsch/process_all_years.py --years 2020-2023
```

### 2. Query Optimization

```sql
-- Always use LIMIT for exploration
SELECT * FROM nsch_2023_raw LIMIT 100;

-- Select only needed columns
SELECT HHID, SC_AGE_YEARS FROM nsch_2023_raw;

-- Filter before aggregating
WHERE conditions... LIMIT 1000
```

### 3. Storage Optimization

```bash
# Feather files are temporary - can delete after database load
rm data/nsch/*/raw.feather
rm data/nsch/*/processed.feather

# Keep metadata.json for documentation
```

### 4. Connection Management

```python
# Always close connections
conn.close()

# Use context managers
with duckdb.connect('path/to/db') as conn:
    result = conn.execute("SELECT ...").fetchdf()
# Auto-closes
```

---

## Additional Resources

- **Pipeline Usage:** [pipeline_usage.md](pipeline_usage.md)
- **Database Schema:** [database_schema.md](database_schema.md)
- **Example Queries:** [example_queries.md](example_queries.md)
- **Implementation Plan:** [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)

---

**Last Updated:** October 3, 2025

**For additional support, see main project [CLAUDE.md](../../CLAUDE.md)**

# Imputation Stage Validation Checks

**Purpose:** Pattern compliance checks for imputation stage implementations

**Last Updated:** October 8, 2025 | **Version:** 1.0.0

---

## Overview

This document defines the 8 critical pattern checks that the `imputation-stage-builder` agent uses in validation mode to verify existing implementations comply with standardized patterns.

## Validation Procedure

When user requests validation of an existing stage:

1. **Identify files** - Ask for stage number or file paths
2. **Read scripts** - Load both R and Python implementations
3. **Run checks** - Execute all 8 critical pattern checks
4. **Generate report** - Create findings summary with line numbers
5. **Offer fixes** - Provide corrected code for any failures

---

## Critical Pattern Checks

### Check 1: Seed Usage Pattern ⚠️ CRITICAL

**Purpose:** Prevent identical imputations across M runs

**Pattern:** `set.seed(seed + m)` inside imputation loop

**Location:** R script, inside `for (m in 1:M)` loop

**How to Check:**
```
1. Search R script for "set.seed("
2. Verify it's inside the for loop
3. Check expression is "seed + m" not just "seed"
```

**Expected:**
```r
for (m in 1:M) {
  set.seed(seed + m)  # CRITICAL: seed + m, not just seed
  mice_result <- mice::mice(...)
}
```

**Common Error:**
```r
for (m in 1:M) {
  set.seed(seed)  # ❌ WRONG: All imputations will be identical!
  mice_result <- mice::mice(...)
}
```

**Severity:** CRITICAL - Causes all M imputations to be identical

---

### Check 2: Defensive Filtering ⚠️ CRITICAL

**Purpose:** Prevent data contamination from ineligible/inauthentic records

**Pattern:** All DuckDB queries include `WHERE "eligible.x" = TRUE AND "authentic.x" = TRUE`

**Location:** R script, in all `DBI::dbGetQuery()` calls

**How to Check:**
```
1. Search R script for "DBI::dbGetQuery" or "dbGetQuery"
2. For each occurrence, check WHERE clause
3. Verify includes both eligible.x AND authentic.x filters
```

**Expected:**
```r
query <- "
  SELECT pid, record_id, variable1, variable2
  FROM ne25_transformed
  WHERE \"eligible.x\" = TRUE AND \"authentic.x\" = TRUE
"
base_data <- DBI::dbGetQuery(con, query)
```

**Common Error:**
```r
query <- "
  SELECT pid, record_id, variable1, variable2
  FROM ne25_transformed
"  # ❌ WRONG: Missing defensive filters!
base_data <- DBI::dbGetQuery(con, query)
```

**Severity:** CRITICAL - Contaminates imputation with invalid records

---

### Check 3: Storage Convention ✓ IMPORTANT

**Purpose:** Space-efficient storage, only save imputed values

**Pattern:** Only save records where `is.na(original_data[[variable]])`

**Location:** R script, in `save_*_feather()` function

**How to Check:**
```
1. Find save function (e.g., save_adult_anxiety_feather)
2. Check for "originally_missing" variable
3. Verify saves only originally_missing records
```

**Expected:**
```r
save_feather <- function(completed_data, original_data, m, output_dir, variable_name) {
  # Save ONLY originally-missing records
  originally_missing <- is.na(original_data[[variable_name]])
  imputed_records <- completed_data[originally_missing, ]

  # Defensive filtering: Remove records where imputation failed
  successfully_imputed <- !is.na(imputed_records[[variable_name]])
  imputed_records <- imputed_records[successfully_imputed, ]

  arrow::write_feather(imputed_records, output_path)
}
```

**Common Error:**
```r
# ❌ WRONG: Saves all records, including observed values
arrow::write_feather(completed_data, output_path)
```

**Severity:** IMPORTANT - Wastes storage, may overwrite observed values

---

### Check 4: Metadata Tracking ✓ IMPORTANT

**Purpose:** Enable auditing and verification of imputation process

**Pattern:** Call `update_metadata()` for each variable in Python script

**Location:** Python script, in `main()` function

**How to Check:**
```
1. Search Python script for "update_metadata("
2. Count occurrences
3. Verify count matches number of variables
4. Check includes all required parameters
```

**Expected:**
```python
def main():
    # Create tables
    create_adult_anxiety_tables(db, study_id)

    # Insert imputations
    for variable in variables:
        insert_variable_imputations(db, variable, imputations)

        # Update metadata for each variable
        update_metadata(
            db=db,
            study_id=study_id,
            variable_name=variable,
            n_imputations=config["n_imputations"],
            n_rows_imputed=len(imputations[variable]),
            imputation_method="cart",
            stage="adult_anxiety"
        )
```

**Common Error:**
```python
# ❌ WRONG: No metadata tracking
insert_variable_imputations(db, variable, imputations)
# Missing update_metadata() call!
```

**Severity:** IMPORTANT - Prevents auditing and validation

---

### Check 5: Table Naming Convention ✓ IMPORTANT

**Purpose:** Consistent programmatic access to imputation tables

**Pattern:** `{study_id}_imputed_{variable}` format

**Location:** Python script, in table creation SQL

**How to Check:**
```
1. Search Python script for "CREATE TABLE"
2. Extract table name from each statement
3. Verify matches pattern: {study_id}_imputed_{variable}
4. Check consistency across all tables
```

**Expected:**
```python
CREATE TABLE IF NOT EXISTS "ne25_imputed_gad7_1" (
    "study_id" VARCHAR NOT NULL,
    "pid" VARCHAR NOT NULL,
    "record_id" INTEGER NOT NULL,
    "imputation_m" INTEGER NOT NULL,
    "gad7_1" INTEGER NOT NULL,
    PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
```

**Common Error:**
```python
# ❌ WRONG: Incorrect naming pattern
CREATE TABLE IF NOT EXISTS "ne25_gad7_1_imputed" (...)
CREATE TABLE IF NOT EXISTS "imputed_gad7_1" (...)
```

**Severity:** IMPORTANT - Breaks helper functions and queries

---

### Check 6: Index Creation ✓ IMPORTANT

**Purpose:** Query performance for data retrieval

**Pattern:** Two indexes per table: `(pid, record_id)` and `(imputation_m)`

**Location:** Python script, after table creation SQL

**How to Check:**
```
1. Search Python script for "CREATE INDEX"
2. For each table, verify 2 indexes exist
3. Check index names follow pattern
4. Verify indexed columns are correct
```

**Expected:**
```python
CREATE TABLE IF NOT EXISTS "ne25_imputed_gad7_1" (...);

CREATE INDEX IF NOT EXISTS "idx_ne25_imputed_gad7_1_pid_record"
    ON "ne25_imputed_gad7_1" (pid, record_id);

CREATE INDEX IF NOT EXISTS "idx_ne25_imputed_gad7_1_imputation_m"
    ON "ne25_imputed_gad7_1" (imputation_m);
```

**Common Error:**
```python
# ❌ WRONG: Missing indexes
CREATE TABLE IF NOT EXISTS "ne25_imputed_gad7_1" (...);
# No indexes created!
```

**Severity:** IMPORTANT - Degrades query performance significantly

---

### Check 7: R Namespacing ✓ RECOMMENDED

**Purpose:** Prevent namespace conflicts and improve code clarity

**Pattern:** Explicit package prefixes on all function calls

**Location:** R script, throughout

**How to Check:**
```
1. Search for common function names without prefix
2. Check: select, filter, mutate, summarise (should be dplyr::)
3. Check: pivot_longer, pivot_wider (should be tidyr::)
4. Check: read_feather, write_feather (should be arrow::)
5. Check: mice, complete (should be mice::)
```

**Expected:**
```r
data %>%
  dplyr::select(pid, record_id) %>%
  dplyr::filter(age > 5) %>%
  dplyr::mutate(new_var = old_var * 2)

arrow::write_feather(data, output_path)
mice_result <- mice::mice(data, m = 1, method = "cart")
```

**Common Error:**
```r
# ❌ WRONG: No namespace prefixes
data %>%
  select(pid, record_id) %>%
  filter(age > 5) %>%
  mutate(new_var = old_var * 2)
```

**Severity:** RECOMMENDED - Can cause conflicts but not always fatal

---

### Check 8: NULL Filtering ✓ IMPORTANT

**Purpose:** Prevent constraint violations and data quality issues

**Pattern:** Remove NULL values before database insertion

**Location:** Python script, before inserting data

**How to Check:**
```
1. Find data insertion logic
2. Check for NULL filtering before insertion
3. Verify uses .isna() or .notna() check
4. Confirm removes rows with NULL in target variable
```

**Expected:**
```python
def insert_variable_imputations(db, variable, data):
    # Remove records where imputation failed (NULL values)
    data_clean = data[~data[variable].isna()]

    if len(data_clean) == 0:
        print(f"[WARN] No valid imputations for {variable}")
        return

    # Insert clean data
    with db.get_connection() as conn:
        data_clean.to_sql(table_name, conn, if_exists='append', index=False)
```

**Common Error:**
```python
# ❌ WRONG: No NULL filtering
data.to_sql(table_name, conn, if_exists='append', index=False)
# May insert NULL values, violating NOT NULL constraint!
```

**Severity:** IMPORTANT - Causes database insertion failures

---

## Validation Report Format

When agent runs validation, it should generate a report in this format:

```
=============================================================================
VALIDATION REPORT: Stage XX ({domain})
=============================================================================

Files Validated:
  R Script: scripts/imputation/ne25/{XX}_impute_{domain}.R
  Python Script: scripts/imputation/ne25/{XX}b_insert_{domain}.py

=============================================================================
CRITICAL CHECKS
=============================================================================

✅ PASS: Seed Usage Pattern
   - Found: set.seed(seed + m) at line 439
   - Location: Inside for (m in 1:M) loop
   - Status: Correct pattern

✅ PASS: Defensive Filtering
   - Found 3 DBI::dbGetQuery calls
   - All include WHERE "eligible.x" = TRUE AND "authentic.x" = TRUE
   - Lines: 94, 224, 360

❌ FAIL: Storage Convention
   - Line 268: Saving all records instead of only originally_missing
   - Issue: Missing is.na() check before write_feather
   - Impact: IMPORTANT - May overwrite observed values

=============================================================================
IMPORTANT CHECKS
=============================================================================

❌ FAIL: Metadata Tracking
   - Expected: 9 update_metadata() calls (one per variable)
   - Found: 0 calls
   - Issue: No metadata tracking implemented
   - Impact: IMPORTANT - Prevents auditing

✅ PASS: Table Naming Convention
   - All 9 tables follow {study_id}_imputed_{variable} pattern
   - Examples: ne25_imputed_gad7_1, ne25_imputed_gad7_2, ...

❌ FAIL: Index Creation
   - Table ne25_imputed_gad7_1: Missing imputation_m index
   - Table ne25_imputed_gad7_2: Missing both indexes
   - Impact: IMPORTANT - Poor query performance

=============================================================================
RECOMMENDED CHECKS
=============================================================================

⚠️  WARN: R Namespacing
   - Line 145: select() should be dplyr::select()
   - Line 146: mutate() should be dplyr::mutate()
   - Count: 12 unprefixed function calls
   - Impact: RECOMMENDED - May cause namespace conflicts

✅ PASS: NULL Filtering
   - Found NULL removal at line 287
   - Pattern: data[~data[variable].isna()]
   - Status: Correct implementation

=============================================================================
SUMMARY
=============================================================================

Overall Status: ❌ FAILED (3 failures, 1 warning)

Critical Issues: 1
  - Storage Convention violation (line 268)

Important Issues: 2
  - Missing metadata tracking (Python script)
  - Missing indexes on 2 tables (Python script)

Recommended Improvements: 1
  - Add R namespace prefixes (12 locations)

=============================================================================
RECOMMENDED ACTIONS
=============================================================================

1. Fix storage convention in R script (line 268)
2. Add update_metadata() calls in Python script
3. Add missing indexes to table creation SQL
4. (Optional) Add R namespace prefixes for clarity

Would you like me to generate corrected code for these issues?
```

---

## Using Validation Mode

**Invoke validation:**
```
User: "Validate Stage 7"
User: "Check if scripts/imputation/ne25/05_impute_adult_mental_health.R follows patterns"
User: "Run validation on adult anxiety implementation"
```

**Agent will:**
1. Read specified files
2. Run all 8 checks
3. Generate detailed report
4. Offer to fix any issues found

---

## Severity Levels

**CRITICAL** ⚠️
- Must be fixed before production use
- Causes incorrect results or data corruption
- Examples: Wrong seed usage, missing defensive filtering

**IMPORTANT** ✓
- Should be fixed for best practices
- Causes performance issues or prevents auditing
- Examples: Missing indexes, no metadata tracking

**RECOMMENDED** ℹ️
- Nice to have for code quality
- Improves maintainability but not required
- Examples: R namespacing, code comments

---

**For complete pattern documentation, see:** `docs/imputation/ADDING_IMPUTATION_STAGES.md`

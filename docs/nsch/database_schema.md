# NSCH Database Schema Documentation

Comprehensive documentation of the NSCH DuckDB database structure.

**Last Updated:** October 2025

---

## Table of Contents

1. [Database Overview](#database-overview)
2. [Data Tables](#data-tables)
3. [Metadata Tables](#metadata-tables)
4. [Schema Details](#schema-details)
5. [Common Queries](#common-queries)
6. [Design Decisions](#design-decisions)

---

## Database Overview

### Connection Information

**Database File:** `data/duckdb/kidsights_local.duckdb`

**Database Type:** DuckDB (columnar analytical database)

**Total Tables:** 11
- 8 data tables (`nsch_{year}_raw`)
- 3 metadata tables (`nsch_variables`, `nsch_value_labels`, `nsch_crosswalk`)

**Total Records:** 284,496 survey responses (2017-2023)

**Database Size:** 0.27 MB (efficient columnar compression)

### Table Summary

| Table Name | Type | Records | Purpose |
|------------|------|---------|---------|
| `nsch_2016_raw` | Data | 0 | 2016 survey data (empty - schema incompatibility) |
| `nsch_2017_raw` | Data | 21,599 | 2017 survey data |
| `nsch_2018_raw` | Data | 30,530 | 2018 survey data |
| `nsch_2019_raw` | Data | 29,433 | 2019 survey data |
| `nsch_2020_raw` | Data | 42,777 | 2020 survey data |
| `nsch_2021_raw` | Data | 50,892 | 2021 survey data |
| `nsch_2022_raw` | Data | 54,103 | 2022 survey data |
| `nsch_2023_raw` | Data | 55,162 | 2023 survey data |
| `nsch_variables` | Metadata | 6,867 | Variable definitions (name, label, type) |
| `nsch_value_labels` | Metadata | 36,164 | Value label mappings (code → meaning) |
| `nsch_crosswalk` | Metadata | 0 | Variable name changes across years (future use) |

---

## Data Tables

### Structure

Each year has its own table with the naming pattern `nsch_{year}_raw`.

**Why year-specific tables?**
- Survey questionnaires evolve over time
- Variable names change across years
- Response options differ between years
- New variables are added/removed annually

### Common Schema Pattern

While column counts vary by year (813-923 columns), all year tables share common identifiers:

```sql
-- Core identifiers present in all years
HHID         DOUBLE    -- Unique household identifier
YEAR         DOUBLE    -- Survey year
FIPSST       DOUBLE    -- State FIPS code
STRATUM      DOUBLE    -- Sampling stratum
```

### Year-Specific Details

#### 2016 Data

```sql
TABLE: nsch_2016_raw
Columns: 840
Records: 0 (empty due to schema incompatibility)
Status: Table exists but no data loaded
```

**Known Issue:** 2016 uses different variable encodings than 2017-2023. Will be addressed in harmonization phase.

#### 2017 Data

```sql
TABLE: nsch_2017_raw
Columns: 813
Records: 21,599
First HHID: 17000010
```

**Sample Structure:**
```sql
-- View table schema
PRAGMA table_info(nsch_2017_raw);

-- Sample record
SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX, FIPSST
FROM nsch_2017_raw
LIMIT 5;
```

#### 2018 Data

```sql
TABLE: nsch_2018_raw
Columns: 835
Records: 30,530
First HHID: 18000001
```

#### 2019 Data

```sql
TABLE: nsch_2019_raw
Columns: 834
Records: 29,433
First HHID: 19000001
```

#### 2020 Data

```sql
TABLE: nsch_2020_raw
Columns: 847
Records: 42,777
First HHID: 20001293
```

#### 2021 Data

```sql
TABLE: nsch_2021_raw
Columns: 880
Records: 50,892
First HHID: 21000002
```

#### 2022 Data

```sql
TABLE: nsch_2022_raw
Columns: 923
Records: 54,103
First HHID: 22000005
```

#### 2023 Data

```sql
TABLE: nsch_2023_raw
Columns: 895
Records: 55,162
First HHID: 23043707
```

### Data Types

**All survey variables are stored as `DOUBLE` (floating-point):**

- Preserves SPSS numeric precision
- Handles missing values (NaN)
- Maintains value label codes
- Allows efficient aggregation

**Example:**
```sql
-- Check data types
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'nsch_2023_raw'
LIMIT 10;

-- All columns are DOUBLE
```

---

## Metadata Tables

### nsch_variables

**Purpose:** Stores variable definitions for all years

**Schema:**
```sql
CREATE TABLE nsch_variables (
    year              INTEGER,
    variable_name     VARCHAR,
    variable_label    VARCHAR,
    variable_type     VARCHAR,
    source_file       VARCHAR,
    position          INTEGER,
    loaded_at         TIMESTAMP
);
```

**Records:** 6,867 (variable-year combinations)

**Sample Data:**
```sql
SELECT year, variable_name, variable_label, variable_type
FROM nsch_variables
WHERE year = 2023
LIMIT 5;
```

**Output:**
```
year | variable_name | variable_label              | variable_type
-----|---------------|-----------------------------|---------------
2023 | HEIGHT        | Child's Height (CM)        | numeric
2023 | FIPSST        | State FIPS Code            | numeric
2023 | STRATUM       | Sampling Stratum           | numeric
2023 | HHID          | Unique Household ID        | numeric
2023 | FORMTYPE      | Form Type                  | numeric
```

### nsch_value_labels

**Purpose:** Maps numeric codes to text labels (response options)

**Schema:**
```sql
CREATE TABLE nsch_value_labels (
    year              INTEGER,
    variable_name     VARCHAR,
    value             VARCHAR,
    label             VARCHAR,
    loaded_at         TIMESTAMP
);
```

**Records:** 36,164 (value label mappings)

**Sample Data:**
```sql
SELECT value, label
FROM nsch_value_labels
WHERE year = 2023
  AND variable_name = 'SC_SEX'
ORDER BY value;
```

**Output:**
```
value | label
------|---------------------------
1.0   | Male
2.0   | Female
90.0  | Not in universe
95.0  | Logical skip
96.0  | Suppressed for confidentiality
99.0  | No valid response
```

### nsch_crosswalk

**Purpose:** Tracks variable name changes across years (future use)

**Schema:**
```sql
CREATE TABLE nsch_crosswalk (
    variable_name_old   VARCHAR,
    variable_name_new   VARCHAR,
    year_changed        INTEGER,
    notes               VARCHAR
);
```

**Records:** 0 (reserved for harmonization phase)

**Planned Use:**
```sql
-- Example: Track variable renames
INSERT INTO nsch_crosswalk VALUES
    ('K2Q01', 'K2Q01_R', 2023, 'Added _R suffix for revised version');
```

---

## Schema Details

### Indexes

DuckDB automatically creates indexes for efficient querying. No manual index management needed.

### Primary Keys

No formal primary keys are defined, but `HHID` serves as the unique identifier within each year table.

**Uniqueness Check:**
```sql
-- Verify HHID uniqueness in 2023
SELECT COUNT(*) AS total, COUNT(DISTINCT HHID) AS unique_hhids
FROM nsch_2023_raw;
```

### Constraints

No foreign key constraints are enforced. Metadata tables reference data tables by year and variable name, but this is not enforced at the database level.

**Validation Example:**
```sql
-- Check if all 2023 variables have metadata
SELECT COUNT(*) AS vars_without_metadata
FROM (
    SELECT column_name
    FROM information_schema.columns
    WHERE table_name = 'nsch_2023_raw'
) AS data_cols
LEFT JOIN nsch_variables AS meta
    ON data_cols.column_name = meta.variable_name
   AND meta.year = 2023
WHERE meta.variable_name IS NULL;
```

### Missing Values

Missing values are represented as:
- `NULL` (no value recorded)
- Specific codes: 90 (Not in universe), 95 (Logical skip), 96 (Suppressed), 99 (No valid response)

**Example:**
```sql
-- Count missing values for a variable
SELECT
    COUNT(*) AS total,
    COUNT(SC_AGE_YEARS) AS non_null,
    COUNT(*) - COUNT(SC_AGE_YEARS) AS null_count,
    SUM(CASE WHEN SC_AGE_YEARS IN (90, 95, 96, 99) THEN 1 ELSE 0 END) AS coded_missing
FROM nsch_2023_raw;
```

---

## Common Queries

### Basic Data Retrieval

#### Get Sample Records

```sql
-- Get first 10 records from 2023
SELECT *
FROM nsch_2023_raw
LIMIT 10;
```

#### Get Specific Variables

```sql
-- Get selected columns
SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX, FIPSST
FROM nsch_2023_raw
WHERE SC_AGE_YEARS <= 5
LIMIT 100;
```

#### Count Records by Year

```sql
-- Cross-year record counts
SELECT 2017 AS year, COUNT(*) AS records FROM nsch_2017_raw
UNION ALL
SELECT 2018, COUNT(*) FROM nsch_2018_raw
UNION ALL
SELECT 2019, COUNT(*) FROM nsch_2019_raw
UNION ALL
SELECT 2020, COUNT(*) FROM nsch_2020_raw
UNION ALL
SELECT 2021, COUNT(*) FROM nsch_2021_raw
UNION ALL
SELECT 2022, COUNT(*) FROM nsch_2022_raw
UNION ALL
SELECT 2023, COUNT(*) FROM nsch_2023_raw
ORDER BY year;
```

### Metadata Queries

#### Find Variables by Keyword

```sql
-- Find all ACE-related variables in 2023
SELECT variable_name, variable_label
FROM nsch_variables
WHERE year = 2023
  AND (
      LOWER(variable_label) LIKE '%ace%'
      OR LOWER(variable_label) LIKE '%adverse%'
  )
ORDER BY variable_name;
```

#### Get Value Labels for a Variable

```sql
-- Get response options for SC_SEX in 2023
SELECT value, label
FROM nsch_value_labels
WHERE year = 2023
  AND variable_name = 'SC_SEX'
ORDER BY value;
```

#### Find Common Variables Across Years

```sql
-- Variables present in all 7 years with data (2017-2023)
SELECT variable_name, COUNT(DISTINCT year) AS year_count
FROM nsch_variables
WHERE year BETWEEN 2017 AND 2023
GROUP BY variable_name
HAVING COUNT(DISTINCT year) = 7
ORDER BY variable_name;
```

### Cross-Year Analysis

#### Compare Variable Availability

```sql
-- Check if K2Q01 exists in all years
SELECT year, variable_name, variable_label
FROM nsch_variables
WHERE variable_name = 'K2Q01'
ORDER BY year;
```

#### Age Distribution by Year

```sql
-- Age distribution in 2023
SELECT
    CAST(SC_AGE_YEARS AS INTEGER) AS age,
    COUNT(*) AS count
FROM nsch_2023_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
  AND SC_AGE_YEARS IS NOT NULL
GROUP BY age
ORDER BY age;
```

#### State-Level Sample Sizes

```sql
-- Sample size by state in 2023
SELECT
    FIPSST AS state_fips,
    COUNT(*) AS sample_size
FROM nsch_2023_raw
GROUP BY FIPSST
ORDER BY sample_size DESC
LIMIT 10;
```

### Joining Data and Metadata

#### Get Data with Variable Labels

```sql
-- Query data and display variable labels
WITH var_labels AS (
    SELECT variable_name, variable_label
    FROM nsch_variables
    WHERE year = 2023
)
SELECT
    d.HHID,
    d.SC_AGE_YEARS,
    v_age.variable_label AS age_label,
    d.SC_SEX,
    v_sex.variable_label AS sex_label
FROM nsch_2023_raw d
LEFT JOIN var_labels v_age ON v_age.variable_name = 'SC_AGE_YEARS'
LEFT JOIN var_labels v_sex ON v_sex.variable_name = 'SC_SEX'
LIMIT 10;
```

#### Decode Value Labels

```sql
-- Get decoded sex values for 2023
SELECT
    d.HHID,
    d.SC_SEX AS sex_code,
    vl.label AS sex_label
FROM nsch_2023_raw d
LEFT JOIN nsch_value_labels vl
    ON vl.variable_name = 'SC_SEX'
   AND vl.year = 2023
   AND CAST(vl.value AS DOUBLE) = d.SC_SEX
LIMIT 10;
```

### Export Queries

#### Export to CSV

```sql
-- Export filtered data to CSV
COPY (
    SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX, FIPSST
    FROM nsch_2023_raw
    WHERE SC_AGE_YEARS <= 5
) TO 'output/nsch_2023_ages_0_5.csv' (HEADER, DELIMITER ',');
```

#### Export to Parquet

```sql
-- Export full year to Parquet
COPY (SELECT * FROM nsch_2023_raw)
TO 'output/nsch_2023_full.parquet' (FORMAT PARQUET);
```

---

## Design Decisions

### Why Year-Specific Tables?

**Decision:** Create separate tables for each year (`nsch_{year}_raw`)

**Rationale:**
1. **Survey Evolution:** Questionnaires change annually
2. **Variable Changes:** Column names/meanings differ across years
3. **No Automatic Harmonization:** Raw data preserved as-is
4. **Future Flexibility:** Harmonization will create separate standardized tables

**Alternative Considered:** Single table with all years
- **Rejected:** Would require extensive harmonization upfront
- **Rejected:** Would lose year-specific variable details

### Why DOUBLE Data Type?

**Decision:** Store all numeric variables as `DOUBLE`

**Rationale:**
1. **SPSS Compatibility:** Preserves original SPSS numeric precision
2. **Missing Values:** NaN naturally represents missing data
3. **Code Preservation:** Maintains original numeric codes
4. **Aggregation:** Efficient for statistical operations

**Alternative Considered:** Mixed types (INTEGER, VARCHAR, etc.)
- **Rejected:** Would require complex type inference
- **Rejected:** Could lose precision during conversion

### Why No Primary Keys?

**Decision:** No formal primary key constraints

**Rationale:**
1. **DuckDB Design:** Analytical database, not transactional
2. **HHID Uniqueness:** Already unique within each year
3. **Performance:** No overhead from constraint checking
4. **Flexibility:** Easier to reload/replace data

**Note:** HHID serves as logical primary key, but not enforced

### Why Separate Metadata Tables?

**Decision:** Store metadata in separate tables (`nsch_variables`, `nsch_value_labels`)

**Rationale:**
1. **Documentation:** Auto-generated reference documentation
2. **Querying:** Easy to search variables by keyword
3. **Decoding:** Programmatic access to value labels
4. **Versioning:** Track variable definitions across years

**Alternative Considered:** Metadata embedded in column comments
- **Rejected:** Limited queryability
- **Rejected:** Not accessible programmatically

### Why Feather Intermediate Format?

**Decision:** Use Feather files between SPSS and DuckDB

**Rationale:**
1. **Cross-Language:** Works with both Python and R
2. **Fast I/O:** 3x faster than CSV
3. **Type Preservation:** Maintains data types perfectly
4. **Validation:** Easy to validate before database insertion

**Alternative Considered:** Direct SPSS → DuckDB
- **Rejected:** Less flexible for validation
- **Rejected:** Harder to debug issues

---

## Performance Considerations

### Query Optimization

**Best Practices:**

1. **Use LIMIT** for exploratory queries:
```sql
-- Good: Fast exploratory query
SELECT * FROM nsch_2023_raw LIMIT 100;

-- Bad: Loads entire table (55K rows)
SELECT * FROM nsch_2023_raw;
```

2. **Filter early** to reduce data scanned:
```sql
-- Good: Filter before aggregation
SELECT AVG(SC_AGE_YEARS)
FROM nsch_2023_raw
WHERE FIPSST = 31;  -- Nebraska only

-- Bad: Scans entire table
SELECT AVG(SC_AGE_YEARS)
FROM nsch_2023_raw;
```

3. **Select only needed columns**:
```sql
-- Good: Select specific columns
SELECT HHID, SC_AGE_YEARS
FROM nsch_2023_raw;

-- Bad: Select all 895 columns
SELECT * FROM nsch_2023_raw;
```

### Storage Efficiency

DuckDB's columnar format provides:
- **200:1 compression ratio** (Feather → DuckDB)
- **Sub-second queries** for most operations
- **Efficient aggregation** by column

### Memory Usage

- **Typical RAM Usage:** <2 GB for full pipeline
- **Query Memory:** <500 MB for most queries
- **Can run on standard laptop**

---

## Future Enhancements

### Planned (Harmonization Phase)

1. **Standardized Variables Table:**
```sql
CREATE TABLE nsch_harmonized (
    hhid              BIGINT,
    year              INTEGER,
    age_years         INTEGER,
    sex               VARCHAR,  -- Decoded: "Male"/"Female"
    race_ethnicity    VARCHAR,  -- Standardized categories
    state_fips        INTEGER,
    ...
);
```

2. **Cross-Year Crosswalk:**
```sql
-- Track variable renames
INSERT INTO nsch_crosswalk VALUES
    ('K2Q01', 'K2Q01_R', 2023, 'Added _R suffix');
```

3. **Analysis Views:**
```sql
-- Pre-built views for common analyses
CREATE VIEW nsch_ace_analysis AS
SELECT year, ...
FROM nsch_harmonized
WHERE ...;
```

---

## Additional Resources

- **Variable Reference:** [variables_reference.md](variables_reference.md)
- **Example Queries:** [example_queries.md](example_queries.md)
- **Pipeline Usage:** [pipeline_usage.md](pipeline_usage.md)
- **DuckDB Documentation:** https://duckdb.org/docs/

---

**Last Updated:** October 3, 2025

**Database Version:** 1.0 (7 years loaded: 2017-2023)

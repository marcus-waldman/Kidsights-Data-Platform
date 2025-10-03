# NSCH Example Queries

Practical query examples for analyzing NSCH data in DuckDB.

**Last Updated:** October 2025

---

## Table of Contents

1. [Basic Queries](#basic-queries)
2. [Filtering and Subsetting](#filtering-and-subsetting)
3. [Aggregation and Summary Statistics](#aggregation-and-summary-statistics)
4. [Cross-Year Queries](#cross-year-queries)
5. [Joining with Metadata](#joining-with-metadata)
6. [Value Label Decoding](#value-label-decoding)
7. [Geographic Analysis](#geographic-analysis)
8. [Age and Demographic Analysis](#age-and-demographic-analysis)
9. [Exporting Results](#exporting-results)
10. [Advanced Patterns](#advanced-patterns)

---

## Basic Queries

### Connect to Database

**Python:**
```python
import duckdb
import pandas as pd

# Connect to database
conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Run query
df = conn.execute("SELECT * FROM nsch_2023_raw LIMIT 5").fetchdf()
print(df)

# Close connection
conn.close()
```

**R:**
```r
library(duckdb)

# Connect to database
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Run query
df <- dbGetQuery(conn, "SELECT * FROM nsch_2023_raw LIMIT 5")
print(df)

# Close connection
dbDisconnect(conn, shutdown = TRUE)
```

### Get Sample Records

```sql
-- First 10 records from 2023
SELECT *
FROM nsch_2023_raw
LIMIT 10;
```

### Get Specific Columns

```sql
-- Selected variables only
SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX, FIPSST
FROM nsch_2023_raw
LIMIT 100;
```

### Count Total Records

```sql
-- Total records in 2023
SELECT COUNT(*) AS total_records
FROM nsch_2023_raw;
```

**Output:** `55,162`

---

## Filtering and Subsetting

### Filter by Age

```sql
-- Children ages 0-5 only
SELECT HHID, SC_AGE_YEARS, SC_SEX
FROM nsch_2023_raw
WHERE SC_AGE_YEARS >= 0
  AND SC_AGE_YEARS <= 5
  AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)  -- Exclude missing codes
LIMIT 100;
```

### Filter by State

```sql
-- Nebraska (FIPS 31) children only
SELECT HHID, SC_AGE_YEARS, FIPSST
FROM nsch_2023_raw
WHERE FIPSST = 31;
```

### Filter by Multiple Conditions

```sql
-- Nebraska adolescents (ages 12-17)
SELECT HHID, SC_AGE_YEARS, SC_SEX, FIPSST
FROM nsch_2023_raw
WHERE FIPSST = 31
  AND SC_AGE_YEARS >= 12
  AND SC_AGE_YEARS <= 17
  AND SC_AGE_YEARS NOT IN (90, 95, 96, 99);
```

### Exclude Missing Values

```sql
-- Non-missing general health ratings
SELECT HHID, K2Q01 AS general_health
FROM nsch_2023_raw
WHERE K2Q01 IS NOT NULL
  AND K2Q01 NOT IN (90, 95, 96, 99);
```

---

## Aggregation and Summary Statistics

### Count by Category

```sql
-- Count by sex
SELECT
    SC_SEX,
    COUNT(*) AS count
FROM nsch_2023_raw
WHERE SC_SEX NOT IN (90, 95, 96, 99)
GROUP BY SC_SEX
ORDER BY SC_SEX;
```

### Age Distribution

```sql
-- Age distribution histogram
SELECT
    CAST(SC_AGE_YEARS AS INTEGER) AS age,
    COUNT(*) AS count
FROM nsch_2023_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
  AND SC_AGE_YEARS IS NOT NULL
GROUP BY age
ORDER BY age;
```

### State Sample Sizes

```sql
-- Sample size by state (top 10)
SELECT
    FIPSST AS state_fips,
    COUNT(*) AS sample_size
FROM nsch_2023_raw
GROUP BY FIPSST
ORDER BY sample_size DESC
LIMIT 10;
```

### Average Age by State

```sql
-- Mean age by state
SELECT
    FIPSST AS state_fips,
    COUNT(*) AS n,
    ROUND(AVG(SC_AGE_YEARS), 2) AS mean_age,
    ROUND(STDDEV(SC_AGE_YEARS), 2) AS sd_age
FROM nsch_2023_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
  AND SC_AGE_YEARS IS NOT NULL
GROUP BY FIPSST
ORDER BY mean_age DESC;
```

### Percentages

```sql
-- Percentage by sex
SELECT
    SC_SEX,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent
FROM nsch_2023_raw
WHERE SC_SEX NOT IN (90, 95, 96, 99)
GROUP BY SC_SEX
ORDER BY SC_SEX;
```

---

## Cross-Year Queries

### Record Counts by Year

```sql
-- Compare sample sizes across years
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

### Age Trends Over Time

```sql
-- Mean age by year
SELECT 2017 AS year, ROUND(AVG(SC_AGE_YEARS), 2) AS mean_age
FROM nsch_2017_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
UNION ALL
SELECT 2018, ROUND(AVG(SC_AGE_YEARS), 2)
FROM nsch_2018_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
UNION ALL
SELECT 2019, ROUND(AVG(SC_AGE_YEARS), 2)
FROM nsch_2019_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
UNION ALL
SELECT 2020, ROUND(AVG(SC_AGE_YEARS), 2)
FROM nsch_2020_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
UNION ALL
SELECT 2021, ROUND(AVG(SC_AGE_YEARS), 2)
FROM nsch_2021_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
UNION ALL
SELECT 2022, ROUND(AVG(SC_AGE_YEARS), 2)
FROM nsch_2022_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
UNION ALL
SELECT 2023, ROUND(AVG(SC_AGE_YEARS), 2)
FROM nsch_2023_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
ORDER BY year;
```

### Combine Years for Larger Sample

```sql
-- Combined 2022-2023 data for Nebraska
SELECT HHID, YEAR, SC_AGE_YEARS, FIPSST
FROM nsch_2022_raw
WHERE FIPSST = 31
UNION ALL
SELECT HHID, YEAR, SC_AGE_YEARS, FIPSST
FROM nsch_2023_raw
WHERE FIPSST = 31;
```

---

## Joining with Metadata

### Get Variable Descriptions

```sql
-- Find ACE-related variables in 2023
SELECT variable_name, variable_label
FROM nsch_variables
WHERE year = 2023
  AND (
      LOWER(variable_label) LIKE '%ace%'
      OR LOWER(variable_label) LIKE '%adverse%'
  )
ORDER BY variable_name;
```

### Search Variables by Keyword

```sql
-- Find all mental health variables
SELECT DISTINCT variable_name, variable_label
FROM nsch_variables
WHERE year = 2023
  AND (
      LOWER(variable_label) LIKE '%mental%'
      OR LOWER(variable_label) LIKE '%emotional%'
      OR LOWER(variable_label) LIKE '%anxiety%'
      OR LOWER(variable_label) LIKE '%depression%'
  )
ORDER BY variable_name;
```

### Find Common Variables Across Years

```sql
-- Variables present in all 7 years (2017-2023)
SELECT variable_name, COUNT(DISTINCT year) AS year_count
FROM nsch_variables
WHERE year BETWEEN 2017 AND 2023
GROUP BY variable_name
HAVING COUNT(DISTINCT year) = 7
ORDER BY variable_name;
```

---

## Value Label Decoding

### Get Response Options

```sql
-- See all response options for general health (K2Q01)
SELECT value, label
FROM nsch_value_labels
WHERE year = 2023
  AND variable_name = 'K2Q01'
ORDER BY CAST(value AS DOUBLE);
```

### Decode Single Variable

```sql
-- Decode sex values
SELECT
    d.HHID,
    d.SC_SEX AS sex_code,
    vl.label AS sex_label
FROM nsch_2023_raw d
LEFT JOIN nsch_value_labels vl
    ON vl.variable_name = 'SC_SEX'
   AND vl.year = 2023
   AND CAST(vl.value AS DOUBLE) = d.SC_SEX
WHERE d.SC_SEX NOT IN (90, 95, 96, 99)
LIMIT 100;
```

### Decode Multiple Variables

```sql
-- Decode sex and general health
SELECT
    d.HHID,
    d.SC_AGE_YEARS,
    vl_sex.label AS sex,
    vl_health.label AS general_health
FROM nsch_2023_raw d
LEFT JOIN nsch_value_labels vl_sex
    ON vl_sex.variable_name = 'SC_SEX'
   AND vl_sex.year = 2023
   AND CAST(vl_sex.value AS DOUBLE) = d.SC_SEX
LEFT JOIN nsch_value_labels vl_health
    ON vl_health.variable_name = 'K2Q01'
   AND vl_health.year = 2023
   AND CAST(vl_health.value AS DOUBLE) = d.K2Q01
WHERE d.SC_SEX NOT IN (90, 95, 96, 99)
  AND d.K2Q01 NOT IN (90, 95, 96, 99)
LIMIT 100;
```

### Frequency Table with Labels

```sql
-- General health frequency with labels
SELECT
    vl.label AS health_rating,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent
FROM nsch_2023_raw d
LEFT JOIN nsch_value_labels vl
    ON vl.variable_name = 'K2Q01'
   AND vl.year = 2023
   AND CAST(vl.value AS DOUBLE) = d.K2Q01
WHERE d.K2Q01 NOT IN (90, 95, 96, 99)
  AND d.K2Q01 IS NOT NULL
GROUP BY vl.label, d.K2Q01
ORDER BY d.K2Q01;
```

---

## Geographic Analysis

### Nebraska Sample Summary

```sql
-- Nebraska 2023 summary
SELECT
    COUNT(*) AS total_records,
    COUNT(DISTINCT HHID) AS unique_households,
    ROUND(AVG(SC_AGE_YEARS), 2) AS mean_age,
    MIN(SC_AGE_YEARS) AS min_age,
    MAX(SC_AGE_YEARS) AS max_age
FROM nsch_2023_raw
WHERE FIPSST = 31
  AND SC_AGE_YEARS NOT IN (90, 95, 96, 99);
```

### Top 10 States by Sample Size

```sql
-- Largest state samples in 2023
SELECT
    FIPSST AS state_fips,
    COUNT(*) AS sample_size
FROM nsch_2023_raw
GROUP BY FIPSST
ORDER BY sample_size DESC
LIMIT 10;
```

### Regional Comparison

```sql
-- Compare Midwest states (example: IA, KS, MO, NE)
SELECT
    FIPSST AS state_fips,
    COUNT(*) AS n,
    ROUND(AVG(SC_AGE_YEARS), 2) AS mean_age
FROM nsch_2023_raw
WHERE FIPSST IN (19, 20, 29, 31)  -- IA, KS, MO, NE
  AND SC_AGE_YEARS NOT IN (90, 95, 96, 99)
GROUP BY FIPSST
ORDER BY FIPSST;
```

---

## Age and Demographic Analysis

### Age Groups

```sql
-- Create age groups
SELECT
    CASE
        WHEN SC_AGE_YEARS BETWEEN 0 AND 5 THEN '0-5 years'
        WHEN SC_AGE_YEARS BETWEEN 6 AND 11 THEN '6-11 years'
        WHEN SC_AGE_YEARS BETWEEN 12 AND 17 THEN '12-17 years'
        ELSE 'Missing/Invalid'
    END AS age_group,
    COUNT(*) AS count
FROM nsch_2023_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
GROUP BY age_group
ORDER BY age_group;
```

### Sex Distribution by Age Group

```sql
-- Sex distribution within age groups
SELECT
    CASE
        WHEN SC_AGE_YEARS BETWEEN 0 AND 5 THEN '0-5'
        WHEN SC_AGE_YEARS BETWEEN 6 AND 11 THEN '6-11'
        WHEN SC_AGE_YEARS BETWEEN 12 AND 17 THEN '12-17'
    END AS age_group,
    SC_SEX,
    COUNT(*) AS count
FROM nsch_2023_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
  AND SC_SEX NOT IN (90, 95, 96, 99)
GROUP BY age_group, SC_SEX
ORDER BY age_group, SC_SEX;
```

---

## Exporting Results

### Export to CSV

**Python:**
```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Export filtered data
conn.execute("""
    COPY (
        SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX, FIPSST
        FROM nsch_2023_raw
        WHERE FIPSST = 31
    ) TO 'output/nebraska_2023.csv' (HEADER, DELIMITER ',')
""")

conn.close()
```

**SQL:**
```sql
-- Direct SQL export
COPY (
    SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX, FIPSST
    FROM nsch_2023_raw
    WHERE FIPSST = 31
) TO 'output/nebraska_2023.csv' (HEADER, DELIMITER ',');
```

### Export to Parquet

```sql
-- Export to Parquet format (more efficient)
COPY (SELECT * FROM nsch_2023_raw)
TO 'output/nsch_2023_full.parquet' (FORMAT PARQUET);
```

### Export Aggregated Results

```python
import duckdb
import pandas as pd

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Create summary table
summary = conn.execute("""
    SELECT
        FIPSST AS state,
        COUNT(*) AS n,
        ROUND(AVG(SC_AGE_YEARS), 2) AS mean_age
    FROM nsch_2023_raw
    WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
    GROUP BY FIPSST
    ORDER BY FIPSST
""").fetchdf()

# Export to CSV
summary.to_csv('output/state_summary_2023.csv', index=False)

conn.close()
```

---

## Advanced Patterns

### Window Functions

```sql
-- Rank states by sample size
SELECT
    FIPSST,
    COUNT(*) AS sample_size,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS rank
FROM nsch_2023_raw
GROUP BY FIPSST
ORDER BY rank
LIMIT 10;
```

### Percentiles

```sql
-- Age percentiles
SELECT
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY SC_AGE_YEARS) AS p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY SC_AGE_YEARS) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY SC_AGE_YEARS) AS p75
FROM nsch_2023_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99);
```

### Conditional Aggregation

```sql
-- Count conditions by age group
SELECT
    CASE
        WHEN SC_AGE_YEARS BETWEEN 0 AND 5 THEN '0-5'
        WHEN SC_AGE_YEARS BETWEEN 6 AND 11 THEN '6-11'
        WHEN SC_AGE_YEARS BETWEEN 12 AND 17 THEN '12-17'
    END AS age_group,
    SUM(CASE WHEN K2Q01 = 1 THEN 1 ELSE 0 END) AS excellent_health,
    SUM(CASE WHEN K2Q01 = 2 THEN 1 ELSE 0 END) AS very_good_health,
    SUM(CASE WHEN K2Q01 = 3 THEN 1 ELSE 0 END) AS good_health,
    COUNT(*) AS total
FROM nsch_2023_raw
WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
  AND K2Q01 NOT IN (90, 95, 96, 99)
GROUP BY age_group
ORDER BY age_group;
```

### Create Derived Variables (CTE)

```sql
-- Create age groups and summarize
WITH age_categorized AS (
    SELECT
        HHID,
        SC_AGE_YEARS,
        CASE
            WHEN SC_AGE_YEARS BETWEEN 0 AND 5 THEN 'Early Childhood'
            WHEN SC_AGE_YEARS BETWEEN 6 AND 11 THEN 'Middle Childhood'
            WHEN SC_AGE_YEARS BETWEEN 12 AND 17 THEN 'Adolescence'
        END AS developmental_stage,
        K2Q01 AS general_health
    FROM nsch_2023_raw
    WHERE SC_AGE_YEARS NOT IN (90, 95, 96, 99)
      AND K2Q01 NOT IN (90, 95, 96, 99)
)
SELECT
    developmental_stage,
    COUNT(*) AS n,
    ROUND(AVG(general_health), 2) AS mean_health_rating
FROM age_categorized
GROUP BY developmental_stage
ORDER BY developmental_stage;
```

### Complex Filtering with Subquery

```sql
-- Find HHIDs with children in multiple age groups
SELECT DISTINCT HHID
FROM nsch_2023_raw
WHERE HHID IN (
    SELECT HHID
    FROM nsch_2023_raw
    WHERE SC_AGE_YEARS BETWEEN 0 AND 5
)
AND HHID IN (
    SELECT HHID
    FROM nsch_2023_raw
    WHERE SC_AGE_YEARS BETWEEN 12 AND 17
);
```

---

## Query Templates

### Template: State Analysis

```sql
-- Replace {STATE_FIPS} and {YEAR} with desired values
SELECT
    COUNT(*) AS sample_size,
    ROUND(AVG(SC_AGE_YEARS), 2) AS mean_age,
    ROUND(STDDEV(SC_AGE_YEARS), 2) AS sd_age,
    MIN(SC_AGE_YEARS) AS min_age,
    MAX(SC_AGE_YEARS) AS max_age
FROM nsch_{YEAR}_raw
WHERE FIPSST = {STATE_FIPS}
  AND SC_AGE_YEARS NOT IN (90, 95, 96, 99);
```

### Template: Variable Frequency

```sql
-- Replace {VARIABLE}, {YEAR} with desired values
SELECT
    {VARIABLE} AS value,
    vl.label,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent
FROM nsch_{YEAR}_raw d
LEFT JOIN nsch_value_labels vl
    ON vl.variable_name = '{VARIABLE}'
   AND vl.year = {YEAR}
   AND CAST(vl.value AS DOUBLE) = d.{VARIABLE}
WHERE {VARIABLE} NOT IN (90, 95, 96, 99)
  AND {VARIABLE} IS NOT NULL
GROUP BY {VARIABLE}, vl.label
ORDER BY {VARIABLE};
```

### Template: Cross-Tabulation

```sql
-- Replace {VAR1}, {VAR2}, {YEAR}
SELECT
    {VAR1},
    {VAR2},
    COUNT(*) AS count
FROM nsch_{YEAR}_raw
WHERE {VAR1} NOT IN (90, 95, 96, 99)
  AND {VAR2} NOT IN (90, 95, 96, 99)
GROUP BY {VAR1}, {VAR2}
ORDER BY {VAR1}, {VAR2};
```

---

## Best Practices

### 1. Always Exclude Missing Codes

```sql
-- Include this in WHERE clause for numeric variables
WHERE variable_name NOT IN (90, 95, 96, 99)
  AND variable_name IS NOT NULL
```

### 2. Use LIMIT for Exploration

```sql
-- Start with LIMIT to test queries
SELECT * FROM nsch_2023_raw
LIMIT 10;  -- Remove LIMIT once query is validated
```

### 3. Check Value Labels First

```sql
-- Before analyzing a variable, check its value labels
SELECT value, label
FROM nsch_value_labels
WHERE year = 2023
  AND variable_name = 'YOUR_VARIABLE'
ORDER BY CAST(value AS DOUBLE);
```

### 4. Use CTEs for Complex Queries

```sql
-- Break complex queries into readable steps
WITH filtered_data AS (
    SELECT ...
    FROM ...
    WHERE ...
),
aggregated AS (
    SELECT ...
    FROM filtered_data
    GROUP BY ...
)
SELECT * FROM aggregated;
```

### 5. Cast Value Labels for Joins

```sql
-- Always cast value labels to DOUBLE for joining
AND CAST(vl.value AS DOUBLE) = d.variable_name
```

---

## Additional Resources

- **Database Schema:** [database_schema.md](database_schema.md)
- **Variable Reference:** [variables_reference.md](variables_reference.md)
- **Pipeline Usage:** [pipeline_usage.md](pipeline_usage.md)
- **DuckDB SQL Reference:** https://duckdb.org/docs/sql/introduction

---

**Last Updated:** October 3, 2025

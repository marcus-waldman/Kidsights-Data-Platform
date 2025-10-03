# Geographic Crosswalks Guide

**Last Updated:** October 2025

This document provides comprehensive documentation for the geographic crosswalk system in the Kidsights Data Platform. Geographic crosswalks enable translation of ZIP codes to various geographic units for spatial analysis and reporting.

---

## Table of Contents

1. [Overview](#overview)
2. [Database-Backed Reference Tables](#database-backed-reference-tables)
3. [Loading Crosswalk Data](#loading-crosswalk-data)
4. [Querying Crosswalks](#querying-crosswalks)
5. [Derived Geographic Variables](#derived-geographic-variables)
6. [Data Format and Structure](#data-format-and-structure)
7. [Use Cases](#use-cases)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### What are Geographic Crosswalks?

Geographic crosswalks are lookup tables that map one geographic unit (e.g., ZIP code) to another (e.g., county, PUMA, school district). They enable:
- **Geographic aggregation:** Roll up ZIP-level data to counties or PUMAs
- **Spatial joining:** Link datasets using different geographic identifiers
- **Policy analysis:** Identify legislative districts, school districts, etc.
- **Rural/urban classification:** Classify locations by urbanicity

### Why Database-Backed?

The crosswalk system uses **DuckDB reference tables** rather than static CSV files to:
- **Avoid R segfaults:** Queries via Python bypass R DuckDB driver issues
- **Enable efficient joins:** Database joins are faster than in-memory merges
- **Support updates:** Refresh crosswalks without code changes
- **Ensure consistency:** Single source of truth for all geographic mappings

### Key Features

- **10 crosswalk tables** covering major US geographies
- **126,000+ rows** of ZIP-to-geography mappings
- **Allocation factors** for ZIP codes spanning multiple geographies
- **Hybrid R-Python** querying for stability

---

## Database-Backed Reference Tables

The system includes **10 crosswalk tables** (126,000+ total rows) stored in DuckDB.

### Table Inventory

| Table Name | Description | Source Vintage | Row Count |
|------------|-------------|----------------|-----------|
| `geo_zip_to_puma` | Public Use Microdata Areas | 2020 Census | ~42,000 |
| `geo_zip_to_county` | County FIPS codes | 2020 Census | ~42,000 |
| `geo_zip_to_tract` | Census tract FIPS codes | 2020 Census | ~42,000 |
| `geo_zip_to_cbsa` | Core-Based Statistical Areas | 2020 Census | ~30,000 |
| `geo_zip_to_urban_rural` | Urban/Rural classification | 2022 Census | ~42,000 |
| `geo_zip_to_school_dist` | School districts | 2020 | ~42,000 |
| `geo_zip_to_state_leg_lower` | State house districts | 2024 | ~42,000 |
| `geo_zip_to_state_leg_upper` | State senate districts | 2024 | ~42,000 |
| `geo_zip_to_congress` | US Congressional districts | 119th Congress (2025) | ~42,000 |
| `geo_zip_to_native_lands` | AIANNH areas (tribal lands) | 2021 | Variable |

### Table Schema

All crosswalk tables follow a consistent schema:

```sql
CREATE TABLE geo_zip_to_{geography} (
    zip VARCHAR,              -- 5-digit ZIP code
    {geography_code} VARCHAR, -- Geographic unit code (FIPS, PUMA ID, etc.)
    {geography_name} VARCHAR, -- Geographic unit name (optional)
    afact DOUBLE,             -- Allocation factor (0.0-1.0)
    PRIMARY KEY (zip, {geography_code})
);
```

**Example: `geo_zip_to_county`**
```sql
CREATE TABLE geo_zip_to_county (
    zip VARCHAR,
    county VARCHAR,       -- 5-digit county FIPS (state + county)
    county_name VARCHAR,  -- County name
    afact DOUBLE,
    PRIMARY KEY (zip, county)
);
```

### Allocation Factors

**Allocation factors** (`afact`) indicate the proportion of a ZIP code's population in each geographic unit.

**Why needed?** ZIP codes don't align perfectly with other geographies:
- A ZIP code may span multiple counties
- A ZIP code may span multiple school districts
- Population is not evenly distributed within ZIP codes

**Values:**
- `0.0` to `1.0` (percentage as decimal)
- Sum of `afact` for all rows with same ZIP = 1.0
- Higher `afact` = more population in that geography

**Example:**
```
ZIP 68001 spans 2 counties:
- Douglas County: afact = 0.75 (75% of ZIP population)
- Sarpy County:   afact = 0.25 (25% of ZIP population)
```

---

## Loading Crosswalk Data

### Initial Load

Run this script once to populate all 10 crosswalk tables:

```bash
# Load all geographic crosswalk reference tables
python pipelines/python/load_geo_crosswalks_sql.py
```

**What it does:**
1. Connects to DuckDB database
2. Drops existing crosswalk tables (if any)
3. Creates fresh tables from source CSV files
4. Validates row counts and schema
5. Creates indexes for efficient queries

**Output:**
```
[INFO] Loading geographic crosswalks into database
[OK] geo_zip_to_puma: 42,120 rows loaded
[OK] geo_zip_to_county: 42,120 rows loaded
[OK] geo_zip_to_tract: 42,120 rows loaded
...
[OK] All 10 crosswalk tables loaded successfully
```

### Refresh Data

To update crosswalks with new vintages (e.g., new census data, redistricting):

1. Place updated CSV files in `data/geographic_crosswalks/`
2. Run loader script: `python pipelines/python/load_geo_crosswalks_sql.py`
3. Verify row counts match expectations

### Manual Inspection

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Check what crosswalk tables exist
tables = db.execute_query("""
    SELECT table_name
    FROM information_schema.tables
    WHERE table_name LIKE 'geo_%'
    ORDER BY table_name
""")
print(f"Found {len(tables)} crosswalk tables")

# Check row counts
for table in tables:
    count = db.execute_query(f"SELECT COUNT(*) FROM {table[0]}")[0][0]
    print(f"{table[0]}: {count:,} rows")
```

---

## Querying Crosswalks

### From Python

```python
from python.db.query_geo_crosswalk import query_geo_crosswalk

# Query entire crosswalk table
puma_data = query_geo_crosswalk("geo_zip_to_puma")
print(f"PUMA crosswalk: {len(puma_data)} rows")

# Query for specific ZIP codes
county_data = query_geo_crosswalk("geo_zip_to_county", zip_codes=["68001", "68022"])
print(county_data)
```

### From R

```r
# Source utility function
source("R/utils/query_geo_crosswalk.R")

# Query entire crosswalk table (returns data.frame)
puma_data <- query_geo_crosswalk("geo_zip_to_puma")
cat("PUMA crosswalk:", nrow(puma_data), "rows\n")

# Query for specific ZIP codes
county_data <- query_geo_crosswalk("geo_zip_to_county", zip_codes = c("68001", "68022"))
print(county_data)
```

### Direct SQL Queries

**Example 1: Find all counties for a ZIP code**
```sql
SELECT zip, county, county_name, afact
FROM geo_zip_to_county
WHERE zip = '68001'
ORDER BY afact DESC;
```

**Example 2: Find primary county (highest afact)**
```sql
SELECT zip, county, county_name, MAX(afact) as afact
FROM geo_zip_to_county
WHERE zip = '68001'
GROUP BY zip;
```

**Example 3: Get urban/rural classification**
```sql
SELECT zip, urban_rural, urban_pct
FROM geo_zip_to_urban_rural
WHERE zip IN ('68001', '68022', '68144');
```

**Example 4: Join with survey data**
```sql
SELECT
    s.pid,
    s.zip as survey_zip,
    c.county,
    c.county_name,
    c.afact as county_allocation
FROM ne25_raw s
LEFT JOIN geo_zip_to_county c ON s.sq001 = c.zip
WHERE c.afact > 0.5  -- Only keep primary county assignment
ORDER BY s.pid;
```

---

## Derived Geographic Variables

The NE25 pipeline uses crosswalk tables to create **27 geographic variables** from ZIP code (`sq001`).

### Variable Inventory

| Geography | Code Variable | Name Variable | Allocation Factor | Description |
|-----------|---------------|---------------|-------------------|-------------|
| **PUMA** | `puma` | - | `puma_afact` | Public Use Microdata Area (2020) |
| **County** | `county` | `county_name` | `county_afact` | County FIPS code |
| **Census Tract** | `tract` | - | `tract_afact` | Census tract FIPS code |
| **CBSA** | `cbsa` | `cbsa_name` | `cbsa_afact` | Core-Based Statistical Area (metro) |
| **Urban/Rural** | `urban_rural` | - | `urban_rural_afact` | Urban/Rural classification |
| **Urban %** | `urban_pct` | - | - | Percent of ZIP that is urban |
| **School District** | `school_dist` | `school_name` | `school_afact` | School district code |
| **State House** | `sldl` | - | `sldl_afact` | State legislative district (lower) |
| **State Senate** | `sldu` | - | `sldu_afact` | State legislative district (upper) |
| **Congress** | `congress_dist` | - | `congress_afact` | US Congressional district |
| **Native Lands** | `aiannh_code` | `aiannh_name` | `aiannh_afact` | Tribal lands (AIANNH areas) |

**Total:** 27 variables (11 geographies × ~2.5 variables per geography)

### Implementation

Geographic variables are created in `R/transform/ne25_transforms.R` (lines 545-790):

```r
# Example: County assignment
source("R/utils/query_geo_crosswalk.R")

# Get county crosswalk
county_crosswalk <- query_geo_crosswalk("geo_zip_to_county")

# Join with survey data
dat <- dat %>%
  dplyr::left_join(
    county_crosswalk,
    by = c("sq001" = "zip")
  )

# For ZIP codes spanning multiple counties, create semicolon-separated list
dat <- dat %>%
  dplyr::group_by(pid) %>%
  dplyr::summarise(
    county = paste(county, collapse = ";"),
    county_name = paste(county_name, collapse = ";"),
    county_afact = paste(afact, collapse = ";")
  )
```

---

## Data Format and Structure

### Semicolon-Separated Values

**All geographic variables use semicolon-separated format** to preserve multiple assignments.

**Why?** ZIP codes often span multiple geographic units:
- **68001** spans Douglas County (75%) and Sarpy County (25%)
- **68022** spans 3 school districts

**Format:**
```
county: "31055;31153"
county_name: "Douglas County;Sarpy County"
county_afact: "0.75;0.25"
```

**Parsing in R:**
```r
# Split semicolon-separated values
library(stringr)

dat <- dat %>%
  dplyr::mutate(
    # Extract primary county (first in list)
    primary_county = stringr::str_extract(county, "^[^;]+"),

    # Extract all counties as list
    all_counties = stringr::str_split(county, ";"),

    # Extract primary allocation factor
    primary_afact = as.numeric(stringr::str_extract(county_afact, "^[^;]+"))
  )
```

**Parsing in Python:**
```python
import pandas as pd

# Split semicolon-separated values
df['counties_list'] = df['county'].str.split(';')
df['primary_county'] = df['county'].str.split(';').str[0]
df['primary_afact'] = df['county_afact'].str.split(';').str[0].astype(float)
```

### Allocation Factor Usage

**Use allocation factors to:**
- **Weight calculations:** Multiply counts by afact for accurate aggregation
- **Determine primary geography:** Select geography with max(afact)
- **Distribute population:** Allocate ZIP-level estimates to geographies

**Example: Aggregate ZIP-level counts to counties**
```r
# Survey data with counts by ZIP
zip_counts <- data.frame(
  zip = c("68001", "68022"),
  count = c(100, 50)
)

# Join with county crosswalk
zip_county <- zip_counts %>%
  dplyr::left_join(county_crosswalk, by = "zip")

# Weighted aggregation to county
county_counts <- zip_county %>%
  dplyr::mutate(weighted_count = count * afact) %>%
  dplyr::group_by(county, county_name) %>%
  dplyr::summarise(total_count = sum(weighted_count))

print(county_counts)
# Douglas County: 75 (100 * 0.75 from ZIP 68001)
# Sarpy County: 25 (100 * 0.25 from ZIP 68001)
# Washington County: 50 (50 * 1.0 from ZIP 68022)
```

---

## Use Cases

### Use Case 1: County-Level Aggregation

**Goal:** Aggregate survey responses to county level for reporting.

```r
source("R/utils/query_geo_crosswalk.R")

# Get county crosswalk
county_crosswalk <- query_geo_crosswalk("geo_zip_to_county")

# Load survey data
survey_data <- arrow::read_feather("ne25_transformed.feather")

# Join and aggregate
county_summary <- survey_data %>%
  dplyr::left_join(county_crosswalk, by = c("sq001" = "zip")) %>%
  # Use only primary county assignment (highest afact)
  dplyr::group_by(sq001) %>%
  dplyr::filter(afact == max(afact)) %>%
  dplyr::ungroup() %>%
  # Aggregate to county
  dplyr::group_by(county, county_name) %>%
  dplyr::summarise(
    n = n(),
    mean_age = mean(years_old, na.rm = TRUE),
    phq2_positive_pct = mean(phq2_positive, na.rm = TRUE) * 100
  )

print(county_summary)
```

### Use Case 2: Legislative District Analysis

**Goal:** Identify which state legislative districts are represented in sample.

```sql
-- Get state legislative district distribution
SELECT
    sldl as district,
    COUNT(*) as respondents,
    ROUND(AVG(CAST(phq2_positive AS FLOAT)) * 100, 1) as phq2_positive_pct
FROM ne25_transformed
WHERE sldl IS NOT NULL
GROUP BY sldl
ORDER BY respondents DESC
LIMIT 10;
```

### Use Case 3: Rural/Urban Comparison

**Goal:** Compare outcomes between rural and urban respondents.

```r
# Join with urban/rural crosswalk
urban_rural <- query_geo_crosswalk("geo_zip_to_urban_rural")

survey_data <- survey_data %>%
  dplyr::left_join(urban_rural, by = c("sq001" = "zip")) %>%
  dplyr::mutate(
    # Classify as urban if >50% urban
    urban_classification = dplyr::if_else(urban_pct > 50, "Urban", "Rural")
  )

# Compare outcomes
survey_data %>%
  dplyr::group_by(urban_classification) %>%
  dplyr::summarise(
    n = n(),
    phq2_mean = mean(phq2_total, na.rm = TRUE),
    ace_mean = mean(ace_total, na.rm = TRUE)
  )
```

### Use Case 4: School District Reporting

**Goal:** Generate reports for each school district.

```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Get survey data with school districts
result = db.execute_query("""
    SELECT
        s.school_dist,
        s.school_name,
        COUNT(*) as n,
        AVG(CAST(phq2_positive AS FLOAT)) * 100 as phq2_positive_pct,
        AVG(age) as mean_age
    FROM ne25_transformed t
    WHERE school_dist IS NOT NULL
    GROUP BY school_dist, school_name
    HAVING COUNT(*) >= 10  -- Only districts with 10+ respondents
    ORDER BY n DESC
""")

for row in result:
    print(f"{row[1]}: {row[2]} respondents, {row[3]:.1f}% PHQ-2 positive")
```

---

## Troubleshooting

### Issue: Missing Geographic Variables

**Symptom:** Geographic variables (county, puma, etc.) are NULL or missing.

**Causes:**
1. ZIP code is invalid or missing in survey data
2. ZIP code not in crosswalk tables (e.g., PO boxes, recent ZIP codes)
3. Crosswalk tables not loaded

**Solutions:**
```r
# Check for missing ZIPs
survey_data %>%
  dplyr::filter(is.na(county)) %>%
  dplyr::count(sq001)

# Manually check crosswalk
county_crosswalk <- query_geo_crosswalk("geo_zip_to_county")
county_crosswalk %>%
  dplyr::filter(zip == "68001")

# Reload crosswalk tables if empty
# python pipelines/python/load_geo_crosswalks_sql.py
```

### Issue: Multiple Geography Assignments

**Symptom:** Geographic variables contain semicolon-separated values.

**This is expected!** ZIP codes spanning multiple geographies.

**Solution:** Extract primary geography using allocation factor:
```r
# Extract primary county (highest afact)
dat <- dat %>%
  dplyr::mutate(
    primary_county = stringr::str_split(county, ";")[[1]][1],
    primary_afact = as.numeric(stringr::str_split(county_afact, ";")[[1]][1])
  )
```

### Issue: Crosswalk Data Outdated

**Symptom:** Congressional districts, legislative districts, or census geographies don't match current boundaries.

**Solution:** Update crosswalk source files and reload:

1. Download updated crosswalks from Census Bureau / state sources
2. Place in `data/geographic_crosswalks/`
3. Reload: `python pipelines/python/load_geo_crosswalks_sql.py`

### Issue: Performance Slow

**Symptom:** Geographic joins are slow.

**Solutions:**
```sql
-- Create index on ZIP column (if not exists)
CREATE INDEX idx_geo_zip_county_zip ON geo_zip_to_county(zip);

-- Use primary geography only (reduces join size)
SELECT ... FROM ne25_raw
LEFT JOIN (
    SELECT zip, county, county_name, MAX(afact) as afact
    FROM geo_zip_to_county
    GROUP BY zip
) c ON sq001 = c.zip;
```

---

## Source Files

### Data Loader
**File:** `pipelines/python/load_geo_crosswalks_sql.py`
**Purpose:** Load CSV crosswalk files into DuckDB tables

### Query Utilities
**Python:** `python/db/query_geo_crosswalk.py`
**R:** `R/utils/query_geo_crosswalk.R`
**Purpose:** Query crosswalk tables from Python or R

### Geographic Transformation
**File:** `R/transform/ne25_transforms.R` (lines 545-790)
**Purpose:** Create 27 geographic variables from ZIP codes

### Configuration
**File:** `config/derived_variables.yaml`
**Purpose:** Document geographic variable definitions

---

## Related Documentation

- **Derived Variables Guide:** [MISSING_DATA_GUIDE.md](MISSING_DATA_GUIDE.md) - General derived variable standards
- **Directory Structure:** [../DIRECTORY_STRUCTURE.md](../DIRECTORY_STRUCTURE.md) - Location of crosswalk files
- **Coding Standards:** [CODING_STANDARDS.md](CODING_STANDARDS.md) - R and Python coding patterns

---

*Last Updated: October 2025*

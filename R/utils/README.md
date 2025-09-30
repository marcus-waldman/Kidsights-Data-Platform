# Geographic Crosswalk Query Utilities

## Overview

Safe database access for geographic crosswalk reference tables using the hybrid Python→Feather→R pattern to avoid R DuckDB segmentation faults.

These utilities enable the NE25 pipeline to query 10 geographic reference tables (126K+ rows) from DuckDB without direct R-to-database connections that historically caused 50%+ failure rates.

## Functions

### `query_geo_crosswalk(table_name, temp_dir = NULL, python_path = "python")`

Query a geographic crosswalk table from DuckDB and return as a data frame.

**Parameters:**
- `table_name` (required) - Name of crosswalk table (see Available Tables below)
- `temp_dir` (optional) - Directory for temporary Feather files (default: `tempdir()`)
- `python_path` (optional) - Path to Python executable (default: "python")

**Returns:**
Data frame with crosswalk data, or NULL on error

**Example:**
```r
source("R/utils/query_geo_crosswalk.R")

# Query PUMA crosswalk
puma_xwalk <- query_geo_crosswalk("geo_zip_to_puma")
head(puma_xwalk)

# Query county crosswalk
county_xwalk <- query_geo_crosswalk("geo_zip_to_county")
```

**How It Works:**
1. R function spawns Python subprocess
2. Python queries DuckDB table (read-only)
3. Python writes results to temporary Feather file
4. R reads Feather file with perfect data type preservation
5. Temporary file is automatically cleaned up

This approach provides 100% reliability vs. direct R→DuckDB connections.

### `get_geo_crosswalk_tables()`

Returns a character vector of all available geographic crosswalk table names.

**Parameters:** None

**Returns:**
Character vector of table names

**Example:**
```r
source("R/utils/query_geo_crosswalk.R")

# List all available tables
tables <- get_geo_crosswalk_tables()
print(tables)
# [1] "geo_zip_to_puma"             "geo_zip_to_county"
# [3] "geo_zip_to_tract"            "geo_zip_to_cbsa"
# [5] "geo_zip_to_urban_rural"      "geo_zip_to_school_dist"
# [7] "geo_zip_to_state_leg_lower"  "geo_zip_to_state_leg_upper"
# [9] "geo_zip_to_congress"         "geo_zip_to_native_lands"
```

## Available Tables

| Table Name | Description | Source Year | Rows (NE) |
|------------|-------------|-------------|-----------|
| `geo_zip_to_puma` | Public Use Microdata Areas | 2020 Census | 708 |
| `geo_zip_to_county` | County FIPS codes | 2020 Census | 975 |
| `geo_zip_to_tract` | Census tract FIPS codes | 2020 Census | 1,711 |
| `geo_zip_to_cbsa` | Core-Based Statistical Areas | 2020 Census | 40,769 (USA) |
| `geo_zip_to_urban_rural` | Urban/Rural classification | 2022 Census | 42,870 (USA) |
| `geo_zip_to_school_dist` | School districts | 2020 | 1,673 |
| `geo_zip_to_state_leg_lower` | State house districts | 2024 | 591 |
| `geo_zip_to_state_leg_upper` | State senate districts | 2024 | 902 |
| `geo_zip_to_congress` | US Congressional districts | 119th Congress | 647 |
| `geo_zip_to_native_lands` | AIANNH tribal areas | 2021 | 35,026 (USA) |

**Note:** CBSA, Urban/Rural, and Native Lands tables contain all USA data because they lack state identifiers. Filtering happens during R transformation by matching to participant ZIP codes.

## Reloading Data

To refresh crosswalk tables from source CSV files:

```bash
# Reload all crosswalk tables (Nebraska only, where applicable)
python pipelines/python/load_geo_crosswalks_sql.py --state NE

# Reload with different state
python pipelines/python/load_geo_crosswalks_sql.py --state IA

# Reload all USA data
python pipelines/python/load_geo_crosswalks_sql.py --state ""
```

## Column Structure

Each crosswalk table follows a consistent pattern:

**Common columns:**
- `zcta` - ZIP Code Tabulation Area (5-digit string)
- `afact` - Allocation factor (proportion of ZIP population in this geography, 0-1)
- `pop20` - Total population in this ZCTA-to-geography match (2020 Census)

**Geography-specific columns:**
- PUMA: `puma22` (code), `PUMA22name` (name), `state`, `stab`
- County: `county` (FIPS), `CountyName` (name)
- Tract: `tract` (tract portion), `county` (county FIPS)
- CBSA: `cbsa20` (code), `CBSAName20` (name)
- Urban/Rural: `ur` (U or R code)
- School: `sdbest20` (code), `bschlnm20` (name), `state`, `stab`
- State Leg Lower: `sldl24` (district code), `state`, `stab`
- State Leg Upper: `sldu24` (district code), `state`, `stab`
- Congress: `cd119` (district code), `state`, `stab`
- Native Lands: `aiannh` (code), `aiannhName` (name)

## Usage in Transformations

The geographic transformation in `R/transform/ne25_transforms.R` uses these utilities to create 27 derived variables from participant ZIP codes:

```r
# Example pattern from ne25_transforms.R
source("R/utils/query_geo_crosswalk.R")

# Query crosswalk
zip_puma_raw <- query_geo_crosswalk("geo_zip_to_puma")

# Process into semicolon-separated format
zip_puma_crosswalk <- zip_puma_raw %>%
  dplyr::select(zcta, puma22, afact) %>%
  dplyr::rename(zip = zcta, puma = puma22, puma_afact = afact) %>%
  dplyr::group_by(zip) %>%
  dplyr::arrange(dplyr::desc(puma_afact), .by_group = TRUE) %>%
  dplyr::summarise(
    puma = paste(puma, collapse = "; "),
    puma_afact = paste(puma_afact, collapse = "; "),
    .groups = "drop"
  )

# Join to participant data
geographic_df <- participant_data %>%
  dplyr::left_join(zip_puma_crosswalk, by = c("zip_clean" = "zip"))
```

## Troubleshooting

**Error: "Python script not found"**
- Ensure you're running from the project root directory
- Check that `python/db/query_geo_crosswalk.py` exists

**Error: "Failed to query [table] from database"**
- Verify database exists: `data/duckdb/kidsights_local.duckdb`
- Reload crosswalk tables: `python pipelines/python/load_geo_crosswalks_sql.py`

**Error: "Table [name] is empty"**
- Check if table was loaded with correct state filter
- Re-run load script with appropriate `--state` parameter

## Related Files

- **Python query script:** `python/db/query_geo_crosswalk.py`
- **Python loader script:** `pipelines/python/load_geo_crosswalks_sql.py`
- **R transformation:** `R/transform/ne25_transforms.R:545-790`
- **Configuration:** `config/derived_variables.yaml`
- **Documentation:** `CLAUDE.md` → "Geographic Crosswalk System"

## Technical Notes

### Why Not Direct R→DuckDB?

The R `duckdb` package causes segmentation faults in ~50% of pipeline runs on Windows systems. The hybrid Python→Feather→R approach:
- ✅ 100% reliability (0 segfaults in production)
- ✅ Perfect data type preservation (factors, numerics)
- ✅ Rich error messages (no cryptic seg faults)
- ❌ ~200ms overhead per query (acceptable for daily pipeline)

### Feather Format Benefits

Apache Feather (arrow format) provides:
- 3x faster I/O vs CSV
- Perfect R factor ↔ pandas category preservation
- Identical data types between R and Python
- Binary format (no character encoding issues)

### Allocation Factors

ZIP codes often span multiple geographic areas. The `afact` (allocation factor) indicates what proportion of the ZIP's population falls into each geography:

```
ZIP 68007 (Bennington, NE):
  PUMA 00901: afact = 0.9866 (98.66% of population)
  PUMA 00701: afact = 0.0134 (1.34% of population)
```

Our semicolon-separated format preserves all assignments ordered by decreasing `afact`.

---

**Last Updated:** September 2025
**Version:** 1.0.0

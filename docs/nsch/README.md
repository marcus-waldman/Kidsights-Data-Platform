# NSCH Pipeline Documentation

**National Survey of Children's Health (NSCH) Data Integration Pipeline**

Version 1.0 | Last Updated: October 2025

---

## Overview

The NSCH Pipeline is a comprehensive data integration system that extracts, validates, and loads National Survey of Children's Health (NSCH) data from SPSS files into a DuckDB database for analysis. The pipeline processes 8 years of NSCH data (2016-2023) with automated validation, metadata extraction, and quality assurance.

### What is NSCH?

The National Survey of Children's Health (NSCH) is an annual survey conducted by the U.S. Census Bureau that provides rich data on the health and well-being of children ages 0-17 in the United States. The survey covers:
- Physical and mental health
- Healthcare access and quality
- Family characteristics
- Neighborhood and school environments
- Adverse childhood experiences (ACEs)
- Social and emotional development

### Key Features

- **Multi-Year Support**: Processes NSCH data from 2016-2023 (8 years)
- **Automated Pipeline**: Single command processes SPSS → Feather → R validation → Database
- **Metadata Extraction**: Automatically extracts variable definitions and value labels from SPSS
- **Data Quality**: Comprehensive validation with 7 checks per year
- **Efficient Storage**: Uses Apache Arrow Feather format for fast I/O and DuckDB for columnar storage
- **Batch Processing**: Process single years or all years at once
- **Round-Trip Verification**: Ensures perfect data integrity with 6-point validation

### Current Status

**✅ Production Ready**

- **Data Loaded**: 284,496 records across 7 years (2017-2023)
- **Variables**: 6,867 variable definitions
- **Value Labels**: 36,164 value label mappings
- **Database Size**: 0.27 MB (efficient columnar storage)
- **Processing Time**: ~2 minutes for 6 years

**Known Limitations:**
- 2016 data table exists but is empty due to schema differences (documented, will be addressed in harmonization phase)

---

## Quick Start

### Prerequisites

**Python Packages:**
```bash
pip install pandas pyreadstat structlog duckdb
```

**R Packages:**
```r
install.packages(c("haven", "arrow", "dplyr", "tidyr"))
```

**Required Files:**
- SPSS files in `data/nsch/spss/` directory
- See [pipeline_usage.md](pipeline_usage.md) for detailed setup

### Process a Single Year

```bash
# Step 1: Convert SPSS to Feather
python pipelines/python/nsch/load_nsch_spss.py --year 2023

# Step 2: Validate with R
Rscript pipelines/orchestration/run_nsch_pipeline.R --year 2023

# Step 3: Load metadata to database
python pipelines/python/nsch/load_nsch_metadata.py --year 2023

# Step 4: Insert raw data to database
python pipelines/python/nsch/insert_nsch_database.py --year 2023
```

### Process All Years (Batch)

```bash
# Process all years 2016-2023
python scripts/nsch/process_all_years.py --years all

# Process specific years
python scripts/nsch/process_all_years.py --years 2020-2023

# Process selected years
python scripts/nsch/process_all_years.py --years 2016,2020,2023
```

### Query the Data

```python
import duckdb

conn = duckdb.connect('data/duckdb/kidsights_local.duckdb')

# Get sample records from 2023
df = conn.execute("""
    SELECT HHID, YEAR, SC_AGE_YEARS, SC_SEX
    FROM nsch_2023_raw
    LIMIT 10
""").fetchdf()

print(df)
conn.close()
```

See [example_queries.md](example_queries.md) for more query examples.

---

## Architecture

### Pipeline Flow

```
SPSS Files (2016-2023)
    ↓
[STEP 1] Python: SPSS → Feather Conversion
    ↓
data/nsch/{year}/raw.feather
    ↓
[STEP 2] R: Validation & Quality Checks
    ↓
data/nsch/{year}/processed.feather
    ↓
[STEP 3] Python: Metadata Loading
    ↓
DuckDB: nsch_variables, nsch_value_labels
    ↓
[STEP 4] Python: Raw Data Insertion
    ↓
DuckDB: nsch_{year}_raw tables
```

### Technology Stack

- **Python 3.13+**: SPSS loading, database operations
- **R 4.5.1**: Data validation, quality assurance
- **Apache Arrow Feather**: Cross-language data interchange format
- **DuckDB**: Analytical database (columnar storage)
- **pyreadstat**: SPSS file reading
- **haven (R)**: SPSS metadata extraction

### Directory Structure

```
Kidsights-Data-Platform/
├── pipelines/
│   ├── python/nsch/
│   │   ├── load_nsch_spss.py       # SPSS → Feather conversion
│   │   ├── load_nsch_metadata.py   # Metadata loading
│   │   └── insert_nsch_database.py # Raw data insertion
│   └── orchestration/
│       └── run_nsch_pipeline.R     # R validation script
├── scripts/nsch/
│   ├── process_all_years.py        # Batch processing
│   ├── generate_db_summary.py      # Database summary
│   └── test_db_roundtrip.py        # Round-trip validation
├── python/nsch/
│   ├── spss_loader.py              # SPSS loading utilities
│   ├── data_loader.py              # Feather operations
│   └── config_manager.py           # Configuration management
├── R/load/nsch/
│   └── load_nsch_data.R            # R data loading functions
├── R/utils/nsch/
│   └── validate_nsch_raw.R         # R validation utilities
├── config/sources/nsch/
│   ├── nsch-template.yaml          # Configuration template
│   └── database_schema.sql         # Database schema
├── data/nsch/
│   ├── spss/                       # SPSS source files
│   └── {year}/                     # Year-specific data
│       ├── raw.feather
│       ├── processed.feather
│       ├── metadata.json
│       └── validation_report.txt
└── docs/nsch/
    ├── README.md                   # This file
    ├── pipeline_usage.md           # Detailed usage guide
    ├── database_schema.md          # Database documentation
    ├── example_queries.md          # Query examples
    ├── troubleshooting.md          # Common issues
    └── testing_guide.md            # Testing procedures
```

---

## Use Cases

### 1. National Benchmarking
Compare state or local child health data against NSCH national estimates.

**Example:** Compare Nebraska ACE prevalence to NSCH national rates.

### 2. Trend Analysis
Analyze changes in child health indicators over time (2017-2023).

**Example:** Track changes in mental health service utilization rates.

### 3. Cross-Year Harmonization
Create standardized variables that work across multiple survey years.

**Example:** Map education categories across years with different response options.

### 4. Multi-Domain Analysis
Examine relationships between health, education, family, and neighborhood factors.

**Example:** Analyze associations between ACEs, mental health, and healthcare access.

### 5. Sample Weight Application
Generate population-level estimates using NSCH sampling weights.

**Example:** Calculate weighted prevalence rates for specific conditions.

---

## Database Structure

The NSCH database contains 11 tables organized into two categories:

### Data Tables (8 tables)

- `nsch_2016_raw` - 2016 survey data (0 records - schema incompatibility)
- `nsch_2017_raw` - 2017 survey data (21,599 records)
- `nsch_2018_raw` - 2018 survey data (30,530 records)
- `nsch_2019_raw` - 2019 survey data (29,433 records)
- `nsch_2020_raw` - 2020 survey data (42,777 records)
- `nsch_2021_raw` - 2021 survey data (50,892 records)
- `nsch_2022_raw` - 2022 survey data (54,103 records)
- `nsch_2023_raw` - 2023 survey data (55,162 records)

### Metadata Tables (3 tables)

- `nsch_variables` - Variable definitions (6,867 records)
- `nsch_value_labels` - Value label mappings (36,164 records)
- `nsch_crosswalk` - Variable name changes across years (0 records - future use)

**Total Records:** 284,496 across all years

See [database_schema.md](database_schema.md) for detailed schema documentation.

---

## Key Concepts

### Year-Specific Tables

Each NSCH year has its own table (`nsch_{year}_raw`) because:
- Survey questionnaires evolve over time
- Variable names change across years
- Response options differ between years
- New variables are added/removed

**Future Harmonization:** A separate harmonization phase will create standardized cross-year variables.

### Common Variables

352 variables exist across all 7 years with data, including:
- **Demographics:** HHID, YEAR, SC_AGE_YEARS, SC_SEX
- **Parent Info:** A1_AGE, A1_SEX, A1_RELATION, A1_MARITAL
- **Health Status:** K2Q01 (general health), K2Q30A-K2Q33A (conditions)
- **Healthcare Access:** K4Q20 (insurance), K5Q10 (checkup)
- **Family:** FAMILY_R, TOTPEOPLE, FPL_I1 (poverty level)

### Data Types

All numeric variables are stored as `DOUBLE` (floating-point) in DuckDB:
- Preserves SPSS numeric precision
- Handles missing values (NaN)
- Maintains value label codes
- Allows efficient aggregation

---

## Data Quality

### Validation Checks

Each year undergoes 7 validation checks:

1. **HHID Present**: Unique household identifier exists
2. **Record Count**: Expected number of records loaded
3. **Column Count**: Matches SPSS metadata
4. **Empty Columns**: No completely empty variables
5. **Data Types**: All variables have valid types
6. **HHID Missing**: No missing household IDs
7. **Year Variable**: YEAR variable present and correct

See [testing_guide.md](testing_guide.md) for detailed validation procedures.

### Round-Trip Verification

6-point validation ensures perfect data integrity:

1. Row count matching
2. Column count matching
3. Column names matching
4. Sample value comparison (10 random rows)
5. Null count verification (first 10 columns)
6. Summary statistics matching (first 5 numeric columns)

**Result:** All checks pass - perfect data integrity confirmed.

---

## Performance

### Processing Speed

- **Single Year:** 15-25 seconds per year
- **Batch (6 years):** ~2 minutes total
- **Database Queries:** <1 second for most queries

### Storage Efficiency

- **Feather Files:** ~50-100 MB per year (uncompressed, fast I/O)
- **Database:** 0.27 MB total (columnar compression)
- **Compression Ratio:** ~200:1 (Feather → DuckDB)

### Scalability

- Processes years independently (no dependencies)
- Chunked insertion (10,000 rows per chunk)
- Efficient memory usage (<2 GB RAM)
- Can process on standard laptop

---

## Documentation Index

### Getting Started
- **[README.md](README.md)** - This file (overview, quick start)
- **[pipeline_usage.md](pipeline_usage.md)** - Detailed usage instructions
- **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)** - Development roadmap

### Reference
- **[database_schema.md](database_schema.md)** - Database tables and schemas
- **[variables_reference.md](variables_reference.md)** - Auto-generated variable reference
- **[database_summary.txt](database_summary.txt)** - Current database status

### How-To Guides
- **[example_queries.md](example_queries.md)** - Query examples and patterns
- **[troubleshooting.md](troubleshooting.md)** - Common issues and solutions
- **[testing_guide.md](testing_guide.md)** - Testing procedures

### Project Summary
- **[NSCH_PIPELINE_SUMMARY.md](NSCH_PIPELINE_SUMMARY.md)** - Executive summary and metrics

---

## Next Steps

### Immediate Use
1. Read [pipeline_usage.md](pipeline_usage.md) for detailed setup
2. Review [example_queries.md](example_queries.md) for query patterns
3. Check [database_summary.txt](database_summary.txt) for current data status

### Future Development (Planned)
- **Phase 8: Harmonization** - Create standardized variables across years
- **Phase 9: Derived Variables** - Calculate composite scores and indicators
- **Phase 10: Analysis Tables** - Create analysis-ready datasets with weights

---

## Support

### Issues and Questions

- Check [troubleshooting.md](troubleshooting.md) for common problems
- Review [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for development history
- See main [CLAUDE.md](../../CLAUDE.md) for overall project context

### Contributing

This pipeline is part of the Kidsights Data Platform. See main project documentation for development guidelines and coding standards.

---

**Last Updated:** October 3, 2025
**Pipeline Version:** 1.0
**Status:** Production Ready (7/8 years loaded)

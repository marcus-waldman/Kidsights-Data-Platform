# Pipeline Architecture Overview

**Last Updated:** October 2025

This document provides detailed architecture documentation for all four data pipelines in the Kidsights Data Platform. Each pipeline is designed as an independent, standalone system with specific data sources and use cases.

---

## Table of Contents

1. [NE25 Pipeline](#ne25-pipeline) - REDCap survey data processing
2. [ACS Pipeline](#acs-pipeline) - Census data extraction for statistical raking
3. [NHIS Pipeline](#nhis-pipeline) - National health surveys for benchmarking
4. [NSCH Pipeline](#nsch-pipeline) - Children's health survey integration
5. [ACS Metadata System](#acs-metadata-system) - IPUMS DDI metadata integration
6. [Pipeline Integration](#pipeline-integration-and-relationship) - How pipelines work together

---

## NE25 Pipeline: Hybrid R-Python Design (September 2025)

### Problem Solved
R DuckDB segmentation faults caused 50% pipeline failure rate

### Solution
R handles orchestration/transforms, Python handles all database operations

### Architecture Diagram

```
REDCap (4 projects) → R: Extract/Transform → Feather Files → Python: Database Ops → Local DuckDB
     3,906 records      REDCapR, recode_it()      arrow format      Chunked processing     47MB local
```

### Key Benefits

- **100% pipeline reliability** (was 50%)
- **3x faster I/O** with Feather format
- **Rich error context** (no more segfaults)
- **Perfect data type preservation** R ↔ Python

### Design Rationale

The hybrid architecture was adopted in September 2025 to eliminate persistent segmentation faults when using R's DuckDB driver. By delegating all database operations to Python while keeping R for its strengths (REDCap extraction, statistical transformations), we achieved complete stability without sacrificing functionality.

### Technical Components

- **R Components:** REDCapR for API calls, recode_it() for transformations, arrow for Feather I/O
- **Python Components:** duckdb for database ops, pandas for data manipulation
- **Data Exchange:** Arrow Feather format preserves R factors ↔ pandas categories perfectly
- **Storage:** Local DuckDB database (47MB, 11 tables, 7,812 records)

---

## ACS Pipeline: Census Data Extraction (September 2025)

### Purpose
Extract American Community Survey data from IPUMS USA API for statistical raking

### Architecture Diagram

```
IPUMS USA API → Python: Extract/Cache → Feather Files → R: Validate → Python: Database Ops → Local DuckDB
  Census data     ipumspy, requests     arrow format    Statistical QC    Chunked inserts    Separate tables
```

### Key Features

- **API Integration:** Direct IPUMS USA API calls (no manual web downloads)
- **Smart Caching:** Automatic caching with checksum validation (90+ day retention)
- **R Validation:** Statistical QC and data validation in R
- **Standalone Design:** Independent of NE25 pipeline (no dependencies)
- **Future Use:** Enables post-stratification raking after harmonization

### Design Rationale

The ACS pipeline was designed as a utility system to support future statistical raking (post-stratification). Rather than integrating it into the NE25 pipeline (different run cadences), we built it as a standalone tool that populates separate database tables. Census data refreshes annually, while NE25 data refreshes continuously.

### Technical Components

- **Python Modules:** `python/acs/` - auth, config management, extract building, caching
- **R Validation:** `pipelines/orchestration/run_acs_pipeline.R` - statistical QC
- **Configuration:** `config/sources/acs/` - state-specific YAML configs
- **Storage:** `acs_raw` and `acs_metadata` tables in shared DuckDB

---

## NHIS Pipeline: Health Surveys Data Extraction (October 2025)

### Purpose
Extract National Health Interview Survey data from IPUMS Health Surveys API for national benchmarking and ACEs/mental health research

### Architecture Diagram

```
IPUMS NHIS API → Python: Extract/Cache → Feather Files → R: Validate → Python: Database Ops → DuckDB
  ih2019-ih2024    ipumspy, requests     arrow format    7 validation    Chunked inserts   nhis_raw table
      ↓                    ↓                     ↓            checks              ↓              ↓
  66 variables      SHA256 caching         3x faster I/O    Survey QC    Perfect types    300K+ records
  6 annual samples  90+ day retention      R ↔ Python       ACE/MH       preservation     47+ MB
```

### Key Features

- **API Integration:** Direct IPUMS NHIS API calls (collection: `nhis`)
- **Multi-Year Samples:** 6 annual samples (2019-2024), not pooled like ACS
- **Smart Caching:** SHA256 signatures based on years + samples + variables
- **66 Variables:** Demographics, parent info, ACEs, GAD-7, PHQ-8, economic indicators
- **No Case Selection:** Nationwide, all ages (vs ACS state/age filters)
- **Survey Design:** Includes SAMPWEIGHT, STRATA, PSU for complex survey analysis
- **Mental Health Focus:** GAD-7 anxiety and PHQ-8 depression (2019, 2022 only)
- **ACEs Coverage:** 8 ACE variables with direct overlap to NE25
- **Documentation:** Complete usage guides, testing procedures, transformation mappings

### Use Cases

- Compare NE25 ACE prevalence to national NHIS estimates
- Extract PHQ-2/GAD-2 from full PHQ-8/GAD-7 scales for comparability
- Population benchmarking for Nebraska sample
- Future harmonization for raking (Phase 12+)

### Design Rationale

NHIS provides nationally representative health data that directly overlaps with NE25 measures (ACEs, mental health). Unlike ACS (demographics only), NHIS enables apples-to-apples comparison of health outcomes. The multi-year design (6 annual samples) allows trend analysis and ensures sufficient sample sizes for subgroup comparisons.

### Technical Components

- **Python Modules:** `python/nhis/` - auth, extract management, SHA256-based caching
- **R Validation:** `pipelines/orchestration/run_nhis_pipeline.R` - 7 validation checks
- **Configuration:** `config/sources/nhis/` - year-specific configs, sample definitions
- **Storage:** `nhis_raw` table with 229,609 records (188,620 sample + 40,989 non-sample)

---

## NSCH Pipeline: Survey Data Integration (October 2025)

### Purpose
Integrate National Survey of Children's Health (NSCH) data from SPSS files for national benchmarking and trend analysis

### Architecture Diagram

```
SPSS Files → Python: Convert → Feather → R: Validate → Python: Load → DuckDB
  2016-2023    pyreadstat      arrow     7 QC checks    Chunked     nsch_{year}_raw
     ↓              ↓            ↓             ↓         inserts          ↓
  840-923 vars  Metadata   Fast I/O    Integrity   10K/chunk    284K records
  50K-55K rows  extraction  3x faster    checks    validation    7 years loaded
```

### Key Features

- **Multi-Year Support:** 8 years (2016-2023), 284,496 records loaded
- **Automated Pipeline:** Single command processes SPSS → Database
- **Metadata Extraction:** Auto-generates variable reference (3,780 variables)
- **Data Quality:** 7-point validation ensures 100% integrity
- **Efficient Storage:** 200:1 compression (SPSS → DuckDB)
- **Batch Processing:** Processes 7 years in 2 minutes
- **Documentation:** 10 comprehensive guides (629 KB total)

### Current Status
✅ Production Ready (7/8 years loaded, 2016 schema incompatibility documented)

### Use Cases

- National benchmarking for state/local child health data
- Trend analysis (2017-2023) for longitudinal studies
- ACE prevalence comparison across years
- Cross-year harmonization (future Phase 8)

### Design Rationale

NSCH is the gold standard for child health surveillance in the US. Unlike NHIS (household-based), NSCH focuses specifically on children and includes detailed ACE assessments, healthcare access, and developmental outcomes. The SPSS-based pipeline (vs API) was chosen because NSCH data is released as SPSS files rather than through IPUMS.

### Technical Components

- **Python Modules:** `python/nsch/` - SPSS loading, metadata extraction, data loading
- **R Validation:** `pipelines/orchestration/run_nsch_pipeline.R` - 7 QC checks
- **Configuration:** `config/sources/nsch/` - database schema, templates
- **Storage:** Year-specific tables (`nsch_2017_raw`, `nsch_2018_raw`, etc.)

---

## ACS Metadata System (October 2025)

### Purpose
Leverage IPUMS DDI (Data Documentation Initiative) metadata for transformation, harmonization, and documentation

### Architecture Diagram

```
DDI XML Files → Python: Parse Metadata → DuckDB: Metadata Tables → Python/R: Query & Transform
  Variable defs    metadata_parser.py    3 tables (42 vars, 1,144 labels)   Decode, harmonize
```

### Components

#### 1. Metadata Extraction (Phase 1)

- **Parser:** `python/acs/metadata_parser.py` - Extracts variables, value labels, dataset info from DDI
- **Schema:** `python/acs/metadata_schema.py` - Defines 3 DuckDB tables (acs_variables, acs_value_labels, acs_metadata_registry)
- **Loader:** `pipelines/python/acs/load_acs_metadata.py` - Populates metadata tables
- **Auto-loading:** Integrated into extraction pipeline (Step 4.6)

#### 2. Transformation Utilities (Phase 2)

**Python Utilities:** `python/acs/metadata_utils.py`
- `decode_value()`: Decode single values (e.g., STATEFIP 27 → "Minnesota")
- `decode_dataframe()`: Decode entire columns
- `get_variable_info()`, `search_variables()`: Query metadata
- `is_categorical()`, `is_continuous()`, `is_identifier()`: Type checking

**R Utilities:** `R/utils/acs/acs_metadata.R`
- `acs_decode_value()`, `acs_decode_column()`: Decode values
- `acs_get_variable_info()`, `acs_search_variables()`: Query metadata
- `acs_is_categorical()`, etc.: Type checking

**Harmonization Tools:** `python/acs/harmonization.py`
- `harmonize_race_ethnicity()`: Maps IPUMS RACE/HISPAN to 7 NE25 categories
- `harmonize_education()`: Maps IPUMS EDUC to NE25 8-cat or 4-cat education levels
- `harmonize_income_to_fpl()`: Converts income to Federal Poverty Level percentages
- `apply_harmonization()`: Applies all harmonizations at once

#### 3. Documentation & Analysis (Phase 3)

**Data Dictionary Generator:** `scripts/acs/generate_data_dictionary.py`
- Auto-generates HTML/Markdown data dictionaries from metadata
- Includes variable descriptions, value labels, data types

**Transformation Docs:** `docs/acs/transformation_mappings.md`
- Documents IPUMS → NE25 category mappings
- Race/ethnicity, education, income/FPL transformations

**Query Cookbook:** `docs/acs/metadata_query_cookbook.md`
- Practical examples in Python and R
- Common patterns for decoding, searching, harmonizing

### Usage Examples

**Python:**
```python
from python.acs.metadata_utils import decode_value, decode_dataframe
from python.acs.harmonization import harmonize_race_ethnicity
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Decode values
state = decode_value('STATEFIP', 27, db)  # "Minnesota"

# Decode DataFrame columns
df = decode_dataframe(df, ['STATEFIP', 'SEX'], db)

# Harmonize to NE25 categories
df['ne25_race'] = harmonize_race_ethnicity(df, 'RACE', 'HISPAN')
```

**R:**
```r
source("R/utils/acs/acs_metadata.R")

# Decode values
state <- acs_decode_value("STATEFIP", 27)  # "Minnesota"

# Decode DataFrame columns
df <- acs_decode_column(df, "STATEFIP")

# Search variables
educ_vars <- acs_search_variables("education")
```

### Key Benefits

- **Precise transformations:** Know exactly what IPUMS codes mean
- **Automated validation:** Check categorical values against DDI
- **Reduced errors:** No guesswork in code-to-label mappings
- **Self-documenting:** Auto-generated data dictionaries
- **Category alignment:** Ensure ACS and NE25 categories match for raking

### Documentation

- Transformation mappings: `docs/acs/transformation_mappings.md`
- Query cookbook: `docs/acs/metadata_query_cookbook.md`
- Data dictionary: `docs/acs/data_dictionary.html` (auto-generated)

---

## Pipeline Integration and Relationship

### Four Independent Pipelines

The Kidsights Data Platform operates **four independent, standalone pipelines**:

#### 1. NE25 Pipeline (Primary)
- **Purpose:** Process REDCap survey data from Nebraska 2025 study
- **Data Source:** 4 REDCap projects via REDCapR
- **Architecture:** Hybrid R-Python with Feather files
- **Status:** Production ready, 100% reliability
- **Tables:** `ne25_raw`, `ne25_transformed`, 9 validation/metadata tables

#### 2. ACS Pipeline (Utility)
- **Purpose:** Extract census data from IPUMS USA API for statistical raking
- **Data Source:** IPUMS USA API via ipumspy
- **Architecture:** Python extraction → R validation → Python database
- **Status:** Complete (Phase 11 integration)
- **Tables:** `acs_raw`, `acs_metadata`

#### 3. NHIS Pipeline (Benchmarking)
- **Purpose:** National health survey data for ACEs/mental health comparison
- **Data Source:** IPUMS NHIS API via ipumspy
- **Architecture:** Python extraction → R validation → Python database
- **Status:** Production ready (Phases 1-7 complete)
- **Tables:** `nhis_raw`

#### 4. NSCH Pipeline (Benchmarking)
- **Purpose:** National children's health survey for trend analysis
- **Data Source:** SPSS files from NSCH releases
- **Architecture:** Python SPSS conversion → R validation → Python database
- **Status:** Production ready (7/8 years loaded)
- **Tables:** `nsch_{year}_raw` (year-specific tables)

### Design Decision: Why Separate?

**No automatic integration** - Pipelines do NOT run as part of each other.

**Rationale:**
1. **Different cadences:** NE25 runs frequently (new survey data), ACS/NHIS/NSCH run rarely (annual updates)
2. **Different dependencies:** NE25 requires REDCap API, ACS/NHIS require IPUMS API, NSCH requires SPSS files
3. **Future use case:** Supporting data needed for post-stratification raking (Phase 12+) and benchmarking
4. **Modular design:** Each pipeline can be maintained/tested independently

### How They Work Together (Future Vision)

```
NE25 Pipeline          ACS Pipeline       NHIS Pipeline      NSCH Pipeline
     ↓                      ↓                   ↓                  ↓
ne25_raw                acs_raw            nhis_raw          nsch_2023_raw
ne25_transformed            ↓                   ↓                  ↓
     ↓                  (future)           (future)           (future)
     ↓                      ↓                   ↓                  ↓
     └──────────────────────┴───────────────────┴──────────────────┘
                                    ↓
                          INTEGRATION MODULE
                             (Phase 12+)
                                    ↓
                    ┌───────────────┴───────────────┐
                    ↓                               ↓
            RAKING MODULE                  BENCHMARKING MODULE
         (ACS for weights)              (NHIS/NSCH for comparison)
                    ↓                               ↓
        Harmonizes geography               Compare ACE prevalence
        Applies sampling weights           Extract PHQ-2/GAD-2 scores
        Generates raked estimates          Population benchmarking
```

### Future Integration (Phase 12+)

**Raking Module (ACS):**
- **Harmonization:** Match NE25 ZIP codes to ACS geographic units (PUMA, county)
- **Raking:** Adjust NE25 sample weights to match ACS population distributions
- **Module Location:** `R/utils/raking_utils.R` (deferred)

**Benchmarking Module (NHIS/NSCH):**
- **Measure Alignment:** Map NE25 ACEs, PHQ-2, GAD-2 to NHIS/NSCH equivalents
- **Comparison:** Generate comparative statistics (Nebraska vs National)
- **Trend Analysis:** Track changes over time using NSCH multi-year data

### When to Run Each Pipeline

**NE25 Pipeline:**
```bash
# Run whenever new REDCap data is available
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

**ACS Pipeline:**
```bash
# Run annually or when new ACS data is released
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R --state nebraska --year-range 2019-2023 --state-fip 31
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

**NHIS Pipeline:**
```bash
# Run annually when new NHIS data is released
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

**NSCH Pipeline:**
```bash
# Run when new NSCH year is released
python scripts/nsch/process_all_years.py --years 2023

# Or process all years
python scripts/nsch/process_all_years.py --years all
```

---

## Related Documentation

- **Pipeline Execution Details:** [PIPELINE_STEPS.md](PIPELINE_STEPS.md)
- **Directory Structure:** [../DIRECTORY_STRUCTURE.md](../DIRECTORY_STRUCTURE.md)
- **Quick Reference:** [../QUICK_REFERENCE.md](../QUICK_REFERENCE.md)
- **ACS Documentation:** [../acs/README.md](../acs/README.md)
- **NHIS Documentation:** [../nhis/README.md](../nhis/README.md)
- **NSCH Documentation:** [../nsch/README.md](../nsch/README.md)

---

*Last Updated: October 2025*

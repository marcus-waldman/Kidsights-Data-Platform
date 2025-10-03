# NHIS Data Pipeline

Complete NHIS (National Health Interview Survey) data extraction pipeline for the Kidsights Data Platform. Extracts data from IPUMS Health Surveys API for years 2019-2024 with 64 variables covering demographics, parent characteristics, ACEs, and mental health.

---

## Quick Start

### Prerequisites

**Required Software:**
- Python 3.13+ with packages: `ipumspy`, `pandas`, `pyyaml`, `duckdb`, `structlog`
- R 4.5.1+ with packages: `arrow`, `dplyr`
- IPUMS API key stored at: `C:/Users/waldmanm/my-APIs/IPUMS.txt`

**Get IPUMS API Key:**
1. Register at [IPUMS Health Surveys](https://healthsurveys.ipums.org/)
2. Navigate to Account → API Keys
3. Generate new API key
4. Save to `C:/Users/waldmanm/my-APIs/IPUMS.txt`

### Run Complete Pipeline (3 Steps)

```bash
# Step 1: Extract from IPUMS NHIS API (30-45 min for 6 years)
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024

# Step 2: Validate in R
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024

# Step 3: Insert into DuckDB
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

**Output:**
- Raw data: `data/nhis/2019-2024/raw.feather` (~50-100 MB)
- Validated: `data/nhis/2019-2024/processed.feather`
- Database: `data/duckdb/kidsights_local.duckdb` (nhis_raw table)
- Validation report: `data/nhis/2019-2024/validation_report.txt`

---

## Architecture

### Hybrid Python-R Design

```
IPUMS NHIS API → Python: Extract/Cache → Feather Files → R: Validate → Python: Database → DuckDB
  (ih2019-ih2024)   ipumspy, requests      arrow format    Statistical QC   Chunked inserts   nhis_raw table
       ↓                    ↓                     ↓               ↓                ↓              ↓
  66 variables      SHA256 caching         3x faster I/O    7 validation    Perfect types   300K+ records
  6 annual samples  90+ day retention      R ↔ Python       checks          preservation    47+ MB
```

**Why This Design?**
- **Python for API/Database:** ipumspy handles IPUMS fixed-width data, DuckDB integration is stable in Python
- **R for Validation:** Statistical QC, survey design checks, complex validation logic
- **Feather Format:** 3x faster than CSV, perfect preservation of R factors ↔ pandas categories
- **Smart Caching:** Avoid 30-45 min re-downloads with SHA256 content-addressed cache

### Data Flow

```
1. EXTRACT (Python)
   - Submit extract to IPUMS API or retrieve from cache
   - Download fixed-width .dat + DDI codebook
   - Parse with ipumspy → pandas DataFrame
   - Save to Feather: data/nhis/{year_range}/raw.feather

2. VALIDATE (R)
   - Load Feather with arrow::read_feather()
   - Run 7 validation checks:
     * Variable presence (66 expected)
     * Year coverage (2019-2024)
     * Survey design (STRATA, PSU)
     * Sampling weights (SAMPWEIGHT)
     * Critical IDs (SERIAL+PERNUM)
     * ACE variables (8 vars, range 0-9)
     * Mental health (GAD-7, PHQ-8)
   - Generate validation report
   - Save processed.feather

3. INSERT (Python)
   - Load processed.feather
   - Chunked insertion to DuckDB
   - Create nhis_raw table
   - Validate row counts
```

---

## Key Features

### 66 NHIS Variables (11 Groups)

| Group | Count | Variables |
|-------|-------|-----------|
| **Identifiers** | 9 | YEAR, SERIAL, STRATA, PSU, NHISHID, PERNUM, NHISPID, HHX, SAMPWEIGHT |
| **Geographic** | 2 | REGION, URBRRL |
| **Demographics** | 2 | AGE, SEX |
| **Parent Info** | 13 | ISPARENTSC, PAR1REL, PAR2REL, PAR1AGE, PAR2AGE, PAR1SEX, PAR2SEX, PARRELTYPE, PAR1MARST, PAR2MARST, PAR1MARSTAT, PAR2MARSTAT, EDUCPARENT |
| **Race/Ethnicity** | 2 | RACENEW, HISPETH |
| **Education** | 1 | EDUC |
| **Economic** | 5 | FAMTOTINC, POVERTY, FSATELESS, FSBALANC, OWNERSHIP |
| **ACEs** | 8 | VIOLENEV, JAILEV, MENTDEPEV, ALCDRUGEV, ADLTPUTDOWN, UNFAIRRACE, UNFAIRSEXOR, BASENEED |
| **GAD-7 Anxiety** | 8 | GADANX, GADWORCTRL, GADWORMUCH, GADRELAX, GADRSTLS, GADANNOY, GADFEAR, GADCAT |
| **PHQ-8 Depression** | 9 | PHQINTR, PHQDEP, PHQSLEEP, PHQENGY, PHQEAT, PHQBAD, PHQCONC, PHQMOVE, PHQCAT |
| **Flags** | 5 | SASCRESP, ASTATFLG, CSTATFLG, HHRESP, RELATIVERESPC |

**Variable Details:** See [nhis_variables_reference.md](nhis_variables_reference.md)

### Multi-Year Annual Samples

**Years:** 2019, 2020, 2021, 2022, 2023, 2024 (6 years)
**Samples:** ih2019, ih2020, ih2021, ih2022, ih2023, ih2024
**Coverage:** Nationwide, all ages (no case selection)

**Note:** NHIS uses annual samples, not pooled 5-year estimates like ACS.

### Intelligent Caching

**SHA256-based Content Addressing:**
- Cache signature based on years + samples + variables
- 90+ day retention for completed extracts
- Automatic checksum validation on cache retrieval
- Avoids 30-45 min re-downloads when config unchanged

**Cache Location:** `cache/ipums/{extract_id}/`

### Survey Design Variables

**Complex Survey Analysis Support:**
- **SAMPWEIGHT:** Primary sampling weight for population estimates
- **STRATA:** Stratification variable for variance estimation
- **PSU:** Primary sampling unit for clustering
- **LONGWEIGHT, PARTWT:** Alternative weights for specific 2020 analyses

**R Integration:** Compatible with `survey` and `srvyr` packages for complex survey analysis.

---

## Documentation

- **[Pipeline Usage Guide](pipeline_usage.md)** - Complete walkthrough, examples, troubleshooting
- **[Variables Reference](nhis_variables_reference.md)** - All 66 variables with IPUMS coding
- **[Testing Guide](testing_guide.md)** - API tests, end-to-end testing, validation
- **[Transformation Mappings](transformation_mappings.md)** - NHIS → NE25 harmonization (future)

---

## Project Structure

```
Kidsights-Data-Platform/
├── python/nhis/                    # Python modules
│   ├── auth.py                     # IPUMS API authentication
│   ├── config_manager.py           # YAML config loading
│   ├── extract_builder.py          # Extract definition builder
│   ├── extract_manager.py          # API submission/download
│   ├── cache_manager.py            # SHA256 caching system
│   └── data_loader.py              # Fixed-width data parsing
│
├── pipelines/
│   ├── python/nhis/                # Executable Python scripts
│   │   ├── extract_nhis_data.py    # CLI for data extraction
│   │   └── insert_nhis_database.py # CLI for database insertion
│   │
│   └── orchestration/              # R orchestration
│       └── run_nhis_pipeline.R     # R validation pipeline
│
├── R/
│   ├── load/nhis/                  # Data loading functions
│   │   └── load_nhis_data.R        # Feather file loading
│   │
│   └── utils/nhis/                 # Validation utilities
│       └── validate_nhis_raw.R     # 7 validation checks
│
├── config/sources/nhis/            # YAML configurations
│   ├── nhis-template.yaml          # Template with 66 variables
│   ├── nhis-2019-2024.yaml         # Year-specific config
│   └── samples.yaml                # Sample reference
│
├── docs/nhis/                      # Documentation
│   ├── README.md                   # This file
│   ├── pipeline_usage.md           # Usage guide
│   ├── nhis_variables_reference.md # Variable reference
│   ├── testing_guide.md            # Testing procedures
│   └── transformation_mappings.md  # Harmonization mappings
│
├── scripts/nhis/                   # Utility scripts
│   ├── test_api_connection.py      # API connection test
│   └── test_pipeline_end_to_end.R  # End-to-end test
│
└── data/nhis/{year_range}/         # Data output
    ├── raw.feather                 # Raw IPUMS data
    ├── processed.feather           # Validated data
    └── validation_report.txt       # Validation results
```

---

## Common Tasks

### Check Extract Status
```bash
python scripts/nhis/check_extract_status.py nhis:12345
```

### Manage Cache
```bash
# List cached extracts
python scripts/nhis/manage_cache.py --list

# Validate cache integrity
python scripts/nhis/manage_cache.py --validate

# Clean old cache (>90 days)
python scripts/nhis/manage_cache.py --clean --max-age 90
```

### Query Database
```python
import duckdb
conn = duckdb.connect("data/duckdb/kidsights_local.duckdb")

# Record count by year
conn.execute("SELECT YEAR, COUNT(*) FROM nhis_raw GROUP BY YEAR ORDER BY YEAR").fetchall()

# Sample weights statistics
conn.execute("SELECT MIN(SAMPWEIGHT), MAX(SAMPWEIGHT), AVG(SAMPWEIGHT) FROM nhis_raw").fetchall()
```

---

## Differences from ACS Pipeline

| Feature | ACS Pipeline | NHIS Pipeline |
|---------|--------------|---------------|
| **Collection** | IPUMS USA (`usa`) | IPUMS Health Surveys (`nhis`) |
| **Samples** | Pooled 5-year (us2019) | Annual (ih2019, ih2020, ...) |
| **Case Selection** | State + Age filters | None (nationwide, all ages) |
| **Variables** | 25 | 66 |
| **Data Format** | CSV | Fixed-width (.dat + DDI) |
| **Parsing** | pandas.read_csv() | ipumspy.read_microdata() |
| **Cache Signature** | state + state_fip + years | years + samples |
| **Primary Use** | Statistical raking | Mental health, ACEs, parent data |

---

## Expected Outcomes

- **Records:** 229,609 (6 years, 2019-2024 production data)
- **Processing Time:** 61 seconds (production extraction) or <1s from cache
- **File Size:** 20 MB Feather file
- **Database Size:** 47+ MB in DuckDB (nhis_raw table)
- **Cache:** Reusable SHA256-based cache for future runs

---

## Status

**Pipeline Status:** ✅ Complete (All 7 Phases)
**Production Ready:** Yes
**Last Updated:** 2025-10-03

### Completed Phases

- ✅ **Phase 1:** Core Infrastructure (10 Python modules)
- ✅ **Phase 2:** Configuration Files (3 YAML configs)
- ✅ **Phase 3:** R Validation Layer (3 R files, 7 validation checks)
- ✅ **Phase 4:** Database Integration (nhis_raw table, chunked insertion)
- ✅ **Phase 5:** Documentation (complete with usage guides and variable reference)
- ✅ **Phase 6:** Testing & Validation (API tests, end-to-end tests, all passing)
- ✅ **Phase 7:** Production Run & Deployment (229,609 records, 188,620 sample persons, all validation checks passed)

---

## Support

**Documentation Issues:** Create issue in GitHub repository
**IPUMS Support:** [IPUMS User Support](https://ipums.org/support)
**Pipeline Maintainer:** Kidsights Data Platform Team

---

*Created: 2025-10-03 | Pipeline Version: 1.0.0*

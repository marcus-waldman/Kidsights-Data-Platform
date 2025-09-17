# Kidsights Data Platform - Development Guidelines & Architecture

## Project Context

The Kidsights Data Platform is a multi-source ETL system for longitudinal childhood development research in Nebraska. Data from multiple sources (REDCap, Census, healthcare, education, childcare) is harmonized and stored in DuckDB locally with robust Python-based database operations.

## Architecture Migration (September 2025)

**🚀 Python Database Architecture**: The platform migrated from R DuckDB to Python-based database operations to eliminate persistent segmentation faults that made the pipeline unreliable.

### Why We Migrated
- **Problem**: R's DuckDB package caused frequent segmentation faults (~50% pipeline failure rate)
- **Impact**: Unreliable pipeline execution, data loss risk, poor debugging experience
- **Solution**: Hybrid R-Python architecture separating concerns:
  - **R**: Pipeline orchestration, REDCap extraction, data transformations
  - **Python**: All database operations, metadata generation, error handling

### Architecture Overview
```
REDCap Projects (4) → R: API Extraction → R: Type Harmonization → R: Dashboard Transforms
     ↓                         ↓                     ↓                        ↓
- Project 7679             - REDCapR             - flexible_bind         - recode_it()
- Project 7943             - Secure tokens       - Type conversion       - Race/ethnicity
- Project 7999             - Rate limiting       - Field mapping         - Education cats
- Project 8014                                                           - Age groups
                                                   ↓
              Python: Database Operations → DuckDB Storage (Local)
                         ↓                         ↓
                  - Connection mgmt            - ne25_raw
                  - Error handling             - ne25_transformed
                  - Metadata generation        - ne25_metadata
                  - Performance monitoring     - ne25_data_dictionary
```

### Key Benefits Achieved
- ✅ **100% Pipeline Success Rate** (previously ~50%)
- ✅ **Zero Segmentation Faults** since migration
- ✅ **Rich Error Context** instead of mysterious crashes
- ✅ **Automated Error Recovery** with retry logic
- ✅ **Performance Monitoring** with detailed timing
- ✅ **Memory Efficiency** with chunked processing

## Directory Structure & Organization

### `/python/` - Python Database Operations
**Purpose**: Robust database operations that eliminated R DuckDB segmentation faults

- **`/python/db/`** - Core database modules
  - `connection.py` - DatabaseManager with connection pooling and retry logic
  - `operations.py` - High-level database operations with chunked processing
  - `config.py` - Configuration loading and management

- **`/python/utils/`** - Python utilities
  - `logging.py` - Enhanced logging with PerformanceLogger and error context
  - `error_handling.py` - Robust error recovery with exponential backoff

### `/pipelines/python/` - Python Database Scripts
**Purpose**: Executable Python scripts called by R pipeline to avoid segmentation faults

- `init_database.py` - Database schema initialization
- `insert_raw_data.py` - Bulk data insertion with memory-efficient chunking
- `generate_metadata.py` - Variable metadata generation and analysis

### `/R/` - Core R Package Functions
**Purpose**: Reusable R functions for orchestration and data processing

- **`/R/extract/`** - Source-specific data extraction functions
  - Each source gets its own file (e.g., `redcap.R`, `census.R`)
  - Functions handle API authentication, rate limiting, error handling
  - Return standardized data frames with consistent column naming

- **`/R/harmonize/`** - Data harmonization and integration
  - `schema_mapper/` - Map source schemas to common data model
  - `entity_resolver/` - Match and link participants across sources
  - `temporal_aligner/` - Align data from different time points
  - `vocabulary_standardizer/` - Standardize coded values across sources

- **`/R/duckdb/`** - ⚠️ DEPRECATED - Use Python database operations instead
  - Legacy R DuckDB functions (archived due to segmentation faults)
  - All database operations now handled by Python scripts

- **`/R/utils/`** - Shared utilities
  - Logging, error handling, caching, configuration loading

### `/pipelines/` - ETL Pipeline Definitions
**Purpose**: Executable scripts that orchestrate the ETL process

- **`/pipelines/extractors/`** - Source-specific extraction pipelines
  - Each source has its own folder (e.g., `/redcap/`, `/census/`)
  - Contains extraction script and source-specific config
  - Handles incremental vs. full loads

- **`/pipelines/harmonization/`** - Data integration pipelines
  - Cross-source participant linking
  - Temporal alignment across longitudinal waves
  - Quality checks and validation

- **`/pipelines/orchestration/`** - Master pipeline controllers
  - Daily, weekly, and ad-hoc pipeline runs
  - Dependency management between pipeline steps
  - Error recovery and alerting

### `/schemas/` - DuckDB Schema Definitions
**Purpose**: SQL DDL for database structure

- **`/schemas/landing/`** - Raw data as extracted from sources
  - Minimal transformation, preserves source structure
  - One schema file per data source

- **`/schemas/staging/`** - Intermediate processing tables
  - Light transformations and data type conversions
  - Temporary tables for processing

- **`/schemas/harmonized/`** - Integrated, clean data
  - Common data model across all sources
  - Standardized variables and coding
  - Entity-resolved participants

- **`/schemas/analytics/`** - Analysis-ready views and tables
  - Pre-aggregated metrics
  - Cohort definitions
  - Census comparison views

### `/config/` - Configuration Files
**Purpose**: YAML/JSON configuration for all components

- **`/config/sources/`** - Data source configurations
  - API endpoints, credentials references
  - Field lists, filter criteria
  - Scheduling and retry policies

- **Core config files**:
  - `graph_api.yaml` - Microsoft Graph settings
  - `duckdb.yaml` - Database configuration
  - `harmonization.yaml` - Integration rules
  - `orchestration.yaml` - Pipeline scheduling

### `/mappings/` - Data Harmonization Mappings
**Purpose**: Define how data sources map to common model

- **`/mappings/field_mappings/`** - Source → target field mappings
  - JSON files defining field-level transformations
  - Data type conversions and calculations

- **`/mappings/vocabularies/`** - Controlled vocabularies
  - Standard code lists (race, ethnicity, education levels)
  - Cross-source code mappings

- **`/mappings/linkage_rules/`** - Entity resolution rules
  - Participant matching algorithms
  - Confidence thresholds

### `/cache/` - Local Caching
**Purpose**: Temporary local storage for performance

- **`/cache/duckdb/`** - Local DuckDB file cache
- **`/cache/graph_api/`** - API response cache

### `/tests/` - Test Suites
**Purpose**: Unit and integration tests

- **`/tests/unit/`** - Function-level tests
  - `test_extractors/` - Test each data source extractor
  - `test_harmonization/` - Test mapping and linking
  - `test_graph_api/` - Test Graph API operations

- **`/tests/integration/`** - End-to-end pipeline tests

### `/scripts/` - Utility Scripts
**Purpose**: Setup and maintenance operations

- **`/scripts/setup/`** - Initial configuration
  - Initialize DuckDB schema
  - Configure Graph API authentication
  - Create OneDrive folder structure

- **`/scripts/maintenance/`** - Ongoing operations
  - Backup to OneDrive
  - Cache cleanup
  - Database optimization

### `/docs/` - Documentation
**Purpose**: Technical and user documentation

- **`/docs/architecture/`** - System design documents
- **`/docs/api/`** - Function documentation
- **`/docs/data_dictionary/`** - Variable definitions

## Development Standards

### File Naming Conventions
- R files: `snake_case.R` (e.g., `extract_redcap.R`)
- Config files: `kebab-case.yaml` (e.g., `graph-api.yaml`)
- SQL schemas: `snake_case.sql` (e.g., `core_participants.sql`)
- Documentation: `UPPER_CASE.md` for key docs, `snake_case.md` for others

### Code Organization Principles

1. **Separation of Concerns**
   - Extraction logic separate from transformation
   - Configuration separate from code
   - Schema definitions separate from data operations

2. **Modularity**
   - Each data source has independent extraction pipeline
   - Harmonization steps are composable
   - Reusable functions in `/R/` directory

3. **Configuration-Driven**
   - No hardcoded values in scripts
   - All settings in YAML/JSON configs
   - Environment variables for secrets

4. **Error Handling**
   - Every external API call wrapped in try-catch
   - Detailed logging at each pipeline step
   - Graceful degradation when sources unavailable

### Data Flow Architecture

**Current (Python-based)**:
```
REDCap Sources → R: Extract → R: Harmonize → Python: Store → R: Transform → Python: Store → Python: Metadata
       ↓              ↓            ↓             ↓            ↓             ↓              ↓
   4 Projects    REDCapR API   Type binding   DuckDB ops   recode_it()   DuckDB ops   Analysis-ready
   3,906 records   Secure auth   Validation    Chunked      588 vars     Chunked      Comprehensive
                                              Reliable                   Reliable      documentation
                                                ↓
                                        Local DuckDB (data/duckdb/kidsights_local.duckdb)
```

**Legacy (OneDrive sync - archived)**:
```
Sources → Extract → Land → Harmonize → Stage → Analytics → DuckDB → OneDrive
                                                                ↑
                                                         Graph API Access
```

### Security Considerations

1. **No Secrets in Code**
   - Use environment variables
   - Store in `.env` file (git-ignored)
   - Reference in configs

2. **Graph API Authentication**
   - OAuth2 flow with Azure AD
   - Refresh tokens stored securely
   - Scoped permissions (minimum required)

3. **Data Privacy**
   - PII handling rules in harmonization
   - De-identification where required
   - Audit logging for data access

## Key Architecture Decisions

1. **Hybrid R-Python Architecture** (September 2025)
   - **R**: Pipeline orchestration, REDCap extraction, statistical transformations
   - **Python**: Database operations, metadata generation, error handling
   - **Rationale**: Eliminates R DuckDB segmentation faults while preserving R strengths
   - **Result**: 100% pipeline reliability, rich error context

2. **Local DuckDB Storage**
   - **Path**: `data/duckdb/kidsights_local.duckdb`
   - **Rationale**: Eliminates OneDrive sync conflicts that contributed to instability
   - **Benefits**: Faster access, no network dependencies, simplified troubleshooting

3. **DuckDB over Traditional RDBMS**
   - Columnar storage ideal for analytical queries
   - Excellent compression for large datasets
   - Native Parquet support
   - ACID compliant

4. **Python Database Package Reliability**
   - **Problem**: R's DuckDB package has persistent segmentation fault issues
   - **Solution**: Python's DuckDB package is stable and mature
   - **Implementation**: Context managers, connection pooling, chunked processing

5. **Multi-Source Harmonization**
   - Common data model across sources
   - Probabilistic record linkage
   - Temporal alignment for longitudinal analysis
   - Standardized vocabularies

## Pipeline Execution Order (Current Python Architecture)

1. **Database Initialization** (Python)
   ```bash
   python pipelines/python/init_database.py --config config/sources/ne25.yaml
   ```
   - Creates local DuckDB schema
   - Sets up all required tables and indexes

2. **Data Extraction** (R)
   - Extract from 4 REDCap projects using REDCapR
   - Type harmonization with flexible_bind_rows
   - Eligibility validation (9 CID criteria)

3. **Raw Data Storage** (Python)
   ```bash
   python pipelines/python/insert_raw_data.py --data-file temp_data.csv --table-name ne25_raw
   ```
   - Chunked insertion for memory efficiency
   - Project-specific tables (ne25_raw_pid7679, etc.)

4. **Data Transformation** (R)
   - Dashboard-style transformations with recode_it()
   - Race/ethnicity harmonization
   - Education level categorization

5. **Transformed Data Storage** (Python)
   - Store 588 transformed variables
   - Automatic error recovery and retry logic

6. **Metadata Generation** (Python)
   ```bash
   python pipelines/python/generate_metadata.py --source-table ne25_transformed
   ```
   - Comprehensive variable analysis
   - Missing data percentages
   - Value label extraction

7. **Documentation Generation** (Python + R + Quarto)
   - Multi-format documentation (Markdown, HTML, JSON)
   - Interactive data dictionary with tree navigation

## Environment Setup

### Required Software
- **R 4.4.3+** at `C:/Program Files/R/R-4.4.3/bin`
- **Python 3.13+** with packages: `duckdb`, `pandas`, `pyyaml`, `structlog`
- **Quarto** for documentation rendering

### Required Environment Variables
```bash
# REDCap API tokens (stored in CSV file)
KIDSIGHTS_API_TOKEN_7679=<Project 7679 token>
KIDSIGHTS_API_TOKEN_7943=<Project 7943 token>
KIDSIGHTS_API_TOKEN_7999=<Project 7999 token>
KIDSIGHTS_API_TOKEN_8014=<Project 8014 token>
```

### Configuration Files
- `config/sources/ne25.yaml` - Pipeline configuration
- `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv` - API credentials

## Common Tasks

### Adding a New Data Source
1. Create extractor in `/R/extract/`
2. Add pipeline in `/pipelines/extractors/<source>/`
3. Define schema in `/schemas/landing/`
4. Create field mappings in `/mappings/field_mappings/`
5. Add config in `/config/sources/`
6. Write tests in `/tests/unit/test_extractors/`

### Modifying Harmonization Rules
1. Update mappings in `/mappings/`
2. Modify harmonization functions in `/R/harmonize/`
3. Update staging schemas if needed
4. Test with integration tests
5. Document changes

### Debugging Pipeline Failures (Python Architecture)
1. **Check Error Context**
   - Python scripts provide detailed error messages with context
   - No more mysterious "Segmentation fault" crashes

2. **Verify Python Dependencies**
   ```bash
   python --version  # Should be 3.13+
   pip list | grep -E "(duckdb|pandas|pyyaml)"
   ```

3. **Test Database Connection**
   ```bash
   python -c "from python.db.connection import DatabaseManager; dm = DatabaseManager(); print('Success' if dm.test_connection() else 'Failed')"
   ```

4. **Run from Project Root**
   - All Python scripts expect to be run from project root directory
   - Check that you're in `/Kidsights-Data-Platform/`

5. **Check Configuration**
   - Verify `config/sources/ne25.yaml` exists and is valid
   - Ensure API credentials file exists at expected path

### Legacy Troubleshooting (Archived)
For pre-migration R DuckDB issues, see: `docs/archive/pre-python-migration/troubleshooting.md`

## Codebook System

The platform includes a comprehensive JSON-based codebook system for managing item metadata across multiple studies.

### Architecture Overview

```
CSV Codebook → JSON Conversion → R API → Quarto Dashboard
                     ↓              ↓           ↓
               305 Items      Query/Filter   Web Explorer
               8 Studies     Validation     Tree Navigation
               4 Domains     Visualization  Interactive UI
```

### Core Components

#### 1. **JSON Data Structure**
- **Location**: `codebook/data/codebook.json`
- **Items**: 305 total (259 original + 46 GSED_PF PS items)
- **Studies**: NE25, NE22, NE20, CAHMI22, CAHMI21, ECDI, CREDI, GSED_PF
- **Domains**: socemo, motor, coglan, psychosocial_problems_general

#### 2. **R Function Library**
- **Location**: `R/codebook/`
- **Modules**: load, query, validate, visualize
- **Key Functions**:
  - `load_codebook()` - Load and initialize JSON
  - `filter_items_by_domain()` - Domain-based filtering
  - `filter_items_by_study()` - Study-based filtering
  - `get_item()` - Retrieve specific items
  - `items_to_dataframe()` - Convert to analysis format

#### 3. **Conversion Pipeline**
- **Location**: `scripts/codebook/initial_conversion.R`
- **Process**: CSV + PS items → JSON with validation
- **Features**:
  - Automatic PS items integration
  - Response set detection
  - Natural alphanumeric sorting
  - Reverse coding corrections

#### 4. **Interactive Dashboard**
- **Location**: `codebook/dashboard/`
- **Technology**: Quarto + jsTree navigation
- **Features**: Hierarchical JSON exploration, search, tree drill-down
- **Output**: `docs/codebook_dashboard/index.html`

### JSON Structure Conventions

#### Item Structure
```json
{
  "id": 2001,
  "studies": ["NE25", "NE22", "NE20"],
  "lexicons": {
    "equate": "PS001",
    "ne25": "PS001"
  },
  "domains": {
    "kidsights": {
      "value": [
        "psychosocial_problems_general",
        "psychosocial_problems_feeding"
      ],
      "studies": ["NE25", "NE22", "NE20"]
    }
  },
  "content": {
    "stems": {
      "combined": "Do you have any concerns..."
    },
    "response_options": {
      "ne25": "ps_frequency"
    }
  },
  "scoring": {
    "reverse": false,
    "equate_group": "NE25"
  },
  "psychometric": {
    "irt_parameters": {
      "NE22": {
        "factors": ["gen", "eat"],
        "loadings": [0.492, 1.447],
        "thresholds": [-2.782, -0.193],
        "constraints": []
      }
    }
  }
}
```

#### Response Sets
```json
{
  "response_sets": {
    "ps_frequency": [
      {"value": 0, "label": "Never or Almost Never"},
      {"value": 1, "label": "Sometimes"},
      {"value": 2, "label": "Often"},
      {"value": -9, "label": "Don't Know", "missing": true}
    ]
  }
}
```

### Adding New Items/Studies

#### 1. **Add to Configuration**
Update `config/codebook_config.yaml`:
```yaml
validation:
  study_validation:
    valid_studies:
      - "NEW_STUDY"
  domain_validation:
    valid_domains:
      - "new_domain"
```

#### 2. **Create Parser Function**
Add to `scripts/codebook/initial_conversion.R`:
```r
parse_new_study_items <- function(csv_path) {
  # Read and parse new items
  # Return structured list
}
```

#### 3. **Integrate in Conversion**
Update `convert_csv_to_json()`:
```r
# Add new items
new_items <- parse_new_study_items()
items_list <- c(items_list, new_items)
```

#### 4. **Test Integration**
```r
source("scripts/codebook/initial_conversion.R")
convert_csv_to_json()

# Verify
codebook <- load_codebook("codebook/data/codebook.json")
new_items <- filter_items_by_study(codebook, "NEW_STUDY")
```

### Response Set System

#### Adding New Response Sets
1. **Define in config**:
```yaml
response_sets:
  new_scale:
    - value: 1
      label: "Option 1"
    - value: 2
      label: "Option 2"
```

2. **Reference in items**:
```json
"response_options": {
  "study_name": "new_scale"
}
```

3. **Detection in conversion**:
```r
# Add to detect_response_set_or_parse()
if (str_detect(normalized, "pattern_for_new_scale")) {
  return("new_scale")
}
```

### Dashboard Customization

#### Rendering
```bash
quarto render codebook/dashboard/index.qmd
```

#### Configuration
- **Location**: `codebook/dashboard/_quarto.yml`
- **Styling**: `codebook/dashboard/custom.scss`
- **Assets**: `codebook/dashboard/assets/`

#### Tree Navigation
- Uses jsTree for hierarchical display
- Mirrors exact JSON structure
- Supports drill-down to specific values
- Search functionality included

### Testing and Validation

#### Basic Functionality Test
```r
source("R/codebook/load_codebook.R")
source("R/codebook/query_codebook.R")

codebook <- load_codebook("codebook/data/codebook.json", validate=FALSE)
motor_items <- filter_items_by_domain(codebook, "motor")
gsed_items <- filter_items_by_study(codebook, "GSED_PF")
cat("Found", length(gsed_items), "GSED_PF items\n")
```

#### Validation
```r
source("R/codebook/validate_codebook.R")
validation <- validate_codebook_structure(codebook)
stopifnot(validation$valid)
```

### Current Status (September 2025)

#### ✅ **COMPLETED v2.6**
- **306 Items**: 260 original + 46 PS items with complete IRT parameters
- **NE22 IRT Integration**: 203 items with empirical unidimensional IRT parameters
- **Bifactor IRT Model**: 44 PS items with factor loadings from Mplus output
- **Multi-domain Support**: Array-based domain assignments for PS items
- **Corrected Studies**: PS items with proper NE25/NE22/NE20 participation
- **Response Sets**: Added ps_frequency scale for psychosocial items
- **Dashboard**: Dark mode toggle and updated navigation
- **Array Format**: Clean threshold storage as `[-1.418, 0.167]` instead of named objects

#### **Key Features**
- **IRT Parameters**: 4-field structure with constraints, array-based thresholds
- **Bifactor Model**: General factor (gen) + specific factors (eat, sle, soc, int, ext)
- **Threshold Transformation**: Proper Mplus threshold conversion (negate and sort)
- **Multi-domain Items**: PS items assigned to multiple psychosocial domains
- **Special Cases**: PS033 with NE22/NE20 only and reverse scoring
- Natural alphanumeric sorting (AA4, AA5, AA11, AA102)
- Response set references (single source of truth)
- Hierarchical domain structure with study groups
- Interactive tree navigation with exact JSON mirroring
- Complete R function library with 20+ functions

### Development Notes

#### File Handling
- Use `simplifyVector = FALSE` when loading JSON in R
- Always validate after major changes
- Use `gtools::mixedsort()` for proper item ordering

#### Performance
- Load without validation for large operations: `validate = FALSE`
- Cache codebook object in interactive sessions
- Use `items_to_dataframe()` for bulk analysis

#### Error Handling
- All functions return NULL/empty for invalid inputs with warnings
- Validation functions provide detailed error lists
- Dashboard gracefully handles missing data

## Contact & Support

- Technical Lead: [Contact Info]
- Data Steward: [Contact Info]
- Graph API Admin: [Contact Info]

## Version Control

- Main branch: Production-ready code
- Feature branches: `feature/<description>`
- Bug fixes: `bugfix/<description>`
- Pull requests required for main branch

---
*Last Updated: September 17, 2025*
*Version: 2.1.0 - Parquet Integration*

## Pipeline Status (September 2025)

### ✅ PYTHON ARCHITECTURE MIGRATION COMPLETED
The NE25 pipeline has been successfully migrated to a hybrid R-Python architecture, eliminating all segmentation faults:

#### **Core Achievement: 100% Reliability**
- **Before**: ~50% pipeline success rate due to R DuckDB segmentation faults
- **After**: 100% pipeline success rate with Python database operations
- **Zero segmentation faults** since migration

#### **Production Data Processing**
- **Data Extraction**: 3,906 records from 4 REDCap projects
- **PID-based Storage**: Project-specific tables (ne25_raw_pid7679, ne25_raw_pid7943, ne25_raw_pid7999, ne25_raw_pid8014)
- **Data Dictionary Storage**: 1,884 fields with PID references in ne25_data_dictionary table
- **Dashboard Transformations**: Full recode_it() transformations applied (588 variables)
- **Metadata Generation**: 28 comprehensive metadata records in ne25_metadata table
- **Documentation**: Auto-generated Markdown, HTML, and JSON exports

### Python Architecture Components
#### **Database Operations** (`python/db/`)
- `connection.py` - DatabaseManager with connection pooling and retry logic
- `operations.py` - High-level database operations with chunked processing
- `config.py` - Configuration loading and management

#### **Pipeline Scripts** (`pipelines/python/`)
- `init_database.py` - Schema initialization without R DuckDB
- `insert_raw_data.py` - Bulk data insertion replacing R's dbWriteTable
- `generate_metadata.py` - Variable metadata generation

#### **Enhanced Error Handling** (`python/utils/`)
- Rich error context instead of segmentation faults
- Exponential backoff retry logic
- Performance monitoring with detailed timing
- Memory-efficient chunked processing

### Migration Benefits Achieved
1. **Reliability**: 100% pipeline success rate (was ~50%)
2. **Debugging**: Rich error messages (was "Segmentation fault")
3. **Performance**: Chunked processing with monitoring
4. **Recovery**: Automatic retry logic with exponential backoff
5. **Monitoring**: Detailed logging and operation timing

### Production-Ready Components
- `run_ne25_pipeline.R` - Main pipeline execution (calls Python scripts)
- `pipelines/orchestration/ne25_pipeline.R` - Complete pipeline orchestration
- `python/db/` - Robust database operations module
- `pipelines/python/` - Executable Python database scripts
- `docs/python/architecture.md` - Complete technical documentation

### Development Notes
- **Python Required**: 3.13+ with packages: `duckdb`, `pandas`, `pyyaml`, `structlog`
- **Database Location**: `data/duckdb/kidsights_local.duckdb` (local, not OneDrive)
- **Run from Root**: All scripts expect to be run from project root directory
- **R DuckDB Deprecated**: All database operations now use Python for stability
- **Documentation**: Comprehensive migration guide at `docs/guides/migration-guide.md`

### Quick Start (Python Architecture)
```bash
# Run complete pipeline
Rscript run_ne25_pipeline.R

# Test individual components
python pipelines/python/init_database.py --config config/sources/ne25.yaml
```

## Current Development Status (September 17, 2025)

### 🔄 **PARQUET MIGRATION IN PROGRESS**

#### **Completed Migration Steps**
- ✅ **R Pipeline Updated**: Replaced all `write.csv()` calls with `arrow::write_parquet()`
- ✅ **Python Script Updated**: Enhanced `insert_raw_data.py` to handle both CSV and Parquet formats
- ✅ **Library Integration**: Added `library(arrow)` to R pipeline dependencies
- ✅ **File Extensions**: Updated all temp file references from `.csv` to `.parquet`

#### **Files Modified**
- `pipelines/orchestration/ne25_pipeline.R` - Updated 5 data export points to use Parquet
- `pipelines/python/insert_raw_data.py` - Added Parquet file format support
- `run_ne25_pipeline.R` - Fixed comment to reference local database (not OneDrive)

#### **Parquet Files Created**
- `tempdir()/ne25_pipeline/ne25_raw.parquet`
- `tempdir()/ne25_pipeline/ne25_eligibility.parquet`
- `tempdir()/ne25_pipeline/ne25_raw_pid{7679,7943,7999,8014}.parquet`
- `tempdir()/ne25_pipeline/dictionary_pid{7679,7943,7999,8014}.parquet`
- `tempdir()/ne25_pipeline/ne25_transformed.parquet`

### 🚨 **Critical Discovery: R Installation Issues**

During testing, we discovered **persistent segmentation faults with multiple R packages**:

```bash
# These ALL fail with segmentation fault:
Rscript -e "library(duckdb); con <- dbConnect(duckdb::duckdb())"
Rscript -e "library(arrow); arrow::write_parquet(data.frame(x=1:5), 'test.parquet')"
Rscript -e "library(arrow); arrow::write_feather(data.frame(x=1:5), 'test.feather')"
```

#### **Scope of R Issues**
- **R DuckDB package**: Confirmed segmentation faults (original problem)
- **R arrow package**: Segmentation faults with both Parquet and Feather operations
- **Pattern**: All binary/system-level R packages appear affected
- **Basic R**: Works fine with base operations and simple packages

#### **Impact Assessment**
- **Problem**: R installation appears corrupted or incompatible
- **Scope**: Affects all advanced file format operations in R
- **Workaround**: Python handles all binary file operations perfectly
- **Solution**: R reinstallation likely required

#### **Tested Alternatives**
1. ✅ **Python PyArrow/Feather**: Works perfectly for all file formats
2. ✅ **CSV Fallback**: Current working solution (R → CSV → Python)
3. ❌ **R Parquet**: Segmentation faults
4. ❌ **R Feather**: Segmentation faults
5. 🔄 **JSON Intermediate**: Not yet tested (R → JSON → Python → Feather)

### 📋 **Python Dependencies Status**

#### **✅ Python Packages Installed and Working**
```bash
# Successfully installed:
pip install pyarrow pandas  # Completed successfully
```

#### **✅ Python Functionality Confirmed**
```python
# All of these work perfectly:
import pandas as pd
df = pd.DataFrame({'x': [1,2,3]})
df.to_parquet('test.parquet')    # ✅ Works
df.to_feather('test.feather')    # ✅ Works
df.to_csv('test.csv')            # ✅ Works

# PyArrow directly:
import pyarrow.feather as feather
feather.write_feather(df, 'test.feather')  # ✅ Works
```

### 🎯 **Next Session Priorities**

#### **Critical: R Installation Issues**
1. **R Reinstallation Required**
   ```bash
   # Current R installation has systemic issues with binary packages
   # Affects: duckdb, arrow, and likely other system-level packages
   # Recommend: Complete R reinstallation with updated version
   ```

2. **R Installation Verification**
   ```bash
   # After reinstallation, test these packages:
   Rscript -e "library(duckdb); cat('DuckDB works\\n')"
   Rscript -e "library(arrow); cat('Arrow works\\n')"
   ```

3. **Post-Reinstallation Pipeline Testing**
   - **Option A**: Test R arrow → Feather pipeline (preferred)
   - **Option B**: Test R arrow → Parquet pipeline
   - **Option C**: Continue with proven CSV workflow (current fallback)

#### **Alternative Architectures (If R Issues Persist)**
4. **JSON Intermediate Format**
   - R writes JSON (reliable) → Python converts to Feather/Parquet
   - Preserves data types while avoiding R binary package issues

5. **Complete Pipeline Testing**
   - Test actual REDCap API extraction (not just database → documentation)
   - Verify complete end-to-end: REDCap → R → Format → Python → DuckDB → JSON → Quarto

### 📊 **Current Architecture Status**

#### **Database Location**: ✅ Confirmed
- Local: `data/duckdb/kidsights_local.duckdb` (47 MB)
- Contains: 11 NE25 tables with 7,812 records

#### **JSON Documentation Workflow**: ✅ 100% Stable
- Python → JSON → Quarto → HTML (no R DuckDB connections)
- Successfully generates 1.17 MB JSON with 1,880 variables
- Renders 6 HTML documentation pages

#### **R Installation Issues**: 🚨 Critical
- **Multiple packages affected**: DuckDB, arrow (Parquet & Feather)
- **Pattern**: All binary/system-level R packages cause segmentation faults
- **Current workaround**: Python handles all binary file operations
- **Solution needed**: Complete R reinstallation

#### **Current Pipeline Status**: ✅ Functional with CSV
- **Working**: R → CSV → Python → DuckDB workflow
- **Reverted**: Pipeline back to CSV format (from failed Parquet attempt)
- **Ready**: Can switch to Feather/Parquet after R is fixed

### 💡 **Session Context for R Reinstallation**

After R reinstallation, test in this order:
1. ✅ **Basic R functionality**: `Rscript -e "cat('Hello\\n')"`
2. 🔄 **DuckDB package**: `Rscript -e "library(duckdb)"`
3. 🔄 **Arrow package**: `Rscript -e "library(arrow)"`
4. 🔄 **Feather operations**: `Rscript -e "library(arrow); arrow::write_feather(data.frame(x=1), 'test.feather')"`
5. 🚀 **Full pipeline test**: Complete REDCap → Feather → Python → DuckDB flow

**Fallback**: If R issues persist, implement JSON intermediate format (R → JSON → Python → Feather)
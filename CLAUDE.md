# Kidsights Data Platform - Development Guidelines & Architecture

## Project Context

The Kidsights Data Platform is a multi-source ETL system for longitudinal childhood development research in Nebraska. Data from multiple sources (REDCap, Census, healthcare, education, childcare) is harmonized and stored in DuckDB on University OneDrive, accessed via Microsoft Graph API.

## Directory Structure & Organization

### `/R/` - Core R Package Functions
**Purpose**: Reusable R functions organized by domain

- **`/R/extract/`** - Source-specific data extraction functions
  - Each source gets its own file (e.g., `redcap.R`, `census.R`)
  - Functions handle API authentication, rate limiting, error handling
  - Return standardized data frames with consistent column naming

- **`/R/harmonize/`** - Data harmonization and integration
  - `schema_mapper/` - Map source schemas to common data model
  - `entity_resolver/` - Match and link participants across sources
  - `temporal_aligner/` - Align data from different time points
  - `vocabulary_standardizer/` - Standardize coded values across sources

- **`/R/graph_api/`** - Microsoft Graph API interface
  - Authentication with Azure AD
  - OneDrive file operations (upload/download DuckDB files)
  - Connection pooling and retry logic

- **`/R/duckdb/`** - DuckDB database operations
  - Connection management (download from OneDrive, local cache)
  - Query builders and executors
  - Schema management and migrations

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

1. **DuckDB over Traditional RDBMS**
   - Columnar storage ideal for analytical queries
   - Excellent compression for cloud storage
   - Native Parquet support
   - ACID compliant

2. **OneDrive via Graph API**
   - University-approved cloud storage
   - Built-in versioning and backup
   - Shared access for research team
   - Integration with Microsoft ecosystem

3. **Multi-Source Harmonization**
   - Common data model across sources
   - Probabilistic record linkage
   - Temporal alignment for longitudinal analysis
   - Standardized vocabularies

4. **R-Based Pipeline**
   - Statistical computing capabilities
   - Rich package ecosystem
   - Familiar to research team
   - Good Graph API and DuckDB support

## Pipeline Execution Order

1. **Extract Phase** (Parallel)
   - Run all source extractors
   - Land raw data in DuckDB

2. **Harmonization Phase** (Sequential)
   - Schema mapping
   - Entity resolution
   - Temporal alignment
   - Vocabulary standardization

3. **Analytics Phase**
   - Update analytical views
   - Generate metrics
   - Quality reports

4. **Sync Phase**
   - Upload DuckDB to OneDrive
   - Update metadata
   - Send notifications

## Environment Setup

Required environment variables:
```
GRAPH_CLIENT_ID=<Azure app registration ID>
GRAPH_CLIENT_SECRET=<Azure app secret>
GRAPH_TENANT_ID=<University tenant ID>
ONEDRIVE_FOLDER_ID=<Target folder in OneDrive>
REDCAP_API_TOKEN=<REDCap API token>
CENSUS_API_KEY=<Census API key>
```

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

### Debugging Pipeline Failures
1. Check logs in pipeline output
2. Verify source API availability
3. Check Graph API authentication
4. Validate schema compatibility
5. Review harmonization rules

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
*Last Updated: September 15, 2025*
*Version: 1.0.0*

## Pipeline Status (September 2025)

### ✅ COMPLETED IMPLEMENTATION
The NE25 pipeline has been fully implemented and tested successfully:

- **Data Extraction**: 3,903 records from 4 REDCap projects
- **PID-based Storage**: Project-specific tables (ne25_raw_pid7679, ne25_raw_pid7943, ne25_raw_pid7999, ne25_raw_pid8014)
- **Data Dictionary Storage**: 1,884 fields with PID references in ne25_data_dictionary table
- **Dashboard Transformations**: Full recode_it() transformations applied (588 variables)
- **Metadata Generation**: 28 comprehensive metadata records in ne25_metadata table
- **Documentation**: Auto-generated Markdown, HTML, and JSON exports

### Key Technical Fixes Applied
1. **Dictionary Conversion**: Added convert_dictionary_to_df() function to handle REDCap API list → dataframe conversion
2. **PID-based Storage**: Implemented project-specific raw data tables by PID
3. **Documentation Pipeline**: Full Python → R integration for multi-format documentation generation
4. **Eligibility Validation**: 9-criteria CID framework with 2,868 eligible participants identified

### Production-Ready Components
- `pipelines/orchestration/ne25_pipeline.R` - Complete pipeline orchestration
- `scripts/documentation/generate_data_dictionary.py` - Python documentation generator
- `R/documentation/generate_data_dictionary.R` - R wrapper functions
- `docs/data_dictionary/` - Auto-generated documentation (MD, HTML, JSON)

### Codebook Management Scripts
- `scripts/codebook/initial_conversion.R` - Convert CSV codebook to JSON format
- `scripts/codebook/update_ne22_irt_parameters.R` - Populate NE22 unidimensional IRT parameters
- `scripts/codebook/update_ps_bifactor_irt.R` - Parse Mplus bifactor output for PS items
- `scripts/codebook/update_ps_studies.R` - Correct PS item study assignments
- `scripts/codebook/assign_ps_domains.R` - Assign multi-domain values to PS items

### Development Notes
- If you persistently run into an error along the lines of "Error: File has been unexpectedly modified", you may need to remake and save over the file
- Python packages required: duckdb, pandas, markdown2 (auto-installed by pipeline)
- Documentation generation works with both 'python' and 'python3' commands
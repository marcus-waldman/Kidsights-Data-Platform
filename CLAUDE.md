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
*Last Updated: [Date]*
*Version: 1.0.0*
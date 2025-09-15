# Kidsights Data Platform

A multi-source data integration platform for longitudinal childhood development research in Nebraska, featuring automated ETL pipelines, data harmonization, and cloud-based analytics using DuckDB on Microsoft OneDrive.

## Overview

The Kidsights Data Platform integrates data from multiple sources to support a comprehensive longitudinal study tracking children from birth to age 6. The platform ensures demographic representativeness by comparing the research sample against Nebraska census data while maintaining high data quality standards.

### Key Features

- **Multi-Source Integration**: REDCap surveys, US Census, healthcare records, education data, childcare provider information
- **Data Harmonization**: Automated entity resolution, temporal alignment, and vocabulary standardization
- **Cloud Architecture**: DuckDB database hosted on University OneDrive, accessed via Microsoft Graph API
- **Population Monitoring**: Real-time comparison against Nebraska demographic targets
- **Longitudinal Support**: Track participants across multiple survey waves over 6 years

## Architecture

```
Data Sources → ETL Pipelines → Harmonization → DuckDB → OneDrive → Graph API → Analytics
```

### Technology Stack

- **Database**: DuckDB (columnar analytical database)
- **Cloud Storage**: Microsoft OneDrive (University account)
- **API Access**: Microsoft Graph API
- **Pipeline Language**: R
- **Configuration**: YAML
- **Authentication**: Azure AD OAuth2

## Project Structure

```
├── R/                      # Core R package functions
│   ├── extract/           # Source-specific extractors
│   ├── harmonize/         # Data integration layer
│   ├── graph_api/         # Microsoft Graph interface
│   ├── duckdb/           # Database operations
│   └── utils/            # Shared utilities
│
├── pipelines/             # ETL pipeline definitions
│   ├── extractors/       # Source extraction pipelines
│   ├── harmonization/    # Integration pipelines
│   └── orchestration/    # Master controllers
│
├── schemas/              # DuckDB schema definitions
│   ├── landing/         # Raw data schemas
│   ├── staging/         # Processing schemas
│   ├── harmonized/      # Integrated schemas
│   └── analytics/       # Analytical views
│
├── config/              # Configuration files
│   └── sources/        # Data source configs
│
├── mappings/           # Harmonization mappings
│   ├── field_mappings/
│   ├── vocabularies/
│   └── linkage_rules/
│
├── cache/             # Local caching
├── tests/            # Test suites
├── scripts/          # Utility scripts
└── docs/            # Documentation
```

## Data Sources

### Primary Sources

1. **REDCap Surveys**
   - Demographics, childcare experiences, child development assessments
   - Caregiver wellbeing, household information
   - Multiple survey waves over 6 years

2. **US Census API**
   - American Community Survey (ACS) 5-year estimates
   - Nebraska demographic benchmarks
   - Geographic reference data (counties, PUMAs)

3. **Healthcare Data**
   - Developmental milestone assessments
   - Immunization records
   - Early intervention services

4. **Education Records**
   - Preschool enrollment
   - Early childhood program participation
   - School readiness assessments

5. **Childcare Provider Data**
   - State licensing information
   - Quality ratings (Step Up to Quality)
   - Provider demographics and capacity

## Quick Start

### Prerequisites

- R >= 4.1.0
- Azure AD application registration
- OneDrive folder with write permissions
- API keys for data sources

### Environment Setup

1. Clone the repository:
```bash
git clone https://github.com/your-org/Kidsights-Data-Platform.git
cd Kidsights-Data-Platform
```

2. Create `.env` file with required credentials:
```env
GRAPH_CLIENT_ID=your-client-id
GRAPH_CLIENT_SECRET=your-client-secret
GRAPH_TENANT_ID=your-tenant-id
ONEDRIVE_FOLDER_ID=your-folder-id
REDCAP_API_TOKEN=your-redcap-token
CENSUS_API_KEY=your-census-key
```

3. Install R dependencies:
```r
install.packages(c("duckdb", "httr2", "dplyr", "yaml", "jsonlite"))
```

4. Initialize database schema:
```r
source("scripts/setup/init_duckdb.R")
```

5. Configure Graph API authentication:
```r
source("scripts/setup/setup_graph_auth.R")
```

## Usage

### Running ETL Pipelines

**Daily Pipeline** (REDCap + incremental updates):
```r
source("pipelines/orchestration/daily_pipeline.R")
```

**Weekly Pipeline** (Full refresh + census data):
```r
source("pipelines/orchestration/weekly_pipeline.R")
```

**Ad-hoc Pipeline** (Specific sources):
```r
source("pipelines/orchestration/adhoc_pipeline.R")
run_pipeline(sources = c("redcap", "childcare"))
```

### Accessing Data

```r
# Connect to DuckDB via Graph API
library(duckdb)
source("R/graph_api/connection.R")

con <- get_duckdb_connection()

# Query harmonized data
participants <- dbGetQuery(con, "
  SELECT * FROM harmonized.participants
  WHERE eligible = TRUE
  AND study_wave = 1
")

# Close connection (uploads changes)
close_duckdb_connection(con)
```

## Data Model

### Core Tables

- `harmonized.participants` - Unified participant records
- `harmonized.children` - Child demographics and development
- `harmonized.caregivers` - Caregiver information
- `harmonized.assessments` - All assessment data
- `analytics.cohorts` - Study cohort definitions
- `analytics.census_comparison` - Sample vs population metrics

### Key Variables

See `/docs/data_dictionary/` for complete variable definitions.

## Development

### Adding a New Data Source

1. Create extractor: `/R/extract/new_source.R`
2. Add pipeline: `/pipelines/extractors/new_source/`
3. Define schema: `/schemas/landing/new_source.sql`
4. Create mappings: `/mappings/field_mappings/new_source_to_core.json`
5. Add config: `/config/sources/new_source.yaml`
6. Write tests: `/tests/unit/test_extractors/test_new_source.R`

### Testing

```r
# Run unit tests
testthat::test_dir("tests/unit/")

# Run integration tests
testthat::test_dir("tests/integration/")
```

## Configuration

Primary configuration files:

- `/config/graph_api.yaml` - Microsoft Graph settings
- `/config/duckdb.yaml` - Database configuration
- `/config/sources/` - Individual source configurations
- `/config/orchestration.yaml` - Pipeline scheduling

## Security

- All credentials stored as environment variables
- Azure AD OAuth2 for Graph API authentication
- Row-level security in DuckDB
- Audit logging for all data access
- HIPAA-compliant data handling

## Monitoring

- Pipeline execution logs in console output
- Data quality metrics in `analytics.data_quality` view
- Source availability tracking
- Harmonization success rates

## Support

- Technical Documentation: `/docs/`
- Architecture Guide: `/CLAUDE.md`
- Issue Tracking: GitHub Issues
- Contact: kidsights-data@university.edu

## License

Copyright (c) 2024 University of Colorado Anschutz Medical Center

This project is licensed under the MIT License - see LICENSE file for details.

## Acknowledgments

- Kidsights Research Team
- University IT Services
- Nebraska Department of Health and Human Services
- Participating families and caregivers

---

*For detailed development guidelines and architecture documentation, see [CLAUDE.md](./CLAUDE.md)*
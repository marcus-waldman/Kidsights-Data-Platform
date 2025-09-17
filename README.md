# Kidsights Data Platform

A multi-source ETL architecture for the Kidsights longitudinal childhood development study in Nebraska, extracting data from REDCap projects and storing in DuckDB for analysis.

## Overview

The Kidsights Data Platform provides automated data extraction, validation, and storage for the Nebraska 2025 (NE25) childhood development study. The platform:

- Extracts data from multiple REDCap projects via API
- Validates participant eligibility using 9 criteria (CID1-CID9)
- Harmonizes data types across different project sources
- Applies dashboard-style transformations for standardized variables
- Stores processed data in DuckDB on OneDrive for analysis
- Generates comprehensive metadata and documentation
- Maintains audit logs of all pipeline executions

## Architecture

```
REDCap Projects (4) → API Extraction → Type Harmonization → Dashboard Transforms → DuckDB Storage
     ↓                     ↓                 ↓                    ↓                   ↓
- Project 7679         - REDCapR           - flexible_bind    - recode_it()       - ne25_raw
- Project 7943         - Secure tokens     - Type conversion  - Race/ethnicity   - ne25_transformed
- Project 7999         - Rate limiting     - Field mapping    - Education cats   - ne25_metadata
- Project 8014                                                - Age groups       - ne25_data_dictionary
```

## Database Location

Data is stored in DuckDB at:
```
C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB/kidsights.duckdb
```

## Quick Start

### Prerequisites

- R 4.4.3+ installed at `C:/Program Files/R/R-4.4.3/bin`
- Required R packages: `dplyr`, `yaml`, `REDCapR`, `duckdb`, `DBI`
- Python 3.13+ with packages: `duckdb`, `pandas`, `markdown2`
- Access to REDCap API credentials file
- OneDrive folder access for database storage

### Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd Kidsights-Data-Platform
   ```

2. **Configure API credentials** (see [API Setup Guide](docs/api-setup.md)):
   - Ensure `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv` exists
   - File should contain columns: `project`, `pid`, `api_code`

3. **Run the NE25 pipeline:**
   ```r
   # From R console
   source("run_ne25_pipeline.R")

   # Or from command line
   "C:/Program Files/R/R-4.4.3/bin/Rscript.exe" run_ne25_pipeline.R
   ```

### Expected Output

A successful run will:
- Extract 3,903 records from 4 REDCap projects
- Store data in DuckDB tables: `ne25_raw`, `ne25_transformed`, `ne25_metadata`
- Generate comprehensive documentation in multiple formats
- Display execution metrics and database summary
- Create pipeline execution log entry

## Codebook System

The platform includes a comprehensive JSON-based codebook system for managing item metadata across multiple studies:

### Features
- **306 Items**: Comprehensive metadata for items from 8 studies with complete IRT parameters
- **NE22 IRT Parameters**: 203 items with empirical unidimensional IRT estimates
- **Bifactor Model**: 44 PS items with factor loadings from Mplus output
- **Interactive Dashboard**: Quarto-based web explorer with dark mode at `docs/codebook_dashboard/`
- **R API**: Complete function library for querying and analysis
- **Multiple Studies**: NE25, NE22, NE20, CAHMI22, CAHMI21, ECDI, CREDI
- **Multi-domain Support**: Array-based domain assignments for psychosocial items

### Quick Start
```r
# Load codebook
source("R/codebook/load_codebook.R")
source("R/codebook/query_codebook.R")
codebook <- load_codebook("codebook/data/codebook.json")

# Query items
motor_items <- filter_items_by_domain(codebook, "motor")
ps_items <- filter_items_by_study(codebook, "NE25")  # Includes 46 PS items
item_details <- get_item(codebook, "PS001")

# Access IRT parameters
ps018 <- get_item(codebook, "PS018")
thresholds <- ps018$psychometric$irt_parameters$NE22$thresholds  # [-1.418, 0.167]
```

### Recent v2.6 Updates
- **IRT Integration**: NE22 unidimensional and bifactor model parameters
- **Array Format**: Clean threshold storage as `[-1.418, 0.167]`
- **Multi-domain PS Items**: Bifactor loadings mapped to multiple psychosocial domains
- **Corrected Studies**: All PS items properly assigned to NE25/NE22/NE20
- **Special Cases**: PS033 with NE22/NE20 only and reverse scoring
- **Response Scale**: ps_frequency (Never/Sometimes/Often/Don't Know)

See `codebook/README.md` for detailed documentation.

## Project Structure

```
Kidsights-Data-Platform/
├── run_ne25_pipeline.R           # Main execution script
├── config/
│   ├── sources/
│   │   └── ne25.yaml             # Pipeline configuration
│   └── codebook_config.yaml      # Codebook validation rules
├── codebook/
│   ├── data/
│   │   └── codebook.json         # JSON codebook (305 items)
│   └── dashboard/                # Quarto dashboard files
├── pipelines/
│   └── orchestration/
│       └── ne25_pipeline.R       # Core pipeline orchestration
├── R/
│   ├── extract/
│   │   └── ne25.R               # REDCap extraction functions
│   ├── harmonize/
│   │   └── ne25_eligibility.R   # Eligibility validation logic
│   ├── transform/
│   │   ├── ne25_transforms.R    # Dashboard-style transformations
│   │   └── ne25_metadata.R      # Metadata generation
│   ├── codebook/                # Codebook R functions
│   │   ├── load_codebook.R      # Loading and initialization
│   │   ├── query_codebook.R     # Filtering and searching
│   │   ├── validate_codebook.R  # Validation functions
│   │   └── visualize_codebook.R # Plotting functions
│   ├── duckdb/
│   │   ├── connection.R         # Database operations
│   │   └── data_dictionary.R    # Dictionary storage functions
│   └── documentation/
│       └── generate_data_dictionary.R  # R wrapper for docs
├── scripts/
│   ├── documentation/
│   │   └── generate_data_dictionary.py # Python doc generator
│   └── codebook/
│       └── initial_conversion.R      # CSV to JSON conversion
├── schemas/
│   └── landing/
│       └── ne25.sql            # DuckDB table definitions
└── docs/                       # Auto-generated documentation
    └── data_dictionary/
        ├── ne25_data_dictionary_full.md    # Complete data dictionary
        ├── ne25_data_dictionary_full.html  # Web-viewable version
        └── ne25_metadata_export.json       # Machine-readable metadata
```

## Key Features

### Secure Credential Management
- API tokens stored in separate CSV file (not in git)
- Environment variables used for secure token access
- No hardcoded credentials in source code

### Type Harmonization
- Uses `flexible_bind_rows` function to handle type mismatches
- Automatic conversion hierarchy: datetime → character → numeric
- Handles differences between REDCap project schemas

### Dashboard-Style Transformations
- Full `recode_it()` transformations applied
- Race/ethnicity harmonization with standardized categories
- Education level categorization (4, 6, and 8-category systems)
- Age calculations and groupings
- Income and Federal Poverty Level calculations
- Caregiver relationship mapping

### Eligibility Validation
- 9-criteria validation system (CID1-CID9)
- Compensation acknowledgment, consent, age, residence checks
- Quality control and survey completion validation
- 2,868 eligible participants identified from 3,903 total records

### Comprehensive Documentation
- Auto-generated data dictionary in Markdown, HTML, and JSON formats
- 28 variables with complete metadata including value labels
- Summary statistics and missing data percentages
- Documentation integrated into pipeline execution

### Audit Trail
- Complete execution logging in `ne25_pipeline_log` table
- Metrics tracking: extraction time, processing counts, errors
- Success/failure status with detailed error messages

## Data Tables

| Table | Records | Purpose |
|-------|---------|---------|
| `ne25_raw` | 3,903 | Combined raw data from all projects |
| `ne25_raw_pid7679` | 322 | Project-specific raw data (kidsights_data_survey) |
| `ne25_raw_pid7943` | 737 | Project-specific raw data (kidsights_email_registration) |
| `ne25_raw_pid7999` | 716 | Project-specific raw data (kidsights_public) |
| `ne25_raw_pid8014` | 2,128 | Project-specific raw data (kidsights_public_birth) |
| `ne25_eligibility` | 3,903 | Eligibility validation results |
| `ne25_transformed` | 3,903 | Dashboard-style transformed data |
| `ne25_data_dictionary` | 1,884 | REDCap field definitions with PID references |
| `ne25_metadata` | 28 | Comprehensive variable metadata |
| `ne25_pipeline_log` | Per run | Execution history and metrics |

## Configuration

The pipeline is configured via `config/sources/ne25.yaml`:

```yaml
redcap:
  url: "https://redcap.ucdenver.edu/api/"
  api_credentials_file: "C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv"
  projects:
    - name: "kidsights_data_survey"
      pid: 7679
      token_env: "KIDSIGHTS_API_TOKEN_7679"
    # ... additional projects
```

## Recent Updates (September 2025)

✅ **FULLY IMPLEMENTED AND TESTED**

The NE25 pipeline is now production-ready with all major components working:

- **3,903 records** successfully extracted from 4 REDCap projects
- **Dashboard-style transformations** applied (588 variables created)
- **PID-based storage** implemented for project-specific data tables
- **1,884 data dictionary fields** stored with project references
- **28 comprehensive metadata records** with value labels and statistics
- **Multi-format documentation** auto-generated (Markdown, HTML, JSON)
- **Eligibility validation** working (2,868 eligible participants identified)

### Database Tables Created

| Table | Records | Purpose |
|-------|---------|---------|
| ne25_raw | 3,903 | Combined raw data |
| ne25_raw_pid7679/7943/7999/8014 | 322/737/716/2128 | Project-specific raw data |
| ne25_eligibility | 3,903 | Eligibility validation results |
| ne25_transformed | 3,903 | Dashboard-style transformed data |
| ne25_data_dictionary | 1,884 | REDCap field definitions with PID |
| ne25_metadata | 28 | Comprehensive variable metadata |

### Auto-Generated Documentation

The pipeline automatically creates:
- `docs/data_dictionary/ne25_data_dictionary_full.md` - Complete data dictionary
- `docs/data_dictionary/ne25_data_dictionary_full.html` - Web-viewable version
- `docs/data_dictionary/ne25_metadata_export.json` - Machine-readable metadata

### Future Enhancements
- Automated scheduling capabilities
- Additional data quality checks
- Graph API integration for OneDrive sync
- Census data integration

## Troubleshooting

### Common Issues

1. **API Token Errors**: Verify credentials file exists and contains valid tokens
2. **Database Connection**: Ensure OneDrive folder is accessible and synced
3. **Type Mismatches**: Check that all REDCap projects use consistent field types
4. **Rate Limiting**: Pipeline includes 1-second delays between API calls
5. **Python Dependencies**: Run `pip install duckdb pandas markdown2` if needed

### Getting Help

- Check the [Troubleshooting Guide](docs/troubleshooting.md)
- Review pipeline logs in DuckDB: `SELECT * FROM ne25_pipeline_log ORDER BY execution_date DESC`
- Examine error messages in console output
- Review generated documentation in `docs/data_dictionary/`

## Development Notes

### Relationship to Dashboard
This pipeline extracts the transformation logic from the existing Kidsights Dashboard (`C:/Users/waldmanm/git-repositories/Kidsights-Data-Dashboard`) but stores data persistently in DuckDB rather than extracting live data each time.

### Key Technical Components
- **REDCap Integration**: Uses REDCapR package with secure API token management
- **Data Harmonization**: Implements dashboard's `recode_it()` transformation functions
- **Metadata Generation**: Creates comprehensive variable documentation with value labels
- **Documentation Pipeline**: Python-R integration for multi-format output generation

## Contributing

1. Follow existing code patterns and documentation standards
2. Test changes against all 4 REDCap projects
3. Update documentation for any configuration changes
4. Ensure API credentials remain secure

## License

[Add license information]

---

**Last Updated**: September 15, 2025
**Pipeline Version**: 1.0.0
**R Version**: 4.4.3
**Status**: ✅ Production Ready
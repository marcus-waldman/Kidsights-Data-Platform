# Kidsights Data Platform

A multi-source ETL architecture for the Kidsights longitudinal childhood development study in Nebraska, extracting data from REDCap projects and storing in DuckDB for analysis.

## Overview

The Kidsights Data Platform provides automated data extraction, validation, and storage for the Nebraska 2025 (NE25) childhood development study. The platform:

- Extracts data from multiple REDCap projects via API
- Validates participant eligibility using 9 criteria (CID1-CID9)
- Harmonizes data types across different project sources
- Stores processed data in DuckDB on OneDrive for analysis
- Maintains audit logs of all pipeline executions

## Architecture

```
REDCap Projects (4) → API Extraction → Type Harmonization → Eligibility Validation → DuckDB Storage
     ↓                     ↓                 ↓                    ↓                   ↓
- Project 7679         - REDCapR           - flexible_bind    - 9 CID criteria   - ne25_raw
- Project 7943         - Secure tokens     - Type conversion  - Pass/Fail logic  - ne25_eligibility
- Project 7999         - Rate limiting     - Field mapping    - Authenticity     - ne25_harmonized
- Project 8014                                                                   - ne25_pipeline_log
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
- Extract ~3,900+ records from 4 REDCap projects
- Store data in DuckDB tables: `ne25_raw`, `ne25_eligibility`, `ne25_harmonized`
- Display execution metrics and database summary
- Create pipeline execution log entry

## Project Structure

```
Kidsights-Data-Platform/
├── run_ne25_pipeline.R           # Main execution script
├── config/
│   └── sources/
│       └── ne25.yaml             # Pipeline configuration
├── pipelines/
│   └── orchestration/
│       └── ne25_pipeline.R       # Core pipeline orchestration
├── R/
│   ├── extract/
│   │   └── ne25.R               # REDCap extraction functions
│   ├── harmonize/
│   │   └── ne25_eligibility.R   # Eligibility validation logic
│   └── duckdb/
│       └── connection.R         # Database operations
├── schemas/
│   └── landing/
│       └── ne25.sql            # DuckDB table definitions
└── docs/                       # Documentation
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

### Eligibility Validation
- 9-criteria validation system (CID1-CID9)
- Compensation acknowledgment, consent, age, residence checks
- Quality control and survey completion validation

### Audit Trail
- Complete execution logging in `ne25_pipeline_log` table
- Metrics tracking: extraction time, processing counts, errors
- Success/failure status with detailed error messages

## Data Tables

| Table | Purpose | Record Count |
|-------|---------|--------------|
| `ne25_raw` | Original REDCap data with metadata | ~3,900+ |
| `ne25_eligibility` | Eligibility validation results | ~3,900+ |
| `ne25_harmonized` | Transformed data ready for analysis | ~3,900+ |
| `ne25_pipeline_log` | Execution history and metrics | Per run |

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

## Troubleshooting

### Common Issues

1. **API Token Errors**: Verify credentials file exists and contains valid tokens
2. **Database Connection**: Ensure OneDrive folder is accessible and synced
3. **Type Mismatches**: Check that all REDCap projects use consistent field types
4. **Rate Limiting**: Pipeline includes 1-second delays between API calls

### Getting Help

- Check the [Troubleshooting Guide](docs/troubleshooting.md)
- Review pipeline logs in DuckDB: `SELECT * FROM ne25_pipeline_log ORDER BY execution_date DESC`
- Examine error messages in console output

## Development Notes

### Relationship to Dashboard
This pipeline mirrors the extraction logic from the existing Kidsights Dashboard (`C:/Users/waldmanm/git-repositories/Kidsights-Data-Dashboard`) but stores data persistently in DuckDB rather than extracting live data each time.

### Known Issues
- Eligibility validation currently returns 0 for all criteria (needs debugging)
- Some harmonized fields are placeholders pending full transformation logic

### Future Enhancements
- Complete data transformation and harmonization
- Additional data quality checks
- Automated scheduling capabilities
- Data export functionality

## Contributing

1. Follow existing code patterns and documentation standards
2. Test changes against all 4 REDCap projects
3. Update documentation for any configuration changes
4. Ensure API credentials remain secure

## License

[Add license information]

---

**Last Updated**: January 2025
**Pipeline Version**: 1.0.0
**R Version**: 4.4.3
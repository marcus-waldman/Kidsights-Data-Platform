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

**🚀 Python Architecture (September 2025)**: Hybrid R-Python design eliminates segmentation faults

```
REDCap Projects (4) → R: API Extraction → R: Type Harmonization → R: Derived Variables → Python: Database Ops
     ↓                         ↓                     ↓                        ↓                    ↓
- Project 7679             - REDCapR             - flexible_bind         - recode_it()      - Connection mgmt
- Project 7943             - Secure tokens       - Type conversion       - 99 variables     - Error handling
- Project 7999             - Rate limiting       - Field mapping         - 10 categories    - Chunked processing
- Project 8014             - 588 raw vars        - 3,908 records         - Factor levels    - Metadata generation
                                                   ↓                        ↓                    ↓
                                          Raw Data (588 vars)    Transformed Data (609 vars)   DuckDB Storage
                                                                         ↓                         ↓
                                                                - eligible, authentic      - ne25_raw
                                                                - hisp, race, raceG        - ne25_transformed
                                                                - educ_max, educ4_max      - ne25_metadata
                                                                - Reference levels set     - Interactive docs
```

## Database Location

Data is stored locally in DuckDB at:
```bash
# Local database (current)
data/duckdb/kidsights_local.duckdb

# Legacy location (archived)
# C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB/kidsights.duckdb
```

### Migration Notice
> In September 2025, the platform migrated from R DuckDB to Python database operations due to persistent segmentation faults. The new architecture provides 100% reliability while maintaining all functionality.

## Quick Start

### Prerequisites

- **R 4.4.3+** installed at `C:/Program Files/R/R-4.4.3/bin`
- **Required R packages**: `dplyr`, `yaml`, `REDCapR` (Note: `duckdb`, `DBI` no longer needed!)
- **Python 3.13+** with packages: `duckdb`, `pandas`, `pyyaml`, `structlog`
- **Access to REDCap API credentials file**
- **Local storage** for database (OneDrive no longer required)

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
   "C:/Program Files/R/R-4.5.1/bin/Rscript.exe" run_ne25_pipeline.R
   ```

### Expected Output

A successful run will:
- Extract 3,903 records from 4 REDCap projects
- Store data in DuckDB tables: `ne25_raw`, `ne25_transformed`, `ne25_metadata`
- Generate comprehensive documentation in multiple formats
- Display execution metrics and database summary
- Create pipeline execution log entry

## Derived Variables System

The platform includes a sophisticated derived variables system that transforms raw REDCap data into analysis-ready variables. This system creates **99 derived variables** across 10 categories through the `recode_it()` transformation process.

### Key Concepts

**Raw vs. Derived Variables**:
- **Raw Variables**: 588 variables directly extracted from REDCap (original field names and values)
- **Derived Variables**: 21 new variables created by transforming and harmonizing raw data
- **Total Variables**: 609 variables in the final `ne25_transformed` table

**Purpose of Derived Variables**:
- **Statistical Analysis**: Reference levels set for meaningful comparisons
- **Data Harmonization**: Consistent categories across different data sources
- **Missing Data Handling**: Systematic treatment of missing/invalid responses
- **Analysis Flexibility**: Multiple category structures (4, 6, 8 categories) for education

### The 99 Derived Variables

#### **Inclusion & Eligibility (3 variables)**
```r
eligible   # Logical: Meets study inclusion criteria
authentic   # Logical: Passes authenticity screening
include     # Logical: Final inclusion (eligible + authentic)
```

#### **Race & Ethnicity (6 variables)**
```r
# Child demographics
hisp        # Factor: Hispanic/Latino ethnicity
race        # Factor: Race with collapsed categories
raceG       # Factor: Combined race/ethnicity

# Primary caregiver demographics
a1_hisp     # Factor: Caregiver Hispanic/Latino ethnicity
a1_race     # Factor: Caregiver race with collapsed categories
a1_raceG    # Factor: Caregiver combined race/ethnicity
```

#### **Education Levels (12 variables)**
```r
# 8-category education (detailed)
educ_max, educ_a1, educ_a2, educ_mom

# 4-category education (simplified)
educ4_max, educ4_a1, educ4_a2, educ4_mom

# 6-category education (intermediate)
educ6_max, educ6_a1, educ6_a2, educ6_mom
```

#### **Income & Poverty (7 variables)**
```r
income                     # Household annual income (nominal $)
inc99                      # Income adjusted to 1999 dollars
family_size                # Number of people in household
federal_poverty_threshold  # FPL threshold for family size
fpl_derivation_flag        # Flag indicating how FPL was derived
fpl                        # Income as % of FPL
fplcat                     # FPL categories (<100%, 100-199%, etc.)
```

#### **Mental Health Screening (10 variables)**
```r
# PHQ-2 (Depression Screening)
phq2_interest, phq2_depressed, phq2_total, phq2_positive, phq2_risk_cat

# GAD-2 (Anxiety Screening)
gad2_nervous, gad2_worry, gad2_total, gad2_positive, gad2_risk_cat
```

#### **Caregiver Adverse Childhood Experiences (12 variables)**
```r
# Individual ACE items (caregiver's own childhood)
ace_neglect, ace_parent_loss, ace_mental_illness, ace_substance_use,
ace_domestic_violence, ace_incarceration, ace_verbal_abuse,
ace_physical_abuse, ace_emotional_neglect, ace_sexual_abuse

# Composite scores
ace_total       # Total count (0-10)
ace_risk_cat    # Risk category (No ACEs, 1 ACE, 2-3 ACEs, 4+ ACEs)
```

#### **Child Adverse Childhood Experiences (10 variables)**
```r
# Individual ACE items (child's experiences as reported by caregiver)
child_ace_parent_divorce, child_ace_parent_death, child_ace_parent_jail,
child_ace_domestic_violence, child_ace_neighborhood_violence,
child_ace_mental_illness, child_ace_substance_use, child_ace_discrimination

# Composite scores
child_ace_total      # Total count (0-8)
child_ace_risk_cat   # Risk category (No ACEs, 1 ACE, 2-3 ACEs, 4+ ACEs)
```

#### **Childcare Access & Support (21 variables)**
```r
# Access and difficulty finding childcare
# Primary arrangement type, hours, costs
# Quality ratings, subsidy receipt
# Derived: formal care indicator, intensity level
```

#### **Geographic Variables (25 variables)**
```r
# ZIP-based geographic assignments with allocation factors
# PUMA, County, Census Tract, CBSA, Urban/Rural
# School Districts, State Legislative Districts, Congressional Districts
# Native Lands (AIANNH areas)
```

### Transformation Process

The `recode_it()` function orchestrates transformations across 10 categories:

```r
# Apply all transformations
transformed_data <- recode_it(raw_data, redcap_dict)

# Or apply specific categories
race_vars <- recode_it(raw_data, redcap_dict, what = "race")
educ_vars <- recode_it(raw_data, redcap_dict, what = "education")
mental_health_vars <- recode_it(raw_data, redcap_dict, what = "mental health")
```

**Transformation Categories**:
1. **include**: Eligibility determination from 8 CID criteria
2. **race**: Race/ethnicity harmonization with collapsed categories
3. **education**: Education with 3 different category structures
4. **caregiver relationship**: Family structure variables
5. **sex**: Child sex variables
6. **age**: Age calculations in multiple units
7. **income**: Income, CPI adjustment, and Federal Poverty Level categories with derivation flags
8. **geographic**: 25 ZIP-based geographic assignments with allocation factors
9. **mental health**: PHQ-2, GAD-2, caregiver ACEs, child ACEs with clinical cutoffs and risk categories
10. **childcare**: 21 childcare access, cost, quality, and support variables

### Configuration & Documentation

**Configuration**: `config/derived_variables.yaml`
- Complete list of all 21 derived variables
- Variable labels and descriptions
- Transformation category mapping

**Full Documentation**: `R/transform/README.md`
- Detailed transformation logic for each category
- Code examples and usage instructions
- Factor level management and reference categories

**Interactive Documentation**: `docs/data_dictionary/ne25/transformed-variables.html`
- Enhanced factor metadata display
- Value counts and missing data analysis
- Searchable, sortable variable table

### Usage Example

```r
# Load transformed data
library(duckdb)
con <- dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")
transformed_data <- dbGetQuery(con, "SELECT * FROM ne25_transformed")

# Access derived variables
table(transformed_data$raceG)          # Race/ethnicity distribution
table(transformed_data$educ4_max)      # Education levels (4 categories)
summary(transformed_data$include)      # Final inclusion rates

# Use in analysis with proper reference levels
library(broom)
model <- glm(include ~ raceG + educ4_max,
             data = transformed_data,
             family = binomial)
tidy(model)  # Reference levels: "White, non-Hisp." and "College Degree"
```

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
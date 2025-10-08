# Kidsights Data Platform

A comprehensive multi-pipeline data platform for childhood development research, integrating local survey data with national datasets through six independent ETL pipelines for statistical analysis and population-representative weighting.

## Overview

The Kidsights Data Platform is a **6-pipeline data integration system** that combines:

**Local Survey Data:**
- **NE25 Pipeline:** Nebraska 2025 childhood development study (REDCap → DuckDB)

**National Benchmarking Data:**
- **ACS Pipeline:** American Community Survey (IPUMS USA API → DuckDB)
- **NHIS Pipeline:** National Health Interview Survey (IPUMS NHIS API → DuckDB)
- **NSCH Pipeline:** National Survey of Children's Health (SPSS → DuckDB)

**Statistical Infrastructure:**
- **Raking Targets Pipeline:** Population-representative targets for post-stratification weighting
- **Imputation Pipeline:** Multiple imputation for geographic, sociodemographic, and childcare uncertainty

**Platform Capabilities:**
- Automated data extraction from REDCap, IPUMS APIs, and SPSS files
- Hybrid R-Python architecture for statistical computing and database operations
- Multiple imputation with M=5 imputations (14 variables: geography + sociodem + childcare)
- 180 raking targets with 614,400 bootstrap replicates for variance estimation
- DuckDB storage with comprehensive metadata and documentation
- Independent pipelines with shared utilities and consistent patterns

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

## Six Pipeline Architecture

### 1. NE25 Pipeline (Local Survey Data)
**Purpose:** Extract and transform Nebraska 2025 childhood development survey data
**Data Source:** 4 REDCap projects via API
**Output:** 3,908 records, 609 variables with 99 derived variables
**Status:** ✅ Production Ready | 100% reliability
**Documentation:** [docs/architecture/PIPELINE_STEPS.md](docs/architecture/PIPELINE_STEPS.md#ne25-pipeline-steps)

### 2. ACS Pipeline (Census Data)
**Purpose:** Extract census demographics for raking targets
**Data Source:** IPUMS USA API (American Community Survey)
**Output:** State-specific multi-year datasets with metadata
**Status:** ✅ Complete | Smart caching (90+ days)
**Documentation:** [docs/acs/README.md](docs/acs/README.md)

### 3. NHIS Pipeline (National Health Data)
**Purpose:** Benchmarking for maternal mental health and ACEs
**Data Source:** IPUMS Health Surveys API
**Output:** 229,609 records, 66 variables (2019-2024)
**Status:** ✅ Production Ready | PHQ-2, GAD-7, 8 ACE variables
**Documentation:** [docs/nhis/README.md](docs/nhis/README.md)

### 4. NSCH Pipeline (Child Health Data)
**Purpose:** Benchmarking for child health outcomes and ACEs
**Data Source:** National Survey of Children's Health (SPSS files)
**Output:** 284,496 records, 3,780 variables (2017-2023)
**Status:** ✅ Production Ready | 7 years integrated
**Documentation:** [docs/nsch/README.md](docs/nsch/README.md)

### 5. Raking Targets Pipeline (Weighting Infrastructure)
**Purpose:** Generate population-representative targets for post-stratification
**Data Sources:** ACS (25 estimands), NHIS (1 estimand), NSCH (4 estimands)
**Output:** 180 raking targets (30 estimands × 6 age groups)
**Bootstrap:** 614,400 replicates for variance estimation
**Status:** ✅ Production Ready | ~2-3 minute runtime
**Documentation:** [docs/raking/NE25_RAKING_TARGETS_PIPELINE.md](docs/raking/NE25_RAKING_TARGETS_PIPELINE.md)

### 6. Imputation Pipeline (Statistical Utility)
**Purpose:** Multiple imputation for geographic, sociodemographic, and childcare uncertainty
**Data Source:** NE25 transformed data
**Output:** 14 variables, 76,636 rows, M=5 imputations
**Architecture:** 7-stage sequential (Geography → Sociodem → Childcare)
**Status:** ✅ Production Ready | 2-minute runtime, 0% error rate
**Documentation:** [docs/imputation/USING_IMPUTATION_AGENT.md](docs/imputation/USING_IMPUTATION_AGENT.md)

**🔗 Complete Architecture Guide:** [docs/architecture/PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)

---

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

## Imputation Pipeline: Multiple Imputation for Uncertainty

The platform includes a **7-stage sequential imputation pipeline** that generates M=5 imputations for 14 variables, handling uncertainty from geographic ambiguity, missing sociodemographic data, and childcare variables.

### Architecture

**7-Stage Sequential Flow:**
```
Stage 1-3: Geography Imputation (Python)
├── PUMA, County, Census Tract
├── Allocation factor (afact) weighted sampling
└── 25,480 rows across 3 tables

Stage 4: Sociodemographic Imputation (R + Python)
├── MICE imputation using geography as predictors
├── 7 variables: female, raceG, educ_mom, educ_a2, income, family_size, fplcat
└── 26,438 rows across 7 tables

Stage 5-7: Childcare Imputation (R + Python)
├── 3-stage sequential: receives_care → type/hours → derived 10hrs indicator
├── Conditional logic: type/hours only for "Yes" responses
├── Data cleaning: hours capped at 168/week
├── 4 variables: cc_receives_care, cc_primary_type, cc_hours_per_week, childcare_10hrs_nonfamily
└── 24,718 rows across 4 tables

Total: 76,636 rows across 14 tables | Runtime: 2.0 minutes | Error Rate: 0%
```

### Usage Examples

**Python - Get Complete Dataset:**
```python
from python.imputation.helpers import get_complete_dataset, get_childcare_imputations

# Get imputation m=1 with all 14 variables
df = get_complete_dataset(study_id='ne25', imputation_number=1)

# Get just childcare variables (4 variables)
childcare = get_childcare_imputations(study_id='ne25', imputation_number=1)
```

**R - Survey Analysis with Multiple Imputation:**
```r
source("R/imputation/helpers.R")
library(survey); library(mitools)

# Get all M=5 imputations for mitools
imp_list <- get_imputation_list(study_id = 'ne25')

# Create survey designs
designs <- lapply(imp_list, function(df) {
  svydesign(ids=~1, weights=~weight, data=df)
})

# Estimate with Rubin's rules
results <- lapply(designs, function(d) svymean(~childcare_10hrs_nonfamily, d))
combined <- MIcombine(results)
summary(combined)  # Proper MI variance from geographic + substantive uncertainty
```

### Key Features

- **Sequential Chained Imputation:** Geography → Sociodem → Childcare ensures proper uncertainty propagation
- **Multi-Study Support:** Independent pipelines for ne25, ia26, co27 with shared helpers
- **Variable-Specific Storage:** Normalized tables (`{study_id}_imputed_{variable}`)
- **Defensive Programming:** NULL filtering, outlier cleaning, conditional logic
- **Statistical Validation:** Complete diagnostics (variance checks, predictor relationships, plausibility)

**📖 Documentation:**
- [USING_IMPUTATION_AGENT.md](docs/imputation/USING_IMPUTATION_AGENT.md) - User guide with 3 use cases
- [PIPELINE_TEST_REPORT.md](docs/imputation/PIPELINE_TEST_REPORT.md) - Production validation
- [ADDING_NEW_STUDY.md](docs/imputation/ADDING_NEW_STUDY.md) - Multi-study onboarding

---

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
├── run_ne25_pipeline.R                   # NE25 pipeline orchestrator
│
├── config/                               # Configuration files
│   ├── sources/
│   │   ├── ne25.yaml                     # NE25 pipeline config
│   │   ├── acs/                          # ACS state-specific configs
│   │   ├── nhis/                         # NHIS year-specific configs
│   │   └── nsch/                         # NSCH config
│   ├── imputation/                       # Imputation configs per study
│   │   └── ne25_config.yaml
│   └── codebook_config.yaml              # Codebook validation
│
├── pipelines/
│   ├── orchestration/                    # Pipeline orchestrators
│   │   ├── run_ne25_pipeline.R
│   │   ├── run_acs_pipeline.R
│   │   └── run_nhis_pipeline.R
│   └── python/                           # Python pipeline scripts
│       ├── acs/                          # ACS extraction & loading
│       ├── nhis/                         # NHIS extraction & loading
│       └── nsch/                         # NSCH SPSS processing
│
├── scripts/                              # Utilities and maintenance
│   ├── imputation/                       # Imputation pipeline
│   │   ├── 00_setup_imputation_schema.py
│   │   └── ne25/                         # Study-specific (7 stages)
│   │       ├── run_full_imputation_pipeline.R
│   │       ├── 01_impute_geography.py
│   │       ├── 02_impute_sociodemographic.R
│   │       ├── 03a_impute_cc_receives_care.R
│   │       └── ... (4 more childcare scripts)
│   ├── raking/ne25/                      # Raking targets pipeline
│   │   ├── run_raking_targets_pipeline.R
│   │   └── ... (21 estimation scripts)
│   ├── nsch/                             # NSCH utilities
│   │   └── process_all_years.py
│   └── documentation/
│       └── generate_data_dictionary.py
│
├── python/                               # Python modules
│   ├── db/                               # Database operations
│   │   ├── connection.py
│   │   └── operations.py
│   ├── imputation/                       # Imputation helpers
│   │   ├── config.py
│   │   └── helpers.py                    # get_completed_dataset(), etc.
│   ├── acs/                              # ACS-specific modules
│   ├── nhis/                             # NHIS-specific modules
│   └── nsch/                             # NSCH-specific modules
│
├── R/                                    # R functions
│   ├── extract/                          # Data extraction
│   │   └── ne25.R
│   ├── transform/                        # Transformations
│   │   └── ne25_transforms.R
│   ├── imputation/                       # Imputation helpers (R)
│   │   └── helpers.R                     # Via reticulate
│   ├── load/                             # Data loading
│   │   ├── acs/
│   │   ├── nhis/
│   │   └── nsch/
│   ├── codebook/                         # Codebook R functions
│   └── utils/                            # Utilities
│       ├── acs/
│       ├── nhis/
│       └── nsch/
│
├── codebook/                             # Codebook system
│   ├── data/codebook.json                # 306 items, 8 studies
│   └── dashboard/                        # Quarto dashboard
│
├── data/                                 # Data storage (gitignored)
│   ├── duckdb/
│   │   └── kidsights_local.duckdb        # Main database
│   ├── acs/{state}/{year_range}/         # ACS raw data
│   ├── nhis/{year_range}/                # NHIS raw data
│   ├── nsch/{year}/                      # NSCH raw data
│   └── imputation/{study_id}/            # Imputation feather files
│
└── docs/                                 # Documentation
    ├── architecture/                     # Architecture guides
    │   ├── PIPELINE_OVERVIEW.md          # Complete 6-pipeline overview
    │   └── PIPELINE_STEPS.md             # Execution instructions
    ├── imputation/                       # Imputation docs (7 files)
    ├── raking/                           # Raking targets docs
    ├── acs/                              # ACS pipeline docs
    ├── nhis/                             # NHIS pipeline docs
    ├── nsch/                             # NSCH pipeline docs
    └── guides/                           # User guides
```

**📖 Complete Structure:** [docs/DIRECTORY_STRUCTURE.md](docs/DIRECTORY_STRUCTURE.md)

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

## Platform Status (October 2025)

✅ **ALL 6 PIPELINES PRODUCTION READY**

The Kidsights Data Platform is fully operational with complete data integration infrastructure:

### NE25 Pipeline (Local Survey)
- **3,908 records** from 4 REDCap projects with 609 variables (99 derived)
- **100% reliability** after Python migration (eliminated R DuckDB segfaults)
- Dashboard-style transformations with complete missing data handling
- Comprehensive documentation auto-generated (Markdown, HTML, JSON)

### ACS Pipeline (Census Data)
- **State-specific extracts** via IPUMS USA API with metadata integration
- **Smart caching** with SHA256 validation (90+ day retention)
- 3 metadata tables for DDI documentation and transformation tracking
- Ready for raking targets estimation

### NHIS Pipeline (National Health)
- **229,609 records** across 6 annual samples (2019-2024), 66 variables
- Mental health measures: **PHQ-2** (depression), **GAD-7** (anxiety)
- **8 ACE variables** with direct overlap to NE25 for benchmarking
- Production-ready for maternal mental health estimation

### NSCH Pipeline (Child Health)
- **284,496 records** across 7 years (2017-2023), **3,780 unique variables**
- Automated SPSS → Feather → Database pipeline (20 sec per year)
- 36,164 value label mappings for categorical variables
- Ready for child health and ACEs benchmarking

### Raking Targets Pipeline (Weighting)
- **180 raking targets** (30 estimands × 6 age groups)
- **614,400 bootstrap replicates** for ACS variance (Rao-Wu-Yue-Beaumont method)
- Complete database integration with 4 indexes for efficient querying
- ~2-3 minute runtime for full pipeline

### Imputation Pipeline (Statistical Utility)
- **7-stage sequential** imputation: Geography → Sociodem → Childcare
- **14 variables** imputed (3 geography + 7 sociodem + 4 childcare)
- **76,636 rows** across 14 tables, M=5 imputations
- **2-minute runtime**, 0% error rate from fresh database
- Multi-study architecture ready (ne25, ia26, co27)
- Complete statistical validation and diagnostics

### Integration Achievements
- **Unified DuckDB storage** with consistent patterns across pipelines
- **Hybrid R-Python architecture** for statistical computing + database reliability
- **Comprehensive documentation** with architecture guides and user examples
- **Production-ready** for post-stratification weighting implementation

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

## Documentation

### Primary Reference
**[CLAUDE.md](CLAUDE.md)** - Comprehensive platform guide with quick start, coding standards, and all pipeline commands

### Architecture Documentation
- **[PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)** - Complete 6-pipeline architecture, design rationales, integration patterns
- **[PIPELINE_STEPS.md](docs/architecture/PIPELINE_STEPS.md)** - Step-by-step execution instructions for all pipelines
- **[DIRECTORY_STRUCTURE.md](docs/DIRECTORY_STRUCTURE.md)** - Complete directory structure and navigation guide
- **[QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** - Command cheatsheet for all pipelines

### Pipeline-Specific Documentation
- **[docs/acs/](docs/acs/)** - ACS pipeline (IPUMS USA API, metadata system, caching)
- **[docs/nhis/](docs/nhis/)** - NHIS pipeline (mental health, ACEs, multi-year)
- **[docs/nsch/](docs/nsch/)** - NSCH pipeline (SPSS processing, 7 years, 3,780 variables)
- **[docs/raking/](docs/raking/)** - Raking targets pipeline (180 targets, bootstrap variance)
- **[docs/imputation/](docs/imputation/)** - Imputation pipeline (7 stages, 14 variables, M=5)
  - [USING_IMPUTATION_AGENT.md](docs/imputation/USING_IMPUTATION_AGENT.md) - User guide with examples
  - [ADDING_NEW_STUDY.md](docs/imputation/ADDING_NEW_STUDY.md) - Multi-study onboarding

### Developer Guides
- **[CODING_STANDARDS.md](docs/guides/CODING_STANDARDS.md)** - R namespacing, Windows console output, file naming
- **[MISSING_DATA_GUIDE.md](docs/guides/MISSING_DATA_GUIDE.md)** - Composite variables, missing data handling
- **[PYTHON_UTILITIES.md](docs/guides/PYTHON_UTILITIES.md)** - DatabaseManager, R Executor, utilities
- **[DERIVED_VARIABLES_SYSTEM.md](docs/guides/DERIVED_VARIABLES_SYSTEM.md)** - 99 derived variables breakdown

---

## Contributing

1. Follow existing code patterns and documentation standards
2. Test changes against all pipelines
3. Update documentation for any configuration changes
4. Ensure API credentials remain secure

## License

[Add license information]

---

**Last Updated**: October 7, 2025
**Platform Version**: 2.0.0 (6 pipelines)
**R Version**: 4.5.1 | **Python Version**: 3.13+
**Status**: ✅ All Pipelines Production Ready

**📖 Complete Documentation**: [CLAUDE.md](CLAUDE.md) | [docs/architecture/PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)
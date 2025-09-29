# DuckDB Schema Documentation

This document provides comprehensive documentation of the DuckDB database schema used by the Kidsights NE25 pipeline.

## Database Overview

**Database Location**: `C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB/kidsights.duckdb`

**Database Type**: DuckDB (columnar analytical database)

**Schema File**: `schemas/landing/ne25.sql`

The database stores data from the Nebraska 2025 (NE25) childhood development study, including raw REDCap data, eligibility validation results, harmonized datasets, and pipeline execution logs.

## Table Structure

### Core Data Tables

| Table | Purpose | Records | Key Fields |
|-------|---------|---------|------------|
| `ne25_raw` | Original REDCap data with metadata | ~3,900+ | `record_id`, `pid`, `retrieved_date` |
| `ne25_eligibility` | Eligibility validation results | ~3,900+ | `record_id`, `pid`, `pass_cid1-9`, `include` |
| `ne25_harmonized` | Transformed data for analysis | ~3,900+ | `participant_id`, `child_age_group`, `include` |
| `ne25_pipeline_log` | Execution history and metrics | Per run | `execution_id`, `execution_date`, `status` |
| `ne25_data_dictionary` | REDCap field definitions | ~300+ | `field_name`, `field_type`, `field_label` |

## Table Schemas

### 1. ne25_raw

**Purpose**: Stores original REDCap data with extraction metadata

**Primary Key**: Composite (`record_id`, `pid`, `retrieved_date`)

**Key Columns**:

#### REDCap Identifiers
```sql
record_id INTEGER,                    -- REDCap record ID
pid TEXT,                            -- Project ID (7679, 7943, 7999, 8014)
redcap_event_name TEXT,              -- REDCap event name
redcap_survey_identifier TEXT        -- Survey identifier
```

#### Extraction Metadata
```sql
retrieved_date TIMESTAMP,           -- When data was extracted
source_project TEXT,                 -- Project name
extraction_id TEXT                   -- Pipeline execution ID
```

#### Child Demographics
```sql
child_dob DATE,                      -- Child date of birth
age_in_days INTEGER                  -- Child age in days
```

#### Geographic Information
```sql
sq001 TEXT,                          -- ZIP code
fq001 INTEGER,                       -- County code
eqstate INTEGER                      -- State residence (31 = Nebraska)
```

#### Eligibility Fields
```sql
eq001 INTEGER,                       -- Informed consent (1 = Yes)
eq002 INTEGER,                       -- Primary caregiver (1 = Yes)
eq003 INTEGER,                       -- Age 19+ (1 = Yes)
date_complete_check INTEGER          -- Birthday confirmed (1 = Yes)
```

#### Compensation Acknowledgment (CID1)
```sql
state_law_requires_that_kidsights_data_collect_my_name___1 INTEGER,
financial_compensation_be_sent_to_a_nebraska_residential_address___1 INTEGER,
state_law_prohibits_sending_compensation_electronically___1 INTEGER,
kidsights_data_reviews_all_responses_for_quality___1 INTEGER
```

#### Race/Ethnicity (Child and Caregiver)
```sql
-- Child race (checkboxes)
cqr010_1___1 INTEGER,                -- White
cqr010_2___1 INTEGER,                -- Black
cqr010_3___1 INTEGER,                -- Asian Indian
-- ... (additional race categories)
cqr011 INTEGER,                      -- Hispanic/Latino

-- Caregiver race (checkboxes)
sq002_1___1 INTEGER,                 -- White
sq002_2___1 INTEGER,                 -- Black
-- ... (additional race categories)
sq003 INTEGER                        -- Hispanic/Latino
```

#### Processing Metadata
```sql
processed BOOLEAN DEFAULT FALSE,     -- Processing status
processing_errors TEXT,              -- Error messages
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
```

### 2. ne25_eligibility

**Purpose**: Stores eligibility validation results for all participants

**Primary Key**: Composite (`record_id`, `pid`, `retrieved_date`)

**Key Columns**:

#### Individual Eligibility Checks (CID1-CID9)
```sql
pass_cid1 BOOLEAN,                   -- Compensation acknowledgment
pass_cid2 BOOLEAN,                   -- Informed consent
pass_cid3 BOOLEAN,                   -- Caregiver age/status
pass_cid4 BOOLEAN,                   -- Child age (0-6 years)
pass_cid5 BOOLEAN,                   -- Nebraska residence
pass_cid6 BOOLEAN,                   -- ZIP/county match
pass_cid7 BOOLEAN,                   -- Birthday confirmation
pass_cid8 BOOLEAN,                   -- KMT quality
pass_cid9 BOOLEAN                    -- Survey completion
```

#### Category Summaries
```sql
eligibility TEXT,                    -- "Pass"/"Fail" (CID2-CID7)
authenticity TEXT,                   -- "Pass"/"Fail" (CID8-CID9)
compensation TEXT                    -- "Pass"/"Fail" (CID1)
```

#### Overall Flags
```sql
eligible BOOLEAN,                    -- Meets eligibility criteria
authentic BOOLEAN,                   -- Passes authenticity checks
include BOOLEAN                      -- Include in final analysis (eligible AND authentic AND compensation)
```

#### Exclusion Information
```sql
exclusion_reason TEXT,               -- Reason for exclusion if not eligible
eligibility_validated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
```

### 3. ne25_harmonized

**Purpose**: Transformed and harmonized data ready for analysis

**Primary Key**: Composite (`record_id`, `pid`, `retrieved_date`)

**Key Columns**:

#### Core Identifiers
```sql
participant_id TEXT,                 -- Unique participant identifier
survey_event TEXT                    -- Survey event name
```

#### Child Demographics
```sql
child_date_of_birth DATE,           -- Child DOB
child_age_days INTEGER,              -- Age in days
child_age_years REAL,                -- Age in years
child_age_group TEXT,                -- Age category
child_sex TEXT,                      -- Child sex
birth_year INTEGER                   -- Birth year
```

#### Geographic
```sql
zip_code TEXT,                       -- ZIP code
county_name TEXT,                    -- County name
state_residence TEXT                 -- State of residence
```

#### Race/Ethnicity (Child and Caregiver)
```sql
-- Child
child_hisp TEXT,                     -- Hispanic/non-Hispanic
child_race TEXT,                     -- Race (collapsed categories)
child_raceG TEXT,                    -- Combined race/ethnicity

-- Caregiver
caregiver_hisp TEXT,
caregiver_race TEXT,
caregiver_raceG TEXT
```

#### Education (Multiple Category Systems)
```sql
educ4 TEXT,                          -- 4-category education
educ4_mom TEXT,                      -- Mother's education (4-cat)
educ4_max TEXT,                      -- Household max (4-cat)
educ6 TEXT,                          -- 6-category education
educ8 TEXT                           -- 8-category education
```

#### Income and Poverty
```sql
household_income REAL,               -- Household income
household_income_cpi REAL,           -- CPI-adjusted income
family_size INTEGER,                 -- Family size
federal_poverty_level REAL,          -- Federal poverty level
fplcat TEXT                          -- FPL categories
```

#### Survey Completion
```sql
survey_complete BOOLEAN,             -- Survey completion status
modules_completed INTEGER,           -- Number of modules completed
completion_rate REAL                 -- Completion rate
```

#### Inclusion Flags
```sql
eligible BOOLEAN,                    -- Eligibility status
authentic BOOLEAN,                   -- Authenticity status
include BOOLEAN                      -- Final inclusion status
```

#### Census Harmonization
```sql
race_ethnicity_acs TEXT,            -- ACS-compatible race/ethnicity
education_acs TEXT,                  -- ACS-compatible education
poverty_level_acs TEXT               -- ACS-compatible poverty level
```

### 4. ne25_pipeline_log

**Purpose**: Audit trail of all pipeline executions

**Primary Key**: `execution_id`

**Key Columns**:

#### Execution Context
```sql
execution_id TEXT PRIMARY KEY,       -- Unique execution identifier
execution_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
pipeline_type TEXT                   -- 'full', 'incremental', 'test'
```

#### Extraction Metrics
```sql
projects_attempted TEXT[],           -- List of projects attempted
projects_successful TEXT[],          -- List of successful projects
total_records_extracted INTEGER,     -- Total records extracted
extraction_errors TEXT              -- Extraction error messages
```

#### Processing Metrics
```sql
records_processed INTEGER,           -- Records processed
records_eligible INTEGER,            -- Eligible participants
records_authentic INTEGER,           -- Authentic participants
records_included INTEGER             -- Included participants
```

#### Performance Metrics
```sql
extraction_duration_seconds REAL,   -- Time spent on extraction
processing_duration_seconds REAL,   -- Time spent on processing
total_duration_seconds REAL         -- Total execution time
```

#### Status Information
```sql
status TEXT,                         -- 'success', 'partial', 'failed'
error_message TEXT,                  -- Error message if failed
config_version TEXT,                 -- Configuration version
r_version TEXT                       -- R version used
```

### 5. ne25_data_dictionary

**Purpose**: Stores REDCap field definitions and metadata

**Primary Key**: `field_name`

**Key Columns**:
```sql
field_name TEXT PRIMARY KEY,        -- REDCap field name
form_name TEXT,                      -- Form/instrument name
section_header TEXT,                 -- Section header
field_type TEXT,                     -- Field type (text, radio, checkbox, etc.)
field_label TEXT,                    -- Field label/question
select_choices_or_calculations TEXT, -- Options for select fields
field_note TEXT,                     -- Field notes
text_validation_type_or_show_slider_number TEXT, -- Validation rules
text_validation_min TEXT,            -- Minimum value
text_validation_max TEXT,            -- Maximum value
identifier TEXT,                     -- Identifier flag
branching_logic TEXT,                -- Branching logic
required_field TEXT,                 -- Required field flag
custom_alignment TEXT,               -- Custom alignment
question_number TEXT,                -- Question number
matrix_group_name TEXT,              -- Matrix group name
matrix_ranking TEXT,                 -- Matrix ranking
field_annotation TEXT,               -- Field annotations
source_project TEXT,                 -- Source project
created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
```

## Indexes

Performance indexes are created for common query patterns:

### Raw Data Indexes
```sql
CREATE INDEX IF NOT EXISTS idx_ne25_raw_pid ON ne25_raw(pid);
CREATE INDEX IF NOT EXISTS idx_ne25_raw_retrieved_date ON ne25_raw(retrieved_date);
CREATE INDEX IF NOT EXISTS idx_ne25_raw_source_project ON ne25_raw(source_project);
```

### Eligibility Indexes
```sql
CREATE INDEX IF NOT EXISTS idx_ne25_eligibility_include ON ne25_eligibility(include);
CREATE INDEX IF NOT EXISTS idx_ne25_eligibility_pid ON ne25_eligibility(pid);
```

### Harmonized Data Indexes
```sql
CREATE INDEX IF NOT EXISTS idx_ne25_harmonized_include ON ne25_harmonized(include);
CREATE INDEX IF NOT EXISTS idx_ne25_harmonized_pid ON ne25_harmonized(pid);
CREATE INDEX IF NOT EXISTS idx_ne25_harmonized_child_age ON ne25_harmonized(child_age_group);
CREATE INDEX IF NOT EXISTS idx_ne25_harmonized_race ON ne25_harmonized(child_raceG);
```

## Views

### v_ne25_eligible_participants
**Purpose**: Simplified view of eligible participants with key demographics

```sql
CREATE VIEW IF NOT EXISTS v_ne25_eligible_participants AS
SELECT
    h.*,
    e.eligibility,
    e.authenticity,
    e.exclusion_reason
FROM ne25_harmonized h
LEFT JOIN ne25_eligibility e ON h.record_id = e.record_id
    AND h.pid = e.pid
    AND h.retrieved_date = e.retrieved_date
WHERE h.include = TRUE;
```

### v_ne25_recruitment_summary
**Purpose**: Daily recruitment summary by project

```sql
CREATE VIEW IF NOT EXISTS v_ne25_recruitment_summary AS
SELECT
    DATE(retrieved_date) as recruitment_date,
    source_project,
    COUNT(*) as total_recruited,
    COUNT(CASE WHEN include = TRUE THEN 1 END) as eligible_recruited,
    ROUND(100.0 * COUNT(CASE WHEN include = TRUE THEN 1 END) / COUNT(*), 1) as eligibility_rate
FROM ne25_harmonized
GROUP BY DATE(retrieved_date), source_project
ORDER BY recruitment_date DESC;
```

### v_ne25_demographics_summary
**Purpose**: Demographics breakdown of included participants

```sql
CREATE VIEW IF NOT EXISTS v_ne25_demographics_summary AS
SELECT
    child_raceG,
    fplcat,
    educ4_mom,
    child_age_group,
    COUNT(*) as n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as percentage
FROM ne25_harmonized
WHERE include = TRUE
GROUP BY child_raceG, fplcat, educ4_mom, child_age_group
ORDER BY n DESC;
```

## Common Queries

### Check Pipeline Status
```sql
SELECT
    execution_id,
    execution_date,
    status,
    total_records_extracted,
    records_included,
    total_duration_seconds
FROM ne25_pipeline_log
ORDER BY execution_date DESC
LIMIT 5;
```

### Eligibility Summary
```sql
SELECT
    COUNT(*) as total_participants,
    COUNT(CASE WHEN eligible = TRUE THEN 1 END) as eligible,
    COUNT(CASE WHEN authentic = TRUE THEN 1 END) as authentic,
    COUNT(CASE WHEN include = TRUE THEN 1 END) as included,
    ROUND(100.0 * COUNT(CASE WHEN include = TRUE THEN 1 END) / COUNT(*), 1) as inclusion_rate
FROM ne25_eligibility;
```

### Demographics by Project
```sql
SELECT
    source_project,
    COUNT(*) as total_records,
    COUNT(CASE WHEN include = TRUE THEN 1 END) as included_records
FROM ne25_raw r
LEFT JOIN ne25_eligibility e ON r.record_id = e.record_id
    AND r.pid = e.pid
    AND r.retrieved_date = e.retrieved_date
GROUP BY source_project;
```

### Recent Data Quality Check
```sql
SELECT
    DATE(retrieved_date) as extraction_date,
    COUNT(*) as records_extracted,
    COUNT(DISTINCT record_id) as unique_participants,
    COUNT(CASE WHEN processing_errors IS NOT NULL THEN 1 END) as records_with_errors
FROM ne25_raw
WHERE retrieved_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(retrieved_date)
ORDER BY extraction_date DESC;
```

## Data Types and Constraints

### Key Data Types
- **Timestamps**: All use `TIMESTAMP` type with UTC timezone
- **Boolean Flags**: Use `BOOLEAN` type for true/false values
- **Identifiers**: `INTEGER` for numeric IDs, `TEXT` for string IDs
- **Measurements**: `REAL` for continuous variables, `INTEGER` for counts

### Constraint Patterns
- **Primary Keys**: Composite keys using (`record_id`, `pid`, `retrieved_date`)
- **Foreign Keys**: Implicit relationships via matching composite keys
- **Not Null**: Essential fields like `record_id`, `pid` are implicitly required
- **Defaults**: Timestamp fields default to `CURRENT_TIMESTAMP`

## Maintenance and Optimization

### Regular Maintenance Tasks
1. **Index Updates**: Automatic with DuckDB
2. **Statistics Refresh**: Automatic query optimization
3. **Log Cleanup**: Consider archiving old pipeline logs
4. **Schema Evolution**: Update schema file for new fields

### Performance Considerations
- **Columnar Storage**: Optimized for analytical queries
- **Compression**: Automatic compression reduces storage
- **Query Planning**: DuckDB optimizes join orders automatically
- **Memory Usage**: Efficient memory management for large datasets

### Backup Strategy
- **OneDrive Sync**: Automatic cloud backup
- **Export Options**: Can export to Parquet, CSV, or other formats
- **Version Control**: Track schema changes in git

---

**Last Updated**: January 2025
**Schema Version**: 1.0.0
**DuckDB Version**: Compatible with 0.8.0+
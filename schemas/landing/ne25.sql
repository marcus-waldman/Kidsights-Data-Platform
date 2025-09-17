-- NE25 Kidsights DuckDB Schema
-- Database location: C:\Users\waldmanm\OneDrive - The University of Colorado Denver\Kidsights-duckDB\kidsights.duckdb

-- Raw REDCap data landing table
CREATE TABLE IF NOT EXISTS ne25_raw (
    -- REDCap identifiers
    record_id INTEGER,
    pid TEXT,
    redcap_event_name TEXT,
    redcap_survey_identifier TEXT,

    -- Extraction metadata
    retrieved_date TIMESTAMP,
    source_project TEXT,
    extraction_id TEXT,

    -- Child demographics
    child_dob DATE,
    age_in_days INTEGER,

    -- Geographic information
    sq001 TEXT,  -- ZIP code
    fq001 INTEGER,  -- County code
    eqstate INTEGER,  -- State residence

    -- Eligibility fields
    eq001 INTEGER,  -- Informed consent
    eq002 INTEGER,  -- Primary caregiver
    eq003 INTEGER,  -- Age 19+
    date_complete_check INTEGER,  -- Birthday confirmed

    -- Compensation acknowledgment (CID1)
    state_law_requires_that_kidsights_data_collect_my_name___1 INTEGER,
    financial_compensation_be_sent_to_a_nebraska_residential_address___1 INTEGER,
    state_law_prohibits_sending_compensation_electronically___1 INTEGER,
    kidsights_data_reviews_all_responses_for_quality___1 INTEGER,

    -- Child race/ethnicity (checkboxes)
    cqr010_1___1 INTEGER,  -- White
    cqr010_2___1 INTEGER,  -- Black
    cqr010_3___1 INTEGER,  -- Asian Indian
    cqr010_4___1 INTEGER,  -- Chinese
    cqr010_5___1 INTEGER,  -- Filipino
    cqr010_6___1 INTEGER,  -- Japanese
    cqr010_7___1 INTEGER,  -- Korean
    cqr010_8___1 INTEGER,  -- Vietnamese
    cqr010_9___1 INTEGER,  -- Native Hawaiian
    cqr010_10___1 INTEGER, -- Guamanian
    cqr010_11___1 INTEGER, -- Samoan
    cqr010_12___1 INTEGER, -- Other Pacific Islander
    cqr010_13___1 INTEGER, -- American Indian
    cqr010_14___1 INTEGER, -- Middle Eastern
    cqr010_15___1 INTEGER, -- Some other race
    cqr011 INTEGER,  -- Hispanic/Latino

    -- Caregiver race/ethnicity (checkboxes)
    sq002_1___1 INTEGER,  -- White
    sq002_2___1 INTEGER,  -- Black
    sq002_3___1 INTEGER,  -- Asian Indian
    sq002_4___1 INTEGER,  -- Chinese
    sq002_5___1 INTEGER,  -- Filipino
    sq002_6___1 INTEGER,  -- Japanese
    sq002_7___1 INTEGER,  -- Korean
    sq002_8___1 INTEGER,  -- Vietnamese
    sq002_9___1 INTEGER,  -- Native Hawaiian
    sq002_10___1 INTEGER, -- Guamanian
    sq002_11___1 INTEGER, -- Samoan
    sq002_12___1 INTEGER, -- Other Pacific Islander
    sq002_13___1 INTEGER, -- American Indian
    sq002_14___1 INTEGER, -- Middle Eastern
    sq002_15___1 INTEGER, -- Some other race
    sq003 INTEGER,  -- Hispanic/Latino

    -- Reverse coded items
    nom054x INTEGER,
    nom052y INTEGER,
    nom056x INTEGER,

    -- Mailing address
    q1394 TEXT,  -- Address line 1
    q1395 TEXT,  -- Address line 2
    q1396 TEXT,  -- City
    q1397 TEXT,  -- State
    q1398 TEXT,  -- ZIP code

    -- Survey completion
    demographics_complete INTEGER,
    child_demographics_complete INTEGER,
    screening_questions_complete INTEGER,

    -- Raw data preservation (JSON for any additional fields)
    raw_data_json TEXT,

    -- Processing flags
    processed BOOLEAN DEFAULT FALSE,
    processing_errors TEXT,

    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Eligibility results table
CREATE TABLE IF NOT EXISTS ne25_eligibility (
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP,

    -- Individual eligibility checks (CID1-CID9)
    pass_cid1 BOOLEAN,  -- Compensation acknowledgment
    pass_cid2 BOOLEAN,  -- Informed consent
    pass_cid3 BOOLEAN,  -- Caregiver age/status
    pass_cid4 BOOLEAN,  -- Child age
    pass_cid5 BOOLEAN,  -- Nebraska residence
    pass_cid6 BOOLEAN,  -- ZIP/county match
    pass_cid7 BOOLEAN,  -- Birthday confirmation
    pass_cid8 BOOLEAN,  -- KMT quality
    pass_cid9 BOOLEAN,  -- Survey completion

    -- Category summaries
    eligibility TEXT,    -- Pass/Fail
    authenticity TEXT,   -- Pass/Fail
    compensation TEXT,   -- Pass/Fail

    -- Overall flags
    eligible BOOLEAN,
    authentic BOOLEAN,
    include BOOLEAN,

    -- Exclusion reason (if not eligible)
    exclusion_reason TEXT,

    -- Validation metadata
    eligibility_validated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (record_id, pid, retrieved_date)
);

-- Transformed/harmonized data table
CREATE TABLE IF NOT EXISTS ne25_harmonized (
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP,

    -- Core identifiers
    participant_id TEXT,
    survey_event TEXT,

    -- Child demographics
    child_date_of_birth DATE,
    child_age_days INTEGER,
    child_age_years REAL,
    child_age_group TEXT,
    child_sex TEXT,
    birth_year INTEGER,

    -- Geographic
    zip_code TEXT,
    county_name TEXT,
    state_residence TEXT,

    -- Race/ethnicity (child)
    child_hisp TEXT,  -- Hispanic/non-Hispanic
    child_race TEXT,  -- Race (collapsed)
    child_raceG TEXT, -- Combined race/ethnicity

    -- Race/ethnicity (caregiver)
    caregiver_hisp TEXT,
    caregiver_race TEXT,
    caregiver_raceG TEXT,

    -- Education (multiple category systems)
    educ4 TEXT,       -- 4-category
    educ4_mom TEXT,   -- Mother's education (4-cat)
    educ4_max TEXT,   -- Household max (4-cat)
    educ6 TEXT,       -- 6-category
    educ8 TEXT,       -- 8-category

    -- Income and poverty
    household_income REAL,
    household_income_cpi REAL,
    family_size INTEGER,
    federal_poverty_level REAL,
    fplcat TEXT,      -- FPL categories

    -- Caregiver relationships
    caregiver_relationship TEXT,
    is_mother BOOLEAN,
    is_father BOOLEAN,

    -- Survey completion
    survey_complete BOOLEAN,
    modules_completed INTEGER,
    completion_rate REAL,

    -- Mental health scores (placeholder)
    ace_score INTEGER,
    anxiety_score REAL,
    depression_score REAL,

    -- Childcare
    childcare_type TEXT,
    childcare_cost REAL,
    childcare_hours REAL,

    -- Inclusion flags
    eligible BOOLEAN,
    authentic BOOLEAN,
    include BOOLEAN,

    -- Census harmonization variables
    race_ethnicity_acs TEXT,
    education_acs TEXT,
    poverty_level_acs TEXT,

    -- Processing metadata
    transformed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (record_id, pid, retrieved_date)
);

-- Data dictionary table (stores REDCap field definitions)
CREATE TABLE IF NOT EXISTS ne25_data_dictionary (
    field_name TEXT PRIMARY KEY,
    form_name TEXT,
    section_header TEXT,
    field_type TEXT,
    field_label TEXT,
    select_choices_or_calculations TEXT,
    field_note TEXT,
    text_validation_type_or_show_slider_number TEXT,
    text_validation_min TEXT,
    text_validation_max TEXT,
    identifier TEXT,
    branching_logic TEXT,
    required_field TEXT,
    custom_alignment TEXT,
    question_number TEXT,
    matrix_group_name TEXT,
    matrix_ranking TEXT,
    field_annotation TEXT,
    source_project TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Pipeline execution log
CREATE TABLE IF NOT EXISTS ne25_pipeline_log (
    execution_id TEXT PRIMARY KEY,
    execution_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    pipeline_type TEXT,  -- 'full', 'incremental', 'test'

    -- Extraction metrics
    projects_attempted TEXT[],
    projects_successful TEXT[],
    total_records_extracted INTEGER,
    extraction_errors TEXT,

    -- Processing metrics
    records_processed INTEGER,
    records_eligible INTEGER,
    records_authentic INTEGER,
    records_included INTEGER,

    -- Performance metrics
    extraction_duration_seconds REAL,
    processing_duration_seconds REAL,
    total_duration_seconds REAL,

    -- Status
    status TEXT,  -- 'success', 'partial', 'failed'
    error_message TEXT,

    -- Configuration
    config_version TEXT,
    r_version TEXT
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_ne25_raw_pid ON ne25_raw(pid);
CREATE INDEX IF NOT EXISTS idx_ne25_raw_retrieved_date ON ne25_raw(retrieved_date);
CREATE INDEX IF NOT EXISTS idx_ne25_raw_source_project ON ne25_raw(source_project);

CREATE INDEX IF NOT EXISTS idx_ne25_eligibility_include ON ne25_eligibility(include);
CREATE INDEX IF NOT EXISTS idx_ne25_eligibility_pid ON ne25_eligibility(pid);

CREATE INDEX IF NOT EXISTS idx_ne25_harmonized_include ON ne25_harmonized(include);
CREATE INDEX IF NOT EXISTS idx_ne25_harmonized_pid ON ne25_harmonized(pid);
CREATE INDEX IF NOT EXISTS idx_ne25_harmonized_child_age ON ne25_harmonized(child_age_group);
CREATE INDEX IF NOT EXISTS idx_ne25_harmonized_race ON ne25_harmonized(child_raceG);

-- Views for common queries
CREATE VIEW IF NOT EXISTS v_ne25_eligible_participants AS
SELECT
    h.*,
    e.eligibility,
    e.authenticity
FROM ne25_harmonized h
LEFT JOIN ne25_eligibility e ON h.record_id = e.record_id AND h.pid = e.pid AND h.retrieved_date = e.retrieved_date
WHERE h.include = TRUE;

CREATE VIEW IF NOT EXISTS v_ne25_recruitment_summary AS
SELECT
    DATE(retrieved_date) as recruitment_date,
    pid,
    COUNT(*) as total_recruited,
    COUNT(CASE WHEN include = TRUE THEN 1 END) as eligible_recruited,
    ROUND(100.0 * COUNT(CASE WHEN include = TRUE THEN 1 END) / COUNT(*), 1) as eligibility_rate
FROM ne25_harmonized
GROUP BY DATE(retrieved_date), pid
ORDER BY recruitment_date DESC;

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

-- End of schema file
-- Fully transformed data table (output of dashboard transformations)
CREATE TABLE IF NOT EXISTS ne25_transformed (
    -- Core identifiers
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP,

    -- Dashboard-style eligibility flags
    eligible BOOLEAN,
    authentic BOOLEAN,
    include BOOLEAN,

    -- Child demographics (transformed)
    years_old REAL,
    months_old REAL,
    days_old REAL,
    sex TEXT,
    female BOOLEAN,

    -- Race/ethnicity (child) - harmonized
    hisp TEXT,                    -- Hispanic/non-Hispanic
    race TEXT,                    -- Race (collapsed categories)
    raceG TEXT,                   -- Combined race/ethnicity

    -- Race/ethnicity (caregiver) - harmonized
    a1_hisp TEXT,                 -- Primary caregiver Hispanic/Latino
    a1_race TEXT,                 -- Primary caregiver race (collapsed)
    a1_raceG TEXT,                -- Primary caregiver race/ethnicity combined

    -- Caregiver relationships
    relation1 TEXT,               -- Primary caregiver relationship
    relation2 TEXT,               -- Secondary caregiver relationship
    female_a1 BOOLEAN,            -- Primary caregiver is female
    mom_a1 BOOLEAN,               -- Primary caregiver is mother

    -- Education (8 categories)
    educ_max TEXT,                -- Maximum education among caregivers
    educ_a1 TEXT,                 -- Primary caregiver education
    educ_a2 TEXT,                 -- Secondary caregiver education
    educ_mom TEXT,                -- Maternal education

    -- Education (4 categories)
    educ4_max TEXT,               -- Maximum education (4-cat)
    educ4_a1 TEXT,                -- Primary caregiver education (4-cat)
    educ4_a2 TEXT,                -- Secondary caregiver education (4-cat)
    educ4_mom TEXT,               -- Maternal education (4-cat)

    -- Education (6 categories)
    educ6_max TEXT,               -- Maximum education (6-cat)
    educ6_a1 TEXT,                -- Primary caregiver education (6-cat)
    educ6_a2 TEXT,                -- Secondary caregiver education (6-cat)
    educ6_mom TEXT,               -- Maternal education (6-cat)

    -- Age variables
    a1_years_old REAL,            -- Primary caregiver age

    -- Income and federal poverty level
    income REAL,                  -- Household income (nominal)
    inc99 REAL,                   -- Household income (1999 dollars)
    family_size INTEGER,          -- Family size
    federal_poverty_threshold REAL, -- FPL threshold for family size
    fpl REAL,                     -- Income as % of FPL
    fplcat TEXT,                  -- FPL categories

    -- Processing metadata
    transformation_version TEXT,   -- Version of transformation applied
    transformed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (record_id, pid, retrieved_date)
);

-- Variable metadata table (comprehensive metadata for all variables)
CREATE TABLE IF NOT EXISTS ne25_metadata (
    variable_name TEXT PRIMARY KEY,
    category TEXT,                -- Transformation category (race, education, etc.)
    variable_label TEXT,          -- Human-readable description
    data_type TEXT,              -- R data type (factor, numeric, character, logical)
    storage_mode TEXT,           -- Storage mode
    n_total INTEGER,             -- Total observations
    n_missing INTEGER,           -- Missing values
    missing_percentage REAL,     -- Missing percentage
    value_labels TEXT,           -- JSON of value labels for factors
    summary_statistics TEXT,     -- JSON of summary statistics
    min_value REAL,             -- Minimum value (numeric variables)
    max_value REAL,             -- Maximum value (numeric variables)
    mean_value REAL,            -- Mean value (numeric variables)
    unique_values INTEGER,       -- Number of unique values
    transformation_notes TEXT,   -- Notes about transformations applied
    creation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for transformed data
CREATE INDEX IF NOT EXISTS idx_ne25_transformed_include ON ne25_transformed(include);
CREATE INDEX IF NOT EXISTS idx_ne25_transformed_pid ON ne25_transformed(pid);
CREATE INDEX IF NOT EXISTS idx_ne25_transformed_raceG ON ne25_transformed(raceG);
CREATE INDEX IF NOT EXISTS idx_ne25_transformed_educ4_mom ON ne25_transformed(educ4_mom);
CREATE INDEX IF NOT EXISTS idx_ne25_transformed_fplcat ON ne25_transformed(fplcat);

-- Create indexes for metadata
CREATE INDEX IF NOT EXISTS idx_ne25_metadata_category ON ne25_metadata(category);
CREATE INDEX IF NOT EXISTS idx_ne25_metadata_data_type ON ne25_metadata(data_type);

-- Views for transformed data analysis
CREATE VIEW IF NOT EXISTS v_ne25_transformed_summary AS
SELECT
    COUNT(*) as total_participants,
    COUNT(CASE WHEN include = TRUE THEN 1 END) as included_participants,
    ROUND(100.0 * COUNT(CASE WHEN include = TRUE THEN 1 END) / COUNT(*), 1) as inclusion_rate,
    COUNT(DISTINCT raceG) as unique_race_categories,
    COUNT(DISTINCT educ4_mom) as unique_education_categories,
    COUNT(DISTINCT fplcat) as unique_poverty_categories
FROM ne25_transformed;

CREATE VIEW IF NOT EXISTS v_ne25_metadata_summary AS
SELECT
    category,
    COUNT(*) as n_variables,
    COUNT(CASE WHEN data_type = 'factor' THEN 1 END) as n_factors,
    COUNT(CASE WHEN data_type = 'numeric' THEN 1 END) as n_numeric,
    COUNT(CASE WHEN data_type = 'logical' THEN 1 END) as n_logical,
    COUNT(CASE WHEN data_type = 'character' THEN 1 END) as n_character,
    ROUND(AVG(missing_percentage), 2) as avg_missing_pct
FROM ne25_metadata
GROUP BY category
ORDER BY n_variables DESC;

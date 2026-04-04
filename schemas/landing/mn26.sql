-- MN26 (Minnesota 2026) DuckDB Schema
-- Kidsights Data Platform
--
-- Key differences from NE25:
--   - mn26_raw_wide: Original household-level extraction (1 row per household)
--   - mn26_raw: Post-pivot long format (1 row per child, child_num = 1 or 2)
--   - 4 eligibility criteria (vs NE25's 9)
--   - child_num column throughout for multi-child support

-- ============================================================================
-- RAW DATA: Wide format (original REDCap extraction, audit trail)
-- ============================================================================
CREATE TABLE IF NOT EXISTS mn26_raw_wide (
    -- REDCap identifiers
    record_id INTEGER,
    pid TEXT,
    redcap_event_name TEXT,

    -- Extraction metadata
    retrieved_date TIMESTAMP,
    source_project TEXT,
    extraction_id TEXT,

    -- This table stores the raw wide-format REDCap data as-is.
    -- All ~976 columns from REDCap are preserved dynamically
    -- (schema auto-detected from Feather/Parquet import).
    -- Not defining every column here — DuckDB handles dynamic schema.

    -- Processing flags
    processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- RAW DATA: Long format (post-pivot, 1 row per child)
-- ============================================================================
CREATE TABLE IF NOT EXISTS mn26_raw (
    -- Composite unique identifier
    record_id INTEGER,
    pid TEXT,
    child_num INTEGER,  -- 1 or 2

    -- Extraction metadata
    retrieved_date TIMESTAMP,
    source_project TEXT,
    extraction_id TEXT,

    -- After pivot, child 2 columns are renamed to match child 1 names.
    -- All child-level variables (cqr009, cqr010b_*, age_in_days_n, etc.)
    -- refer to THIS child (child_num).
    -- Household-level variables (mn2, cqr003, cqr004, etc.) are duplicated.

    -- Processing flags
    processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- ELIGIBILITY (4 criteria, evaluated per child)
-- ============================================================================
CREATE TABLE IF NOT EXISTS mn26_eligibility (
    record_id INTEGER,
    pid TEXT,
    child_num INTEGER,

    -- Individual eligibility checks
    pass_parent_age BOOLEAN,         -- eq003 == 1 (parent/caregiver >= 19)
    pass_child_age BOOLEAN,          -- age_in_days_n <= 1825 (0-5 years)
    pass_primary_caregiver BOOLEAN,  -- eq002 == 1
    pass_minnesota_residence BOOLEAN, -- mn_eqstate == 1

    -- Overall flag
    eligible BOOLEAN,

    -- Exclusion reason (if not eligible)
    exclusion_reason TEXT,

    -- Validation metadata
    eligibility_validated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (record_id, pid, child_num)
);

-- ============================================================================
-- TRANSFORMED DATA (fully derived variables, 1 row per child)
-- ============================================================================
CREATE TABLE IF NOT EXISTS mn26_transformed (
    -- Composite unique identifier
    record_id INTEGER,
    pid TEXT,
    child_num INTEGER,  -- 1 or 2

    -- Extraction metadata
    retrieved_date TIMESTAMP,
    source_project TEXT,

    -- Eligibility & inclusion flags
    eligible BOOLEAN,
    meets_inclusion BOOLEAN,

    -- Child demographics (derived)
    years_old DOUBLE,
    months_old DOUBLE,
    days_old INTEGER,
    sex TEXT,
    female BOOLEAN,

    -- Child race/ethnicity (derived)
    hisp TEXT,
    race TEXT,
    raceG TEXT,

    -- Caregiver demographics (derived, household-level)
    a1_years_old DOUBLE,
    a1_gender TEXT,       -- from mn2 (Female/Male/Non-binary)
    female_a1 BOOLEAN,
    mom_a1 BOOLEAN,
    a1_hisp TEXT,
    a1_race TEXT,
    a1_raceG TEXT,

    -- Education (derived, 4/6/8 category versions)
    educ_max TEXT,
    educ_a1 TEXT,
    educ_a2 TEXT,
    educ_mom TEXT,

    -- Income/poverty (derived)
    income DOUBLE,
    inc99 DOUBLE,
    family_size INTEGER,
    federal_poverty_threshold DOUBLE,
    fpl DOUBLE,
    fplcat TEXT,

    -- Geographic (derived from crosswalks)
    county TEXT,
    county_name TEXT,
    puma TEXT,
    urban_rural TEXT,
    urban_pct DOUBLE,

    -- Calibrated weight (from raking pipeline, if available)
    calibrated_weight DOUBLE,

    -- Transformation metadata
    transformation_version TEXT,
    transformed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (record_id, pid, child_num)
);

-- ============================================================================
-- DATA DICTIONARY (REDCap metadata)
-- ============================================================================
CREATE TABLE IF NOT EXISTS mn26_data_dictionary (
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
    field_annotation TEXT,
    source_project TEXT,
    is_hidden BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- VARIABLE METADATA
-- ============================================================================
CREATE TABLE IF NOT EXISTS mn26_metadata (
    variable_name TEXT PRIMARY KEY,
    category TEXT,
    variable_label TEXT,
    data_type TEXT,
    storage_mode TEXT,
    n_total INTEGER,
    n_missing INTEGER,
    missing_percentage DOUBLE,
    value_labels TEXT,       -- JSON
    summary_statistics TEXT, -- JSON
    min_value DOUBLE,
    max_value DOUBLE,
    mean_value DOUBLE,
    unique_values INTEGER,
    transformation_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- PIPELINE LOG
-- ============================================================================
CREATE TABLE IF NOT EXISTS mn26_pipeline_log (
    execution_id TEXT PRIMARY KEY,
    step_name TEXT,
    status TEXT,
    records_processed INTEGER,
    duration_seconds DOUBLE,
    error_message TEXT,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Raw wide
CREATE INDEX IF NOT EXISTS idx_mn26_raw_wide_pid ON mn26_raw_wide(pid);
CREATE INDEX IF NOT EXISTS idx_mn26_raw_wide_record ON mn26_raw_wide(record_id);

-- Raw long
CREATE INDEX IF NOT EXISTS idx_mn26_raw_pid ON mn26_raw(pid);
CREATE INDEX IF NOT EXISTS idx_mn26_raw_record ON mn26_raw(record_id);
CREATE INDEX IF NOT EXISTS idx_mn26_raw_child ON mn26_raw(child_num);

-- Eligibility
CREATE INDEX IF NOT EXISTS idx_mn26_eligibility_eligible ON mn26_eligibility(eligible);
CREATE INDEX IF NOT EXISTS idx_mn26_eligibility_pid ON mn26_eligibility(pid);

-- Transformed
CREATE INDEX IF NOT EXISTS idx_mn26_transformed_inclusion ON mn26_transformed(meets_inclusion);
CREATE INDEX IF NOT EXISTS idx_mn26_transformed_pid ON mn26_transformed(pid);
CREATE INDEX IF NOT EXISTS idx_mn26_transformed_child ON mn26_transformed(child_num);
CREATE INDEX IF NOT EXISTS idx_mn26_transformed_raceG ON mn26_transformed(raceG);

-- Metadata
CREATE INDEX IF NOT EXISTS idx_mn26_metadata_category ON mn26_metadata(category);

-- Dictionary
CREATE INDEX IF NOT EXISTS idx_mn26_dictionary_form ON mn26_data_dictionary(form_name);
CREATE INDEX IF NOT EXISTS idx_mn26_dictionary_type ON mn26_data_dictionary(field_type);

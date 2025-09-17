-- Minimal NE25 Schema for Testing
-- Core tables only, no complex views

-- Raw REDCap data landing table
CREATE TABLE IF NOT EXISTS ne25_raw (
    record_id INTEGER,
    pid TEXT,
    redcap_event_name TEXT,
    retrieved_date TIMESTAMP,
    source_project TEXT,
    extraction_id TEXT
);

-- Eligibility results table
CREATE TABLE IF NOT EXISTS ne25_eligibility (
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP,
    eligible BOOLEAN,
    authentic BOOLEAN,
    include BOOLEAN,
    PRIMARY KEY (record_id, pid, retrieved_date)
);

-- Transformed data table
CREATE TABLE IF NOT EXISTS ne25_transformed (
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP,
    transformation_version TEXT,
    transformed_at TIMESTAMP
);

-- Metadata table
CREATE TABLE IF NOT EXISTS ne25_metadata (
    variable_name TEXT PRIMARY KEY,
    variable_label TEXT,
    data_type TEXT,
    category TEXT,
    n_total INTEGER,
    n_missing INTEGER,
    missing_percentage DOUBLE,
    unique_values INTEGER,
    min_value DOUBLE,
    max_value DOUBLE,
    mean_value DOUBLE,
    storage_mode TEXT,
    value_labels TEXT,
    transformation_notes TEXT,
    summary_statistics TEXT,
    creation_date TEXT
);

-- Data dictionary table
CREATE TABLE IF NOT EXISTS ne25_data_dictionary (
    field_name TEXT,
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
    pid TEXT,
    created_at TIMESTAMP
);

-- Project-specific tables (will be created dynamically by pipeline)
CREATE TABLE IF NOT EXISTS ne25_raw_pid7679 (
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ne25_raw_pid7943 (
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ne25_raw_pid7999 (
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ne25_raw_pid8014 (
    record_id INTEGER,
    pid TEXT,
    retrieved_date TIMESTAMP
);

-- Basic indexes
CREATE INDEX IF NOT EXISTS idx_ne25_raw_pid ON ne25_raw(pid);
CREATE INDEX IF NOT EXISTS idx_ne25_eligibility_include ON ne25_eligibility(include);
CREATE INDEX IF NOT EXISTS idx_ne25_metadata_category ON ne25_metadata(category);
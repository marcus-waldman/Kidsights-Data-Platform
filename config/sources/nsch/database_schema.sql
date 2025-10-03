-- NSCH Database Schema
--
-- Schema for National Survey of Children's Health (NSCH) data in DuckDB.
-- This schema stores raw NSCH data and metadata for 2016-2023 survey years.
--
-- Tables:
--   - nsch_{year}_raw: Raw survey data (one table per year, e.g., nsch_2023_raw)
--   - nsch_variables: Variable metadata (labels, types, etc.)
--   - nsch_value_labels: Value-to-label mappings for categorical variables
--   - nsch_crosswalk: Variable harmonization mappings (for future use)
--
-- Author: Kidsights Data Platform
-- Date: 2025-10-03

-- ============================================================================
-- Table: nsch_variables
-- ============================================================================
-- Stores metadata about NSCH variables across all years
-- One row per variable per year

CREATE TABLE IF NOT EXISTS nsch_variables (
    -- Identifiers
    year INTEGER NOT NULL,                  -- Survey year (2016-2023)
    variable_name VARCHAR NOT NULL,         -- Variable name (e.g., "HHID", "SC_AGE_YEARS")

    -- Variable metadata
    variable_label VARCHAR,                 -- Descriptive label from SPSS
    variable_type VARCHAR,                  -- Data type: "numeric", "character", "factor"

    -- Source file information
    source_file VARCHAR,                    -- Original SPSS filename
    position INTEGER,                       -- Column position in dataset (0-indexed)

    -- Metadata timestamp
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Primary key
    PRIMARY KEY (year, variable_name)
);

-- Index for fast lookups by variable name across years
CREATE INDEX IF NOT EXISTS idx_nsch_variables_name ON nsch_variables(variable_name);


-- ============================================================================
-- Table: nsch_value_labels
-- ============================================================================
-- Stores value-to-label mappings for categorical variables
-- Multiple rows per variable (one per value)

CREATE TABLE IF NOT EXISTS nsch_value_labels (
    -- Identifiers
    year INTEGER NOT NULL,                  -- Survey year (2016-2023)
    variable_name VARCHAR NOT NULL,         -- Variable name
    value VARCHAR NOT NULL,                 -- Raw value (stored as string)

    -- Label information
    label VARCHAR NOT NULL,                 -- Descriptive label for value

    -- Metadata timestamp
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Primary key
    PRIMARY KEY (year, variable_name, value),

    -- Foreign key to nsch_variables
    FOREIGN KEY (year, variable_name) REFERENCES nsch_variables(year, variable_name)
);

-- Index for fast lookups by variable
CREATE INDEX IF NOT EXISTS idx_nsch_value_labels_var ON nsch_value_labels(year, variable_name);


-- ============================================================================
-- Table: nsch_crosswalk
-- ============================================================================
-- Stores variable harmonization mappings across years
-- For future harmonization - currently deferred

CREATE TABLE IF NOT EXISTS nsch_crosswalk (
    -- Source variable
    year_from INTEGER NOT NULL,             -- Source year
    variable_from VARCHAR NOT NULL,         -- Source variable name

    -- Target variable
    year_to INTEGER NOT NULL,               -- Target year
    variable_to VARCHAR NOT NULL,           -- Target variable name

    -- Mapping information
    mapping_type VARCHAR,                   -- Type: "exact", "recode", "derived"
    mapping_rules TEXT,                     -- JSON string with transformation rules
    notes TEXT,                             -- Additional notes

    -- Metadata timestamp
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Primary key
    PRIMARY KEY (year_from, variable_from, year_to, variable_to)
);


-- ============================================================================
-- Raw Data Tables (one per year): nsch_{year}_raw
-- ============================================================================
-- Example: nsch_2023_raw, nsch_2022_raw, etc.
--
-- These tables are created dynamically by insert_nsch_database.py
-- Each table contains all 895 variables from the SPSS file
-- All numeric columns stored as DOUBLE
--
-- Schema will be inferred from Feather file during insertion
-- Example structure:
--
-- CREATE TABLE nsch_2023_raw (
--     HHID BIGINT,                        -- Household ID (required, unique)
--     YEAR INTEGER,                       -- Survey year
--     FIPSST INTEGER,                     -- State FIPS code
--     HEIGHT DOUBLE,                      -- Height in inches
--     ... (895 total columns)
-- );
--
-- Notes:
--   - HHID is required and must be non-null
--   - All other columns can be null (missing data)
--   - No explicit PRIMARY KEY (HHID not guaranteed unique across projects)
--   - Index on HHID for fast lookups
--
-- Table creation is handled by:
--   pipelines/python/nsch/insert_nsch_database.py::create_year_table()

-- Index template for raw data tables
-- These are created after data insertion:
--   CREATE INDEX idx_nsch_{year}_raw_hhid ON nsch_{year}_raw(HHID);
--   CREATE INDEX idx_nsch_{year}_raw_year ON nsch_{year}_raw(YEAR);


-- ============================================================================
-- Schema Verification Queries
-- ============================================================================
-- Run these queries to verify schema is correct after creation:

-- 1. Check metadata tables exist
-- SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'nsch_%';

-- 2. Count variables by year
-- SELECT year, COUNT(*) as variable_count FROM nsch_variables GROUP BY year ORDER BY year;

-- 3. Count value labels by year
-- SELECT year, COUNT(*) as label_count FROM nsch_value_labels GROUP BY year ORDER BY year;

-- 4. Check raw data tables
-- SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'nsch_%_raw';

-- 5. Sample data from 2023
-- SELECT * FROM nsch_2023_raw LIMIT 10;


-- ============================================================================
-- Data Deletion Queries (use with caution)
-- ============================================================================
-- Delete all data for a specific year:
--   DELETE FROM nsch_value_labels WHERE year = 2023;
--   DELETE FROM nsch_variables WHERE year = 2023;
--   DROP TABLE IF EXISTS nsch_2023_raw;

-- Delete all NSCH data (full reset):
--   DROP TABLE IF EXISTS nsch_value_labels;
--   DROP TABLE IF EXISTS nsch_variables;
--   DROP TABLE IF EXISTS nsch_crosswalk;
--   DROP TABLE IF EXISTS nsch_2016_raw;
--   DROP TABLE IF EXISTS nsch_2017_raw;
--   DROP TABLE IF EXISTS nsch_2018_raw;
--   DROP TABLE IF EXISTS nsch_2019_raw;
--   DROP TABLE IF EXISTS nsch_2020_raw;
--   DROP TABLE IF EXISTS nsch_2021_raw;
--   DROP TABLE IF EXISTS nsch_2022_raw;
--   DROP TABLE IF EXISTS nsch_2023_raw;

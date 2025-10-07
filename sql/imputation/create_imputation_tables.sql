-- Create imputation tables for Kidsights Data Platform
--
-- This script creates the database schema for storing multiple imputations
-- of variables with missing or uncertain values.
--
-- Design: Variable-specific storage (normalized format)
-- - Each imputed variable gets its own table
-- - Structure: (record_id, imputation_m, value)
-- - Only imputed values stored (observed data remains in base tables)

-- ============================================================================
-- METADATA TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS imputation_metadata (
  study_id VARCHAR NOT NULL,
  variable_name VARCHAR NOT NULL,
  n_imputations INTEGER NOT NULL,
  imputation_method VARCHAR,
  predictors TEXT,  -- JSON array of predictor variables
  created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_by VARCHAR,
  software_version VARCHAR,
  notes TEXT,
  PRIMARY KEY (study_id, variable_name)
);

CREATE INDEX IF NOT EXISTS idx_imputation_metadata_study
  ON imputation_metadata(study_id);

-- ============================================================================
-- GEOGRAPHY IMPUTATION TABLES
-- ============================================================================

-- PUMA (Public Use Microdata Area)
CREATE TABLE IF NOT EXISTS ne25_imputed_puma (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  puma VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_puma_m
  ON ne25_imputed_puma(imputation_m);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_puma_study
  ON ne25_imputed_puma(study_id, pid);


-- County
CREATE TABLE IF NOT EXISTS ne25_imputed_county (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  county VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_county_m
  ON ne25_imputed_county(imputation_m);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_county_study
  ON ne25_imputed_county(study_id, pid);


-- Census Tract
CREATE TABLE IF NOT EXISTS ne25_imputed_census_tract (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  census_tract VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_census_tract_m
  ON ne25_imputed_census_tract(imputation_m);

CREATE INDEX IF NOT EXISTS idx_ne25_imputed_census_tract_study
  ON ne25_imputed_census_tract(study_id, pid);


-- ============================================================================
-- SUBSTANTIVE IMPUTATION TABLES (Placeholders for future use)
-- ============================================================================

-- Example: Income imputation
-- Uncomment when needed
-- CREATE TABLE IF NOT EXISTS imputed_income (
--   record_id INTEGER NOT NULL,
--   imputation_m INTEGER NOT NULL,
--   income DOUBLE,
--   PRIMARY KEY (record_id, imputation_m)
-- );
--
-- CREATE INDEX IF NOT EXISTS idx_imputed_income_m
--   ON imputed_income(imputation_m);


-- Example: Education imputation
-- Uncomment when needed
-- CREATE TABLE IF NOT EXISTS imputed_education (
--   record_id INTEGER NOT NULL,
--   imputation_m INTEGER NOT NULL,
--   education VARCHAR,
--   PRIMARY KEY (record_id, imputation_m)
-- );
--
-- CREATE INDEX IF NOT EXISTS idx_imputed_education_m
--   ON imputed_education(imputation_m);



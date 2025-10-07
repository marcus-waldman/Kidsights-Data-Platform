-- Create sociodemographic imputation tables
--
-- This script creates database tables for storing multiple imputations
-- of sociodemographic variables using CART + Random Forest methods.
--
-- Design: Variable-specific storage (normalized format)
-- - Each imputed variable gets its own table
-- - Structure: (study_id, pid, record_id, imputation_m, value)
-- - Only imputed values stored (observed data remains in ne25_transformed)
--
-- Imputation Method: Chained imputation via mice package
-- - For each geography imputation m (1-5):
--   - Run mice with m=1 using geography from imputation m as fixed auxiliary
--   - Store only originally missing values (50%+ storage efficiency)
--
-- Variables Imputed:
-- 1. sex - Child's sex (Female, Male)
-- 2. raceG - Child's race/ethnicity grouped (7 categories)
-- 3. educ_mom - Maternal education (8 categories, ordinal)
-- 4. educ_a2 - Adult 2 education (8 categories, ordinal)
-- 5. income - Family income in dollars (continuous)
-- 6. family_size - Household size (count: 1-99)
-- 7. fplcat - Federal Poverty Level category (5 levels, DERIVED)

-- ============================================================================
-- SOCIODEMOGRAPHIC IMPUTATION TABLES
-- ============================================================================

-- Female (binary: TRUE/FALSE)
CREATE TABLE IF NOT EXISTS imputed_female (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  female BOOLEAN NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_imputed_female_m
  ON imputed_female(imputation_m);

CREATE INDEX IF NOT EXISTS idx_imputed_female_study
  ON imputed_female(study_id, pid);


-- Race/Ethnicity Grouped (7 categories)
CREATE TABLE IF NOT EXISTS imputed_raceG (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  raceG VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_imputed_raceG_m
  ON imputed_raceG(imputation_m);

CREATE INDEX IF NOT EXISTS idx_imputed_raceG_study
  ON imputed_raceG(study_id, pid);


-- Maternal Education (8 categories, ordinal)
CREATE TABLE IF NOT EXISTS imputed_educ_mom (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  educ_mom VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_imputed_educ_mom_m
  ON imputed_educ_mom(imputation_m);

CREATE INDEX IF NOT EXISTS idx_imputed_educ_mom_study
  ON imputed_educ_mom(study_id, pid);


-- Adult 2 Education (8 categories, ordinal)
CREATE TABLE IF NOT EXISTS imputed_educ_a2 (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  educ_a2 VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_imputed_educ_a2_m
  ON imputed_educ_a2(imputation_m);

CREATE INDEX IF NOT EXISTS idx_imputed_educ_a2_study
  ON imputed_educ_a2(study_id, pid);


-- Family Income (continuous, dollars)
CREATE TABLE IF NOT EXISTS imputed_income (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  income DOUBLE NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_imputed_income_m
  ON imputed_income(imputation_m);

CREATE INDEX IF NOT EXISTS idx_imputed_income_study
  ON imputed_income(study_id, pid);


-- Family Size (count: 1-99)
CREATE TABLE IF NOT EXISTS imputed_family_size (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  family_size INTEGER NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_imputed_family_size_m
  ON imputed_family_size(imputation_m);

CREATE INDEX IF NOT EXISTS idx_imputed_family_size_study
  ON imputed_family_size(study_id, pid);


-- Federal Poverty Level Category (5 levels, DERIVED from income + family_size)
-- Categories: <100% FPL, 100-199% FPL, 200-399% FPL, 400%+ FPL, Missing
CREATE TABLE IF NOT EXISTS imputed_fplcat (
  study_id VARCHAR NOT NULL,
  pid INTEGER NOT NULL,
  record_id INTEGER NOT NULL,
  imputation_m INTEGER NOT NULL,
  fplcat VARCHAR NOT NULL,
  PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

CREATE INDEX IF NOT EXISTS idx_imputed_fplcat_m
  ON imputed_fplcat(imputation_m);

CREATE INDEX IF NOT EXISTS idx_imputed_fplcat_study
  ON imputed_fplcat(study_id, pid);

-- =============================================================================
-- IRT Score Tables - Database Schema
-- =============================================================================
-- Purpose: Create tables for storing IRT-based scores calculated using MAP
--          estimation with latent regression predictors
--
-- Execution: Run via Python (duckdb) or R (duckdb package)
-- Version: 1.0
-- Created: January 4, 2025
--
-- Design Principles:
-- 1. Wide format (one table per scale, multiple factor columns for bifactor)
-- 2. Consistent with imputation pipeline naming (imputation_m)
-- 3. One row per person per imputation (M=5 imputations)
-- 4. Includes both theta (score estimate) and SE (standard error)
-- 5. Multi-study support via study_id
-- =============================================================================

-- -----------------------------------------------------------------------------
-- KIDSIGHTS DEVELOPMENTAL SCORES
-- -----------------------------------------------------------------------------
-- Unidimensional GRM model (203 items, NE22 calibration)
-- Single latent trait: Kidsights developmental ability

CREATE TABLE IF NOT EXISTS ne25_irt_scores_kidsights (
    -- Primary key components
    study_id VARCHAR NOT NULL,
    pid INTEGER NOT NULL,
    record_id INTEGER NOT NULL,
    imputation_m INTEGER NOT NULL,

    -- IRT scores
    theta_kidsights DOUBLE NOT NULL,  -- MAP estimate of latent trait
    se_kidsights DOUBLE NOT NULL,     -- Standard error of MAP estimate

    -- Metadata
    scoring_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    scoring_version VARCHAR DEFAULT '1.0',

    -- Primary key constraint
    PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_kidsights_pid_record
    ON ne25_irt_scores_kidsights (pid, record_id);

CREATE INDEX IF NOT EXISTS idx_kidsights_imputation_m
    ON ne25_irt_scores_kidsights (imputation_m);

CREATE INDEX IF NOT EXISTS idx_kidsights_study
    ON ne25_irt_scores_kidsights (study_id);

-- Comments
COMMENT ON TABLE ne25_irt_scores_kidsights IS
    'IRT scores for Kidsights developmental scale. Unidimensional GRM model with 203 items. Scores calculated using MAP estimation with latent regression (covariates: age_years, female, educ_mom, fpl, primary_ruca + age interactions + log(age+1) for developmental trends).';

COMMENT ON COLUMN ne25_irt_scores_kidsights.theta_kidsights IS
    'MAP estimate of latent developmental ability (higher = more developed). Expected range: approximately -3 to +3 for most children.';

COMMENT ON COLUMN ne25_irt_scores_kidsights.se_kidsights IS
    'Standard error of MAP estimate. Lower SE indicates more precise measurement. Typical range: 0.3 to 1.5.';

COMMENT ON COLUMN ne25_irt_scores_kidsights.imputation_m IS
    'Imputation number (1 to 5). Consistent with imputation pipeline naming. Use for variance estimation via Rubins rules.';

-- -----------------------------------------------------------------------------
-- PSYCHOSOCIAL BIFACTOR SCORES
-- -----------------------------------------------------------------------------
-- Bifactor GRM model (44 items, NE22 calibration)
-- 6 factors: gen (general) + eat + sle + soc + int + ext

CREATE TABLE IF NOT EXISTS ne25_irt_scores_psychosocial (
    -- Primary key components
    study_id VARCHAR NOT NULL,
    pid INTEGER NOT NULL,
    record_id INTEGER NOT NULL,
    imputation_m INTEGER NOT NULL,

    -- General factor (all items load on this)
    theta_gen DOUBLE NOT NULL,        -- General psychosocial problems
    se_gen DOUBLE NOT NULL,

    -- Specific factor 1: Eating problems (4 items)
    theta_eat DOUBLE NOT NULL,
    se_eat DOUBLE NOT NULL,

    -- Specific factor 2: Sleep problems (5 items)
    theta_sle DOUBLE NOT NULL,
    se_sle DOUBLE NOT NULL,

    -- Specific factor 3: Social-emotional problems (7 items)
    theta_soc DOUBLE NOT NULL,
    se_soc DOUBLE NOT NULL,

    -- Specific factor 4: Internalizing problems (8 items)
    theta_int DOUBLE NOT NULL,
    se_int DOUBLE NOT NULL,

    -- Specific factor 5: Externalizing problems (17 items)
    theta_ext DOUBLE NOT NULL,
    se_ext DOUBLE NOT NULL,

    -- Metadata
    scoring_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    scoring_version VARCHAR DEFAULT '1.0',

    -- Primary key constraint
    PRIMARY KEY (study_id, pid, record_id, imputation_m)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_psychosocial_pid_record
    ON ne25_irt_scores_psychosocial (pid, record_id);

CREATE INDEX IF NOT EXISTS idx_psychosocial_imputation_m
    ON ne25_irt_scores_psychosocial (imputation_m);

CREATE INDEX IF NOT EXISTS idx_psychosocial_study
    ON ne25_irt_scores_psychosocial (study_id);

-- Comments
COMMENT ON TABLE ne25_irt_scores_psychosocial IS
    'IRT scores for psychosocial bifactor model. 44 items (ps001-ps049, excluding ps031/ps033) loading on 6 factors: general (all items) + 5 specific factors (eat, sle, soc, int, ext). Scores calculated using MAP estimation with latent regression (covariates: age_years, female, educ_mom, fpl, primary_ruca + age interactions).';

COMMENT ON COLUMN ne25_irt_scores_psychosocial.theta_gen IS
    'General psychosocial problems factor score. All 44 items load on this factor. Higher scores indicate more overall psychosocial difficulties.';

COMMENT ON COLUMN ne25_irt_scores_psychosocial.theta_eat IS
    'Eating/feeding problems specific factor score (4 items). Higher scores indicate more eating difficulties beyond general psychosocial problems.';

COMMENT ON COLUMN ne25_irt_scores_psychosocial.theta_sle IS
    'Sleep problems specific factor score (5 items). Higher scores indicate more sleep difficulties beyond general psychosocial problems.';

COMMENT ON COLUMN ne25_irt_scores_psychosocial.theta_soc IS
    'Social-emotional problems specific factor score (7 items). Higher scores indicate more social-emotional difficulties beyond general psychosocial problems.';

COMMENT ON COLUMN ne25_irt_scores_psychosocial.theta_int IS
    'Internalizing problems specific factor score (8 items). Higher scores indicate more internalizing difficulties (anxiety, withdrawal, etc.) beyond general psychosocial problems.';

COMMENT ON COLUMN ne25_irt_scores_psychosocial.theta_ext IS
    'Externalizing problems specific factor score (17 items). Higher scores indicate more externalizing difficulties (aggression, defiance, etc.) beyond general psychosocial problems.';

COMMENT ON COLUMN ne25_irt_scores_psychosocial.imputation_m IS
    'Imputation number (1 to 5). Consistent with imputation pipeline naming. Use for variance estimation via Rubins rules.';

-- =============================================================================
-- USAGE EXAMPLES
-- =============================================================================

-- Example 1: Get all imputations for a single person (Kidsights)
-- SELECT * FROM ne25_irt_scores_kidsights
-- WHERE study_id = 'ne25' AND pid = 12345 AND record_id = 1
-- ORDER BY imputation_m;

-- Example 2: Get mean score across imputations (Rubin's rules - point estimate)
-- SELECT
--     study_id, pid, record_id,
--     AVG(theta_kidsights) as theta_mean,
--     SQRT(AVG(se_kidsights^2) + VARIANCE(theta_kidsights) * (1 + 1.0/5)) as total_se
-- FROM ne25_irt_scores_kidsights
-- WHERE study_id = 'ne25'
-- GROUP BY study_id, pid, record_id;

-- Example 3: Join with base data (for imputation m=1)
-- SELECT
--     t.pid, t.record_id, t.age_in_days, t.female,
--     k.theta_kidsights, k.se_kidsights
-- FROM ne25_transformed t
-- LEFT JOIN ne25_irt_scores_kidsights k
--     ON t.pid = k.pid AND t.record_id = k.record_id
--     AND k.study_id = 'ne25' AND k.imputation_m = 1;

-- Example 4: Get psychosocial scores for all factors (imputation m=1)
-- SELECT
--     pid, record_id,
--     theta_gen as general_problems,
--     theta_eat as eating_problems,
--     theta_sle as sleep_problems,
--     theta_soc as social_emotional_problems,
--     theta_int as internalizing_problems,
--     theta_ext as externalizing_problems
-- FROM ne25_irt_scores_psychosocial
-- WHERE study_id = 'ne25' AND imputation_m = 1;

-- Example 5: Count scores by imputation (quality check)
-- SELECT
--     imputation_m,
--     COUNT(*) as n_scores,
--     AVG(theta_kidsights) as mean_theta,
--     STDDEV(theta_kidsights) as sd_theta,
--     AVG(se_kidsights) as mean_se
-- FROM ne25_irt_scores_kidsights
-- WHERE study_id = 'ne25'
-- GROUP BY imputation_m
-- ORDER BY imputation_m;

-- =============================================================================
-- VALIDATION QUERIES
-- =============================================================================

-- Check for NULL values (should be none)
-- SELECT imputation_m,
--        SUM(CASE WHEN theta_kidsights IS NULL THEN 1 ELSE 0 END) as null_theta,
--        SUM(CASE WHEN se_kidsights IS NULL THEN 1 ELSE 0 END) as null_se
-- FROM ne25_irt_scores_kidsights
-- GROUP BY imputation_m;

-- Check theta range (should be approximately -4 to +4)
-- SELECT
--     MIN(theta_kidsights) as min_theta,
--     MAX(theta_kidsights) as max_theta,
--     AVG(theta_kidsights) as mean_theta
-- FROM ne25_irt_scores_kidsights;

-- Check SE range (should be positive, typically 0.3 to 1.5)
-- SELECT
--     MIN(se_kidsights) as min_se,
--     MAX(se_kidsights) as max_se,
--     AVG(se_kidsights) as mean_se
-- FROM ne25_irt_scores_kidsights;

-- =============================================================================
-- FUTURE SCALES (Placeholders for Phase 2+)
-- =============================================================================

-- To be added:
-- - ne25_irt_scores_phq2 (depression screening, 2 items)
-- - ne25_irt_scores_gad2 (anxiety screening, 2 items)
-- - ne25_irt_scores_child_aces (child ACEs bifactor, 8 items)
-- - ne25_irt_scores_caregiver_aces (caregiver ACEs bifactor, 10 items)
-- - ne25_irt_scores_credi_sf (CREDI short form, 37 items)
-- - ne25_irt_scores_credi_lf (CREDI long form, 60 items)
-- - ne25_irt_scores_gsed (GSED D-scores, 132 items via dscore package)

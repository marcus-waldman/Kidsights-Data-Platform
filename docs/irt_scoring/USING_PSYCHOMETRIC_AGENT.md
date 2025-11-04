# Using the Psychometric Specialist Agent

**Version:** 1.0
**Last Updated:** January 4, 2025
**Status:** ⚠️ IN DEVELOPMENT - NOT PRODUCTION READY

> **IMPORTANT:** This agent and its workflows are currently in active development. Core functionality has been implemented and tested, but the system has not been validated for production use. Use for development and testing purposes only.

## Overview

The psychometric specialist agent is a domain expert for IRT (Item Response Theory) score construction, psychometric calibration workflows, and codebook maintenance. It provides guided, human-in-the-loop workflows for all psychometric tasks in the Kidsights Data Platform.

### Core Capabilities

The agent specializes in four core areas:

1. **IRT Score Construction** - MAP scoring with latent regression
2. **Codebook Maintenance** - Updating and validating IRT parameters
3. **Calibration Dataset Preparation** - Mplus workflow guidance
4. **GitHub Issue Management** - Feature requests for IRTScoring package

### When to Use This Agent

Use the psychometric specialist when you need to:

- Calculate IRT scores for survey data (MAP estimation)
- Add or update IRT parameters in the codebook
- Prepare datasets for Mplus calibration
- Reconcile Mplus templates with new data
- Draft GitHub issues for missing IRTScoring features
- Validate psychometric parameter structures

### Agent Location

```bash
# Invoke agent from Claude Code
.claude/agents/psychometric-specialist.yaml
```

---

## Capability 1: IRT Score Construction

### Overview

Construct IRT scores using MAP (Maximum A Posteriori) estimation with latent regression. Supports both unidimensional and bifactor models with covariate-adjusted scoring.

### Key Features

- **MAP Estimation:** Individual latent trait estimates with standard errors
- **Latent Regression:** Incorporates covariates (age, demographics, geography)
- **Multiple Imputations:** Scores each imputation separately (M=5 by default)
- **Two Scale Types:**
  - **Kidsights:** Unidimensional developmental scale (203 items)
  - **Psychosocial:** Bifactor model (6 factors: gen + 5 specific)

### Workflow

The agent guides you through:

1. **Configuration Review** - Verify `config/irt_scoring/irt_scoring_config.yaml`
2. **Scale Selection** - Choose kidsights, psychosocial, or both
3. **Covariate Preparation** - Standard set + age interactions + developmental terms
4. **MAP Scoring** - Calls IRTScoring package functions
5. **Database Insertion** - Stores scores in DuckDB tables
6. **Validation** - Checks theta ranges, SE values, row counts

### Standard Covariates

All MAP scoring includes:

**Main Effects:**
- `age_years` - Derived from age_in_days / 365.25
- `female` - Binary gender indicator
- `educ_mom` - Maternal education level
- `fpl` - Federal poverty level ratio
- `primary_ruca` - Rural-urban continuum (1-10)

**Age Interactions:**
- `age_X_female`, `age_X_educ_mom`, `age_X_fpl`, `age_X_primary_ruca`

**Developmental Scales Only:**
- `log_age_plus_1` - Log transformation for developmental trajectories

### Usage Example

```bash
# Run full IRT scoring pipeline (both scales)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_irt_scoring_pipeline.R --scales all

# Run selective execution (kidsights only)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_irt_scoring_pipeline.R --scales kidsights

# Run psychosocial only
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_irt_scoring_pipeline.R --scales psychosocial
```

### Output Tables

**Kidsights Scores:**
```sql
SELECT * FROM ne25_irt_scores_kidsights
-- Columns: study_id, pid, record_id, imputation_m, theta_kidsights, se_kidsights
```

**Psychosocial Scores:**
```sql
SELECT * FROM ne25_irt_scores_psychosocial
-- Columns: study_id, pid, record_id, imputation_m,
--          theta_gen, se_gen (general factor),
--          theta_eat, se_eat (eating problems),
--          theta_sle, se_sle (sleep problems),
--          theta_soc, se_soc (social-emotional),
--          theta_int, se_int (internalizing),
--          theta_ext, se_ext (externalizing)
```

### Troubleshooting

**Issue:** IRTScoring function not found

```r
# Error message will guide you:
"[ERROR] Function 'map_estimate_latent_regression' not found in IRTScoring package
Please create GitHub issue at: https://github.com/marcus-waldman/IRTScoring/issues
Title: Add map_estimate_latent_regression() for MAP scoring with covariates"
```

**Solution:** The agent will help you draft a GitHub issue (see Capability 4).

**Issue:** Covariate missing in data

```r
# Check config matches available data
source("scripts/irt_scoring/helpers/covariate_preparation.R")
result <- get_standard_covariates(data, config, "kidsights")
# Reviews which covariates are available
```

**Issue:** Unexpected theta ranges

- **Normal range:** Typically [-4, 4] for standardized scales
- **Check:** Mean should be ~0, SD should be ~1 if using calibration sample
- **If extreme:** Review item responses for data quality issues

---

## Capability 2: Codebook Maintenance

### Overview

Interactive system for updating IRT parameters in `codebook/data/codebook.json`. All updates include validation, backup, and version tracking.

### Key Features

- **Interactive Workflow:** Step-by-step guided parameter entry
- **Batch Updates:** CSV import for multiple items
- **Validation:** 6 checks before saving (structure, arrays, thresholds, factors, duplicates)
- **Automatic Backup:** Timestamped backups in `codebook/backups/`
- **Version Tracking:** Semantic versioning (MAJOR.MINOR) with changelog
- **Human-in-the-Loop:** All updates require user confirmation

### Workflow Steps

1. **Update Type Selection:** New item / Update params / New calibration / Batch
2. **Study Selection:** NE25, NE22, NE20, or custom study ID
3. **Model Type:** Unidimensional / Bifactor / Multidimensional
4. **Factor Structure:** Specify factor names (e.g., "gen", "eat", "sle")
5. **Parameter Entry:** Interactive or CSV batch
6. **Validation:** Automatic checks before saving
7. **Version Increment:** Changelog entry and version bump
8. **Backup & Save:** Automatic backup then save

### Usage Example

**Interactive Update:**

```r
# Source the update functions
source("R/codebook/update_irt_parameters.R")

# Launch interactive workflow
interactive_parameter_update()

# Follow prompts:
# 1. Update type: [2] Update existing IRT parameters
# 2. Study: NE25
# 3. Model type: [2] Bifactor
# 4. Factors: gen, eat, sle, soc, int, ext
# 5. Parameter entry...
# 6. Validation passes
# 7. Changelog: "Updated NE25 psychosocial parameters after recalibration"
# 8. Backup created, version 2.0 -> 2.1
```

**Batch Update from CSV:**

```r
# CSV format:
# item_id,loading_gen,loading_eat,threshold_1,threshold_2,threshold_3
# ps001,0.45,0.32,-1.418,0.167,1.892
# ps002,0.52,0.28,-0.982,0.445,1.654

# Use batch update option in interactive workflow
# Or call directly:
codebook <- jsonlite::fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)
codebook <- batch_update_from_csv(codebook, study_id = "NE25",
                                   model_type_str = "bifactor",
                                   factors = c("gen", "eat", "sle", "soc", "int", "ext"))
```

**View Version History:**

```r
source("R/codebook/update_irt_parameters.R")
display_version_history("codebook/data/codebook.json")

# Output:
# Current version: 2.1
# Last updated: 2025-01-04 15:30:00
#
# CHANGELOG
# Version 2.1 (2025-01-04 15:30:00)
#   Type: parameter_update
#   Changes: Updated NE25 psychosocial parameters after recalibration
```

### Validation Checks

The system performs 6 validation checks:

1. **JSON Structure:** Required fields (items, id, lexicons, psychometric)
2. **Parameter Arrays:** Loadings count = factors count
3. **Thresholds Ordered:** Ascending order (required for GRM)
4. **Factor Names:** No empty names, consistency within studies
5. **Duplicate Items:** No duplicate lexicon values
6. **Plausibility:** Loadings <10, SE>0, thresholds not empty

### Troubleshooting

**Issue:** Thresholds not in ascending order

```r
# Error:
"Item ps001, study NE25: thresholds not in ascending order (-1.418, 0.167, 1.892)"

# Solution: Check Mplus output for parameter order
# Thresholds must be: threshold_1 < threshold_2 < threshold_3
```

**Issue:** Loading count doesn't match factor count

```r
# Error:
"Item ps001, study NE25: 2 loadings but 6 factors"

# Solution: Bifactor model needs one loading per factor
# Example: gen=0.45, eat=0.32, sle=0, soc=0, int=0, ext=0
```

---

## Capability 3: Calibration Dataset Preparation

### Overview

Prepare datasets for Mplus IRT calibration with automatic variable reconciliation, validation, and syntax generation.

### Key Features

- **Codebook-First Extraction:** Only items with IRT parameters
- **Flexible Filtering:** Sample filters (eligible, authentic, age ranges)
- **Variable Naming:** Automatic (lex_equate uppercase, psychosocial lowercase)
- **Mplus Format:** Free format .dat files, missing as "."
- **Template Reconciliation:** Updates existing Mplus syntax with new variable names
- **Validation:** 5 checks before writing (empty columns, variable names, etc.)

### Workflow Steps

1. **Scale Selection:** Kidsights or psychosocial
2. **Sample Filters:** Standard (eligible, authentic) or custom
3. **Age Range:** Optional age restriction in months
4. **Dataset Extraction:** From database with filtering
5. **Output Paths:** Specify .dat and .inp file locations
6. **Template Decision:** Existing template or from scratch
7. **File Writing:** .dat file + variable names reference
8. **Syntax Creation:** New template or reconciled existing

### Usage Example

**Interactive Workflow:**

```r
# Source helper functions
source("scripts/irt_scoring/prepare_mplus_calibration.R")

# Launch interactive workflow
prepare_mplus_calibration()

# Follow prompts:
# 1. Scale: [1] Kidsights
# 2. Filters: [1] Standard (eligible=TRUE, authentic=TRUE)
# 3. Age range: [2] No restriction
# 4. .dat path: mplus/kidsights_ne25.dat
# 5. Template: [1] Yes, reconcile existing
# 6. Template path: mplus/templates/ne22_kidsights.inp
# 7. .inp path: mplus/kidsights_ne25.inp
```

**Programmatic Usage:**

```r
# Extract dataset
source("scripts/irt_scoring/helpers/mplus_dataset_prep.R")

kidsights_data <- extract_items_for_calibration(
  scale_name = "kidsights",
  sample_filters = list(eligible = TRUE),
  age_range = c(0, 72),  # 0-6 years
  codebook_path = "codebook/data/codebook.json",
  db_path = "data/duckdb/kidsights_local.duckdb"
)

# Write .dat file
source("scripts/irt_scoring/helpers/write_mplus_data.R")

write_dat_file(
  data = kidsights_data,
  output_path = "mplus/kidsights_calibration.dat",
  identifier_cols = c("record_id"),
  validate_before_write = TRUE
)

# Reconcile template
source("scripts/irt_scoring/helpers/modify_mplus_template.R")

item_cols <- setdiff(names(kidsights_data), c("record_id"))

reconcile_template_with_data(
  template_path = "mplus/templates/ne22_kidsights.inp",
  data_varnames = item_cols,
  new_dat_path = "kidsights_calibration.dat",
  output_path = "mplus/kidsights_ne25.inp"
)
```

### Output Files

After workflow completion:

```
mplus/
├── kidsights_ne25.dat              # Data file (whitespace delimited)
├── kidsights_ne25_varnames.txt     # Variable names reference
└── kidsights_ne25.inp              # Mplus syntax (updated or new)
```

### Validation Checks

Before writing .dat files:

1. **Empty Columns:** All-NA columns detected and rejected
2. **Zero Variance:** Constant columns flagged
3. **Variable Names:** Max 8 characters, alphanumeric + underscore
4. **High Missingness:** >50% missing data warnings
5. **Duplicate Names:** No duplicate variable names allowed

### Template Reconciliation

Detects 4 types of mismatches:

1. **Case Differences:** `AA4` (template) vs `aa4` (data) → Updates template
2. **Order Differences:** Variables in different order → Reorders to match data
3. **Missing Variables:** In template but not data → Removes from template
4. **Extra Variables:** In data but not template → Reports for user decision

### Troubleshooting

**Issue:** Most items have 100% missing data

```r
# This means items aren't in the study's dataset
# Check codebook calibration study vs data source

# View items in codebook for study:
source("scripts/irt_scoring/helpers/mplus_dataset_prep.R")
item_info <- get_items_from_codebook("kidsights", "codebook/data/codebook.json")
print(item_info$items)  # Items expected
print(item_info$calibration_study)  # Which study's parameters

# Solution: Use correct study data or update calibration study filter
```

**Issue:** Template has different variable names

```r
# The reconciliation system handles this automatically
# Reviews mismatch report in output

# Example output:
# [WARN] Found 12 case differences:
#   'AA4' (template) vs 'aa4' (data)
# [ACTION NEEDED] Template requires updates:
#   - Update case for 12 variables
```

---

## Capability 4: GitHub Issue Management

### Overview

Draft GitHub issues for missing IRTScoring package features. The agent guides you through creating well-structured feature requests.

### When to Use

Create issues when:

- MAP scoring function doesn't exist
- Bifactor support missing
- Latent regression features needed
- Model types not supported

### Issue Drafting Workflow

1. **Identify Missing Feature:** From error messages in scoring workflow
2. **Use Case Description:** What you're trying to accomplish
3. **Current Behavior:** What happens now (function not found, error message)
4. **Requested Feature:** Specific function signature and behavior
5. **Context:** Example data structure and expected output
6. **Review & Submit:** User reviews draft and submits to GitHub

### Example Issue Draft

**Title:** Add `map_estimate_bifactor_latent_regression()` for bifactor MAP scoring

**Body:**

```markdown
## Use Case
Calculate MAP scores for a bifactor psychometric model (general + specific factors) with covariate adjustment.

## Current Behavior
The IRTScoring package has `map_estimate_latent_regression()` for unidimensional models, but no equivalent for bifactor models.

## Requested Feature
Add function: `map_estimate_bifactor_latent_regression()`

**Signature:**
```r
map_estimate_bifactor_latent_regression <- function(
  item_responses,      # Matrix: N x J items
  loadings,            # Matrix: J x K factors
  thresholds,          # List: length J, each vector of thresholds
  covariates,          # Data frame: N x P covariates
  formula_terms        # Character vector of covariate names
)
```

**Returns:**
```r
# Data frame with columns:
# - theta_factor1, se_factor1
# - theta_factor2, se_factor2
# - ... (one pair per factor)
```

## Context
Working with 6-factor bifactor model (general + 5 specific) from psychosocial scale calibration. Need MAP scores incorporating demographic covariates (age, education, geography).

## Example
```r
# Bifactor model: gen + eat + sle + soc + int + ext
scores <- map_estimate_bifactor_latent_regression(
  item_responses = ps_items,
  loadings = loading_matrix,  # 44 items x 6 factors
  thresholds = threshold_list,
  covariates = covariate_df,
  formula_terms = c("age_years", "female", "educ_mom", "fpl")
)
```
```

### Troubleshooting

**Issue:** Not sure what feature is needed

```r
# Review error message from scoring workflow
# It will suggest feature name and GitHub link

# Example:
# [ERROR] Function 'map_estimate_latent_regression' not found
# Please create issue at: https://github.com/marcus-waldman/IRTScoring/issues
# Suggested title: Add map_estimate_latent_regression() for MAP scoring
```

---

## Integration with Workflows

### Full Workflow: Imputation → Scoring → Analysis

```bash
# Step 1: Run imputation pipeline (Stages 1-11)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R

# Step 2: Run IRT scoring pipeline (Stages 12-13)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_irt_scoring_pipeline.R --scales all

# Step 3: Query scores for analysis
# (See SCORE_DATABASE_SCHEMA.md for example queries)
```

### Recalibration Workflow

```bash
# Step 1: Prepare calibration dataset
source("scripts/irt_scoring/prepare_mplus_calibration.R")
prepare_mplus_calibration()

# Step 2: Run Mplus (external)
# Open mplus/scale_calibration.inp in Mplus software
# Run analysis
# Review output for fit and parameters

# Step 3: Update codebook with new parameters
source("R/codebook/update_irt_parameters.R")
interactive_parameter_update()

# Step 4: Re-run scoring with updated parameters
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_irt_scoring_pipeline.R --scales kidsights
```

---

## Common Tasks

### Task 1: Add Scores for New Study

```r
# 1. Update config/irt_scoring/irt_scoring_config.yaml
study_id: ia26  # Change from ne25

# 2. Ensure codebook has calibration parameters for study
source("R/codebook/update_irt_parameters.R")
interactive_parameter_update()
# Add IA26 calibration parameters

# 3. Run scoring pipeline
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_irt_scoring_pipeline.R --scales all
```

### Task 2: Add New Scale

```r
# 1. Add scale to config/irt_scoring/irt_scoring_config.yaml
scales:
  newscale:
    enabled: true
    model_type: "unidimensional"
    developmental_scale: false
    items: [item1, item2, ...]  # Or use codebook
    calibration_study: "NE22"
    output_table: "ne25_irt_scores_newscale"

# 2. Add calibration parameters to codebook
source("R/codebook/update_irt_parameters.R")
interactive_parameter_update()

# 3. Create scoring script (copy 01_score_kidsights.R as template)
# 4. Create database insertion script (copy 01b_insert_kidsights_scores.py)
# 5. Update run_irt_scoring_pipeline.R to include new scale
```

### Task 3: Change Covariate Set

```r
# Edit config/irt_scoring/irt_scoring_config.yaml
standard_covariates:
  main_effects:
    - age_years
    - female
    - new_covariate  # Add here

  age_interactions:  # Will auto-create age_X_new_covariate
    - new_covariate

# Re-run scoring
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_irt_scoring_pipeline.R --scales all
```

---

## Best Practices

### 1. Always Validate Before Scoring

- Check item response distributions
- Verify covariate availability
- Review missing data patterns
- Confirm IRT parameters in codebook

### 2. Use Selective Execution During Development

```bash
# Test one scale at a time
Rscript run_irt_scoring_pipeline.R --scales kidsights  # Faster iteration
```

### 3. Version Control for Codebook

- Automatic backups in `codebook/backups/`
- Version increments tracked in changelog
- Can revert if needed: copy backup to `codebook/data/codebook.json`

### 4. Document Recalibrations

When updating parameters after Mplus calibration:
- Save Mplus output files in `mplus/output/`
- Document model fit statistics
- Note any modifications to MODEL section
- Record version increment in codebook changelog

### 5. Validate Scores After Generation

```r
# Check distributions
library(duckdb)
conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

scores <- dbGetQuery(conn, "
  SELECT
    AVG(theta_kidsights) as mean_theta,
    STDDEV(theta_kidsights) as sd_theta,
    MIN(theta_kidsights) as min_theta,
    MAX(theta_kidsights) as max_theta
  FROM ne25_irt_scores_kidsights
")

print(scores)
# Expect: mean ~0, sd ~1, range [-4, 4] for standardized scores
```

---

## Troubleshooting Guide

### General Debugging Steps

1. **Check Configuration:** Review `config/irt_scoring/irt_scoring_config.yaml`
2. **Verify Codebook:** Ensure IRT parameters exist for study and scale
3. **Check Data:** Confirm items exist in database table
4. **Review Logs:** Read console output for specific error messages
5. **Test Components:** Run helper functions individually to isolate issue

### Common Error Messages

**"Function not found in IRTScoring package"**
- **Cause:** IRTScoring package missing feature
- **Solution:** Draft GitHub issue (Capability 4)

**"No IRT parameters found for study"**
- **Cause:** Codebook missing calibration for study_id
- **Solution:** Add parameters via interactive_parameter_update()

**"Validation failed: empty columns"**
- **Cause:** Items not in dataset (100% missing)
- **Solution:** Check item mapping or use different calibration study

**"Thresholds not in ascending order"**
- **Cause:** Parameter entry error
- **Solution:** Re-enter with correct threshold order

---

## Additional Resources

- **Configuration Guide:** `docs/irt_scoring/CONFIGURATION_GUIDE.md`
- **Score Database Schema:** `docs/irt_scoring/SCORE_DATABASE_SCHEMA.md`
- **Mplus Workflow:** `docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md`
- **Updating Parameters:** `docs/codebook/UPDATING_IRT_PARAMETERS.md`
- **Pipeline Overview:** `docs/architecture/PIPELINE_OVERVIEW.md`

---

**Questions or Issues?**

Contact the data platform team or create an issue at the repository.

---

## Development Status

**⚠️ IN DEVELOPMENT**

This agent is under active development. The following components have been implemented:

✅ **Completed:**
- IRT score construction workflows (MAP scoring)
- Codebook maintenance system (validation, backup, versioning)
- Mplus dataset preparation and template reconciliation
- Configuration system and helper functions
- Comprehensive validation checks

🚧 **Pending:**
- Full end-to-end testing with complete datasets
- Integration with IRTScoring package (functions may not exist yet)
- Production validation and performance benchmarking
- Real-world recalibration workflow testing

**Do not use for production analyses until marked as Production Ready.**

---

*Document Version: 1.0*
*Last Updated: January 4, 2025*
*Status: IN DEVELOPMENT*

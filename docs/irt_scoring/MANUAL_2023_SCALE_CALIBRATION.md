# Manual 2023 Scale Calibration Workflow

**Last Updated:** December 2025 | **Status:** Complete

## Overview

The Manual 2023 Scale Calibration is a fixed-item calibration workflow that anchors new NE25 items to the 2023 historical GSED scale parameters. This ensures continuity across studies and time periods while estimating person-fit scores for NE25 participants on the established 2022 GSED scale.

### What This Workflow Does

1. **Extracts** NE25 item response data and person-level covariates
2. **Filters** for high-quality responses (excluding influential observations)
3. **Imputes** missing covariate values using CART algorithm
4. **Calibrates** 224 items in Mplus (171 fixed to 2023 parameters + 53 new free items)
5. **Generates** person-fit scores across 7 GSED domains + overall kidsights score
6. **Stores** results in DuckDB for pipeline integration

### Key Outputs

- **`ne25_kidsights_gsed_pf_scores_2022_scale`** - Person-fit scores for 2,831 NE25 participants
  - 14 columns: 7 domain scores + 7 conditional standard errors
  - 56.1% of NE25 participants have scores
- **`ne25_too_few_items`** - Exclusion flags for 718 participants (14.5%)
  - Records with <5 valid item responses
  - Includes response count and reason for exclusion

## Prerequisites

### Required Data

1. **NE25 Transformed Table** (`ne25_transformed`)
   - Must exist in DuckDB database
   - Contains 269 item response columns + person-level covariates
   - Run `run_ne25_pipeline.R` first if this table doesn't exist

2. **2023 mirt Calibration Archive** (`todo/kidsights-calibration/kidsight_calibration_mirt.rds`)
   - 205 items with 2023 parameters
   - 845 rows of IRT parameters (a1, d, g, u values)
   - Maps to NE22 lexicon → NE25 equate lexicon

3. **Codebook** (`codebook/data/codebook.json`)
   - Item definitions with lexicon mappings
   - Required for equate name identification and reverse coding

### Required Software

- **R 4.5.1** with packages:
  - `dplyr` - Data manipulation
  - `DBI` - Database connectivity
  - `duckdb` - DuckDB connection
  - `arrow` - Feather file I/O
  - `mice` - Imputation (CART method)
  - `jsonlite` - JSON parsing
  - `MplusAutomation` - Mplus integration

- **Mplus** - For .inp file execution and result parsing
  - Graded response model (GRM) with categorical IRT

- **Python 3.13+** (optional, for database management)

### Configuration

Ensure `.env` file is configured with:
```
REDCAP_API_CREDENTIALS_PATH=C:/Users/YOUR_USERNAME/my-APIs/kidsights_redcap_api.csv
KIDSIGHTS_DB_PATH=data/duckdb/kidsights_local.duckdb
```

## Workflow Steps

### Step 0: Directory Setup

```r
# Set working directory to project root
setwd("C:/Users/marcu/git-repositories/Kidsights-Data-Platform")

# Directory structure created automatically:
# calibration/ne25/manual_2023_scale/
#   ├── data/           # Intermediate datasets
#   ├── mplus/          # Mplus input/output files
#   ├── utils/          # Helper scripts
#   └── run_manual_calibration.R  # Main orchestrator
```

### Step 1: Load Item Response Data

**File:** `calibration/ne25/manual_2023_scale/utils/00_load_item_response_data.R`

**What it does:**
- Connects to `ne25_transformed` table
- Extracts 269 item response variables + 8 person-level covariates
- Filters for `meets_inclusion=TRUE` (2,831 participants)
- Excludes high-influence observations from database (if available)
- Applies minimum response threshold (≥5 valid items)
- **Result:** 2,785 eligible participants × 269 items

**Output files:**
- `data/stage1_wide.rds` - Wide format item responses
- `data/stage1_person_data.rds` - Covariates (pid, record_id, years, etc.)
- `data/stage1_item_metadata.rds` - Item metadata from codebook
- `data/stage1_exclusions.rds` - Exclusion reasons and counts

### Step 2: Filter High-Influence Persons

**What it does:**
- Identifies persons with Cook's distance > 5.5 quantile
- Excludes from calibration dataset
- Reason: High-leverage observations can distort IRT parameter estimates

**Result:** 2,785 → 2,785 (no flagged observations in this dataset)

### Step 3: Impute Missing Covariates

**Algorithm:** CART (Classification and Regression Trees)
- Single imputation (m=1)
- 20 iterations for convergence
- Handles: education, income, maternal factors, demographics

**What it does:**
- Uses `mice::mice()` with CART method
- Non-parametric imputation (preserves relationships)
- Creates single completed dataset for Mplus

**Covariates imputed:**
- `female` - Child gender (0/1)
- `years` - Age in years (log-transformed for modeling)
- `educ_a1` - Maternal education
- `fpl` - Federal poverty level ratio (log-transformed)
- `raceG` - Race/ethnicity groups
- `phq2_total` - Maternal depression (PHQ-2 scale)

### Step 4: Engineer Demographic Predictors

**What it does:**
- Creates binary indicators: college education, no high school, etc.
- Scales continuous predictors (school, logfpl, phq2)
- Calculates age interactions: `yrs3 × school`, `yrs3 × logfpl`, etc.
- Centers age at 3 years (`yrs3 = years - 3`)

**Final predictor set for Mplus:**
- `logyrs` - Log-transformed age
- `yrs3` - Age centered at 3 years
- `school` - Standardized education level (4-20 scale)
- `logfpl` - Standardized log federal poverty level
- `phq2` - Standardized maternal depression
- `black`, `hisp`, `other` - Race/ethnicity indicators
- `schXyrs3`, `fplXyrs3`, `phqXyrs3` - Age × predictor interactions

### Step 5: Create Mplus Dataset

**What it does:**
- Combines person covariates with item responses
- Creates unique record ID (1:n)
- Adds column `rid` for within-person identification
- Applies **reverse coding** to PS items (psychosocial problems)
  - Formula: `abs(y - max(y))`
  - Converts to developmental outcome scale (higher = better)

**Dataset dimensions:**
- 2,785 rows (unique persons)
- 269 + 10 = 279 columns (items + predictors)

**File output:** `calibration/ne25/manual_2023_scale/mplus/mplus_dat.dat`

### Step 6: Load 2023 mirt Parameters

**File:** `calibration/ne25/manual_2023_scale/utils/generate_mplus_model_block.R`

**What it does:**
- Reads `todo/kidsights-calibration/kidsight_calibration_mirt.rds`
- Extracts 205 items with 2023 calibration parameters (a, d, g, u)
- Maps from NE22 lexicon to NE25 equate lexicon
- Filters to 171 items that match NE25 dataset
- **Result:** 171 fixed parameters + 53 new free items = 224 total

**Parameter conversion (mirt → Mplus):**
- Slope: `a_mplus = a_mirt`
- Threshold: `tau_mplus = -d_mirt` (sign flip)
- Guessing: `g_mplus = g_mirt` (2-PL uses threshold, not guessing)

### Step 7: Generate Mplus Model Block

**File:** `calibration/ne25/manual_2023_scale/utils/generate_mplus_model_block.R`

**What it does:**
- Creates 456-line Mplus MODEL block
- Specifies 171 fixed item parameters with `@` notation
- Specifies 53 free item parameters (no `@` notation)
- Includes threshold specifications for categorical data
- Single latent factor `F` representing overall development

**Mplus notation example:**
```
MODEL:
  F BY AA102@0.303429  (fixed slope)
       AA203;          (free slope)
  [AA102$1@-3.656554]; (fixed threshold)
  [AA203$1];           (free threshold)
```

**Output:** `calibration/ne25/manual_2023_scale/mplus/mplus_model_block.txt`

### Step 8: Run Mplus Calibration

**What it does:**
- Executes `.inp` file in Mplus
- Estimates 53 free item parameters
- Anchors 171 fixed parameters to 2023 scale
- Uses graded response model (GRM) for ordinal data
- Computes person-fit scores (empirical Bayes)
- Generates conditional standard errors

**Mplus specifications:**
- **Estimator:** MLR (Maximum Likelihood Robust)
- **Integration:** Monte Carlo (4,096-16,384 points)
- **Model:** Single-factor graded response
- **OUTPUT:** SAVEDATA with person-fit scores

### Step 9: Parse Mplus Results

**What it does:**
- Reads Mplus SAVEDATA file
- Extracts person-fit scores: F, F_SE (overall)
- Extracts domain scores: GEN, EAT, INT, SLE, SOC (saved variably)
- Renames to standard GSED naming: `general_gsed_pf_2022`, etc.
- Creates CSEM (conditional SEM) columns: `_csem` suffix

**Result columns:**
```r
kidsights_2022              # Overall developmental score
kidsights_2022_csem         # Overall SEM
general_gsed_pf_2022        # General GSED domain
general_gsed_pf_2022_csem   # Domain SEM
# ... 5 more domains ...
```

### Step 10: Create Exclusion Flags Table

**What it does:**
- Identifies persons with <5 valid item responses
- Records exclusion reason ("Fewer than 5 responses")
- Creates boolean flag: `too_few_item_responses`
- Includes response count: `n_kidsight_psychosocial_responses`

**Result:** 718 participants flagged (14.5% of 4,966 total NE25)

### Step 11: Store Results in Database

**What it does:**
- Creates `ne25_kidsights_gsed_pf_scores_2022_scale` table
  - Columns: pid, record_id, 14 score columns
  - Records: 2,831 with `meets_inclusion=TRUE`
  - Indexed on pid, record_id composite key
- Creates `ne25_too_few_items` table
  - Columns: pid, record_id, too_few_item_responses, n_kidsight_psychosocial_responses, exclusion_reason
  - Records: 718 flagged participants

**Integration:** Tables automatically joined in NE25 pipeline Step 6.7 during next pipeline execution

## Running the Workflow

### Quick Start

```bash
# 1. Navigate to calibration directory
cd calibration/ne25/manual_2023_scale

# 2. Run the orchestrator script
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_manual_calibration.R

# 3. Verify results
SELECT COUNT(*) FROM ne25_kidsights_gsed_pf_scores_2022_scale;
SELECT COUNT(*) FROM ne25_too_few_items;
```

### Step-by-Step Execution

```r
# In R or RStudio, from project root:

# Load configuration and utilities
source("calibration/ne25/manual_2023_scale/utils/00_load_item_response_data.R")
source("calibration/ne25/manual_2023_scale/utils/generate_mplus_model_block.R")

# Step 1: Load data
out_00 <- load_stage1_data(
  db_path = "data/duckdb/kidsights_local.duckdb",
  codebook_path = "codebook/data/codebook.json",
  output_dir = "calibration/ne25/manual_2023_scale/data"
)

# Steps 2-4: Person-level engineering
# (See run_manual_calibration.R for person_dat_imp engineering)

# Step 5-7: Prepare Mplus dataset and model
# (Generated automatically by run_manual_calibration.R)

# Step 8: Run Mplus
# Execute: calibration/ne25/manual_2023_scale/mplus/all_2023_calibration_ne25.inp

# Step 9-11: Parse and store
# (Handled by run_manual_calibration.R)
```

## File Structure

```
calibration/ne25/manual_2023_scale/
├── README.md                           # This directory overview
├── run_manual_calibration.R            # Main orchestrator script
├── data/                               # Intermediate data
│   ├── stage1_wide.rds                 # Item responses (wide format)
│   ├── stage1_person_data.rds          # Person covariates
│   ├── stage1_item_metadata.rds        # Item metadata
│   └── stage1_exclusions.rds           # Exclusion tracking
├── utils/                              # Helper functions
│   ├── 00_load_item_response_data.R    # Data loading
│   └── generate_mplus_model_block.R    # MODEL block generation
└── mplus/                              # Mplus files
    ├── all_2023_calibration_ne25.inp   # Mplus input file
    ├── mplus_dat.dat                   # Mplus data (space-delimited)
    ├── all_2023_calibration_ne25.out   # Mplus output
    └── mplus_model_block.txt           # Generated MODEL section
```

## Technical Details

### Fixed Item Calibration Method

**Why fixed-item calibration?**
- Maintains continuity with 2023 GSED scale
- Allows comparison across studies and time periods
- Reduces parameter estimation burden (171 → 53 free parameters)
- Improves statistical precision for new items

**Implementation in Mplus:**
```
MODEL:
  F BY item1@slope1;    ! Fixed slope (from 2023)
       item2@slope2     ! Fixed slope (from 2023)
       item3;           ! Free slope (estimated from NE25)
```

### Graded Response Model (GRM)

**Item response model for ordinal data:**
- Response categories: 0, 1, 2, 3 (developmental progression)
- Each item has multiple thresholds (cumulative probabilities)
- Slopes (a parameters) vary by item (1-PL not used here)
- Intercepts/thresholds vary by response category

**Probability of endorsing category k:**
```
P(Y_i = k | θ) = P(Y_i ≥ k | θ) - P(Y_i ≥ k+1 | θ)
                = Φ(a_i(θ - τ_{ik})) - Φ(a_i(θ - τ_{i,k+1}))
```

### Conditional Standard Error of Measurement (CSEM)

**Interpretation:**
- Measurement precision for each person's score
- Individual-level standard error (not population average)
- Larger CSEM = less precise person-fit estimate
- Used to construct confidence intervals around scores

**Mplus output:** F_SE (standard error of factor score)

### Reverse Coding for Psychosocial Items

**PS items** (`starting with "ps"` in codebook) are **behavioral problems**:
- Raw scores: Higher = worse behavior (problems)
- Reverse-coded: Higher = better (fewer problems)
- Formula: `abs(value - max_value)`

**Example:**
```r
# If original scale is 0-3 (3 = most problems)
# Reverse: 3 → 0, 2 → 1, 1 → 2, 0 → 3 (0 = most problems becomes best score)
```

**Why?** GSED scales are developmental outcomes where higher = better. PS items must be reversed to align with this interpretation.

## Quality Assurance

### Data Quality Checks

1. **Item response completeness**
   - Minimum 5 valid responses per person (≥5 items)
   - Excludes 718 persons with <5 responses

2. **Covariate imputation**
   - CART preserves distributional properties
   - Single imputation (m=1) acceptable for auxiliary use in IRT
   - No multiply-imputed estimates needed for calibration

3. **Mplus convergence**
   - Monitor iteration counts (typically <50)
   - Check standard errors (SE/est < 0.1 preferred)
   - Review modification indices for misfit

4. **Person-fit diagnostics**
   - CSEM > 0 for all persons (ensures positive variance)
   - Extreme scores (F > ±3) flagged for review
   - Influential observations already excluded

### Troubleshooting

**Problem:** "Table not found: ne25_transformed"
- **Solution:** Run `run_ne25_pipeline.R` first to create transformed data

**Problem:** Mplus convergence errors
- **Solution:** See [CLAUDE.md - Mplus Convergence Criteria](../../CLAUDE.md#mplus-convergence-criteria)
- Increase `INTEGRATION = montecarlo(8192)` or higher
- Loosen `CONVERGENCE = 0.01`

**Problem:** "No ne25_flagged_observations table"
- **Solution:** This is optional; script gracefully skips if table missing
- All 2,785 eligible persons included without influence diagnostics

**Problem:** Reverse coding mismatch on PS items
- **Solution:** Verify codebook has `reverse_scoring: TRUE` for PS items
- Check `generate_mplus_model_block.R` for correct field references

## Integration with NE25 Pipeline

### Automatic Integration

Once tables are created, NE25 pipeline **Step 6.7** automatically:
- Checks for table existence
- Joins person-fit scores to `ne25_transformed` if found
- Gracefully skips if tables don't exist
- No manual post-processing required

### Example Usage

```r
# After pipeline run:
library(DBI)
library(duckdb)

con <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Check integrated data
scores_df <- dbGetQuery(con,
  "SELECT pid, record_id, kidsights_2022, general_gsed_pf_2022
   FROM ne25_transformed
   WHERE kidsights_2022 IS NOT NULL LIMIT 10")

dbDisconnect(con)
```

## Documentation Links

- [CLAUDE.md - Manual 2023 Scale Calibration Status](../../CLAUDE.md#-manual-2023-scale-calibration---complete-december-2025)
- [PIPELINE_STEPS.md - Step 6.7](../../docs/architecture/PIPELINE_STEPS.md#67-join-gsed-person-fit-scores--too-few-items-flags)
- [calibration/ne25/manual_2023_scale/README.md](../README.md) - Quick start guide
- [Mplus IRT Documentation](https://www.statmodel.com/webdocs/Mplus_Chapter_16.pdf) - Categorical IRT models

## Terminology

- **GSED** - Global Scale of Early Development
- **GRM** - Graded Response Model (ordinal categorical IRT model)
- **CSE M** - Conditional Standard Error of Measurement
- **Person-fit scores** - IRT trait estimates (theta, factor scores)
- **Domain scores** - Factor scores for specific GSED domains (general, feeding, etc.)
- **2023 scale** - Historical mirt calibration from 2023 study (now used as anchor)
- **Equate lexicon** - Harmonized item naming across studies (e.g., EG41_2, AA102)

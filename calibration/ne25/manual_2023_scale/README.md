# Manual 2023 Scale Calibration

**Automated workflow for fixed-item calibration of NE25 items to the 2023 GSED scale**

## Quick Start

```bash
# Prerequisites: Run NE25 pipeline first
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R

# Then run calibration workflow
cd calibration/ne25/manual_2023_scale
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_manual_calibration.R
```

## What This Does

Performs **fixed-item calibration** in Mplus to:
- Estimate new item parameters for 53 new NE25 items
- Anchor 171 items to 2023 historical GSED scale parameters
- Generate person-fit scores across 7 GSED domains
- Store results in DuckDB for pipeline integration

**Result:** 2,831 NE25 participants with person-fit scores on the 2022 GSED scale

## Key Files

| File | Purpose |
|------|---------|
| `run_manual_calibration.R` | Main orchestrator script (entry point) |
| `utils/00_load_item_response_data.R` | Load NE25 data from database |
| `utils/generate_mplus_model_block.R` | Generate Mplus MODEL block with 2023 parameters |
| `data/stage1_wide.rds` | Item responses (intermediate) |
| `data/stage1_person_data.rds` | Person covariates (intermediate) |
| `mplus/all_2023_calibration_ne25.inp` | Mplus input file |
| `mplus/mplus_dat.dat` | Mplus data (space-delimited) |

## Directory Structure

```
calibration/ne25/manual_2023_scale/
├── README.md                          ← You are here
├── run_manual_calibration.R           ← Run this file
├── data/                              # Intermediate datasets
│   ├── stage1_wide.rds
│   ├── stage1_person_data.rds
│   ├── stage1_item_metadata.rds
│   └── stage1_exclusions.rds
├── utils/                             # Helper functions
│   ├── 00_load_item_response_data.R   # Data loading utility
│   └── generate_mplus_model_block.R   # MODEL block generator
└── mplus/                             # Mplus files
    ├── all_2023_calibration_ne25.inp  # Mplus input
    ├── mplus_dat.dat                  # Mplus data
    ├── all_2023_calibration_ne25.out  # Mplus output (generated)
    └── mplus_model_block.txt          # Generated MODEL block
```

## Workflow Overview

The workflow follows 8 main steps:

### 1. Load Item Response Data
- Extracts 269 items + 8 covariates from `ne25_transformed` table
- Filters for `meets_inclusion=TRUE` (2,831 eligible)
- Applies ≥5 response minimum (excludes 718 records)
- **Result:** 2,785 persons × 269 items

### 2. Filter Influential Observations
- Removes high Cook's distance cases (if `ne25_flagged_observations` table exists)
- Protects calibration from outlier distortion
- **Result:** 2,785 persons (no influential flagged in current dataset)

### 3. Impute Missing Covariates
- Uses CART algorithm (Classification and Regression Trees)
- Single imputation (m=1) for auxiliary variables
- Covariates: education, income, demographics
- **Result:** Imputed person-level data

### 4. Engineer Demographic Predictors
- Creates binary indicators (college, no HS, etc.)
- Standardizes continuous predictors
- Calculates age interactions
- **Result:** 13 person-level predictors for Mplus

### 5. Prepare Mplus Dataset
- Combines persons + covariates + items
- Applies reverse coding to PS (psychosocial) items
- Creates space-delimited `.dat` file for Mplus
- **Result:** `mplus/mplus_dat.dat` (2,785 × 279)

### 6. Load 2023 mirt Parameters
- Reads historical 2023 calibration (`todo/kidsights-calibration/kidsight_calibration_mirt.rds`)
- Maps NE22 lexicon → NE25 equate lexicon
- Extracts 171 fixed parameters for anchoring
- **Result:** Fixed parameter values ready for Mplus

### 7. Generate Mplus MODEL Block
- Writes 456-line MODEL block with 171 fixed + 53 free parameters
- Creates threshold specifications for all 224 items
- Uses `@` notation for fixed values
- **Result:** `mplus/mplus_model_block.txt`

### 8. Create Output Tables
- Parses Mplus SAVEDATA for person-fit scores
- Creates `ne25_kidsights_gsed_pf_scores_2022_scale` (2,831 records)
- Creates `ne25_too_few_items` (718 exclusion flags)
- Tables automatically joined in NE25 pipeline Step 6.7

## Configuration

### Prerequisites

1. **NE25 transformed data** - Must exist in DuckDB
   - Run `run_ne25_pipeline.R` first if missing

2. **Codebook** - `codebook/data/codebook.json`
   - Item definitions and lexicon mappings
   - Included in repository

3. **2023 mirt calibration** - `todo/kidsights-calibration/kidsight_calibration_mirt.rds`
   - Historical parameters from 2023 study
   - Included in repository

4. **R packages** - Auto-checked by `run_manual_calibration.R`
   - dplyr, DBI, duckdb, arrow, mice, jsonlite, MplusAutomation

### .env Configuration

Ensure `.env` has database path (or use default):
```
KIDSIGHTS_DB_PATH=data/duckdb/kidsights_local.duckdb
```

## Running the Workflow

### Option 1: Full Orchestration (Recommended)

```bash
cd calibration/ne25/manual_2023_scale
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" run_manual_calibration.R
```

**What it does:**
- Loads all utilities and dependencies
- Executes Steps 1-8 in sequence
- Generates intermediate data files
- Creates database tables
- Reports progress and timing

**Expected runtime:** 3-5 minutes

**Output:**
```
Connected to DuckDB database

=== STEP 1: LOAD ITEM RESPONSE DATA ===

[OK] Data loaded: 2785 records, 269 items, 8 covariates
[OK] Exclusions checked: 718 with <5 responses
[OK] Stage1 data saved to: calibration/ne25/manual_2023_scale/data/

=== STEP 2-4: ENGINEER DEMOGRAPHIC PREDICTORS ===

[OK] Imputation completed (CART, m=1)
[OK] Predictors engineered: 13 variables
[OK] Mplus dataset created: 2785 rows × 279 cols

=== STEP 5-7: MPLUS MODEL GENERATION ===

[OK] 2023 mirt parameters loaded: 171 items
[OK] Mplus MODEL block generated: 456 lines
[OK] Mplus data file saved: mplus/mplus_dat.dat

=== STEP 8-11: DATABASE STORAGE ===

[OK] Person-fit scores table created: ne25_kidsights_gsed_pf_scores_2022_scale
[OK] Too-few-items table created: ne25_too_few_items
[OK] Integration: Tables ready for NE25 pipeline Step 6.7

[SUCCESS] Workflow completed
```

### Option 2: Step-by-Step Execution

```r
# In R from project root:

# 1. Set up environment
setwd("C:/Users/marcu/git-repositories/Kidsights-Data-Platform")
source("calibration/ne25/manual_2023_scale/utils/00_load_item_response_data.R")
source("calibration/ne25/manual_2023_scale/utils/generate_mplus_model_block.R")

# 2. Load data
out_00 <- load_stage1_data(
  db_path = "data/duckdb/kidsights_local.duckdb",
  codebook_path = "codebook/data/codebook.json",
  output_dir = "calibration/ne25/manual_2023_scale/data"
)
wide_dat <- out_00$wide_data
person_dat <- out_00$person_data

# 3-4. Engineer predictors (see run_manual_calibration.R for code)
# 5-7. Prepare Mplus and generate MODEL block (automatic)
# 8. Run Mplus: Execute all_2023_calibration_ne25.inp
# 9-11. Parse and store (automatic)
```

## Outputs

### Database Tables

**`ne25_kidsights_gsed_pf_scores_2022_scale` (2,831 records)**

Columns:
- `pid` - Project ID (1-4)
- `record_id` - Record identifier
- `kidsights_2022` - Overall developmental score
- `kidsights_2022_csem` - Conditional SEM
- `general_gsed_pf_2022` - General GSED domain
- `general_gsed_pf_2022_csem` - Domain SEM
- `feeding_gsed_pf_2022` - Feeding domain
- `feeding_gsed_pf_2022_csem` - Domain SEM
- `externalizing_gsed_pf_2022` - Externalizing problems
- `externalizing_gsed_pf_2022_csem` - Domain SEM
- `internalizing_gsed_pf_2022` - Internalizing problems
- `internalizing_gsed_pf_2022_csem` - Domain SEM
- `sleeping_gsed_pf_2022` - Sleeping domain
- `sleeping_gsed_pf_2022_csem` - Domain SEM
- `social_competency_gsed_pf_2022` - Social competency
- `social_competency_gsed_pf_2022_csem` - Domain SEM

**`ne25_too_few_items` (718 records)**

Columns:
- `pid` - Project ID
- `record_id` - Record identifier
- `too_few_item_responses` - Boolean: TRUE if <5 responses
- `n_kidsight_psychosocial_responses` - Count of valid responses
- `exclusion_reason` - Text reason for exclusion

### File Outputs

**Intermediate Data (in `data/`):**
- `stage1_wide.rds` - Item responses (2,785 × 269)
- `stage1_person_data.rds` - Covariates (2,785 × 8)
- `stage1_item_metadata.rds` - Item definitions from codebook
- `stage1_exclusions.rds` - Exclusion tracking

**Mplus Files (in `mplus/`):**
- `mplus_dat.dat` - Space-delimited data for Mplus (2,785 × 279)
- `all_2023_calibration_ne25.inp` - Mplus input file
- `all_2023_calibration_ne25.out` - Mplus output (generated)
- `mplus_model_block.txt` - Generated MODEL section

## Integration with NE25 Pipeline

### Automatic Integration

After running this workflow, the next execution of `run_ne25_pipeline.R` will:

1. **Detect** tables in database
2. **Join** person-fit scores in Step 6.7
3. **Add** 17 new columns to `ne25_transformed` table
4. **Report** join statistics

### Pipeline Step 6.7

```
--- Step 6.7: Joining GSED Scores and Item Insufficiency Flags ---
Loading GSED person-fit scores from database...
  - Records with GSED scores: 2785 (56.1%)
Loading too-few-items flags from database...
  - Records with too few items: 718 (14.5%)
Person-fit joins completed in 0.9 seconds
```

### Usage Example

```r
library(DBI)
library(duckdb)

con <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")

# Get integrated data with person-fit scores
df <- dbGetQuery(con,
  "SELECT pid, record_id, years, kidsights_2022, general_gsed_pf_2022
   FROM ne25_transformed
   WHERE kidsights_2022 IS NOT NULL")

dbDisconnect(con)
```

## Troubleshooting

### Issue: "Table not found: ne25_transformed"

**Cause:** NE25 pipeline hasn't been run yet

**Solution:**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

### Issue: Mplus convergence errors

**Cause:** Complex model with many parameters may require looser convergence criteria

**Solution:** Edit `mplus/all_2023_calibration_ne25.inp`
```
ANALYSIS:
  INTEGRATION = montecarlo(8192);  ! Increase from 4096
  MITERATION = 200;                ! Increase from 100
  CONVERGENCE = 0.01;              ! Loosen default
```

### Issue: "No such table: ne25_flagged_observations"

**Cause:** Influence diagnostics table doesn't exist (optional)

**Solution:** Not an error - script gracefully skips. All eligible persons included.

### Issue: Wrong item counts

**Cause:** Codebook or mirt calibration file missing or different location

**Solution:** Verify paths:
- Codebook: `codebook/data/codebook.json` ✓
- 2023 mirt: `todo/kidsights-calibration/kidsight_calibration_mirt.rds` ✓

## Documentation

**Complete Workflow Details:**
See [docs/irt_scoring/MANUAL_2023_SCALE_CALIBRATION.md](../../docs/irt_scoring/MANUAL_2023_SCALE_CALIBRATION.md)

**Pipeline Integration:**
See [docs/architecture/PIPELINE_STEPS.md - Step 6.7](../../docs/architecture/PIPELINE_STEPS.md#67-join-gsed-person-fit-scores--too-few-items-flags)

**Project Status:**
See [CLAUDE.md - Manual 2023 Scale Calibration](../../CLAUDE.md#-manual-2023-scale-calibration---complete-december-2025)

## Technical Notes

### Fixed-Item Calibration

- **171 items** with parameters anchored to 2023 mirt calibration
- **53 items** with parameters estimated from NE25 data
- **Single-factor GRM** (Graded Response Model) for ordinal responses
- **MLR estimator** in Mplus for robust standard errors

### Parameter Conversion (mirt → Mplus)

```
τ_Mplus = -d_mirt
a_Mplus = a_mirt
(Sign flip for threshold parameterization)
```

### Reverse Coding

PS items (psychosocial problems) are reverse-coded:
```r
abs(value - max(value))
```
This converts them to developmental outcome scale (higher = better).

### CSEM (Conditional Standard Error of Measurement)

- Person-specific measurement precision
- Lower = more precise score
- Used for confidence intervals around person-fit estimates

## Quick Reference

| Item | Count | Notes |
|------|-------|-------|
| Total NE25 participants | 4,966 | From REDCap |
| Meets inclusion criteria | 3,507 | Eligible candidates |
| Valid item responses (≥5) | 2,785 | Calibration sample |
| Too few items (<5) | 718 | Excluded |
| Fixed item parameters | 171 | From 2023 mirt |
| Free item parameters | 53 | Estimated from NE25 |
| Person-fit scores generated | 2,831 | 56.1% coverage |
| GSED domains estimated | 7 | + overall score |

---

**Last Updated:** December 2025
**Workflow Status:** ✅ Production-Ready
**Questions?** See [MANUAL_2023_SCALE_CALIBRATION.md](../../docs/irt_scoring/MANUAL_2023_SCALE_CALIBRATION.md)

# Pipeline Architecture Overview

**Last Updated:** January 2025

This document provides detailed architecture documentation for all seven data pipelines in the Kidsights Data Platform. Each pipeline is designed as an independent, standalone system with specific data sources and use cases.

---

## Table of Contents

1. [NE25 Pipeline](#ne25-pipeline) - REDCap survey data processing
2. [ACS Pipeline](#acs-pipeline) - Census data extraction for statistical raking
3. [NHIS Pipeline](#nhis-pipeline) - National health surveys for benchmarking
4. [NSCH Pipeline](#nsch-pipeline) - Children's health survey integration
5. [Raking Targets Pipeline](#raking-targets-pipeline) - Population-representative targets for post-stratification
6. [Imputation Pipeline](#imputation-pipeline) - Multiple imputation for geographic uncertainty
7. [IRT Calibration Pipeline](#irt-calibration-pipeline) - Mplus calibration dataset for psychometric recalibration
8. [ACS Metadata System](#acs-metadata-system) - IPUMS DDI metadata integration
9. [Pipeline Integration](#pipeline-integration-and-relationship) - How pipelines work together

---

## NE25 Pipeline: Hybrid R-Python Design (September 2025)

### Problem Solved
R DuckDB segmentation faults caused 50% pipeline failure rate

### Solution
R handles orchestration/transforms, Python handles all database operations

### Architecture Diagram

```
REDCap (4 projects) → R: Extract/Transform → Feather Files → Python: Database Ops → Local DuckDB
     3,906 records      REDCapR, recode_it()      arrow format      Chunked processing     47MB local
```

### Key Benefits

- **100% pipeline reliability** (was 50%)
- **3x faster I/O** with Feather format
- **Rich error context** (no more segfaults)
- **Perfect data type preservation** R ↔ Python

### Design Rationale

The hybrid architecture was adopted in September 2025 to eliminate persistent segmentation faults when using R's DuckDB driver. By delegating all database operations to Python while keeping R for its strengths (REDCap extraction, statistical transformations), we achieved complete stability without sacrificing functionality.

### Technical Components

- **R Components:** REDCapR for API calls, recode_it() for transformations, arrow for Feather I/O
- **Python Components:** duckdb for database ops, pandas for data manipulation
- **Data Exchange:** Arrow Feather format preserves R factors ↔ pandas categories perfectly
- **Storage:** Local DuckDB database (47MB, 11 tables, 7,812 records)

---

## ACS Pipeline: Census Data Extraction (September 2025)

### Purpose
Extract American Community Survey data from IPUMS USA API for statistical raking

### Architecture Diagram

```
IPUMS USA API → Python: Extract/Cache → Feather Files → R: Validate → Python: Database Ops → Local DuckDB
  Census data     ipumspy, requests     arrow format    Statistical QC    Chunked inserts    Separate tables
```

### Key Features

- **API Integration:** Direct IPUMS USA API calls (no manual web downloads)
- **Smart Caching:** Automatic caching with checksum validation (90+ day retention)
- **R Validation:** Statistical QC and data validation in R
- **Standalone Design:** Independent of NE25 pipeline (no dependencies)
- **Future Use:** Enables post-stratification raking after harmonization

### Design Rationale

The ACS pipeline was designed as a utility system to support future statistical raking (post-stratification). Rather than integrating it into the NE25 pipeline (different run cadences), we built it as a standalone tool that populates separate database tables. Census data refreshes annually, while NE25 data refreshes continuously.

### Technical Components

- **Python Modules:** `python/acs/` - auth, config management, extract building, caching
- **R Validation:** `pipelines/orchestration/run_acs_pipeline.R` - statistical QC
- **Configuration:** `config/sources/acs/` - state-specific YAML configs
- **Storage:** `acs_raw` and `acs_metadata` tables in shared DuckDB

---

## NHIS Pipeline: Health Surveys Data Extraction (October 2025)

### Purpose
Extract National Health Interview Survey data from IPUMS Health Surveys API for national benchmarking and ACEs/mental health research

### Architecture Diagram

```
IPUMS NHIS API → Python: Extract/Cache → Feather Files → R: Validate → Python: Database Ops → DuckDB
  ih2019-ih2024    ipumspy, requests     arrow format    7 validation    Chunked inserts   nhis_raw table
      ↓                    ↓                     ↓            checks              ↓              ↓
  66 variables      SHA256 caching         3x faster I/O    Survey QC    Perfect types    300K+ records
  6 annual samples  90+ day retention      R ↔ Python       ACE/MH       preservation     47+ MB
```

### Key Features

- **API Integration:** Direct IPUMS NHIS API calls (collection: `nhis`)
- **Multi-Year Samples:** 6 annual samples (2019-2024), not pooled like ACS
- **Smart Caching:** SHA256 signatures based on years + samples + variables
- **66 Variables:** Demographics, parent info, ACEs, GAD-7, PHQ-8, economic indicators
- **No Case Selection:** Nationwide, all ages (vs ACS state/age filters)
- **Survey Design:** Includes SAMPWEIGHT, STRATA, PSU for complex survey analysis
- **Mental Health Focus:** GAD-7 anxiety and PHQ-8 depression (2019, 2022 only)
- **ACEs Coverage:** 8 ACE variables with direct overlap to NE25
- **Documentation:** Complete usage guides, testing procedures, transformation mappings

### Use Cases

- Compare NE25 ACE prevalence to national NHIS estimates
- Extract PHQ-2/GAD-2 from full PHQ-8/GAD-7 scales for comparability
- Population benchmarking for Nebraska sample
- Future harmonization for raking (Phase 12+)

### Design Rationale

NHIS provides nationally representative health data that directly overlaps with NE25 measures (ACEs, mental health). Unlike ACS (demographics only), NHIS enables apples-to-apples comparison of health outcomes. The multi-year design (6 annual samples) allows trend analysis and ensures sufficient sample sizes for subgroup comparisons.

### Technical Components

- **Python Modules:** `python/nhis/` - auth, extract management, SHA256-based caching
- **R Validation:** `pipelines/orchestration/run_nhis_pipeline.R` - 7 validation checks
- **Configuration:** `config/sources/nhis/` - year-specific configs, sample definitions
- **Storage:** `nhis_raw` table with 229,609 records (188,620 sample + 40,989 non-sample)

---

## NSCH Pipeline: Survey Data Integration (October 2025)

### Purpose
Integrate National Survey of Children's Health (NSCH) data from SPSS files for national benchmarking and trend analysis

### Architecture Diagram

```
SPSS Files → Python: Convert → Feather → R: Validate → Python: Load → DuckDB
  2016-2023    pyreadstat      arrow     7 QC checks    Chunked     nsch_{year}_raw
     ↓              ↓            ↓             ↓         inserts          ↓
  840-923 vars  Metadata   Fast I/O    Integrity   10K/chunk    284K records
  50K-55K rows  extraction  3x faster    checks    validation    7 years loaded
```

### Key Features

- **Multi-Year Support:** 8 years (2016-2023), 284,496 records loaded
- **Automated Pipeline:** Single command processes SPSS → Database
- **Metadata Extraction:** Auto-generates variable reference (3,780 variables)
- **Data Quality:** 7-point validation ensures 100% integrity
- **Efficient Storage:** 200:1 compression (SPSS → DuckDB)
- **Batch Processing:** Processes 7 years in 2 minutes
- **Documentation:** 10 comprehensive guides (629 KB total)

### Current Status
✅ Production Ready (7/8 years loaded, 2016 schema incompatibility documented)

### Use Cases

- National benchmarking for state/local child health data
- Trend analysis (2017-2023) for longitudinal studies
- ACE prevalence comparison across years
- Cross-year harmonization (future Phase 8)

### Design Rationale

NSCH is the gold standard for child health surveillance in the US. Unlike NHIS (household-based), NSCH focuses specifically on children and includes detailed ACE assessments, healthcare access, and developmental outcomes. The SPSS-based pipeline (vs API) was chosen because NSCH data is released as SPSS files rather than through IPUMS.

### Technical Components

- **Python Modules:** `python/nsch/` - SPSS loading, metadata extraction, data loading
- **R Validation:** `pipelines/orchestration/run_nsch_pipeline.R` - 7 QC checks
- **Configuration:** `config/sources/nsch/` - database schema, templates
- **Storage:** Year-specific tables (`nsch_2017_raw`, `nsch_2018_raw`, etc.)

---

## Raking Targets Pipeline: Population-Representative Targets (October 2025)

### Purpose
Generate population-representative raking targets for post-stratification weighting of NE25 survey data

### Architecture Diagram

```
ACS Estimates + NHIS Estimates + NSCH Estimates → R: Consolidate & Structure → DuckDB: raking_targets_ne25
25 estimands      1 estimand        4 estimands         30 estimands × 6 ages    180 targets with indexes
```

### Key Features

- **Multi-Source Integration:** Combines ACS (census), NHIS (health), NSCH (child health)
- **Age Stratification:** 6 age groups (0-1, 2-3, 4-5, 6-8, 9-11, 12-17)
- **Streamlined Pipeline:** Single R script executes all phases (~2-3 minutes)
- **Database Integration:** Optimized table with 4 indexes for efficient querying
- **Bootstrap Variance:** 614,400 bootstrap replicates for ACS estimands

### Design Rationale

Post-stratification (raking) requires population-representative targets from multiple data sources. Rather than manually compiling these, the pipeline automatically generates 180 raking targets by combining survey-weighted estimates from ACS, NHIS, and NSCH. The targets are structured for direct use with the `survey` package in R.

### Technical Components

- **R Scripts:** `scripts/raking/ne25/` - Estimation and consolidation
- **Data Sources:** ACS (demographics), NHIS (maternal depression), NSCH (ACEs, health, childcare)
- **Output:** `raking_targets_ne25` table with 180 rows
- **Documentation:** [docs/raking/NE25_RAKING_TARGETS_PIPELINE.md](../raking/NE25_RAKING_TARGETS_PIPELINE.md)

---

## Imputation Pipeline: Multiple Imputation for Uncertainty (October 2025)

### Purpose
Generate M=5 imputations for geographic, sociodemographic, and childcare variables using sequential chained imputation

### Architecture Diagram

```
7-Stage Sequential Imputation Pipeline (Study-Specific: ne25, ia26, co27)

Stage 1-3: Geography Imputation
ne25_transformed → Parse afact → Sample M values → imputed_puma/county/census_tract
                   (allocation     (weighted         (3 tables: 25,480 rows)
                    factors)        random)

Stage 4: Sociodemographic Imputation
Geography (M) → MICE imputation → imputed_female/raceG/educ_mom/educ_a2/income/family_size/fplcat
                (7 variables)      (7 tables: 26,438 rows)

Stage 5-7: Childcare Imputation (3-Stage Sequential)
Geo + Sociodem (M) → CART Stage 1 → imputed_cc_receives_care (805 rows)
                   → CART Stage 2 → imputed_cc_primary_type (7,934 rows)
                                  → imputed_cc_hours_per_week (6,329 rows)
                   → Derivation   → imputed_childcare_10hrs_nonfamily (15,590 rows)

Helper Functions → Completed Datasets (14 variables joined)
Python/R           Ready for analysis with proper MI variance
```

### Key Features

- **7-Stage Sequential Pipeline:** Geography → Sociodem → Childcare (3-stage conditional)
- **14 Total Variables:** 3 geography + 7 sociodem + 4 childcare
- **Multi-Study Architecture:** Independent studies (ne25, ia26, co27) with shared codebase
- **Variable-Specific Storage:** Normalized schema (one table per imputed variable per study)
- **Selective Storage:** Only stores imputed values (not observed), 50%+ storage efficiency
- **Single Source of Truth:** R functions via reticulate call Python directly
- **Configuration-Driven:** M, random seed, variables in study-specific YAML configs
- **Statistical Validity:** Proper propagation of uncertainty from multiple sources

### Production Metrics (Study: ne25)

**Geographic Variables (3):**
- 878 PUMA imputations (26% of records have ambiguity)
- 1,054 county imputations (31% of records)
- 3,164 census tract imputations (94% of records!)
- Subtotal: 25,480 rows across 3 tables

**Sociodemographic Variables (7):**
- female, raceG, educ_mom, educ_a2, income, family_size, fplcat
- MICE imputation with geography as predictors
- Subtotal: 26,438 rows across 7 tables

**Childcare Variables (4):**
- 3-stage sequential: receives_care → type/hours → derived 10hrs indicator
- Defensive programming: NULL filtering, outlier cleaning (hours ≤168)
- Subtotal: 24,718 rows across 4 tables

**Total:** 76,636 rows across 14 tables | **Runtime:** 2.0 minutes | **Error Rate:** 0%

### Design Rationale

**Sequential Chained Imputation:**
Rather than imputing all variables simultaneously, we use a **3-phase sequential approach**:
1. **Geography first** - Provides spatial context for downstream models
2. **Sociodemographics second** - Uses geography as predictors in MICE
3. **Childcare last** - Conditional 3-stage process uses all upstream variables

This ensures geographic uncertainty propagates through all substantive imputations while maintaining logical consistency (e.g., childcare type only imputed when receives_care = "Yes").

**Variable-Specific Tables:**
Pre-computed realized values stored in separate tables ensure internal consistency (geography in imputation #5 is the same across all uses) while maintaining storage efficiency. The reticulate-based R interface eliminates code duplication.

### Technical Components

- **Python Modules:** `python/imputation/` - Configuration, helper functions for data retrieval
- **R Scripts:** `scripts/imputation/{study_id}/` - Study-specific 7-stage pipeline
- **R Wrappers:** `R/imputation/` - Single source of truth via reticulate
- **Configuration:** `config/imputation/{study_id}_config.yaml` - Study-specific M, seed, variables
- **Storage:** 14 tables per study: `{study_id}_imputed_{variable}`
- **Documentation:**
  - [USING_IMPUTATION_AGENT.md](../imputation/USING_IMPUTATION_AGENT.md) - User guide with examples
  - [CHILDCARE_IMPUTATION_IMPLEMENTATION.md](../imputation/CHILDCARE_IMPUTATION_IMPLEMENTATION.md) - Implementation plan
  - [PIPELINE_TEST_REPORT.md](../imputation/PIPELINE_TEST_REPORT.md) - Production validation

### Usage Examples

**Python - Get Complete Dataset (All 14 Variables):**
```python
from python.imputation.helpers import get_complete_dataset, get_childcare_imputations

# Get imputation m=1 with all 14 variables
df = get_complete_dataset(study_id='ne25', imputation_number=1)
# Returns: puma, county, census_tract, female, raceG, educ_mom, educ_a2,
#          income, family_size, fplcat, cc_receives_care, cc_primary_type,
#          cc_hours_per_week, childcare_10hrs_nonfamily

# Get just childcare variables (4 variables)
childcare = get_childcare_imputations(study_id='ne25', imputation_number=1)
```

**R - Survey Analysis with MI (via reticulate):**
```r
source("R/imputation/helpers.R")

# Get list of all M=5 imputations for mitools
imp_list <- get_imputation_list(study_id = 'ne25')

# Survey analysis with Rubin's rules
library(survey); library(mitools)
designs <- lapply(imp_list, function(df) {
  svydesign(ids=~1, weights=~weight, data=df)
})
results <- lapply(designs, function(d) svymean(~childcare_10hrs_nonfamily, d))
combined <- MIcombine(results)
summary(combined)  # Proper MI variance from geographic + substantive uncertainty
```

### Multi-Study Support

The imputation pipeline supports **independent studies** with shared infrastructure:

- **Study-Specific Tables:** `{study_id}_imputed_{variable}` (e.g., `ne25_imputed_puma`)
- **Study-Specific Configs:** `config/imputation/{study_id}_config.yaml`
- **Study-Specific Scripts:** `scripts/imputation/{study_id}/run_full_imputation_pipeline.R`
- **Shared Helpers:** Python/R helper functions accept `study_id` parameter

**Adding a New Study (e.g., ia26):**
```bash
python scripts/imputation/create_new_study.py --study-id ia26 --study-name "Iowa 2026"
# Creates: config, scripts, database schema
# Customize variables, then run full pipeline
```

See [ADDING_NEW_STUDY.md](../imputation/ADDING_NEW_STUDY.md) for complete onboarding guide.

---

## IRT Calibration Pipeline: Multi-Study Psychometric Recalibration (In Development - November 2025)

### Purpose
Create Mplus-compatible calibration dataset combining historical studies and national benchmarks for Item Response Theory recalibration of Kidsights developmental/behavioral scales

⚠️ **Development Status:** Pipeline under active validation following recent bug fixes. See "Data Quality Improvements" section below.

### Architecture Diagram

```
Multi-Study Data Integration → Lexicon Harmonization → Mplus Calibration → IRT Scoring

Historical (NE20/22/USA24)  ┐
KidsightsPublic Package     │
41,577 records              │
241 items                   ├─→ R: Lexicon Mapping ──→ Mplus .dat ──→ IRT Parameters ──→ NE25 Scoring
                           │    Codebook-driven         47,084 records    Graded response    Theta scores
NE25 Current Study          │    416 items aligned      38.71 MB          model calibration   Domain scores
ne25_transformed table      │                           28s execution
3,507 records (eligible)    │
276 items                   │
                           │
NSCH National Benchmarks   │
2021: 20,719 → sample 1000 │
2022: 19,741 → sample 1000 │
30-37 items                ┘
```

### Key Features

- **Multi-Study Integration:** 6 studies (NE20, NE22, NE25, USA24, NSCH21, NSCH22) with 47,084 total records
- **Lexicon-Based Harmonization:** Automatic item name mapping via codebook (ne25/cahmi21/cahmi22 → lex_equate)
- **Historical Data Import:** One-time import from KidsightsPublic R package to DuckDB
- **National Benchmarking:** Configurable NSCH sampling (default: 1,000 per year, ages 0-6)
- **Mplus Compatibility:** Space-delimited .dat format with missing as ".", no headers
- **Production Performance:** 28 seconds execution time for full workflow
- **Comprehensive Validation:** 100% data integrity match with original historical data
- **Interactive Workflow:** User prompts for NSCH sample size and output paths

### Data Quality Improvements (November 2025)

**Issue #6: Three Critical Bug Fixes**

The IRT calibration pipeline underwent significant data quality improvements in November 2025 to address contamination from NSCH missing codes and syntax generation errors. All fixes have been implemented and committed to the repository.

#### 1. NSCH Missing Code Contamination (Commits: 20e3cf5, 25d2b47)

**Problem:**
- NSCH 2021 and 2022 variables used study-specific missing codes in the 90-99 range
- Values >= 90 (e.g., 90="Not applicable", 95="Refused", 97="Don't know", 98="Missing", 99="Missing") were treated as valid response categories
- When reverse/forward coding transformations were applied, `max(x)` calculations included these sentinel values

**Impact:**
- Dichotomous items showed inflated threshold counts (e.g., DD201 with values {0, 1} showed 5 thresholds instead of 1)
- Example: ONEWORD (DD201) had values 0, 1, 4, 97, 98 (max=98) causing invalid IRT parameter estimation

**Solution:**
```r
# Modified scripts/irt_scoring/helpers/recode_nsch_2021.R (lines 200-226)
# Modified scripts/irt_scoring/helpers/recode_nsch_2022.R (lines 204-230)

# Recode all values >= 90 to NA BEFORE reverse/forward coding
nsch_data <- nsch_data %>%
  dplyr::mutate(
    dplyr::across(dplyr::any_of(available_cahmi_vars),
                  function(x) dplyr::case_when(
                    x >= 90 ~ NA_real_,
                    .default = x
                  ))
  )
```

**Validation:**
- After fix, DD201 values: {0, 1}, max=1 (correct for dichotomous item)
- "Non-Sequential Response Values" quality flags reduced from 194 to 114 (80 NSCH-related flags eliminated)

#### 2. Missing Study Field Assignment (Commit: d72afaa)

**Problem:**
- NSCH helper functions `recode_nsch_2021()` and `recode_nsch_2022()` didn't create a `study` column
- When `bind_rows()` combined datasets in `prepare_calibration_dataset.R`, NSCH records showed `study = NA`

**Impact:**
- Couldn't trace items back to original study source in combined calibration dataset
- Study-level analyses (DIF detection, study comparisons) were compromised

**Solution:**
```r
# Modified scripts/irt_scoring/prepare_calibration_dataset.R (lines 292-293, 319-320)

# After NSCH sampling, explicitly assign study field
nsch21_data <- nsch21_data %>% dplyr::mutate(study = "NSCH21")
nsch22_data <- nsch22_data %>% dplyr::mutate(study = "NSCH22")
```

**Validation:**
- All 6 studies now properly labeled: NE20, NE22, NE25, NSCH21, NSCH22, USA24
- Study breakdown shows correct record counts for each study source

#### 3. Syntax Generator Indexing Bug (Commit: 37d2034)

**Problem:**
- `scripts/irt_scoring/calibration/write_syntax2.R` used positional array indexing `Ks[jdx]` where `jdx` is the item's `jid` value (e.g., 150 for EG16c)
- The `Ks` vector only has ~260 elements (one per item), but `jid` values can exceed 400
- When `jdx=150` but `Ks` length=260, R's indexing behavior caused incorrect threshold counts

**Impact:**
- 26 items (EG14b, EG16c, EG17b, EG19, etc.) generated incorrect threshold specifications
- Example: EG16c (dichotomous, max=1) showed 4 thresholds in Mplus syntax instead of 1
- Partial starting values appeared: threshold 1 had starting value, thresholds 2-4 were blank

**Solution:**
```r
# Modified scripts/irt_scoring/calibration/write_syntax2.R (lines 167-234)

# Before (BUGGY):
if (!is.na(Ks[jdx]) && Ks[jdx] >= 2) { ... }  # Positional indexing by jid

# After (FIXED):
item_max_category <- categories[jid == jdx] + 1  # Named lookup from codebook_df
if (!is.na(item_max_category) && item_max_category >= 2) { ... }
```

**Validation:**
- All 261 items now generate threshold counts matching actual data ranges
- EG16c: 1 threshold (correct for dichotomous item)
- DD201: 1 threshold (correct for dichotomous item)
- Generated syntax file: `todo/kidsights_syntax_FIXED.xlsx`

**Development Implications:**
- Clean calibration dataset: `calibration_dataset_2020_2025` (47,084 records, no sentinel values)
- Accurate Mplus syntax: All threshold specifications match actual category ranges
- Verify outputs: If calibration data generated before November 2025, re-run `prepare_calibration_dataset.R`

### Current Metrics

**Dataset Composition:**
- **Historical Studies:** NE20 (37,546) + NE22 (2,431) + USA24 (1,600) = 41,577 records
- **Current Study:** NE25 (3,507 eligible records)
- **National Benchmarks:** NSCH21 (1,000) + NSCH22 (1,000) = 2,000 records
- **Total:** 47,084 records across 416 developmental/behavioral items
- **File Size:** 38.71 MB Mplus .dat file
- **Execution Time:** 28 seconds (17x faster than target)
- **Missingness:** 92.9% overall (expected - different studies measure different items)

**NE25 Item Coverage:**
- 66 items with <50% missing (sufficient for IRT calibration)
- 20 social-emotional items (PS*) with ~26% missing (excellent coverage)
- 3 items with <20% missing (demographic/structural variables)

### Design Rationale

**Multi-Study Calibration Approach:**
Rather than calibrating on NE25 alone (n=3,507), we combine **historical Nebraska studies** (larger sample, established parameters) with **national NSCH benchmarks** (population diversity) to create robust, generalizable item parameters. This approach:

1. **Increases Statistical Power:** 47K records vs 3.5K for stable parameter estimation
2. **Tests Cross-Study Invariance:** Detects differential item functioning (DIF) across studies
3. **Enables National Norming:** NSCH provides nationally representative benchmarks
4. **Preserves Continuity:** Historical parameters anchor the recalibration

**Lexicon System Integration:**
The codebook's lexicon system provides automatic item harmonization across studies:
- **NE25:** Database columns (lowercase: c020, ps001)
- **NSCH:** CAHMI variables (uppercase: SIMPLEINST, ONEWORD)
- **Equate:** Universal IDs (uppercase: DD103, PS001)

This eliminates manual crosswalks and ensures single source of truth.

### Technical Components

**R Scripts:**
- `scripts/irt_scoring/prepare_calibration_dataset.R` (586 lines) - Main interactive workflow
- `scripts/irt_scoring/import_historical_calibration.R` (273 lines) - One-time historical data import
- `scripts/irt_scoring/helpers/recode_nsch_2021.R` (264 lines) - NSCH 2021 harmonization
- `scripts/irt_scoring/helpers/recode_nsch_2022.R` (268 lines) - NSCH 2022 harmonization
- `scripts/irt_scoring/helpers/mplus_dataset_prep.R` (modified) - Age filter utilities

**Validation Scripts:**
- `scripts/irt_scoring/validate_calibration_dataset.R` - Compare with KidsightsPublic original
- `scripts/irt_scoring/validate_item_missingness.R` - Analyze missingness patterns
- `scripts/irt_scoring/test_mplus_compatibility.R` - Verify .dat file format
- `scripts/irt_scoring/run_full_scale_test.R` - Production performance benchmarking

**Quality Assurance Tools:**
- Age-Response Gradient Explorer Shiny app (`scripts/shiny/age_gradient_explorer/`)
- Box plots + GAM smoothing for 308 items across 6 studies
- Real-time filtering by item, study, and quality flags
- Codebook metadata integration
- **Role:** Mandatory pre-calibration visual inspection of age gradients
- **Status:** Production-ready (15 test scenarios passed)
- **Launch:** `shiny::runApp("scripts/shiny/age_gradient_explorer")`

**Database Tables:**
- `historical_calibration_2020_2024` - Historical studies (NE20, NE22, USA24)
- `calibration_dataset_2020_2025` - Complete calibration dataset (all 6 studies)
- Indexes: study, study_num, id, (study, id)

**Documentation:**
- [MPLUS_CALIBRATION_WORKFLOW.md](../irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md) - Complete 4-stage workflow guide
- `todo/calibration_dataset_validation_summary.md` - Comprehensive validation results

### Usage Example

**Prepare Calibration Dataset (Interactive):**
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/irt_scoring/prepare_calibration_dataset.R

# Prompts:
#   NSCH sample size per year: 1000  (recommended)
#   Output .dat file path: [Enter] for default (mplus/calibdat.dat)
```

**Or in R Session:**
```r
source("scripts/irt_scoring/prepare_calibration_dataset.R")
prepare_calibration_dataset()
```

**Outputs:**
1. **Mplus .dat file:** `mplus/calibdat.dat` (38.71 MB, ready for graded response model)
2. **DuckDB table:** `calibration_dataset_2020_2025` (47,084 records, 420 columns)

**Validation:**
```bash
# Test Mplus compatibility
"C:\Program Files\R\R-4.5.1\bin\R.exe" -f scripts/irt_scoring/test_mplus_compatibility.R

# Validate missingness patterns
"C:\Program Files\R\R-4.5.1\bin\R.exe" -f scripts/irt_scoring/validate_item_missingness.R
```

### Study Indicator Codes

Mplus dataset uses numeric `study_num` for grouping/DIF analysis:

| Study  | study_num | Records | Description |
|--------|-----------|---------|-------------|
| NE20   | 1         | 37,546  | Nebraska 2020 (historical) |
| NE22   | 2         | 2,431   | Nebraska 2022 (historical) |
| NE25   | 3         | 3,507   | Nebraska 2025 (current) |
| NSCH21 | 5         | 1,000   | National Survey 2021 (benchmark) |
| NSCH22 | 6         | 1,000   | National Survey 2022 (benchmark) |
| USA24  | 7         | 1,600   | USA national sample 2024 |

**Note:** study_num=4 is intentionally skipped to maintain consistency with KidsightsPublic numbering.

### Known Limitations

1. **Authentic Column Issue:** All NE25 records have `authentic=FALSE`, currently using `eligible=TRUE` only
   - GitHub Issue: `.github/ISSUE_TEMPLATE/authentic_column_all_false.md`
   - Workaround: Active (filters by eligible only)
   - Priority: Medium (investigate authenticity validation process)

2. **High Overall Missingness:** 92.9% missing expected (different studies measure different item subsets)

3. **Age-Specific Items:** Developmental items show 70-80% missingness (age-appropriate administration)

### Next Steps for IRT Calibration

After dataset preparation, follow [MPLUS_CALIBRATION_WORKFLOW.md](../irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md):

1. **Quality Assurance (REQUIRED)** - Use Age-Response Gradient Explorer to inspect age-response patterns
   - Launch: `shiny::runApp("scripts/shiny/age_gradient_explorer")`
   - Complete QA checklist: developmental gradients, negative flags, category separation, study consistency
   - Document item exclusion decisions (items with negative correlations, poor discrimination, etc.)
   - Export quality summary for calibration notes
   - **Timing:** 15-30 minutes for thorough review of 308 items
   - **Output:** Documented list of items to exclude or investigate before Mplus calibration
2. **Create Mplus .inp file** with graded response model specification
3. **Run Mplus calibration** (10-120 minutes depending on model complexity)
4. **Extract item parameters** (discrimination, thresholds)
5. **Store parameters in codebook** (`irt_params` section)
6. **Apply IRT scoring to NE25 data** (generate theta scores)

---

## ACS Metadata System (October 2025)

### Purpose
Leverage IPUMS DDI (Data Documentation Initiative) metadata for transformation, harmonization, and documentation

### Architecture Diagram

```
DDI XML Files → Python: Parse Metadata → DuckDB: Metadata Tables → Python/R: Query & Transform
  Variable defs    metadata_parser.py    3 tables (42 vars, 1,144 labels)   Decode, harmonize
```

### Components

#### 1. Metadata Extraction (Phase 1)

- **Parser:** `python/acs/metadata_parser.py` - Extracts variables, value labels, dataset info from DDI
- **Schema:** `python/acs/metadata_schema.py` - Defines 3 DuckDB tables (acs_variables, acs_value_labels, acs_metadata_registry)
- **Loader:** `pipelines/python/acs/load_acs_metadata.py` - Populates metadata tables
- **Auto-loading:** Integrated into extraction pipeline (Step 4.6)

#### 2. Transformation Utilities (Phase 2)

**Python Utilities:** `python/acs/metadata_utils.py`
- `decode_value()`: Decode single values (e.g., STATEFIP 27 → "Minnesota")
- `decode_dataframe()`: Decode entire columns
- `get_variable_info()`, `search_variables()`: Query metadata
- `is_categorical()`, `is_continuous()`, `is_identifier()`: Type checking

**R Utilities:** `R/utils/acs/acs_metadata.R`
- `acs_decode_value()`, `acs_decode_column()`: Decode values
- `acs_get_variable_info()`, `acs_search_variables()`: Query metadata
- `acs_is_categorical()`, etc.: Type checking

**Harmonization Tools:** `python/acs/harmonization.py`
- `harmonize_race_ethnicity()`: Maps IPUMS RACE/HISPAN to 7 NE25 categories
- `harmonize_education()`: Maps IPUMS EDUC to NE25 8-cat or 4-cat education levels
- `harmonize_income_to_fpl()`: Converts income to Federal Poverty Level percentages
- `apply_harmonization()`: Applies all harmonizations at once

#### 3. Documentation & Analysis (Phase 3)

**Data Dictionary Generator:** `scripts/acs/generate_data_dictionary.py`
- Auto-generates HTML/Markdown data dictionaries from metadata
- Includes variable descriptions, value labels, data types

**Transformation Docs:** `docs/acs/transformation_mappings.md`
- Documents IPUMS → NE25 category mappings
- Race/ethnicity, education, income/FPL transformations

**Query Cookbook:** `docs/acs/metadata_query_cookbook.md`
- Practical examples in Python and R
- Common patterns for decoding, searching, harmonizing

### Usage Examples

**Python:**
```python
from python.acs.metadata_utils import decode_value, decode_dataframe
from python.acs.harmonization import harmonize_race_ethnicity
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Decode values
state = decode_value('STATEFIP', 27, db)  # "Minnesota"

# Decode DataFrame columns
df = decode_dataframe(df, ['STATEFIP', 'SEX'], db)

# Harmonize to NE25 categories
df['ne25_race'] = harmonize_race_ethnicity(df, 'RACE', 'HISPAN')
```

**R:**
```r
source("R/utils/acs/acs_metadata.R")

# Decode values
state <- acs_decode_value("STATEFIP", 27)  # "Minnesota"

# Decode DataFrame columns
df <- acs_decode_column(df, "STATEFIP")

# Search variables
educ_vars <- acs_search_variables("education")
```

### Key Benefits

- **Precise transformations:** Know exactly what IPUMS codes mean
- **Automated validation:** Check categorical values against DDI
- **Reduced errors:** No guesswork in code-to-label mappings
- **Self-documenting:** Auto-generated data dictionaries
- **Category alignment:** Ensure ACS and NE25 categories match for raking

### Documentation

- Transformation mappings: `docs/acs/transformation_mappings.md`
- Query cookbook: `docs/acs/metadata_query_cookbook.md`
- Data dictionary: `docs/acs/data_dictionary.html` (auto-generated)

---

## Pipeline Integration and Relationship

### Six Independent Pipelines

The Kidsights Data Platform operates **six independent, standalone pipelines**:

#### 1. NE25 Pipeline (Primary)
- **Purpose:** Process REDCap survey data from Nebraska 2025 study
- **Data Source:** 4 REDCap projects via REDCapR
- **Architecture:** Hybrid R-Python with Feather files
- **Status:** Production ready, 100% reliability
- **Tables:** `ne25_raw`, `ne25_transformed`, 9 validation/metadata tables

#### 2. ACS Pipeline (Utility)
- **Purpose:** Extract census data from IPUMS USA API for statistical raking
- **Data Source:** IPUMS USA API via ipumspy
- **Architecture:** Python extraction → R validation → Python database
- **Status:** Complete (Phase 11 integration)
- **Tables:** `acs_raw`, `acs_metadata`

#### 3. NHIS Pipeline (Benchmarking)
- **Purpose:** National health survey data for ACEs/mental health comparison
- **Data Source:** IPUMS NHIS API via ipumspy
- **Architecture:** Python extraction → R validation → Python database
- **Status:** Production ready (Phases 1-7 complete)
- **Tables:** `nhis_raw`

#### 4. NSCH Pipeline (Benchmarking)
- **Purpose:** National children's health survey for trend analysis
- **Data Source:** SPSS files from NSCH releases
- **Architecture:** Python SPSS conversion → R validation → Python database
- **Status:** Production ready (7/8 years loaded)
- **Tables:** `nsch_{year}_raw` (year-specific tables)

#### 5. Raking Targets Pipeline (Utility)
- **Purpose:** Generate population-representative raking targets for post-stratification weighting
- **Data Source:** ACS, NHIS, NSCH databases
- **Architecture:** R statistical estimation → DuckDB
- **Status:** Production ready (180 targets generated)
- **Tables:** `raking_targets_ne25`

#### 6. Imputation Pipeline (Utility)
- **Purpose:** Multiple imputation for geographic, sociodemographic, childcare, mental health, and child ACEs uncertainty
- **Data Source:** `ne25_transformed` table
- **Architecture:** 11-stage sequential (Geography → Sociodem → Childcare → Mental Health → Child ACEs) → Variable-specific tables
- **Status:** Production ready (M=5 imputations, 85,746 rows, 30 variables, ~3 min)
- **Tables:** 30 tables per study: `{study_id}_imputed_{variable}` (3 geography + 7 sociodem + 4 childcare + 7 mental health/parenting + 9 child ACEs)

### Design Decision: Why Separate?

**No automatic integration** - Pipelines do NOT run as part of each other.

**Rationale:**
1. **Different cadences:** NE25 runs frequently (new survey data), ACS/NHIS/NSCH run rarely (annual updates), Raking/Imputation run on-demand
2. **Different dependencies:** NE25 requires REDCap API, ACS/NHIS require IPUMS API, NSCH requires SPSS files, Imputation requires completed NE25 data
3. **Future use case:** Supporting data needed for post-stratification raking and benchmarking
4. **Modular design:** Each pipeline can be maintained/tested independently
5. **Reusability:** Raking Targets and Imputation pipelines are reusable utilities for multiple studies

### How They Work Together

```
NE25 Pipeline          ACS Pipeline       NHIS Pipeline      NSCH Pipeline
     ↓                      ↓                   ↓                  ↓
ne25_raw                acs_raw            nhis_raw          nsch_2023_raw
ne25_transformed            ↓                   ↓                  ↓
     ↓                      ↓                   ↓                  ↓
     ↓                      └───────────────────┴──────────────────┘
     ↓                                      ↓
     ↓                          RAKING TARGETS PIPELINE
     ↓                             (Phase 5 complete)
     ↓                                      ↓
     ↓                            raking_targets_ne25
     ↓                          (180 population targets)
     ↓                                      ↓
     └──────────────────────────────────────┘
                           ↓
              IMPUTATION PIPELINE (7-Stage Sequential)
                           ↓
        ┌──────────────────┼──────────────────────────┐
        ↓                  ↓                           ↓
   Geography (3)      Sociodem (7)              Childcare (4)
   imputed_puma       imputed_female            imputed_cc_receives_care
   imputed_county     imputed_raceG             imputed_cc_primary_type
imputed_census_tract  imputed_educ_mom          imputed_cc_hours_per_week
     (M=5)            imputed_educ_a2     imputed_childcare_10hrs_nonfamily
   25,480 rows        imputed_income                 (M=5)
                      imputed_family_size          24,718 rows
                      imputed_fplcat
                           (M=5)
                        26,438 rows
        ↓                  ↓                           ↓
        └──────────────────┴───────────────────────────┘
                           ↓
              Helper Functions: get_complete_dataset()
                 (14 variables joined, M=5)
                           ↓
                  RAKING IMPLEMENTATION
                      (Future Phase)
                           ↓
              Apply raking targets across M=5
              completed imputation datasets
                           ↓
              Generate raked population estimates
              with uncertainty from geographic,
              sociodemographic, and childcare
              imputation plus survey sampling
```

### Raking Targets Pipeline (October 2025)

**Status:** Implemented and operational

**Purpose:** Generate population-representative raking targets for post-stratification weighting of NE25 survey data

**Architecture Diagram:**

```
ACS (25 estimands) →  ╮
NHIS (1 estimand)  → ─┤ Phase 1-4: Estimation → Phase 5: Consolidation → DuckDB
NSCH (4 estimands) →  ╯   GLM/GLMM models         180 raking targets      raking_targets_ne25
```

**Key Features:**
- **30 Estimands:** Demographics (ACS), parent mental health (NHIS), child health (NSCH)
- **Age-Specific:** 6 age groups (0-5 years) = 180 total targets
- **Statistical Methods:** GLM for ACS/NHIS, GLMM with state random effects for NSCH
- **Database Integration:** Indexed table for efficient querying
- **Execution:** Streamlined pipeline (~2-3 minutes)

**Pipeline Location:** `scripts/raking/ne25/run_raking_targets_pipeline.R`

**Documentation:** [docs/raking/NE25_RAKING_TARGETS_PIPELINE.md](../raking/NE25_RAKING_TARGETS_PIPELINE.md)

**Future Integration:**
- **Raking Implementation:** Apply targets to NE25 using survey package (Phase 6+)
- **Benchmarking Module:** Compare NE25 to national estimates from NHIS/NSCH

### When to Run Each Pipeline

**NE25 Pipeline:**
```bash
# Run whenever new REDCap data is available
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

**ACS Pipeline:**
```bash
# Run annually or when new ACS data is released
python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2019-2023
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_acs_pipeline.R --state nebraska --year-range 2019-2023 --state-fip 31
python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023
```

**NHIS Pipeline:**
```bash
# Run annually when new NHIS data is released
python pipelines/python/nhis/extract_nhis_data.py --year-range 2019-2024
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" pipelines/orchestration/run_nhis_pipeline.R --year-range 2019-2024
python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024
```

**NSCH Pipeline:**
```bash
# Run when new NSCH year is released
python scripts/nsch/process_all_years.py --years 2023

# Or process all years
python scripts/nsch/process_all_years.py --years all
```

**Raking Targets Pipeline:**
```bash
# Run when ACS/NHIS/NSCH data is updated or NE25 raking targets need refresh
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/run_raking_targets_pipeline.R

# Verify results
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/raking/ne25/verify_pipeline.R
```

**Imputation Pipeline:**
```bash
# Setup database schema (one-time, study-specific)
python scripts/imputation/00_setup_imputation_schema.py --study-id ne25

# Run full 7-stage pipeline (geography + sociodem + childcare)
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/run_full_imputation_pipeline.R

# Validate results
python -m python.imputation.helpers
```

---

## Related Documentation

- **Pipeline Execution Details:** [PIPELINE_STEPS.md](PIPELINE_STEPS.md)
- **Directory Structure:** [../DIRECTORY_STRUCTURE.md](../DIRECTORY_STRUCTURE.md)
- **Quick Reference:** [../QUICK_REFERENCE.md](../QUICK_REFERENCE.md)
- **ACS Documentation:** [../acs/README.md](../acs/README.md)
- **NHIS Documentation:** [../nhis/README.md](../nhis/README.md)
- **NSCH Documentation:** [../nsch/README.md](../nsch/README.md)

---

*Last Updated: October 2025*

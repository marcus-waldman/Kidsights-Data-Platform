# Mplus IRT Calibration Workflow

**Version:** 1.1
**Last Updated:** November 2025
**Status:** In Development (Active Bug Fixes)

---

## Overview

This document provides a complete workflow for recalibrating the **Kidsights developmental and behavioral scale** using Item Response Theory (IRT) in Mplus. The workflow combines historical Nebraska studies (NE20, NE22, USA24), current NE25 data, and national benchmarking samples (NSCH 2021, 2022) to create robust, population-representative item parameters.

**Workflow Stages:**
0. **Visual Quality Assurance (REQUIRED)** - Mandatory visual inspection of age-response patterns
1. **Data Preparation** - Create calibration dataset using R
2. **Mplus Calibration** - Estimate IRT parameters (graded response model)
3. **Parameter Extraction** - Automated extraction using MplusAutomation and codebook update
4. **Scoring Application** - Apply parameters to score NE25 data

**Estimated Time:** 2-4 hours (including Mplus model estimation + 15-30 min QA)
**Key Improvement:** Stage 3 now fully automated (30 seconds vs 15-30 minutes manual extraction)

---

## Stage 0: Visual Quality Assurance (REQUIRED)

**Purpose:** Mandatory visual inspection of item quality before formal Mplus calibration

**Tool:** Age-Response Gradient Explorer Shiny app

```r
# Launch interactive explorer
shiny::runApp("scripts/shiny/age_gradient_explorer")
```

### Quality Assurance Checklist

**⚠️ You MUST complete all 4 checks before proceeding to Stage 1:**

- [ ] **Developmental Gradients** - Verify positive age-response correlations for skill items
  - Items should show increasing response values with age
  - GAM curves should trend upward for developmental items
  - Flag items with flat or negative trends

- [ ] **Negative Correlation Flags** - Investigate items with unexpected patterns
  - Review all items flagged with NEGATIVE_CORRELATION
  - Document decisions: exclude, recode, or justify retention
  - Export list of items to exclude from calibration

- [ ] **Category Separation** - Check box plot overlap
  - Overlapping boxes indicate poor discrimination between categories
  - Consider collapsing categories or excluding items with severe overlap
  - Verify adequate spread in age distributions across response levels

- [ ] **Study Consistency** - Compare patterns across all 6 studies
  - NE20, NE22, NE25 (Nebraska studies)
  - NSCH21, NSCH22 (National benchmarking samples)
  - USA24 (National validation study)
  - Flag items with dramatically different patterns across studies

### Timing

- **Startup:** 3-5 seconds (data loading)
- **Per-item review:** 30-60 seconds (thorough inspection)
- **Complete review:** 15-30 minutes for all 308 items

### Output

**Required documentation before proceeding:**
- List of items to exclude from calibration (with justification)
- Items requiring recoding or category collapsing
- Items flagged for further investigation
- Quality summary notes for calibration documentation

### Next Step

Once QA is complete and exclusion list is documented, proceed to Stage 1 (Data Preparation) with the refined item list.

---

## Stage 1: Data Preparation

### 1.1 Prerequisites

**Required:**
- ✅ All pipelines run successfully (NE25, NSCH, historical data imported)
- ✅ R 4.5.1 installed with required packages
- ✅ DuckDB database populated: `data/duckdb/kidsights_local.duckdb`
- ✅ Codebook available: `codebook/data/codebook.json`

**Validation:**
```r
# Check database connection
library(duckdb)
conn <- duckdb::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = TRUE)
DBI::dbListTables(conn)
DBI::dbDisconnect(conn)

# Should show tables including:
# - ne25_transformed
# - historical_calibration_2020_2024
# - nsch_2021_raw
# - nsch_2022_raw
```

### 1.2 Run Calibration Pipeline

**Full Pipeline (Recommended):**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R
```

**Skip Long Format (Faster):**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/irt_scoring/run_calibration_pipeline.R --skip-long-format
```

**Expected Output:**
```
[1/6] Creating/updating calibration tables...
  ✓ Created ne20_calibration (37,546 records)
  ✓ Created ne22_calibration (2,431 records)
  ✓ Created ne25_calibration (3,507 records)
  ✓ Created nsch21_calibration (20,719 records - full data)
  ✓ Created nsch22_calibration (19,741 records - full data)
  ✓ Created usa24_calibration (1,600 records)

[2/6] Running quality checks...
  ✓ All validation tests passed

[3/6] Creating long format dataset...
  - Development sample: 529,668 rows (devflag=1)
  - Holdout sample: 786,723 rows (devflag=0)
  - Total: 1,316,391 rows
  ✓ Created calibration_dataset_long

[4/6] Exporting to Mplus format...
  - Sampling NSCH: 1,000 records per year
  - Combined dataset: 47,084 records
  ✓ Exported to mplus/calibdat.dat (38.71 MB)

[5/6] Validating output...
  ✓ Mplus compatibility verified

[6/6] Summary statistics:
  Study Record Counts (in Mplus export):
    NE20   (study_num=1):  37,546 records ( 79.7%)
    NE22   (study_num=2):   2,431 records (  5.2%)
    NE25   (study_num=3):   3,507 records (  7.4%)
    NSCH21 (study_num=5):   1,000 records (  2.1%)
    NSCH22 (study_num=6):   1,000 records (  2.1%)
    USA24  (study_num=7):   1,600 records (  3.4%)
    TOTAL                  47,084 records (100.0%)

  Database Tables Created:
    - calibration_dataset_2020_2025 (wide format, 47,084 records)
    - calibration_dataset_long (long format, 1,316,391 rows)

  Output Files:
    - mplus/calibdat.dat (38.71 MB)
```

**Execution Time:** ~5-7 minutes (full pipeline), ~3-5 minutes (--skip-long-format)

**Long Format Benefits:**
- Includes full NSCH holdout sample (786K rows) for external validation
- devflag: 0=holdout, 1=development (used for calibration)
- maskflag: 0=original, 1=QA-cleaned (excluded observations)
- Required for Age Gradient Explorer's masking toggle feature

**Legacy Command (Deprecated):**

The old `prepare_calibration_dataset.R` script still works but is no longer documented. Use `run_calibration_pipeline.R` for new workflows.

### 1.3 Validate Output

```bash
# Test Mplus file compatibility
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/irt_scoring/test_mplus_compatibility.R
```

**Expected Result:**
```
[OK] MPLUS COMPATIBILITY TEST PASSED

The .dat file meets all Mplus format requirements:
  - Space-delimited format
  - Missing values as '.' (read as NA)
  - No column headers
  - Numeric-only values

File ready for Mplus IRT calibration: mplus/calibdat.dat
```

### 1.4 Data Quality Fixes (November 2025)

⚠️ **Development Status:** Recent bug fixes have been implemented to improve calibration data quality. The pipeline is under active validation.

**Three Critical Fixes (Issue #6):**

1. **NSCH Missing Code Contamination** (Commits: 20e3cf5, 25d2b47)
   - **Problem:** NSCH variables with values >= 90 (e.g., 90="Not applicable", 95="Refused", 97="Don't know", 98="Missing", 99="Missing") were treated as valid response categories
   - **Impact:** Dichotomous items showed inflated threshold counts (e.g., DD201 had 5 thresholds instead of 1)
   - **Fix:** Modified `recode_nsch_2021.R` and `recode_nsch_2022.R` to recode values >= 90 to NA before transformations
   - **Validation:** After fix, DD201 values: {0, 1}, max=1 (correct)

2. **Missing Study Field** (Commit: d72afaa)
   - **Problem:** NSCH data lacked study identifier column after helper function processing
   - **Impact:** Combined dataset showed `study = NA` for NSCH records, preventing study-level tracing
   - **Fix:** Added explicit study field assignment in `prepare_calibration_dataset.R`
   - **Validation:** All 6 studies now properly labeled (NE20, NE22, NE25, NSCH21, NSCH22, USA24)

3. **Syntax Generator Indexing** (Commit: 37d2034)
   - **Problem:** `write_syntax2.R` used positional array indexing instead of category lookup
   - **Impact:** 26 items (EG14b, EG16c, etc.) generated incorrect threshold specifications in Mplus syntax
   - **Fix:** Replaced `Ks[jdx]` with `item_max_category <- categories[jid == jdx] + 1`
   - **Validation:** All items now generate threshold counts matching actual data ranges

**What This Means for Your Calibration:**
- Clean data: No sentinel values (90-99) contaminating item responses
- Accurate syntax: Threshold specifications match actual category ranges
- Traceable sources: All records properly labeled with study identifiers

**Verify Before Proceeding:** If you generated calibration data before November 2025, re-run `prepare_calibration_dataset.R` to get clean data.

---

## Stage 2: Mplus Calibration

### 2.1 Create Mplus Input File

Create `mplus/calibration.inp` with the following structure:

```
TITLE:
    Kidsights IRT Calibration
    Multi-Study Dataset (NE20, NE22, NE25, USA24, NSCH21, NSCH22)
    47,084 records, 416 items

DATA:
    FILE = calibdat.dat;

VARIABLE:
    NAMES = study_num id years
        AA10 AA102 AA104 AA105 AA106 AA107 AA108 AA109 AA11 AA110
        AA111 AA112 AA113 AA114 AA115 AA116 AA117 AA12 AA13 AA14
        AA15 AA16 AA2 AA202 AA203 AA20402 AA20403 AA20404 AA20405
        AA20406 AA20407 AA20408 AA20409 AA20410 AA20411 AA20502
        AA20503 AA20504 AA20505 AA20506 AA20507 AA20508 AA20509
        AA20510 AA20511 AA206 AA207 AA208 AA209 AA210 AA211 AA212
        AA213 AA25 AA3 AA4 AA5 AA6 AA7 AA8 AA9 AC601 AC602 AC603
        AC604 AC605 AC606 AC607 AC608 AC609 AC610 ADDLITEM00
        ADDLITEM01 ADDLITEM02 ADDLITEM03 ADDLITEM04 ADDLITEM05
        ADDLITEM06 ADDLITEM07 ADDLITEM08 ADDLITEM09 ADDLITEM10
        ADDLITEM11 ADDLITEM12 ADDLITEM13 ADDLITEM14 BB110 BB111
        BB12 BB13 BB14 BB204 BB205 BB3 BB5 BB6 BB7 BB8 BB9 C001
        C002 C003 C004 C005 C006 C007 C008 C009 C010 C011 C012
        C013 C014 C015 C016 C017 C018 C019 C020 C021 C022 C023
        C024 C025 C026 C027 C028 C029 C029X C030 C030X C031 C032
        C033 C034 C035 C036 C037 C038 C039 C040 C041 C042 C043
        C044 C045 C046 C047 C048 C049 C050 C051 C052 C053 C054
        C055 C056 C057 C058 C059 C060 C061 C062 C063 C064 C065
        C066 C067 C068 C069 C070 C071 C072 C073 C074 C075 C076
        C077 C078 C079 C080 C081 C082 C083 C084 C085 C086 C087
        C088 C089 C090 C091 C092 C093 C094 C095 C096 C097 C098
        C099 C100 C101 C102 C103 C104 C105 C106 C107 C108 C109
        C110 C111 C112 C113 C114 C115 C116 C117 C118 C119 C120
        C121 C122 C123 C124 C125 C126 C127 C128 C129 C130 C131
        C132 C133 C134 C135 C136 C137 C138 C139 CC101 CC102 CC103
        CC104 CC201 CC202 CC203 CC204 CC205 CC206 CC301 CC302
        CC303 CC304 CC305 CC306 CCGROUP CCTYPE CQFA002 CQFA005
        CQFA010A1 CQFA010A2 CQFA010A3 CQFA010A4 CQFA010A5 CQFA010A6
        CQFB002 CQFB007 CQFB008 CQFB009 CQFB011 CQFB012 CQR003
        CQR004 CQR007_1 CQR007_2 CQR007_3 CQR007_4 CQR007_5
        CQR007_6 CQR007_7 CQR013 CQR014X CQR016 CQR022 CQR023
        CREDI001 CREDI005 CREDI017 CREDI019 CREDI020 CREDI021
        CREDI025 CREDI028 CREDI029 CREDI030 CREDI031 CREDI036
        CREDI038 CREDI041 CREDI045 CREDI046 CREDI052 CREDI058
        DD101 DD102 DD103 DD2 DD201 DD202 DD203 DD206 DD207
        DD301 DD302 DD303 DD304 DD305 DD306 DD307 DD308 DD309
        DD310 DD311 DD403 DD405 DD406 DD501 DD502 DD701 DD702
        DD703 DD704 DD705 DD706 DD801 DD802 DD803 ECDI007 ECDI009X
        ECDI010 ECDI011 ECDI014 ECDI015 ECDI015X ECDI016 ECDI017
        ECDI018 NOM001 NOM002 NOM002X NOM003 NOM003X NOM005
        NOM005X NOM006 NOM006X NOM009 NOM012 NOM014 NOM014X
        NOM015 NOM017 NOM017X NOM018 NOM018X NOM019 NOM022
        NOM022X NOM024 NOM024X NOM026 NOM026X NOM028 NOM029
        NOM029X NOM031 NOM033 NOM033X NOM034 NOM034X NOM035
        NOM035X NOM042X NOM044 NOM046X NOM047 NOM047X NOM048X
        NOM049 NOM049X NOM052Y NOM053 NOM053X NOM054X NOM056X
        NOM057 NOM059 NOM059X NOM060Y NOM061 NOM061X NOM062Y
        NOM102 NOM103 NOM104 NOM2202 NOM2205 NOM2208 PS001 PS002
        PS003 PS004 PS005 PS006 PS007 PS008 PS009 PS010 PS011
        PS013 PS014 PS015 PS016 PS017 PS018 PS019 PS020 PS022
        PS023 PS024 PS025 PS026 PS027 PS028 PS029 PS030 PS031
        PS032 PS034 PS035 PS036 PS037 PS038 PS039 PS040 PS041
        PS042 PS043 PS044 PS045 PS046 PS047 PS048 PS049 SF018
        SF019 SF021 SF054 SF093 SF122 SF127;

    USEVARIABLES = <list items for specific domain/scale>;
    MISSING = ALL (.);
    CATEGORICAL = <list categorical items>;
    GROUPING = study_num (1=NE20 2=NE22 3=NE25 5=NSCH21 6=NSCH22 7=USA24);

ANALYSIS:
    TYPE = GENERAL;  ! Graded response model
    ESTIMATOR = WLSMV;  ! Weighted least squares with mean and variance adjustment
    PARAMETERIZATION = THETA;  ! IRT parameterization

MODEL:
    ! Define latent factor structure
    ! Example for single domain:
    F1 BY item1* item2* item3*;  ! * = freely estimate all loadings

    F1@1;  ! Fix factor variance for identification
    [F1@0];  ! Fix factor mean for identification

OUTPUT:
    STANDARDIZED;
    TECH1;  ! Parameter specifications
    TECH4;  ! Latent variable means, covariances, correlations
    TECH10; ! Model fit for each observation

SAVEDATA:
    FILE = calibration_scores.dat;
    SAVE = FSCORES;  ! Save factor scores
```

**Key Decisions:**

1. **GROUPING Variable:** Use `study_num` to check for differential item functioning (DIF) across studies
   - If DIF is minimal, collapse groups for final calibration
   - If DIF is substantial, use multi-group IRT model

2. **ESTIMATOR:** `WLSMV` is recommended for categorical data (graded response model)

3. **Item Selection:** Start with domain-specific subsets (e.g., social-emotional items first)
   - Focus on items with <50% missing in NE25
   - Gradually expand to full item set

### 2.2 Run Mplus Calibration

**Option A: Mplus GUI**
1. Open Mplus software
2. File → Open → Select `mplus/calibration.inp`
3. Run → Run Mplus

**Option B: Command Line (if Mplus is in PATH)**
```bash
mplus mplus/calibration.inp
```

**Expected Execution Time:** 10 minutes to 2 hours (depending on number of items and model complexity)

### 2.3 Interpret Output

**Check `mplus/calibration.out` for:**

1. **Model Convergence:**
   ```
   THE MODEL ESTIMATION TERMINATED NORMALLY
   ```

2. **Model Fit Indices:**
   - **CFI:** > 0.95 (excellent), > 0.90 (acceptable)
   - **TLI:** > 0.95 (excellent), > 0.90 (acceptable)
   - **RMSEA:** < 0.06 (excellent), < 0.08 (acceptable)
   - **SRMR:** < 0.08 (excellent), < 0.10 (acceptable)

3. **Item Parameters:**
   ```
   IRT PARAMETERIZATION

   Item                    Discrimina    Difficulty
                           (a)           (b1) (b2) (b3) (b4)

   ITEM1                   1.234         -2.1  -0.5  0.8  2.3
   ITEM2                   0.987         -1.8  -0.3  1.1  2.6
   ```

   - **Discrimination (a):** Typically 0.5 - 2.5 (higher = more discriminating)
   - **Difficulty (b):** Typically -3 to +3 (lower = easier)

4. **Warnings/Errors:**
   - Check for Heywood cases (negative variances)
   - Look for items with estimation issues
   - Verify no local dependency warnings

---

## Stage 3: Parameter Extraction

### 3.1 Automated Parameter Extraction and Codebook Update

**Use the automated extraction function** to parse Mplus output and update the codebook:

```r
# Run automated parameter extraction
source("scripts/irt_scoring/update_codebook_parameters.R")

# Extract parameters from calibration output and update codebook
stats <- update_codebook_parameters(
  mplus_output_path = "mplus/Kidsights-calibration.out",
  codebook_path = "codebook/data/codebook.json",
  study_name = "NE25",
  factor_name = "kidsights",
  latent_class = 1,
  backup = TRUE,
  verbose = TRUE
)

# View update statistics
cat(sprintf("Items updated: %d\n", stats$items_updated))
cat(sprintf("Items not found: %d\n", stats$items_not_found))
```

**What this function does:**
1. **Parses Mplus Output**: Uses `MplusAutomation::readModels()` to extract item parameters
2. **Extracts Discrimination (α)**: Factor loadings from `.BY` parameters
3. **Extracts Thresholds (τ)**: Difficulty parameters from `Thresholds` section
4. **Matches Items**: Finds items in codebook by `lex_equate` lexicon name
5. **Updates Codebook**: Stores parameters in study-specific IRT parameters
6. **Creates Backup**: Automatically backs up codebook before updating

**Expected Output:**
```
================================================================================
UPDATE CODEBOOK WITH IRT PARAMETERS
================================================================================

Mplus output: mplus/Kidsights-calibration.out
Codebook: codebook/data/codebook.json
Study: NE25
Factor: kidsights

================================================================================
EXTRACT IRT PARAMETERS FROM MPLUS OUTPUT
================================================================================

[1/3] Reading Mplus output file with MplusAutomation...
      [OK] Output file parsed successfully

[2/3] Extracting discrimination parameters (alpha)...
      Extracted 257 discrimination parameters
      Alpha range: [0.003, 3.946]

[3/3] Extracting threshold parameters (tau)...
      Extracted 399 threshold parameters
      Unique items: 257
      Tau range: [-15.252, 12.487]

================================================================================
UPDATE COMPLETE
================================================================================

Summary:
  Study: NE25
  Items updated: 161
  Backup: codebook/data/codebook_backup.json
```

### 3.2 Verify Updated Codebook

**Check parameter storage:**
```r
library(jsonlite)

codebook <- fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)

# Find an item with updated NE25 parameters
sample_item <- codebook$items$AA4

# View parameter structure
cat("Item: AA4\n")
cat("NE25 IRT Parameters:\n")
str(sample_item$psychometric$irt_parameters$NE25)

# Example output:
# List of 4
#  $ factors          : chr "kidsights"
#  $ loadings         : num 0.272
#  $ thresholds       : num -3.625
#  $ param_constraints: list()
```

**Parameter Storage Format:**
```json
"irt_parameters": {
  "NE25": {
    "factors": ["kidsights"],
    "loadings": [1.234],
    "thresholds": [0.567, 1.234, 2.345],
    "param_constraints": []
  }
}
```

**Key Features:**
- `factors`: Factor name used in MODEL syntax (typically "kidsights" for Kidsights scale)
- `loadings`: Single discrimination parameter per item
- `thresholds`: Array of difficulty parameters (ordered by response category)
- `param_constraints`: Preserved from existing codebook (not modified)

---

## Stage 4: Scoring Application

### 4.1 Apply IRT Scoring to NE25 Data

**Create scoring script: `scripts/irt_scoring/score_ne25_irt.R`**

```r
library(duckdb)
library(dplyr)
library(jsonlite)
library(mirt)  # For IRT scoring

# Load codebook with IRT parameters
codebook <- fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)

# Extract items with IRT parameters
items_with_params <- names(codebook$items)[sapply(codebook$items, function(x) {
  !is.null(x$irt_params)
})]

# Load NE25 data
conn <- duckdb::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = TRUE)
ne25_data <- DBI::dbGetQuery(conn, "SELECT * FROM ne25_transformed WHERE eligible = TRUE")
DBI::dbDisconnect(conn)

# Score each domain (example for social-emotional domain)
se_items <- c("PS001", "PS002", "PS003", ...)  # List items in domain

# Create IRT scoring function
score_domain <- function(data, items, codebook) {
  # Extract item responses
  item_data <- data %>% select(all_of(items))

  # Build mirt model specification from codebook parameters
  # ... (implementation depends on mirt package)

  # Calculate theta scores
  theta_scores <- fscores(model, response.pattern = item_data)

  return(theta_scores)
}

# Apply scoring
ne25_data$se_theta <- score_domain(ne25_data, se_items, codebook)

# Store scored data
conn <- duckdb::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = FALSE)
DBI::dbWriteTable(conn, "ne25_scored", ne25_data, overwrite = TRUE)
DBI::dbDisconnect(conn)
```

### 4.2 Validate IRT Scores

```r
# Check score distribution
summary(ne25_data$se_theta)
hist(ne25_data$se_theta, main = "Social-Emotional Theta Scores", xlab = "Theta")

# Compare to sum scores
ne25_data$se_sum <- rowSums(ne25_data[, se_items], na.rm = TRUE)
cor(ne25_data$se_theta, ne25_data$se_sum, use = "complete.obs")
# Should be high correlation (r > 0.90)

# Check for outliers
extreme_scores <- ne25_data %>% filter(abs(se_theta) > 3)
cat(sprintf("Extreme scores (|theta| > 3): %d (%.1f%%)\n",
            nrow(extreme_scores),
            (nrow(extreme_scores) / nrow(ne25_data)) * 100))
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Mplus Estimation Fails to Converge

**Symptoms:**
```
THE MODEL ESTIMATION DID NOT TERMINATE NORMALLY DUE TO A NON-POSITIVE
DEFINITE G MATRIX
```

**Solutions:**
1. **Reduce model complexity:** Start with fewer items
2. **Check for problematic items:** Remove items with <5% endorsement or >95% endorsement
3. **Increase iterations:** Add `MITER = 1000;` to ANALYSIS section
4. **Try different estimator:** Change from WLSMV to MLR

#### Issue 2: Poor Model Fit

**Symptoms:**
- CFI < 0.90
- RMSEA > 0.08
- TLI < 0.90

**Solutions:**
1. **Check item quality:** Remove items with low discrimination (a < 0.5)
2. **Test unidimensionality:** Use exploratory factor analysis first
3. **Allow correlated errors:** Add residual correlations for related items
4. **Consider multi-dimensional model:** Split into subdomains

#### Issue 3: High Missingness in Calibration Data

**Symptoms:**
- Many items with >95% missing across all studies
- Model won't converge due to insufficient data

**Solutions:**
1. **Focus on well-covered items:** Use only items with <50% missing
2. **Age-stratified calibration:** Calibrate separately by age group
3. **Multiple imputation:** Impute missing item responses before calibration

#### Issue 4: Differential Item Functioning (DIF) Detected

**Symptoms:**
- Item parameters differ significantly across study groups
- Model fit poor when grouping by study

**Solutions:**
1. **Test for DIF:** Use `MODINDICES` in Mplus to identify DIF items
2. **Free problematic parameters:** Allow different thresholds for DIF items
3. **Remove DIF items:** Exclude items with substantial DIF from calibration
4. **Use anchor items:** Fix parameters for non-DIF items

---

## Performance Benchmarks

**Stage 1: Data Preparation**
- Execution time: 28 seconds
- Output size: 38.71 MB

**Stage 2: Mplus Calibration**
- Execution time: 10-120 minutes (varies by model complexity)
- Small model (20 items, 1 factor): ~10 minutes
- Medium model (100 items, 3 factors): ~45 minutes
- Large model (400+ items, 8 factors): ~2 hours

**Stage 3: Parameter Extraction**
- Automated extraction: ~30 seconds
- Codebook update: ~5 seconds
- Total: <1 minute (was 15-30 minutes manual)

**Stage 4: Scoring Application**
- Execution time: ~5 minutes for 3,500 NE25 records

**Total Workflow:** 2-4 hours

---

## Next Steps

After successful IRT calibration:

1. **Validate Scores:** Compare IRT scores to existing sum scores
2. **Document Parameters:** Update all documentation with new IRT parameters
3. **Create Scoring Functions:** Develop production-ready IRT scoring functions
4. **Update Pipeline:** Integrate IRT scoring into NE25 pipeline
5. **Generate Reports:** Create psychometric reports for stakeholders

---

## References

**Mplus Resources:**
- [Mplus User's Guide](https://www.statmodel.com/ugexcerpts.shtml)
- [IRT Models in Mplus](https://www.statmodel.com/download/irtOct13.pdf)
- [Categorical Data Analysis](https://www.statmodel.com/download/CatAnalysis.pdf)

**IRT Theory:**
- Embretson & Reise (2000). *Item Response Theory for Psychologists*
- Baker & Kim (2017). *The Basics of Item Response Theory Using R*

**Validation Studies:**
- See `todo/calibration_dataset_validation_summary.md` for detailed validation results

---

**Document Version:** 1.0
**Last Updated:** January 2025
**Maintained By:** Kidsights Data Platform Team

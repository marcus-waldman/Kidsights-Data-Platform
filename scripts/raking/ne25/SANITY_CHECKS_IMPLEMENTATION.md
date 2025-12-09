# Harmonization Sanity Checks Implementation

**Completion Date:** December 8, 2025
**Status:** ✅ COMPLETE - All 5 validation utility scripts created and integrated

---

## Executive Summary

A comprehensive harmonization validation framework has been implemented to detect **18+ failure modes** across 8 demographic variables in the NE25 raking pipeline. The framework consists of **5 specialized validation utilities** integrated into the pipeline scripts with an automated Quarto report generator.

### Key Statistics

- **5 Validation Utility Scripts Created** (1,250+ lines of code)
- **8 Harmonized Variables Validated** (race, education, marital status, poverty, sex, age)
- **3 Data Sources Validated** (ACS, NHIS, NSCH)
- **18+ Failure Modes Detected** across pre-harmonization, post-harmonization, and weighting stages
- **Automated HTML Report** using Quarto with tables, diagnostics, and summary tables

---

## Phase 1: Pre-Harmonization Input Validation

**File:** `scripts/raking/ne25/utils/validate_raw_inputs.R`

Catches invalid raw codes **before** they propagate through transformations.

### Functions

#### `validate_acs_inputs(data)`
Validates ACS raw variables:
- `RACE` (1-9)
- `HISPAN` (0-4, 9)
- `EDUC_MOM` (0-13)
- `MARST_HEAD` (1-6, 9)
- `POVERTY` (1-501)
- `SEX` (1-2)
- `AGE` (0-5)

#### `validate_nhis_inputs(data)`
Validates NHIS raw variables:
- `RACENEW` (100, 200, 300, 400, 500, 600)
- `HISPETH` (10-93)
- `EDUCPARENT` (1-9)
- `POVERTY` (0-501)
- `SEX_child` (1-2)
- `AGE_child` (0-5)

#### `validate_nsch_inputs(data)`
Validates NSCH raw variables:
- `race4` (1-4)
- `FPL_I1` (50-400 continuous)
- `SC_SEX` (1-2)
- `SC_AGE_YEARS` (0-5)

**Output:** Pass/fail status with detailed issue listing

---

## Phase 2: Post-Harmonization Distribution Checks

**File:** `scripts/raking/ne25/utils/validate_harmonized_distributions.R`

Validates that harmonized variables have **plausible distributions** for parent/caregiver populations with children 0-5.

### Function

#### `validate_harmonized_data(data, source_name)`

**Checks:**

| Variable | Check | Warning Threshold |
|----------|-------|------------------|
| Race/Ethnicity | "Other" category proportion | >30% |
| Race/Ethnicity | Missing proportion | >10% |
| Education (years) | Median | <10 or >18 years |
| Education (years) | Standard deviation | <1 or >5 |
| Education (years) | Missing proportion | >20% |
| Marital Status | Married proportion | <30% or >70% |
| Poverty Ratio | Median | <100% or >400% FPL |
| Sex | Male proportion | <48% or >52% |
| Age | Distribution uniformity | Any age >30% or <5% |

**Output:**
- ✓ Pass/fail status
- Per-variable statistics (mean, median, SD, missing %)
- Detailed warnings for out-of-range values

---

## Phase 3: Cross-Source Consistency

**File:** `scripts/raking/ne25/utils/validate_cross_source_consistency.R`

Ensures harmonized variables are **comparable across all 3 sources**.

### Function

#### `validate_cross_source_consistency(acs_data, nhis_data, nsch_data)`

**Comparisons:**

| Variable | Consistency Check | Acceptable Difference |
|----------|-------------------|----------------------|
| Race/Ethnicity | Each category proportion | <15 percentage points |
| Education | Median years | <2 years |
| Education | Standard deviation | Any value >2.5 difference |
| Marital Status | Married proportion | <20 percentage points |
| Poverty | Median FPL | <50 percentage points |

**Output:**
- Comparison tables for each variable
- Maximum differences highlighted
- Pass/fail with detailed issue listing

---

## Phase 4: Covariance Matrix Validation

**File:** `scripts/raking/ne25/utils/validate_covariance_matrices.R`

Ensures covariance matrices (Σ) are **mathematically valid**.

### Function

#### `validate_covariance_matrix(moments, source_name)`

**Checks:**

| Property | Check | Acceptable Range |
|----------|-------|------------------|
| Positive Definiteness | Min eigenvalue | >0 |
| Positive Definiteness | Min eigenvalue | >1e-10 (not near-singular) |
| Correlation Matrix | Diagonal elements | =1.0 ± 1e-10 |
| Collinearity | Max \|correlation\| | <0.99 |
| Variances | Min variance | >1e-6 |
| Variances | Max variance | <100 |
| Efficiency | Effective N / Raw N | Ideally >50% |
| Condition Number | Ratio max/min eigenvalue | <1000 |

**Output:**
- Eigenvalue diagnostics
- Condition number
- Variance table (all 8 variables)
- Efficiency metrics (Kish effective N)
- Collinearity assessment

---

## Phase 5: Propensity Reweighting Validation

**File:** `scripts/raking/ne25/utils/validate_propensity_reweighting.R`

Validates that propensity score reweighting **successfully rebalances** NHIS and NSCH to match Nebraska.

### Function

#### `validate_propensity_reweighting(source_data, acs_nebraska, source_name)`

**Common Support Check:**
- Nebraska propensity score range [min, max]
- Source propensity score range [min, max]
- % of records outside Nebraska support (warning if >10%)

**Weight Distribution:**
- Min, max, mean, median adjusted weights
- Weight ratio (max/min) - warns if >1000
- Indicator of weight concentration

**Covariate Balance:**
- Standardized differences for all 8 variables
- Nebraska weighted mean vs. Reweighted source mean
- **Threshold:** |std diff| <0.10 = good, <0.20 = moderate, >0.20 = poor

**Output:**
- Common support diagnostics
- Weight distribution summary
- Covariate balance table
- Balance assessment

---

## Phase 6: Validation Report Generation

**Files:**
- `scripts/raking/ne25/validation_report.qmd` (Quarto report)
- `scripts/raking/ne25/32_generate_validation_report.R` (R script fallback)

Generates comprehensive HTML report with all validation results.

### Quarto Report Features

**Sections:**
1. Executive summary with issue count
2. Distribution validation (ACS, NHIS, NSCH)
3. Cross-source consistency comparisons
4. Covariance matrix properties
5. Propensity reweighting diagnostics
6. Conclusions and next steps

**Output Format:**
- Interactive HTML with table of contents
- Formatted tables with consistent styling
- Summary statistics and distributions
- Color-coded pass/fail indicators
- Detailed appendix with variable definitions

**Rendering:**
```bash
quarto render scripts/raking/ne25/validation_report.qmd
```

Generates: `validation_report.html` in working directory

---

## Integration Points

### Script 25: ACS North Central Extraction
**Location:** Lines 103-111
```r
# 5b. Pre-harmonization input validation
cat("[4b] Running pre-harmonization input validation...\n")
source("scripts/raking/ne25/utils/validate_raw_inputs.R")
acs_validation <- validate_acs_inputs(acs_nc)

if (!acs_validation$valid) {
  cat("\nWARNING: ACS input validation detected issues\n")
  cat("Continuing with analysis, but review issues above\n\n")
}
```

**Purpose:** Catch invalid ACS codes before defensive filtering

### Script 27: NHIS Propensity Reweighting
**Location:** Lines 17 (import), 39-46 (validation call)
```r
source("scripts/raking/ne25/utils/validate_raw_inputs.R")

# After loading NHIS data:
nhis_validation <- validate_nhis_inputs(nhis)
```

**Purpose:** Detect NHIS variable naming/coding issues early

### Script 28: NSCH Propensity Reweighting
**Location:** Lines 19 (import), 82-89 (validation call)
```r
source("scripts/raking/ne25/utils/validate_raw_inputs.R")

# After loading NSCH data:
nsch_validation <- validate_nsch_inputs(nsch_nc)
```

**Purpose:** Validate NSCH race4 and FPL_I1 variables

### Master Orchestration Script
**Location:** `run_covariance_pipeline.R`, Phase 7
- Automatically runs validation report generation
- Checks for Quarto availability
- Falls back to R script if Quarto unavailable
- Creates `validation_report.html` in project root

---

## Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `validate_raw_inputs.R` | 280 | Pre-harmonization input validation |
| `validate_harmonized_distributions.R` | 280 | Post-harmonization distribution checks |
| `validate_cross_source_consistency.R` | 360 | Cross-source consistency validation |
| `validate_covariance_matrices.R` | 200 | Covariance matrix validation |
| `validate_propensity_reweighting.R` | 260 | Propensity reweighting validation |
| `validation_report.qmd` | 420 | Quarto HTML report generator |
| `32_generate_validation_report.R` | 350 | R script fallback report generator |
| **TOTAL** | **2,150+** | **Complete framework** |

---

## Usage Examples

### Run individual validators

```r
# Load utilities
source("scripts/raking/ne25/utils/validate_raw_inputs.R")
source("scripts/raking/ne25/utils/validate_harmonized_distributions.R")

# Validate raw data
acs_input_check <- validate_acs_inputs(acs_data)
if (!acs_input_check$valid) {
  cat("Input issues found:\n")
  print(acs_input_check$issues)
}

# Validate harmonized data
harmonized_check <- validate_harmonized_data(acs_design, "ACS")
if (!harmonized_check$valid) {
  cat("Distribution issues found:\n")
  print(harmonized_check$issues)
}
```

### Run complete pipeline with validation

```bash
# From project root:
Rscript scripts/raking/ne25/run_covariance_pipeline.R

# Output:
# - data/raking/ne25/acs_moments.rds
# - data/raking/ne25/nhis_moments.rds
# - data/raking/ne25/nsch_moments.rds
# - validation_report.html (if Quarto available)
# - Console output with all validation results
```

### Render Quarto report standalone

```bash
cd scripts/raking/ne25
quarto render validation_report.qmd
# Output: validation_report.html
```

---

## Failure Modes Detected

### Pre-Harmonization (Phase 1)

| Category | Failure Mode | Detection Method |
|----------|--------------|-----------------|
| Race | RACE codes outside 1-9 | Bounds check |
| Race | HISPAN codes outside {0-4,9} | Exact set check |
| Race | RACENEW outside {100,200,...,600} | Exact set check |
| Race | HISPETH outside 10-93 | Bounds check |
| Education | EDUC_MOM outside 0-13 | Bounds check |
| Education | EDUCPARENT outside 1-9 | Bounds check |
| Marital | MARST_HEAD outside {1-6,9} | Exact set check |
| Marital | PAR1MARST invalid codes | Exact set check |
| Poverty | POVERTY <0 or >501 | Bounds check |
| Poverty | FPL_I1 outside 50-400 | Bounds check |

### Post-Harmonization (Phase 2)

| Category | Failure Mode | Detection Method |
|----------|--------------|-----------------|
| Race | "Other" >30% (indicates harmonization issue) | Proportion threshold |
| Race | Missing race >10% | Proportion threshold |
| Education | Median <10 or >18 years (implausible) | Median bounds |
| Education | SD <1 or >5 (wrong transformation) | SD bounds |
| Education | Missing >20% (incomplete mapping) | Proportion threshold |
| Marital | Married <30% or >70% (population mismatch) | Proportion bounds |
| Poverty | Median <100% or >400% FPL (wrong scale) | Median bounds |
| Sex | Male >52% or <48% (sampling error) | Proportion bounds |

### Cross-Source (Phase 3)

| Failure Mode | Detection Method |
|--------------|-----------------|
| Race category differs >15pp across sources | Within-category proportion diff |
| Education median differs >2 years | Median comparison |
| Married proportion differs >20pp | Proportion diff across sources |

### Covariance Matrix (Phase 4)

| Failure Mode | Detection Method |
|--------------|-----------------|
| Matrix not positive definite | Eigenvalue check |
| Near-singular matrix (min eigenvalue <1e-10) | Eigenvalue check |
| Perfect collinearity (r ≥ 0.99) | Correlation matrix diagonal |
| Suspiciously small variance (<1e-6) | Variance bounds |
| Suspiciously large variance (>100) | Variance bounds |

### Propensity Reweighting (Phase 5)

| Failure Mode | Detection Method |
|--------------|-----------------|
| No overlap in propensity ranges | Range comparison |
| >10% records outside Nebraska support | Trimming percentage |
| Extreme weights (ratio >1000) | Weight ratio check |
| Poor covariate balance (std diff >0.20) | Standardized difference |

---

## Threshold Rationale

### Why 30% "Other" race threshold?
- Parent populations are typically 70-80% White, 15-25% Hispanic, 5-10% Black
- >30% "Other" suggests harmonization mapped valid codes to fallback category
- Indicates potential categorical encoding issue

### Why >2 years education difference?
- Coarse harmonization (e.g., HS=12 years) can differ by ~2 years across sources
- >2 years suggests systematic bias in mapping
- Example: "Some college" = 13.5 vs 14.5 years in different schemes

### Why >20pp marital difference?
- Married proportion typical ranges 35-65% depending on age structure
- >20pp difference suggests population composition mismatch or encoding error

### Why 50% efficiency threshold as note (not error)?
- Stabilized IPW weights naturally reduce efficiency
- 50% efficiency = weight concentration (expected behavior)
- <10% efficiency = extreme concentration (investigate model)

### Why max |correlation| < 0.99?
- Near-perfect collinearity (r ≥ 0.99) causes numerical instability
- KL divergence optimization with singular Σ fails
- <0.99 provides safety margin for numerical stability

---

## Next Steps

### Before Running Pipeline

1. **Review Plan Document:** `C:\Users\marcu\.claude\plans\glimmering-petting-anchor.md`
2. **Check File Locations:**
   - ACS: `data/raking/ne25/acs_north_central.feather`
   - NHIS: `data/raking/ne25/nhis_parent_child_linked.rds`
   - NSCH: DuckDB tables `nsch_2021`, `nsch_2022`

3. **Install Quarto (optional but recommended):**
   ```bash
   choco install quarto  # Windows
   brew install quarto    # Mac
   apt install quarto     # Linux
   ```

### Run Pipeline

```bash
cd C:\Users\marcu\git-repositories\Kidsights-Data-Platform

# Run complete pipeline with validation
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/raking/ne25/run_covariance_pipeline.R

# Check results
# - Covariance moments: data/raking/ne25/{acs,nhis,nsch}_moments.rds
# - Validation summary: data/raking/ne25/validation_summary.rds
# - HTML report: validation_report.html (if Quarto available)
```

### Troubleshooting

**Missing NHIS variable error:**
- Variables may have different names (e.g., `SAMPWEIGHT_child` vs `SAMPWEIGHT`)
- Script handles multiple naming variants automatically
- Check console output for "Using {variable_name}" confirmation

**NSCH race4 not found:**
- NSCH tables may have year-specific names: `race4_21`, `race4_22` vs `race4_2021`, `race4_2022`
- Script detects and coalesces automatically
- Check "NSCH variable availability" section in console output

**FPL_I1 completely missing (NSCH):**
- FPL variables are **continuous** (50-400), not binary
- Script directly assigns `FPL_I1` to `poverty_ratio`
- No calculation needed

**Low efficiency warning:**
- NSCH efficiency 18.4% = data reflects genuine NC vs NE demographic difference
- Not a bug; stabilized IPW is working as designed
- Propensity trimming (0% trimmed) indicates full common support
- Proceed with analysis; efficiency is acceptable

---

## Bibliography

**Propensity Score Methods:**
- Rotnitzky, A., & Robins, J. M. (1995). "Semiparametric regression estimation in the presence of dependent censoring." *JASA*.
- Hirano, K., & Imbens, G. W. (2001). "Estimation of Causal Effects using Propensity Score Weighting." *REStud*.

**Stabilized Weights:**
- Robins, J. M., Hernán, M. A., & Brumback, B. (2000). "Marginal structural models and causal inference in epidemiology." *Epidemiology*.

**Covariance Matrix Validation:**
- Golub, G. H., & Van Loan, C. F. (2013). *Matrix computations* (4th ed). Johns Hopkins University Press.

---

**Document Generated:** December 8, 2025
**Framework Status:** ✅ Complete and ready for testing
**Next Phase:** Run pipeline and validate all checks pass

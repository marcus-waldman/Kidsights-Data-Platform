# Adding a New Study to the Imputation Pipeline

**Guide for adding future studies (ia26, co27, etc.) to the multi-study imputation system.**

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Configuration Requirements](#configuration-requirements)
3. [Study-Specific Customization](#study-specific-customization)
4. [Validation Checklist](#validation-checklist)
5. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Automated Setup (Recommended)

Use the automated setup script to scaffold a new study:

```bash
# Example: Adding Iowa 2026 study
python scripts/imputation/create_new_study.py \
  --study-id ia26 \
  --study-name "Iowa 2026"
```

This will:
- ✅ Create directory structure (`scripts/imputation/ia26/`, `data/imputation/ia26/`)
- ✅ Generate configuration file (`config/imputation/ia26_config.yaml`)
- ✅ Copy and adapt pipeline scripts from ne25 template
- ✅ Provide next steps for customization

### Manual Setup

If you prefer manual setup:

```bash
# 1. Create directories
mkdir -p scripts/imputation/ia26
mkdir -p data/imputation/ia26/sociodem_feather

# 2. Copy configuration template
cp config/imputation/ne25_config.yaml config/imputation/ia26_config.yaml

# 3. Copy pipeline scripts
cp scripts/imputation/ne25/*.py scripts/imputation/ia26/
cp scripts/imputation/ne25/*.R scripts/imputation/ia26/

# 4. Update all occurrences of 'ne25' to 'ia26' in copied files
```

---

## Configuration Requirements

### 1. Study Configuration File

**Location:** `config/imputation/{study_id}_config.yaml`

**Required Fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `study_id` | Unique study identifier (lowercase alphanumeric) | `ia26` |
| `study_name` | Full descriptive name | `Iowa 2026` |
| `table_prefix` | Database table prefix | `ia26_imputed` |
| `n_imputations` | Number of imputations (M) | `5` |
| `random_seed` | Seed for reproducibility | `42` |
| `data_dir` | Data storage location | `data/imputation/ia26` |
| `scripts_dir` | Scripts location | `scripts/imputation/ia26` |

**Geography Variables:**

List all geographic variables to impute (for records with ambiguous geocoding):

```yaml
geography:
  variables:
    - puma
    - county
    - census_tract
```

**Sociodemographic Variables:**

List all sociodemographic variables to impute via MICE:

```yaml
sociodemographic:
  variables:
    - female
    - raceG
    - educ_mom
    - educ_a2
    - income
    - family_size
    - fplcat
```

### 2. What Needs to Change for Each Study?

#### Required Changes

1. **Study Metadata:**
   - `study_id` - Must be unique across all studies
   - `study_name` - Descriptive name
   - `table_prefix` - Must match `{study_id}_imputed` pattern

2. **Directory Paths:**
   - `data_dir` - Must point to `data/imputation/{study_id}/`
   - `scripts_dir` - Must point to `scripts/imputation/{study_id}/`

3. **Variable Lists:**
   - May differ by study (not all studies have same variables)
   - Check source data (`{study_id}_transformed` table) for available columns
   - Geography variables depend on geocoding strategy
   - Sociodem variables depend on survey questions

#### Optional Changes

1. **Number of Imputations (M):**
   - Default: `5` (balances variance estimation vs. computation)
   - Increase to `10` or `20` for higher precision
   - Decrease to `3` for faster prototyping

2. **Random Seed:**
   - Keep as `42` for consistency across studies
   - Change if different reproducibility stream needed

3. **Feather File Settings:**
   - Usually keep defaults unless custom workflow needed

### 3. Auxiliary Variables (MICE Configuration)

**Purpose:** Variables used to **predict** missing values but are **not** themselves imputed.

**Location in Config:**

```yaml
sociodemographic:
  # Variables to impute
  variables:
    - female
    - raceG
    - educ_mom

  # Auxiliary variables (used as predictors)
  auxiliary_variables:
    - age_in_days
    - birth_weight
    - gestational_age
    - maternal_age
```

**Selection Criteria:**

✅ **Include** auxiliary variables that:
- Are complete (no or minimal missing data)
- Are correlated with imputed variables
- Add predictive power to the model
- Are measured before the imputed variables (temporal precedence)

❌ **Exclude** auxiliary variables that:
- Have high missingness (>20%)
- Are post-outcome variables (measured after imputed vars)
- Are derived from the imputed variables (circular dependency)

**Study-Specific Considerations:**

- **Different studies may have different auxiliary variables available**
- Check data dictionary for each study
- Validate correlation structure (auxiliaries should predict missing vars)

### 4. MICE Methods

**Location in Config:**

```yaml
sociodemographic:
  mice_methods:
    female: "logreg"      # Binary variable → logistic regression
    raceG: "polyreg"      # Categorical (5 levels) → polytomous regression
    income: "cart"        # Continuous/categorical → classification tree
    family_size: "cart"   # Count variable → classification tree
    fplcat: "polyreg"     # Ordered categorical → polytomous regression
```

**Method Selection Guide:**

| Variable Type | Recommended Method | Alternative |
|---------------|-------------------|-------------|
| Binary (0/1) | `logreg` | `cart` |
| Categorical (unordered) | `polyreg` | `cart`, `rf` |
| Categorical (ordered) | `polr` | `cart` |
| Continuous | `pmm`, `norm` | `cart`, `rf` |
| Count | `cart` | `pmm` |
| Semi-continuous | `cart` | `rf` |

**Study-Specific Customization:**

- **Variable availability may differ** (some studies lack certain variable types)
- **Convergence issues:** Switch to `cart` or `rf` if method-specific models fail
- **Sample size:** Small samples (<500) may require robust methods like `cart`
- **Interactions:** `cart` and `rf` handle interactions automatically

---

## Study-Specific Customization

### Required Script Modifications

After scaffolding, review and customize these files:

#### 1. Geography Imputation (`01_impute_geography.py`)

**Check:**
- Does the base table name match? (`{study_id}_transformed`)
- Are geography columns named correctly? (`puma`, `county`, `census_tract`)
- Does the geocoding use semicolon-delimited `afact` probabilities?

**Customization Example:**
```python
# Line ~35: Update base table name
base_table = f"{study_id}_transformed"  # Auto-updated by script

# Line ~50: Check geography column names
geography_cols = config['geography']['variables']  # From config
```

#### 2. Sociodemographic Imputation (`02_impute_sociodemographic.R`)

**Check:**
- Auxiliary variables exist in base data
- MICE methods are appropriate for variable distributions
- Convergence diagnostics are enabled

**Customization Example:**
```r
# Lines 80-100: Verify auxiliary variables
auxiliary_vars <- config$sociodemographic$auxiliary_variables

# Check they exist in data
missing_aux <- setdiff(auxiliary_vars, names(base_data))
if (length(missing_aux) > 0) {
  stop(paste("Missing auxiliary variables:", paste(missing_aux, collapse=", ")))
}

# Lines 120-140: Custom MICE methods
methods <- config$sociodemographic$mice_methods
# Validate methods are compatible with variable types
```

#### 3. Database Insertion (`02b_insert_sociodem_imputations.py`)

**Check:**
- Feather file directory path is correct
- Study_id matches throughout

**Usually auto-updated by `create_new_study.py` - verify lines 40-50**

#### 4. Pipeline Orchestration (`run_full_imputation_pipeline.R`)

**Check:**
- All script paths reference correct study directory
- Timing expectations are reasonable for study sample size

---

## Validation Checklist

Use this checklist when adding a new study:

### Pre-Setup Validation

- [ ] **Base data table exists:** `{study_id}_transformed` table in database
- [ ] **Required columns present:**
  - `pid` (participant ID)
  - `record_id` (record ID, for longitudinal data)
  - All geography variables (if imputing geography)
  - All sociodem variables (with missing values to impute)
  - All auxiliary variables (for MICE predictors)

- [ ] **Data quality checks:**
  - Missing data codes are properly coded as `NA` (not 99, -99, etc.)
  - Geography variables have afact probabilities (semicolon-delimited)
  - Auxiliary variables have <20% missingness

### Post-Setup Validation

- [ ] **Directory structure created:**
  - `scripts/imputation/{study_id}/`
  - `data/imputation/{study_id}/sociodem_feather/`

- [ ] **Configuration file exists:**
  - `config/imputation/{study_id}_config.yaml`
  - Study metadata is correct (study_id, study_name, table_prefix)
  - Variable lists match available data
  - Auxiliary variables are appropriate
  - MICE methods are correct for variable types

- [ ] **Pipeline scripts customized:**
  - All `ne25` references replaced with `{study_id}`
  - Base table name is correct
  - Geography column names match data
  - Auxiliary variables validated

### Database Schema Validation

- [ ] **Run schema setup:**
  ```bash
  python scripts/imputation/00_setup_imputation_schema.py --study-id {study_id}
  ```

- [ ] **Verify tables created:**
  - `{study_id}_imputed_puma`
  - `{study_id}_imputed_county`
  - `{study_id}_imputed_census_tract`
  - `{study_id}_imputed_{sociodem_var}` (for each sociodem variable)

- [ ] **Verify imputation_metadata entry:**
  ```sql
  SELECT * FROM imputation_metadata WHERE study_id = '{study_id}';
  ```

### Pipeline Execution Validation

- [ ] **Run geography imputation:**
  ```bash
  python scripts/imputation/{study_id}/01_impute_geography.py
  ```
  Expected: ~5,000 rows per imputation (M × ambiguous records)

- [ ] **Run sociodem imputation:**
  ```bash
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/{study_id}/02_impute_sociodemographic.R
  ```
  Expected: 35 feather files (7 variables × 5 imputations)

- [ ] **Insert sociodem imputations:**
  ```bash
  python scripts/imputation/{study_id}/02b_insert_sociodem_imputations.py
  ```
  Expected: ~68,000 rows (depends on sample size)

- [ ] **Run full pipeline:**
  ```bash
  "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/{study_id}/run_full_imputation_pipeline.R
  ```
  Expected: Success in 2-5 minutes

### Helper Functions Validation

- [ ] **Test get_completed_dataset():**
  ```python
  from python.imputation.helpers import get_completed_dataset
  df = get_completed_dataset(imputation_m=1, study_id='{study_id}')
  assert len(df) > 0
  assert 'female' in df.columns  # Or other imputed variable
  ```

- [ ] **Test get_imputed_variable_summary():**
  ```python
  from python.imputation.helpers import get_imputed_variable_summary
  summary = get_imputed_variable_summary('female', study_id='{study_id}')
  assert len(summary) > 0
  ```

- [ ] **Test validate_imputations():**
  ```python
  from python.imputation.helpers import validate_imputations
  results = validate_imputations(study_id='{study_id}')
  assert results['all_valid'] == True
  ```

---

## Troubleshooting

### Issue: Base table not found

**Error:** `Table '{study_id}_transformed' does not exist`

**Solution:**
- Ensure base data table is created before running imputation
- Check table name matches config (`{study_id}_transformed`)
- Verify database connection is working

### Issue: Missing auxiliary variables

**Error:** `Column 'auxiliary_var' not found in base data`

**Solution:**
- Check auxiliary variables exist in `{study_id}_transformed` table
- Remove non-existent variables from `auxiliary_variables` list in config
- Or add missing variables to base data table

### Issue: MICE convergence failure

**Error:** `mice() algorithm did not converge`

**Solution:**
- Increase `maxit` parameter (default 5 → try 10 or 20)
- Switch to more robust method (e.g., `cart` instead of `pmm`)
- Check for collinearity in auxiliary variables
- Reduce number of auxiliary variables

### Issue: Incorrect row counts

**Expected:** ~5,000 geography rows, ~68,000 sociodem rows
**Actual:** Much higher or lower

**Solution:**
- **Higher:** Check for duplicate `(pid, record_id, imputation_m)` keys
- **Lower:** Check for filtering logic in scripts (some records may be excluded)
- **Zero:** Verify base data has records with missing values to impute

### Issue: Helper functions return empty data

**Error:** `get_completed_dataset()` returns empty DataFrame

**Solution:**
- Verify study_id is correct (case-sensitive)
- Check imputation tables have data:
  ```sql
  SELECT COUNT(*) FROM {study_id}_imputed_female;
  ```
- Ensure imputation_m value is valid (1 to M)
- Check base table has matching `(pid, record_id)` keys

---

## See Also

- [Python Imputation README](../../python/imputation/README.md) - Helper functions documentation
- [R Imputation README](../../R/imputation/README.md) - R interface documentation
- [Migration Plan](STUDY_SPECIFIC_MIGRATION_PLAN.md) - Full migration documentation
- [Examples](../../examples/imputation/README.md) - Usage examples

---

**Questions or Issues?**

If you encounter problems not covered in this guide, please:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review logs for detailed error messages
3. Validate data using the [Validation Checklist](#validation-checklist)
4. Contact the Kidsights Data Platform team for assistance

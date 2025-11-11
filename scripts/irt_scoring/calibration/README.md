# IRT Item Calibration Functions

**Version:** 1.0
**Last Updated:** November 2025
**Status:** Phase 1 Complete - Core migration functional

---

## Purpose

This directory contains functions for generating Mplus MODEL syntax for **IRT item calibration** using graded response models.

### Calibration vs Scoring - Critical Distinction

| Aspect | Calibration (this directory) | Scoring (../scoring/) |
|--------|------------------------------|----------------------|
| **Purpose** | Estimate item parameters from multi-study data | Apply existing parameters to new data |
| **Input** | Raw item responses from multiple studies | Item responses + calibrated parameters |
| **Output** | Mplus syntax → item parameters (a, b) | IRT scores (theta) for participants |
| **Workflow** | Research/psychometric analysis | Production/operational scoring |
| **Frequency** | Occasional (when recalibrating scales) | Frequent (every data collection wave) |

**Example:**
- **Calibration:** "Combine NE20, NE22, NE25, NSCH data to estimate item parameters for Kidsights scale"
- **Scoring:** "Use NE25 calibrated parameters to score new IA26 participants"

---

## Files

### Core Functions

- **`write_syntax2.R`** - Generate MODEL, MODEL CONSTRAINT, MODEL PRIOR syntax
  - Implements graded response model with parameter constraints
  - Supports 5 constraint types (see below)
  - Auto-generates 1-PL constraints and Bayesian priors

- **`write_syntax2_hrtl.R`** - HRTL domain-specific calibration (PLACEHOLDER)
  - Full migration deferred to Phase 2
  - Requires mirt package for initial parameter estimation

- **`generate_model_syntax.R`** - Main orchestrator
  - Loads codebook and calibration dataset
  - Builds codebook_df with param_constraints
  - Calls write_syntax2() and writes output

### Helper Functions

- **`helpers/build_equate_table.R`**
  - `build_equate_table_from_codebook()` - Extract jid ↔ lex_equate mapping
  - `build_codebook_df()` - Create codebook_df structure for write_syntax2

---

## Constraint Types Supported

The `param_constraints` field in codebook.json supports 5 constraint types:

### 1. Complete Equality ("Constrain all to ITEM")
```
param_constraints: "Constrain all to AA102"
```
**Effect:** Share ALL parameters (discrimination + thresholds) with reference item

### 2. Slope-Only Equality ("Constrain slope to ITEM")
```
param_constraints: "Constrain slope to AA102"
```
**Effect:** Share discrimination parameter only, different thresholds

### 3. Threshold Ordering ("greater than" / "less than")
```
param_constraints: "Constrain tau$1 to be greater than AA102$1"
```
**Effect:** Inequality constraint (developmental ordering)

### 4. Simplex Constraints ("simplex between")
```
param_constraints: "Constrain tau$1 to be a simplex between AA102$1 and AA102$4"
```
**Effect:** Linear interpolation (threshold bounded by two anchors)

### 5. 1-PL/Rasch (Automatic for Unconstrained Items)
- All unconstrained items get equal discrimination constraints
- N(1,1) Bayesian priors on discrimination parameters

**Multiple Constraints:**
```
param_constraints: "Constrain slope to AA102; Constrain tau$1 to be greater than AA102$1"
```

---

## Usage

### Quick Start

```r
# Source orchestrator
source("scripts/irt_scoring/calibration/generate_model_syntax.R")

# Option 1: Generate Excel only (for review)
result <- generate_kidsights_model_syntax(
  scale_name = "kidsights",
  output_xlsx = "mplus/generated_syntax.xlsx"
)

# Output: mplus/generated_syntax.xlsx
# Sheets: MODEL, MODEL CONSTRAINT, MODEL PRIOR

# Option 2: Generate both Excel + complete .inp file
result <- generate_kidsights_model_syntax(
  scale_name = "kidsights",
  output_xlsx = "mplus/generated_syntax.xlsx",
  output_inp = "mplus/calibration.inp",
  dat_file_path = "calibdat.dat"
)

# Output:
#   - mplus/generated_syntax.xlsx (review file)
#   - mplus/calibration.inp (ready for Mplus execution)

# Option 3: Use existing template for TITLE/DATA/VARIABLE/ANALYSIS sections
result <- generate_kidsights_model_syntax(
  output_xlsx = "mplus/generated_syntax.xlsx",
  output_inp = "mplus/calibration.inp",
  template_inp = "mplus/my_template.inp",
  dat_file_path = "calibdat.dat"
)
```

### Programmatic Usage

```r
# Load functions
source("scripts/irt_scoring/calibration/write_syntax2.R")
source("scripts/irt_scoring/calibration/helpers/build_equate_table.R")

# Build inputs
codebook <- jsonlite::fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)
equate <- build_equate_table_from_codebook()
codebook_df <- build_codebook_df(codebook, equate, scale_name = "kidsights")

# Load calibration data
conn <- duckdb::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb", read_only = TRUE)
calibdat <- DBI::dbGetQuery(conn, "SELECT * FROM calibration_dataset_2020_2025_restructured")
DBI::dbDisconnect(conn)

# Generate syntax
syntax <- write_syntax2(
  codebook_df = codebook_df,
  calibdat = calibdat,
  output_xlsx = "mplus/generated_syntax.xlsx"
)
```

---

## Dependencies

### R Packages (Required)
- `dplyr` - Data manipulation
- `stringr` - String operations
- `purrr` - Functional programming
- `tibble` - Data frames
- `tidyr` - Data tidying
- `jsonlite` - JSON parsing
- `duckdb` - Database connection
- `writexl` - Excel output

### External Software (Optional)
- **Mplus** - For running generated .inp files and estimating parameters

---

## Workflow

1. **Prepare Calibration Dataset**
   ```r
   source("scripts/irt_scoring/prepare_calibration_dataset.R")
   prepare_calibration_dataset()
   ```

2. **Specify Constraints in Codebook**
   - Edit `codebook/data/codebook.json`
   - Add `param_constraints` field to items needing constraints
   - See constraint types above

3. **Generate Mplus Syntax**
   ```r
   source("scripts/irt_scoring/calibration/generate_model_syntax.R")

   # Generate both Excel + complete .inp file
   generate_kidsights_model_syntax(
     output_xlsx = "mplus/generated_syntax.xlsx",
     output_inp = "mplus/calibration.inp"
   )
   ```

4. **Review Generated Files**
   - Open `mplus/generated_syntax.xlsx` (Excel review file)
     - Check MODEL section (factor loadings, thresholds)
     - Check CONSTRAINT section (parameter constraints, 1-PL)
     - Check PRIOR section (N(1,1) priors)
   - Open `mplus/calibration.inp` (complete Mplus input file)
     - Verify TITLE, DATA, VARIABLE, ANALYSIS sections
     - Confirm MODEL, CONSTRAINT, PRIOR sections are present

5. **Run Mplus Calibration**
   - Open `mplus/calibration.inp` in Mplus
   - Run → Run Mplus
   - Review `.out` file for convergence and fit
   - Extract parameter estimates for IRT scoring

---

## Testing

### Basic Migration Test
```r
source("scripts/temp/test_write_syntax2_migration.R")
# Runs validation checks on write_syntax2 migration
# Uses minimal test data (3 items, 10 records)
```

### Integration Test (Planned - Phase 4)
- Test with full calibration dataset (47,084 records, 416 items)
- Compare output to Update-KidsightsPublic
- Validate Mplus compatibility

---

## Troubleshooting

### Issue: "Missing param_constraints field"
**Cause:** Codebook not updated with renamed field
**Solution:** Ensure codebook uses `param_constraints` not `constraints`

### Issue: "Variable name mismatch"
**Cause:** Item names in calibdat don't match lex_equate in codebook
**Solution:** Check calibration dataset column names, regenerate if needed

### Issue: "No items with equate lexicon"
**Cause:** Codebook items missing equate lexicon
**Solution:** Update codebook with equate names for calibration items

---

## Future Enhancements (Phase 2+)

- [ ] Complete write_syntax2_hrtl migration (HRTL domains)
- [ ] Automatic .inp file generation (combine MODEL + template sections)
- [ ] Interactive constraint specification workflow
- [ ] Constraint validation (detect circular dependencies, conflicts)
- [ ] Multi-factor model support (bifactor, hierarchical)

---

## References

- **Source Repository:** Update-KidsightsPublic (`utils/write_model_constraint_syntax.R`)
- **Migration Plan:** `todo/irt_calibration_migration_phase*.md`
- **Mplus Documentation:** [statmodel.com](https://www.statmodel.com/)

---

**Migrated:** November 2025
**Maintained By:** Kidsights Data Platform Team

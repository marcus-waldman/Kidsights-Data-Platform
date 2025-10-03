# Codebook Documentation

This directory contains documentation for the JSON-based codebook system.

## Contents

- **`IRT_PARAMETERS.md`** - Documentation of IRT (Item Response Theory) parameters across studies
- **`PSYCHOSOCIAL_ITEMS.md`** - Special documentation for psychosocial (PS) items with NE22 bifactor parameters
- **`CREDI_ITEMS.md`** - CREDI Short Form and Long Form IRT parameter documentation
- **`GSED_ITEMS.md`** - GSED Rasch model with multiple calibrations documentation
- **`ne25_validation_report.md`** - Validation report for NE25 study codebook entries

## Codebook System

The primary codebook is stored at `codebook/data/codebook.json` and contains:
- **309 items** across 8 studies (NE25, NE22, NE20, CAHMI22, CAHMI21, ECDI, CREDI, GSED)
- **Version**: 3.1 (updated October 2025)
- Item stems, response options, domains, age ranges
- IRT parameters: NE22, CREDI (SF/LF), GSED (multi-calibration), NE25
- Study-specific lexicon mappings

## Interactive Dashboard

View the codebook interactively:
- **Source**: `codebook/dashboard/index.qmd`
- **Output**: `docs/codebook_dashboard/index.html`

## Key Functions

### Basic Querying

```r
# Load codebook
source("R/codebook/load_codebook.R")
source("R/codebook/query_codebook.R")
codebook <- load_codebook("codebook/data/codebook.json")

# Filter items
motor_items <- filter_items_by_domain(codebook, "motor")
ne25_items <- filter_items_by_study(codebook, "NE25")
```

### Data Extraction Utilities

```r
# Load extraction utilities
source("R/codebook/extract_codebook.R")

# Extract data
crosswalk <- codebook_extract_lexicon_crosswalk(codebook)
irt_params <- codebook_extract_irt_parameters(codebook, "NE22")
responses <- codebook_extract_response_sets(codebook, study = "NE25")
content <- codebook_extract_item_content(codebook, domains = "motor")
summary <- codebook_extract_study_summary(codebook, "NE25")
```

### Utility Functions Reference

**File:** `R/codebook/extract_codebook.R` | **Documentation:** `docs/codebook_utilities.md`

| Function | Purpose |
|----------|---------|
| `codebook_extract_lexicon_crosswalk()` | Item ID mappings across studies |
| `codebook_extract_irt_parameters()` | IRT discrimination/threshold parameters |
| `codebook_extract_response_sets()` | Response options and value labels |
| `codebook_extract_item_content()` | Item text, domains, age ranges |
| `codebook_extract_study_summary()` | Study-level summary statistics |

**Example workflow:**
```r
# Run complete analysis example
source("scripts/examples/codebook_utilities_examples.R")
```

## IRT Parameters

The codebook includes IRT calibration parameters for multiple studies:

### NE22 Parameters (203 items)
- **Unidimensional model:** factor = "kidsights"
- **PS items:** Bifactor model with general + specific factors (eat/sle/soc/int/ext)
- **Script:** `scripts/codebook/update_ne22_irt_parameters.R`

### CREDI Parameters (60 items)
- **Short Form (SF):** 37 items, unidimensional, factor = "credi_overall"
- **Long Form (LF):** 60 items, multidimensional, factors = mot/cog/lang/sem
- **Nested structure:** `CREDI → short_form/long_form → parameters`
- **Script:** `scripts/codebook/update_credi_irt_parameters.R`
- **Source:** `data/credi-mest_df.csv`

### GSED Parameters (132 items)
- **Rasch model:** loading = 1.0 (all items)
- **Multiple calibrations per item** (avg 3.03): gsed2406, gsed2212, gsed1912, gcdg, dutch, 293_0
- **Nested structure:** `GSED → calibration_key → parameters`
- **Script:** `scripts/codebook/update_gsed_irt_parameters.R`
- **Source:** `dscore::builtin_itembank`

### Threshold Transformations
- **NE22:** threshold = -tau (negated and sorted)
- **CREDI SF:** threshold = -delta / alpha
- **CREDI LF:** threshold = -tau
- **GSED:** threshold = -tau

## Dashboard Rendering

Render the interactive codebook dashboard:

```bash
# Render dashboard
quarto render codebook/dashboard/index.qmd

# Output location
# codebook/dashboard/index.html
```

The dashboard provides interactive browsing of all 309 items across 8 studies with filtering by domain, study, and age range.

## Related Files

### R Functions
- `/R/codebook/` - R functions for codebook operations

### Management Scripts
- `/scripts/codebook/update_ne22_irt_parameters.R` - NE22 unidimensional parameters
- `/scripts/codebook/update_ps_bifactor_irt.R` - PS bifactor parameters
- `/scripts/codebook/update_credi_irt_parameters.R` - CREDI SF/LF parameters
- `/scripts/codebook/update_gsed_irt_parameters.R` - GSED multi-calibration parameters

### Data Source
- `/codebook/data/codebook.json` - Primary codebook data source (~625 KB, version 3.0)
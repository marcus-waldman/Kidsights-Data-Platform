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

## Utility Functions

See `R/codebook/` for querying and extracting codebook data:
- `load_codebook()` - Load JSON into R
- `filter_items_by_domain()` - Filter by developmental domain
- `filter_items_by_study()` - Filter by study
- `codebook_extract_*()` - Specialized extraction utilities

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
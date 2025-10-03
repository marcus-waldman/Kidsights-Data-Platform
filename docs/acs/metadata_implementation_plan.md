# ACS Metadata Implementation Plan

## Overview

Leverage IPUMS DDI (Data Documentation Initiative) metadata to create a comprehensive metadata system that supports transformations, harmonization, and documentation for ACS data.

---

## Phase 1: Metadata Extraction & Storage

**Goal:** Parse DDI files and store metadata in DuckDB for queryable access

### Tasks

- [✅] **Create DDI metadata parser** (`python/acs/metadata_parser.py`)
  - Parse DDI XML files
  - Extract variable definitions (name, label, type, description)
  - Extract value labels (code-to-label mappings for categorical variables)
  - Handle IPUMS-specific DDI schema

- [✅] **Create metadata database schema**
  - `acs_variables` table (variable definitions)
  - `acs_value_labels` table (categorical value mappings)
  - `acs_metadata_registry` table (track DDI files processed)

- [✅] **Implement metadata loader script** (`pipelines/python/acs/load_acs_metadata.py`)
  - Read DDI files from cache directories
  - Populate metadata tables
  - Handle updates/versioning

- [✅] **Update ACS pipeline to auto-load metadata**
  - Integrate metadata extraction after DDI download (Step 4.6)
  - Store metadata alongside data insertion

### Deliverables

- DDI parser module
- Metadata tables in DuckDB
- Populated metadata for Nebraska & Minnesota extracts
- Basic query examples

---

## Phase 2: Transformation Utilities

**Goal:** Create tools to use metadata for data transformations and harmonization

### Tasks

- [✅] **Value label decoder** (`python/acs/metadata_utils.py`)
  - Function to decode numeric codes to labels
  - Support for single values and DataFrames
  - Example: `decode_value('STATEFIP', 27)` → "Minnesota"

- [✅] **Variable type classifier**
  - Identify categorical vs continuous variables
  - Detect identifier variables (SERIAL, PERNUM)
  - Functions: `is_categorical()`, `is_continuous()`, `is_identifier()`

- [✅] **Category harmonization tools** (`python/acs/harmonization.py`)
  - Map IPUMS categories to NE25 categories
  - Race/ethnicity crosswalk (7 categories, Hispanic overrides race)
  - Education level harmonization (8-cat and 4-cat)
  - Income category alignment (FPL percentages)

- [✅] **R metadata access functions** (`R/utils/acs/acs_metadata.R`)
  - Query metadata from R
  - Decode values in R workflows (acs_decode_value, acs_decode_column)
  - Integration with existing codebook system

### Deliverables

- Metadata utility functions (Python & R)
- Harmonization crosswalk examples
- Documentation for using metadata in transformations

---

## Phase 3: Documentation & Analysis Tools

**Goal:** Auto-generate documentation and enable metadata-driven analysis

### Tasks

- [✅] **Data dictionary generator** (`scripts/acs/generate_data_dictionary.py`)
  - Parse DDI → Generate HTML data dictionary
  - Include variable descriptions, value labels, data types
  - Support Markdown and HTML output formats

- [✅] **Transformation documentation** (`docs/acs/transformation_mappings.md`)
  - Document IPUMS → NE25 variable mappings
  - Explain category harmonization decisions (race, education, FPL)
  - Detailed mapping tables and examples

- [✅] **Metadata query examples** (`docs/acs/metadata_query_cookbook.md`)
  - Python and R query examples for common tasks
  - Integration with analysis workflows
  - Basic queries, decoding, harmonization, quality checks

- [✅] **Update CLAUDE.md with metadata usage**
  - Document metadata system architecture
  - Add usage examples with 3-phase breakdown
  - Update pipeline documentation

### Deliverables

- Auto-generated ACS data dictionary (HTML/Markdown)
- Transformation documentation
- Metadata query cookbook
- Updated project documentation

---

## Benefits

### For Transformations
- **Precise harmonization:** Know exactly what IPUMS codes mean
- **Automated validation:** Check categorical values against DDI
- **Reduced errors:** No guesswork in code-to-label mappings

### For Analysis
- **Self-documenting queries:** Join data with labels for readable output
- **Variable discovery:** Query metadata to find relevant variables
- **Quality checks:** Validate data against expected ranges/categories

### For Raking
- **Category alignment:** Ensure ACS and NE25 categories match exactly
- **Weight calculation:** Accurate population totals by category
- **Documentation:** Transparent raking variable definitions

---

## Implementation Notes

- **DDI Files Available:**
  - Nebraska: `data/acs/cache/extracts/usa_44/usa_00044.xml` (160KB)
  - Minnesota: `data/acs/cache/extracts/usa_46/usa_00046.xml` (160KB)

- **Database:** DuckDB (`data/duckdb/kidsights_local.duckdb`)

- **Integration Points:**
  - ACS extraction pipeline (automatic metadata load)
  - Transformation scripts (metadata-driven recoding)
  - Analysis workflows (value label decoding)

---

## Next Steps

1. **Review and approve plan**
2. **Begin Phase 1 implementation**
3. **Test metadata extraction with existing DDI files**
4. **Iterate based on transformation needs**

---

*Created: 2025-10-03*
*Status: ✅ Completed - October 2025*

---

## Implementation Summary

**Completion Date:** 2025-10-03

**Database Statistics:**
- **Variables:** 42 total (28 categorical, 9 continuous, 5 identifier)
- **Value Labels:** 1,144 mappings
- **DDI Files Processed:** 2 (Nebraska usa_00044.xml, Minnesota usa_00046.xml)
- **Database Tables:** 3 (acs_variables, acs_value_labels, acs_metadata_registry)
- **ACS Records:** 24,449 (6,657 Nebraska + 17,792 Minnesota)

**Key Components Delivered:**
- DDI metadata parser (`python/acs/metadata_parser.py`)
- Database schema with 3 tables (`python/acs/metadata_schema.py`)
- Metadata loader CLI (`pipelines/python/acs/load_acs_metadata.py`)
- Python utilities for decoding and harmonization (`python/acs/metadata_utils.py`, `python/acs/harmonization.py`)
- R metadata functions (`R/utils/acs/acs_metadata.R`)
- Auto-generated data dictionaries (HTML + Markdown)
- Transformation mappings documentation
- Metadata query cookbook

**Next Steps:** Metadata system is production-ready for statistical raking and analysis workflows.

# Kidsights Codebook System

## Overview

This directory contains the JSON-based codebook system for the Kidsights Data Platform. The codebook provides comprehensive metadata about 309 items from multiple studies, including their properties, scoring rules, psychometric parameters, and study-specific response options.

**Current Studies Supported:**
- **NE25, NE22, NE20**: Nebraska longitudinal studies
- **CAHMI22, CAHMI21**: Child and Adolescent Health Measurement Initiative
- **ECDI, CREDI, GSED**: International development assessments
- **GSED_PF**: GSED Psychosocial Frequency items (46 PS items)

**Key Features:**
- 309 total items with comprehensive metadata
- Hierarchical domain classification system
- Study-specific response set definitions with proper missing value coding
- Interactive Quarto dashboard for exploration
- R functions for querying and analysis

## Directory Structure

```
codebook/
├── data/                          # Codebook data files
│   ├── codebook.json             # Primary JSON codebook
│   ├── codebook.csv              # Legacy CSV (for reference)
│   └── versions/                 # Historical versions
├── dashboard/                    # Quarto dashboard files
│   ├── _quarto.yml              # Quarto configuration
│   ├── *.qmd                    # Dashboard pages
│   └── assets/                  # Dashboard resources
└── README.md                    # This file
```

## Quick Start

### Load the codebook in R:
```r
source("R/codebook/load_codebook.R")
codebook <- load_codebook("codebook/data/codebook.json")
```

### Query items:
```r
source("R/codebook/query_codebook.R")

# Filter by domain
motor_items <- filter_items_by_domain(codebook, "motor")
psychosocial_items <- filter_items_by_domain(codebook, "psychosocial_problems_general")

# Filter by study
ne25_items <- filter_items_by_study(codebook, "NE25")
gsed_pf_items <- filter_items_by_study(codebook, "GSED_PF")  # 46 PS items

# Get specific items
item_aa4 <- get_item(codebook, "AA4")
item_ps001 <- get_item(codebook, "PS001")

# Work with IRT parameters
items_with_irt <- filter_items_with_irt(codebook, "NE25")  # Items with NE25 IRT parameters
item_irt <- get_irt_parameters(item_aa4, "NE25")  # Get IRT parameters for specific study
```

### View dashboard:
Open `docs/codebook_dashboard/index.html` in a web browser

## Maintenance

### Regenerate from CSV:
```r
source("scripts/codebook/initial_conversion.R")
convert_csv_to_json()  # Converts CSV + PS items to JSON
```

### Regenerate dashboard:
```bash
quarto render codebook/dashboard/index.qmd
```

## Data Quality Validation

### NE25 Comprehensive Audit Results (September 2025)

**Coverage:** 276 codebook items validated against 434 REDCap fields
**Location:** `scripts/audit/ne25_codebook/`

**Key Findings:**
- **265 items (96%)** successfully matched between sources
- **80% value/label alignment** for matched items
- **11 items require NE25 variable mapping:** DD201, DD203, EG2_2, EG3_2, EG4a_2, EG4b_1, EG9b, EG11_2, EG13b, EG42b, EG50a
- **52 items have minor discrepancies** (mainly missing "Don't Know" options)

**Run Validation:**
```bash
# Complete audit pipeline
Rscript scripts/audit/ne25_codebook/extract_codebook_responses.R
Rscript scripts/audit/ne25_codebook/compare_sources.R
Rscript scripts/audit/ne25_codebook/generate_audit_report.R
```

**Reports:** `scripts/audit/ne25_codebook/reports/NE25_COMPREHENSIVE_AUDIT_SUMMARY.txt`

## Data Structure

The JSON codebook contains:

### Items (309 total)
Core item definitions with:
- **Identifiers**: Primary equate ID plus study-specific lexicons
- **Domains**: Hierarchical classification (kidsights/cahmi with study groups)
- **Content**: Item stems and response option references
- **Scoring**: Reverse coding flags and equate groups
- **Psychometric**: Study-specific IRT parameters and calibration metadata

### Response Sets (Study-Specific)
Study-specific response option definitions ensure proper missing value coding:

**Psychosocial Frequency Scales:**
- `ps_frequency_ne25`: PS items for NE25 (Don't Know = **9**)
- `ps_frequency_ne22`: PS items for NE22 (Don't Know = **-9**)
- `ps_frequency_ne20`: PS items for NE20 (Don't Know = **-9**)
- `ps_frequency_gsed_pf`: PS items for GSED_PF (Don't Know = **-9**)

**Binary Response Scales:**
- `standard_binary_ne25`: Yes/No for NE25 (Don't Know = **9**)
- `standard_binary`: Yes/No for other studies (Don't Know = **-9**)

**Common Likert Scales (NE25-specific):**
- `likert_5_frequency_ne25`: 5-point Always→Never (Don't Know = **9**)
- `likert_4_skill_ne25`: 4-point Very well→Not at all (Don't Know = **9**)

**⚠️ CRITICAL**: NE25 uses positive **9** for missing values, other studies use **-9**

### Domains
- `socemo`: Social-emotional development
- `motor`: Motor skills and physical development
- `coglan`: Cognitive and language development
- `psychosocial_problems_general`: GSED_PF psychosocial items
- `health`: HRTL health-related items from NSCH

### Studies Integration
- **GSED_PF**: 46 PS items (PS001-PS049) with psychosocial_problems_general domain
- **Nebraska studies**: NE25, NE22, NE20 with various domains
- **CAHMI studies**: CAHMI22, CAHMI21 with parallel domain structure

## GSED_PF PS Items

The 46 PS (Psychosocial) items were integrated from `tmp/ne25_ps_items.csv`:

**Characteristics:**
- **Item IDs**: PS001 through PS049 (some gaps in sequence)
- **Domain**: psychosocial_problems_general
- **Study**: GSED_PF
- **Response Scale**: ps_frequency (0=Never or Almost Never, 1=Sometimes, 2=Often, -9=Don't Know)
- **Content**: Early childhood behavioral and emotional concerns

**Example items:**
- PS001: "Do you have any concerns about how your child behaves?"
- PS007: "Does your child have a hard time calming down even when you soothe him/her?"
- PS034: "Does your child have trouble paying attention?"

## IRT Parameters

The codebook now supports study-specific Item Response Theory (IRT) parameters for psychometric analysis:

**Structure:**
```json
"irt_parameters": {
  "NE25": {
    "factors": [],      // Factor names for multidimensional models
    "loadings": [],     // Factor loadings (a-parameters)
    "thresholds": []    // Difficulty/threshold parameters
  },
  "GSED_PF": {
    "factors": [],
    "loadings": [],
    "thresholds": []
  }
}
```

**R Functions:**
```r
# Get IRT parameters for specific study
item <- get_item(codebook, "AA4")
ne25_irt <- get_irt_parameters(item, "NE25")

# Filter items with IRT parameters
items_with_irt <- filter_items_with_irt(codebook, "NE25")
any_irt_items <- filter_items_with_irt(codebook)  # Any study

# Get IRT coverage matrix
coverage <- get_irt_coverage(codebook)  # Which items have parameters for which studies
```

**Supported Studies:**
All studies can have IRT parameters, with template structure created automatically during conversion.

## Version History

- **v1.0**: Initial CSV codebook (259 items)
- **v2.0**: JSON-based system with enhanced structure and dashboard
- **v2.1**: Added GSED_PF study with 46 PS items, psychosocial_problems_general domain
- **v2.2**: Implemented study-specific IRT parameters with constraints field template
- **v2.3**: Added NE22 IRT parameter estimates for 203 items from empirical calibration
- **v2.7**: Fixed PS items response options for proper recoding compatibility
- **v2.8**: ⚠️ **MAJOR**: Study-specific response sets with NE25 missing value fix (9 vs -9)

## Troubleshooting

### Common Issues

**Q: Dashboard won't render**
A: Ensure Quarto is installed and run from the codebook/dashboard/ directory

**Q: Can't find PS items**
A: Use `filter_items_by_study(codebook, "GSED_PF")` to get all 46 PS items

**Q: JSON loading errors**
A: Check that simplifyVector=FALSE when using jsonlite::fromJSON()

**Q: Missing response options**
A: Response options are stored as references (e.g., "ps_frequency") - check codebook$response_sets

For detailed function documentation, see `R/codebook/README.md`.

## Response Sets Migration (v2.8.0)

### Critical Change: Study-Specific Missing Values

⚠️ **BREAKING CHANGE**: Version 2.8.0 introduces study-specific response sets to fix missing value coding inconsistencies.

**Key Changes:**
- **NE25**: Missing values coded as **9** (positive)
- **All other studies**: Missing values coded as **-9** (negative)
- **Eliminated inline response options**: All items now reference named response sets
- **Study-specific sets**: Each study has appropriate response sets for its coding scheme

### Migration Impact

**Affected Items:**
- **47 PS items**: Now use study-specific `ps_frequency_*` response sets
- **168 binary items**: NE25 items now use `standard_binary_ne25` (9 vs -9)
- **62 inline response items**: Converted to response set references

**Recoding Pipeline**: Ensure your data processing accounts for the NE25 missing value change from -9 to 9.

### Response Set Reference

```r
# Example: PS041 item response options
{
  "response_options": {
    "ne25": "ps_frequency_ne25",    # 9 = Don't Know
    "ne22": "ps_frequency_ne22",    # -9 = Don't Know
    "ne20": "ps_frequency_ne20"     # -9 = Don't Know
  }
}
```

### Update Script

The migration was performed by `scripts/codebook/fix_codebook_response_sets.R`:

```bash
# Run the response sets fix
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=scripts/codebook/fix_codebook_response_sets.R
```

**Backup**: Previous version saved as `codebook_pre_response_sets_fix_TIMESTAMP.json`
# Kidsights Codebook System

## Overview

This directory contains the JSON-based codebook system for the Kidsights Data Platform. The codebook provides comprehensive metadata about 305 items from multiple studies, including their properties, scoring rules, psychometric parameters, and response options.

**Current Studies Supported:**
- **NE25, NE22, NE20**: Nebraska longitudinal studies
- **CAHMI22, CAHMI21**: Child and Adolescent Health Measurement Initiative
- **ECDI, CREDI, GSED**: International development assessments
- **GSED_PF**: GSED Psychosocial Frequency items (46 PS items)

**Key Features:**
- 305 total items with comprehensive metadata
- Hierarchical domain classification system
- Reusable response set definitions
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

## Data Structure

The JSON codebook contains:

### Items (305 total)
Core item definitions with:
- **Identifiers**: Primary equate ID plus study-specific lexicons
- **Domains**: Hierarchical classification (kidsights/cahmi with study groups)
- **Content**: Item stems and response option references
- **Scoring**: Reverse coding flags and equate groups
- **Psychometric**: Study-specific IRT parameters and calibration metadata

### Response Sets
Reusable response option definitions:
- `standard_binary`: Yes/No/Don't Know
- `likert_5`: 5-point Never to Always scale
- `ps_frequency`: PS item frequency scale (Never or Almost Never/Sometimes/Often/Don't Know)

### Domains
- `socemo`: Social-emotional development
- `motor`: Motor skills and physical development
- `coglan`: Cognitive and language development
- `psychosocial_problems_general`: GSED_PF psychosocial items

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
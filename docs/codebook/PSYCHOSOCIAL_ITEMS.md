# Psychosocial Items in the Kidsights Codebook

This document describes the psychosocial (PS) items integrated into the Kidsights codebook system, including their bifactor model structure, domain assignments, and special handling.

## Overview

The codebook includes **46 psychosocial items** (PS001-PS049, excluding PS031 and PS033 with special handling) designed to assess various aspects of psychosocial functioning in early childhood development.

### Key Characteristics
- **Item Range**: PS001-PS049 (46 items total)
- **Response Scale**: ps_frequency (Never/Sometimes/Often/Don't Know)
- **Model**: Bifactor structure with general + specific factors
- **Studies**: NE25, NE22, NE20 (PS033 exception: NE22, NE20 only)
- **Domains**: Multiple psychosocial problem domains based on factor loadings

## Bifactor Model Structure

### Factor Organization
The PS items follow a bifactor model with 6 factors:

| Factor | Description | Example Items |
|--------|-------------|---------------|
| `gen` | General psychosocial problems | All PS items |
| `eat` | Feeding/eating problems | PS002, PS017, PS025, PS030 |
| `sle` | Sleep problems | PS005, PS010, PS011, PS013, PS043 |
| `soc` | Social-emotional problems | PS009, PS015, PS032, PS035, PS038, PS041, PS042 |
| `int` | Internalizing problems | PS004, PS014, PS016, PS018, PS029, PS040, PS044, PS048 |
| `ext` | Externalizing problems | PS003, PS006, PS007, PS008, PS019, PS022-PS028, PS034, PS036-PS037, PS039, PS045, PS049 |

### Model Specification
Items load on both:
1. **General factor** (`gen`) - All PS items have loadings
2. **Specific factor** - One domain-specific factor per item

Example IRT parameters for PS018 (internalizing):
```json
"irt_parameters": {
  "NE22": {
    "factors": ["gen", "int"],
    "loadings": [0.205, 0.287],
    "thresholds": [-1.418, 0.167],
    "constraints": []
  }
}
```

## Domain Assignments

### Multi-Domain Structure
PS items are assigned to multiple `psychosocial_problems_*` domains based on their factor loadings:

```json
"domains": {
  "kidsights": {
    "value": [
      "psychosocial_problems_general",
      "psychosocial_problems_internalizing"
    ],
    "studies": ["NE25", "NE22", "NE20"]
  }
}
```

### Domain Mappings
The bifactor structure maps to standardized domain names:

| Factor Code | Domain Name |
|-------------|-------------|
| `gen` | `psychosocial_problems_general` |
| `eat` | `psychosocial_problems_feeding` |
| `sle` | `psychosocial_problems_sleeping` |
| `soc` | `psychosocial_problems_socialemotional` |
| `int` | `psychosocial_problems_internalizing` |
| `ext` | `psychosocial_problems_externalizing` |

### Assignment Logic
Items receive domain assignments based on factor loadings:

```r
# Domain assignment from CSV data
domain_mappings <- list(
  gen = "psychosocial_problems_general",
  eat = "psychosocial_problems_feeding",
  sle = "psychosocial_problems_sleeping",
  soc = "psychosocial_problems_socialemotional",
  int = "psychosocial_problems_internalizing",
  ext = "psychosocial_problems_externalizing"
)

# Items with factor loading = 1 get assigned to that domain
# All items automatically get "general" domain
```

## Special Cases

### PS033 - Reverse Scoring and Limited Studies
PS033 has unique characteristics:

```json
{
  "id": 2032,
  "studies": ["NE22", "NE20"],  // Missing NE25
  "scoring": {
    "reverse": true,            // Only PS item with reverse scoring
    "equate_group": "NE22"
  },
  "domains": {
    "kidsights": {
      "value": "psychosocial_problems_general",
      "studies": ["NE22", "NE20"]
    }
  }
}
```

**Special handling:**
- Only appears in NE22 and NE20 studies (not NE25)
- Requires reverse scoring: `reverse: true`
- Single domain assignment (general only)

### PS020, PS046, PS047 - General Factor Only
These items load only on the general factor without specific factors:

```json
"irt_parameters": {
  "NE22": {
    "factors": ["gen"],
    "loadings": [0.888],
    "thresholds": [-1.250, 1.027],
    "constraints": []
  }
}
```

## Response Scale

### ps_frequency Scale
All PS items use the standardized ps_frequency response scale:

```json
"response_sets": {
  "ps_frequency": [
    {"value": 0, "label": "Never or Almost Never"},
    {"value": 1, "label": "Sometimes"},
    {"value": 2, "label": "Often"},
    {"value": -9, "label": "Don't Know", "missing": true}
  ]
}
```

### Item Reference
Each PS item references this scale:

```json
"content": {
  "response_options": {
    "ne25": "ps_frequency"
  }
}
```

## Data Sources and Processing

### Source Files
- **Bifactor Model**: `tmp/bifactor5e.txt` (Mplus output)
- **Domain Assignments**: `tmp/psychosocial-items - Sheet1.csv`
- **Original Items**: Integrated from GSED_PF study

### Processing Pipeline

1. **Parse Mplus Output** (`update_ps_bifactor_irt.R`):
   ```
   bifactor5e.txt → Factor loadings + Thresholds → JSON parameters
   ```

2. **Assign Domains** (`assign_ps_domains.R`):
   ```
   CSV domain flags → Multi-domain arrays → JSON domains
   ```

3. **Correct Studies** (`update_ps_studies.R`):
   ```
   GSED_PF → NE25/NE22/NE20 (PS033: NE22/NE20 only)
   ```

### Migration History
1. **v2.4**: Added PS items from GSED_PF with single domain
2. **v2.5**: Corrected study assignments and PS033 reverse scoring
3. **v2.6**: Added bifactor IRT parameters and multi-domain assignments

## Usage Examples

### Query PS Items
```r
# Load codebook
codebook <- load_codebook("codebook/data/codebook.json")

# Get all PS items from NE25 study
ps_items <- filter_items_by_study(codebook, "NE25")
ps_only <- ps_items[grepl("^PS", names(ps_items))]

cat("Found", length(ps_only), "PS items in NE25")
```

### Access Bifactor Parameters
```r
# Get PS018 with internalizing factors
ps018 <- get_item(codebook, "PS018")

# Extract bifactor information
factors <- ps018$psychometric$irt_parameters$NE22$factors
loadings <- ps018$psychometric$irt_parameters$NE22$loadings

# Display factor structure
for (i in seq_along(factors)) {
  cat(factors[i], "loading:", loadings[i], "\n")
}
# Output:
# gen loading: 0.205
# int loading: 0.287
```

### Find Items by Domain
```r
# Get all internalizing items
internalizing_items <- filter_items_by_domain(codebook, "psychosocial_problems_internalizing")

# Get items with multiple domains
multi_domain_items <- list()
for (id in names(codebook$items)) {
  item <- codebook$items[[id]]
  if (is.list(item$domains$kidsights$value) &&
      length(item$domains$kidsights$value) > 1) {
    multi_domain_items[[id]] <- item
  }
}
```

### Check Reverse Scoring
```r
# Find all reverse-scored items
reverse_items <- list()
for (id in names(codebook$items)) {
  item <- codebook$items[[id]]
  if (!is.null(item$scoring$reverse) && item$scoring$reverse) {
    reverse_items[[id]] <- item
  }
}

cat("Reverse-scored items:", names(reverse_items))  # Should show PS033
```

## Validation Checks

### Factor Loading Validation
```r
validate_ps_bifactor <- function(item) {
  params <- item$psychometric$irt_parameters$NE22

  # Check factor structure
  factors <- params$factors
  if (!"gen" %in% factors) {
    stop("PS items must have general factor")
  }

  # Validate specific factors
  valid_specific <- c("eat", "sle", "soc", "int", "ext")
  specific_factors <- setdiff(factors, "gen")
  if (length(specific_factors) > 1) {
    stop("PS items should have only one specific factor")
  }

  if (length(specific_factors) == 1 && !specific_factors %in% valid_specific) {
    stop("Invalid specific factor:", specific_factors)
  }

  return(TRUE)
}
```

### Domain Assignment Validation
```r
validate_ps_domains <- function(item) {
  domains <- item$domains$kidsights$value

  # Check for general domain
  if (!"psychosocial_problems_general" %in% domains) {
    stop("PS items must include general psychosocial domain")
  }

  # Validate domain names
  valid_domains <- c(
    "psychosocial_problems_general",
    "psychosocial_problems_feeding",
    "psychosocial_problems_sleeping",
    "psychosocial_problems_socialemotional",
    "psychosocial_problems_internalizing",
    "psychosocial_problems_externalizing"
  )

  invalid_domains <- setdiff(domains, valid_domains)
  if (length(invalid_domains) > 0) {
    stop("Invalid psychosocial domains:", paste(invalid_domains, collapse = ", "))
  }

  return(TRUE)
}
```

## Management Scripts

### Core Scripts
- `scripts/codebook/update_ps_bifactor_irt.R` - Parse Mplus bifactor model
- `scripts/codebook/assign_ps_domains.R` - Multi-domain assignments
- `scripts/codebook/update_ps_studies.R` - Correct study participation

### Usage
```bash
# Update bifactor IRT parameters
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" -e "source('scripts/codebook/update_ps_bifactor_irt.R'); update_ps_bifactor_irt()"

# Assign domains from CSV
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" -e "source('scripts/codebook/assign_ps_domains.R'); assign_ps_domains()"

# Correct study assignments
"C:/Program Files/R/R-4.4.3/bin/Rscript.exe" -e "source('scripts/codebook/update_ps_studies.R'); update_ps_studies()"
```

## Summary Statistics

### Current Status (v2.6)
- **Total PS Items**: 46
- **Items with Bifactor Parameters**: 44 (PS031 missing, PS033 in NE22 only)
- **Multi-domain Items**: 43 (items with specific factors)
- **General-only Items**: 3 (PS020, PS046, PS047)
- **Reverse-scored Items**: 1 (PS033)
- **Response Scale**: ps_frequency (4-point ordinal)

### Factor Distribution
- **Feeding (eat)**: 4 items
- **Sleep (sle)**: 5 items
- **Social-emotional (soc)**: 7 items
- **Internalizing (int)**: 8 items
- **Externalizing (ext)**: 17 items
- **General only**: 3 items

---
*Last Updated: September 16, 2025*
*Codebook Version: 2.6*
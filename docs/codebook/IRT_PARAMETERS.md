# IRT Parameters in the Kidsights Codebook System

This document describes the Item Response Theory (IRT) parameter system implemented in the Kidsights codebook JSON structure.

## Overview

The codebook supports IRT parameters for multiple studies, storing calibration parameters in a standardized 4-field structure. As of version 3.0, the system includes:

- **203 items** with NE22 unidimensional IRT parameters
- **44 PS items** with NE22 bifactor model parameters
- **60 CREDI items** with Short Form (SF) and/or Long Form (LF) parameters
- **132 GSED items** with Rasch model parameters across multiple calibrations
- **Array-based threshold storage** for clean JSON representation

## IRT Parameter Structure

### Schema
Every IRT parameter entry follows this 4-field structure:

```json
"irt_parameters": {
  "STUDY_NAME": {
    "factors": ["factor1", "factor2"],
    "loadings": [0.492, 1.447],
    "thresholds": [-2.782, -0.193],
    "constraints": []
  }
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `factors` | Array of strings | Factor names (e.g., "gen", "eat", "sle") |
| `loadings` | Array of numbers | Factor loadings corresponding to factors |
| `thresholds` | Array of numbers | Item thresholds in ascending order |
| `constraints` | Array | Constraints applied during estimation |

## Study-Specific Parameters

### NE22 Unidimensional Model
For most items, NE22 parameters follow a unidimensional structure:

```json
"NE22": {
  "factors": ["kidsight"],
  "loadings": [1.234],
  "thresholds": [-1.45, 0.67, 2.12],
  "constraints": []
}
```

### NE22 Bifactor Model (PS Items)
Psychosocial items use a bifactor model with general and specific factors:

```json
"NE22": {
  "factors": ["gen", "int"],
  "loadings": [0.205, 0.287],
  "thresholds": [-1.418, 0.167],
  "constraints": []
}
```

**Bifactor Factors:**
- `gen`: General psychosocial problems factor
- `eat`: Feeding problems
- `sle`: Sleep problems
- `soc`: Social-emotional problems
- `int`: Internalizing problems
- `ext`: Externalizing problems

### CREDI Two-Model Structure
CREDI items use nested keys to support both Short Form (SF) and Long Form (LF) scoring:

```json
"CREDI": {
  "short_form": {
    "factors": ["credi_overall"],
    "loadings": [0.669],
    "thresholds": [17.622],
    "constraints": [],
    "model_type": "unidimensional",
    "description": "CREDI-SF scoring (62-item)"
  },
  "long_form": {
    "factors": ["sem"],
    "loadings": [0.962],
    "thresholds": [7.634],
    "constraints": [],
    "model_type": "multidimensional",
    "description": "CREDI-LF scoring (117-item, 4 factors: mot, cog, lang, sem)"
  }
}
```

**CREDI Structure:**
- 60 items in codebook (cross-study equated items)
- 37 items have both SF and LF parameters
- 23 items have LF parameters only
- **SF**: Unidimensional (credi_overall), threshold = -delta / alpha
- **LF**: Multidimensional (mot/cog/lang/sem), threshold = -tau

### GSED Multi-Calibration Structure
GSED items use calibration-level keys to store parameters from multiple studies:

```json
"GSED": {
  "gsed2406": {
    "factors": ["gsed"],
    "loadings": [1.0],
    "thresholds": [-30.20],
    "constraints": [],
    "model_type": "rasch",
    "description": "GSED calibration: gsed2406"
  },
  "gsed2212": {
    "factors": ["gsed"],
    "loadings": [1.0],
    "thresholds": [-30.20],
    "constraints": [],
    "model_type": "rasch"
  },
  "gsed1912": {
    "factors": ["gsed"],
    "loadings": [1.0],
    "thresholds": [-38.17],
    "constraints": [],
    "model_type": "rasch"
  }
}
```

**GSED Structure:**
- 132 items in codebook with GSED parameters
- Average 3.03 calibrations per item
- Rasch model: unit loading (1.0) for all items
- Calibrations: gsed2406, gsed2212, gsed1912, 293_0, gcdg, dutch
- 126 items (95%) have varying thresholds across calibrations
- threshold = -tau
- Source: `dscore::builtin_itembank`

## Threshold Array Format

### Design Decision
Thresholds are stored as numeric arrays rather than named objects to avoid JSON serialization issues and maintain mathematical ordering.

**Preferred (Array):**
```json
"thresholds": [-1.418, 0.167]
```

**Avoided (Named Object):**
```json
"thresholds": {"t1": -1.418, "t2": 0.167}
```

### Threshold Ordering
- Arrays are automatically sorted in ascending order
- Position indicates threshold number: `thresholds[0]` = threshold 1
- Ensures mathematical constraint: `threshold[i] < threshold[i+1]`

## Mplus Integration

### Threshold Transformation
When importing from Mplus output, thresholds undergo transformation:

1. **Extract**: Parse thresholds from `[ item$1*value ]` syntax
2. **Negate**: Apply negative sign to Mplus values
3. **Sort**: Ensure ascending order for IRT convention

**Example transformation:**
```
Mplus: [ ps018$1*-0.16716 ] [ ps018$2*1.41800 ]
     ↓ (negate values)
Temp:  [0.16716, -1.41800]
     ↓ (sort ascending)
Final: [-1.41800, 0.16716]
```

### Parsing Code
The transformation is implemented in `scripts/codebook/update_ps_bifactor_irt.R`:

```r
transform_thresholds <- function(threshold_list) {
  # Extract and negate Mplus thresholds
  negated_thresholds <- -unlist(threshold_list)

  # Sort to ensure ascending order
  sorted_thresholds <- sort(negated_thresholds)

  return(sorted_thresholds)
}
```

## Migration Notes

### From GSED_PF to NE22
PS items were migrated from GSED_PF study parameters to NE22:

```r
# Remove old parameters
item$psychometric$irt_parameters$GSED_PF <- NULL

# Add new NE22 parameters
item$psychometric$irt_parameters$NE22 <- list(
  factors = factor_data$factors,
  loadings = factor_data$loadings,
  thresholds = threshold_data,
  constraints = list()
)
```

### Constraints Field Addition
The system was upgraded from 3-field to 4-field structure:

**Before (v2.1):**
```json
{"factors": [], "loadings": [], "thresholds": []}
```

**After (v2.6):**
```json
{"factors": [], "loadings": [], "thresholds": [], "constraints": []}
```

Migration moved existing `param_constraints` to the NE25 study's constraints field.

## Usage Examples

### Loading Parameters
```r
# Load codebook
codebook <- load_codebook("codebook/data/codebook.json")

# Get item with IRT parameters
ps018 <- get_item(codebook, "PS018")

# Access parameters
ne22_params <- ps018$psychometric$irt_parameters$NE22
factors <- ne22_params$factors        # ["gen", "int"]
loadings <- ne22_params$loadings      # [0.205, 0.287]
thresholds <- ne22_params$thresholds  # [-1.418, 0.167]
```

### Filtering Items with Parameters
```r
# Find all items with NE22 IRT parameters
items_with_ne22 <- list()
for (id in names(codebook$items)) {
  item <- codebook$items[[id]]
  if (!is.null(item$psychometric$irt_parameters$NE22)) {
    items_with_ne22[[id]] <- item
  }
}

cat("Found", length(items_with_ne22), "items with NE22 parameters")
```

## Validation

### Required Checks
- Thresholds in ascending order
- Equal length of factors and loadings arrays
- Valid factor names for bifactor models
- Non-empty arrays for populated parameters

### Example Validation
```r
validate_irt_parameters <- function(irt_params) {
  # Check threshold ordering
  thresholds <- irt_params$thresholds
  if (length(thresholds) > 1 && !all(diff(thresholds) > 0)) {
    stop("Thresholds must be in ascending order")
  }

  # Check factor/loading correspondence
  if (length(irt_params$factors) != length(irt_params$loadings)) {
    stop("Factors and loadings must have equal length")
  }

  return(TRUE)
}
```

## Files and Scripts

### Management Scripts
- `scripts/codebook/update_ne22_irt_parameters.R` - Populate unidimensional NE22 parameters
- `scripts/codebook/update_ps_bifactor_irt.R` - Parse Mplus bifactor output for PS items
- `scripts/codebook/update_credi_irt_parameters.R` - Populate CREDI SF/LF parameters
- `scripts/codebook/update_gsed_irt_parameters.R` - Populate GSED multi-calibration parameters
- `scripts/codebook/initial_conversion.R` - Template creation and migration

### Data Sources
- `temp/archive_2025/ne22_kidsights-parameter-values.csv` - NE22 unidimensional estimates
- `temp/archive_2025/bifactor5e.txt` - Mplus bifactor model output (PS items)
- `data/credi-mest_df.csv` - CREDI SF/LF parameter estimates
- `dscore::builtin_itembank` - GSED Rasch parameters (R package)

---
*Last Updated: September 29, 2025*
*Codebook Version: 3.0*
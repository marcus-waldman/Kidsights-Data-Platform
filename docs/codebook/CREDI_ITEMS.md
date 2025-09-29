# CREDI Items in the Kidsights Codebook

This document describes the CREDI (Caregiver Reported Early Development Instruments) items and their IRT parameters in the codebook system.

## Overview

The codebook includes **60 CREDI items** (cross-study equated) with IRT parameters for two scoring procedures:
- **Short Form (SF)**: 37 items, unidimensional model
- **Long Form (LF)**: 60 items, multidimensional model

### Key Characteristics
- **Item Range**: LF1-LF108 (CREDI lexicon codes)
- **Studies**: Items that also appear in NE25, NE22, NE20, and GSED studies
- **Two Models**: SF (62-item subset) and LF (117-item full form)
- **Codebook Coverage**: 60 items (cross-study equated items only)

## Two-Model Structure

### Short Form (SF) - Unidimensional

**Model:** 1-parameter logistic with discrimination
- **Items**: 37 items in codebook (62 total in SF)
- **Factor**: "credi_overall" (single general development factor)
- **Loading**: Discrimination parameter (alpha)
- **Threshold**: Transformed from difficulty: `threshold = -delta / alpha`

```json
"short_form": {
  "factors": ["credi_overall"],
  "loadings": [0.669],
  "thresholds": [17.622],
  "constraints": [],
  "model_type": "unidimensional",
  "description": "CREDI-SF scoring (62-item)"
}
```

### Long Form (LF) - Multidimensional

**Model:** 4-factor multidimensional IRT
- **Items**: 60 items in codebook (117 total in LF)
- **Factors**: mot (motor), cog (cognitive), lang (language), sem (socioemotional)
- **Loadings**: Factor-specific discrimination parameters
- **Threshold**: Transformed from tau: `threshold = -tau`

```json
"long_form": {
  "factors": ["sem"],
  "loadings": [0.962],
  "thresholds": [7.634],
  "constraints": [],
  "model_type": "multidimensional",
  "description": "CREDI-LF scoring (117-item, 4 factors: mot, cog, lang, sem)"
}
```

## Item Distribution

### By Model Participation
- **Both SF and LF**: 37 items (have both `short_form` and `long_form` keys)
- **LF Only**: 23 items (have only `long_form` key)

### By Factor (LF Model)
Items load on one or more of the four LF factors:
- **Motor (mot)**: Gross and fine motor development
- **Cognitive (cog)**: Problem-solving, spatial reasoning
- **Language (lang)**: Receptive and expressive language
- **Socioemotional (sem)**: Social interaction, emotional regulation

### Multi-Factor Items
5 items load on multiple LF factors (e.g., LF19 loads on both mot and cog)

## JSON Structure

### Complete Example (Item with Both Models)

```json
"irt_parameters": {
  "NE22": {
    "factors": ["kidsights"],
    "loadings": [1.234],
    "thresholds": [2.145],
    "constraints": []
  },
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
}
```

## Parameter Transformations

### Source Data
Parameters come from `data/credi-mest_df.csv` with columns:
- `CREDI_code`: Item identifier (LF1, LF2, etc.)
- `ShortForm`: Boolean indicating SF inclusion
- `alpha`: Discrimination (SF)
- `delta`: Difficulty (SF)
- `tau`: Threshold (LF)
- `MOT`, `COG`, `LANG`, `SEM`: Factor loadings (LF)

### Transformations Applied

**Short Form:**
```r
loading <- alpha
threshold <- -delta / alpha  # Convert difficulty to threshold
```

**Long Form:**
```r
# Extract non-zero loadings
factors <- c("mot", "cog", "lang", "sem")[loadings != 0]
loadings <- loadings[loadings != 0]
threshold <- -tau  # Simple negation
```

## Usage Examples

### Access SF Parameters
```r
# Load codebook
codebook <- load_codebook("codebook/data/codebook.json")

# Get CREDI item
item <- codebook$items[["AA50"]]  # LF4 / QS01

# Access Short Form parameters
if (!is.null(item$psychometric$irt_parameters$CREDI$short_form)) {
  sf <- item$psychometric$irt_parameters$CREDI$short_form
  cat("SF loading:", sf$loadings[[1]], "\n")
  cat("SF threshold:", sf$thresholds[[1]], "\n")
}
```

### Access LF Parameters
```r
# Get Long Form parameters
lf <- item$psychometric$irt_parameters$CREDI$long_form
cat("LF factors:", paste(lf$factors, collapse = ", "), "\n")
cat("LF loadings:", paste(lf$loadings, collapse = ", "), "\n")
cat("LF threshold:", lf$thresholds[[1]], "\n")
```

### Find Items by Model
```r
# Find all CREDI items with SF parameters
sf_items <- list()
for (id in names(codebook$items)) {
  item <- codebook$items[[id]]
  if (!is.null(item$psychometric$irt_parameters$CREDI$short_form)) {
    sf_items[[id]] <- item
  }
}

cat("Found", length(sf_items), "items in CREDI Short Form\n")
```

### Find Multi-Factor Items
```r
# Find items loading on multiple LF factors
multi_factor_items <- list()
for (id in names(codebook$items)) {
  item <- codebook$items[[id]]
  lf <- item$psychometric$irt_parameters$CREDI$long_form
  if (!is.null(lf) && length(lf$factors) > 1) {
    multi_factor_items[[id]] <- item
  }
}

cat("Found", length(multi_factor_items), "multi-factor CREDI items\n")
```

## Data Sources and Processing

### Source File
- **Location**: `data/credi-mest_df.csv`
- **Total Items**: 117 CREDI items with parameter estimates
- **Codebook Match**: 60 items (cross-study equated)

### Processing Pipeline

1. **Parse CSV** (`update_credi_irt_parameters.R`):
   ```
   credi-mest_df.csv → Match CREDI_code to lexicons.credi
   ```

2. **Transform Parameters**:
   - SF: threshold = -delta / alpha
   - LF: threshold = -tau, extract non-zero factor loadings

3. **Populate Codebook**:
   - Create nested structure: CREDI → short_form/long_form
   - For ShortForm=TRUE items: add both SF and LF
   - For ShortForm=FALSE items: add LF only

### Update Command
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/codebook/update_credi_irt_parameters.R
```

## Validation

### Required Checks
- Items with SF parameters must have `ShortForm=TRUE` in source data
- All items must have LF parameters
- Multi-factor items must have equal-length factors and loadings arrays
- Thresholds must be properly transformed

### Example Validation
```r
validate_credi_parameters <- function(item) {
  credi <- item$psychometric$irt_parameters$CREDI

  # Check LF presence (required)
  if (is.null(credi$long_form)) {
    stop("CREDI items must have long_form parameters")
  }

  # Check SF consistency
  if (!is.null(credi$short_form)) {
    sf <- credi$short_form
    if (length(sf$factors) != 1 || sf$factors[[1]] != "credi_overall") {
      stop("SF must have single factor 'credi_overall'")
    }
  }

  # Check LF factor/loading correspondence
  lf <- credi$long_form
  if (length(lf$factors) != length(lf$loadings)) {
    stop("LF factors and loadings must have equal length")
  }

  return(TRUE)
}
```

## Summary Statistics

### Current Status (v3.0)
- **Total CREDI Items in Codebook**: 60
- **Items with SF Parameters**: 37
- **Items with LF Parameters**: 60
- **Multi-Factor Items**: 14
- **LF Factor Distribution**:
  - Motor: ~30 items
  - Cognitive: ~25 items
  - Language: ~20 items
  - Socioemotional: ~15 items

---
*Last Updated: September 29, 2025*
*Codebook Version: 3.0*
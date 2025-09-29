# GSED Items in the Kidsights Codebook

This document describes the GSED (Global Scales for Early Development) items and their IRT parameters in the codebook system.

## Overview

The codebook includes **132 GSED items** with Rasch model IRT parameters from multiple calibration studies:
- **Model**: Rasch (1-parameter logistic with unit loading)
- **Calibrations**: Average 3.03 calibrations per item
- **Source**: `dscore::builtin_itembank` R package

### Key Characteristics
- **Item Codes**: Various GSED instrument codes (cromoc*, croclc*, iyomoc*, mdtsed*, etc.)
- **Studies**: Items that cross-equate with NE25, NE22, NE20, CREDI studies
- **Rasch Model**: Unit loading (1.0) for all items
- **Multi-Calibration**: Each item has 2-4 calibration studies

## Multi-Calibration Structure

### Calibration-Level Keys

GSED items use nested keys to store parameters from different calibration studies:

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
    "model_type": "rasch",
    "description": "GSED calibration: gsed2212"
  },
  "gsed1912": {
    "factors": ["gsed"],
    "loadings": [1.0],
    "thresholds": [-38.17],
    "constraints": [],
    "model_type": "rasch",
    "description": "GSED calibration: gsed1912"
  }
}
```

### Calibration Studies

Six calibration studies are included in `dscore::builtin_itembank`:

| Calibration Key | Description | Items |
|-----------------|-------------|-------|
| `gsed2406` | GSED Phase 2406 | Most common |
| `gsed2212` | GSED Phase 2212 | Most common |
| `gsed1912` | GSED Phase 1912 | Most common |
| `293_0` | GSED Phase 293 | Less common |
| `gcdg` | Gradual Child Development Guide | Less common |
| `dutch` | Dutch validation study | Least common |

**Distribution in Codebook:**
- 2 calibrations: 6 items
- 3 calibrations: 116 items (most common)
- 4 calibrations: 10 items

## Rasch Model Structure

### Unit Loading Constraint

All GSED items follow the Rasch model with **loading = 1.0**:
- Simplifies interpretation (all items equally discriminating)
- Focuses on item difficulty (threshold) differences
- Allows common scale across calibrations

### Threshold Transformation

Source data provides `tau` (difficulty parameter):
```r
threshold <- -tau  # Simple negation
```

**Example:**
- Source: `tau = 30.20`
- Stored: `threshold = -30.20`

## Varying Thresholds Across Calibrations

### Importance of Multiple Calibrations

**126 items (95%)** have different thresholds across calibrations:

| Item | Study | Threshold | Difference |
|------|-------|-----------|------------|
| CC12 (crosec002) | gsed2406 | -30.15 | Baseline |
| | gsed2212 | -30.15 | Same |
| | gsed1912 | -56.48 | **-26.33** |

**Top 5 Largest Threshold Ranges:**
1. **CC12** (crosec002): range = 26.33
2. **CC13** (iyosec001): range = 21.34
3. **CC8** (iyosec004): range = 21.26
4. **CC6** (croclc001): range = 21.18
5. **CC9** (iyolgc002): range = 20.41

### Why This Matters

Different calibrations reflect:
- **Population differences**: Items may be easier/harder in different samples
- **Age range effects**: Different calibrations cover different age spans
- **Cultural adaptation**: Local norming adjustments
- **Study design**: Longitudinal vs. cross-sectional effects

## JSON Structure

### Complete Example

```json
"irt_parameters": {
  "NE22": {
    "factors": ["kidsights"],
    "loadings": [0.852],
    "thresholds": [2.145],
    "constraints": []
  },
  "CREDI": {
    "long_form": {
      "factors": ["mot"],
      "loadings": [1.027],
      "thresholds": [8.180],
      "constraints": [],
      "model_type": "multidimensional"
    }
  },
  "GSED": {
    "gsed2406": {
      "factors": ["gsed"],
      "loadings": [1.0],
      "thresholds": [-29.530],
      "constraints": [],
      "model_type": "rasch",
      "description": "GSED calibration: gsed2406"
    },
    "gsed2212": {
      "factors": ["gsed"],
      "loadings": [1.0],
      "thresholds": [-29.530],
      "constraints": [],
      "model_type": "rasch",
      "description": "GSED calibration: gsed2212"
    },
    "gsed1912": {
      "factors": ["gsed"],
      "loadings": [1.0],
      "thresholds": [-38.050],
      "constraints": [],
      "model_type": "rasch",
      "description": "GSED calibration: gsed1912"
    }
  }
}
```

## Usage Examples

### Access All Calibrations
```r
# Load codebook
codebook <- load_codebook("codebook/data/codebook.json")

# Get GSED item
item <- codebook$items[["AA12"]]  # cromoc009

# Access all GSED calibrations
gsed_params <- item$psychometric$irt_parameters$GSED

# Iterate through calibrations
for (cal_key in names(gsed_params)) {
  cal <- gsed_params[[cal_key]]
  cat(cal_key, ": threshold =", cal$thresholds[[1]], "\n")
}
```

### Compare Calibrations
```r
# Compare thresholds across calibrations
compare_calibrations <- function(item_id) {
  item <- codebook$items[[item_id]]
  gsed <- item$psychometric$irt_parameters$GSED

  thresholds <- sapply(gsed, function(cal) cal$thresholds[[1]])

  cat("Item:", item_id, "\n")
  cat("Calibrations:", length(thresholds), "\n")
  cat("Range:", max(thresholds) - min(thresholds), "\n")

  return(thresholds)
}

# Example
compare_calibrations("AA12")
```

### Find Items with Varying Thresholds
```r
# Find items with large threshold differences
large_variation <- list()

for (id in names(codebook$items)) {
  item <- codebook$items[[id]]

  if (!is.null(item$psychometric$irt_parameters$GSED)) {
    gsed <- item$psychometric$irt_parameters$GSED
    thresholds <- sapply(gsed, function(cal) cal$thresholds[[1]])

    if (length(thresholds) > 1) {
      threshold_range <- max(thresholds) - min(thresholds)

      if (abs(threshold_range) > 10) {
        large_variation[[id]] <- list(
          gsed_code = item$lexicons$gsed,
          range = abs(threshold_range)
        )
      }
    }
  }
}

# Sort by range
sorted <- large_variation[order(sapply(large_variation, function(x) -x$range))]
cat("Found", length(sorted), "items with threshold range > 10\n")
```

### Extract for Specific Calibration
```r
# Get parameters for specific calibration study
get_calibration_params <- function(study_key = "gsed2406") {
  params_list <- list()

  for (id in names(codebook$items)) {
    item <- codebook$items[[id]]

    if (!is.null(item$psychometric$irt_parameters$GSED[[study_key]])) {
      params_list[[id]] <- item$psychometric$irt_parameters$GSED[[study_key]]
    }
  }

  return(params_list)
}

# Get all gsed2406 parameters
gsed2406_params <- get_calibration_params("gsed2406")
cat("Found", length(gsed2406_params), "items in gsed2406 calibration\n")
```

## Data Sources and Processing

### Source Package
- **Package**: `dscore` (CRAN)
- **Dataset**: `dscore::builtin_itembank`
- **Total Items**: 1,793 unique GSED items
- **Total Rows**: 5,045 (items × calibrations)
- **Codebook Match**: 132 items (cross-study equated)

### Processing Pipeline

1. **Load from dscore** (`update_gsed_irt_parameters.R`):
   ```r
   itembank <- dscore::builtin_itembank
   ```

2. **Match Items**:
   - Match `item` column to `lexicons.gsed` in codebook
   - Filter to items with "GSED" in studies array

3. **Transform Parameters**:
   ```r
   loading <- 1.0  # Rasch model
   threshold <- -tau  # Negate difficulty
   ```

4. **Populate Codebook**:
   - Create nested structure: GSED → calibration_key → parameters
   - Add all calibrations for each matched item

### Update Command
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/codebook/update_gsed_irt_parameters.R
```

## Validation

### Required Checks
- All items must have at least one calibration
- All calibrations must have loading = 1.0
- All calibrations must have single factor = "gsed"
- Calibration keys must match expected values

### Example Validation
```r
validate_gsed_parameters <- function(item) {
  gsed <- item$psychometric$irt_parameters$GSED

  # Check at least one calibration
  if (length(gsed) == 0) {
    stop("GSED items must have at least one calibration")
  }

  # Check each calibration
  for (cal_key in names(gsed)) {
    cal <- gsed[[cal_key]]

    # Check Rasch model
    if (cal$loadings[[1]] != 1.0) {
      stop("GSED items must have unit loading (1.0)")
    }

    # Check single factor
    if (length(cal$factors) != 1 || cal$factors[[1]] != "gsed") {
      stop("GSED items must have single factor 'gsed'")
    }

    # Check model type
    if (cal$model_type != "rasch") {
      stop("GSED items must have model_type 'rasch'")
    }
  }

  return(TRUE)
}
```

## Summary Statistics

### Current Status (v3.0)
- **Total GSED Items**: 132
- **Total Calibrations**: 400
- **Average Calibrations per Item**: 3.03
- **Items with Varying Thresholds**: 126 (95%)
- **Largest Threshold Range**: 26.33 (crosec002)

### Calibration Distribution
- **2 calibrations**: 6 items (5%)
- **3 calibrations**: 116 items (88%) - most common
- **4 calibrations**: 10 items (8%)

### Common Calibration Combinations
Most items (116) have the "standard three":
- gsed2406
- gsed2212
- gsed1912

Items with 4 calibrations add one of:
- gcdg (most common for 4th calibration)
- 293_0
- dutch (rare)

---
*Last Updated: September 29, 2025*
*Codebook Version: 3.0*
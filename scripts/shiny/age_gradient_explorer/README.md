# Age-Response Gradient Explorer

**Interactive Shiny app for visualizing developmental item age-response gradients with GAM smoothing**

---

## Overview

This Shiny app provides an interactive interface for exploring age-response relationships across 308 developmental and behavioral items from the Kidsights calibration dataset. It combines data from six studies (NE20, NE22, NE25, NSCH21, NSCH22, USA24) spanning 2020-2025 with 46,212 total observations.

**Key Features:**
- **GAM Smoothing:** Visualize non-linear age trends using Generalized Additive Models with b-splines
- **Multi-Study Filtering:** Select which studies to include in the analysis
- **Box Plot Overlays:** Show age distributions at each response category level
- **Quality Flag Warnings:** Automatic alerts for items with data quality issues
- **Codebook Integration:** Full metadata display for each item
- **Performance Optimized:** No scatter points for fast rendering with large datasets

---

## Quick Start

### Prerequisites

Ensure you have all required R packages installed:

```r
install.packages(c("shiny", "duckdb", "dplyr", "ggplot2", "mgcv", "jsonlite", "DT"))
```

### Launching the App

From the project root directory:

```r
# Option 1: Using runApp()
shiny::runApp("scripts/shiny/age_gradient_explorer")

# Option 2: Using app.R directly
source("scripts/shiny/age_gradient_explorer/app.R")
```

From within the app directory:

```r
setwd("scripts/shiny/age_gradient_explorer")
shiny::runApp()
```

The app will open automatically in your default web browser.

---

## User Interface

### Sidebar Panel (Left)

#### 1. Study Filter
- **Checkboxes:** Select which studies to include in the analysis
  - NE20: Nebraska Early Childhood Study 2020
  - NE22: Nebraska Early Childhood Study 2022
  - NE25: Nebraska Early Childhood Study 2025
  - NSCH21: National Survey of Children's Health 2021
  - NSCH22: National Survey of Children's Health 2022
  - USA24: USA National Study 2024
- **Buttons:**
  - **Select All:** Include all six studies
  - **Deselect All:** Clear all study selections

#### 2. Item Selection
- **Searchable Dropdown:** Select an item from 308 available developmental/behavioral items
  - Search by item code (e.g., "AA7", "PS1")
  - Search by description text
  - Shows item code + truncated description for easy identification

#### 3. Display Options
- **Show GAM Smooth:** Toggle Generalized Additive Model smoothing line (default: ON)
- **Show Box Plots:** Overlay box-and-whisker plots showing age distribution at each response level (default: OFF)
- **Color by Study:** When enabled with multiple studies selected, fits separate GAMs per study with color-coded lines (default: ON)
- **GAM Smoothness (k):** Adjust the basis dimension for the GAM smooth
  - Range: 3-10 (default: 5)
  - Lower k = more flexible (may overfit)
  - Higher k = smoother (may underfit)

#### 4. Summary Statistics
Displays key statistics for the filtered data:
- **n observations:** Total non-missing responses
- **Age range:** Minimum to maximum age in years
- **% missing:** Percentage of missing responses across selected studies
- **Correlation (age × response):** Pearson correlation coefficient
  - Positive values indicate developmental progression (skills increase with age)
  - Negative values may indicate data quality issues or reverse-coded items

### Main Panel (Right)

#### 1. Item Description
- Displays the full item description from the codebook
- Shows item code as a heading

#### 2. Quality Flag Warnings
- **Appears only for flagged items**
- Color-coded by severity:
  - **Red (ERROR):** Critical issues like category mismatches
  - **Orange (WARNING):** Potential issues like negative correlations
- Shows flag type, study, and description

#### 3. Age Gradient Plot
- **X-axis:** Age in years (0-6)
- **Y-axis:** Item response value
- **GAM Line(s):**
  - Blue line: Single GAM across all selected studies
  - Colored lines: Study-specific GAMs when "Color by Study" is enabled
- **Box Plots (optional):**
  - Horizontal boxes at each response category level
  - Shows age distribution (median, quartiles, range) for that response value
  - Useful for understanding category overlap and separation
- **No scatter points** (for performance with 46k+ observations)
- **No confidence bands** (for visual clarity)

#### 4. Codebook Metadata
- Complete JSON metadata for the selected item
- Includes:
  - Item ID and study information
  - Lexicon mappings (equate, kidsight, ne25, etc.)
  - Content description and response options
  - Psychometric properties (expected categories, calibration status)
  - Instrument assignments
  - Any other metadata fields

---

## Interpreting Results

### Positive Gradients (Expected)

**Example: Parenting Stress (PS) items**

Positive age-response correlations are expected for items measuring constructs that increase with age, such as:
- Parenting stress (as children grow, parents may experience different stressors)
- Behavioral problems (some behaviors emerge or intensify with age)

**Interpretation:**
- Upward-sloping GAM line
- Positive correlation value (e.g., 0.15-0.40)
- Normal developmental pattern for these constructs

### Negative Gradients (Unexpected - Quality Flags)

**Example: Developmental skill items (AA7, AA15)**

Negative age-response correlations are generally unexpected for developmental items and trigger quality flags:
- Skills should increase with age (e.g., language, motor skills)
- Negative correlations suggest:
  - Reverse coding issues
  - Data collection problems
  - Category labeling errors

**Interpretation:**
- Downward-sloping GAM line
- Negative correlation value (e.g., -0.20)
- Quality flag warning displayed
- Item may need exclusion from calibration or recoding

### Zero/Flat Gradients

Items with minimal age-response relationship:
- May be age-invariant constructs (e.g., temperament traits)
- Could indicate low item quality or high measurement error
- Check % missing and category distribution

### Box Plot Interpretation

When "Show Box Plots" is enabled:
- **Well-separated boxes:** Clear distinction between response categories across age
- **Overlapping boxes:** Poor discrimination between adjacent response levels
- **Wide boxes:** High age variability within a response category
- **Narrow boxes:** Response category concentrated in specific age range

---

## Technical Details

### GAM Specification

**Formula:** `response ~ s(years, bs = "bs", k = input$gam_k)`

- **s():** Smooth term
- **years:** Predictor variable (age in years)
- **bs = "bs":** B-spline basis (smooth, flexible curves)
- **k:** Basis dimension (user-adjustable, default = 5)
- **Family:** Gaussian (for continuous/ordinal responses)

### Data Source

**DuckDB Table:** `calibration_dataset_2020_2025`

- **Records:** 46,212 observations
- **Studies:** 6 (NE20, NE22, NE25, NSCH21, NSCH22, USA24)
- **Items:** 308 developmental/behavioral items
- **Age Range:** 0-6 years (early childhood)
- **Metadata Columns:** study, studynum, id, years

### Quality Flags

**Source:** `docs/irt_scoring/quality_flags.csv` (76 flags)

**Flag Types:**
1. **CATEGORY_MISMATCH:** Observed categories don't match expected categories from codebook
2. **NEGATIVE_CORRELATION:** Negative age-response correlation for developmental items
3. **NON_SEQUENTIAL:** Non-consecutive response values (e.g., 0, 1, 3 instead of 0, 1, 2)

**Severity Levels:**
- **ERROR:** Critical issues requiring attention before calibration
- **WARNING:** Potential issues worth investigating

---

## File Structure

```
scripts/shiny/age_gradient_explorer/
├── app.R          # Launcher script (calls shiny::runApp())
├── global.R       # Data loading and setup (runs once on app startup)
├── ui.R           # User interface definition (all UI components)
├── server.R       # Server logic (reactives, observers, rendering)
└── README.md      # This documentation file
```

**Design Pattern:** Traditional Shiny multi-file structure for organization and maintainability

---

## Performance Notes

**Optimizations:**
- **No scatter points:** With 46k+ observations, scatter plots would be very slow to render
- **No confidence bands:** Simplifies rendering and improves visual clarity
- **Cached data:** Data loaded once on app startup in global.R
- **Debounced GAM fitting:** Prevents excessive re-fitting during slider adjustment

**Expected Performance:**
- App startup: 3-5 seconds (data loading)
- Plot rendering: < 1 second for most items
- GAM fitting: < 500ms for typical datasets

---

## Troubleshooting

### App won't launch

**Error:** `Database not found at: data/duckdb/kidsights_local.duckdb`

**Cause:** The calibration dataset hasn't been created yet, or paths are incorrect.

**Solution 1 - Create calibration dataset:**
Run the IRT calibration pipeline first to create the calibration dataset:

```r
source("scripts/irt_scoring/prepare_calibration_dataset.R")
prepare_calibration_dataset()
```

**Solution 2 - Verify paths:**
The app uses relative paths from the app directory (`../../../`) to access project resources. If you moved or renamed directories, verify:
- Database: `data/duckdb/kidsights_local.duckdb` exists at project root
- Codebook: `codebook/data/codebook.json` exists at project root
- Quality flags: `docs/irt_scoring/quality_flags.csv` exists at project root

**Note:** Always launch the app from the project root directory, not from within the app directory

### GAM fitting failed

**Message:** "GAM fitting failed (insufficient data or convergence issue)"

**Causes:**
- Too few observations (< 10) for the selected study/item combination
- Item has very limited response variability
- Smoothness parameter (k) too high relative to data

**Solutions:**
- Select more studies to increase sample size
- Reduce the GAM smoothness slider (k)
- Check if item has adequate response distribution

### Missing item descriptions

**Symptom:** Item dropdown shows only item codes, not descriptions

**Cause:** Codebook metadata not available for some items

**Solution:** This is expected for a small number of items; metadata lookup is incomplete

---

## Use Cases

### 1. Quality Assurance
- Identify items with unexpected age-response patterns
- Verify developmental items show positive gradients
- Cross-check quality flags with visual inspection

### 2. Item Selection for Calibration
- Exclude items with negative gradients from IRT calibration
- Identify items with poor category separation (overlapping box plots)
- Select items with strong age-response relationships

### 3. Developmental Research
- Explore age trajectories for specific constructs
- Compare developmental patterns across studies
- Identify age ranges with rapid skill acquisition

### 4. Codebook Validation
- Verify expected categories match observed categories
- Check response option definitions
- Review instrument assignments

---

## Citation

When using this app in publications, please cite:

> Marcus, A. (2025). Age-Response Gradient Explorer [Shiny application].
> Kidsights Data Platform. https://github.com/your-org/kidsights-data-platform

---

## Contact

For questions, issues, or feature requests:
- Open an issue on GitHub
- Contact the Kidsights team

**Version:** 1.0.0
**Last Updated:** November 2025

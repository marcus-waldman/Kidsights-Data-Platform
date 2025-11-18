# Age-Response Gradient Explorer

**Interactive Shiny app for systematic review of developmental item age-response gradients with configurable influence point analysis and database-backed review notes**

---

## Overview

This Shiny app provides an interactive interface for exploring age-response relationships across 308 developmental and behavioral items from the Kidsights calibration dataset. It combines data from six studies (NE20, NE22, NE25, NSCH21, NSCH22, USA24) spanning 2020-2025 with 9,512 total observations.

**Key Features:**
- **Regression-Based Smoothing:** Statistical models appropriate for categorical response data
  - Binary items: Logistic regression (probability curves)
  - Ordinal items: Linear regression (predicted response level)
- **Configurable Influence Point Threshold:** Slider to adjust sensitivity (1-5% top influential observations)
- **Multi-Study Filtering:** Select which studies to include in the analysis
- **Pooled vs Study-Specific Display:** Toggle between combined analysis or separate curves per study
- **Database-Backed Review Notes:** Systematic item review with version history stored in DuckDB
- **Quality Flag Warnings:** Automatic alerts for items with data quality issues
- **Codebook Integration:** Full metadata display for each item
- **Database Connection Management:** Explicit control over database resources

---

## Quick Start

### Prerequisites

Ensure you have all required R packages installed:

```r
install.packages(c("shiny", "duckdb", "dplyr", "ggplot2", "jsonlite", "DT",
                   "future", "future.apply", "patchwork"))
```

### First-Time Setup: Precompute Models

**Important:** The app requires precomputed regression models for all items. This is a **one-time** setup step (or rerun when calibration data updates).

```r
# Run precomputation script (uses parallel processing, ~5-10 seconds)
source("scripts/shiny/age_gradient_explorer/precompute_models.R")
```

**What this does:**
- Fits logistic/linear regression models for all 308 items in parallel
- Computes influence metrics (Cook's D) at 5 thresholds (1%, 2%, 3%, 4%, 5%)
- Fits 6 models per item: 1 full + 5 reduced (excluding influence points at each threshold)
- Saves results to `scripts/shiny/age_gradient_explorer/precomputed_models.rds` (~4.5 MB)
- Uses `future` package with parallel workers (defaults to cores - 1)

**Performance:**
- Precomputation: ~5-10 seconds (parallel processing on 32-core system)
- File size: ~4.5 MB (compressed)
- App startup after precomputation: < 2 seconds (just loads saved file)

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
  - Search by item code (e.g., "DD201", "EG13b")
  - Search by description text
  - Shows item code + truncated description for easy identification

#### 3. Display Options
- **Display Mode (Radio Buttons):**
  - **Pooled (combined studies):** Single smoothing curve combining all selected studies
  - **Study-Specific (colored curves):** Separate curves per study, colored for comparison
- **Influence Point Threshold (Slider):** Adjust sensitivity from 1% to 5% (default: 5%)
  - Controls which observations are flagged as influential based on Cook's D percentile
  - Lower values = more stringent (fewer influence points)
  - Higher values = more lenient (more influence points)
- **Exclude Influence Points from Curves:** Fit regression models excluding influential observations
- **Show Influence Points (markers):** Overlay vertical dash markers (|) showing influential observations

#### 4. Summary Statistics
Displays key statistics for the filtered data:
- **n observations:** Total non-missing responses (updated when influence points excluded)
- **Age range:** Minimum to maximum age in years
- **% missing:** Percentage of missing responses across selected studies

#### 5. Database
Connection management controls:
- **Test Connection:** Verify database accessibility and show note count
- **Close All Connections:** Explicitly close all DuckDB connections and release resources
- **Status:** Real-time connection status indicator

### Main Panel (Right)

#### Tab 1: Regression Coefficients
- **Pre-computed age regression coefficients** for all 262 items (excludes 46 PS/Parenting Stress items)
- Displayed as beta coefficients on logit scale (binary) or original scale (ordinal)
- Negative coefficients highlighted in red (potential reverse coding or data quality issues)
- Sortable and searchable table
- Two viewing modes:
  - **Full Model:** Coefficients from models with all observations
  - **Reduced Model:** Coefficients excluding top 5% influence points
- Includes pooled coefficients across all studies plus study-specific values

#### Tab 2: Age Gradient Plot

##### Item Description
- Displays the full item description from the codebook
- Shows item code as a heading

##### Review Notes
- **Text Area:** Enter notes for systematic item review
- **Save Note Button:** Persist notes to DuckDB with timestamp and reviewer name
- **Last Saved:** Shows timestamp of most recent save
- **Show Previous Versions (Collapsible):**
  - Checkbox to reveal/hide version history (hidden by default)
  - View up to 5 most recent note versions
  - Load previous versions to edit and re-save
- **Auto-Reset:** Version history collapses when switching to different item
- **Storage:** All notes stored in `item_review_notes` table in DuckDB

##### Quality Flag Warnings
- **Appears only for flagged items**
- Color-coded by severity:
  - **Red (ERROR):** Critical issues like category mismatches
  - **Orange (WARNING):** Potential issues like negative correlations
- Shows flag type, study, and description

##### Age Gradient Plot
- **Main Plot (Top):**
  - **X-axis:** Age in years (0-6)
  - **Y-axis:**
    - Binary items: Predicted Probability (0-1)
    - Ordinal items: Predicted Response (on original scale, e.g., 0-4)
  - **Smoothing Method:**
    - **Binary items (2 categories):** Logistic regression curve showing P(Response = 1 | Age)
    - **Ordinal items (3+ categories):** Linear regression showing predicted response level
  - **Display Modes:**
    - **Pooled:** Single black curve for all items
    - **Study-Specific:** Colored curves per study
  - **Influence Points (optional):** Vertical dash markers (|) color-coded by study showing influential observations at selected threshold

- **Boxplots (Bottom):**
  - Horizontal boxplots showing age distribution for each selected study
  - Color-coded to match study colors in main plot
  - Automatically updates when "Exclude Influence Points" is enabled
  - Helps visualize which ages are represented in each study sample

##### Codebook Metadata
- Complete JSON metadata for the selected item
- Includes:
  - Item ID and study information
  - Lexicon mappings (equate, kidsights, ne25, cahmi21, cahmi22, etc.)
  - Content description and response options
  - Psychometric properties (expected categories, calibration status)
  - Scoring information (reverse coding, study-specific overrides)
  - Instrument assignments

---

## Interpreting Results

### Binary Items (2 Categories)

**Example: DD201 (ONEWORD) - "Can say one word clearly?"**

**Response Coding:** 0 = No, 1 = Yes

**Expected Pattern:** Upward-sloping logistic curve
- Younger children (0-1 years): Low probability (~0.1-0.3)
- Older children (2-3 years): High probability (~0.8-0.95)
- Inflection point around 12-18 months

**Interpretation:**
- **Positive slope:** Probability increases with age ✓ (expected developmental progression)
- **Negative slope:** Probability decreases with age ⚠ (reverse coding error or data quality issue)
- **Flat slope:** Age-invariant item (poor discriminability)

**Study-Specific Mode:**
- Parallel curves → Consistent across studies ✓
- Divergent curves → Study-specific calibration or harmonization issues ⚠

### Ordinal Items (3+ Categories)

**Example: DD205 (UNDERSTAND) - "How well does child understand you?"**

**Response Coding:** 0 = Not at All, 1 = Not Very Well, 2 = Somewhat Well, 3 = Very Well

**Expected Pattern:** Upward-sloping linear trend
- Predicted response increases with age
- Younger children: Lower predicted values (0-1 range)
- Older children: Higher predicted values (2-3 range)

**Interpretation:**
- **Positive slope:** Response level increases with age ✓ (expected developmental progression)
- **Negative slope:** Response level decreases with age ⚠ (reverse coding error)
- **Flat slope:** Poor age discrimination

**Study-Specific Mode:**
- Parallel lines → Consistent across studies ✓
- Different intercepts → Study differences in baseline levels
- Different slopes → Study-specific developmental trajectories ⚠

**Note:** Ordinal items use linear regression (not ordered logit) for simplicity and clarity. This treats response categories as numeric (0, 1, 2, 3) and provides a single clean developmental trajectory per study.

### Influence Points

**Vertical dash markers (|) color-coded by study indicate high-influence observations based on Cook's D at selected threshold:**

**Common Causes:**
1. **Age-routing artifacts:** Only certain ages asked specific items
2. **Outliers:** Unusual response for a given age (e.g., 6-year-old failing 1-year skill)
3. **Sparse cells:** Very few observations at extreme ages or rare responses

**Diagnostic Value:**
- Cluster of influence points at one age → Age-routing in survey design
- Scattered influence points → Genuine outliers or data quality issues
- Influence points driving downward slope → May explain negative correlation
- Color coding reveals which study contributes the influential observations

**Threshold Selection:**
- **1%:** Most stringent - only extreme outliers
- **3%:** Moderate - typical outliers and leverage points
- **5%:** Liberal - includes moderately influential points (default)
- Compare curves with/without influence points to assess sensitivity

---

## Review Notes System

### Purpose
Systematic documentation of QA findings during item review for IRT calibration.

### Features
- **Persistent Storage:** Notes stored in DuckDB `item_review_notes` table
- **Version History:** Full audit trail of all note revisions
- **Timestamp & Reviewer:** Automatic capture of when and who saved notes
- **Collapsible History:** Clean interface with optional version viewing
- **SQL Queryable:** Use SQL to find patterns across reviews

### Database Schema
```sql
CREATE TABLE item_review_notes (
  id INTEGER PRIMARY KEY AUTO_INCREMENT,
  item_id VARCHAR,          -- Item name (e.g., 'DD205')
  note TEXT,                -- Review note content
  timestamp TIMESTAMP,      -- When note was saved
  reviewer VARCHAR,         -- Who saved it (system username)
  is_current BOOLEAN        -- TRUE for latest version
);
```

### Example Queries
```sql
-- Find all items with notes containing "negative"
SELECT item_id, note FROM item_review_notes
WHERE is_current = TRUE AND note LIKE '%negative%';

-- Count items reviewed per day
SELECT DATE(timestamp) as date, COUNT(DISTINCT item_id) as items_reviewed
FROM item_review_notes
GROUP BY DATE(timestamp);

-- Get full history for an item
SELECT * FROM item_review_notes
WHERE item_id = 'DD205'
ORDER BY timestamp DESC;
```

---

## Technical Details

### Statistical Models

#### Binary Items (Logistic Regression)
```r
model <- glm(response ~ years, family = binomial(), data = data)
prob <- predict(model, type = "response")
```

**Interpretation:**
- Logit link: log(p / (1-p)) = β₀ + β₁ × age
- β₁ > 0: Odds of positive response increase with age (expected)
- β₁ < 0: Odds decrease with age (reverse coding error)

#### Ordinal Items (Linear Regression)
```r
model <- lm(response ~ years, data = data)
predicted_response <- predict(model)
```

**Interpretation:**
- Simple linear model: E(Response | Age) = β₀ + β₁ × age
- β₁ > 0: Response level increases with age (expected)
- β₁ < 0: Response level decreases with age (reverse coding error)
- Treats ordinal categories as numeric for cleaner visualization
- Simplifies interpretation compared to ordered logit models

**Rationale for Linear Regression:**
- Ordinal categories represent meaningful progression (0→1→2→3)
- Linear model provides single clean trajectory per study
- Avoids complex probability curves with crossing lines
- Sufficient for QA purposes (identifying reverse coding, outliers)
- Much faster computation enables real-time threshold adjustments

### Influence Metrics

**Cook's D (Distance):**
- Measures combined leverage × residual for each observation
- Computed at 5 thresholds: 99th, 98th, 97th, 96th, 95th percentiles
- Precomputed during model fitting for fast threshold switching

**Formula:**
```
D_i = (residual_i² / (p × MSE)) × (leverage_i / (1 - leverage_i)²)
```

Where:
- p = number of parameters
- MSE = mean squared error
- leverage_i = hat value for observation i

**Precomputation Strategy:**
- Fit 6 models per item: 1 full + 5 reduced (one per threshold)
- Store influence data for all 5 thresholds
- App switches between precomputed models based on slider position
- No runtime model fitting required (instant threshold changes)

### Data Source

**DuckDB Table:** `calibration_dataset_2020_2025`

- **Records:** 9,512 observations
- **Studies:** 6 (NE20, NE22, NE25, NSCH21, NSCH22, USA24)
- **Items:** 308 developmental/behavioral items
- **Age Range:** 0-6 years (early childhood)
- **Metadata Columns:** study, studynum, id, years

**DuckDB Table:** `item_review_notes`

- **Records:** 361 notes (307 unique items reviewed)
- **Columns:** id, item_id, note, timestamp, reviewer, is_current
- **Indexes:** idx_item_notes(item_id, is_current)

### Quality Flags

**Source:** `docs/irt_scoring/quality_flags.csv` (46 flags)

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
├── app.R                      # Launcher script
├── global.R                   # Data loading, coefficient extraction, notes init
├── ui.R                       # User interface (study filter, item selector, display controls, notes UI)
├── server.R                   # Server logic (plots, tables, notes management, DB connections)
├── precompute_models.R        # Model precomputation script (run once)
├── notes_helpers_db.R         # DuckDB notes management functions
├── notes_helpers.R            # Legacy JSON notes functions (deprecated)
├── precomputed_models.rds     # Cached models (~4.5 MB, gitignored)
├── item_review_notes.json     # Legacy JSON notes (migrated to DB, kept for reference)
└── README.md                  # This documentation file
```

**Design Pattern:** Traditional Shiny multi-file structure for organization and maintainability

---

## Performance Notes

**Optimizations:**
- **Precomputed models:** All regression fits done upfront, app just loads results
- **Multi-threshold precomputation:** 5 reduced models per item avoid runtime refitting
- **No scatter points:** With 9k+ observations, scatter plots would slow rendering
- **Cached data:** Data loaded once on app startup in global.R
- **Database-backed notes:** DuckDB provides ACID transactions and indexing
- **Parallel processing:** Uses all available CPU cores during precomputation

**Expected Performance:**
- App startup: 3-5 seconds (data loading + notes initialization)
- Plot rendering: < 1 second for most items
- Threshold slider response: Instant (just swaps precomputed model)
- Note save: < 100ms (database insert with transaction)

---

## Troubleshooting

### App won't launch

**Error:** `Database not found at: data/duckdb/kidsights_local.duckdb`

**Cause:** The calibration dataset hasn't been created yet, or paths are incorrect.

**Solution:** Run the IRT calibration pipeline first:

```r
source("scripts/irt_scoring/prepare_calibration_dataset.R")
prepare_calibration_dataset()
```

### Precomputed models not found

**Warning:** `[WARN] Precomputed models not found!`

**Cause:** The precompute_models.R script hasn't been run yet.

**Solution:** Run precomputation script:

```r
source("scripts/shiny/age_gradient_explorer/precompute_models.R")
```

### Model fitting failed

**Message:** "Insufficient data to fit model"

**Causes:**
- Too few observations (< 10) for the selected study/item combination
- Item has zero variance (all responses identical)
- Complete separation in logistic regression

**Solutions:**
- Select more studies to increase sample size
- Check if item has adequate response distribution
- Try pooled mode instead of study-specific

### Database connection issues

**Error:** Connection failed or notes won't save

**Solutions:**
1. Click "Test Connection" to diagnose
2. Click "Close All Connections" to force cleanup
3. Check that kidsights_local.duckdb exists
4. Verify you have write permissions

---

## Use Cases

### 1. Quality Assurance (Primary Use)
- **Identify reverse coding errors:** Negative slopes for developmental items
- **Detect harmonization failures:** Study-specific curves inverted (e.g., NSCH21 vs NSCH22)
- **Verify developmental progression:** Positive slopes for skill items
- **Spot age-routing artifacts:** Influence points clustered at specific ages
- **Document findings:** Review notes with version history for audit trail

**Example:** Issue #8 NSCH negative correlations would have been immediately visible in study-specific mode, showing NSCH22 curves inverted relative to NSCH21.

### 2. Item Selection for IRT Calibration
- **Exclude problematic items:** Negative gradients, poor discrimination
- **Select strong items:** Steep curves with good age separation
- **Identify DIF candidates:** Study-specific curves differ substantially
- **Document decisions:** Notes explain why items included/excluded

### 3. Influence Point Sensitivity Analysis
- **Test threshold robustness:** Compare 1% vs 5% influence point exclusion
- **Identify fragile items:** Curves change dramatically at different thresholds
- **Diagnose outlier impact:** See if negative correlations disappear when outliers excluded

### 4. Developmental Research
- **Explore age trajectories:** When do skills emerge/plateau?
- **Compare developmental patterns:** Cross-study consistency
- **Identify sensitive age windows:** Steepest part of curve = rapid acquisition

### 5. Codebook Validation
- **Verify expected categories:** Match observed response distribution
- **Check reverse coding logic:** Confirm study-specific overrides work
- **Review response option definitions:** Ensure clarity

---

## Recent Updates

**Version 3.1.0 (November 2025):**
- **NEW:** Configurable influence point threshold slider (1-5%)
- **NEW:** Database-backed review notes system with version history
- **NEW:** Collapsible version history (hidden by default)
- **NEW:** Database connection management (Test/Close buttons)
- **NEW:** Domain labels in item dropdown (Cognitive/Language, Motor, Social-Emotional, Psychosocial Problems)
- **NEW:** Masking toggle to compare original vs QA-cleaned data (Issue #11: partial implementation)
- **NEW:** Response options display below item stem (Issue #11: partial implementation)
- **CHANGED:** Ordinal items now use linear regression instead of ordered logit
- **CHANGED:** Precomputed models now include 5 reduced model variants per item
- **CHANGED:** Now uses `calibration_dataset_long` table for maskflag data
- **IMPROVED:** Automatic notes migration from JSON to DuckDB
- **IMPROVED:** Real-time database status indicator

**Version 2.1.0 (November 2025):**
- **New feature:** Linear model (lm) fallback for non-converged logistic/polr models
- **Enhanced:** Influence points now color-coded by study (was single red color)
- **Enhanced:** Influence points use vertical dash markers (|) instead of dots for better visibility
- **New feature:** Horizontal boxplots below main plot showing age distribution by study
- **Improved:** Patchwork library for seamless plot composition

**Version 2.0.0 (November 2025):**
- **Major rewrite:** Replaced GAM smoothing with logistic/ordered logit models
- **New feature:** Pooled vs Study-Specific display toggle
- **New feature:** Cook's D influence point overlay
- **Improved:** Axes flipped (age on X, probability on Y)
- **Enhanced:** Faceted display for ordinal items in study-specific mode
- **Fixed:** Proper handling of binary vs ordinal item types

**Previous Version 1.0.0 (November 2025):**
- Initial release with GAM smoothing
- Box plot visualization
- Basic quality flag integration

---

## Citation

When using this app in publications, please cite:

> Waldman, M. (2025). Age-Response Gradient Explorer [Shiny application].
> Kidsights Data Platform. https://github.com/marcus-waldman/Kidsights-Data-Platform

---

## Contact

For questions, issues, or feature requests:
- Open an issue on GitHub
- Contact the Kidsights team

**Version:** 3.0.0
**Last Updated:** November 2025

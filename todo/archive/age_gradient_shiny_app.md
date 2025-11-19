# Age-Response Gradient Explorer Shiny App

**Created:** 2025-11-11
**Completed:** 2025-11-11
**Status:** Complete
**Purpose:** Interactive visualization of age-response gradients with GAM smoothing

---

## Phase 1: Project Setup & Data Loading

**Objective:** Create file structure and load calibration data

### Tasks

- [ ] Create directory structure: `scripts/shiny/age_gradient_explorer/`
  - Create `app.R` (launches the app - calls shiny::runApp())
  - Create `ui.R` (UI definition)
  - Create `server.R` (server logic)
  - Create `global.R` (data loading and setup, runs once on startup)
  - Create `README.md` (usage instructions)

- [ ] Implement data loading in global.R
  - Load calibration_dataset_2020_2025 from DuckDB
  - Query: SELECT study, studynum, years, [308 item columns]
  - Expected: 46,212 records × 312 columns

- [ ] Load codebook metadata
  - Load codebook.json using jsonlite::fromJSON()
  - Extract item descriptions for all 308 items
  - Create lookup: item_name → full codebook entry

- [ ] Load quality flags
  - Load quality_flags.csv (76 flags)
  - Create lookup: item_name + study → flag details

- [ ] Verify required packages
  - shiny
  - duckdb
  - dplyr
  - ggplot2
  - mgcv (GAM fitting)
  - jsonlite
  - DT (for displaying JSON)

- [ ] Test data loading
  - Verify all 308 items loaded
  - Check codebook lookup works
  - Verify quality flags loaded correctly

- [ ] Load Phase 2 tasks into Claude todo list
  - Use TodoWrite tool to add Phase 2 tasks
  - Mark Phase 1 as complete

---

## Phase 2: UI Layout & Controls

**Objective:** Build Shiny UI with all interactive controls

**Note:** All UI components should be implemented in `ui.R`

### Part 2A: Sidebar Panel

- [ ] Create study filter checkboxes
  - checkboxGroupInput with 6 studies (NE20, NE22, NE25, NSCH21, NSCH22, USA24)
  - Default: All studies selected
  - Label: "Filter by Study"

- [ ] Add "Select All" / "Deselect All" buttons
  - actionButton("select_all_studies")
  - actionButton("deselect_all_studies")
  - Place below study checkboxes

- [ ] Create item selection dropdown
  - selectizeInput with 308 items
  - Options: Show item name + description
  - Searchable
  - Label: "Select Item"

- [ ] Add display options section
  - Checkbox: "Show GAM Smooth" (default: TRUE)
  - Checkbox: "Show Box Plots" (default: FALSE)
  - Slider: "GAM Smoothness (k)" (range: 3-10, default: 5)
  - Checkbox: "Color by Study" (default: TRUE)

- [ ] Add summary statistics panel
  - Text outputs for:
    - n observations
    - Age range (min-max)
    - % missing
    - Pearson correlation (age × response)
  - Update reactively based on filtered data

### Part 2B: Main Panel

- [ ] Create plot output area
  - plotOutput("age_gradient_plot", height = "600px")
  - Responsive width

- [ ] Add item description text
  - textOutput or htmlOutput above plot
  - Show full item description from codebook

- [ ] Add quality flag warning banner
  - conditionalPanel: Show if item has flags
  - Display flag type, severity, description
  - Use alert styling (warning/error colors)

- [ ] Add codebook JSON display
  - DT::dataTableOutput or verbatimTextOutput
  - Show all codebook fields for selected item
  - Below the plot
  - Collapsible section (optional)

- [ ] Load Phase 3 tasks into Claude todo list
  - Use TodoWrite tool to add Phase 3 tasks
  - Mark Phase 2 as complete

---

## Phase 3: Server Logic - Data Filtering

**Objective:** Implement reactive data filtering and study selection

**Note:** All server logic should be implemented in `server.R`

### Tasks

- [ ] Implement study selection observers
  - observeEvent for "Select All" button
  - observeEvent for "Deselect All" button
  - Update checkboxGroupInput programmatically

- [ ] Create filtered_data reactive
  - Filter by selected studies
  - Filter by selected item (extract single column)
  - Remove NA values
  - Return data.frame with: study, years, response

- [ ] Create item_metadata reactive
  - Extract codebook entry for selected item
  - Return: description, expected_categories, instruments

- [ ] Create item_flags reactive
  - Filter quality_flags.csv by selected item
  - Return: All flags for this item (any study)
  - Handle case where no flags exist

- [ ] Implement summary statistics reactives
  - n_observations: nrow(filtered_data())
  - age_range: paste(min, max)
  - pct_missing: Calculate from full dataset
  - correlation: cor(years, response)

- [ ] Render summary statistics outputs
  - output$n_observations
  - output$age_range
  - output$pct_missing
  - output$correlation

- [ ] Load Phase 4 tasks into Claude todo list
  - Use TodoWrite tool to add Phase 4 tasks
  - Mark Phase 3 as complete

---

## Phase 4: GAM Fitting & Visualization

**Objective:** Implement GAM fitting with b-splines and plot generation

**Note:** All GAM fitting and plot rendering logic should be in `server.R`

### Part 4A: GAM Fitting

- [ ] Create gam_fit reactive
  - Check: nrow(filtered_data()) >= 10
  - Model: response ~ s(years, bs = "bs", k = input$gam_k)
  - Family: gaussian()
  - Error handling: Return NULL if convergence fails

- [ ] Create gam_predictions reactive
  - Generate prediction grid: seq(0, 6, by = 0.05)
  - predict() on gam_fit
  - Return data.frame: years, fitted_values
  - Only compute if input$show_gam == TRUE

### Part 4B: Plot Generation

- [ ] Create base ggplot (NO scatter points)
  - Empty ggplot with age × response axes
  - Set x-limits: 0-6 years
  - Set y-limits: Based on observed response range
  - theme_minimal(base_size = 14)

- [ ] Add GAM smooth line (if enabled)
  - geom_line() with gam_predictions data
  - Color: "blue" or study-specific
  - Line width: 1.5
  - NO confidence bands

- [ ] Add box plots (if enabled)
  - geom_boxplot for each response category
  - Orientation: horizontal (y = response level)
  - Show age distribution at each response value
  - Width: 0.3, alpha: 0.5

- [ ] Implement study coloring
  - If input$color_by_study: Color GAM lines by study
  - Fit separate GAMs per study
  - Use study_colors palette from global.R

- [ ] Add plot labels and title
  - Title: "Age Gradient: {item_name}"
  - X-axis: "Age (years)"
  - Y-axis: "Item Response"
  - Subtitle: Item description (truncated if long)

- [ ] Render plot output
  - output$age_gradient_plot <- renderPlot({ ... })
  - Handle edge cases (no data, GAM failure)

- [ ] Load Phase 5 tasks into Claude todo list
  - Use TodoWrite tool to add Phase 5 tasks
  - Mark Phase 4 as complete

---

## Phase 5: Codebook Display & Polish

**Objective:** Display codebook JSON and add final features

**Note:** JSON display rendering in `server.R`, UI output elements in `ui.R`

### Part 5A: Codebook JSON Display

- [ ] Create codebook_json_display reactive
  - Extract all fields for selected item from codebook
  - Convert to formatted JSON string
  - Use jsonlite::toJSON(pretty = TRUE)

- [ ] Render codebook JSON output
  - Option 1: verbatimTextOutput (plain text box)
  - Option 2: DT::renderDataTable (transposed key-value table)
  - Option 3: htmlOutput (formatted HTML)
  - Place below plot with clear section header

- [ ] Add collapsible section for JSON
  - Use shiny::conditionalPanel or bslib::accordion
  - Label: "Show Codebook Metadata"
  - Default: Collapsed

### Part 5B: Quality Flag Integration

- [ ] Render item description output
  - output$item_description
  - Source: item_metadata()$description
  - Display above plot

- [ ] Render quality flag warning banner
  - Check: nrow(item_flags()) > 0
  - Show flag details:
    - Flag type (CATEGORY_MISMATCH, NEGATIVE_CORRELATION, etc.)
    - Severity (ERROR, WARNING)
    - Description
  - Use HTML for styling (red for ERROR, yellow for WARNING)

- [ ] Format flag display
  - Multiple flags: Show all as bullet list
  - Include study name if flag is study-specific

### Part 5C: Performance & Error Handling

- [ ] Add loading indicators
  - Use shiny::withProgress for GAM fitting
  - Show spinner during plot rendering

- [ ] Implement error handling
  - GAM convergence failures: Show warning message
  - Insufficient data (n < 10): Show informative message
  - No studies selected: Show "Select at least one study"

- [ ] Add debouncing
  - Debounce GAM smoothness slider (500ms)
  - Avoid re-fitting GAM on every slider drag

- [ ] Test performance
  - Verify plot renders quickly (< 1 second)
  - Test with all 308 items
  - Test with different study combinations

- [ ] Load Phase 6 tasks into Claude todo list
  - Use TodoWrite tool to add Phase 6 tasks
  - Mark Phase 5 as complete

---

## Phase 6: Testing & Documentation

**Objective:** Test all features and document usage

### Part 6A: Functional Testing

- [ ] Test positive gradient items
  - Select PS items (parenting stress)
  - Verify GAM shows positive slope
  - Check correlation value is positive

- [ ] Test negative gradient items
  - Select AA7, AA15 (flagged items)
  - Verify GAM shows negative slope
  - Check correlation value is negative

- [ ] Test box plot overlay
  - Enable box plots
  - Verify age distributions shown at each response level
  - Check overlap between categories

- [ ] Test study filtering
  - Select single study (e.g., NE25 only)
  - Select multiple studies
  - Use "Select All" / "Deselect All"
  - Verify plot updates correctly

- [ ] Test GAM smoothness slider
  - Set k=3 (undersmoothed)
  - Set k=10 (oversmoothed)
  - Verify GAM line changes appropriately

- [ ] Test quality flag display
  - Select CC85 (has CATEGORY_MISMATCH flag)
  - Verify warning banner appears
  - Check flag details displayed correctly

- [ ] Test codebook JSON display
  - Expand/collapse section
  - Verify all fields shown
  - Check JSON formatting is readable

### Part 6B: Edge Case Testing

- [ ] Test with sparse items
  - Select items with < 10 observations per study
  - Verify error message displayed
  - Ensure app doesn't crash

- [ ] Test with dichotomous items
  - Select items with only 0/1 responses
  - Verify GAM fits binary data
  - Check box plots show 2 levels

- [ ] Test with polytomous items
  - Select items with 0-5 responses
  - Verify box plots show all levels
  - Check GAM captures non-linear patterns

- [ ] Test with missing data
  - Select items with high missingness
  - Verify % missing statistic accurate
  - Check GAM uses available data only

### Part 6C: Documentation

- [ ] Write README.md
  - Purpose and overview
  - How to launch app
  - Description of controls
  - Interpretation guide (positive vs negative gradients)
  - Technical details (GAM with b-splines)

- [ ] Add inline help text
  - Tooltips for controls (use shinyBS::bsTooltip)
  - Help icon with app usage instructions

- [ ] Document code
  - Add comments to complex reactives
  - Document GAM formula and parameters
  - Explain data filtering logic

- [ ] Create example screenshots
  - Positive gradient example
  - Negative gradient example
  - Box plot overlay example
  - Include in README.md

- [ ] Archive this task list
  - Move to: todo/archive/age_gradient_shiny_app.md
  - Add completion date

---

## Notes

**File Structure:**

The app uses the traditional multi-file Shiny structure for better organization:

```
scripts/shiny/age_gradient_explorer/
├── app.R          # Launcher script (calls shiny::runApp())
├── ui.R           # UI definition (all UI components)
├── server.R       # Server logic (all reactives, observers, rendering)
├── global.R       # Global setup (data loading, runs once on startup)
└── README.md      # Usage documentation
```

**File Responsibilities:**

- **app.R**: Minimal launcher
  ```r
  shiny::runApp(launch.browser = TRUE)
  ```

- **global.R**: Runs once when app starts
  - Load calibration_dataset_2020_2025 from DuckDB
  - Load codebook.json
  - Load quality_flags.csv
  - Define study_colors palette
  - Create item metadata lookups

- **ui.R**: UI definition using `fluidPage()` or `navbarPage()`
  - sidebarPanel: Study filters, item selection, display options
  - mainPanel: Plot output, description, quality flags, JSON display
  - All `*Input()` and `*Output()` placeholders

- **server.R**: Server function `function(input, output, session)`
  - All reactive expressions
  - All observers (buttons, filters)
  - All render functions (renderPlot, renderText, etc.)

**Performance Optimizations:**
- NO scatter points (only GAM lines and optional box plots)
- NO confidence bands (simplifies rendering)
- Debounce slider inputs
- Cache calibration data on app startup

**GAM Configuration:**
- Basis: B-splines (`bs = "bs"`)
- Default k: 5 (user-adjustable 3-10)
- Family: Gaussian
- No confidence intervals

**Codebook JSON Display:**
All fields from codebook for selected item:
- id
- studies
- lexicons (equate, kidsight, ne25, etc.)
- content (description, response_options)
- psychometric (calibration_item, expected_categories)
- instruments
- Any other metadata fields

**Launch Commands:**

From project root:
```r
# Option 1: Using runApp()
shiny::runApp("scripts/shiny/age_gradient_explorer")

# Option 2: Using app.R directly
source("scripts/shiny/age_gradient_explorer/app.R")
```

From within the app directory:
```r
shiny::runApp()
```

**Key Questions:**
1. Should GAM lines be colored by study, or single aggregate line?
2. Box plot orientation: Horizontal boxes at each y-level?
3. Codebook display format: JSON text or formatted table?

**Dependencies:**
- Calibration dataset in DuckDB
- codebook.json
- quality_flags.csv (76 flags)

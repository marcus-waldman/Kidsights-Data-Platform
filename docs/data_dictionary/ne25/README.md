# NE25 Interactive Data Dictionary

This directory contains the comprehensive documentation system for the NE25 (Nebraska 2025) longitudinal childhood development study. The documentation is built using Quarto and provides interactive exploration of both raw REDCap variables and derived variables created through transformations.

## Documentation Architecture

The NE25 data dictionary follows a multi-layered documentation architecture:

```
REDCap Data → JSON Export → Quarto Processing → Interactive Web Documentation
      ↓            ↓              ↓                      ↓
  4 Projects   Metadata     R Functions           6 HTML Pages
  1,880 vars   Structure   Templating            Tree Navigation
  3,906 recs   1.17 MB     Dynamic Tables       Search & Filter
```

## Generated Documentation Files

### **Interactive HTML Pages**

| File | Purpose | Content |
|------|---------|---------|
| [`index.html`](index.html) | **Overview & Summary** | Dataset summary, freshness warnings, project descriptions |
| [`raw-variables.html`](raw-variables.html) | **Raw REDCap Variables** | 1,880 variables from 4 REDCap projects with field types, labels |
| [`transformed-variables.html`](transformed-variables.html) | **Derived Variables** | 21 variables created by recode_it() transformations |
| [`transformations.html`](transformations.html) | **Transformation Process** | Documentation of how derived variables are created |
| [`matrix.html`](matrix.html) | **Variable Mapping Matrix** | Cross-project variable alignment and harmonization |

### **Data Sources**

| File | Purpose | Size | Content |
|------|---------|------|---------|
| `ne25_dictionary.json` | **Master Data Source** | 1.17 MB | Complete metadata for all variables, summaries, field types |
| `search.json` | **Search Index** | ~50 KB | Optimized search data for interactive filtering |

### **Configuration & Assets**

| File/Directory | Purpose | Content |
|----------------|---------|---------|
| `_quarto.yml` | **Site Configuration** | Quarto project settings, navigation, themes |
| `custom.css` | **Styling** | Custom CSS for enhanced visual presentation |
| `assets/` | **R Functions & Dependencies** | Dictionary functions, dependency management |
| `site_libs/` | **Generated Libraries** | Bootstrap, jQuery, and other web dependencies |

## Source Files (Quarto Markdown)

### **`index.qmd` - Overview Page**

**Purpose**: Main landing page with dataset summary and navigation.

**Key Features**:
- Dataset freshness warnings
- REDCap project descriptions
- Summary statistics (1,880 raw variables, 21 derived variables)
- Navigation guidance

**R Functions Used**:
```r
# Load and initialize JSON data
dict_data <- initialize_dictionary()

# Display data freshness
display_freshness_warning(dict_data)

# Get summary statistics
raw_vars_data <- get_raw_variables_data(dict_data)
transformed_vars_data <- get_transformed_variables_data(dict_data)
```

### **`raw-variables.qmd` - Raw Variables Documentation**

**Purpose**: Comprehensive table of all 1,880 raw variables from REDCap projects.

**Features**:
- **Interactive DataTable**: Searchable, sortable, paginated
- **Multi-project View**: Variables from all 4 REDCap projects
- **Field Type Filtering**: Radio, checkbox, text, calc, descriptive
- **Label Display**: Full field labels and descriptions
- **PID Identification**: Shows which project each variable belongs to

**Table Columns**:
- `field_name`: Variable name in database
- `field_label`: Human-readable description
- `field_type`: REDCap field type (radio, checkbox, etc.)
- `pid`: REDCap project ID
- `form_name`: REDCap form/instrument name

**R Implementation**:
```r
# Load raw variables
raw_vars_data <- get_raw_variables_data(dict_data)

# Create interactive DataTable
DT::datatable(
  raw_vars_data,
  filter = "top",
  options = list(
    pageLength = 25,
    scrollX = TRUE,
    dom = 'Bfrtip'
  )
)
```

### **`transformed-variables.qmd` - Derived Variables Documentation**

**Purpose**: Detailed documentation of the 21 derived variables created by recode_it() transformations.

**Enhanced Factor Metadata Display**:
- **Comprehensive Factor Analysis**: Levels, labels, value counts, reference levels
- **Missing Data Analysis**: Counts, percentages, handling strategies
- **Value Distribution**: Frequency tables and percentage breakdowns
- **Transformation Notes**: How each variable was created

**Variable Categories Documented**:

#### **Inclusion & Eligibility (3 variables)**
- `eligible`, `authentic`, `include`
- Logical variables based on 9 CID criteria
- Shows pass/fail rates for study inclusion

#### **Race & Ethnicity (6 variables)**
- Child: `hisp`, `race`, `raceG`
- Caregiver: `a1_hisp`, `a1_race`, `a1_raceG`
- Collapsed race categories, combined race/ethnicity variables
- Reference levels set for statistical analysis

#### **Education (12 variables)**
- 8-category: `educ_max`, `educ_a1`, `educ_a2`, `educ_mom`
- 4-category: `educ4_max`, `educ4_a1`, `educ4_a2`, `educ4_mom`
- 6-category: `educ6_max`, `educ6_a1`, `educ6_a2`, `educ6_mom`
- Multiple category structures for different analysis needs

**Factor Metadata Format**:
```r
# Example factor variable display
Variable: raceG (Child race/ethnicity combined)
├── Data Type: factor
├── Storage: character
├── Missing: 0 (0.0%)
├── Unique Values: 5
├── Reference Level: "White, non-Hisp."
├── Factor Levels: [5]
│   ├── "White, non-Hisp." (n=2,156, 55.2%)
│   ├── "Hispanic" (n=892, 22.8%)
│   ├── "Black, non-Hisp." (n=423, 10.8%)
│   ├── "Multiracial, non-Hisp." (n=248, 6.4%)
│   └── "Other, non-Hisp." (n=187, 4.8%)
└── Transformation: "Created by recode_it() race transformation"
```

### **`transformations.qmd` - Transformation Process Documentation**

**Purpose**: Explains how raw REDCap variables are transformed into analysis-ready derived variables.

**Content Sections**:
1. **Transformation Overview**: The recode_it() system architecture
2. **Category-by-Category Documentation**: Each of the 7 transformation categories
3. **Code Examples**: Actual R code used for transformations
4. **Quality Checks**: Validation and error handling procedures

**Transformation Categories Explained**:

#### **Include (Eligibility)**
```r
# Example transformation code
eligible = (eligibility == "Pass")
authentic = (authenticity == "Pass")
include = (eligible & authentic)
```

#### **Race/Ethnicity**
```r
# Complex pivoting and collapsing logic
race = ifelse(n() > 1, "Two or More", label[1])
raceG = ifelse(hisp == "Hispanic", "Hispanic", paste0(race, ", non-Hisp."))
```

#### **Education**
```r
# Multiple category mappings
educ4_max = plyr::mapvalues(as.character(educ_max),
                           from = simple_educ_label$educ,
                           to = simple_educ_label$educ4)
```

### **`matrix.qmd` - Variable Mapping Matrix**

**Purpose**: Shows how variables are harmonized and aligned across the 4 REDCap projects.

**Features**:
- **Cross-Project Alignment**: Which variables appear in which projects
- **Harmonization Status**: Successfully aligned vs. project-specific variables
- **Field Type Consistency**: Ensures consistent data types across projects
- **Missing Coverage**: Identifies variables not collected in all projects

**Matrix Display**:
```
Variable Name    | PID 7679 | PID 7943 | PID 7999 | PID 8014 | Harmonized
record_id        |    ✓     |    ✓     |    ✓     |    ✓     |     ✓
cqr001          |    ✓     |    ✗     |    ✓     |    ✓     |     ✗
age_in_days     |    ✓     |    ✓     |    ✓     |    ✓     |     ✓
```

## JSON Data Structure

### **`ne25_dictionary.json` Schema**

The master JSON file contains comprehensive metadata organized in a hierarchical structure:

```json
{
  "metadata": {
    "generated": "2025-09-17 16:55:47",
    "study": "ne25",
    "version": "2.0.0",
    "total_raw_variables": 1880,
    "total_transformed_variables": 21,
    "unique_raw_variables": 472
  },
  "summaries": {
    "raw_variable_types": {
      "data": [
        {"field_type": "radio", "count": 392, "percentage": 83.1},
        {"field_type": "calc", "count": 21, "percentage": 4.4}
      ]
    },
    "project_coverage": {
      "data": [
        {"pid": 7679, "variable_count": 561, "percentage": 29.8},
        {"pid": 7943, "variable_count": 423, "percentage": 22.5}
      ]
    }
  },
  "raw_variables": [
    {
      "field_name": "record_id",
      "field_label": "Record ID",
      "field_type": "text",
      "pid": 7679,
      "form_name": "demographics"
    }
  ],
  "transformed_variables": [
    {
      "variable_name": "eligible",
      "variable_label": "Meets study inclusion criteria",
      "category": "eligibility",
      "data_type": "logical",
      "factor_levels": ["FALSE", "TRUE"],
      "value_counts": {"FALSE": 234, "TRUE": 3672},
      "transformation_notes": "Created by recode_it()"
    }
  ]
}
```

### **Key JSON Sections**

#### **Metadata Section**
- Generation timestamp and version info
- Summary statistics (variable counts, projects)
- Data freshness indicators

#### **Summaries Section**
- Raw variable type distribution
- Project coverage analysis
- Transformation category breakdown

#### **Raw Variables Array**
- Complete list of 1,880 raw variables
- Field metadata from REDCap data dictionary
- Project assignment and form organization

#### **Transformed Variables Array**
- Detailed metadata for 21 derived variables
- Factor levels, value counts, reference levels
- Transformation provenance and notes

## R Function Library

### **`assets/dictionary_functions.R`**

Core R functions that power the interactive documentation:

#### **Data Loading Functions**
```r
# Initialize JSON data
initialize_dictionary <- function(json_file = "ne25_dictionary.json")

# Extract raw variables data
get_raw_variables_data <- function(dict_data)

# Extract transformed variables data
get_transformed_variables_data <- function(dict_data)
```

#### **Display Functions**
```r
# Create enhanced factor variable display
display_enhanced_factor_metadata <- function(var_data)

# Format value counts and percentages
format_value_counts <- function(value_counts, n_total)

# Display data freshness warnings
display_freshness_warning <- function(dict_data)
```

#### **Utility Functions**
```r
# Safe data extraction with error handling
safe_extract <- function(data, key, default = NULL)

# Format large numbers with commas
format_number <- function(x)

# Calculate percentages with proper rounding
calc_percentage <- function(count, total)
```

### **`assets/ensure_dependencies.R`**

Dependency management system that ensures all required R packages are available:

```r
# Required packages for documentation
required_packages <- c(
  "dplyr",      # Data manipulation
  "DT",         # Interactive tables
  "knitr",      # Document generation
  "jsonlite",   # JSON processing
  "htmltools"   # HTML generation
)

# Install missing packages
missing_packages <- setdiff(required_packages, installed.packages()[,"Package"])
if(length(missing_packages) > 0) {
  install.packages(missing_packages, dependencies = TRUE)
}
```

## Interactive Features

### **DataTables Integration**

All variable tables use the DT package for rich interactivity:

```r
DT::datatable(
  data,
  filter = "top",           # Column-wise filtering
  extensions = 'Buttons',   # Export functionality
  options = list(
    pageLength = 25,        # Pagination
    scrollX = TRUE,         # Horizontal scrolling
    dom = 'Bfrtip',         # Button placement
    buttons = c('copy', 'csv', 'excel', 'pdf')  # Export options
  )
)
```

**User Features**:
- **Search**: Global search across all columns
- **Filter**: Column-specific filtering with dropdowns
- **Sort**: Click column headers to sort
- **Export**: Copy, CSV, Excel, PDF export options
- **Pagination**: Navigate through large datasets

### **Enhanced Factor Display**

For categorical variables, the documentation provides rich factor metadata:

```r
# Factor variable display format
display_enhanced_factor_metadata <- function(var_data) {
  if (var_data$data_type == "factor") {
    # Parse factor levels
    levels <- fromJSON(var_data$factor_levels)
    counts <- fromJSON(var_data$value_counts)

    # Create hierarchical display
    cat("├── Factor Levels: [", length(levels), "]\n")
    for (level in levels) {
      count <- counts[[level]]
      pct <- round(100 * count / var_data$n_total, 1)
      cat("│   ├── \"", level, "\" (n=", format_number(count), ", ", pct, "%)\n")
    }
  }
}
```

## Documentation Generation Process

### **Automated Pipeline**

The documentation is generated through an automated pipeline:

```bash
# 1. Python exports metadata to JSON
python pipelines/python/generate_metadata.py --output-format json

# 2. R processes JSON into Quarto-ready data
Rscript -e "source('assets/dictionary_functions.R'); initialize_dictionary()"

# 3. Quarto renders interactive HTML
quarto render index.qmd
quarto render raw-variables.qmd
quarto render transformed-variables.qmd
```

### **Data Flow**

```
DuckDB Tables → Python Analysis → JSON Export → R Processing → Quarto Rendering → HTML Output
      ↓              ↓              ↓            ↓                ↓               ↓
  Raw data     Metadata calc    Structured   Template         Web docs        User access
  Derived vars  Factor analysis    data      application      Interactive      Navigation
```

### **Update Frequency**

- **Manual Updates**: When pipeline runs or transformations change
- **Automatic Refresh**: Data freshness warnings after 7 days
- **Version Control**: JSON files tracked in git for change history

## Customization and Theming

### **Visual Styling (`custom.css`)**

Custom CSS provides enhanced visual presentation:

```css
/* Enhanced table styling */
.dataTables_wrapper {
  margin-top: 20px;
}

/* Factor display formatting */
.factor-metadata {
  font-family: monospace;
  background-color: #f8f9fa;
  padding: 10px;
  margin: 10px 0;
}

/* Warning messages */
.freshness-warning {
  background-color: #fff3cd;
  border: 1px solid #ffeaa7;
  border-radius: 4px;
  padding: 10px;
  margin: 15px 0;
}
```

### **Quarto Configuration (`_quarto.yml`)**

Site-wide configuration for consistent presentation:

```yaml
project:
  type: website
  output-dir: docs

website:
  title: "NE25 Data Dictionary"
  navbar:
    left:
      - text: "Overview"
        href: index.html
      - text: "Raw Variables"
        href: raw-variables.html
      - text: "Derived Variables"
        href: transformed-variables.html

format:
  html:
    theme: cosmo
    css: custom.css
    toc: true
    number-sections: true
```

## Usage Instructions

### **For Data Users**

1. **Start with Overview**: [`index.html`](index.html) provides dataset summary and navigation
2. **Explore Raw Variables**: [`raw-variables.html`](raw-variables.html) for comprehensive variable catalog
3. **Understand Derived Variables**: [`transformed-variables.html`](transformed-variables.html) for analysis-ready variables
4. **Learn Transformations**: [`transformations.html`](transformations.html) for methodology

### **For Developers**

1. **Understand JSON Structure**: Review `ne25_dictionary.json` schema
2. **Examine R Functions**: Study `assets/dictionary_functions.R`
3. **Modify Templates**: Edit `.qmd` files for content changes
4. **Update Styling**: Modify `custom.css` for visual changes

### **For Data Managers**

1. **Check Data Freshness**: Monitor warnings on overview page
2. **Validate Transformations**: Review derived variables documentation
3. **Update Documentation**: Re-run generation pipeline after data changes
4. **Version Control**: Track changes through git commits

## Troubleshooting

### **Common Issues**

#### **Missing or Outdated JSON Data**
```bash
# Regenerate JSON from current database
python pipelines/python/generate_metadata.py --output-format json --output-file docs/data_dictionary/ne25/ne25_dictionary.json
```

#### **R Package Dependency Errors**
```r
# Install missing packages
source("assets/ensure_dependencies.R")

# Or manually install
install.packages(c("dplyr", "DT", "knitr", "jsonlite"))
```

#### **Quarto Rendering Failures**
```bash
# Check Quarto installation
quarto --version

# Render specific page for debugging
quarto render index.qmd

# Clear cache and re-render
quarto render --clean
```

#### **Factor Display Issues**
```r
# Debug factor metadata
dict_data <- initialize_dictionary()
transformed_vars <- get_transformed_variables_data(dict_data)

# Check specific variable
var_data <- transformed_vars[transformed_vars$variable_name == "raceG", ]
display_enhanced_factor_metadata(var_data)
```

### **Performance Optimization**

#### **Large Dataset Handling**
- Use `pageLength` option in DataTables for pagination
- Enable server-side processing for datasets >10k rows
- Optimize JSON file size by removing unnecessary fields

#### **Rendering Speed**
- Use `cache: true` in Quarto YAML headers
- Pre-process complex calculations in R functions
- Minimize real-time data loading in templates

## Development Guidelines

### **Adding New Documentation Pages**

1. **Create Quarto Markdown file**: `new-page.qmd`
2. **Add to navigation**: Update `_quarto.yml`
3. **Source required functions**: Add to `assets/dictionary_functions.R` if needed
4. **Test rendering**: `quarto render new-page.qmd`

### **Extending JSON Schema**

1. **Modify Python generation**: Update `generate_metadata.py`
2. **Update R functions**: Modify loading/display functions
3. **Test compatibility**: Ensure existing pages still work
4. **Document changes**: Update this README

### **Custom Styling**

1. **Add CSS rules**: Modify `custom.css`
2. **Test responsiveness**: Check mobile/tablet views
3. **Maintain accessibility**: Ensure WCAG compliance
4. **Cross-browser testing**: Verify compatibility

## Related Documentation

- **Transformation System**: `R/transform/README.md`
- **Python Metadata Generation**: `pipelines/python/README.md`
- **Configuration Management**: `config/README.md`
- **Database Operations**: `python/db/README.md`
- **Project Overview**: `CLAUDE.md` (Derived Variables section)

---

*Last Updated: September 17, 2025*
*Version: 2.1.0 - Interactive Documentation System*
*For technical support, see main project documentation in `README.md`*
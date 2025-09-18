# Documentation Generation Scripts

This directory contains Python scripts for automated generation of HTML documentation from the NE25 pipeline data.

## Architecture Overview

The documentation generation system creates interactive HTML documentation from JSON metadata exported by the NE25 pipeline:

```
NE25 Pipeline → JSON Export → Python Processing → Quarto Rendering → HTML Output
     ↓              ↓              ↓                  ↓               ↓
DuckDB Tables → JSON files → Data processing → QMD compilation → Web-ready docs
(metadata)    (machine)     (formatting)      (styling)        (interactive)
```

## Core Scripts

### `generate_interactive_dictionary_json.py`

**Purpose**: Converts NE25 database metadata into structured JSON files for Quarto documentation.

**Usage**:
```bash
python scripts/documentation/generate_interactive_dictionary_json.py
```

**Features**:
- **Database Connection**: Reads directly from `data/duckdb/kidsights_local.duckdb`
- **Multi-table Processing**: Processes ne25_data_dictionary and ne25_metadata tables
- **JSON Export**: Creates structured JSON files for Quarto rendering
- **Error Handling**: Graceful handling of missing tables or empty data

**Output Files**:
- `docs/data_dictionary/ne25/ne25_dictionary.json` - Complete data dictionary (1,880+ variables)
- `docs/data_dictionary/ne25/ne25_metadata.json` - Enhanced metadata with statistics
- Processing logs with record counts and execution time

### `generate_html_documentation.py`

**Purpose**: Automated end-to-end HTML documentation generation workflow.

**Usage**:
```bash
python scripts/documentation/generate_html_documentation.py
```

**Workflow Steps**:
1. **JSON Generation**: Calls `generate_interactive_dictionary_json.py`
2. **Quarto Rendering**: Renders all QMD files in `docs/data_dictionary/ne25/`
3. **Validation**: Checks output file sizes and content
4. **Error Recovery**: Detailed logging for troubleshooting

**Generated Documentation**:
- `index.html` - Main data dictionary landing page
- `transformed-variables.html` - Derived variables documentation
- `raw-variables.html` - Original REDCap field documentation
- `data-sources.html` - Project and source information
- `variable-categories.html` - Categorized variable listings
- `summary-statistics.html` - Statistical summaries and distributions

## Integration with NE25 Pipeline

### Automatic Generation
The documentation scripts are designed to be called after successful NE25 pipeline execution:

```r
# In pipelines/orchestration/ne25_pipeline.R (future enhancement)
system("python scripts/documentation/generate_html_documentation.py")
```

### Manual Generation
For on-demand documentation updates:

```bash
# Generate JSON from current database
python scripts/documentation/generate_interactive_dictionary_json.py

# Generate complete HTML documentation
python scripts/documentation/generate_html_documentation.py
```

## Database Requirements

### Required Tables
- **ne25_data_dictionary**: REDCap field definitions with project references
- **ne25_metadata**: Enhanced variable metadata with statistics and categories

### Expected Schema
```sql
-- ne25_data_dictionary
field_name, form_name, section_header, field_type, field_label,
select_choices_or_calculations, field_note, text_validation_type_or_show_slider_number,
text_validation_min, text_validation_max, identifier, branching_logic, required_field,
custom_alignment, question_number, matrix_group_name, matrix_ranking, field_annotation, pid

-- ne25_metadata
variable_name, variable_label, category, data_type, storage_mode, n_total, n_missing,
missing_percentage, unique_values, factor_levels, value_labels, value_counts,
reference_level, ordered_factor, factor_type, transformation_notes
```

## Output Structure

### Documentation Hierarchy
```
docs/data_dictionary/ne25/
├── index.html                    # Main landing page
├── transformed-variables.html    # 21 derived variables
├── raw-variables.html           # 1,880+ REDCap fields
├── data-sources.html            # Project information
├── variable-categories.html     # Category-based listings
├── summary-statistics.html      # Statistical summaries
├── ne25_dictionary.json         # Machine-readable data
└── ne25_metadata.json          # Enhanced metadata
```

### Interactive Features
- **Searchable Tables**: Filter variables by name, category, or data type
- **Sortable Columns**: Click headers to sort by different attributes
- **Expandable Sections**: Detailed variable information on demand
- **Cross-References**: Links between related variables and categories
- **Responsive Design**: Mobile-friendly layout with Bootstrap styling

## Configuration

### Database Configuration
- **Database Path**: `data/duckdb/kidsights_local.duckdb`
- **Connection Timeout**: 300 seconds
- **Retry Logic**: 3 attempts with exponential backoff

### Quarto Configuration
- **Execution Engine**: R with Python integration
- **Output Format**: HTML with Bootstrap theme
- **Styling**: Custom CSS in `docs/data_dictionary/ne25/_quarto.yml`
- **Navigation**: Automatic sidebar generation

## Error Handling

### Common Issues
1. **Database Connection Failures**
   - Check DuckDB file exists at expected path
   - Verify file permissions and accessibility
   - Ensure no other processes have exclusive locks

2. **Empty Tables**
   - Run NE25 pipeline to populate data: `source("run_ne25_pipeline.R")`
   - Verify pipeline completed without errors
   - Check table record counts in database

3. **Quarto Rendering Errors**
   - Verify R and required packages are installed
   - Check that JSON files were generated successfully
   - Review Quarto error logs for specific issues

### Debugging Commands
```bash
# Test database connection
python -c "import duckdb; conn = duckdb.connect('data/duckdb/kidsights_local.duckdb'); print('Tables:', [t[0] for t in conn.execute('SHOW TABLES').fetchall()])"

# Check table counts
python -c "import duckdb; conn = duckdb.connect('data/duckdb/kidsights_local.duckdb'); print('Dictionary:', conn.execute('SELECT COUNT(*) FROM ne25_data_dictionary').fetchone()[0]); print('Metadata:', conn.execute('SELECT COUNT(*) FROM ne25_metadata').fetchone()[0])"

# Test JSON generation only
python scripts/documentation/generate_interactive_dictionary_json.py

# Test Quarto rendering manually
cd docs/data_dictionary/ne25
"C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe" render index.qmd
```

## Performance Characteristics

### Processing Times
- **JSON Generation**: ~2-5 seconds for 1,880 variables
- **Quarto Rendering**: ~10-15 seconds for 6 HTML files
- **Total Documentation**: <30 seconds end-to-end

### Output Sizes
- **JSON Files**: ~1.2 MB combined
- **HTML Files**: ~2-4 MB total with embedded CSS/JS
- **Images/Assets**: Minimal, relies on CDN resources

## Development Guidelines

### Adding New Documentation Pages
1. **Create QMD File**: Add new `.qmd` file in `docs/data_dictionary/ne25/`
2. **Update Navigation**: Modify `_quarto.yml` sidebar configuration
3. **Test Rendering**: Verify individual page renders correctly
4. **Update Automation**: Add to `generate_html_documentation.py` if needed

### Extending JSON Schema
1. **Modify Query**: Update SQL in `generate_interactive_dictionary_json.py`
2. **Test Data Flow**: Verify JSON structure and Quarto compatibility
3. **Update Documentation**: Reflect schema changes in QMD files
4. **Version Control**: Update this README with schema changes

### Custom Styling
- **CSS Location**: `docs/data_dictionary/ne25/custom.css`
- **Bootstrap Theme**: Configured in `_quarto.yml`
- **JavaScript**: Minimal, relies on Quarto built-in features

## Related Documentation

- **Pipeline Overview**: `README.md` (project root)
- **Python Database Operations**: `pipelines/python/README.md`
- **Quarto Configuration**: `docs/data_dictionary/ne25/_quarto.yml`
- **Database Schema**: `schemas/landing/ne25.sql`

---

*Last Updated: September 17, 2025*
*For questions or issues, check pipeline logs and database table contents first*
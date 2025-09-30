# Getting Started with the Kidsights Manual

## Quick Start

### 1. Install Quarto

Download and install Quarto from: https://quarto.org/docs/get-started/

Verify installation:
```bash
quarto --version
```

### 2. Navigate to Manual Directory

```bash
cd docs/manual
```

### 3. Render the Manual

**Preview while editing:**
```bash
quarto preview
```
This opens an auto-refreshing browser window.

**Render full book:**
```bash
quarto render
```
Output will be in `_book/` directory.

## What's Already Complete

### ✅ Foundations (Part I)
All three foundation chapters are complete:
- **Overview** (`chapters/foundations/overview.qmd`): System philosophy, transformation problem, quality assurance
- **Architecture** (`chapters/foundations/architecture.qmd`): Hybrid R-Python design, data flow, component details
- **Standards** (`chapters/foundations/standards.qmd`): Naming conventions, factor standards, coding standards

### ✅ Education Domain (Part II)
Complete model chapter demonstrating the documentation standard:
- **Education** (`chapters/domains/education.qmd`):
  - 12 derived variables fully documented
  - Source variables from REDCap
  - Transformation algorithms with flowcharts
  - Factor specifications (8/4/6-category systems)
  - Validation rules and test cases
  - Usage guidance and examples
  - ~6000 words of comprehensive documentation

### ✅ Contribution Guide (Part IV)
- **Contribution** (`chapters/implementation/contribution.qmd`):
  - New variable specification template
  - Quick start templates (binary, categorical, collapsed)
  - Submission workflow
  - Review checklist

### ✅ Machine-Readable Specifications
- **Education YAML** (`specs/yaml/education_variables.yaml`):
  - Complete specification for all 12 education variables
  - Category mapping tables
  - Validation rules and test cases
  - Implementation guidance
  - ~400 lines of structured YAML

## Reading Guide

### For Domain Experts
Start here to understand how to contribute specifications:
1. Read `index.qmd` (Welcome page)
2. Skim `chapters/foundations/overview.qmd` for philosophy
3. **Study `chapters/domains/education.qmd` in detail** as the model
4. Review `chapters/implementation/contribution.qmd` for how to contribute

### For Developers
Start here to understand implementation requirements:
1. Read `index.qmd` (Welcome page)
2. Read `chapters/foundations/architecture.qmd` for system design
3. Read `chapters/foundations/standards.qmd` for coding conventions
4. **Study `chapters/domains/education.qmd`** to see how specs map to code
5. Review `specs/yaml/education_variables.yaml` for machine-readable format

### For Data Analysts
Start here to understand variables available for analysis:
1. Read `index.qmd` (Welcome page)
2. Jump directly to `chapters/domains/education.qmd`
3. Focus on "Variable Specifications", "Factor Specifications", and "Common Analysis Patterns" sections

## Next Steps

### Immediate Next Steps

**1. Complete Remaining Domain Chapters** (Priority: High)

Use education chapter as template. For each domain:
- Extract transformation logic from `R/transform/ne25_transforms.R`
- Document source variables, algorithms, factor specifications
- Add validation rules and test cases
- Create corresponding YAML specification

**Domains to complete:**
- Eligibility (3 variables: eligible, authentic, include)
- Demographics (age, sex variables)
- Race & Ethnicity (6 variables: hisp, race, raceG + caregiver versions)
- Income (FPL calculations)
- Caregiver Relationships
- Geography

**2. Write Part III Chapters** (Priority: Medium)

Document cross-cutting transformation patterns:
- Common transformation patterns (checkbox pivoting, value collapsing, etc.)
- Factor variable construction guidelines
- Missing data handling conventions
- Cross-study harmonization rules

**3. Complete Part IV Implementation Chapters** (Priority: Medium)

- Development guide: How to implement transformations from specs
- Testing guide: Unit testing, integration testing, validation
- Documentation guide: Inline documentation, metadata generation

### Long-Term Vision

**Automated Tooling:**
1. **Spec validator:** Parse YAML specs and validate code compliance
2. **Code generator:** Generate R function templates from YAML specs
3. **Test generator:** Create test cases automatically from YAML
4. **Doc generator:** Auto-generate portions of manual from YAML

**Integration:**
1. **CI/CD:** Automatic manual rendering on git commits
2. **Version control:** Link manual versions to code releases
3. **Cross-referencing:** Hyperlinks from manual to code and vice versa

## Editing Tips

### Quarto Markdown Syntax

**Cross-references:**
```markdown
See @sec-education for details.
See @fig-diagram for the flowchart.
See @tbl-mapping for the mapping table.
```

**Code blocks:**
````markdown
```r
# R code here
educ_max <- factor(...)
```

```python
# Python code here
df.to_feather("output.feather")
```
````

**Mermaid diagrams:**
````markdown
```{mermaid}
flowchart TD
    A[Start] --> B[Process]
    B --> C[End]
```
````

**Callout blocks:**
```markdown
::: {.callout-note}
This is a note.
:::

::: {.callout-warning}
This is a warning.
:::

::: {.callout-tip}
This is a tip.
:::
```

### Chapter Structure

Follow this consistent structure for domain chapters (use education.qmd as reference):

1. **Overview** - Research importance, variables created
2. **Source Variables** - REDCap fields with details
3. **Transformation Logic** - Step-by-step algorithms
4. **Factor Specifications** - Levels, ordering, reference
5. **Metadata Specifications** - Labels and documentation
6. **Validation Rules** - Quality checks and test cases
7. **Common Analysis Patterns** - Usage examples
8. **Implementation Notes** - Technical details
9. **Change History** - Version tracking

## Common Issues

### Quarto Won't Render

**Problem:** `quarto: command not found`
**Solution:** Install Quarto or add to PATH

**Problem:** R code won't execute
**Solution:** Ensure R is installed and packages available

### Missing Cross-References

**Problem:** `@sec-xyz` shows as `??`
**Solution:** Ensure target section has `{#sec-xyz}` identifier

### Mermaid Diagrams Not Showing

**Problem:** Diagram doesn't render
**Solution:** Check syntax, ensure `{mermaid}` chunk option set

## Resources

### Documentation
- **Quarto Guide:** https://quarto.org/docs/guide/
- **Quarto Books:** https://quarto.org/docs/books/
- **Mermaid Syntax:** https://mermaid.js.org/

### Examples
- **Education chapter:** Complete model to follow
- **Education YAML:** Machine-readable spec example
- **Contribution template:** Structured template for new variables

### Support
- **Questions:** Contact technical lead
- **Issues:** Create GitHub issue
- **Suggestions:** Team meeting or email

## Contact

**Technical Lead:** [Contact information]
**Data Team:** [Contact information]

---

*Last Updated: 2025-09-30*
*Manual Version: 1.0.0*

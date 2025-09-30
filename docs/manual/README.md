# Kidsights Data Transformation & Metadata Manual

## Overview

This manual serves as the **authoritative specification** for data transformation and metadata management in the Kidsights Data Platform. It is a living document that bridges research requirements and technical implementation.

## Philosophy

**Specification-First Development:** This manual is written BEFORE code. Developers implement transformations according to specifications documented here. When discrepancies arise between manual and code, the manual is authoritative—code must be corrected.

## Structure

### Part I: Foundations
Core concepts, architecture, and standards that apply across all transformations.

- **Overview:** System philosophy and transformation problem
- **Architecture:** Technical design and component details
- **Standards:** Naming conventions and coding standards

### Part II: Variable Domains
Detailed specifications for each functional domain. Each chapter includes:
- Source variables (REDCap fields)
- Transformation logic (step-by-step algorithms)
- Factor specifications (levels, ordering, reference)
- Validation rules (quality checks, test cases)
- Usage guidance (common analyses)

**Completed:**
- ✅ **Education:** 12 variables with 8/4/6-category systems (comprehensive model)

**To Be Completed:**
- ⏳ Eligibility: 3 variables (eligible, authentic, include)
- ⏳ Demographics: Age and sex variables
- ⏳ Race & Ethnicity: 6 variables (child + caregiver)
- ⏳ Income: Federal poverty level calculations
- ⏳ Relationships: Caregiver relationship variables
- ⏳ Geography: Location variables

### Part III: Transformation Specifications
Technical patterns for cross-cutting concerns:
- Transformation patterns
- Factor variable handling
- Missing data conventions
- Cross-study harmonization

### Part IV: Implementation Guide
Guidelines for developers and contributors:
- Development standards
- Testing requirements
- Documentation guidelines
- **Contribution process** (templates and workflow)

## Building the Manual

### Prerequisites

- **Quarto** (version 1.3+): [Installation instructions](https://quarto.org/docs/get-started/)
- **R** (version 4.5.1+): For code examples and execution
- **R Packages:** dplyr, knitr, rmarkdown

### Rendering

**Full book:**
```bash
cd docs/manual
quarto render
```

**Single chapter:**
```bash
quarto render chapters/domains/education.qmd
```

**Preview while editing:**
```bash
quarto preview
```

**Output formats:**
- HTML: `_book/index.html` (default, interactive)
- PDF: `_book/manual.pdf` (requires LaTeX)

### Project Configuration

Configuration is in `_quarto.yml`:
- Book structure and chapter order
- Output formats (HTML, PDF)
- Theming and styling
- Code execution options

## Contributing

### Adding New Variable Specifications

1. **Use the template:** `chapters/implementation/contribution.qmd` provides complete templates
2. **Fill out specification:** Include research justification, transformation logic, validation
3. **Submit for review:** Via Git pull request or email to technical lead
4. **Iterate:** Address reviewer feedback
5. **Implementation:** Developers code to approved specification
6. **Validation:** Tests verify implementation matches specification

### Template Files

**Human-readable specification:**
- Location: `chapters/implementation/contribution.qmd`
- Format: Markdown with structured sections
- Purpose: Team review and approval

**Machine-readable specification:**
- Location: `specs/yaml/[domain]_variables.yaml`
- Format: YAML
- Purpose: Automated validation and code generation
- Example: `specs/yaml/education_variables.yaml`

### Workflow

```
1. Researcher identifies need
2. Fill out specification template
3. Domain expert reviews research justification
4. Technical lead reviews feasibility
5. Specification approved and merged into manual
6. Developer implements from specification
7. Automated tests validate implementation
8. Documentation auto-generated
9. Deploy to production pipeline
```

## Machine-Readable Specifications

The `specs/yaml/` directory contains structured YAML files that complement human documentation:

**Purpose:**
- Enable automated validation of implementations
- Support code generation from specifications
- Facilitate cross-referencing between manual and code
- Provide test case definitions

**Example:** `education_variables.yaml`
- Variable definitions with data types and labels
- Transformation algorithms in pseudocode
- Category mapping tables
- Validation rules and test cases
- Usage guidance and examples

**Integration:**
Future tooling will use these YAML files to:
- Generate R function templates
- Create automated test cases
- Validate code against specifications
- Produce documentation

## Current Status

### Completed Components

- ✅ Manual structure (Quarto book project)
- ✅ Foundations Part I (3 chapters)
- ✅ Education domain chapter (comprehensive model)
- ✅ Contribution templates and workflow
- ✅ Machine-readable YAML specification (education)
- ✅ README and setup instructions

### In Progress

- ⏳ Remaining domain chapters (6 domains)
- ⏳ Transformation specifications (Part III)
- ⏳ Implementation guide chapters (Part IV)

### Planned

- 📋 Automated validation tools
- 📋 Code generation from YAML specs
- 📋 Cross-referencing between manual and code
- 📋 Version tracking and change management

## File Organization

```
docs/manual/
├── _quarto.yml                    # Quarto book configuration
├── index.qmd                      # Welcome page
├── README.md                      # This file
├── chapters/                      # Manual chapters
│   ├── foundations/               # Part I
│   │   ├── overview.qmd          # ✅ System philosophy
│   │   ├── architecture.qmd      # ✅ Technical design
│   │   └── standards.qmd         # ✅ Naming conventions
│   ├── domains/                   # Part II
│   │   ├── education.qmd         # ✅ Education variables (model)
│   │   ├── eligibility.qmd       # ⏳ To be completed
│   │   ├── demographics.qmd      # ⏳ To be completed
│   │   ├── race-ethnicity.qmd    # ⏳ To be completed
│   │   ├── income.qmd            # ⏳ To be completed
│   │   ├── relationships.qmd     # ⏳ To be completed
│   │   └── geography.qmd         # ⏳ To be completed
│   ├── specifications/            # Part III
│   │   ├── patterns.qmd          # ⏳ To be completed
│   │   ├── factors.qmd           # ⏳ To be completed
│   │   ├── missing-data.qmd      # ⏳ To be completed
│   │   └── harmonization.qmd     # ⏳ To be completed
│   └── implementation/            # Part IV
│       ├── development.qmd       # ⏳ To be completed
│       ├── testing.qmd           # ⏳ To be completed
│       ├── documentation.qmd     # ⏳ To be completed
│       └── contribution.qmd      # ✅ Contribution guide
├── specs/                         # Machine-readable specs
│   └── yaml/
│       └── education_variables.yaml  # ✅ Education spec
└── _book/                         # Generated output (gitignored)
```

## Version Control

### Git Tracking

**Tracked (version controlled):**
- All `.qmd` source files
- `_quarto.yml` configuration
- YAML specification files
- This README

**Ignored (generated):**
- `_book/` directory (rendered output)
- `.quarto/` directory (Quarto cache)
- Temporary files

### Versioning

The manual follows semantic versioning:
- **Major (X.0.0):** Breaking changes to specifications
- **Minor (1.X.0):** New variable specifications added
- **Patch (1.0.X):** Corrections and clarifications

**Current Version:** 1.0.0

## Resources

### Documentation

- **Quarto Documentation:** https://quarto.org/docs/guide/
- **R Markdown Cookbook:** https://bookdown.org/yihui/rmarkdown-cookbook/
- **Mermaid Diagrams:** https://mermaid.js.org/ (for flowcharts)

### Templates

- Variable specification: `chapters/implementation/contribution.qmd`
- YAML specification: `specs/yaml/education_variables.yaml`

### Support

- **Questions:** Contact technical lead
- **Issues:** Create GitHub issue
- **Suggestions:** Email or team meeting

## Next Steps

### For Manual Development

1. **Complete remaining domain chapters:**
   - Use education.qmd as template
   - Extract logic from `R/transform/ne25_transforms.R`
   - Add YAML specifications for each domain

2. **Write Part III chapters:**
   - Document transformation patterns
   - Factor variable guidelines
   - Missing data conventions
   - Harmonization rules

3. **Complete Part IV chapters:**
   - Development guide with code examples
   - Testing requirements and examples
   - Documentation standards

### For Integration

1. **Develop validation tools:**
   - Parse YAML specifications
   - Compare code to specifications
   - Generate compliance reports

2. **Create code generators:**
   - R function templates from YAML
   - Test case generation
   - Documentation generation

3. **Setup CI/CD:**
   - Automatic rendering on commits
   - Specification validation
   - Cross-reference checking

---

**Maintainer:** Kidsights Data Team
**Last Updated:** 2025-09-30
**Version:** 1.0.0

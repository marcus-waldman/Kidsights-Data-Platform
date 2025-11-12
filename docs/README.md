# Kidsights Data Platform Documentation

Comprehensive documentation for the Kidsights Data Platform - a multi-source ETL system for childhood development research with four independent pipelines: **NE25** (REDCap surveys), **ACS** (census data), **NHIS** (health surveys), and **NSCH** (children's health).

## 🚀 Quick Start

**→ See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for command cheatsheet covering all 4 pipelines**

### Run NE25 Pipeline
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

### View Interactive Documentation
- **Codebook Dashboard**: `docs/codebook_dashboard/index.html`
- **Data Dictionary**: `docs/data_dictionary/ne25/index.html`
- **Documentation Index**: [INDEX.md](INDEX.md) - Complete guide navigation

## 📚 Essential Guides (October 2025)

### Architecture & Pipeline Documentation
- **[PIPELINE_OVERVIEW.md](architecture/PIPELINE_OVERVIEW.md)** - Comprehensive architecture for all 4 pipelines
- **[PIPELINE_STEPS.md](architecture/PIPELINE_STEPS.md)** - Step-by-step execution instructions
- **[DIRECTORY_STRUCTURE.md](DIRECTORY_STRUCTURE.md)** - Complete directory structure

### Critical Coding Standards
- **[CODING_STANDARDS.md](guides/CODING_STANDARDS.md)** - R namespacing, Windows console output, file naming
- **[MISSING_DATA_GUIDE.md](guides/MISSING_DATA_GUIDE.md)** - CRITICAL: Missing data handling for derived variables
- **[PYTHON_UTILITIES.md](guides/PYTHON_UTILITIES.md)** - R Executor, DatabaseManager utilities

### Data & Variables
- **[DERIVED_VARIABLES_SYSTEM.md](guides/DERIVED_VARIABLES_SYSTEM.md)** - 99 derived variables breakdown
- **[GEOGRAPHIC_CROSSWALKS.md](guides/GEOGRAPHIC_CROSSWALKS.md)** - 10 crosswalk tables, database-backed references

## Documentation Structure

### 📚 Core Documentation

- **[Architecture](architecture/)** - System design, hybrid R/Python architecture, all 4 pipelines
- **[Guides](guides/)** - Comprehensive guides for coding standards, missing data, utilities
- **[Pipeline](pipeline/)** - ETL workflow, data flow, and pipeline components
- **[API Documentation](api/)** - REDCap API integration and endpoints

### 📖 Data & Metadata

- **[Codebook](codebook/)** - JSON-based codebook system (305 items, 8 studies)
- **[Data Dictionary](data_dictionary/)** - Variable definitions, raw and derived variables
  - NE25 interactive site with comprehensive variable documentation

### 🔬 Pipeline-Specific Documentation

- **[ACS Pipeline](acs/)** - Census data extraction, metadata system, IPUMS variables
- **[NHIS Pipeline](nhis/)** - Health surveys data, ACEs, mental health measures
- **[NSCH Pipeline](nsch/)** - Children's health survey, database schema, queries
- **[Raking Targets](raking/)** - Population-representative targets, statistical methods, pipeline execution
- **[IRT Calibration](irt_scoring/)** - Mplus calibration pipeline, quality assurance tools, constraint specification

### 🛠️ Development & References

- **[User Guides](guides/)** - Step-by-step workflows and tutorials
- **[Python Components](python/)** - Python module documentation and usage examples
- **[System Fixes](fixes/)** - Bug fixes, patches, and system updates

### 📁 Archives

- **[Archive](archive/)** - Historical documentation and deprecated materials

## Additional Documentation

Root-level markdown files in `/docs`:
- `codebook_utilities.md` - R functions for querying codebook data
- `database_operations.md` - Database CRUD operation reference
- `ne25_eligibility_criteria.md` - 8 eligibility criteria (CID1-7 + completion)
- `installation_issues.md` - Troubleshooting R/Python setup

## Platform Capabilities

### NE25 Pipeline (Production Ready)
- **3,908 records** from 4 REDCap projects
- **99 derived variables** - eligibility, race/ethnicity, education, mental health, ACEs, childcare, geographic
- **100% pipeline reliability** with hybrid R/Python architecture
- **Local DuckDB storage** (47MB, 11 tables)

### ACS Pipeline (Complete)
- **Census data extraction** from IPUMS USA API
- **Metadata system** with 3 DuckDB tables for transformations
- **Smart caching** with 90+ day retention
- **Status:** Standalone utility, integrated with raking targets pipeline

### NHIS Pipeline (Production Ready)
- **229,609 records** across 6 annual samples (2019-2024)
- **66 variables** - demographics, ACEs, GAD-7, PHQ-8, economic indicators
- **Mental health focus** - anxiety and depression measures
- **National benchmarking** for NE25 comparisons

### NSCH Pipeline (Production Ready)
- **284,496 records** across 7 years (2017-2023)
- **3,780 unique variables** from SPSS files
- **Automated pipeline** - SPSS → Feather → R validation → Database
- **Performance:** Single year in 20 seconds, batch in 2 minutes

### Raking Targets Pipeline (Complete)
- **180 raking targets** (30 estimands × 6 age groups)
- **3 data sources** - ACS (25 estimands), NHIS (1 estimand), NSCH (4 estimands)
- **Database integration** - `raking_targets_ne25` table with 4 indexes
- **Execution:** ~2-3 minutes with automated verification

### Codebook System
- **305 items** across 8 studies (NE25, NE22, NE20, CAHMI22, CAHMI21, ECDI, CREDI, GSED)
- **IRT parameters** - NE22, CREDI (SF/LF), GSED (multi-calibration)
- **Interactive dashboard** - Browse items by domain, study, age range

## Documentation Standards

- **READMEs**: Every subdirectory has a README explaining its contents
- **Cross-references**: Documentation links to related files for easy navigation
- **Auto-generated**: Data dictionaries regenerate after each pipeline run
- **Version control**: Use git history instead of backup files
- **Comprehensive guides**: October 2025 reorganization created 9 essential guides (see above)

---

**For AI assistant instructions and quick reference, see [CLAUDE.md](../CLAUDE.md)**

**For complete documentation navigation, see [INDEX.md](INDEX.md)**

*Last Updated: October 2025 | Version 3.2.0*
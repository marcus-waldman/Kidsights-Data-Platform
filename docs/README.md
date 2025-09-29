# Kidsights Data Platform Documentation

Comprehensive documentation for the Kidsights Data Platform - a hybrid R/Python ETL system for childhood development research.

## Documentation Structure

### 📚 Core Documentation

- **[API Documentation](api/)** - REDCap API integration and endpoints
- **[Architecture](architecture/)** - System design and hybrid R/Python architecture
- **[Pipeline](pipeline/)** - ETL workflow, data flow, and pipeline components

### 📖 Data & Metadata

- **[Codebook](codebook/)** - JSON-based codebook system (306 items, 8 studies)
- **[Data Dictionary](data_dictionary/)** - Variable definitions, raw and derived variables
  - NE25 interactive site with comprehensive variable documentation

### 🛠️ Guides & References

- **[User Guides](guides/)** - Step-by-step workflows and tutorials
- **[Python Components](python/)** - Python module documentation and usage examples
- **[System Fixes](fixes/)** - Bug fixes, patches, and system updates

### 📁 Archives

- **[Archive](archive/)** - Historical documentation and deprecated materials

## Quick Start

### Run the Pipeline
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

### View Interactive Documentation
- **Codebook Dashboard**: `docs/codebook_dashboard/index.html`
- **Data Dictionary**: `docs/data_dictionary/ne25/index.html`

## Additional Documentation

Root-level markdown files in `/docs`:
- `codebook_utilities.md` - R functions for querying codebook data
- `database_operations.md` - Database CRUD operation reference
- `derived_variables.md` - 21 derived variables and transformation logic
- `installation_issues.md` - Troubleshooting R/Python setup
- `ne25_eligibility_criteria.md` - 8 eligibility criteria (CID1-7 + completion)

## Key Features

- **3,906 records** from 4 REDCap projects
- **306 items** across 8 studies (NE25, NE22, NE20, CAHMI22, CAHMI21, ECDI, CREDI, GSED_PF)
- **21 derived variables** for eligibility, race/ethnicity, education
- **100% pipeline reliability** with hybrid R/Python architecture
- **Local DuckDB storage** (47MB, 11 tables)

## Documentation Standards

- **READMEs**: Every subdirectory has a README explaining its contents
- **Cross-references**: Documentation links to related files for easy navigation
- **Auto-generated**: Data dictionaries regenerate after each pipeline run
- **Version control**: Use git history instead of backup files

---

For development guidelines and technical standards, see the main project `CLAUDE.md`.
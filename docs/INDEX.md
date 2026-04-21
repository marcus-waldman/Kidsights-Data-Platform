# Kidsights Documentation Index

Welcome to the Kidsights Data Platform documentation. This platform provides multi-source ETL for childhood development research with **eight independent pipelines**: NE25 & MN26 (REDCap surveys), ACS (census), NHIS (health surveys), NSCH (child health), Raking Targets (weighting), Imputation (uncertainty), and IRT Calibration (psychometrics).

## 🚀 Quick Start
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Command cheatsheet for all 8 pipelines ⭐
- **[CLAUDE.md](../CLAUDE.md)** - Most current platform reference (project root)

## 🏗️ Architecture & Design
- **[PIPELINE_OVERVIEW.md](architecture/PIPELINE_OVERVIEW.md)** - Comprehensive architecture for all 8 pipelines ⭐
- **[PIPELINE_STEPS.md](architecture/PIPELINE_STEPS.md)** - Step-by-step execution instructions ⭐
- **[DIRECTORY_STRUCTURE.md](DIRECTORY_STRUCTURE.md)** - Complete directory structure for all pipelines ⭐
- [Python Architecture Overview](python/architecture.md) - Current system architecture

## 💻 Coding & Development Standards
- **[CODING_STANDARDS.md](guides/CODING_STANDARDS.md)** - R namespacing, Windows console, file naming ⭐
- **[PYTHON_UTILITIES.md](guides/PYTHON_UTILITIES.md)** - R Executor, DatabaseManager, utilities ⭐
- [API Setup](api-setup.md) - REDCap API configuration
- [Installation Guide](setup/INSTALLATION_GUIDE.md) - Full machine setup
- [Environment Setup](setup/ENVIRONMENT_SETUP.md) - Environment variables and `.env` file

## 📊 Data, Variables & Missing Data
- **[MISSING_DATA_GUIDE.md](guides/MISSING_DATA_GUIDE.md)** - Critical missing data handling (REQUIRED) ⭐
- **[DERIVED_VARIABLES_SYSTEM.md](guides/DERIVED_VARIABLES_SYSTEM.md)** - 99 derived variables breakdown ⭐
- **[GEOGRAPHIC_CROSSWALKS.md](guides/GEOGRAPHIC_CROSSWALKS.md)** - 10 crosswalk tables, querying ⭐
- [Data Dictionary](data_dictionary/ne25/index.html) - Interactive variable explorer
- [Codebook API](codebook/codebook_api.md) - JSON-based item metadata system
- [Codebook System](codebook/README.md) - IRT parameters, utility functions

## 📚 Pipeline-Specific Documentation

### NE25 Pipeline (Nebraska 2025 REDCap Survey)
- See [CLAUDE.md - NE25 Pipeline](../CLAUDE.md#-ne25-pipeline---production-ready-december-2025) for current status
- [docs/raking/ne25/](raking/ne25/) - NE25 raking weights documentation

### MN26 Pipeline (Minnesota 2026 REDCap Survey)
- **[MN26 Pipeline Guide](mn26/pipeline_guide.qmd)** ⭐ — Single Quarto guide (render to HTML): Quick Start, data flow diagram, variable recoding reference, eligibility logic, scoring, troubleshooting

### ACS Pipeline (Census Data)
- [ACS Documentation](acs/) - IPUMS variables, pipeline usage, testing, cache management

### NHIS Pipeline (Health Surveys)
- [NHIS Documentation](nhis/) - Variables, pipeline usage, testing, transformations

### NSCH Pipeline (Children's Health)
- [NSCH Documentation](nsch/) - Database schema, queries, troubleshooting, variables

### Raking Targets Pipeline
- [Raking Documentation](raking/) - Targets pipeline, statistical methods

### Imputation Pipeline
- [Imputation Documentation](imputation/) - Multi-imputation architecture, helpers, examples

### IRT Calibration Pipeline
- [IRT Scoring Documentation](irt_scoring/) - Calibration pipeline, Mplus workflow, QA tools

## 🔍 Reference & Troubleshooting
- [Troubleshooting](troubleshooting.md) - Common issues and solutions

---

## 📜 Archived Documentation

> **Migration Notice**: In September 2025, the platform was migrated from R DuckDB to Python-based database operations due to segmentation faults.

- [Pre-Python Migration](archive/pre-python-migration/) - Historical R DuckDB documentation
- [Legacy Troubleshooting](archive/pre-python-migration/troubleshooting.md) - R DuckDB segmentation fault issues
- [Original Architecture](archive/pre-python-migration/pipeline-architecture.md) - Deprecated R DuckDB design
- [Migration Guide (archived)](archive/guides/migration-guide.md)
- [Manual (archived 2026-04)](archive/manual/) - Abandoned Quarto book draft

---

## 🏷️ Version History
- **v3.8** (April 2026) - Doc audit + cleanup; added MN26 + IRT Calibration; archived completed plans
- **v3.2** (October 2025) - Documentation reorganization and CLAUDE.md streamlining
- **v3.0** (October 2025) - Four-pipeline platform (NE25, ACS, NHIS, NSCH complete)
- **v2.0** (September 2025) - Python architecture migration
- **v1.0** - Original R DuckDB implementation

Last Updated: April 2026 (drift-checked and pruned of broken links 2026-04-20)

---

**Legend:** ⭐ = Authoritative reference docs

## Verification Summary

**Last fact-check:** 2026-04-20

- Pipeline count corrected: 4 → 8
- Removed 14 broken links to non-existent docs (`guides/quick-start.md`, `guides/migration-guide.md` (now in archive), `guides/development.md`, `guides/testing.md`, `guides/troubleshooting.md`, `pipeline/configuration.md`, `pipeline/overview.md`, `pipeline/schemas.md`, `pipeline/scripts.md`, `python/api-reference.md`, `python/error-handling.md`, `python/performance.md`, `examples/`, top-level `codebook_api.md`)
- Added entries for previously-undocumented pipelines: MN26, Raking Targets, Imputation, IRT Calibration
- Updated codebook API link to new location: `codebook/codebook_api.md` (moved in Bucket A doc cleanup)
- Updated archive section with newly-archived `guides/migration-guide.md` and `archive/manual/`
- Updated last-modified date to April 2026
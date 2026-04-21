# Architecture Documentation

This directory contains system architecture documentation for the Kidsights Data Platform.

## System Overview

**Hybrid R-Python Design** (introduced September 2025 to eliminate R DuckDB segfaults)

R handles statistical work (REDCap extraction, transformations, scoring, imputation models). Python handles all DuckDB operations (writes, schema, queries). The two sides exchange data via Apache Arrow Feather files for fast, type-preserving handoff.

## The Eight Pipelines

The platform now operates **eight independent pipelines**:

1. **NE25** — Nebraska 2025 REDCap survey (4 projects)
2. **MN26** — Minnesota 2026 REDCap survey (multi-child households, NORC-administered)
3. **ACS** — Census via IPUMS USA API
4. **NHIS** — National Health Interview Survey via IPUMS NHIS API
5. **NSCH** — National Survey of Children's Health (SPSS files)
6. **Raking Targets** — Population-representative weighting targets
7. **Imputation** — Multiple imputation across 29 variables (M=5)
8. **IRT Calibration** — Mplus calibration dataset for psychometric scale recalibration

For current per-pipeline status, record counts, and table inventories, see **[CLAUDE.md → Current Status](../../CLAUDE.md#current-status-april-2026)** — that's the single source of truth and is kept in sync with the live system.

## Key Design Decisions

### R/Python Division of Labor
- **R**: Orchestration, data extraction (REDCapR), harmonization, transformations (`recode_it`), IRT scoring, imputation models
- **Python**: All database operations (DuckDB connection, inserts, queries, schema management)

### Why This Split?
- **Problem (pre-Sept 2025):** R DuckDB package caused 50% pipeline failure rate with segmentation faults
- **Solution:** Python handles database I/O with robust error context
- **Result:** 100% pipeline reliability and 3x faster I/O

### Data Exchange Format
- **Apache Feather** — preserves R factors ↔ Python categories perfectly
- **Temp Directory** — `tempdir()/{pipeline}_pipeline/*.feather`

## Detailed Architecture Documentation

- **[PIPELINE_OVERVIEW.md](PIPELINE_OVERVIEW.md)** — Comprehensive architecture for all pipelines, design rationales, integration patterns, ACS metadata system
- **[PIPELINE_STEPS.md](PIPELINE_STEPS.md)** — Step-by-step execution instructions, timing expectations, troubleshooting

## Related Documentation

- `../python/architecture.md` — Python component details
- `../../CLAUDE.md` — Authoritative platform reference (run commands, current status, coding standards)

---

*Last Updated: April 2026 (rewritten during pre-handoff doc audit; original described only the NE25 pipeline)*

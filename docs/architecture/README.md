# Architecture Documentation

This directory contains system architecture documentation for the Kidsights Data Platform.

## System Overview

**Hybrid R-Python Design** (implemented September 2025)

```
REDCap (4 projects) → R: Extract/Transform → Feather Files → Python: Database Ops → Local DuckDB
     3,906 records      REDCapR, recode_it()      arrow format      Chunked processing     47MB local
```

## Key Design Decisions

### R/Python Division of Labor
- **R**: Orchestration, data extraction (REDCapR), harmonization, transformations (recode_it)
- **Python**: All database operations (DuckDB connection, inserts, queries)

### Why This Split?
- **Problem**: R DuckDB package caused 50% pipeline failure rate with segmentation faults
- **Solution**: Python handles database I/O with robust error context
- **Result**: 100% pipeline reliability, 3x faster I/O

### Data Exchange Format
- **Apache Feather**: Perfect R factor ↔ Python category preservation
- **Temp Directory**: `tempdir()/ne25_pipeline/*.feather`

## Detailed Architecture Documentation

- **[PIPELINE_OVERVIEW.md](PIPELINE_OVERVIEW.md)** - Comprehensive architecture for all 4 pipelines (NE25, ACS, NHIS, NSCH), design rationales, and integration patterns
- **[PIPELINE_STEPS.md](PIPELINE_STEPS.md)** - Step-by-step execution instructions, timing expectations, and troubleshooting

## Related Documentation

- `/docs/python/architecture.md` - Python component details
- Main `CLAUDE.md` - Quick reference guide and development standards
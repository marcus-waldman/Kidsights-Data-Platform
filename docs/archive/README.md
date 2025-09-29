# Archived Documentation

This directory contains historical documentation that has been superseded by the Python architecture migration in September 2025.

## Archive Structure

### `pre-python-migration/`
Documentation from before the Python architecture was implemented (September 2025):
- **pipeline-architecture.md** - Original R DuckDB pipeline architecture
- **troubleshooting.md** - R DuckDB troubleshooting guide (includes segmentation fault issues)
- **schema-documentation.md** - Original schema documentation with problematic views

### `r-duckdb-era/`
Documentation specific to the R DuckDB implementation that was deprecated due to segmentation faults.

## Migration Context

In September 2025, the Kidsights Data Platform was migrated from R DuckDB to a Python-based database architecture due to persistent segmentation faults in R's DuckDB package. While R continues to handle pipeline orchestration and REDCap extraction, all database operations are now performed via Python scripts.

## Current Documentation

For up-to-date documentation, see:
- [Python Architecture](../python/architecture.md)
- [Pipeline Overview](../pipeline/overview.md)
- [Quick Start Guide](../guides/quick-start.md)

## Historical Value

This archived documentation remains valuable for:
- Understanding the evolution of the system
- Troubleshooting legacy issues
- Providing context for architectural decisions
- Reference for systems that may still use R DuckDB
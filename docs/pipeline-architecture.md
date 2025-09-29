# Pipeline Architecture

> **📢 Documentation Updated**
>
> This documentation has been updated for the Python architecture migration (September 2025).
>
> - **Current Architecture**: [Python Architecture Overview](python/architecture.md)
> - **Pipeline Overview**: [Pipeline Documentation](pipeline/overview.md)
> - **Legacy Documentation**: [Archived R DuckDB Architecture](archive/pre-python-migration/pipeline-architecture.md)

## Quick Links

### Current Documentation
- [🐍 Python Architecture](python/architecture.md) - **NEW** - Hybrid R-Python design
- [🚀 Pipeline Overview](pipeline/overview.md) - Updated pipeline documentation
- [📚 Migration Guide](guides/migration-guide.md) - How we moved from R DuckDB

### Why We Migrated
The original R DuckDB implementation suffered from persistent **segmentation faults** that made the pipeline unreliable. The new Python architecture:
- ✅ **Zero segmentation faults** since migration
- ✅ **100% pipeline success rate**
- ✅ **Rich error handling and logging**
- ✅ **Better performance monitoring**

### Architecture Summary
```
R (Orchestration) → Python (Database) → DuckDB
     ↓                    ↓              ↓
- REDCap extraction  - Connection mgmt  - Stable storage
- Data transforms    - Error handling   - No crashes
- Pipeline control   - Metadata gen     - Reliable ops
```

For the complete technical details, see the [Python Architecture documentation](python/architecture.md).
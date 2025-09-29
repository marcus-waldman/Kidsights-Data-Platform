# Kidsights Documentation Index

Welcome to the Kidsights Data Platform documentation. This platform provides automated data extraction, validation, and storage for the Nebraska 2025 (NE25) childhood development study.

## 🚀 Quick Start
- [Getting Started Guide](guides/quick-start.md) - Set up and run your first pipeline
- [Migration from R DuckDB](guides/migration-guide.md) - Upgrade from legacy implementation

## 🏗️ Architecture
- [Python Architecture Overview](python/architecture.md) - **NEW** - Current system architecture
- [Pipeline Overview](pipeline/overview.md) - End-to-end pipeline documentation
- [Configuration Guide](pipeline/configuration.md) - YAML and environment setup

## 🐍 Python Components
- [API Reference](python/api-reference.md) - Complete Python module documentation
- [Error Handling](python/error-handling.md) - Robust error handling patterns
- [Performance Guide](python/performance.md) - Optimization and monitoring

## 📊 Data & Schema
- [Data Dictionary](data_dictionary/ne25/index.html) - Interactive variable explorer
- [Codebook API](codebook_api.md) - JSON-based item metadata system
- [Schema Reference](pipeline/schemas.md) - Database structure

## 🔧 Development
- [Development Guide](guides/development.md) - Contributing and extending the platform
- [API Setup](api-setup.md) - REDCap API configuration
- [Testing Guide](guides/testing.md) - Testing procedures

## 📚 Reference
- [Troubleshooting](guides/troubleshooting.md) - Common issues and solutions
- [Pipeline Scripts](pipeline/scripts.md) - Individual script documentation
- [Examples](examples/) - Code examples and templates

---

## 📜 Archived Documentation

> **Migration Notice**: In September 2025, the platform was migrated from R DuckDB to Python-based database operations due to segmentation faults.

- [Pre-Python Migration](archive/pre-python-migration/) - Historical R DuckDB documentation
- [Legacy Troubleshooting](archive/pre-python-migration/troubleshooting.md) - R DuckDB segmentation fault issues
- [Original Architecture](archive/pre-python-migration/pipeline-architecture.md) - Deprecated R DuckDB design

---

## 🏷️ Version History
- **v2.0** (September 2025) - Python architecture migration
- **v1.0** - Original R DuckDB implementation

Last Updated: September 2025
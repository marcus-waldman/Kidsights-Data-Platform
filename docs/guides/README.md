# Kidsights Platform Guides

This directory contains comprehensive guides for the Kidsights Data Platform. Guides are organized by category: **Coding Standards**, **Data & Variables**, and **Operations & Utilities**.

---

## 💻 Coding & Development Standards

### [CODING_STANDARDS.md](CODING_STANDARDS.md)
**Essential coding requirements for all R and Python code**

- **R Namespacing (REQUIRED):** All R functions must use explicit package prefixes (`dplyr::`, `tidyr::`, `arrow::`)
- **Windows Console Output:** Python must use ASCII characters only (no Unicode symbols)
- **R Execution Guidelines:** Never use inline `-e` commands (causes segfaults)
- **File Naming Conventions:** snake_case.R, kebab-case.yaml, UPPER_CASE.md

**When to use:** Before writing any R or Python code. Critical for avoiding namespace conflicts and Windows compatibility issues.

---

### [PYTHON_UTILITIES.md](PYTHON_UTILITIES.md)
**Python utilities for R execution, database operations, and data management**

- **R Executor:** `execute_r_script()` for running R code from Python
- **DatabaseManager:** Connection management, query execution, transaction handling
- **Data Refresh Strategy:** Replace mode for clean datasets without duplicates

**When to use:** When writing Python code that interacts with R or the database.

---

## 📊 Data, Variables & Missing Data

### [MISSING_DATA_GUIDE.md](MISSING_DATA_GUIDE.md) ⚠️ CRITICAL
**Required reading for anyone creating or modifying derived variables**

- **Defensive Recoding:** Always use `recode_missing()` before transformation
- **Conservative Approach:** Use `na.rm = FALSE` in composite score calculations
- **Composite Variables Inventory:** Complete table of all 12 composite variables
- **Validation Checklist:** Required steps when adding new derived variables

**Critical Issue Prevented:** 254+ records (5.2% of dataset) had invalid ACE total scores (99-990 instead of 0-10) due to "Prefer not to answer" (99) being summed directly before this standard was implemented.

**When to use:** ALWAYS before creating new derived variables. Reference when debugging unexpected values.

---

### [DERIVED_VARIABLES_SYSTEM.md](DERIVED_VARIABLES_SYSTEM.md)
**Complete documentation of 99 derived variables created by recode_it()**

- **Variable Categories:** 10 categories (eligibility, race/ethnicity, education, income/FPL, mental health, ACEs, childcare, geographic)
- **Transformation Pipeline:** Step-by-step process from raw to derived
- **Configuration System:** `config/derived_variables.yaml` structure
- **Adding New Variables:** Complete checklist with code templates

**When to use:** Understanding what derived variables exist, how they're created, or when adding new variables.

---

### [GEOGRAPHIC_CROSSWALKS.md](GEOGRAPHIC_CROSSWALKS.md)
**Database-backed geographic reference tables for ZIP code translations**

- **10 Crosswalk Tables:** PUMA, County, Tract, CBSA, Urban/Rural, School Districts, Legislative Districts, Congressional Districts, Native Lands (126K+ rows total)
- **Querying from Python/R:** Utility functions and code examples
- **27 Derived Variables:** Geographic variables created from ZIP codes
- **Allocation Factors:** Handling ZIP codes spanning multiple geographies

**When to use:** Working with geographic data, understanding geographic variable creation, or querying crosswalk tables.

---

## 🔄 Migration & Deprecation

### [migration-guide.md](migration-guide.md)
**Guide for system migrations and deprecation notices**

- Historical migration from R DuckDB to Python database operations (September 2025)
- Upgrade paths and compatibility notes

**When to use:** Understanding historical system changes or planning future migrations.

---

## 📋 Guide Development Standards

When creating new guides, include:

1. **Purpose Statement** - What the guide helps you accomplish (1-2 sentences)
2. **Prerequisites** - Required software, credentials, or setup
3. **Step-by-Step Instructions** - Numbered steps with code examples
4. **Code Examples** - Concrete, runnable examples (not pseudocode)
5. **Common Pitfalls** - "What NOT to do" with explanations
6. **Troubleshooting** - Common issues and solutions
7. **Related Documentation** - Links to relevant technical docs
8. **Last Updated Date** - Keep guides current

---

## 🔗 Related Documentation

### Quick Reference
- **[../QUICK_REFERENCE.md](../QUICK_REFERENCE.md)** - Command cheatsheet for all 4 pipelines

### Architecture
- **[../architecture/PIPELINE_OVERVIEW.md](../architecture/PIPELINE_OVERVIEW.md)** - Comprehensive architecture for all 4 pipelines
- **[../architecture/PIPELINE_STEPS.md](../architecture/PIPELINE_STEPS.md)** - Step-by-step execution instructions

### Structure & Navigation
- **[../DIRECTORY_STRUCTURE.md](../DIRECTORY_STRUCTURE.md)** - Complete directory structure
- **[../INDEX.md](../INDEX.md)** - Complete documentation index

### Data & Codebook
- **[../codebook/README.md](../codebook/README.md)** - JSON-based metadata system, IRT parameters

### Pipeline-Specific Guides
- **[../acs/](../acs/)** - ACS pipeline documentation
- **[../nhis/](../nhis/)** - NHIS pipeline documentation
- **[../nsch/](../nsch/)** - NSCH pipeline documentation

---

## 📊 Guide Statistics

- **Total Guides:** 6 comprehensive guides
- **New Guides (October 2025):** 5 guides created in documentation reorganization
- **Total Documentation:** ~4,000 lines across all guides
- **Critical Guides:** 1 (MISSING_DATA_GUIDE.md marked as CRITICAL)

---

*Last Updated: October 2025 | Version 3.2.0*

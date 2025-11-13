# HRTL (Healthy & Ready to Learn) Scoring Functions

**Status:** 🚧 **IN DEVELOPMENT** - Functional but pending validation

## Overview

This directory contains R functions for scoring the **Healthy & Ready to Learn (HRTL)** framework, designed to assess school readiness for children ages 3-5 across five developmental domains.

## Components

### 27 HRTL Items Across 5 Domains

1. **Early Learning Skills** (9 items)
2. **Health** (3 items)
3. **Motor Development** (4 items)
4. **Self-Regulation** (5 items)
5. **Social-Emotional Development** (6 items)

### HRTL Classification Logic

A child is classified as **"Ready for Learning"** if:
- **At least 4 out of 5 domains** are classified as "On-Track" **AND**
- **Zero domains** are classified as "Needs-Support"

Domain classifications use standard HRTL cutoffs:
- **On-Track:** Mean score ≥ 2.5
- **Emerging:** Mean score ≥ 2.0 (but < 2.5)
- **Needs-Support:** Mean score < 2.0

## Functions

### 1. `load_hrtl_codebook()`

**Purpose:** Extract HRTL metadata from codebook.json

**Returns:** Data frame with:
- Item IDs and variable names (equate/ne25 lexicons)
- Domain classifications
- Age-specific thresholds (ages 3, 4, 5)

**Example:**
```r
source("R/hrtl/load_hrtl_codebook.R")
hrtl_meta <- load_hrtl_codebook(lexicon = "equate")
```

### 2. `classify_items()`

**Purpose:** Apply age-specific thresholds to individual item responses

**Returns:** Original data plus `{item}_class` columns (On-Track/Emerging/Needs-Support)

**Example:**
```r
source("R/hrtl/classify_items.R")
dat_classified <- classify_items(dat, age_var = "years", lexicon = "equate")
```

### 3. `aggregate_domains()`

**Purpose:** Compute domain-level scores and classifications

**Returns:** Original data plus:
- `hrtl_{domain}`: Domain mean scores (0-4 scale)
- `hrtl_{domain}_class`: Domain classifications
- `hrtl_n_items_valid`: Total valid items
- `hrtl_n_domains_valid`: Total valid domains

**Example:**
```r
source("R/hrtl/aggregate_domains.R")
dat_domains <- aggregate_domains(dat, lexicon = "equate")
```

### 4. `score_hrtl()` ⭐ **Complete Workflow**

**Purpose:** End-to-end HRTL scoring and classification

**Returns:** Original data plus:
- All domain scores and classifications
- `hrtl_n_on_track`: Number of On-Track domains
- `hrtl_n_emerging`: Number of Emerging domains
- `hrtl_n_needs_support`: Number of Needs-Support domains
- `hrtl_ready_for_learning`: Logical (TRUE/FALSE)
- `hrtl_classification`: "Ready", "Not Ready", or "Insufficient Data"

**Example:**
```r
source("R/hrtl/score_hrtl.R")
dat_hrtl <- score_hrtl(dat, age_var = "years", lexicon = "equate")
table(dat_hrtl$hrtl_classification)
```

## Known Limitations (GitHub Issue #9)

### Age-Based Routing Problem

NE25 data collection uses age-based routing that **excludes 8/27 items from ages 3-5**. This is developmentally appropriate (items measure infant/toddler milestones), but creates challenges for HRTL scoring:

| Domain | Total Items | Available (Ages 3-5) | Coverage |
|--------|-------------|---------------------|----------|
| Early Learning | 9 | 6 | 67% |
| Health | 3 | 3 | 100% |
| **Motor Development** | 4 | **1** | **25%** ⚠️ |
| Self-Regulation | 5 | 5 | 100% |
| Social-Emotional | 6 | 4 | 67% |

**Most Problematic:** Motor Development domain relies on single item (DD207: "How well can this child bounce a ball?")

### Items Excluded from Ages 3-5

**Early Learning (3 items):**
- EG20a: Counting objects
- EG21a: Reading one-digit numbers
- EG29a: Recognizing alphabet letters

**Motor Development (3 items):**
- EG30a: Drawing a circle
- EG32a: Drawing a face
- EG33a: Drawing a person

**Social-Emotional (2 items):**
- EG16a_1: Playing well with children
- EG43a_1: Explaining experiences

**Reference:** `docs/hrtl/hrtl_item_age_contingency.csv` (complete item × age breakdown)

## Interim Solution

**Current Approach:**
- Use **simple averaging** with `na.rm = TRUE` to handle missing items
- Compute domain scores from **available items only**
- Flag limitations in documentation

**Future Improvements:**
1. Develop **NE25-specific HRTL norms** using available item sets
2. Validate "Ready for Learning" classification against external criteria
3. Pool multi-study data (NE20, NE22, NE25) for complete item coverage
4. Implement **IRT-based domain scores** instead of simple means

## Test Results (N=978, Ages 3-5)

**Overall Classification:**
- **Ready:** 15 children (1.5%)
- **Not Ready:** 940 children (96.1%)
- **Insufficient Data:** 23 children (2.4%)

**Domain Performance:**
| Domain | Mean Score | On-Track | Emerging | Needs-Support |
|--------|------------|----------|----------|---------------|
| Social-Emotional | 2.83 | 73% | 17% | 10% |
| Early Learning | 2.41 | 54% | 14% | 33% |
| Motor | 2.01 | 29% | 46% | 25% |
| Health | 1.76 | 7% | 27% | 67% |
| Self-Regulation | 1.45 | 9% | 13% | 78% |

**Interpretation:** Low "Ready" rate (1.5%) reflects strict conjunctive logic requiring excellence across ALL domains. Health (67% Needs-Support) and Self-Regulation (78% Needs-Support) are common bottlenecks.

## Usage Example

```r
library(DBI)
library(duckdb)

# Load data
con <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
dat <- dbGetQuery(con, "
  SELECT *
  FROM ne25_calibration
  WHERE years BETWEEN 3 AND 5
")
dbDisconnect(con)

# Score HRTL
source("R/hrtl/score_hrtl.R")
dat_hrtl <- score_hrtl(
  dat = dat,
  age_var = "years",
  lexicon = "equate",
  verbose = TRUE
)

# Analyze results
table(dat_hrtl$hrtl_classification, useNA = "ifany")

# By age
library(dplyr)
dat_hrtl %>%
  group_by(age = floor(years)) %>%
  summarise(
    n = n(),
    pct_ready = 100 * mean(hrtl_ready_for_learning, na.rm = TRUE),
    mean_on_track = mean(hrtl_n_on_track, na.rm = TRUE)
  )
```

## Documentation

- **GitHub Issue #9:** Complete analysis of age-routing limitations
- **Contingency Table:** `docs/hrtl/hrtl_item_age_contingency.csv`
- **Test Scripts:** `scripts/temp/test_hrtl_scoring.R`, `scripts/temp/test_score_hrtl.R`
- **Main Documentation:** See `CLAUDE.md` under "Current Status"

## Development Status

**Completed:**
- ✅ All 4 core functions implemented
- ✅ Age-specific threshold application (ages 3, 4, 5)
- ✅ Domain aggregation with missing data handling
- ✅ HRTL classification logic
- ✅ Comprehensive testing (N=978)
- ✅ GitHub issue documenting limitations

**Pending:**
- ⏳ External validation against school readiness outcomes
- ⏳ NE25-specific norm development
- ⏳ Integration into main NE25 pipeline
- ⏳ Comparison with IRT-based scoring approaches

**Caution:** Results should be interpreted cautiously, especially for Motor Development domain (single-item measure). NE25-specific validation is strongly recommended before using for high-stakes decisions.

---

*Last Updated: November 2025*

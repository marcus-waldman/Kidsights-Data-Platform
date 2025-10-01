# Codebook System Changelog

All notable changes to the Kidsights Codebook System will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.0] - 2025-10-01

### Added
- **HRTL Health Items**: Added 4 health-related items from National Survey of Children's Health (NSCH)
  - `CQR014X` (ID 260): Health conditions impact frequency
  - `NOM044` (ID 261): Extent of health impact (conditional item)
  - `CQFA002` (ID 262): General health rating
  - `NOM046X` (ID 263): Dental health condition
- **New Domain**: `health` added to valid domains for HRTL/NSCH health items
- **New Response Sets**: Four HRTL-specific response sets for health items:
  - `hrtl_health_impact_ne25`: 5-point scale for health condition impact
  - `hrtl_extent_ne25`: 3-point extent scale
  - `hrtl_health_rating_ne25`: 5-point quality scale for general health
  - `hrtl_dental_ne25`: 6-point scale for dental condition
- **Enhanced Conversion**: Updated `detect_response_set_or_parse()` to recognize response set names without "=" characters

### Changed
- **Total Items**: Increased from 305 to 309 items (added 4 HRTL health items)
- **Domain Structure**: "health" domain now available in both `valid_domains` and `valid_hrtl_domains`
- **Configuration**: Updated `codebook_config.yaml` with health domain and response sets

### Technical Details
- Health items use NE25 study with explicit response set references
- All health items classified under both `kidsights.health` and `cahmi.health` domains
- Response sets follow NE25 convention (missing value = 9, not -9)
- Items added to CSV at IDs 260-263, maintaining sequential numbering

## [2.1.0] - 2025-09-16

### Added
- **GSED_PF Study Integration**: Added 46 PS (Psychosocial) items from GSED_PF study
- **New Domain**: `psychosocial_problems_general` for GSED_PF psychosocial items
- **PS Frequency Response Set**: New `ps_frequency` response set with scale:
  - 0 = "Never or Almost Never"
  - 1 = "Sometimes"
  - 2 = "Often"
  - -9 = "Don't Know" (missing)
- **PS Items Parser**: `parse_ps_items()` function in conversion script
- **Enhanced Dashboard**: Tree navigation now supports all 305 items including PS items

### Changed
- **Total Items**: Increased from 259 to 305 items (added 46 PS items)
- **Domain Structure**: Updated to support nested study groups within domain classifications
- **Conversion Script**: Enhanced `initial_conversion.R` to automatically integrate PS items
- **Configuration**: Updated `codebook_config.yaml` with new domain and response set

### Fixed
- **Reverse Coding**: Corrected reverse coding for 4 items (DD221, EG25a, EG26a, EG26b)
- **ID Consistency**: Ensured all items have integer IDs for dashboard compatibility
- **Response Set Detection**: Improved detection for PS frequency pattern

### Technical Details
- PS items use `lex_ne25` identifiers as primary keys (PS001-PS049)
- All PS items classified under `kidsights.psychosocial_problems_general` domain
- PS items assigned to GSED_PF study group
- Response options reference `ps_frequency` response set (not inline)

## [2.0.0] - 2025-09-15

### Added
- **JSON-Based Architecture**: Complete migration from CSV to structured JSON format
- **Quarto Dashboard**: Interactive web-based codebook explorer
- **Response Sets System**: Reusable response option definitions
- **Domain Hierarchies**: Structured kidsights/cahmi domain classifications
- **R Function Library**: Comprehensive functions for loading, querying, and visualizing
- **Tree Navigation**: Hierarchical JSON exploration in dashboard
- **Natural Sorting**: Alphanumeric ordering of items (e.g., AA4, AA5, AA11, AA102)

### Changed
- **Primary Identifier**: Switched from `lex_kidsight` to `lex_equate` as primary identifier
- **Data Structure**: Converted from flat CSV to nested JSON with proper metadata
- **Identifiers**: Restructured as "lexicons" object with study-specific mappings
- **Classification**: Split into separate "domains" and "age_range" objects

### Technical Details
- Implements configuration-driven validation via `codebook_config.yaml`
- Uses `gtools::mixedsort()` for natural alphanumeric ordering
- Supports both simplified and non-simplified JSON loading
- Dashboard built with Quarto and jsTree for navigation

## [1.0.0] - 2025-09-01

### Added
- **Initial CSV Codebook**: Legacy flat-file structure with 259 items
- **Basic Item Metadata**: Essential fields for item identification and classification
- **Study Coverage**: Support for NE25, NE22, NE20, CAHMI studies
- **Domain Classification**: Basic socemo, motor, coglan domains

### Technical Details
- CSV format with UTF-8 encoding
- Manual response option parsing
- Basic reverse coding flags
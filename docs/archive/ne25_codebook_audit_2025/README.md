# NE25 Comprehensive Codebook Audit System

## Overview

Validates all 435 NE25 items across REDCap and Codebook sources to ensure data integrity and consistency. Expanded from 46 PS items to complete coverage of all response set types.

## Quick Start

```bash
# Run complete audit pipeline
Rscript scripts/audit/ne25_codebook/extract_codebook_responses.R
Rscript scripts/audit/ne25_codebook/extract_redcap_metadata.R
Rscript scripts/audit/ne25_codebook/compare_sources.R
Rscript scripts/audit/ne25_codebook/generate_audit_report.R
```

## Scripts

### 1. `extract_codebook_responses.R`
- **Purpose:** Extracts all 276 items across 4 response set types
- **Output:** `data/codebook_responses.rds`, `data/codebook_validation.rds`
- **Coverage:** standard_binary_ne25 (193), ps_frequency_ne25 (46), likert_5_frequency_ne25 (32), likert_4_skill_ne25 (5)

### 2. `extract_redcap_metadata.R`
- **Purpose:** Extracts all 434 REDCap fields with response options
- **Output:** `data/redcap_metadata.rds`
- **Analysis:** Field types, prefixes, parsed response options

### 3. `compare_sources.R`
- **Purpose:** Direct REDCap-to-Codebook comparison (skips dictionary)
- **Output:** `data/source_comparison.rds`
- **Analysis:** Value/label matching, coverage gaps

### 4. `generate_audit_report.R`
- **Purpose:** Comprehensive reporting across all response set types
- **Output:** `reports/NE25_COMPREHENSIVE_AUDIT_SUMMARY.txt`

## Key Findings (September 2025)

- **265 items (60.9%)** present in both sources
- **80.8%** values match, **80.5%** labels match
- **11 items** need NE25 variable mapping
- **52 items** have value/label discrepancies

## Critical Issues

### Missing NE25 Mappings (11 items)
DD201, DD203, EG2_2, EG3_2, EG4a_2, EG4b_1, EG9b, EG11_2, EG13b, EG42b, EG50a

### Common Discrepancies
- Missing "Don't Know" option (value 9) in REDCap
- Label wording differences ("Dont Know" vs "Don't Know")
- Skill scale phrasing variations

## Troubleshooting

**Error: "Column doesn't exist"**
- Ensure all input data files exist before running comparison

**Low match rates**
- Check lexicon crosswalk completeness
- Verify REDCap project contains expected fields

**Missing reports**
- Ensure output directory exists: `reports/`
- Check file permissions

## Maintenance

Run audits after:
- Codebook updates
- REDCap field changes
- New study integration
- Response set modifications
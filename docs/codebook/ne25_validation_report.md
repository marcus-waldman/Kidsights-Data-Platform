# NE25 Codebook Validation Report

**Generated:** 2025-09-17 15:37:38.366617
**Script:** validate_ne25_codebook.R

## Executive Summary

This report validates that all items marked as NE25 in the codebook actually exist in the NE25 dictionary (actual REDCap data collection).

### Key Findings

- **Total NE25 Items:** 272
- **Items Found in Data:** 272 (100%)
- **Items Missing from Data:** 0 (0%)
- **Items with NE25 IRT Parameters:** 0 (0%)
- **Items with NE22 IRT Parameters:** 226 (83.1%)
- **Items with NE25 Response Options:** 226 (83.1%)

### Status
✅ **VALIDATION PASSED:** All codebook items exist in actual data collection

No phantom items detected. The codebook accurately reflects NE25 data collection.

## Detailed Analysis

### IRT Parameter Status

- **Empty NE25 IRT blocks:** 272 items
- **Available NE22 IRT data:** 226 items could potentially have parameters copied

### Response Options Coverage

- **Items with NE25 response mappings:** 226
- **Items missing response mappings:** 46

## IRT Parameter Analysis

### Items with NE22 but not NE25 IRT Parameters

These items have psychometric parameters from NE22 that could potentially be copied:

**Count:** 226 items

- AA4 (C020)
- AA5 (C023)
- AA6 (C026)
- AA7 (C033)
- AA9 (C038)
- AA11 (C042)
- AA12 (C043)
- AA13 (C047)
- AA14 (C048)
- AA15 (C049)
- ... and 216 more items

## Recommendations

### 1. Data Integrity

✅ No action needed - all NE25 assignments are valid.

### 2. IRT Parameters

Consider copying NE22 IRT parameters to 226 NE25 items that currently lack psychometric data.

### 3. Response Options

Review 46 items missing NE25 response option mappings.

## Technical Details

- **Codebook Version:** NE25
- **Codebook Version:** NE22
- **Codebook Version:** NE20
- **Codebook Version:** CREDI
- **Codebook Version:** GSED
- **Dictionary Fields:** 472 unique fields
- **Validation Date:** 2025-09-17 15:37:38.371774
- **Validation Script:** validate_ne25_codebook.R v1.0


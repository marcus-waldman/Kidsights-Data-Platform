# NE25 Audit Quick Reference

## Run Complete Audit

```bash
# 1. Extract codebook responses (all 276 items across 4 response sets)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/audit/ne25_codebook/extract_codebook_responses.R

# 2. Extract REDCap metadata (all 434 fields with response options)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/audit/ne25_codebook/extract_redcap_metadata.R

# 3. Compare sources directly (REDCap ↔ Codebook)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/audit/ne25_codebook/compare_sources.R

# 4. Generate comprehensive reports
"C:\Program Files\R\R-4.5.1\bin\R.exe" --arch x64 --slave --no-save --no-restore --no-environ -f scripts/audit/ne25_codebook/generate_audit_report.R
```

## Key Files Generated

### Data Files
- `data/codebook_responses.rds` - All 276 codebook items with response sets
- `data/codebook_validation.rds` - Response set validation results
- `data/redcap_metadata.rds` - All 434 REDCap fields with parsed options
- `data/source_comparison.rds` - Complete comparison results

### Reports
- `reports/NE25_COMPREHENSIVE_AUDIT_SUMMARY.txt` - Main executive summary
- `reports/value_label_mismatches.csv` - 52 items with discrepancies
- `reports/codebook_only_items.csv` - 11 unmapped items
- `reports/audit_reports_index.txt` - File index and usage guide

## Expected Results (September 2025)

```
Total Items Analyzed: 435
Perfect Matches: 265 (60.9%)
REDCap-Only Items: 169 (38.9%)
Codebook-Only Items: 0 (0%)
Value Match Rate: 80.8%
Label Match Rate: 80.5%
```

## Common Issues & Solutions

**"Column doesn't exist" error**
- Ensure all data files exist before running comparison script

**Missing reports**
- Check that `reports/` directory exists
- Verify R has write permissions

**Low match rates**
- Review lexicon crosswalk completeness
- Check REDCap project field names

## Critical Actions Needed

### 1. Add NE25 Variable Mappings (11 items)
DD201, DD203, EG2_2, EG3_2, EG4a_2, EG4b_1, EG9b, EG11_2, EG13b, EG42b, EG50a

### 2. Add "Don't Know" Option to REDCap (42 items)
Many items missing value 9 ("Don't Know") that exists in codebook

### 3. Standardize Labels (10 items)
Minor wording differences like "Dont Know" vs "Don't Know"

## When to Run Audits

- After codebook updates
- Before major data releases
- When REDCap fields change
- Monthly quality checks
- After new study integration
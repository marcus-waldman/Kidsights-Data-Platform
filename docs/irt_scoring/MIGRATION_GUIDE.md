# IRT Calibration Tables - Migration Guide

**Date:** January 2025
**Version:** 2.0
**Breaking Change:** Yes - New table structure

---

## Summary

The IRT calibration dataset architecture has been **refactored from combined tables to study-specific tables**. This eliminates data duplication and enables flexible NSCH sampling at export time.

---

## What Changed

### Old Architecture (Deprecated)

```
Database Tables:
├── historical_calibration_2020_2024 (41,577 records)
│   └── Combined: NE20 + NE22 + USA24
└── calibration_dataset_2020_2025 (47,084 records)
    └── Combined: All 6 studies
    └── NSCH: Fixed sample size (1000 per year)

Issues:
❌ Data duplication (~90 MB)
❌ NSCH sampling locked at storage time
❌ Cannot change sample size without re-running entire workflow
```

### New Architecture (Current)

```
Database Tables (Study-Specific):
├── ne20_calibration (37,546 records)
├── ne22_calibration (2,431 records)
├── usa24_calibration (1,600 records)
├── ne25_calibration (3,507 records)
├── nsch21_calibration (~50,000 records) ✨ ALL data
└── nsch22_calibration (~50,000 records) ✨ ALL data

Benefits:
✅ No duplication (~58 MB total)
✅ NSCH sampling at export time (flexible n=100 to n=50,000)
✅ Update one study without touching others
✅ Store ALL NSCH data, sample as needed
```

---

## Migration Steps

### Step 1: Migrate Existing Tables

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/migrate_to_study_tables.R
```

**What it does:**
- Splits `historical_calibration_2020_2024` into 3 study tables
- Prompts to drop deprecated `calibration_dataset_2020_2025` table
- Creates missing calibration tables (NE25, NSCH21, NSCH22)

### Step 2: Verify Migration

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/validate_calibration_tables.R
```

**Expected output:**
- ✅ All 6 tables exist
- ✅ Record counts in expected ranges
- ✅ Age ranges appropriate (0-18 years)
- ✅ No duplicate IDs within studies

### Step 3: Export Calibration Dataset

```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/export_calibration_dat.R
```

**What it does:**
- Combines 6 study tables on-the-fly
- Samples NSCH data (default: n=1000 per year)
- Creates Mplus .dat file
- Output: `mplus/calibdat.dat`

---

## New Workflow

### One-Time Setup (Per Database)

```bash
# 1. Import historical studies (NE20, NE22, USA24)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/import_historical_calibration.R

# 2. Create current study tables (NE25, NSCH21, NSCH22)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/create_calibration_tables.R

# 3. Validate all tables
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/validate_calibration_tables.R
```

### Regular Usage (As Needed)

```bash
# Export with default settings (NSCH n=1000)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/export_calibration_dat.R
```

### R Function Usage

```r
# Production export
source("scripts/irt_scoring/export_calibration_dat.R")
export_calibration_dat()

# Large sample for DIF analysis
export_calibration_dat(
  output_dat = "mplus/calibdat_large.dat",
  nsch_sample_size = 5000
)

# Quick test
export_calibration_dat(
  output_dat = "mplus/calibdat_test.dat",
  nsch_sample_size = 100
)

# Update only NE25 (after new data collection)
source("scripts/irt_scoring/create_calibration_tables.R")
create_calibration_tables(studies = "NE25")
```

---

## API Changes

### Deprecated Functions/Scripts

❌ **`prepare_calibration_dataset.R`** (OLD)
   - Created combined table + .dat file in one step
   - NSCH sampling at storage time
   - **Replaced by:** `create_calibration_tables.R` + `export_calibration_dat.R`

### New Functions/Scripts

✅ **`create_calibration_tables.R`** (NEW)
   - Creates study-specific tables
   - Stores ALL NSCH data (no sampling)
   - Can create all or individual studies

✅ **`export_calibration_dat.R`** (NEW)
   - Combines study tables on-the-fly
   - Samples NSCH at export time
   - Creates Mplus .dat file
   - Optional: creates database view

✅ **`migrate_to_study_tables.R`** (NEW)
   - Converts old tables to new structure
   - Interactive prompts for safety

✅ **`validate_calibration_tables.R`** (NEW)
   - Validates study-specific tables
   - Replaces old validation script

---

## Database Schema Changes

### Tables Removed

- `historical_calibration_2020_2024` (combined historical)
- `calibration_dataset_2020_2025` (combined all studies)

### Tables Added

- `ne20_calibration` (37,546 records)
- `ne22_calibration` (2,431 records)
- `usa24_calibration` (1,600 records)
- `ne25_calibration` (3,507 records)
- `nsch21_calibration` (~50,000 records)
- `nsch22_calibration` (~50,000 records)

### Table Structure

**All tables have consistent structure:**
- `id` (INTEGER) - Study-specific identifier
- `years` (REAL) - Child age in years
- `{items}` (REAL) - 30-416 developmental/behavioral items

**Notes:**
- No `study` column (table name indicates study)
- No `study_num` column (added at export time)
- NSCH uses original HHID as `id`

---

## Backward Compatibility

### Breaking Changes

⚠️ **Scripts that query old tables will fail:**

```r
# OLD CODE (FAILS)
DBI::dbGetQuery(conn, "SELECT * FROM calibration_dataset_2020_2025")

# NEW CODE (WORKS)
DBI::dbGetQuery(conn, "SELECT * FROM ne25_calibration")
```

⚠️ **Old .dat files remain valid but won't be updated:**

- Existing `mplus/calibdat.dat` files created before migration are still valid
- To update with new data, re-export using new workflow

### Migration Script Handles

✅ Existing old tables are converted automatically
✅ No data loss during migration
✅ Interactive prompts prevent accidental deletions

---

## FAQ

### Q: Do I need to re-run historical import?

**A:** No, if you already have `historical_calibration_2020_2024`. The migration script will split it into 3 study tables automatically.

### Q: Will my existing .dat files still work?

**A:** Yes! Existing Mplus .dat files are still valid. However, they won't include new NE25 data collected after they were created.

### Q: How do I update just NE25 data?

**A:** Run:
```r
source("scripts/irt_scoring/create_calibration_tables.R")
create_calibration_tables(studies = "NE25")
```

Then re-export:
```r
source("scripts/irt_scoring/export_calibration_dat.R")
export_calibration_dat()
```

### Q: Can I use different NSCH sample sizes?

**A:** Yes! That's the main benefit of the new architecture:
```r
export_calibration_dat(nsch_sample_size = 5000)  # Large sample
export_calibration_dat(nsch_sample_size = 100)   # Quick test
```

### Q: How do I query combined data?

**A:** Create a database view:
```r
export_calibration_dat(create_db_view = TRUE, view_name = "calibration_combined")
```

Then query:
```sql
SELECT study_num, COUNT(*) as n
FROM calibration_combined
GROUP BY study_num;
```

---

## Troubleshooting

### Error: "Table 'historical_calibration_2020_2024' not found"

**Solution:** You need to run the historical import first:
```bash
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore \
  --file=scripts/irt_scoring/import_historical_calibration.R
```

### Error: "Table 'nsch_2021_raw' not found"

**Solution:** Run NSCH pipeline first:
```bash
python scripts/nsch/process_all_years.py --years 2021 2022
```

### Validation warnings about record counts

**Normal:** Expected ranges are approximate. As long as you have:
- NE20: 35K-40K records
- NE25: 3K-5K records
- NSCH: 40K-60K records per year

You're fine.

---

## Performance Comparison

| Metric | Old Architecture | New Architecture | Improvement |
|--------|------------------|------------------|-------------|
| **Storage** | ~90 MB (duplicated) | ~58 MB | 35% smaller |
| **NSCH Flexibility** | Fixed at creation | Flexible at export | ✨ Major |
| **Update NE25** | Re-run full workflow | Update 1 table only | 10x faster |
| **Export Time** | N/A (combined) | ~5 seconds | Instant |
| **Sample n=100 test** | Re-run full workflow | Change parameter | 100x faster |

---

## Next Steps

After migration:

1. **Validate tables:** Run `validate_calibration_tables.R`
2. **Export dataset:** Run `export_calibration_dat.R`
3. **Test Mplus format:** Run `test_mplus_compatibility.R`
4. **Update documentation:** Review and update project-specific docs
5. **Create .inp file:** See `MPLUS_CALIBRATION_WORKFLOW.md`

---

**Migration Date:** January 2025
**Architecture Version:** 2.0
**Status:** Production Ready

---

*For questions or issues, see: docs/irt_scoring/CALIBRATION_DATASET_EXAMPLE.md*

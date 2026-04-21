# Database Table Catalog

**Snapshot date:** 2026-04-21
**Database:** `data/duckdb/kidsights_local.duckdb`
**Total tables:** 97
**Regenerate via:** `/refresh-database-inventory` skill (see `.claude/skills/refresh-database-inventory/SKILL.md`)
**Source of truth for metadata:** [`docs/database/table_metadata.yaml`](table_metadata.yaml)

---

This catalog lists every table in the platform's DuckDB database, grouped by pipeline. For each table: row count and column count come from live DB introspection; the source, primary downstream consumer, and status come from the hand-written YAML config linked above.

**Status values:**
- `live` — actively written and read by a current pipeline
- `backup` — snapshot retained for reference
- `test` — development artifact
- `empty` — exists but holds 0 rows (may be a placeholder or defunct)
- `deprecated` — superseded but not yet removed

---

## NE25 Pipeline (non-imputed)

Nebraska 2025 REDCap survey pipeline. Entry point: `run_ne25_pipeline.R`. `ne25_transformed` is the canonical analytic table; see its dictionary link below.

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `ne25_credi_scores` | 1,678 | 17 | Step 7.5 of run_ne25_pipeline.R via R/credi/score_credi.R. | CREDI developmental scoring for NE25 children under 4 (15 columns: 5 domain scores + 5 Z-scores + 5 SEs). 884 scored of 1,678 eligible. | — | live |
| `ne25_dscore_scores` | 2,645 | 8 | Step 7.6 of run_ne25_pipeline.R via R/dscore/score_dscore.R using gsed2406 key. | GSED D-score results for NE25 (d, daz, sem, a, n, p). 2,639 of 2,645 scored. | — | live |
| `ne25_flagged_observations` | 4 | 3 | scripts/influence_diagnostics/ (manual workflow; inserts via calibration/ne25/manual_2023_scale/utils/00_load_item_response_data.R). | Cook's-distance flagged observations from manual influence-diagnostic screening. Joined into ne25_transformed as the `influential` column. | Step 6.5 of run_ne25_pipeline.R (joins into ne25_transformed). _Note: Only 4 rows currently; most flagged observations live elsewhere. Verify scope before relying on this count._ | live |
| `ne25_hrtl_domain_scores` | 7,086 | 6 | Step 7.7 of run_ne25_pipeline.R — scripts/hrtl/01..04_*.R (extract → Rasch → impute → CAHMI threshold scoring). | HRTL per-domain classification (5 domains × ~1,411-1,425 records). Motor Development classification masked to NA per Issue #15. | — | live |
| `ne25_hrtl_overall` | 1,412 | 5 | Step 7.7 of run_ne25_pipeline.R — scripts/hrtl/04_score_hrtl.R. | HRTL overall readiness classification for ages 3-5 (1,412 records). Currently all NA pending Motor fix (Issue #15). | — | live |
| `ne25_kidsights_gsed_pf_scores_2022_scale` | 2,785 | 19 | calibration/ne25/manual_2023_scale/run_manual_calibration.R (Mplus output loaded into DuckDB). | Person-fit scores from the manual 2023-scale fixed-item Mplus calibration (7 domains × score + CSEM). 2,785 participants scored. | Step 6.7 of run_ne25_pipeline.R (joins person-fit scores into ne25_transformed). | live |
| `ne25_raw` | 4,966 | 6 | Step 5 of run_ne25_pipeline.R (R/extract/ne25.R writes via python.db.operations). | Raw REDCap exports from the four NE25 project PIDs, unioned and lightly cleaned. | Step 6 of run_ne25_pipeline.R — feeds recode_it() derivation into ne25_transformed. | live |
| `ne25_too_few_items` | 718 | 8 | calibration/ne25/manual_2023_scale/run_manual_calibration.R. | Exclusion flags for NE25 participants with insufficient item responses for IRT scoring (718 records). | Step 6.7 of run_ne25_pipeline.R (joins as inclusion criterion). | live |
| `ne25_transformed` | 4,966 | 723 | Step 6 onward of run_ne25_pipeline.R (recode_it() for derived vars, Step 6.7+ joins scores, Step 6.9 joins raking weights). | Canonical NE25 analytic table — raw fields + 99 derived variables + inclusion flags + weights + scoring joins. See [dictionary](../data_dictionary/ne25_data_dictionary_full.md). | Most downstream consumers: raking (scripts/raking/ne25/*), imputation pipeline, IRT calibration prep, all reports. | live |

## NE25 Imputed Variables (M=5)

Multiple-imputation outputs (M=5) from `scripts/imputation/ne25/`. Each table stores only the imputed rows (observed values remain in the base table). Join by `(pid, record_id, imputation_m)`.

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `ne25_imputed_cc_hours_per_week` | 5,514 | 5 | scripts/imputation/ne25/04_impute_childcare.R. | M=5 imputed weekly childcare hours. | Derived childcare_10hrs_nonfamily flag. | live |
| `ne25_imputed_cc_primary_type` | 7,014 | 5 | scripts/imputation/ne25/04_impute_childcare.R. | M=5 imputed primary childcare type. | Imputation-aware reports. | live |
| `ne25_imputed_cc_receives_care` | 85 | 5 | scripts/imputation/ne25/04_impute_childcare.R + 04_insert_childcare_imputations.py. | M=5 3-stage-sequential imputed childcare receipt indicator. | Imputation-aware reports. | live |
| `ne25_imputed_census_tract` | 16,060 | 5 | scripts/imputation/ne25/01_impute_geography.py. | M=5 probabilistically allocated census tracts. | Imputation-aware reports. | live |
| `ne25_imputed_child_ace_discrimination` | 205 | 5 | scripts/imputation/ne25/06_impute_child_aces.R. | M=5 random-forest-imputed child ACE: racial/ethnic discrimination. | Derived child_ace_total. | live |
| `ne25_imputed_child_ace_domestic_violence` | 240 | 5 | scripts/imputation/ne25/06_impute_child_aces.R. | M=5 random-forest-imputed child ACE: domestic violence exposure. | Derived child_ace_total. | live |
| `ne25_imputed_child_ace_mental_illness` | 265 | 5 | scripts/imputation/ne25/06_impute_child_aces.R. | M=5 random-forest-imputed child ACE: household mental illness. | Derived child_ace_total. | live |
| `ne25_imputed_child_ace_neighborhood_violence` | 255 | 5 | scripts/imputation/ne25/06_impute_child_aces.R. | M=5 random-forest-imputed child ACE: neighborhood violence. | Derived child_ace_total. | live |
| `ne25_imputed_child_ace_parent_death` | 170 | 5 | scripts/imputation/ne25/06_impute_child_aces.R. | M=5 random-forest-imputed child ACE: parent death. | Derived child_ace_total. | live |
| `ne25_imputed_child_ace_parent_divorce` | 205 | 5 | scripts/imputation/ne25/06_impute_child_aces.R. | M=5 random-forest-imputed child ACE: parent divorce/separation. | Derived child_ace_total. | live |
| `ne25_imputed_child_ace_parent_jail` | 255 | 5 | scripts/imputation/ne25/06_impute_child_aces.R. | M=5 random-forest-imputed child ACE: parent incarceration. | Derived child_ace_total. | live |
| `ne25_imputed_child_ace_substance_use` | 250 | 5 | scripts/imputation/ne25/06_impute_child_aces.R. | M=5 random-forest-imputed child ACE: household substance use. | Derived child_ace_total. | live |
| `ne25_imputed_child_ace_total` | 740 | 5 | scripts/imputation/ne25/06_impute_child_aces.R (derived). | M=5 derived total child ACE score (sum of 8 items). | Imputation-aware reports. | live |
| `ne25_imputed_childcare_10hrs_nonfamily` | 13,820 | 5 | scripts/imputation/ne25/04_impute_childcare.R (derived). | M=5 derived indicator: >=10 hours/week non-family childcare. | Raking pipeline (childcare estimand). | live |
| `ne25_imputed_county` | 5,300 | 5 | scripts/imputation/ne25/01_impute_geography.py. | M=5 probabilistically allocated counties. | Raking pipeline and imputation-aware reports. | live |
| `ne25_imputed_educ_a2` | 3,050 | 5 | scripts/imputation/ne25/02_impute_sociodem.R. | M=5 MICE-imputed secondary caregiver education. | Imputation-aware reports. | live |
| `ne25_imputed_educ_mom` | 3,830 | 5 | scripts/imputation/ne25/02_impute_sociodem.R + 02b_insert_sociodem_imputations.py. | M=5 MICE-imputed maternal education. | Raking pipeline (mother education estimand). | live |
| `ne25_imputed_family_size` | 430 | 5 | scripts/imputation/ne25/02_impute_sociodem.R. | M=5 MICE-imputed family size. | Downstream FPL calculation. | live |
| `ne25_imputed_female` | 170 | 5 | scripts/imputation/ne25/02_impute_sociodem.R + 02b_insert_sociodem_imputations.py. | M=5 MICE-imputed binary sex indicator. | Raking pipeline (sex estimand). | live |
| `ne25_imputed_fplcat` | 13,782 | 5 | scripts/imputation/ne25/03_derive_fpl.R. | M=5 imputed federal poverty level categories (derived from imputed income + family size). | Raking pipeline (FPL estimand). | live |
| `ne25_imputed_gad2_nervous` | 130 | 5 | scripts/imputation/ne25/05_impute_mental_health.R. | M=5 CART-imputed GAD-2 nervousness item. | Derived gad2_positive flag. | live |
| `ne25_imputed_gad2_positive` | 155 | 5 | scripts/imputation/ne25/05_impute_mental_health.R (derived). | M=5 derived GAD-2 positive-screen indicator. | Raking pipeline (mental health estimand). | live |
| `ne25_imputed_gad2_worry` | 100 | 5 | scripts/imputation/ne25/05_impute_mental_health.R. | M=5 CART-imputed GAD-2 worry item. | Derived gad2_positive flag. | live |
| `ne25_imputed_income` | 25 | 5 | scripts/imputation/ne25/02_impute_sociodem.R. | M=5 MICE-imputed household income. | Downstream FPL calculation and reports. | live |
| `ne25_imputed_phq2_depressed` | 130 | 5 | scripts/imputation/ne25/05_impute_mental_health.R. | M=5 CART-imputed PHQ-2 depressed-mood item. | Derived phq2_positive flag. | live |
| `ne25_imputed_phq2_interest` | 80 | 5 | scripts/imputation/ne25/05_impute_mental_health.R + 05b_insert_mental_health_imputations.py. | M=5 CART-imputed PHQ-2 anhedonia item. | Derived phq2_positive flag; raking pipeline. | live |
| `ne25_imputed_phq2_positive` | 135 | 5 | scripts/imputation/ne25/05_impute_mental_health.R (derived). | M=5 derived PHQ-2 positive-screen indicator. | Raking pipeline (mental health estimand). | live |
| `ne25_imputed_puma` | 4,430 | 5 | scripts/imputation/ne25/01_impute_geography.py. | M=5 probabilistically allocated PUMAs for NE25 records with missing PUMA assignments. | Raking pipeline (joins imputed geography for calibration target matching). | live |
| `ne25_imputed_q1502` | 115 | 5 | scripts/imputation/ne25/05_impute_mental_health.R. | M=5 CART-imputed parenting item (q1502). | Imputation-aware reports. | live |
| `ne25_imputed_raceG` | 360 | 5 | scripts/imputation/ne25/02_impute_sociodem.R + 02b_insert_sociodem_imputations.py. | M=5 MICE-imputed collapsed race/ethnicity categories. | Raking pipeline (race/ethnicity estimand). | live |

## NSCH Pipeline

National Survey of Children's Health (2016-2023). Produced by `scripts/nsch/process_all_years.py`. Note the year-suffix naming inconsistency (2021/2022 use `nsch_{year}`; other years use `nsch_{year}_raw`).

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `nsch_2016_raw` | 0 | 840 | Schema placeholder only; scripts/nsch/process_all_years.py skips 2016. | NSCH 2016 raw data — never loaded (schema differences with 2017+). | — _Note: Documented as a schema-incompatibility case in HANDOFF.md._ | empty |
| `nsch_2017_raw` | 21,599 | 813 | scripts/nsch/process_all_years.py (SPSS → Feather → DuckDB). | NSCH 2017 raw data, 21,599 records × 813 cols. | IRT calibration pipeline (NSCH records used for national benchmarking). | live |
| `nsch_2018_raw` | 30,530 | 835 | scripts/nsch/process_all_years.py. | NSCH 2018 raw data, 30,530 records × 835 cols. | IRT calibration pipeline. | live |
| `nsch_2019_raw` | 29,433 | 834 | scripts/nsch/process_all_years.py. | NSCH 2019 raw data, 29,433 records × 834 cols. | IRT calibration pipeline. | live |
| `nsch_2020_raw` | 42,777 | 847 | scripts/nsch/process_all_years.py. | NSCH 2020 raw data, 42,777 records × 847 cols. | IRT calibration pipeline. | live |
| `nsch_2021` | 50,892 | 909 | scripts/nsch/process_all_years.py. | NSCH 2021 raw data, 50,892 records × 909 cols. Note naming inconsistency (no _raw suffix). | IRT calibration pipeline. _Note: Naming inconsistency flagged in HANDOFF.md. Years 2017-2020 and 2023 use nsch_{year}_raw; 2021 and 2022 use nsch_{year}. Worth standardizing._ | live |
| `nsch_2022` | 54,103 | 958 | scripts/nsch/process_all_years.py. | NSCH 2022 raw data, 54,103 records × 958 cols. Note naming inconsistency (no _raw suffix). | IRT calibration pipeline; raking targets (NSCH estimands). _Note: See nsch_2021 note on naming inconsistency._ | live |
| `nsch_2023_raw` | 55,162 | 895 | scripts/nsch/process_all_years.py. | NSCH 2023 raw data, 55,162 records × 895 cols. | IRT calibration pipeline; raking targets. | live |
| `nsch_value_labels` | 36,164 | 5 | pipelines/python/nsch/load_nsch_metadata.py. | Value-label mappings across all NSCH years (36,164 rows). | Data dictionary generation; IRT calibration codebook harmonization. | live |
| `nsch_variables` | 6,867 | 7 | pipelines/python/nsch/load_nsch_metadata.py. | Variable metadata across all NSCH years (6,867 rows). | Data dictionary generation; IRT calibration codebook harmonization. | live |

## NHIS Pipeline

National Health Interview Survey multi-year extracts (2019-2024) from IPUMS.

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `nhis_raw` | 229,609 | 66 | pipelines/python/nhis/insert_nhis_database.py (IPUMS extraction → Feather → DuckDB). | NHIS multi-year raw extracts (2019-2024), 229,609 records × 66 cols. | Raking pipeline scripts 12-14 (NHIS estimand estimation). | live |

## ACS Pipeline

IPUMS USA ACS extracts + DDI metadata registry. Consumed by the raking pipeline.

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `acs_data` | 24,449 | 44 | pipelines/python/acs/insert_acs_database.py (IPUMS extraction → Feather → DuckDB). | ACS multi-year raw extracts for target states (24,449 records for Nebraska 2019-2023). | Raking pipeline scripts 01-07 (ACS survey design and GLM estimation). | live |
| `acs_metadata_registry` | 2 | 10 | pipelines/python/acs/insert_acs_database.py. | Registry of DDI metadata files loaded (title, producer, dates). | Provenance audit trail. | live |
| `acs_value_labels` | 1,144 | 5 | pipelines/python/acs/ddi_parser.py. | ACS value-label mappings (1,144 rows across all variables). | Raking pipeline transformation lookups. | live |
| `acs_variables` | 42 | 9 | pipelines/python/acs/ddi_parser.py + insert_acs_database.py. | ACS variable metadata parsed from DDI XML (42 vars currently tracked). | Raking pipeline transformation lookups. | live |

## IRT Calibration

Multi-study IRT calibration dataset (9,319 post-QA records across 6 studies). `calibration_dataset_2020_2025` is the canonical wide format; the `_with_flags`, `_full_with_flags`, and `_restructured` variants serve QA and Mplus-syntax-generation workflows respectively.

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `calibration_dataset_2020_2025` | 9,319 | 312 | scripts/irt_scoring/prepare_calibration_dataset.R via scripts/irt_scoring/run_calibration_pipeline.R. | Wide-format multi-study calibration dataset (9,319 post-QA records × 312 cols, 6 studies). | mplus/calibdat.dat export (weighted graded response model in Mplus). | live |
| `calibration_dataset_2020_2025_restructured` | 85,544 | 303 | scripts/irt_scoring/prepare_calibration_dataset.R (alternate shape for syntax builder). | Restructured variant of the calibration dataset used as the reference table for Mplus MODEL syntax generation (85,544 rows × 303 cols). | scripts/irt_scoring/calibration/generate_model_syntax.R (produces MODEL / CONSTRAINT / PRIOR sheets). | live |
| `calibration_dataset_full_with_flags` | 46,003 | 10 | scripts/irt_scoring/run_calibration_pipeline.R. | All calibration records + just the flag columns (46,003 rows × 10 cols). | QA summary reports; masking audit. | live |
| `calibration_dataset_long` | 1,332,042 | 9 | scripts/irt_scoring/create_calibration_long.R. | Long-format calibration dataset with QA flags (1,332,042 rows × 9 cols: id, years, study, studynum, lex_equate, y, cooksd_quantile, maskflag, devflag). | Age Gradient Explorer Shiny app; masking/QA analysis. | live |
| `calibration_dataset_with_flags` | 18,638 | 314 | scripts/irt_scoring/run_calibration_pipeline.R (flag-joined variant). | Wide-format subset with QA flags merged in (18,638 rows × 314 cols). | QA inspection; alternate Mplus export. | live |

## Historical Calibration Data

Historical Kidsights calibration records imported from the KidsightsPublic package (NE20, NE22, USA24).

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `historical_calibration_2020_2024` | 5,012 | 290 | scripts/irt_scoring/import_historical_calibration.R. | Historical multi-study Kidsights calibration records (5,012 rows × 290 cols) imported from the KidsightsPublic package — covers NE20, NE22, USA24. | scripts/irt_scoring/prepare_calibration_dataset.R (merged into calibration_dataset_2020_2025). | live |

## Raking Targets & Bootstrap Replicates

Population-representative targets and bootstrap replicate infrastructure feeding the NE25 raking pipeline (scripts 01-34) and the MIBB variance framework (scripts 35-36).

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `ne25_raked_weights` | 13,225 | 5 | scripts/raking/ne25/32-34_*.R (run_ne25_raking_full.R orchestrator). | Bucket 2 output: M=5 multi-imputation calibrated raking weights (13,225 rows = 5 × 2,645). | Step 6.9 of run_ne25_pipeline.R (pulls M=1 slice as calibrated_weight column). | live |
| `ne25_raked_weights_boot` | 2,645,000 | 6 | scripts/raking/ne25/35_run_bayesian_bootstrap.R + 36_store_bootstrap_weights_long.py. | Bucket 3 output: MIBB replicate weights (2,645,000 rows = 5 imputations × 200 bootstrap draws × 2,645 records). | reports/ne25/helpers/model_fitting.R (Rubin's-rules pooling — not yet wired as of 2026-04-21). | live |
| `raking_targets_boot_replicates` | 737,280 | 10 | scripts/raking/ne25/run_bootstrap_pipeline.R + 23_insert_boot_replicates.py + 24_create_database_table.py. | Bootstrap replicate estimates for ACS estimands (737,280 rows = 180 targets × 4,096 Rao-Wu-Yue-Beaumont replicates). | Variance estimation in raking-targets construction; input to MIBB variance framework. | live |
| `raking_targets_ne25` | 11 | 14 | scripts/raking/ne25/run_raking_targets_pipeline.R. | Pooled population-representative targets for NE25 raking (11 consolidated target rows × 14 cols including estimate, SE, CI, sample_size). | NE25 raking pipeline scripts 32-34 (calibration via Stan optimization). _Note: 11 is the current consolidated-target state; older design docs describing 180 targets (30 estimands × 6 age groups) are stale text. See HANDOFF.md drift review._ | live |

## Geographic Crosswalks

ZCTA-based geographic crosswalks. `geo_zip_to_*` tables are loaded by `pipelines/python/load_geographic_crosswalks.py`; `ne_zip_county_crosswalk` is a legacy Nebraska-specific array format kept for the NE25 eligibility path.

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `geo_zip_to_cbsa` | 40,769 | 6 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → Core-Based Statistical Area crosswalk with population allocation factors (40,769 rows). | R/utils/query_geo_crosswalk.R and python/db/query_geo_crosswalk.py; NE25 transform for ZIP-based geography. | live |
| `geo_zip_to_congress` | 647 | 7 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → Congressional district crosswalk (647 rows). | Geographic transformation utilities. | live |
| `geo_zip_to_county` | 975 | 6 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → county crosswalk (975 rows, supersedes ne_zip_county_crosswalk for general use). | NE25 and MN26 transforms for county assignment. | live |
| `geo_zip_to_native_lands` | 35,026 | 6 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → tribal/native lands crosswalk (35,026 rows). | Geographic transformation utilities. | live |
| `geo_zip_to_puma` | 708 | 8 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → PUMA 2022 crosswalk (708 rows). | NE25 transform (PUMA assignment) and imputation pipeline. | live |
| `geo_zip_to_school_dist` | 1,673 | 8 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → school district crosswalk (1,673 rows). | Geographic transformation utilities. | live |
| `geo_zip_to_state_leg_lower` | 591 | 7 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → state legislative lower chamber crosswalk (591 rows). | Geographic transformation utilities. | live |
| `geo_zip_to_state_leg_upper` | 902 | 7 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → state legislative upper chamber crosswalk (902 rows). | Geographic transformation utilities. | live |
| `geo_zip_to_tract` | 1,711 | 7 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → Census tract crosswalk (1,711 rows). | Imputation pipeline (census tract allocation). | live |
| `geo_zip_to_urban_rural` | 42,870 | 5 | pipelines/python/load_geographic_crosswalks.py. | ZCTA → urban/rural classification (42,870 rows). | NE25 and MN26 transforms. | live |
| `ne_zip_county_crosswalk` | 627 | 2 | scripts/setup/load_zip_crosswalk.R. | Nebraska-specific legacy ZIP → acceptable-counties lookup (627 rows, 2 cols). | NE25 eligibility logic (in-state verification). _Note: Older/simpler format than geo_zip_to_county. Kept for NE25 eligibility path that expects the acceptable_counties array form._ | live |

## Metadata / Catalog Tables

Catalog and provenance tables not tied to a single pipeline.

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `imputation_metadata` | 21 | 9 | scripts/imputation/ne25/*.py (one row per imputed variable per study). | Imputation provenance registry (21 rows × 9 cols: study_id, variable_name, n_imputations, method, predictors, dates, software version). | Imputation-aware downstream tooling; python.imputation.helpers validation. | live |
| `item_review_notes` | 6,186 | 6 | scripts/shiny/age_gradient_explorer/notes_helpers_db.R (interactive Shiny writes). | Reviewer annotations from the Age Gradient Explorer QA tool (6,186 rows: id, item_id, note, timestamp, reviewer, is_current). | IRT calibration QA workflow (informs masking decisions). | live |
| `ne25_data_dictionary` | 471 | 20 | pipelines/python/generate_metadata.py (REDCap metadata export loaded into DuckDB). | REDCap field metadata (field_name, form_name, field_type, labels, branching logic) for NE25. | scripts/documentation/generate_html_documentation.py and the codebook dashboard. | live |
| `ne25_metadata` | 720 | 26 | pipelines/python/generate_metadata.py, run near the end of the NE25 pipeline. | Variable-level summary statistics for the NE25 transformed dataset (n_missing, unique_values, min/max, labels). | Data dictionary HTML and codebook dashboard. | live |

---

## Cleanup Candidates

Zero-row, backup, test, or deprecated tables flagged for removal. HANDOFF.md's DB Drift section tracks the larger cleanup initiative.

| Table | Rows | Cols | Source | Purpose | Used by | Status |
|---|---:|---:|---|---|---|---|
| `ne25_credi_scores_test` | 1,678 | 17 | Historical test run. | Test/development duplicate of ne25_credi_scores. | — | test |
| `ne25_dscore_scores_test` | 2,645 | 8 | Historical test run. | Test/development duplicate of ne25_dscore_scores. | — | test |
| `ne25_eligibility` | 0 | 6 | Historical — R/harmonize/ne25_eligibility.R referenced this name but current pipeline writes eligibility columns into ne25_transformed. | Originally a standalone eligibility snapshot; eligibility flags now live on ne25_transformed. | — | empty |
| `ne25_imputed_imputed_cc_hours_per_week` | 0 | 5 | Early implementation bug — superseded by ne25_imputed_cc_hours_per_week. | Defunct double-prefixed childcare imputation table. | — | empty |
| `ne25_imputed_imputed_cc_primary_type` | 0 | 5 | Early implementation bug — superseded by ne25_imputed_cc_primary_type. | Defunct double-prefixed childcare imputation table. | — | empty |
| `ne25_imputed_imputed_cc_receives_care` | 0 | 5 | Early implementation bug — superseded by ne25_imputed_cc_receives_care. | Defunct double-prefixed childcare imputation table. | — | empty |
| `ne25_imputed_imputed_childcare_10hrs_nonfamily` | 0 | 5 | Early implementation bug — superseded by ne25_imputed_childcare_10hrs_nonfamily. | Defunct double-prefixed childcare imputation table. | — | empty |
| `ne25_irt_scores_kidsights` | 0 | 8 | Legacy schema (pre-manual-calibration workflow). | Placeholder for Kidsights IRT score cache; never populated by the current pipeline. | — | empty |
| `ne25_irt_scores_psychosocial` | 0 | 18 | Legacy schema (pre-manual-calibration workflow). | Placeholder for psychosocial IRT score cache; never populated by the current pipeline. | — | empty |
| `ne25_raw_pid7679` | 0 | 3 | Legacy per-project ingestion pattern (pre-unioned ne25_raw). | Per-project staging table for REDCap PID 7679 (defunct). | — | empty |
| `ne25_raw_pid7943` | 0 | 3 | Legacy per-project ingestion pattern (pre-unioned ne25_raw). | Per-project staging table for REDCap PID 7943 (defunct). | — | empty |
| `ne25_raw_pid7999` | 0 | 3 | Legacy per-project ingestion pattern (pre-unioned ne25_raw). | Per-project staging table for REDCap PID 7999 (defunct). | — | empty |
| `ne25_raw_pid8014` | 0 | 3 | Legacy per-project ingestion pattern (pre-unioned ne25_raw). | Per-project staging table for REDCap PID 8014 (defunct). | — | empty |
| `ne25_transformed_backup_2025_11_08` | 4,966 | 670 | Manual backup taken 2025-11-08 before schema changes. | Pre-refactor snapshot of ne25_transformed (670 cols vs current 723). | — _Note: Flagged for cleanup in HANDOFF.md. Schema pre-dates the weight and scoring column additions._ | backup |
| `nsch_crosswalk` | 0 | 8 | Planned metadata table; never populated. | NSCH cross-year variable crosswalk (empty placeholder). | — | empty |
| `test_duckdb_120` | 5 | 8 | Ad-hoc development. | Smoke-test table for DuckDB 1.2.0 migration. | — | test |
| `test_geo_parquet` | 3 | 27 | Ad-hoc development. | Smoke-test table for geographic Parquet loading. | — | test |
| `test_table` | 0 | 1 | Ad-hoc development. | Generic smoke-test placeholder. | — | test |

---

## Regenerating this catalog

When a table is added, dropped, or its metadata changes:

1. Edit [`docs/database/table_metadata.yaml`](table_metadata.yaml) — the hand-written source.
2. Invoke `/refresh-database-inventory` (the skill runs the generator and surfaces orphan/stale warnings).
3. Commit both the YAML edits and the regenerated `TABLES.md` together.

*Generated 2026-04-21 by `scripts/documentation/generate_tables_md.py`.*

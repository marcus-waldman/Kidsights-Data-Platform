"""
Multi-Study Data Access - Python Example

Demonstrates how to work with multiple independent studies
(ne25, ia26, co27) using the imputation helper functions.
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(project_root))

from python.imputation.helpers import (
    get_completed_dataset,
    get_imputation_metadata,
    validate_imputations
)
from python.imputation.config import get_study_config
import pandas as pd

print("=" * 70)
print("EXAMPLE 1: Access Data from Multiple Studies")
print("=" * 70)

# Get ne25 data
print("\n[INFO] Loading ne25 data (Nebraska 2025)...")
ne25_df = get_completed_dataset(
    imputation_m=1,
    variables=['puma', 'county', 'female', 'raceG'],
    base_table='ne25_transformed',
    study_id='ne25'
)
print(f"[OK] Loaded {len(ne25_df)} records from ne25")

# Note: ia26 and co27 are future studies - this is example code
# Uncomment when those studies are available:
#
# print("\n[INFO] Loading ia26 data (Iowa 2026)...")
# ia26_df = get_completed_dataset(
#     imputation_m=1,
#     variables=['puma', 'county', 'female', 'raceG'],
#     base_table='ia26_transformed',
#     study_id='ia26'
# )
# print(f"[OK] Loaded {len(ia26_df)} records from ia26")

print("\n" + "=" * 70)
print("EXAMPLE 2: Compare Study Configurations")
print("=" * 70)

# Get configuration for ne25
ne25_config = get_study_config('ne25')
print(f"\n[INFO] NE25 Configuration:")
print(f"  Study Name: {ne25_config['study_name']}")
print(f"  Number of Imputations: {ne25_config['n_imputations']}")
print(f"  Geography Variables: {', '.join(ne25_config['geography']['variables'])}")
print(f"  Sociodem Variables: {', '.join(ne25_config['sociodemographic']['variables'])}")

# Future studies (example):
# ia26_config = get_study_config('ia26')
# print(f"\n[INFO] IA26 Configuration:")
# print(f"  Study Name: {ia26_config['study_name']}")
# print(f"  Number of Imputations: {ia26_config['n_imputations']}")

print("\n" + "=" * 70)
print("EXAMPLE 3: Metadata Across All Studies")
print("=" * 70)

# Get metadata for all studies in the database
all_meta = get_imputation_metadata()

print(f"\n[OK] Found metadata for {len(all_meta)} variables across all studies")

# Summarize by study
study_summary = all_meta.groupby('study_id').agg({
    'variable_name': 'count',
    'n_imputations': 'first'
}).rename(columns={'variable_name': 'n_variables'})

print("\nStudies in database:")
for study_id, row in study_summary.iterrows():
    print(f"  {study_id}: {row['n_variables']} variables, M={row['n_imputations']} imputations")

# Show variables for each study
print("\nVariables by study:")
for study_id in all_meta['study_id'].unique():
    study_vars = all_meta[all_meta['study_id'] == study_id]
    var_names = ', '.join(study_vars['variable_name'].tolist())
    print(f"  {study_id}: {var_names}")

print("\n" + "=" * 70)
print("EXAMPLE 4: Validate Multiple Studies")
print("=" * 70)

# Validate each study independently
studies_to_validate = ['ne25']  # Add 'ia26', 'co27' when available

for study_id in studies_to_validate:
    print(f"\n[INFO] Validating {study_id}...")
    results = validate_imputations(study_id=study_id)

    if results['all_valid']:
        print(f"  [OK] All {results['variables_checked']} variables validated")
    else:
        print(f"  [WARN] Issues found:")
        for issue in results['issues']:
            print(f"    - {issue}")

print("\n" + "=" * 70)
print("EXAMPLE 5: Study-Specific Analysis")
print("=" * 70)

# Demonstrate accessing study-specific variables that may differ
print("\n[INFO] NE25-specific analysis:")

# Get all variables for ne25 (including study-specific ones)
ne25_full = get_completed_dataset(
    imputation_m=1,
    variables=None,  # Get ALL imputed variables
    base_table='ne25_transformed',
    study_id='ne25'
)

imputed_cols = [col for col in ne25_full.columns
                if col in ['puma', 'county', 'census_tract', 'female', 'raceG',
                          'educ_mom', 'educ_a2', 'income', 'family_size', 'fplcat']]

print(f"  Total columns: {len(ne25_full.columns)}")
print(f"  Imputed variables: {', '.join(imputed_cols)}")
print(f"  Records: {len(ne25_full)}")

# Check for missing values in imputed variables
print("\n[INFO] Missing values in imputed variables:")
for col in imputed_cols:
    if col in ne25_full.columns:
        n_missing = ne25_full[col].isna().sum()
        pct_missing = 100 * n_missing / len(ne25_full)
        print(f"  {col}: {n_missing} ({pct_missing:.1f}%)")

print("\n" + "=" * 70)
print("[OK] Multi-study examples completed")
print("=" * 70)

print("\n[INFO] Note: Future studies (ia26, co27) will follow the same pattern:")
print("  1. Create study config: config/imputation/studies/{study_id}.yaml")
print("  2. Run pipeline: scripts/imputation/{study_id}/run_full_imputation_pipeline.R")
print("  3. Access data: get_completed_dataset(..., study_id='{study_id}')")

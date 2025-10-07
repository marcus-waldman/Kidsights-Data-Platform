"""
Basic Usage Examples - Python Imputation Helpers

Demonstrates core functionality for accessing multiply imputed data
from the Kidsights imputation system.
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(project_root))

from python.imputation.helpers import (
    get_completed_dataset,
    get_all_imputations,
    get_imputed_variable_summary,
    get_imputation_metadata,
    validate_imputations
)

print("=" * 70)
print("EXAMPLE 1: Get Completed Dataset (Single Imputation)")
print("=" * 70)

# Get imputation m=1 with specific variables
df = get_completed_dataset(
    imputation_m=1,
    variables=['puma', 'county', 'female', 'raceG'],
    base_table='ne25_transformed',
    study_id='ne25'
)

print(f"\n[OK] Loaded {len(df)} records with {len(df.columns)} columns")
print(f"Columns: {', '.join(df.columns.tolist())}")
print(f"\nFirst 5 records:")
print(df.head())

print("\n" + "=" * 70)
print("EXAMPLE 2: Get All Imputations (Long Format)")
print("=" * 70)

# Get all M=5 imputations for geography variables
df_long = get_all_imputations(
    variables=['puma', 'county'],
    base_table='ne25_transformed',
    study_id='ne25'
)

print(f"\n[OK] Loaded {len(df_long)} records (5 imputations)")
print(f"Columns: {', '.join(df_long.columns.tolist())}")

# Calculate variability across imputations
import pandas as pd
variability = df_long.groupby(['pid', 'record_id']).agg({
    'puma': lambda x: x.nunique(),
    'county': lambda x: x.nunique()
}).rename(columns={'puma': 'n_puma_values', 'county': 'n_county_values'})

uncertain_puma = (variability['n_puma_values'] > 1).sum()
uncertain_county = (variability['n_county_values'] > 1).sum()

print(f"\n[INFO] Records with geographic uncertainty:")
print(f"  PUMA varies: {uncertain_puma} records")
print(f"  County varies: {uncertain_county} records")

print("\n" + "=" * 70)
print("EXAMPLE 3: Variable Summary Statistics")
print("=" * 70)

# Get distribution of PUMA values across all imputations
summary = get_imputed_variable_summary('puma', study_id='ne25')

print(f"\n[OK] PUMA distribution across M=5 imputations")
print(f"Total rows in summary: {len(summary)}")
print("\nTop 10 PUMA values (imputation 1):")
m1_summary = summary[summary['imputation_m'] == 1].sort_values('count', ascending=False).head(10)
for _, row in m1_summary.iterrows():
    print(f"  PUMA {row['value']}: {row['count']} records")

print("\n" + "=" * 70)
print("EXAMPLE 4: Imputation Metadata")
print("=" * 70)

# Get metadata for all variables
meta = get_imputation_metadata()
ne25_meta = meta[meta['study_id'] == 'ne25']

print(f"\n[OK] Found {len(ne25_meta)} imputed variables for ne25")
print("\nVariable details:")
for _, row in ne25_meta.iterrows():
    print(f"  {row['variable_name']}: {row['n_imputations']} imputations, method={row['imputation_method']}")

print("\n" + "=" * 70)
print("EXAMPLE 5: Validate Imputations")
print("=" * 70)

# Validate all imputation tables
results = validate_imputations(study_id='ne25')

if results['all_valid']:
    print(f"\n[OK] All {results['variables_checked']} variables validated successfully!")
else:
    print("\n[WARN] Validation issues found:")
    for issue in results['issues']:
        print(f"  - {issue}")

print("\n" + "=" * 70)
print("[OK] All examples completed successfully")
print("=" * 70)

"""
Advanced Multi-Study Queries - Cross-Study Analysis Examples

Demonstrates advanced patterns for comparing and combining data across
multiple independent studies in the imputation system.

Prerequisites:
- Multiple studies with imputations (ne25, ia26, etc.)
- Matching variable names across studies
- Completed imputation pipelines for each study
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(project_root))

from python.imputation.helpers import (
    get_completed_dataset,
    get_all_imputations,
    get_imputation_metadata,
    validate_imputations
)
import pandas as pd

print("=" * 70)
print("EXAMPLE 1: Compare Sample Sizes Across Studies")
print("=" * 70)

# Get metadata for all studies
all_meta = get_imputation_metadata()

# Summarize by study
study_summary = {}
for study_id in all_meta['study_id'].unique():
    # Get one imputation to check sample size
    df = get_completed_dataset(
        imputation_m=1,
        variables=['female'],  # Just need one variable
        study_id=study_id
    )
    study_summary[study_id] = len(df)

print("\n[INFO] Sample sizes by study:")
for study_id, n in sorted(study_summary.items()):
    print(f"  {study_id}: {n:,} participants")

print("\n" + "=" * 70)
print("EXAMPLE 2: Compare Variable Availability Across Studies")
print("=" * 70)

# Get imputed variables for each study
study_vars = {}
for study_id in all_meta['study_id'].unique():
    study_meta = all_meta[all_meta['study_id'] == study_id]
    study_vars[study_id] = set(study_meta['variable_name'].tolist())

# Find common variables
if len(study_vars) > 1:
    common_vars = set.intersection(*study_vars.values())
    print(f"\n[INFO] Variables imputed in ALL studies ({len(common_vars)}):")
    for var in sorted(common_vars):
        print(f"  - {var}")

    # Find study-specific variables
    print(f"\n[INFO] Study-specific variables:")
    for study_id, vars_set in sorted(study_vars.items()):
        unique_vars = vars_set - common_vars
        if unique_vars:
            print(f"  {study_id} only: {', '.join(sorted(unique_vars))}")
else:
    print("\n[INFO] Only one study available - cannot compare")

print("\n" + "=" * 70)
print("EXAMPLE 3: Combine Data Across Studies (Pooled Analysis)")
print("=" * 70)

# Note: This example assumes ne25 exists. Adapt for available studies.
available_studies = all_meta['study_id'].unique().tolist()

print(f"\n[INFO] Available studies: {', '.join(available_studies)}")

# Get common variables
common_vars = list(set.intersection(*study_vars.values())) if len(study_vars) > 1 else list(study_vars[available_studies[0]])

if len(common_vars) > 0:
    # Example: Pool 'female' and 'raceG' across studies
    pooling_vars = [v for v in ['female', 'raceG'] if v in common_vars]

    if pooling_vars:
        print(f"\n[INFO] Pooling variables: {', '.join(pooling_vars)}")

        # Get data from each study (imputation m=1)
        pooled_dfs = []
        for study_id in available_studies:
            df = get_completed_dataset(
                imputation_m=1,
                variables=pooling_vars,
                study_id=study_id
            )
            df['study'] = study_id  # Add study indicator
            pooled_dfs.append(df)

        # Combine
        pooled_data = pd.concat(pooled_dfs, ignore_index=True)

        print(f"  [OK] Pooled dataset: {len(pooled_data):,} total participants")
        print(f"\n  Distribution by study:")
        print(pooled_data['study'].value_counts().to_string())

        # Analyze pooled data
        if 'female' in pooled_data.columns:
            print(f"\n  Sex distribution (pooled):")
            print(pooled_data.groupby('study')['female'].value_counts(normalize=True).unstack().to_string())
    else:
        print("\n[INFO] No common demographic variables to pool")
else:
    print("\n[INFO] No common variables across studies")

print("\n" + "=" * 70)
print("EXAMPLE 4: Compare Imputation Uncertainty Across Studies")
print("=" * 70)

# For studies with same variables, compare how much variability across imputations
print("\n[INFO] Comparing geographic uncertainty across studies...")

for study_id in available_studies:
    # Check if study has geography variables
    study_meta = all_meta[all_meta['study_id'] == study_id]
    has_puma = 'puma' in study_meta['variable_name'].values

    if has_puma:
        # Get all M imputations
        df_long = get_all_imputations(
            variables=['puma'],
            study_id=study_id
        )

        # Calculate variability for each participant
        variability = df_long.groupby(['pid', 'record_id'])['puma'].nunique()
        uncertain = (variability > 1).sum()
        total = len(variability)

        print(f"\n  {study_id}:")
        print(f"    Participants with varying PUMA: {uncertain} / {total} ({100*uncertain/total:.1f}%)")
    else:
        print(f"\n  {study_id}: No PUMA variable imputed")

print("\n" + "=" * 70)
print("EXAMPLE 5: Study-Specific Analysis with Common Framework")
print("=" * 70)

# Demonstrate running the same analysis on multiple studies
def analyze_study(study_id):
    """Run standardized analysis for any study."""
    print(f"\n[INFO] Analyzing {study_id}...")

    # Get data
    df = get_completed_dataset(
        imputation_m=1,
        variables=None,  # Get all imputed variables
        study_id=study_id
    )

    # Identify imputed columns
    study_meta = all_meta[all_meta['study_id'] == study_id]
    imputed_vars = study_meta['variable_name'].tolist()

    # Calculate missingness before imputation (would need base data for real calc)
    print(f"  Sample size: {len(df):,}")
    print(f"  Imputed variables: {len(imputed_vars)}")

    # Example: Check for complete cases after imputation
    imputed_cols_in_df = [col for col in imputed_vars if col in df.columns]
    complete_cases = df[imputed_cols_in_df].notna().all(axis=1).sum()

    print(f"  Complete cases (imputed vars): {complete_cases:,} ({100*complete_cases/len(df):.1f}%)")

    return {
        'study_id': study_id,
        'n': len(df),
        'n_vars': len(imputed_vars),
        'pct_complete': 100 * complete_cases / len(df)
    }

# Run analysis on all studies
results = []
for study_id in available_studies:
    results.append(analyze_study(study_id))

# Summarize results
print(f"\n[INFO] Cross-study comparison:")
results_df = pd.DataFrame(results)
print(results_df.to_string(index=False))

print("\n" + "=" * 70)
print("EXAMPLE 6: Validate Consistency Across Studies")
print("=" * 70)

# Check that all studies pass validation
print("\n[INFO] Running validation for all studies...")

validation_results = {}
for study_id in available_studies:
    results = validate_imputations(study_id=study_id)
    validation_results[study_id] = results['all_valid']

    if results['all_valid']:
        print(f"  [OK] {study_id}: All {results['variables_checked']} variables validated")
    else:
        print(f"  [WARN] {study_id}: Validation issues:")
        for issue in results['issues']:
            print(f"    - {issue}")

# Overall status
all_valid = all(validation_results.values())
if all_valid:
    print(f"\n[OK] All {len(validation_results)} studies validated successfully!")
else:
    failed = [s for s, v in validation_results.items() if not v]
    print(f"\n[WARN] {len(failed)} studies have validation issues: {', '.join(failed)}")

print("\n" + "=" * 70)
print("EXAMPLE 7: Meta-Analysis Setup (Multiple Imputation)")
print("=" * 70)

# Demonstrate preparing data for meta-analysis with proper MI handling
print("\n[INFO] Preparing data for meta-analysis with Rubin's rules...")

# Example: Estimate sex distribution in each study, across all M imputations
def estimate_with_mi(study_id, variable='female'):
    """Estimate proportion with proper MI variance."""
    # Get all M imputations
    df_long = get_all_imputations(
        variables=[variable],
        study_id=study_id
    )

    # Calculate proportion in each imputation
    estimates = df_long.groupby('imputation_m')[variable].apply(
        lambda x: x.notna().sum() / len(x)  # Proportion non-missing
    )

    # Within-imputation variance (simplified - would need survey weights)
    Q_bar = estimates.mean()  # Pooled estimate
    U_bar = estimates.var()   # Within-imputation variance

    # Between-imputation variance
    B = estimates.var()

    # Total variance (Rubin's rules)
    M = len(estimates)
    T = U_bar + (1 + 1/M) * B

    return {
        'study_id': study_id,
        'estimate': Q_bar,
        'variance': T,
        'se': T ** 0.5
    }

# Run for available studies with 'female' variable
meta_data = []
for study_id in available_studies:
    study_meta = all_meta[all_meta['study_id'] == study_id]
    if 'female' in study_meta['variable_name'].values:
        meta_data.append(estimate_with_mi(study_id, 'female'))

if meta_data:
    meta_df = pd.DataFrame(meta_data)
    print("\n[INFO] Study-specific estimates (proportion female, with MI):")
    print(meta_df.to_string(index=False))

    print("\n[NOTE] These estimates can be combined using meta-analysis methods")
    print("       accounting for both within-study and between-study variance")
else:
    print("\n[INFO] No studies with 'female' variable for meta-analysis example")

print("\n" + "=" * 70)
print("[OK] Advanced multi-study examples completed")
print("=" * 70)

print("\n[NOTE] Adapt these examples for your specific research questions:")
print("  - Modify variable names to match your data")
print("  - Add survey weights for proper estimation")
print("  - Customize analysis functions for your outcomes")
print("  - Use mitools (R) or statsmodels (Python) for formal MI combination")

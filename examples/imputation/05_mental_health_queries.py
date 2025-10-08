"""
Mental Health & Parenting Query Examples

Demonstrates how to access and analyze adult mental health (PHQ-2, GAD-2)
and parenting self-efficacy (q1502) imputations from the Kidsights platform.

Variables Covered:
  - PHQ-2 items: phq2_interest, phq2_depressed
  - PHQ-2+ positive screen: phq2_positive (>= 3 cutoff)
  - GAD-2 items: gad2_nervous, gad2_worry
  - GAD-2+ positive screen: gad2_positive (>= 3 cutoff)
  - Parenting self-efficacy: q1502 (handling day-to-day demands)

All variables use 0-3 scale (Not at all to Nearly every day / Very well)
"""

import sys
from pathlib import Path
import pandas as pd
import numpy as np

# Add project root to path
project_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(project_root))

from python.imputation.helpers import (
    get_mental_health_imputations,
    get_complete_dataset
)

print("=" * 70)
print("EXAMPLE 1: Get Mental Health Variables (Single Imputation)")
print("=" * 70)

# Get mental health variables for imputation m=1 (includes base observed data)
# IMPORTANT: include_base_data=True merges imputed values with observed values
mh = get_mental_health_imputations(study_id='ne25', imputation_number=1, include_base_data=True)

print(f"\n[OK] Loaded {len(mh)} records with {len(mh.columns)} columns")
print(f"Mental health columns: {', '.join([c for c in mh.columns if c in ['phq2_interest', 'phq2_depressed', 'phq2_positive', 'gad2_nervous', 'gad2_worry', 'gad2_positive', 'q1502']])}")
print(f"\nFirst 5 records (mental health variables only):")
mh_vars = ['pid', 'record_id', 'phq2_interest', 'phq2_depressed', 'phq2_positive', 'gad2_nervous', 'gad2_worry', 'gad2_positive', 'q1502']
print(mh[mh_vars].head())

# Filter to non-null records (defensive filtering applied during imputation)
# Only eligible.x = TRUE AND authentic.x = TRUE records have mental health data
mh_complete = mh[mh['phq2_interest'].notna()].copy()
print(f"\n[INFO] Records with mental health data: {len(mh_complete)} / {len(mh)}")
print(f"      (Only eligible & authentic adult respondents have mental health data)")

print("\n" + "=" * 70)
print("EXAMPLE 2: PHQ-2 and GAD-2 Prevalence")
print("=" * 70)

# Calculate PHQ-2+ prevalence
phq2_pos_count = (mh_complete['phq2_positive'] == 1).sum()
phq2_pos_prev = phq2_pos_count / len(mh_complete) * 100

print(f"\nPHQ-2+ Positive Screen:")
print(f"  N = {phq2_pos_count} / {len(mh_complete)}")
print(f"  Prevalence = {phq2_pos_prev:.1f}%")

# Calculate GAD-2+ prevalence
gad2_pos_count = (mh_complete['gad2_positive'] == 1).sum()
gad2_pos_prev = gad2_pos_count / len(mh_complete) * 100

print(f"\nGAD-2+ Positive Screen:")
print(f"  N = {gad2_pos_count} / {len(mh_complete)}")
print(f"  Prevalence = {gad2_pos_prev:.1f}%")

# Calculate parenting self-efficacy mean
q1502_mean = mh_complete['q1502'].mean()
q1502_sd = mh_complete['q1502'].std()

print(f"\nParenting Self-Efficacy (q1502):")
print(f"  Mean = {q1502_mean:.2f} (SD = {q1502_sd:.2f}) on 0-3 scale")
print(f"  Higher scores = better self-efficacy")

print("\n" + "=" * 70)
print("EXAMPLE 3: Pooling Prevalence Estimates Across M=5 Imputations")
print("=" * 70)

# Get all M=5 imputations and pool prevalence estimates
phq2_prevalences = []
gad2_prevalences = []
q1502_means = []

for m in range(1, 6):
    mh_m = get_mental_health_imputations(study_id='ne25', imputation_number=m, include_base_data=True)
    mh_m_complete = mh_m[mh_m['phq2_interest'].notna()].copy()

    phq2_prev_m = (mh_m_complete['phq2_positive'] == 1).sum() / len(mh_m_complete) * 100
    gad2_prev_m = (mh_m_complete['gad2_positive'] == 1).sum() / len(mh_m_complete) * 100
    q1502_mean_m = mh_m_complete['q1502'].mean()

    phq2_prevalences.append(phq2_prev_m)
    gad2_prevalences.append(gad2_prev_m)
    q1502_means.append(q1502_mean_m)

    print(f"  m={m}: PHQ-2+ = {phq2_prev_m:.1f}%, GAD-2+ = {gad2_prev_m:.1f}%, q1502 = {q1502_mean_m:.2f}")

# Pooled estimates (simple average across imputations)
phq2_pooled_mean = np.mean(phq2_prevalences)
phq2_pooled_sd = np.std(phq2_prevalences, ddof=1)

gad2_pooled_mean = np.mean(gad2_prevalences)
gad2_pooled_sd = np.std(gad2_prevalences, ddof=1)

q1502_pooled_mean = np.mean(q1502_means)
q1502_pooled_sd = np.std(q1502_means, ddof=1)

print(f"\n[POOLED ESTIMATES]")
print(f"  PHQ-2+ prevalence: {phq2_pooled_mean:.1f}% (SD = {phq2_pooled_sd:.2f})")
print(f"  GAD-2+ prevalence: {gad2_pooled_mean:.1f}% (SD = {gad2_pooled_sd:.2f})")
print(f"  Parenting self-efficacy: {q1502_pooled_mean:.2f} (SD = {q1502_pooled_sd:.3f})")

print("\n" + "=" * 70)
print("EXAMPLE 4: Mental Health by Demographics (Imputation m=1)")
print("=" * 70)

# Merge mental health with base data for demographics
mh_demo = get_mental_health_imputations(
    study_id='ne25',
    imputation_number=1,
    include_base_data=True
)

# Filter to non-null mental health data
mh_demo_complete = mh_demo[mh_demo['phq2_interest'].notna()].copy()

print(f"\n[INFO] Analyzing {len(mh_demo_complete)} records with complete mental health data")

# PHQ-2+ by race/ethnicity
if 'a1_raceG' in mh_demo_complete.columns:
    print("\nPHQ-2+ Prevalence by Adult Race/Ethnicity:")
    phq2_by_race = mh_demo_complete.groupby('a1_raceG').agg({
        'phq2_positive': ['count', 'sum', 'mean']
    }).round(3)
    phq2_by_race.columns = ['N', 'N_positive', 'Prevalence']
    phq2_by_race['Prevalence'] = phq2_by_race['Prevalence'] * 100
    print(phq2_by_race)

# GAD-2+ by education
if 'educ_a1' in mh_demo_complete.columns:
    print("\nGAD-2+ Prevalence by Adult Education:")
    gad2_by_educ = mh_demo_complete.groupby('educ_a1').agg({
        'gad2_positive': ['count', 'sum', 'mean']
    }).round(3)
    gad2_by_educ.columns = ['N', 'N_positive', 'Prevalence']
    gad2_by_educ['Prevalence'] = gad2_by_educ['Prevalence'] * 100
    print(gad2_by_educ)

print("\n" + "=" * 70)
print("EXAMPLE 5: Correlation Analysis (Depression, Anxiety, Parenting)")
print("=" * 70)

# Calculate total scores
mh_complete['phq2_total'] = mh_complete['phq2_interest'] + mh_complete['phq2_depressed']
mh_complete['gad2_total'] = mh_complete['gad2_nervous'] + mh_complete['gad2_worry']

# Correlation matrix
corr_vars = ['phq2_total', 'gad2_total', 'q1502']
corr_matrix = mh_complete[corr_vars].corr().round(3)

print("\nCorrelation Matrix:")
print(corr_matrix)

print("\nInterpretation:")
phq_gad_corr = corr_matrix.loc['phq2_total', 'gad2_total']
phq_q1502_corr = corr_matrix.loc['phq2_total', 'q1502']
gad_q1502_corr = corr_matrix.loc['gad2_total', 'q1502']

print(f"  - PHQ-2 & GAD-2 correlation: r = {phq_gad_corr:.3f} (expect moderate-strong positive)")
print(f"  - PHQ-2 & Parenting Self-Efficacy: r = {phq_q1502_corr:.3f} (expect weak-moderate negative)")
print(f"  - GAD-2 & Parenting Self-Efficacy: r = {gad_q1502_corr:.3f} (expect weak-moderate negative)")

print("\n" + "=" * 70)
print("EXAMPLE 6: Get Complete Dataset with Mental Health")
print("=" * 70)

# Get ALL imputed variables including mental health
df_complete = get_complete_dataset(
    study_id='ne25',
    imputation_number=1,
    include_mental_health=True
)

print(f"\n[OK] Loaded {len(df_complete)} records with {len(df_complete.columns)} columns")
print(f"\nImputed variables included:")
print(f"  - Geography (3): puma, county, census_tract")
print(f"  - Sociodemographic (7): female, raceG, educ_mom, educ_a2, income, family_size, fplcat")
print(f"  - Childcare (4): cc_receives_care, cc_primary_type, cc_hours_per_week, childcare_10hrs_nonfamily")
print(f"  - Mental Health (7): phq2_interest, phq2_depressed, phq2_positive, gad2_nervous, gad2_worry, gad2_positive, q1502")
print(f"  - TOTAL: 21 imputed variables")

# Example analysis: PHQ-2+ by childcare arrangement
df_analysis = df_complete[df_complete['phq2_interest'].notna()].copy()

if 'cc_receives_care' in df_analysis.columns:
    print("\nPHQ-2+ Prevalence by Childcare Receipt:")
    phq2_by_cc = df_analysis.groupby('cc_receives_care').agg({
        'phq2_positive': ['count', 'sum', 'mean']
    }).round(3)
    phq2_by_cc.columns = ['N', 'N_positive', 'Prevalence']
    phq2_by_cc['Prevalence'] = phq2_by_cc['Prevalence'] * 100
    print(phq2_by_cc)

print("\n" + "=" * 70)
print("All examples completed successfully!")
print("=" * 70)

"""
Geography Imputation for NE25

Generates M imputations for records with geographic ambiguity by sampling
from afact probabilities.

Usage:
    python scripts/imputation/01_impute_geography.py
"""

import sys
from pathlib import Path
import numpy as np
import pandas as pd

# Add project root to path
# __file__ is scripts/imputation/ne25/01_impute_geography.py
# parent = ne25/, parent.parent = imputation/, parent.parent.parent = scripts/, parent.parent.parent.parent = project_root
project_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(project_root))

from python.db.connection import DatabaseManager
from python.imputation.config import get_study_config, get_n_imputations, get_random_seed, get_table_prefix


def parse_semicolon_delimited(value_str: str, afact_str: str):
    """
    Parse semicolon-delimited geography and afact strings

    Parameters
    ----------
    value_str : str
        Semicolon-delimited geography values (e.g., "00802; 00801")
    afact_str : str
        Semicolon-delimited afact probabilities (e.g., "0.8092 ; 0.1908 ")

    Returns
    -------
    tuple of (list of str, list of float)
        Geography values and corresponding probabilities

    Examples
    --------
    >>> values, probs = parse_semicolon_delimited("00802; 00801", "0.8092 ; 0.1908 ")
    >>> values
    ['00802', '00801']
    >>> probs
    [0.8092, 0.1908]
    """
    values = [v.strip() for v in value_str.split(';')]
    probs = [float(p.strip()) for p in afact_str.split(';')]

    # Normalize probabilities to sum to 1 (handle rounding errors)
    prob_sum = sum(probs)
    probs = [p / prob_sum for p in probs]

    return values, probs


def sample_geography(values, probs, n_imputations, random_state):
    """
    Sample geography assignments using afact probabilities

    Parameters
    ----------
    values : list of str
        Possible geography assignments
    probs : list of float
        Corresponding probabilities (must sum to 1)
    n_imputations : int
        Number of imputations to generate
    random_state : np.random.RandomState
        Random number generator for reproducibility

    Returns
    -------
    list of str
        Sampled geography values (length = n_imputations)
    """
    if len(values) == 1:
        # No ambiguity - return same value for all imputations
        return [values[0]] * n_imputations

    # Sample with replacement using probabilities
    samples = random_state.choice(values, size=n_imputations, p=probs)
    return samples.tolist()


def impute_geography_variable(
    db: DatabaseManager,
    study_id: str,
    variable_name: str,
    value_col: str,
    afact_col: str,
    n_imputations: int,
    random_seed: int
):
    """
    Impute a single geography variable for all ambiguous records

    Parameters
    ----------
    db : DatabaseManager
        Database connection manager
    study_id : str
        Study identifier (e.g., "ne25")
    variable_name : str
        Name of imputed variable (e.g., "puma", "county", "census_tract")
    value_col : str
        Column name for geography values in source table
    afact_col : str
        Column name for afact probabilities
    n_imputations : int
        Number of imputations to generate
    random_seed : int
        Random seed for reproducibility

    Returns
    -------
    int
        Number of records imputed
    """
    print(f"\n[INFO] Imputing {variable_name}...")

    # Get ambiguous records (those with semicolons in afact)
    with db.get_connection(read_only=True) as conn:
        ambiguous_records = conn.execute(f"""
            SELECT
                CAST(pid AS INTEGER) as pid,
                CAST(record_id AS INTEGER) as record_id,
                {value_col} as values,
                {afact_col} as afacts
            FROM ne25_transformed
            WHERE {afact_col} LIKE '%;%'
        """).df()

    n_ambiguous = len(ambiguous_records)
    print(f"  Found {n_ambiguous} records with {variable_name} ambiguity")

    if n_ambiguous == 0:
        print(f"  [SKIP] No ambiguous records for {variable_name}")
        return 0

    # Generate imputations
    random_state = np.random.RandomState(random_seed)
    imputation_rows = []

    for idx, row in ambiguous_records.iterrows():
        pid = row['pid']
        record_id = row['record_id']
        values_str = row['values']
        afacts_str = row['afacts']

        # Parse semicolon-delimited strings
        try:
            values, probs = parse_semicolon_delimited(values_str, afacts_str)
        except Exception as e:
            print(f"  [WARN] Failed to parse record {record_id}: {e}")
            print(f"        values='{values_str}', afacts='{afacts_str}'")
            continue

        # Sample M imputations
        samples = sample_geography(values, probs, n_imputations, random_state)

        # Create rows for database insertion
        for m, sampled_value in enumerate(samples, start=1):
            imputation_rows.append({
                'study_id': study_id,
                'pid': pid,
                'record_id': record_id,
                'imputation_m': m,
                variable_name: sampled_value
            })

    # Convert to DataFrame
    imputations_df = pd.DataFrame(imputation_rows)

    print(f"  Generated {len(imputations_df)} imputation rows ({n_ambiguous} records x {n_imputations} imputations)")

    # Insert into database
    table_prefix = get_table_prefix(study_id)
    table_name = f"{table_prefix}_{variable_name}"

    with db.get_connection() as conn:
        # Clear existing imputations for this study
        conn.execute(f"""
            DELETE FROM {table_name}
            WHERE study_id = '{study_id}'
        """)

        # Insert new imputations
        conn.execute(f"""
            INSERT INTO {table_name}
            SELECT * FROM imputations_df
        """)

    print(f"  [OK] Inserted {len(imputations_df)} rows into {table_name}")

    return n_ambiguous


def update_imputation_metadata(
    db: DatabaseManager,
    study_id: str,
    variable_name: str,
    n_imputations: int,
    n_records_imputed: int
):
    """
    Update or insert metadata for imputed variable

    Parameters
    ----------
    db : DatabaseManager
        Database connection manager
    study_id : str
        Study identifier (e.g., "ne25")
    variable_name : str
        Name of imputed variable
    n_imputations : int
        Number of imputations generated
    n_records_imputed : int
        Number of records with ambiguity
    """
    import json
    from datetime import datetime

    with db.get_connection() as conn:
        # Check if metadata exists
        exists = conn.execute(f"""
            SELECT COUNT(*) as count
            FROM imputation_metadata
            WHERE study_id = '{study_id}' AND variable_name = '{variable_name}'
        """).df()

        if exists['count'].iloc[0] > 0:
            # Update existing
            conn.execute(f"""
                UPDATE imputation_metadata
                SET n_imputations = {n_imputations},
                    created_date = CURRENT_TIMESTAMP,
                    created_by = '01_impute_geography.py',
                    notes = 'Sampled from afact probabilities for {n_records_imputed} ambiguous records'
                WHERE study_id = '{study_id}' AND variable_name = '{variable_name}'
            """)
        else:
            # Insert new
            conn.execute(f"""
                INSERT INTO imputation_metadata
                (study_id, variable_name, n_imputations, imputation_method, predictors, created_by, notes)
                VALUES (
                    '{study_id}',
                    '{variable_name}',
                    {n_imputations},
                    'probabilistic_allocation',
                    '["geocode_latitude", "geocode_longitude", "{variable_name}_afact"]',
                    '01_impute_geography.py',
                    'Sampled from afact probabilities for {n_records_imputed} ambiguous records'
                )
            """)


def main():
    """
    Main imputation workflow
    """
    print("Geography Imputation for NE25")
    print("=" * 60)

    # Load study-specific configuration
    study_id = "ne25"
    config = get_study_config(study_id)
    n_imputations = get_n_imputations()
    random_seed = get_random_seed()

    print(f"Configuration:")
    print(f"  Study: {config['study_name']}")
    print(f"  Study ID: {study_id}")
    print(f"  Number of imputations (M): {n_imputations}")
    print(f"  Random seed: {random_seed}")
    print(f"  Variables: {', '.join(config['geography']['variables'])}")

    # Connect to database
    db = DatabaseManager()
    print(f"\n[OK] Connected to database")

    # Impute each geography variable
    results = {}

    # PUMA
    n_puma = impute_geography_variable(
        db=db,
        study_id=study_id,
        variable_name='puma',
        value_col='puma',
        afact_col='puma_afact',
        n_imputations=n_imputations,
        random_seed=random_seed
    )
    results['puma'] = n_puma
    update_imputation_metadata(db, study_id, 'puma', n_imputations, n_puma)

    # County
    n_county = impute_geography_variable(
        db=db,
        study_id=study_id,
        variable_name='county',
        value_col='county',
        afact_col='county_afact',
        n_imputations=n_imputations,
        random_seed=random_seed
    )
    results['county'] = n_county
    update_imputation_metadata(db, study_id, 'county', n_imputations, n_county)

    # Census Tract
    n_tract = impute_geography_variable(
        db=db,
        study_id=study_id,
        variable_name='census_tract',
        value_col='tract',
        afact_col='tract_afact',
        n_imputations=n_imputations,
        random_seed=random_seed
    )
    results['census_tract'] = n_tract
    update_imputation_metadata(db, study_id, 'census_tract', n_imputations, n_tract)

    # Summary
    print("\n" + "=" * 60)
    print("Imputation Summary:")
    print(f"  PUMA: {results['puma']} records imputed")
    print(f"  County: {results['county']} records imputed")
    print(f"  Census Tract: {results['census_tract']} records imputed")
    print("\n[OK] Geography imputation complete!")

    print("\nNext steps:")
    print("  1. Validate: python scripts/imputation/02_validate_imputations.py")
    print("  2. Test helpers: python -m python.imputation.helpers")


if __name__ == "__main__":
    main()

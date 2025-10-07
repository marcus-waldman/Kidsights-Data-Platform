"""
Helper functions for working with multiple imputations

Provides functions to retrieve completed datasets by joining imputed variable
tables with base observed data.
"""

import pandas as pd
from typing import List, Optional
from python.db.connection import DatabaseManager
from .config import get_imputation_config, get_n_imputations


def get_completed_dataset(
    imputation_m: int,
    variables: Optional[List[str]] = None,
    base_table: str = "ne25_transformed",
    study_id: str = "ne25",
    include_observed: bool = True
) -> pd.DataFrame:
    """
    Construct a completed dataset for a specific imputation

    Parameters
    ----------
    imputation_m : int
        Which imputation to retrieve (1 to M)
    variables : list of str, optional
        Imputed variables to include. If None, includes all available.
    base_table : str, default "ne25_transformed"
        Base table with observed data
    study_id : str, default "ne25"
        Study identifier for filtering imputations
    include_observed : bool, default True
        Whether to include base observed data

    Returns
    -------
    pandas.DataFrame
        Completed dataset with observed + imputed values for imputation m

    Examples
    --------
    >>> # Get imputation 3 with geography only
    >>> df = get_completed_dataset(3, variables=['puma', 'county'])
    >>>
    >>> # Get imputation 5 with all imputed variables
    >>> df = get_completed_dataset(5)
    """
    db = DatabaseManager()

    # Validate imputation_m
    config = get_imputation_config()
    max_m = config['n_imputations']
    if imputation_m < 1 or imputation_m > max_m:
        raise ValueError(
            f"imputation_m must be between 1 and {max_m}, got {imputation_m}"
        )

    # Start with base data (if requested)
    if include_observed:
        with db.get_connection(read_only=True) as conn:
            base = conn.execute(f"SELECT * FROM {base_table}").df()
    else:
        with db.get_connection(read_only=True) as conn:
            base = conn.execute(f"SELECT pid, record_id FROM {base_table}").df()

    # Get list of available imputed variables
    if variables is None:
        with db.get_connection(read_only=True) as conn:
            meta = conn.execute("SELECT variable_name FROM imputation_metadata").df()
        variables = meta['variable_name'].tolist()

    # Join each imputed variable table
    for var in variables:
        query = f"""
            SELECT pid, record_id, {var}
            FROM imputed_{var}
            WHERE imputation_m = {imputation_m}
              AND study_id = '{study_id}'
        """

        with db.get_connection(read_only=True) as conn:
            imputed = conn.execute(query).df()

        # Left join: only ambiguous records are in imputed tables
        base = base.merge(imputed, on=['pid', 'record_id'], how='left', suffixes=('', '_imputed'))

        # Coalesce: use imputed value if available, else observed
        if f'{var}_imputed' in base.columns:
            base[var] = base[f'{var}_imputed'].fillna(base[var])
            base = base.drop(columns=[f'{var}_imputed'])

    return base


def get_all_imputations(
    variables: Optional[List[str]] = None,
    base_table: str = "ne25_transformed",
    study_id: str = "ne25"
) -> pd.DataFrame:
    """
    Get all imputations for specified variables in long format

    Parameters
    ----------
    variables : list of str, optional
        Imputed variables to include. If None, includes all.
    base_table : str, default "ne25_transformed"
        Base table with observed data
    study_id : str, default "ne25"
        Study identifier for filtering imputations

    Returns
    -------
    pandas.DataFrame
        Long-format data with imputation_m column

    Examples
    --------
    >>> # Get all geography imputations
    >>> df_long = get_all_imputations(variables=['puma', 'county'])
    >>>
    >>> # Analyze across imputations
    >>> df_long.groupby('imputation_m')['puma'].value_counts()
    """
    config = get_imputation_config()
    max_m = config['n_imputations']

    # Stack all imputations
    all_imputations = []
    for m in range(1, max_m + 1):
        df_m = get_completed_dataset(m, variables=variables, base_table=base_table, study_id=study_id)
        df_m['imputation_m'] = m
        all_imputations.append(df_m)

    return pd.concat(all_imputations, ignore_index=True)


def get_imputation_metadata() -> pd.DataFrame:
    """
    Get metadata about all imputed variables

    Returns
    -------
    pandas.DataFrame
        Metadata table with variable names, methods, creation dates

    Examples
    --------
    >>> meta = get_imputation_metadata()
    >>> print(meta[['variable_name', 'n_imputations', 'imputation_method']])
    """
    db = DatabaseManager()

    with db.get_connection(read_only=True) as conn:
        metadata = conn.execute("SELECT * FROM imputation_metadata").df()

    return metadata


def get_imputed_variable_summary(variable_name: str) -> pd.DataFrame:
    """
    Get summary statistics for an imputed variable across all imputations

    Parameters
    ----------
    variable_name : str
        Name of the imputed variable

    Returns
    -------
    pandas.DataFrame
        Summary with counts/frequencies across imputations

    Examples
    --------
    >>> summary = get_imputed_variable_summary('puma')
    >>> print(summary)
    """
    db = DatabaseManager()
    config = get_imputation_config()
    max_m = config['n_imputations']

    # Check if variable exists
    with db.get_connection(read_only=True) as conn:
        table_check = conn.execute(f"""
            SELECT COUNT(*) as count
            FROM information_schema.tables
            WHERE table_name = 'imputed_{variable_name}'
        """).df()

    if table_check['count'].iloc[0] == 0:
        raise ValueError(f"No imputation table found for variable: {variable_name}")

    # Get value counts across all imputations
    with db.get_connection(read_only=True) as conn:
        summary = conn.execute(f"""
            SELECT
                imputation_m,
                {variable_name} as value,
                COUNT(*) as count
            FROM imputed_{variable_name}
            GROUP BY imputation_m, {variable_name}
            ORDER BY imputation_m, count DESC
        """).df()

    return summary


def validate_imputations() -> dict:
    """
    Validate imputation tables for completeness and consistency

    Returns
    -------
    dict
        Validation results with any issues detected

    Examples
    --------
    >>> results = validate_imputations()
    >>> if results['all_valid']:
    ...     print("All imputations valid!")
    ... else:
    ...     print("Issues detected:", results['issues'])
    """
    db = DatabaseManager()
    config = get_imputation_config()
    expected_m = config['n_imputations']
    issues = []

    # Get list of imputed variables
    with db.get_connection(read_only=True) as conn:
        meta = conn.execute("SELECT variable_name FROM imputation_metadata").df()
    variables = meta['variable_name'].tolist()

    for var in variables:
        with db.get_connection(read_only=True) as conn:
            # Check number of imputations
            m_count = conn.execute(f"""
                SELECT COUNT(DISTINCT imputation_m) as count
                FROM imputed_{var}
            """).df()

            actual_m = m_count['count'].iloc[0]
            if actual_m != expected_m:
                issues.append(
                    f"{var}: Expected {expected_m} imputations, found {actual_m}"
                )

            # Check for NULL values
            null_check = conn.execute(f"""
                SELECT COUNT(*) as count
                FROM imputed_{var}
                WHERE {var} IS NULL
            """).df()

            null_count = null_check['count'].iloc[0]
            if null_count > 0:
                issues.append(
                    f"{var}: Found {null_count} NULL values"
                )

    return {
        'all_valid': len(issues) == 0,
        'expected_imputations': expected_m,
        'variables_checked': len(variables),
        'issues': issues
    }


if __name__ == "__main__":
    # Test helper functions
    print("Testing imputation helper functions...")
    print("=" * 60)

    # Test 1: Get metadata
    try:
        meta = get_imputation_metadata()
        print(f"[OK] Metadata table has {len(meta)} variables")
        if len(meta) > 0:
            print(f"     Variables: {', '.join(meta['variable_name'].tolist())}")
    except Exception as e:
        print(f"[FAIL] get_imputation_metadata: {e}")

    # Test 2: Validate imputations (will fail if no data yet)
    try:
        results = validate_imputations()
        if results['all_valid']:
            print(f"[OK] All {results['variables_checked']} variables validated")
        else:
            print(f"[WARN] Validation issues found:")
            for issue in results['issues']:
                print(f"     - {issue}")
    except Exception as e:
        print(f"[INFO] Validation skipped (no imputations yet): {e}")

    print("\n" + "=" * 60)
    print("Helper functions ready!")
    print("\nNext steps:")
    print("  1. Run: python scripts/imputation/01_impute_geography.py")
    print("  2. Then test: python -m python.imputation.helpers")

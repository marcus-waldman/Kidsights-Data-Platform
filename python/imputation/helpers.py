"""
Helper functions for working with multiple imputations

Provides functions to retrieve completed datasets by joining imputed variable
tables with base observed data.

Available Functions
-------------------
- get_completed_dataset(): Get a single imputation with all variables
- get_all_imputations(): Get all M imputations in long format
- get_geography_imputations(): Get geography variables (PUMA, county, census tract)
- get_sociodem_imputations(): Get sociodemographic variables (7 variables)
- get_childcare_imputations(): Get childcare variables (4 variables)
- get_mental_health_imputations(): Get mental health variables (7 variables)
- get_child_aces_imputations(): Get child ACEs variables (9 variables)
- get_complete_dataset(): Get ALL 30 imputed variables joined together
- get_imputation_metadata(): Get metadata about imputed variables
- get_imputed_variable_summary(): Get summary stats for a variable
- validate_imputations(): Validate imputation tables

Quick Examples
--------------
# Get complete dataset for imputation 1 (all 30 variables)
>>> df = get_complete_dataset(study_id='ne25', imputation_number=1)

# Get just mental health variables for imputation 2
>>> mental_health = get_mental_health_imputations(study_id='ne25', imputation_number=2)

# Get just child ACEs variables for imputation 3
>>> child_aces = get_child_aces_imputations(study_id='ne25', imputation_number=3)

# Validate all imputation tables
>>> results = validate_imputations(study_id='ne25')
"""

import pandas as pd
from typing import List, Optional
from python.db.connection import DatabaseManager
from .config import get_imputation_config, get_n_imputations, get_table_prefix


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
            meta = conn.execute(f"""
                SELECT variable_name
                FROM imputation_metadata
                WHERE study_id = '{study_id}'
            """).df()
        variables = meta['variable_name'].tolist()

    # Get table prefix for study-specific table names
    table_prefix = get_table_prefix(study_id)

    # Join each imputed variable table
    for var in variables:
        table_name = f"{table_prefix}_{var}"
        query = f"""
            SELECT pid, record_id, {var}
            FROM {table_name}
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


def get_geography_imputations(
    study_id: str = "ne25",
    imputation_number: int = 1
) -> pd.DataFrame:
    """
    Get geography imputations (PUMA, county, census_tract) for a specific imputation

    Parameters
    ----------
    study_id : str, default "ne25"
        Study identifier
    imputation_number : int, default 1
        Which imputation to retrieve (1 to M)

    Returns
    -------
    pandas.DataFrame
        Geography variables with pid, record_id

    Examples
    --------
    >>> geo = get_geography_imputations(study_id='ne25', imputation_number=1)
    >>> print(geo.columns)
    Index(['pid', 'record_id', 'puma', 'county', 'census_tract'], dtype='object')
    """
    geography_vars = ['puma', 'county', 'census_tract']
    return get_completed_dataset(
        imputation_m=imputation_number,
        variables=geography_vars,
        base_table=f"{study_id}_transformed",
        study_id=study_id,
        include_observed=False
    )


def get_sociodem_imputations(
    study_id: str = "ne25",
    imputation_number: int = 1
) -> pd.DataFrame:
    """
    Get sociodemographic imputations for a specific imputation

    Parameters
    ----------
    study_id : str, default "ne25"
        Study identifier
    imputation_number : int, default 1
        Which imputation to retrieve (1 to M)

    Returns
    -------
    pandas.DataFrame
        Sociodem variables (female, raceG, educ_mom, educ_a2, income,
        family_size, fplcat) with pid, record_id

    Examples
    --------
    >>> sociodem = get_sociodem_imputations(study_id='ne25', imputation_number=2)
    >>> print(sociodem.columns)
    Index(['pid', 'record_id', 'female', 'raceG', 'educ_mom', 'educ_a2',
           'income', 'family_size', 'fplcat'], dtype='object')
    """
    sociodem_vars = ['female', 'raceG', 'educ_mom', 'educ_a2', 'income', 'family_size', 'fplcat']
    return get_completed_dataset(
        imputation_m=imputation_number,
        variables=sociodem_vars,
        base_table=f"{study_id}_transformed",
        study_id=study_id,
        include_observed=False
    )


def get_childcare_imputations(
    study_id: str = "ne25",
    imputation_number: int = 1
) -> pd.DataFrame:
    """
    Get childcare imputations for a specific imputation

    Parameters
    ----------
    study_id : str, default "ne25"
        Study identifier
    imputation_number : int, default 1
        Which imputation to retrieve (1 to M)

    Returns
    -------
    pandas.DataFrame
        Childcare variables (cc_receives_care, cc_primary_type,
        cc_hours_per_week, childcare_10hrs_nonfamily) with pid, record_id

    Notes
    -----
    - cc_receives_care is imputed for all eligible records
    - cc_primary_type and cc_hours_per_week are conditionally imputed
      (only for records where cc_receives_care = "Yes")
    - childcare_10hrs_nonfamily is derived from the above variables

    Examples
    --------
    >>> childcare = get_childcare_imputations(study_id='ne25', imputation_number=3)
    >>> print(childcare.columns)
    Index(['pid', 'record_id', 'cc_receives_care', 'cc_primary_type',
           'cc_hours_per_week', 'childcare_10hrs_nonfamily'], dtype='object')

    >>> # Check conditional structure
    >>> childcare[childcare['cc_receives_care'] == 'No']['cc_primary_type'].isna().sum()
    # Should be high - type/hours only imputed for "Yes" responses
    """
    childcare_vars = ['cc_receives_care', 'cc_primary_type', 'cc_hours_per_week', 'childcare_10hrs_nonfamily']
    return get_completed_dataset(
        imputation_m=imputation_number,
        variables=childcare_vars,
        base_table=f"{study_id}_transformed",
        study_id=study_id,
        include_observed=False
    )


def get_mental_health_imputations(
    study_id: str = "ne25",
    imputation_number: int = 1,
    include_base_data: bool = False
) -> pd.DataFrame:
    """
    Get adult mental health and parenting imputations for a specific imputation

    Parameters
    ----------
    study_id : str, default "ne25"
        Study identifier
    imputation_number : int, default 1
        Which imputation to retrieve (1 to M)
    include_base_data : bool, default False
        If True, merge with ne25_transformed base data

    Returns
    -------
    pandas.DataFrame
        Mental health variables (phq2_interest, phq2_depressed, phq2_positive,
        gad2_nervous, gad2_worry, gad2_positive, q1502) with pid, record_id

    Notes
    -----
    - PHQ-2 items (phq2_interest, phq2_depressed): 0-3 scale (Not at all to Nearly every day)
    - GAD-2 items (gad2_nervous, gad2_worry): 0-3 scale (Not at all to Nearly every day)
    - PHQ-2+ positive screen: phq2_interest + phq2_depressed >= 3
    - GAD-2+ positive screen: gad2_nervous + gad2_worry >= 3
    - q1502 (parenting self-efficacy): 0-3 scale (Not very well to Very well)
    - Only eligible.x = TRUE AND authentic.x = TRUE records are imputed

    Examples
    --------
    >>> # Get mental health variables for imputation 1
    >>> mh = get_mental_health_imputations(study_id='ne25', imputation_number=1)
    >>> print(mh.columns)
    Index(['pid', 'record_id', 'phq2_interest', 'phq2_depressed', 'phq2_positive',
           'gad2_nervous', 'gad2_worry', 'gad2_positive', 'q1502'], dtype='object')

    >>> # Check PHQ-2+ prevalence
    >>> mh['phq2_positive'].value_counts(normalize=True)
    False    0.891
    True     0.109
    Name: phq2_positive, dtype: float64

    >>> # Merge with base data for demographics
    >>> mh_full = get_mental_health_imputations(study_id='ne25', imputation_number=1,
    ...                                          include_base_data=True)
    >>> # Analyze PHQ-2+ by race/ethnicity
    >>> mh_full.groupby('a1_raceG')['phq2_positive'].value_counts(normalize=True)
    """
    mental_health_vars = [
        'phq2_interest', 'phq2_depressed', 'phq2_positive',
        'gad2_nervous', 'gad2_worry', 'gad2_positive',
        'q1502'
    ]
    return get_completed_dataset(
        imputation_m=imputation_number,
        variables=mental_health_vars,
        base_table=f"{study_id}_transformed",
        study_id=study_id,
        include_observed=include_base_data
    )


def get_child_aces_imputations(
    study_id: str = "ne25",
    imputation_number: int = 1,
    include_base_data: bool = False
) -> pd.DataFrame:
    """
    Get child ACEs (Adverse Childhood Experiences) imputations for a specific imputation

    Parameters
    ----------
    study_id : str, default "ne25"
        Study identifier
    imputation_number : int, default 1
        Which imputation to retrieve (1 to M)
    include_base_data : bool, default False
        If True, merge with ne25_transformed base data

    Returns
    -------
    pandas.DataFrame
        Child ACEs variables (8 ACE items + child_ace_total) with pid, record_id

    Notes
    -----
    - 8 binary ACE items (0/1): parent_divorce, parent_death, parent_jail,
      domestic_violence, neighborhood_violence, mental_illness,
      substance_use, discrimination
    - child_ace_total: Sum of 8 items (0-8 scale)
    - Only eligible.x = TRUE AND authentic.x = TRUE records are imputed
    - Imputation method: Random forest (method="rf")

    Examples
    --------
    >>> # Get child ACEs for imputation 1
    >>> aces = get_child_aces_imputations(study_id='ne25', imputation_number=1)
    >>> print(aces.columns)
    Index(['pid', 'record_id', 'child_ace_parent_divorce', 'child_ace_parent_death',
           'child_ace_parent_jail', 'child_ace_domestic_violence',
           'child_ace_neighborhood_violence', 'child_ace_mental_illness',
           'child_ace_substance_use', 'child_ace_discrimination', 'child_ace_total'],
          dtype='object')

    >>> # Check 4+ ACEs prevalence
    >>> pct_4plus = (aces['child_ace_total'] >= 4).mean() * 100
    >>> print(f"4+ ACEs prevalence: {pct_4plus:.1f}%")
    4+ ACEs prevalence: 4.4%

    >>> # Cross-tabulate by demographics (with base data)
    >>> aces_full = get_child_aces_imputations(study_id='ne25', imputation_number=1,
    ...                                         include_base_data=True)
    >>> # Analyze by race/ethnicity
    >>> aces_full.groupby('a1_raceG')['child_ace_total'].mean()
    """
    child_ace_vars = [
        'child_ace_parent_divorce',
        'child_ace_parent_death',
        'child_ace_parent_jail',
        'child_ace_domestic_violence',
        'child_ace_neighborhood_violence',
        'child_ace_mental_illness',
        'child_ace_substance_use',
        'child_ace_discrimination',
        'child_ace_total'
    ]
    return get_completed_dataset(
        imputation_m=imputation_number,
        variables=child_ace_vars,
        base_table=f"{study_id}_transformed",
        study_id=study_id,
        include_observed=include_base_data
    )


def get_complete_dataset(
    study_id: str = "ne25",
    imputation_number: int = 1,
    include_base_data: bool = False,
    include_mental_health: bool = True,
    include_child_aces: bool = True
) -> pd.DataFrame:
    """
    Get complete dataset with ALL imputed variables joined together

    This is the primary function for analysis-ready datasets. It joins:
    - Geography (3 variables): puma, county, census_tract
    - Sociodemographic (7 variables): female, raceG, educ_mom, educ_a2,
      income, family_size, fplcat
    - Childcare (4 variables): cc_receives_care, cc_primary_type,
      cc_hours_per_week, childcare_10hrs_nonfamily
    - Mental Health (7 variables, optional): phq2_interest, phq2_depressed, phq2_positive,
      gad2_nervous, gad2_worry, gad2_positive, q1502
    - Child ACEs (9 variables, optional): 8 ACE items + child_ace_total

    Parameters
    ----------
    study_id : str, default "ne25"
        Study identifier
    imputation_number : int, default 1
        Which imputation to retrieve (1 to M)
    include_base_data : bool, default False
        If True, includes all columns from base transformed table
    include_mental_health : bool, default True
        If True, includes mental health and parenting variables
    include_child_aces : bool, default True
        If True, includes child ACEs variables

    Returns
    -------
    pandas.DataFrame
        Complete dataset with pid, record_id and all 30 imputed variables (or subsets based on include_* params)

    Examples
    --------
    >>> # Get complete imputation 1 (30 variables: all stages)
    >>> df = get_complete_dataset(study_id='ne25', imputation_number=1)
    >>> print(df.shape)
    (3908, 32)  # pid, record_id + 30 imputed variables

    >>> # Get without mental health and child ACEs (14 variables)
    >>> df_no_mh_aces = get_complete_dataset(study_id='ne25', imputation_number=1,
    ...                                       include_mental_health=False,
    ...                                       include_child_aces=False)
    >>> print(df_no_mh_aces.shape)
    (3908, 16)  # pid, record_id + 14 imputed variables

    >>> # Get with base data for additional covariates
    >>> df_full = get_complete_dataset(study_id='ne25', imputation_number=1,
    ...                                 include_base_data=True)
    >>> print(df_full.shape)
    (3908, 150+)  # All transformed variables + 30 imputations

    >>> # Verify all 30 variables present
    >>> imputed_vars = ['puma', 'county', 'census_tract', 'female', 'raceG',
    ...                 'educ_mom', 'educ_a2', 'income', 'family_size', 'fplcat',
    ...                 'cc_receives_care', 'cc_primary_type', 'cc_hours_per_week',
    ...                 'childcare_10hrs_nonfamily', 'phq2_interest', 'phq2_depressed',
    ...                 'phq2_positive', 'gad2_nervous', 'gad2_worry', 'gad2_positive', 'q1502',
    ...                 'child_ace_parent_divorce', 'child_ace_parent_death', 'child_ace_parent_jail',
    ...                 'child_ace_domestic_violence', 'child_ace_neighborhood_violence',
    ...                 'child_ace_mental_illness', 'child_ace_substance_use',
    ...                 'child_ace_discrimination', 'child_ace_total']
    >>> all(var in df.columns for var in imputed_vars)
    True
    """
    all_imputed_vars = [
        # Geography (3)
        'puma', 'county', 'census_tract',
        # Sociodemographic (7)
        'female', 'raceG', 'educ_mom', 'educ_a2', 'income', 'family_size', 'fplcat',
        # Childcare (4)
        'cc_receives_care', 'cc_primary_type', 'cc_hours_per_week', 'childcare_10hrs_nonfamily'
    ]

    # Add mental health variables if requested
    if include_mental_health:
        all_imputed_vars.extend([
            # Mental Health & Parenting (7)
            'phq2_interest', 'phq2_depressed', 'phq2_positive',
            'gad2_nervous', 'gad2_worry', 'gad2_positive',
            'q1502'
        ])

    # Add child ACEs variables if requested
    if include_child_aces:
        all_imputed_vars.extend([
            # Child ACEs (9)
            'child_ace_parent_divorce', 'child_ace_parent_death',
            'child_ace_parent_jail', 'child_ace_domestic_violence',
            'child_ace_neighborhood_violence', 'child_ace_mental_illness',
            'child_ace_substance_use', 'child_ace_discrimination',
            'child_ace_total'
        ])

    return get_completed_dataset(
        imputation_m=imputation_number,
        variables=all_imputed_vars,
        base_table=f"{study_id}_transformed",
        study_id=study_id,
        include_observed=include_base_data
    )


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


def get_imputed_variable_summary(variable_name: str, study_id: str = "ne25") -> pd.DataFrame:
    """
    Get summary statistics for an imputed variable across all imputations

    Parameters
    ----------
    variable_name : str
        Name of the imputed variable
    study_id : str, default "ne25"
        Study identifier for filtering imputations

    Returns
    -------
    pandas.DataFrame
        Summary with counts/frequencies across imputations

    Examples
    --------
    >>> summary = get_imputed_variable_summary('puma', study_id='ne25')
    >>> print(summary)
    """
    db = DatabaseManager()
    config = get_imputation_config()
    max_m = config['n_imputations']

    # Get table prefix for study-specific table names
    table_prefix = get_table_prefix(study_id)
    table_name = f"{table_prefix}_{variable_name}"

    # Check if variable exists
    with db.get_connection(read_only=True) as conn:
        table_check = conn.execute(f"""
            SELECT COUNT(*) as count
            FROM information_schema.tables
            WHERE table_name = '{table_name}'
        """).df()

    if table_check['count'].iloc[0] == 0:
        raise ValueError(f"No imputation table found for variable: {variable_name} (table: {table_name})")

    # Get value counts across all imputations
    with db.get_connection(read_only=True) as conn:
        summary = conn.execute(f"""
            SELECT
                imputation_m,
                {variable_name} as value,
                COUNT(*) as count
            FROM {table_name}
            WHERE study_id = '{study_id}'
            GROUP BY imputation_m, {variable_name}
            ORDER BY imputation_m, count DESC
        """).df()

    return summary


def validate_imputations(study_id: str = "ne25") -> dict:
    """
    Validate imputation tables for completeness and consistency

    Parameters
    ----------
    study_id : str, default "ne25"
        Study identifier for filtering imputations

    Returns
    -------
    dict
        Validation results with any issues detected

    Examples
    --------
    >>> results = validate_imputations(study_id='ne25')
    >>> if results['all_valid']:
    ...     print("All imputations valid!")
    ... else:
    ...     print("Issues detected:", results['issues'])
    """
    db = DatabaseManager()
    config = get_imputation_config()
    expected_m = config['n_imputations']
    issues = []

    # Get table prefix for study-specific table names
    table_prefix = get_table_prefix(study_id)

    # Get list of imputed variables for this study
    with db.get_connection(read_only=True) as conn:
        meta = conn.execute(f"""
            SELECT variable_name
            FROM imputation_metadata
            WHERE study_id = '{study_id}'
        """).df()
    variables = meta['variable_name'].tolist()

    for var in variables:
        table_name = f"{table_prefix}_{var}"
        with db.get_connection(read_only=True) as conn:
            # Check number of imputations
            m_count = conn.execute(f"""
                SELECT COUNT(DISTINCT imputation_m) as count
                FROM {table_name}
                WHERE study_id = '{study_id}'
            """).df()

            actual_m = m_count['count'].iloc[0]
            if actual_m != expected_m:
                issues.append(
                    f"{var}: Expected {expected_m} imputations, found {actual_m}"
                )

            # Check for NULL values (should be 0 - NULLs are filtered before saving)
            # Space-efficient design: only complete imputed/derived values are stored
            # Records without complete auxiliary variables are excluded from tables
            null_check = conn.execute(f"""
                SELECT COUNT(*) as count
                FROM {table_name}
                WHERE study_id = '{study_id}' AND {var} IS NULL
            """).df()

            null_count = null_check['count'].iloc[0]
            if null_count > 0:
                issues.append(
                    f"{var}: Found {null_count} NULL values (should be 0 - NULLs filtered before save)"
                )

            # Childcare-specific validation
            if var == 'cc_receives_care':
                # Check for valid values (should be "Yes" or "No")
                valid_check = conn.execute(f"""
                    SELECT COUNT(*) as count
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                      AND {var} NOT IN ('Yes', 'No')
                """).df()
                invalid_count = valid_check['count'].iloc[0]
                if invalid_count > 0:
                    issues.append(
                        f"{var}: Found {invalid_count} invalid values (must be 'Yes' or 'No')"
                    )

            elif var == 'cc_primary_type':
                # Check for valid childcare types (from NE25 codebook)
                valid_types = [
                    'Relative care',
                    'Non-relative care',
                    'Childcare center',
                    'Preschool program',
                    'Head Start/Early Head Start',
                    'Other'
                ]
                valid_list = "', '".join(valid_types)
                valid_check = conn.execute(f"""
                    SELECT COUNT(*) as count
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                      AND {var} NOT IN ('{valid_list}')
                """).df()
                invalid_count = valid_check['count'].iloc[0]
                if invalid_count > 0:
                    issues.append(
                        f"{var}: Found {invalid_count} invalid values (must be one of: {', '.join(valid_types)})"
                    )

            elif var == 'cc_hours_per_week':
                # Check for reasonable hour ranges (0-168 hours per week)
                range_check = conn.execute(f"""
                    SELECT COUNT(*) as count
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                      AND ({var} < 0 OR {var} > 168)
                """).df()
                invalid_count = range_check['count'].iloc[0]
                if invalid_count > 0:
                    issues.append(
                        f"{var}: Found {invalid_count} values outside valid range (0-168 hours/week)"
                    )

            elif var == 'childcare_10hrs_nonfamily':
                # Check for valid boolean values (0 or 1)
                bool_check = conn.execute(f"""
                    SELECT COUNT(*) as count
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                      AND {var} NOT IN (0, 1)
                """).df()
                invalid_count = bool_check['count'].iloc[0]
                if invalid_count > 0:
                    issues.append(
                        f"{var}: Found {invalid_count} invalid values (must be 0 or 1)"
                    )

            # Mental health item validation (PHQ-2 and GAD-2 items)
            elif var in ['phq2_interest', 'phq2_depressed', 'gad2_nervous', 'gad2_worry', 'q1502']:
                # Check for valid range (0-3)
                range_check = conn.execute(f"""
                    SELECT COUNT(*) as count
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                      AND ({var} < 0 OR {var} > 3)
                """).df()
                invalid_count = range_check['count'].iloc[0]
                if invalid_count > 0:
                    issues.append(
                        f"{var}: Found {invalid_count} values outside valid range (0-3)"
                    )

            # Mental health positive screen validation
            elif var in ['phq2_positive', 'gad2_positive']:
                # Check for valid boolean values
                bool_check = conn.execute(f"""
                    SELECT COUNT(*) as count
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                      AND {var} NOT IN (0, 1)
                """).df()
                invalid_count = bool_check['count'].iloc[0]
                if invalid_count > 0:
                    issues.append(
                        f"{var}: Found {invalid_count} invalid values (must be 0 or 1)"
                    )

                # Verify positive screen derivation consistency (check sample)
                if var == 'phq2_positive':
                    # PHQ-2+ should be TRUE when phq2_interest + phq2_depressed >= 3
                    consistency_check = conn.execute(f"""
                        SELECT COUNT(*) as count
                        FROM {table_prefix}_phq2_interest i
                        JOIN {table_prefix}_phq2_depressed d
                          ON i.pid = d.pid AND i.record_id = d.record_id AND i.imputation_m = d.imputation_m
                        JOIN {table_name} p
                          ON i.pid = p.pid AND i.record_id = p.record_id AND i.imputation_m = p.imputation_m
                        WHERE i.study_id = '{study_id}'
                          AND ((i.phq2_interest + d.phq2_depressed >= 3 AND p.phq2_positive = 0)
                            OR (i.phq2_interest + d.phq2_depressed < 3 AND p.phq2_positive = 1))
                    """).df()
                    inconsistent_count = consistency_check['count'].iloc[0]
                    if inconsistent_count > 0:
                        issues.append(
                            f"{var}: Found {inconsistent_count} inconsistent positive screen derivations"
                        )

                elif var == 'gad2_positive':
                    # GAD-2+ should be TRUE when gad2_nervous + gad2_worry >= 3
                    consistency_check = conn.execute(f"""
                        SELECT COUNT(*) as count
                        FROM {table_prefix}_gad2_nervous n
                        JOIN {table_prefix}_gad2_worry w
                          ON n.pid = w.pid AND n.record_id = w.record_id AND n.imputation_m = w.imputation_m
                        JOIN {table_name} g
                          ON n.pid = g.pid AND n.record_id = g.record_id AND n.imputation_m = g.imputation_m
                        WHERE n.study_id = '{study_id}'
                          AND ((n.gad2_nervous + w.gad2_worry >= 3 AND g.gad2_positive = 0)
                            OR (n.gad2_nervous + w.gad2_worry < 3 AND g.gad2_positive = 1))
                    """).df()
                    inconsistent_count = consistency_check['count'].iloc[0]
                    if inconsistent_count > 0:
                        issues.append(
                            f"{var}: Found {inconsistent_count} inconsistent positive screen derivations"
                        )

            # Child ACE item validation (binary 0/1)
            elif var in ['child_ace_parent_divorce', 'child_ace_parent_death', 'child_ace_parent_jail',
                         'child_ace_domestic_violence', 'child_ace_neighborhood_violence',
                         'child_ace_mental_illness', 'child_ace_substance_use', 'child_ace_discrimination']:
                # Check for valid boolean values (0 or 1)
                bool_check = conn.execute(f"""
                    SELECT COUNT(*) as count
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                      AND {var} NOT IN (0, 1)
                """).df()
                invalid_count = bool_check['count'].iloc[0]
                if invalid_count > 0:
                    issues.append(
                        f"{var}: Found {invalid_count} invalid values (must be 0 or 1)"
                    )

            # Child ACE total validation (0-8 scale)
            elif var == 'child_ace_total':
                # Check for valid range (0-8)
                range_check = conn.execute(f"""
                    SELECT COUNT(*) as count
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                      AND ({var} < 0 OR {var} > 8)
                """).df()
                invalid_count = range_check['count'].iloc[0]
                if invalid_count > 0:
                    issues.append(
                        f"{var}: Found {invalid_count} values outside valid range (0-8)"
                    )

            # Check for duplicates (pid, record_id, imputation_m should be unique)
            dup_check = conn.execute(f"""
                SELECT COUNT(*) as dup_count
                FROM (
                    SELECT pid, record_id, imputation_m, COUNT(*) as n
                    FROM {table_name}
                    WHERE study_id = '{study_id}'
                    GROUP BY pid, record_id, imputation_m
                    HAVING COUNT(*) > 1
                ) duplicates
            """).df()

            dup_count = dup_check['dup_count'].iloc[0]
            if dup_count > 0:
                issues.append(
                    f"{var}: Found {dup_count} duplicate (pid, record_id, imputation_m) combinations"
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
            print(f"     - No NULL values found")
            print(f"     - All childcare values within valid ranges")
            print(f"     - No duplicate records")
        else:
            print(f"[WARN] Validation issues found:")
            for issue in results['issues']:
                print(f"     - {issue}")
    except Exception as e:
        print(f"[INFO] Validation skipped (no imputations yet): {e}")

    # Test 3: Test childcare imputations retrieval (if data exists)
    try:
        childcare = get_childcare_imputations(study_id='ne25', imputation_number=1)
        print(f"[OK] Childcare imputations retrieved: {len(childcare)} records")
        print(f"     Variables: {', '.join([c for c in childcare.columns if c not in ['pid', 'record_id']])}")
    except Exception as e:
        print(f"[INFO] Childcare test skipped: {e}")

    # Test 4: Test complete dataset retrieval (if data exists)
    try:
        complete = get_complete_dataset(study_id='ne25', imputation_number=1)
        imputed_vars = [c for c in complete.columns if c not in ['pid', 'record_id']]
        print(f"[OK] Complete dataset retrieved: {len(complete)} records, {len(imputed_vars)} imputed variables")
    except Exception as e:
        print(f"[INFO] Complete dataset test skipped: {e}")

    # Test 5: Test mental health imputations retrieval (if data exists)
    try:
        mh = get_mental_health_imputations(study_id='ne25', imputation_number=1)
        print(f"[OK] Mental health imputations retrieved: {len(mh)} records")
        print(f"     Variables: {', '.join([c for c in mh.columns if c not in ['pid', 'record_id']])}")

        # Show PHQ-2+ and GAD-2+ prevalence
        if 'phq2_positive' in mh.columns:
            phq2_prev = (mh['phq2_positive'] == 1).sum() / len(mh) * 100
            gad2_prev = (mh['gad2_positive'] == 1).sum() / len(mh) * 100
            print(f"     PHQ-2+ prevalence: {phq2_prev:.1f}%")
            print(f"     GAD-2+ prevalence: {gad2_prev:.1f}%")
    except Exception as e:
        print(f"[INFO] Mental health test skipped: {e}")

    # Test 6: Test child ACEs imputations retrieval (if data exists)
    try:
        aces = get_child_aces_imputations(study_id='ne25', imputation_number=1)
        print(f"[OK] Child ACEs imputations retrieved: {len(aces)} records")
        print(f"     Variables: {', '.join([c for c in aces.columns if c not in ['pid', 'record_id']])}")

        # Show 4+ ACEs prevalence
        if 'child_ace_total' in aces.columns:
            pct_4plus = (aces['child_ace_total'] >= 4).mean() * 100
            print(f"     4+ ACEs prevalence: {pct_4plus:.1f}%")
    except Exception as e:
        print(f"[INFO] Child ACEs test skipped: {e}")

    print("\n" + "=" * 60)
    print("Helper functions ready!")
    print("\nQuick Usage Examples:")
    print("  # Get complete dataset (all 30 variables)")
    print("  df = get_complete_dataset(study_id='ne25', imputation_number=1)")
    print("")
    print("  # Get just mental health variables")
    print("  mh = get_mental_health_imputations(study_id='ne25', imputation_number=1)")
    print("")
    print("  # Get just child ACEs variables")
    print("  aces = get_child_aces_imputations(study_id='ne25', imputation_number=1)")
    print("")
    print("  # Get just childcare variables")
    print("  childcare = get_childcare_imputations(study_id='ne25', imputation_number=1)")
    print("")
    print("  # Validate all imputations")
    print("  results = validate_imputations(study_id='ne25')")

"""
Configuration loader for imputation pipeline

Provides a single source of truth for imputation parameters across all scripts.
"""

import yaml
from pathlib import Path
from typing import Dict, Any


def get_imputation_config(config_path: str = None) -> Dict[str, Any]:
    """
    Load imputation configuration from YAML file

    Parameters
    ----------
    config_path : str, optional
        Path to config file. If None, uses default location.

    Returns
    -------
    dict
        Configuration dictionary with imputation parameters

    Examples
    --------
    >>> config = get_imputation_config()
    >>> print(f"Number of imputations: {config['n_imputations']}")
    Number of imputations: 5

    >>> # Access nested settings
    >>> geo_vars = config['geography']['variables']
    >>> print(geo_vars)
    ['puma', 'county', 'census_tract']
    """
    if config_path is None:
        # Default location: config/imputation/imputation_config.yaml
        project_root = Path(__file__).parent.parent.parent
        config_path = project_root / "config" / "imputation" / "imputation_config.yaml"
    else:
        config_path = Path(config_path)

    if not config_path.exists():
        raise FileNotFoundError(
            f"Imputation config file not found: {config_path}\n"
            f"Expected location: config/imputation/imputation_config.yaml"
        )

    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)

    # Validate required fields
    required_fields = ['n_imputations', 'random_seed', 'geography', 'database']
    missing_fields = [field for field in required_fields if field not in config]

    if missing_fields:
        raise ValueError(
            f"Missing required fields in config: {', '.join(missing_fields)}"
        )

    return config


def get_n_imputations() -> int:
    """
    Get the number of imputations (M) from config

    Returns
    -------
    int
        Number of imputations to generate

    Examples
    --------
    >>> M = get_n_imputations()
    >>> print(M)
    5
    """
    config = get_imputation_config()
    return config['n_imputations']


def get_random_seed() -> int:
    """
    Get the random seed for reproducibility

    Returns
    -------
    int or None
        Random seed value, or None for non-reproducible runs

    Examples
    --------
    >>> seed = get_random_seed()
    >>> import numpy as np
    >>> np.random.seed(seed)
    """
    config = get_imputation_config()
    return config['random_seed']


if __name__ == "__main__":
    # Test configuration loading
    config = get_imputation_config()
    print("Imputation Configuration:")
    print(f"  Number of imputations (M): {config['n_imputations']}")
    print(f"  Random seed: {config['random_seed']}")
    print(f"  Geography variables: {', '.join(config['geography']['variables'])}")
    print(f"  Database path: {config['database']['db_path']}")

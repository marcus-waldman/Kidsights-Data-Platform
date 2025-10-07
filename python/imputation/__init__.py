"""
Imputation module for the Kidsights Data Platform

This module provides functionality for multiple imputation of missing and
uncertain values, particularly geographic variables with allocation factor
uncertainty.
"""

from .config import (
    get_imputation_config,
    get_n_imputations,
    get_random_seed,
    get_study_config,
    get_table_prefix
)
from .helpers import (
    get_completed_dataset,
    get_all_imputations,
    get_imputation_metadata,
    get_imputed_variable_summary,
    validate_imputations
)

__all__ = [
    'get_imputation_config',
    'get_n_imputations',
    'get_random_seed',
    'get_study_config',
    'get_table_prefix',
    'get_completed_dataset',
    'get_all_imputations',
    'get_imputation_metadata',
    'get_imputed_variable_summary',
    'validate_imputations'
]

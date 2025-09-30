"""
ACS Data Pipeline - Python Utilities

This package provides core utilities for extracting American Community Survey (ACS)
data from IPUMS USA API for statistical raking procedures.

Modules:
    auth: IPUMS API authentication and client initialization
    config_manager: YAML configuration loading and validation
    extract_builder: Build IPUMS extract requests from configuration
    cache_manager: Intelligent caching system to avoid re-downloading extracts
    extract_manager: Submit, monitor, and download IPUMS extracts
    data_loader: Load IPUMS data and convert to Feather format

Usage:
    from python.acs.auth import get_client
    from python.acs.config_manager import get_state_config
    from python.acs.extract_manager import get_or_submit_extract
    from python.acs.data_loader import load_and_convert
"""

__version__ = "1.0.0"
__author__ = "Kidsights Data Platform"

# Version info
VERSION = __version__

# Convenience imports
from python.acs.auth import get_client, read_api_key
from python.acs.config_manager import get_state_config, load_config, validate_config
from python.acs.extract_manager import get_or_submit_extract
from python.acs.data_loader import load_and_convert, load_ipums_data, convert_to_feather

__all__ = [
    'get_client',
    'read_api_key',
    'get_state_config',
    'load_config',
    'validate_config',
    'get_or_submit_extract',
    'load_and_convert',
    'load_ipums_data',
    'convert_to_feather',
]

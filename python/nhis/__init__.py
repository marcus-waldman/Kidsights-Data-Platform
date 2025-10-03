"""
NHIS Data Pipeline Module

Provides functionality for extracting National Health Interview Survey (NHIS) data
from the IPUMS Health Surveys API, including:
- API authentication and extract submission
- Configuration management
- Smart caching with SHA256-based content addressing
- Data loading and validation
- Database operations

Author: Kidsights Data Platform
Created: 2025-10-03
"""

__version__ = "1.0.0"

# Module exports
__all__ = [
    "get_ipums_client",
    "ConfigManager",
    "ExtractBuilder",
    "ExtractManager",
    "CacheManager",
    "load_nhis_data",
]

# Lazy imports to avoid circular dependencies
def __getattr__(name):
    if name == "get_ipums_client":
        from .auth import get_ipums_client
        return get_ipums_client
    elif name == "ConfigManager":
        from .config_manager import ConfigManager
        return ConfigManager
    elif name == "ExtractBuilder":
        from .extract_builder import ExtractBuilder
        return ExtractBuilder
    elif name == "ExtractManager":
        from .extract_manager import ExtractManager
        return ExtractManager
    elif name == "CacheManager":
        from .cache_manager import CacheManager
        return CacheManager
    elif name == "load_nhis_data":
        from .data_loader import load_nhis_data
        return load_nhis_data
    raise AttributeError(f"module '{__name__}' has no attribute '{name}'")

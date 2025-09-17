"""
Kidsights Database Module

Centralized database operations for the Kidsights Data Platform.
Provides clean interfaces for DuckDB operations without segmentation faults.
"""

from .connection import DatabaseManager
from .operations import DatabaseOperations
from .config import load_config

__all__ = ['DatabaseManager', 'DatabaseOperations', 'load_config']
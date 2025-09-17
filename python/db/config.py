"""
Configuration loader for Kidsights database operations.

Reads configuration from YAML files and provides centralized access
to database settings, paths, and other configuration values.
"""

import os
import yaml
from pathlib import Path
from typing import Dict, Any, Optional
from dotenv import load_dotenv


def load_config(config_path: str = "config/sources/ne25.yaml") -> Dict[str, Any]:
    """
    Load configuration from YAML file.

    Args:
        config_path: Path to configuration file relative to project root

    Returns:
        Dictionary containing configuration values

    Raises:
        FileNotFoundError: If config file doesn't exist
        yaml.YAMLError: If config file is invalid YAML
    """
    # Load environment variables
    load_dotenv()

    # Find project root (directory containing config/)
    project_root = find_project_root()
    config_file = project_root / config_path

    if not config_file.exists():
        raise FileNotFoundError(f"Configuration file not found: {config_file}")

    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
    except yaml.YAMLError as e:
        raise yaml.YAMLError(f"Error parsing configuration file: {e}")

    # Resolve relative paths
    config = _resolve_paths(config, project_root)

    return config


def find_project_root(start_path: Optional[Path] = None) -> Path:
    """
    Find the project root directory by looking for config/ directory.

    Args:
        start_path: Directory to start search from (defaults to current working directory)

    Returns:
        Path to project root directory

    Raises:
        FileNotFoundError: If project root cannot be found
    """
    if start_path is None:
        start_path = Path.cwd()

    current = Path(start_path).resolve()

    # Look for config directory going up the tree
    while current != current.parent:
        if (current / "config").exists():
            return current
        current = current.parent

    raise FileNotFoundError("Could not find project root (directory containing config/)")


def _resolve_paths(config: Dict[str, Any], project_root: Path) -> Dict[str, Any]:
    """
    Resolve relative paths in configuration to absolute paths.

    Args:
        config: Configuration dictionary
        project_root: Project root directory

    Returns:
        Configuration with resolved paths
    """
    if 'output' in config and 'database_path' in config['output']:
        db_path = Path(config['output']['database_path'])
        if not db_path.is_absolute():
            config['output']['database_path'] = str(project_root / db_path)

    return config


def get_database_path(config: Optional[Dict[str, Any]] = None) -> str:
    """
    Get the database path from configuration.

    Args:
        config: Configuration dictionary (loads default if None)

    Returns:
        Absolute path to database file
    """
    if config is None:
        config = load_config()

    return config['output']['database_path']


def get_api_credentials_file(config: Optional[Dict[str, Any]] = None) -> str:
    """
    Get the API credentials file path from configuration.

    Args:
        config: Configuration dictionary (loads default if None)

    Returns:
        Path to API credentials file
    """
    if config is None:
        config = load_config()

    return config['redcap']['api_credentials_file']


def get_projects_config(config: Optional[Dict[str, Any]] = None) -> list:
    """
    Get the projects configuration from YAML.

    Args:
        config: Configuration dictionary (loads default if None)

    Returns:
        List of project configurations
    """
    if config is None:
        config = load_config()

    return config['redcap']['projects']
"""
IPUMS API Authentication Module

Handles IPUMS API key management and client initialization for the ACS pipeline.

Functions:
    read_api_key: Read IPUMS API key from file
    initialize_ipums_client: Create and configure IpumsApiClient instance
    get_client: Convenience function to get authenticated client (cached)
"""

import structlog
from pathlib import Path
from typing import Optional
from ipumspy import IpumsApiClient

# Configure structured logging
log = structlog.get_logger()

# Global client cache (singleton pattern)
_CLIENT_CACHE: Optional[IpumsApiClient] = None
_API_KEY_CACHE: Optional[str] = None


def read_api_key(api_key_path: str = "C:/Users/waldmanm/my-APIs/IPUMS.txt") -> str:
    """Read IPUMS API key from file.

    Args:
        api_key_path: Path to file containing IPUMS API key.
            Default: C:/Users/waldmanm/my-APIs/IPUMS.txt

    Returns:
        str: IPUMS API key (whitespace stripped)

    Raises:
        FileNotFoundError: If API key file doesn't exist
        ValueError: If API key file is empty or invalid format

    Example:
        >>> api_key = read_api_key()
        >>> print(f"API key length: {len(api_key)}")
        API key length: 56
    """
    key_file = Path(api_key_path)

    log.debug("Reading IPUMS API key", path=api_key_path)

    if not key_file.exists():
        log.error("IPUMS API key file not found", path=api_key_path)
        raise FileNotFoundError(
            f"IPUMS API key file not found: {api_key_path}\n\n"
            f"Please create this file with your IPUMS API key.\n"
            f"Get your API key from: https://account.ipums.org/api_keys"
        )

    # Read and strip whitespace
    with open(key_file, 'r', encoding='utf-8') as f:
        api_key = f.read().strip()

    if not api_key:
        log.error("IPUMS API key file is empty", path=api_key_path)
        raise ValueError(
            f"IPUMS API key file is empty: {api_key_path}\n"
            f"Please add your IPUMS API key to this file.\n"
            f"Get your API key from: https://account.ipums.org/api_keys"
        )

    # Basic validation: IPUMS API keys are typically 56 characters
    if len(api_key) < 20:
        log.warning(
            "IPUMS API key seems unusually short",
            length=len(api_key),
            expected_length=56
        )

    log.info("IPUMS API key loaded successfully", key_length=len(api_key))
    return api_key


def initialize_ipums_client(
    api_key: Optional[str] = None,
    api_key_path: str = "C:/Users/waldmanm/my-APIs/IPUMS.txt"
) -> IpumsApiClient:
    """Initialize IPUMS API client with error handling.

    Args:
        api_key: IPUMS API key string. If None, will read from api_key_path.
        api_key_path: Path to API key file. Only used if api_key is None.

    Returns:
        IpumsApiClient: Initialized and authenticated IPUMS API client

    Raises:
        FileNotFoundError: If API key file doesn't exist (when api_key is None)
        ValueError: If API key is invalid or empty
        Exception: If client initialization fails

    Example:
        >>> client = initialize_ipums_client()
        >>> # Client is ready to use for extract requests
    """
    # Get API key if not provided
    if api_key is None:
        log.debug("No API key provided, reading from file")
        api_key = read_api_key(api_key_path)

    # Initialize client
    log.debug("Initializing IPUMS API client")

    try:
        client = IpumsApiClient(api_key)
        log.info("IPUMS API client initialized successfully")
        return client

    except ValueError as e:
        log.error("Invalid IPUMS API key format", error=str(e))
        raise ValueError(
            f"Failed to initialize IPUMS API client: {e}\n\n"
            f"Troubleshooting:\n"
            f"  1. Verify your API key is correct\n"
            f"  2. API keys should be ~56 characters long\n"
            f"  3. Get a new key from: https://account.ipums.org/api_keys"
        ) from e

    except Exception as e:
        log.error("Failed to initialize IPUMS API client", error=str(e), error_type=type(e).__name__)
        raise Exception(
            f"Failed to initialize IPUMS API client: {e}\n\n"
            f"Troubleshooting:\n"
            f"  1. Verify ipumspy is installed: pip install ipumspy\n"
            f"  2. Check you have registered for IPUMS USA: https://usa.ipums.org/\n"
            f"  3. Verify network connectivity"
        ) from e


def get_client(
    force_new: bool = False,
    api_key_path: str = "C:/Users/waldmanm/my-APIs/IPUMS.txt"
) -> IpumsApiClient:
    """Get IPUMS API client (cached singleton).

    This function provides a cached client instance to avoid re-initializing
    for multiple API calls within the same session.

    Args:
        force_new: If True, create a new client instance even if cached
        api_key_path: Path to API key file

    Returns:
        IpumsApiClient: Initialized IPUMS API client

    Example:
        >>> # First call reads API key and creates client
        >>> client1 = get_client()
        >>>
        >>> # Subsequent calls return cached client (fast)
        >>> client2 = get_client()
        >>> assert client1 is client2  # Same instance
    """
    global _CLIENT_CACHE, _API_KEY_CACHE

    # Return cached client if available
    if not force_new and _CLIENT_CACHE is not None:
        log.debug("Using cached IPUMS API client")
        return _CLIENT_CACHE

    # Create new client
    log.debug("Creating new IPUMS API client")
    api_key = read_api_key(api_key_path)
    client = initialize_ipums_client(api_key=api_key)

    # Cache for future use
    _CLIENT_CACHE = client
    _API_KEY_CACHE = api_key

    return client


def clear_client_cache():
    """Clear cached API client and key.

    Useful for testing or when switching between different IPUMS accounts.

    Example:
        >>> client1 = get_client()
        >>> clear_client_cache()
        >>> client2 = get_client()  # Will create new client
        >>> assert client1 is not client2
    """
    global _CLIENT_CACHE, _API_KEY_CACHE

    log.debug("Clearing IPUMS API client cache")
    _CLIENT_CACHE = None
    _API_KEY_CACHE = None


# Convenience functions for common operations
def get_api_key(api_key_path: str = "C:/Users/waldmanm/my-APIs/IPUMS.txt") -> str:
    """Get API key (cached).

    Returns:
        str: IPUMS API key
    """
    global _API_KEY_CACHE

    if _API_KEY_CACHE is None:
        _API_KEY_CACHE = read_api_key(api_key_path)

    return _API_KEY_CACHE

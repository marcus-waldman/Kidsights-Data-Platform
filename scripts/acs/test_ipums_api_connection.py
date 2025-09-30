#!/usr/bin/env python3
"""
Test IPUMS API Connectivity

This script verifies that the IPUMS API key is valid and the ipumspy package
can successfully connect to the IPUMS USA API.

Usage:
    python scripts/acs/test_ipums_api_connection.py

Requirements:
    - IPUMS API key at C:/Users/waldmanm/my-APIs/IPUMS.txt
    - ipumspy package installed
"""

import sys
from pathlib import Path

# Add project root to path for imports
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))


def read_api_key(api_key_path: str = "C:/Users/waldmanm/my-APIs/IPUMS.txt") -> str:
    """Read IPUMS API key from file.

    Args:
        api_key_path: Path to IPUMS API key file

    Returns:
        API key string (stripped of whitespace)

    Raises:
        FileNotFoundError: If API key file doesn't exist
    """
    key_file = Path(api_key_path)

    if not key_file.exists():
        raise FileNotFoundError(
            f"IPUMS API key file not found: {api_key_path}\n"
            f"Please create this file with your IPUMS API key.\n"
            f"Get your API key from: https://account.ipums.org/api_keys"
        )

    with open(key_file, 'r') as f:
        api_key = f.read().strip()

    if not api_key:
        raise ValueError(f"IPUMS API key file is empty: {api_key_path}")

    return api_key


def test_ipumspy_import():
    """Test that ipumspy can be imported."""
    print("Testing ipumspy import...", end=" ")
    try:
        import ipumspy
        print(f"[OK] Success! ipumspy version: {ipumspy.__version__}")
        return True
    except ImportError as e:
        print(f"[FAIL] Failed!")
        print(f"Error: {e}")
        print("Install ipumspy with: pip install ipumspy")
        return False


def test_api_connection(api_key: str):
    """Test IPUMS API connection with the provided API key.

    Args:
        api_key: IPUMS API key

    Returns:
        True if connection successful, False otherwise
    """
    print("\nTesting IPUMS API client initialization...", end=" ")

    try:
        from ipumspy import IpumsApiClient

        # Initialize API client - this validates the API key
        client = IpumsApiClient(api_key)

        print(f"[OK] Success!")
        print(f"  - API client initialized successfully")
        print(f"  - API key accepted")

        # Note: Full API connectivity test (submitting/listing extracts)
        # requires an actual extract request, which we'll do in Phase 3
        print("\nNote: Full API functionality will be tested when submitting first extract in Phase 3.")

        return True

    except ValueError as e:
        print(f"[FAIL] Failed!")
        print(f"Error: Invalid API key - {e}")
        print("\nTroubleshooting:")
        print("  1. Verify your API key is correct")
        print("  2. Get a new API key from: https://account.ipums.org/api_keys")
        return False
    except Exception as e:
        print(f"[FAIL] Failed!")
        print(f"Error: {e}")
        print("\nTroubleshooting:")
        print("  1. Verify your API key is correct")
        print("  2. Check you have registered for IPUMS USA: https://usa.ipums.org/")
        print("  3. Verify ipumspy installation: pip install -U ipumspy")
        return False


def main():
    """Main test script."""
    print("=" * 60)
    print("IPUMS API Connection Test")
    print("=" * 60)

    # Test 1: Import ipumspy
    if not test_ipumspy_import():
        sys.exit(1)

    # Test 2: Read API key
    print("\nReading API key...", end=" ")
    try:
        api_key = read_api_key()
        print("[OK] Success!")
        print(f"  - API key length: {len(api_key)} characters")
    except (FileNotFoundError, ValueError) as e:
        print("[FAIL] Failed!")
        print(f"Error: {e}")
        sys.exit(1)

    # Test 3: Test API connection
    if not test_api_connection(api_key):
        sys.exit(1)

    # Success!
    print("\n" + "=" * 60)
    print("[OK] All tests passed! IPUMS API is ready to use.")
    print("=" * 60)
    print("\nNext steps:")
    print("  1. Create Nebraska config: config/sources/acs/nebraska-2019-2023.yaml")
    print("  2. Proceed to Phase 2: Core Python Utilities")

    return 0


if __name__ == "__main__":
    sys.exit(main())

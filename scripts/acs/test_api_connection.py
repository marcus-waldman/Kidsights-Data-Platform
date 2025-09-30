"""
ACS API Connection Test

Quick test to verify IPUMS API connection and submit a small test extract.
Uses Nebraska 2021 1-year sample for fast processing (~5-15 minutes).

Usage:
    # Test API connection only
    python scripts/acs/test_api_connection.py --test-connection

    # Submit test extract
    python scripts/acs/test_api_connection.py --submit-test

    # Check test extract status
    python scripts/acs/test_api_connection.py --check-status usa:12345

    # Full test workflow
    python scripts/acs/test_api_connection.py --full-test

Author: Kidsights Data Platform
Date: 2025-09-30
"""

import argparse
import sys
from pathlib import Path
from datetime import datetime

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from python.acs.auth import get_client
from python.acs.config_manager import get_state_config
from python.acs.extract_builder import build_extract_from_config
from python.acs.extract_manager import submit_extract, check_extract_status


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Test IPUMS API connection",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Test connection
  python scripts/acs/test_api_connection.py --test-connection

  # Submit test extract
  python scripts/acs/test_api_connection.py --submit-test

  # Full workflow
  python scripts/acs/test_api_connection.py --full-test
        """
    )

    parser.add_argument(
        "--test-connection",
        action="store_true",
        help="Test API connection only"
    )

    parser.add_argument(
        "--submit-test",
        action="store_true",
        help="Submit test extract (Nebraska 2021)"
    )

    parser.add_argument(
        "--check-status",
        type=str,
        metavar="EXTRACT_ID",
        help="Check status of extract (e.g., usa:12345)"
    )

    parser.add_argument(
        "--full-test",
        action="store_true",
        help="Run full test workflow (connection + submit)"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    return parser.parse_args()


def test_connection() -> bool:
    """Test IPUMS API connection.

    Returns:
        True if connection successful
    """
    print("\n" + "=" * 70)
    print("TEST 1: API CONNECTION")
    print("=" * 70)

    try:
        print("\nConnecting to IPUMS API...")
        client = get_client()

        print("[OK] Successfully connected to IPUMS API")
        print(f"     Client: {client}")

        return True

    except Exception as e:
        print(f"[FAIL] API connection failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def submit_test_extract() -> dict:
    """Submit test extract for Nebraska 2021.

    Returns:
        Dict with extract submission results
    """
    print("\n" + "=" * 70)
    print("TEST 2: SUBMIT TEST EXTRACT")
    print("=" * 70)

    try:
        print("\nLoading test configuration...")
        config = get_state_config("nebraska", "2021", validate=True)

        print(f"[OK] Configuration loaded")
        print(f"     State: {config.get('state')}")
        print(f"     Sample: {config.get('acs_sample')}")
        print(f"     Year Range: {config.get('year_range')}")

        print("\nBuilding extract request...")
        extract = build_extract_from_config(config)

        print(f"[OK] Extract built")
        print(f"     Variables: {len([v for group in config.get('variables', {}).values() for v in group])}")

        print("\nSubmitting extract to IPUMS API...")
        print("     (This may take a moment...)")

        client = get_client()
        extract_id = submit_extract(client, extract)

        print(f"\n[OK] Extract submitted successfully!")
        print(f"     Extract ID: {extract_id}")
        print(f"     Status: Queued for processing")
        print(f"\nEstimated processing time: 5-15 minutes")
        print(f"Check status with: python scripts/acs/test_api_connection.py --check-status {extract_id}")

        return {
            'success': True,
            'extract_id': extract_id,
            'config': config
        }

    except Exception as e:
        print(f"\n[FAIL] Extract submission failed: {e}")
        import traceback
        traceback.print_exc()
        return {
            'success': False,
            'error': str(e)
        }


def check_status(extract_id: str) -> dict:
    """Check status of extract.

    Args:
        extract_id: IPUMS extract ID

    Returns:
        Dict with status information
    """
    print("\n" + "=" * 70)
    print(f"CHECKING EXTRACT STATUS: {extract_id}")
    print("=" * 70)

    try:
        print("\nConnecting to IPUMS API...")
        client = get_client()

        print("Checking extract status...")
        status = check_extract_status(client, extract_id)

        print(f"\n[OK] Extract status retrieved")
        print(f"     Extract ID: {extract_id}")
        print(f"     Status: {status.get('status', 'Unknown')}")

        if status.get('status') == 'completed':
            print(f"\n[OK] Extract is ready for download!")
            print(f"     Download with: python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2021")
        elif status.get('status') == 'failed':
            print(f"\n[FAIL] Extract processing failed")
            print(f"     Error: {status.get('error_message', 'Unknown error')}")
        else:
            print(f"\n[PENDING] Extract is still processing")
            print(f"     Check again in a few minutes")

        return {
            'success': True,
            'status': status
        }

    except Exception as e:
        print(f"\n[FAIL] Status check failed: {e}")
        import traceback
        traceback.print_exc()
        return {
            'success': False,
            'error': str(e)
        }


def run_full_test() -> bool:
    """Run full test workflow.

    Returns:
        True if all tests pass
    """
    print("\n" + "=" * 70)
    print("ACS API FULL TEST WORKFLOW")
    print("=" * 70)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    all_passed = True

    # Test 1: Connection
    if not test_connection():
        all_passed = False
        print("\n[FAIL] Connection test failed, stopping tests")
        return False

    # Test 2: Submit extract
    result = submit_test_extract()
    if not result.get('success'):
        all_passed = False
        print("\n[FAIL] Extract submission failed")
        return False

    # Summary
    print("\n" + "=" * 70)
    if all_passed:
        print("[OK] ALL TESTS PASSED")
        print("=" * 70)
        print(f"\nTest extract submitted: {result.get('extract_id')}")
        print(f"\nNext steps:")
        print(f"  1. Wait 5-15 minutes for processing")
        print(f"  2. Check status: python scripts/acs/test_api_connection.py --check-status {result.get('extract_id')}")
        print(f"  3. Download: python pipelines/python/acs/extract_acs_data.py --state nebraska --year-range 2021")
    else:
        print("[FAIL] SOME TESTS FAILED")
        print("=" * 70)

    return all_passed


def main():
    """Main test workflow."""
    args = parse_arguments()

    # Test connection
    if args.test_connection:
        success = test_connection()
        return 0 if success else 1

    # Submit test extract
    if args.submit_test:
        result = submit_test_extract()
        return 0 if result.get('success') else 1

    # Check status
    if args.check_status:
        result = check_status(args.check_status)
        return 0 if result.get('success') else 1

    # Full test
    if args.full_test:
        success = run_full_test()
        return 0 if success else 1

    # Default: show help
    print("No test specified. Use --help for usage information.")
    print("\nQuick tests:")
    print("  --test-connection    Test IPUMS API connection")
    print("  --submit-test        Submit test extract")
    print("  --full-test          Run all tests")
    return 1


if __name__ == "__main__":
    sys.exit(main())

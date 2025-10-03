"""
Test Error Handling for NSCH SPSS Loader

Tests that the spss_loader functions handle errors appropriately:
1. Non-existent file
2. Invalid filename format
3. Invalid/corrupted SPSS file

Usage:
    python scripts/nsch/test_error_handling.py
"""

import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from python.nsch.spss_loader import (
    get_year_from_filename,
    read_spss_file
)


def test_nonexistent_file():
    """Test handling of non-existent file."""
    print("\n[TEST] Non-existent file...")
    try:
        read_spss_file("data/nsch/spss/nonexistent.sav")
        print("[FAIL] Should have raised FileNotFoundError")
        return False
    except FileNotFoundError as e:
        print(f"[OK] Caught FileNotFoundError: {str(e)[:60]}...")
        return True


def test_invalid_filename():
    """Test handling of invalid filename format."""
    print("\n[TEST] Invalid filename format...")
    try:
        get_year_from_filename("invalid_filename.sav")
        print("[FAIL] Should have raised ValueError")
        return False
    except ValueError as e:
        print(f"[OK] Caught ValueError: {str(e)[:60]}...")
        return True


def test_invalid_file_content():
    """Test handling of invalid/corrupted SPSS file."""
    print("\n[TEST] Invalid file content...")

    # Create a dummy non-SPSS file
    test_file = Path("data/nsch/spss/test_invalid.txt")
    test_file.write_text("This is not an SPSS file")

    try:
        read_spss_file(str(test_file))
        print("[FAIL] Should have raised Exception")
        test_file.unlink()  # Clean up
        return False
    except Exception as e:
        print(f"[OK] Caught Exception: {str(e)[:60]}...")
        test_file.unlink()  # Clean up
        return True


def main():
    print("[INFO] Testing NSCH SPSS Loader Error Handling")
    print("=" * 60)

    results = []

    # Run tests
    results.append(test_nonexistent_file())
    results.append(test_invalid_filename())
    results.append(test_invalid_file_content())

    print("\n" + "=" * 60)
    if all(results):
        print("[SUCCESS] All error handling tests passed!")
        print("=" * 60)
        return 0
    else:
        print("[FAIL] Some error handling tests failed")
        print("=" * 60)
        return 1


if __name__ == "__main__":
    sys.exit(main())

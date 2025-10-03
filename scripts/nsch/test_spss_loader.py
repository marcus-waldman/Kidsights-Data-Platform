"""
Test Script for NSCH SPSS Loader

Tests the spss_loader module with 2023 NSCH data:
1. Parse year from filename
2. Read SPSS file
3. Extract variable metadata
4. Extract value labels
5. Optionally export metadata to JSON

Usage:
    python scripts/nsch/test_spss_loader.py
    python scripts/nsch/test_spss_loader.py --export-metadata
"""

import sys
import argparse
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from python.nsch.spss_loader import (
    get_year_from_filename,
    read_spss_file,
    extract_variable_metadata,
    extract_value_labels,
    save_metadata_json
)


def main():
    parser = argparse.ArgumentParser(description="Test NSCH SPSS Loader")
    parser.add_argument("--export-metadata", action="store_true", help="Export metadata to JSON")
    args = parser.parse_args()

    # Test file path
    spss_file = "data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav"

    print("[INFO] Testing NSCH SPSS Loader")
    print("=" * 60)

    # Test 1: Parse year from filename
    print("\n[TEST 1] Parse year from filename...")
    year = get_year_from_filename(spss_file)
    print(f"[OK] Parsed year: {year}")
    assert year == 2023, f"Expected year 2023, got {year}"

    # Test 2: Read SPSS file
    print("\n[TEST 2] Read SPSS file...")
    df, meta = read_spss_file(spss_file)
    print(f"[OK] DataFrame shape: {df.shape}")
    print(f"[OK] Records: {len(df):,}")
    print(f"[OK] Variables: {len(df.columns)}")

    # Test 3: Extract variable metadata
    print("\n[TEST 3] Extract variable metadata...")
    var_metadata = extract_variable_metadata(meta)
    print(f"[OK] Variable metadata extracted: {len(var_metadata)} variables")

    # Show sample variable metadata
    print("\n[INFO] Sample variable metadata (first 5):")
    for i, (var_name, var_info) in enumerate(list(var_metadata.items())[:5]):
        print(f"  {var_name}:")
        print(f"    Label: {var_info.get('label', 'N/A')}")
        print(f"    Has value labels: {var_info.get('has_value_labels', False)}")

    # Test 4: Extract value labels
    print("\n[TEST 4] Extract value labels...")
    value_labels = extract_value_labels(meta)
    print(f"[OK] Value labels extracted: {len(value_labels)} variables with labels")

    # Show sample value labels
    print("\n[INFO] Sample value labels (first variable with labels):")
    for var_name, labels in list(value_labels.items())[:1]:
        print(f"  {var_name}:")
        for value, label in list(labels.items())[:5]:
            print(f"    {value}: {label}")
        if len(labels) > 5:
            print(f"    ... ({len(labels) - 5} more values)")

    # Test 5: Export metadata (optional)
    if args.export_metadata:
        print("\n[TEST 5] Export metadata to JSON...")
        output_path = f"data/nsch/{year}/metadata.json"
        save_metadata_json(
            year=year,
            file_name=Path(spss_file).name,
            df=df,
            var_metadata=var_metadata,
            value_labels=value_labels,
            output_path=output_path
        )
        print(f"[OK] Metadata exported to: {output_path}")

        # Verify JSON file exists and is valid
        import json
        with open(output_path, 'r') as f:
            metadata = json.load(f)

        print(f"[OK] JSON file is valid")
        print(f"[INFO] Metadata fields:")
        print(f"  Year: {metadata['year']}")
        print(f"  Records: {metadata['record_count']:,}")
        print(f"  Variables: {metadata['variable_count']}")
        print(f"  Extracted: {metadata['extracted_date']}")

    print("\n" + "=" * 60)
    print("[SUCCESS] All tests passed!")
    print("=" * 60)


if __name__ == "__main__":
    main()

"""
NSCH SPSS to Feather Conversion Pipeline

Main pipeline script that:
1. Reads NSCH SPSS file for specified year
2. Extracts comprehensive metadata
3. Saves metadata to JSON
4. Converts data to Feather format
5. Validates round-trip conversion
6. Prints summary statistics

Usage:
    python pipelines/python/nsch/load_nsch_spss.py --year 2023
    python pipelines/python/nsch/load_nsch_spss.py --year 2023 --overwrite
    python pipelines/python/nsch/load_nsch_spss.py --year 2023 --validate-only

Author: Kidsights Data Platform
Date: 2025-10-03
"""

import sys
import argparse
from pathlib import Path
import time

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.nsch.spss_loader import (
    get_year_from_filename,
    read_spss_file,
    extract_variable_metadata,
    extract_value_labels,
    save_metadata_json
)
from python.nsch.data_loader import (
    convert_to_feather,
    load_feather,
    validate_feather_roundtrip
)


# Mapping of years to SPSS filenames
YEAR_TO_FILE = {
    2016: "NSCH2016_Topical_SPSS_CAHM_DRCv2.sav",
    2017: "2017 NSCH_Topical_CAHMI_DRCv2.sav",
    2018: "2018 NSCH_Topical_DRC_v2.sav",
    2019: "2019 NSCH_Topical_CAHMI DRCv2.sav",
    2020: "NSCH_2020e_Topical_CAHMI_DRCv3.sav",
    2021: "2021e NSCH_Topical_DRC_CAHMIv3.sav",
    2022: "NSCH_2022e_Topical_SPSS_CAHMI_DRCv3.sav",
    2023: "NSCH_2023e_Topical_CAHMI_DRC.sav"
}


def main():
    parser = argparse.ArgumentParser(
        description="Convert NSCH SPSS file to Feather format with metadata extraction",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Convert 2023 NSCH data to Feather
  python pipelines/python/nsch/load_nsch_spss.py --year 2023

  # Force overwrite existing files
  python pipelines/python/nsch/load_nsch_spss.py --year 2023 --overwrite

  # Only validate existing Feather file
  python pipelines/python/nsch/load_nsch_spss.py --year 2023 --validate-only
        """
    )

    parser.add_argument(
        "--year",
        type=int,
        required=True,
        choices=list(YEAR_TO_FILE.keys()),
        help="NSCH survey year (2016-2023)"
    )

    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing Feather and metadata files"
    )

    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Only validate existing Feather file (skip conversion)"
    )

    args = parser.parse_args()

    # Setup paths
    year = args.year
    spss_file = f"data/nsch/spss/{YEAR_TO_FILE[year]}"
    output_dir = Path(f"data/nsch/{year}")
    feather_file = output_dir / "raw.feather"
    metadata_file = output_dir / "metadata.json"

    print("[INFO] NSCH SPSS to Feather Pipeline")
    print("=" * 70)
    print(f"[INFO] Year: {year}")
    print(f"[INFO] SPSS file: {spss_file}")
    print(f"[INFO] Output directory: {output_dir}")
    print("=" * 70)

    # Validate-only mode
    if args.validate_only:
        print("\n[INFO] Validate-only mode")

        if not feather_file.exists():
            print(f"[ERROR] Feather file not found: {feather_file}")
            return 1

        print(f"[INFO] Loading Feather file: {feather_file}")
        df_feather = load_feather(str(feather_file))

        print(f"[OK] Feather file loaded")
        print(f"  Records: {len(df_feather):,}")
        print(f"  Variables: {len(df_feather.columns)}")
        print(f"  File size: {feather_file.stat().st_size / (1024*1024):.1f} MB")

        return 0

    # Check if files already exist
    if feather_file.exists() and not args.overwrite:
        print(f"\n[WARN] Feather file already exists: {feather_file}")
        print("[WARN] Use --overwrite to replace, or --validate-only to validate")
        return 1

    # Step 1: Read SPSS file
    print(f"\n[STEP 1/5] Reading SPSS file...")
    start_time = time.time()

    df, meta = read_spss_file(spss_file)

    read_time = time.time() - start_time
    print(f"[OK] SPSS file loaded in {read_time:.1f}s")
    print(f"  Records: {len(df):,}")
    print(f"  Variables: {len(df.columns)}")

    # Step 2: Extract metadata
    print(f"\n[STEP 2/5] Extracting metadata...")

    var_metadata = extract_variable_metadata(meta)
    value_labels = extract_value_labels(meta)

    print(f"[OK] Metadata extracted")
    print(f"  Variables with labels: {len(var_metadata)}")
    print(f"  Variables with value labels: {len(value_labels)}")

    # Step 3: Save metadata JSON
    print(f"\n[STEP 3/5] Saving metadata to JSON...")

    save_metadata_json(
        year=year,
        file_name=Path(spss_file).name,
        df=df,
        var_metadata=var_metadata,
        value_labels=value_labels,
        output_path=str(metadata_file)
    )

    metadata_size_kb = metadata_file.stat().st_size / 1024
    print(f"[OK] Metadata saved: {metadata_file}")
    print(f"  Size: {metadata_size_kb:.1f} KB")

    # Step 4: Convert to Feather
    print(f"\n[STEP 4/5] Converting to Feather format...")
    start_time = time.time()

    convert_to_feather(df, str(feather_file), compression='zstd')

    convert_time = time.time() - start_time
    feather_size_mb = feather_file.stat().st_size / (1024 * 1024)

    print(f"[OK] Feather file created in {convert_time:.1f}s")
    print(f"  File: {feather_file}")
    print(f"  Size: {feather_size_mb:.1f} MB")

    # Step 5: Validate round-trip
    print(f"\n[STEP 5/5] Validating round-trip conversion...")

    success, message = validate_feather_roundtrip(df, str(feather_file))

    if success:
        print(f"[OK] {message}")
    else:
        print(f"[ERROR] Validation failed: {message}")
        return 1

    # Summary
    print("\n" + "=" * 70)
    print("[SUCCESS] Pipeline completed successfully!")
    print("=" * 70)
    print(f"Output files:")
    print(f"  - Feather: {feather_file} ({feather_size_mb:.1f} MB)")
    print(f"  - Metadata: {metadata_file} ({metadata_size_kb:.1f} KB)")
    print("=" * 70)

    return 0


if __name__ == "__main__":
    sys.exit(main())

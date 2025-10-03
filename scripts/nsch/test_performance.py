"""
Performance Testing: SPSS vs Feather

Compares read times for SPSS and Feather formats to demonstrate
performance benefits of Feather format.

Usage:
    python scripts/nsch/test_performance.py
"""

import sys
import time
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from python.nsch.spss_loader import read_spss_file
from python.nsch.data_loader import load_feather


def time_operation(func, *args, **kwargs):
    """Time a function call and return result + elapsed time."""
    start = time.time()
    result = func(*args, **kwargs)
    elapsed = time.time() - start
    return result, elapsed


def main():
    print("[INFO] Performance Testing: SPSS vs Feather")
    print("=" * 70)

    spss_file = "data/nsch/spss/NSCH_2023e_Topical_CAHMI_DRC.sav"
    feather_file = "data/nsch/2023/raw.feather"

    # Get file sizes
    spss_size_mb = Path(spss_file).stat().st_size / (1024 * 1024)
    feather_size_mb = Path(feather_file).stat().st_size / (1024 * 1024)

    print(f"\nFile sizes:")
    print(f"  SPSS: {spss_size_mb:.1f} MB")
    print(f"  Feather: {feather_size_mb:.1f} MB")
    print(f"  Compression: {(1 - feather_size_mb/spss_size_mb)*100:.1f}% smaller")

    # Test 1: SPSS read time
    print(f"\n[TEST 1] SPSS read time...")
    (df_spss, meta), spss_time = time_operation(read_spss_file, spss_file)
    print(f"[OK] SPSS loaded in {spss_time:.2f}s")
    print(f"  Records: {len(df_spss):,}")
    print(f"  Variables: {len(df_spss.columns)}")

    # Test 2: Feather read time
    print(f"\n[TEST 2] Feather read time...")
    df_feather, feather_time = time_operation(load_feather, feather_file)
    print(f"[OK] Feather loaded in {feather_time:.2f}s")
    print(f"  Records: {len(df_feather):,}")
    print(f"  Variables: {len(df_feather.columns)}")

    # Test 3: Multiple reads (average over 3 runs)
    print(f"\n[TEST 3] Average read time (3 runs)...")

    spss_times = []
    for i in range(3):
        _, t = time_operation(read_spss_file, spss_file)
        spss_times.append(t)

    feather_times = []
    for i in range(3):
        _, t = time_operation(load_feather, feather_file)
        feather_times.append(t)

    avg_spss = sum(spss_times) / len(spss_times)
    avg_feather = sum(feather_times) / len(feather_times)

    print(f"  SPSS avg: {avg_spss:.2f}s")
    print(f"  Feather avg: {avg_feather:.2f}s")
    print(f"  Speedup: {avg_spss / avg_feather:.1f}x faster")

    # Summary
    print("\n" + "=" * 70)
    print("[SUMMARY] Performance Comparison")
    print("=" * 70)
    print(f"File size:")
    print(f"  Feather is {(1 - feather_size_mb/spss_size_mb)*100:.0f}% smaller")
    print(f"Read speed:")
    print(f"  Feather is {avg_spss / avg_feather:.1f}x faster")
    print("=" * 70)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
HTML Documentation Generator for NE25 Data Dictionary

This script automates the complete process of generating HTML documentation:
1. Generates comprehensive JSON from database
2. Renders all Quarto documents
3. Reports success/failure status

Usage:
    python scripts/documentation/generate_html_documentation.py
"""

import subprocess
import sys
import os
from pathlib import Path
import json
import time

def run_command(cmd, description, cwd=None):
    """Run a command and return success status"""
    print(f"[INFO] {description}...")
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            cwd=cwd,
            timeout=300  # 5 minute timeout
        )

        if result.returncode == 0:
            print(f"[SUCCESS] {description} completed successfully")
            return True
        else:
            print(f"[ERROR] {description} failed with exit code {result.returncode}")
            print(f"STDOUT: {result.stdout}")
            print(f"STDERR: {result.stderr}")
            return False

    except subprocess.TimeoutExpired:
        print(f"[ERROR] {description} timed out after 5 minutes")
        return False
    except Exception as e:
        print(f"[ERROR] {description} failed with exception: {e}")
        return False

def check_database_data():
    """Check if database has data to document"""
    try:
        result = subprocess.run([
            "python", "-c",
            """
from python.db.connection import DatabaseManager
dm = DatabaseManager()
with dm.get_connection() as conn:
    raw_count = conn.execute('SELECT COUNT(*) FROM ne25_raw').fetchone()[0]
    dict_count = conn.execute('SELECT COUNT(*) FROM ne25_data_dictionary').fetchone()[0]
    print(f'raw:{raw_count},dict:{dict_count}')
            """
        ], capture_output=True, text=True, timeout=30)

        if result.returncode == 0:
            counts = result.stdout.strip()
            raw_count, dict_count = [int(x.split(':')[1]) for x in counts.split(',')]
            print(f"[INFO] Database status - Raw records: {raw_count}, Dictionary entries: {dict_count}")
            return raw_count > 0 or dict_count > 0
        else:
            print(f"[WARNING] Could not check database status: {result.stderr}")
            return True  # Proceed anyway

    except Exception as e:
        print(f"[WARNING] Database check failed: {e}")
        return True  # Proceed anyway

def validate_json_output(json_path):
    """Validate that JSON file was generated properly"""
    try:
        if not os.path.exists(json_path):
            print(f"[ERROR] JSON file not found: {json_path}")
            return False

        with open(json_path, 'r') as f:
            data = json.load(f)

        # Check for basic structure
        if 'metadata' not in data:
            print("[ERROR] JSON missing metadata section")
            return False

        # Check if it's an error stub
        if 'status' in data['metadata'] and data['metadata']['status'] == 'export_failed':
            print("[ERROR] JSON contains export failure status")
            return False

        # Check for data
        total_vars = data['metadata'].get('total_raw_variables', 0) + data['metadata'].get('total_transformed_variables', 0)
        print(f"[INFO] JSON contains {total_vars} total variables")

        return True

    except Exception as e:
        print(f"[ERROR] JSON validation failed: {e}")
        return False

def main():
    """Main documentation generation workflow"""
    print("=" * 60)
    print("   NE25 HTML Documentation Generator")
    print("=" * 60)
    print(f"Start Time: {time.strftime('%Y-%m-%d %H:%M:%S')}")

    # Change to project root
    project_root = Path(__file__).parent.parent.parent
    os.chdir(project_root)
    print(f"Working Directory: {os.getcwd()}")

    success_count = 0
    total_steps = 4

    # Step 1: Check database
    print(f"\n--- Step 1: Database Status Check ---")
    if check_database_data():
        print("[INFO] Database contains data for documentation")
        success_count += 1
    else:
        print("[WARNING] Database appears empty - documentation may be minimal")

    # Step 2: Generate JSON
    print(f"\n--- Step 2: Generate Comprehensive JSON ---")
    json_success = run_command(
        "python scripts/documentation/generate_interactive_dictionary_json.py",
        "JSON generation"
    )

    if json_success:
        # Validate JSON output
        json_path = "docs/data_dictionary/ne25/ne25_dictionary.json"
        if validate_json_output(json_path):
            success_count += 1
        else:
            print("[WARNING] JSON generated but validation failed")

    # Step 3: Render Quarto documents
    print(f"\n--- Step 3: Render Quarto Documentation ---")
    quarto_cmd = '"C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe" render index.qmd'
    quarto_success = run_command(
        quarto_cmd,
        "Quarto rendering",
        cwd="docs/data_dictionary/ne25"
    )

    if quarto_success:
        success_count += 1

    # Step 4: Verify outputs
    print(f"\n--- Step 4: Verify Output Files ---")
    output_files = [
        "docs/data_dictionary/ne25/ne25_dictionary.json",
        "docs/data_dictionary/ne25/index.html"
    ]

    files_exist = True
    for file_path in output_files:
        if os.path.exists(file_path):
            size_mb = os.path.getsize(file_path) / (1024 * 1024)
            print(f"[SUCCESS] {file_path} ({size_mb:.2f} MB)")
        else:
            print(f"[ERROR] Missing output file: {file_path}")
            files_exist = False

    if files_exist:
        success_count += 1

    # Final report
    print(f"\n{'=' * 60}")
    print("   Documentation Generation Summary")
    print(f"{'=' * 60}")
    print(f"✅ Successful steps: {success_count}/{total_steps}")
    print(f"⏱️  Completion time: {time.strftime('%Y-%m-%d %H:%M:%S')}")

    if success_count == total_steps:
        print("🎉 SUCCESS: All documentation generated successfully!")
        print("\n📁 Output files:")
        for file_path in output_files:
            if os.path.exists(file_path):
                abs_path = os.path.abspath(file_path)
                print(f"   {abs_path}")
        return 0
    else:
        print("⚠️  WARNING: Some steps failed - documentation may be incomplete")
        return 1

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
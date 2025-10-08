"""
Test Template Generator for Imputation Stage Builder Agent

Purpose: Verify that template substitution works correctly before agent deployment
Author: Claude Code
Created: 2025-10-08
"""

import os
import sys
from pathlib import Path

# Project root setup
project_root = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(project_root))


def load_templates(template_file):
    """Load R and Python templates from markdown file."""
    with open(template_file, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract R template
    r_start = content.find("## R Script Template\n\n```r\n")
    r_end = content.find("\n```\n\n## Python Script Template")
    r_template = content[r_start + len("## R Script Template\n\n```r\n"):r_end]

    # Extract Python template
    py_start = content.find("## Python Script Template\n\n```python\n")
    py_end = content.find("\n```\n\n## Variable Substitution Guide")
    py_template = content[py_start + len("## Python Script Template\n\n```python\n"):py_end]

    return r_template, py_template


def generate_table_creation_sql(study_id, variable, data_type):
    """Generate SQL DDL for a single variable table."""
    return f'''
CREATE TABLE IF NOT EXISTS "{study_id}_imputed_{variable}" (
    "study_id" VARCHAR NOT NULL,
    "pid" VARCHAR NOT NULL,
    "record_id" INTEGER NOT NULL,
    "imputation_m" INTEGER NOT NULL,
    "{variable}" {data_type} NOT NULL,
    PRIMARY KEY (study_id, pid, record_id, imputation_m)
);
CREATE INDEX IF NOT EXISTS "idx_{study_id}_imputed_{variable}_pid_record"
    ON "{study_id}_imputed_{variable}" (pid, record_id);
CREATE INDEX IF NOT EXISTS "idx_{study_id}_imputed_{variable}_imputation_m"
    ON "{study_id}_imputed_{variable}" (imputation_m);
'''


def substitute_placeholders(template, substitutions):
    """Perform all placeholder substitutions in template."""
    result = template
    for placeholder, value in substitutions.items():
        result = result.replace(placeholder, str(value))
    return result


def test_simple_scenario():
    """Test template generation with simple scenario: GAD-7 anxiety scale."""

    print("[INFO] Testing Template Generator - Simple Scenario")
    print("=" * 70)

    # Test scenario parameters
    study_id = "ne25"
    stage_number = "12"
    domain = "adult_anxiety"
    domain_title = "Adult Anxiety"
    mice_method = "cart"

    variables = [
        ("gad7_1", "INTEGER"),
        ("gad7_2", "INTEGER"),
        ("gad7_3", "INTEGER"),
        ("gad7_4", "INTEGER"),
        ("gad7_5", "INTEGER"),
        ("gad7_6", "INTEGER"),
        ("gad7_7", "INTEGER"),
        ("gad7_total", "INTEGER"),
        ("gad7_positive", "INTEGER")
    ]

    n_variables = len(variables)
    variable_names = [v[0] for v in variables]
    variable_names_quoted = ", ".join([f'"{v}"' for v in variable_names])
    variables_list = ", ".join(variable_names)

    # Generate SQL DDL for all tables
    table_creation_statements = "\n".join([
        generate_table_creation_sql(study_id, var, dtype)
        for var, dtype in variables
    ])

    # Define all substitutions
    substitutions = {
        "{{STUDY_ID}}": study_id,
        "{{STUDY_ID_UPPER}}": study_id.upper(),
        "{{STAGE_NUMBER}}": stage_number,
        "{{DOMAIN}}": domain,
        "{{DOMAIN_TITLE}}": domain_title,
        "{{MICE_METHOD}}": mice_method,
        "{{N_VARIABLES}}": n_variables,
        "{{VARIABLES_LIST}}": variables_list,
        "{{VARIABLE_NAMES_QUOTED}}": variable_names_quoted,
        "{{TABLE_CREATION_STATEMENTS}}": table_creation_statements
    }

    # Load templates
    template_file = project_root / "docs" / "imputation" / "STAGE_TEMPLATES.md"
    print(f"\n[OK] Loading templates from: {template_file}")

    r_template, py_template = load_templates(template_file)
    print(f"[OK] R template loaded: {len(r_template)} characters")
    print(f"[OK] Python template loaded: {len(py_template)} characters")

    # Perform substitutions
    print(f"\n[INFO] Performing placeholder substitutions...")
    r_script = substitute_placeholders(r_template, substitutions)
    py_script = substitute_placeholders(py_template, substitutions)

    # Verify no placeholders remain
    remaining_r = [p for p in substitutions.keys() if p in r_script]
    remaining_py = [p for p in substitutions.keys() if p in py_script]

    if remaining_r:
        print(f"[ERROR] R script has unsubstituted placeholders: {remaining_r}")
    else:
        print(f"[OK] R script: All placeholders substituted")

    if remaining_py:
        print(f"[ERROR] Python script has unsubstituted placeholders: {remaining_py}")
    else:
        print(f"[OK] Python script: All placeholders substituted")

    # Check for expected content
    print(f"\n[INFO] Verifying expected content...")

    # R script checks
    r_checks = [
        ("set.seed(seed + m)", "Unique seed pattern"),
        (f'"{study_id}_transformed"', "Study ID in query"),
        (f'"{domain}_feather"', "Domain in output path"),
        ("eligible.x\" = TRUE", "Defensive filtering"),
        ("mice::mice(", "MICE call"),
        (f"method = \"{mice_method}\"", "MICE method")
    ]

    for pattern, description in r_checks:
        if pattern in r_script:
            print(f"  [OK] R: {description}")
        else:
            print(f"  [ERROR] R: Missing {description}")

    # Python script checks
    py_checks = [
        (f'"{study_id}_imputed_', "Table naming pattern"),
        ("UPDATE imputation_metadata", "Metadata update"),
        ("PRIMARY KEY (study_id, pid, record_id, imputation_m)", "Primary key"),
        ("CREATE INDEX IF NOT EXISTS", "Index creation"),
        (f"def load_{domain}_feather_files", "Load function naming"),
        (f"def create_{domain}_tables", "Create tables function"),
        (f"def insert_{domain}_imputations", "Insert function naming")
    ]

    for pattern, description in py_checks:
        if pattern in py_script:
            print(f"  [OK] Python: {description}")
        else:
            print(f"  [ERROR] Python: Missing {description}")

    # Output sample (first 50 lines of each)
    print(f"\n[INFO] R Script Sample (first 30 lines):")
    print("-" * 70)
    for i, line in enumerate(r_script.split('\n')[:30], 1):
        print(f"{i:3d} | {line}")

    print(f"\n[INFO] Python Script Sample (first 30 lines):")
    print("-" * 70)
    for i, line in enumerate(py_script.split('\n')[:30], 1):
        print(f"{i:3d} | {line}")

    # File statistics
    r_lines = len(r_script.split('\n'))
    py_lines = len(py_script.split('\n'))

    print(f"\n[INFO] File Statistics:")
    print(f"  R script: {r_lines} lines, {len(r_script)} characters")
    print(f"  Python script: {py_lines} lines, {len(py_script)} characters")

    # Write test outputs
    test_output_dir = project_root / "scripts" / "imputation" / "test_output"
    test_output_dir.mkdir(exist_ok=True)

    r_output = test_output_dir / f"{stage_number}_impute_{domain}_TEST.R"
    py_output = test_output_dir / f"{stage_number}b_insert_{domain}_TEST.py"

    with open(r_output, 'w', encoding='utf-8') as f:
        f.write(r_script)
    print(f"\n[OK] Test R script written to: {r_output}")

    with open(py_output, 'w', encoding='utf-8') as f:
        f.write(py_script)
    print(f"[OK] Test Python script written to: {py_output}")

    print("\n" + "=" * 70)
    print("[OK] Template generation test completed successfully!")
    print("\nNext steps:")
    print("  1. Review test output files in scripts/imputation/test_output/")
    print("  2. Verify TODO markers are properly placed")
    print("  3. Check that all critical patterns are present")
    print("  4. Compare with existing stage implementations")


if __name__ == "__main__":
    test_simple_scenario()

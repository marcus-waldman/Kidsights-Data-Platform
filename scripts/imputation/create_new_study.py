#!/usr/bin/env python3
"""
Create New Study - Imputation Pipeline Setup

This script scaffolds a new study for the imputation pipeline by:
1. Creating directory structure
2. Generating study-specific configuration
3. Copying and adapting pipeline scripts
4. Creating database schema

Usage:
    python scripts/imputation/create_new_study.py --study-id ia26 --study-name "Iowa 2026"
"""

import argparse
import sys
from pathlib import Path
import shutil
import yaml


def create_directories(study_id, project_root):
    """Create directory structure for new study."""
    print(f"\n[INFO] Creating directories for {study_id}...")

    # Create scripts directory
    scripts_dir = project_root / "scripts" / "imputation" / study_id
    scripts_dir.mkdir(parents=True, exist_ok=True)
    print(f"  [OK] Created {scripts_dir}")

    # Create data directory
    data_dir = project_root / "data" / "imputation" / study_id
    data_dir.mkdir(parents=True, exist_ok=True)
    print(f"  [OK] Created {data_dir}")

    # Create sociodem_feather subdirectory
    feather_dir = data_dir / "sociodem_feather"
    feather_dir.mkdir(parents=True, exist_ok=True)
    print(f"  [OK] Created {feather_dir}")

    return scripts_dir, data_dir


def create_config(study_id, study_name, project_root):
    """Create study-specific configuration file."""
    print(f"\n[INFO] Creating configuration for {study_id}...")

    # Load template from ne25
    template_path = project_root / "config" / "imputation" / "ne25_config.yaml"

    if not template_path.exists():
        print(f"  [ERROR] Template config not found at {template_path}")
        return False

    with open(template_path, 'r') as f:
        config = yaml.safe_load(f)

    # Update study-specific fields
    config['study_id'] = study_id
    config['study_name'] = study_name
    config['table_prefix'] = f"{study_id}_imputed"
    config['data_dir'] = f"data/imputation/{study_id}"
    config['scripts_dir'] = f"scripts/imputation/{study_id}"

    # Write new config
    new_config_path = project_root / "config" / "imputation" / f"{study_id}_config.yaml"
    with open(new_config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)

    print(f"  [OK] Created {new_config_path}")
    print(f"  [NOTE] Please review and customize variables in {new_config_path}")

    return True


def copy_scripts(study_id, scripts_dir, project_root):
    """Copy and adapt pipeline scripts from ne25."""
    print(f"\n[INFO] Copying pipeline scripts for {study_id}...")

    # Source directory (ne25 scripts)
    source_dir = project_root / "scripts" / "imputation" / "ne25"

    if not source_dir.exists():
        print(f"  [ERROR] Source scripts not found at {source_dir}")
        return False

    # Scripts to copy
    scripts = [
        "01_impute_geography.py",
        "02_impute_sociodemographic.R",
        "02b_insert_sociodem_imputations.py",
        "run_full_imputation_pipeline.R"
    ]

    for script in scripts:
        source = source_dir / script
        dest = scripts_dir / script

        if source.exists():
            # Read source file
            with open(source, 'r', encoding='utf-8') as f:
                content = f.read()

            # Replace ne25 with new study_id
            content = content.replace('ne25', study_id)
            content = content.replace('NE25', study_id.upper())
            content = content.replace('Nebraska 2025', f'{study_id.upper()} Study')

            # Write to destination
            with open(dest, 'w', encoding='utf-8') as f:
                f.write(content)

            print(f"  [OK] Created {dest}")
            print(f"  [NOTE] Please review {script} for study-specific customization")
        else:
            print(f"  [WARN] Source script not found: {source}")

    return True


def create_database_schema(study_id, project_root):
    """Run database schema setup for new study."""
    print(f"\n[INFO] Creating database schema for {study_id}...")

    schema_script = project_root / "scripts" / "imputation" / "00_setup_imputation_schema.py"

    if not schema_script.exists():
        print(f"  [ERROR] Schema setup script not found at {schema_script}")
        return False

    print(f"  [INFO] To create database tables, run:")
    print(f"  python {schema_script} --study-id {study_id}")
    print(f"  [NOTE] This will create {study_id}_imputed_* tables in the database")

    return True


def print_next_steps(study_id, project_root):
    """Print next steps for completing setup."""
    print(f"\n{'=' * 70}")
    print(f"[OK] Study setup scaffolding complete for {study_id}!")
    print(f"{'=' * 70}\n")

    print("Next Steps:")
    print(f"\n1. Review and customize configuration:")
    print(f"   - Edit config/imputation/{study_id}_config.yaml")
    print(f"   - Update variables list (may differ from ne25)")
    print(f"   - Update auxiliary variables for MICE")
    print(f"   - Adjust MICE methods if needed")

    print(f"\n2. Review and customize pipeline scripts:")
    print(f"   - scripts/imputation/{study_id}/01_impute_geography.py")
    print(f"   - scripts/imputation/{study_id}/02_impute_sociodemographic.R")
    print(f"   - scripts/imputation/{study_id}/02b_insert_sociodem_imputations.py")
    print(f"   - scripts/imputation/{study_id}/run_full_imputation_pipeline.R")

    print(f"\n3. Create database schema:")
    print(f"   python scripts/imputation/00_setup_imputation_schema.py --study-id {study_id}")

    print(f"\n4. Ensure base data table exists:")
    print(f"   - Table name: {study_id}_transformed")
    print(f"   - Required columns: pid, record_id, + imputed variables")

    print(f"\n5. Run imputation pipeline:")
    print(f"   \"C:\\Program Files\\R\\R-4.5.1\\bin\\Rscript.exe\" scripts/imputation/{study_id}/run_full_imputation_pipeline.R")

    print(f"\n6. Validate results:")
    print(f"   from python.imputation.helpers import validate_imputations")
    print(f"   validate_imputations(study_id='{study_id}')")

    print(f"\n7. Test helper functions:")
    print(f"   from python.imputation.helpers import get_completed_dataset")
    print(f"   df = get_completed_dataset(imputation_m=1, study_id='{study_id}')")

    print(f"\n{'=' * 70}")
    print(f"Documentation: See docs/imputation/STUDY_SPECIFIC_MIGRATION_PLAN.md")
    print(f"{'=' * 70}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Create new study setup for imputation pipeline"
    )
    parser.add_argument(
        "--study-id",
        required=True,
        help="Study ID (e.g., ia26, co27)"
    )
    parser.add_argument(
        "--study-name",
        required=True,
        help="Full study name (e.g., 'Iowa 2026', 'Colorado 2027')"
    )
    parser.add_argument(
        "--create-schema",
        action="store_true",
        help="Automatically create database schema (requires database connection)"
    )

    args = parser.parse_args()

    # Validate study_id format
    study_id = args.study_id.lower()
    if not study_id.isalnum():
        print("[ERROR] study_id must be alphanumeric (e.g., ia26, co27)")
        return 1

    # Get project root
    project_root = Path(__file__).resolve().parent.parent.parent

    print(f"\n{'=' * 70}")
    print(f"Creating New Study: {args.study_name} ({study_id})")
    print(f"{'=' * 70}")

    # Execute setup steps
    try:
        # Step 1: Create directories
        scripts_dir, data_dir = create_directories(study_id, project_root)

        # Step 2: Create configuration
        if not create_config(study_id, args.study_name, project_root):
            return 1

        # Step 3: Copy scripts
        if not copy_scripts(study_id, scripts_dir, project_root):
            return 1

        # Step 4: Database schema
        if args.create_schema:
            # Import and run schema setup
            sys.path.insert(0, str(project_root))
            from scripts.imputation import setup_imputation_schema
            setup_imputation_schema.main(['--study-id', study_id])
        else:
            create_database_schema(study_id, project_root)

        # Step 5: Print next steps
        print_next_steps(study_id, project_root)

        return 0

    except Exception as e:
        print(f"\n[ERROR] Setup failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())

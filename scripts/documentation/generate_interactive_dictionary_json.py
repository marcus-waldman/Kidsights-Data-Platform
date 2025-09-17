#!/usr/bin/env python3
"""
Generate Comprehensive JSON Export for NE25 Interactive Data Dictionary

This script handles large datasets efficiently using Python's native JSON capabilities,
avoiding the memory limitations that cause segmentation faults in R's jsonlite package.

Usage:
    python generate_interactive_dictionary_json.py [--db-path PATH] [--output-dir DIR]

Requirements:
    pip install duckdb pandas

Author: Kidsights Data Platform
"""

import duckdb
import pandas as pd
import json
import argparse
import sys
from pathlib import Path
from datetime import datetime


class InteractiveDictionaryExporter:
    """Exports comprehensive data dictionary information to JSON format"""

    def __init__(self, db_path, output_dir="docs/data_dictionary/ne25"):
        """
        Initialize the exporter

        Args:
            db_path (str): Path to DuckDB database file
            output_dir (str): Directory to save JSON output
        """
        self.db_path = Path(db_path)
        self.output_dir = Path(output_dir)

        # Validate inputs
        if not self.db_path.exists():
            raise FileNotFoundError(f"Database file not found: {self.db_path}")

        self.output_dir.mkdir(parents=True, exist_ok=True)

    def get_raw_variables(self, conn):
        """Get raw variables data with project information"""
        query = """
        SELECT
            ROW_NUMBER() OVER (PARTITION BY pid ORDER BY field_name) as column_id,
            pid,
            field_name,
            field_label,
            field_type,
            select_choices_or_calculations,
            field_note,
            form_name
        FROM ne25_data_dictionary
        WHERE field_name NOT IN ('record_id', 'pid', 'redcap_event_name',
                                'redcap_survey_identifier', 'retrieved_date',
                                'source_project', 'extraction_id')
        ORDER BY pid, column_id
        """

        # Use chunked reading for memory efficiency with large datasets
        chunk_size = 500
        chunks = []

        try:
            for chunk in pd.read_sql(query, conn, chunksize=chunk_size):
                chunks.append(chunk)

            if chunks:
                df = pd.concat(chunks, ignore_index=True)
                print(f"[SUCCESS] Loaded {len(df)} raw variables from {df['pid'].nunique()} projects")
                return df
            else:
                print("[WARNING] No raw variables found in ne25_data_dictionary table")
                return pd.DataFrame()

        except Exception as e:
            print(f"[ERROR] Error loading raw variables: {e}")
            return pd.DataFrame()

    def get_transformed_variables(self, conn):
        """Get transformed variables metadata"""
        query = """
        SELECT
            variable_name,
            variable_label,
            category,
            data_type,
            value_labels,
            transformation_notes,
            n_total,
            n_missing,
            missing_percentage
        FROM ne25_metadata
        ORDER BY category, variable_name
        """

        try:
            df = pd.read_sql(query, conn)
            print(f"[SUCCESS] Loaded {len(df)} transformed variables")
            return df
        except Exception as e:
            print(f"[ERROR] Error loading transformed variables: {e}")
            return pd.DataFrame()

    def create_variable_project_matrix(self, raw_vars_df):
        """Create variable-project matrix showing which variables appear in which projects"""
        if raw_vars_df.empty:
            return pd.DataFrame()

        try:
            # Get unique variables with their labels
            unique_vars = raw_vars_df[['field_name', 'field_label', 'pid']].drop_duplicates()

            # Create pivot table to show presence across projects
            matrix = unique_vars.pivot_table(
                index=['field_name', 'field_label'],
                columns='pid',
                values='pid',  # Use pid as value (will be non-null where present)
                aggfunc='first'
            ).reset_index()

            # Convert to boolean presence indicators with PID_ prefix
            project_pids = ['7679', '7943', '7999', '8014']
            pid_columns = [col for col in matrix.columns if str(col) in project_pids]

            for pid in project_pids:
                col_name = f'PID_{pid}'
                if int(pid) in matrix.columns:
                    matrix[col_name] = ~matrix[int(pid)].isna()
                    matrix = matrix.drop(columns=[int(pid)])
                else:
                    matrix[col_name] = False

            # Reorder columns
            final_columns = ['field_name', 'field_label'] + [f'PID_{pid}' for pid in project_pids]
            matrix = matrix[final_columns].sort_values('field_name')

            print(f"[SUCCESS] Created variable-project matrix with {len(matrix)} variables")
            return matrix

        except Exception as e:
            print(f"[ERROR] Error creating variable-project matrix: {e}")
            return pd.DataFrame()

    def get_transformation_mappings(self):
        """Get transformation mapping documentation"""
        mappings = {
            "Race/Ethnicity": {
                "description": "Child and caregiver race/ethnicity variables created from checkbox responses",
                "raw_variables": ["cqr010_1___1 through cqr010_15___1", "cqr011", "sq002_1___1 through sq002_15___1", "sq003"],
                "transformed_variables": ["hisp", "race", "raceG", "a1_hisp", "a1_race", "a1_raceG"],
                "process": "Multiple race checkboxes are collapsed into categories; Hispanic ethnicity is combined with race to create composite variables"
            },
            "Education Categories": {
                "description": "Education levels recoded into 4, 6, and 8 category systems",
                "raw_variables": ["education-related fields from surveys"],
                "transformed_variables": ["educ4_*", "educ6_*", "educ8_*", "educ_max", "educ_mom"],
                "process": "Raw education responses are mapped to standardized categories for analysis"
            },
            "Income and Poverty": {
                "description": "Federal Poverty Level calculations based on income and family size",
                "raw_variables": ["household income fields", "family size fields"],
                "transformed_variables": ["income", "inc99", "family_size", "federal_poverty_threshold", "fpl", "fplcat"],
                "process": "Income is adjusted for inflation; FPL calculated using HHS poverty guidelines; categorical FPL groups created"
            },
            "Age Variables": {
                "description": "Age calculations in multiple units",
                "raw_variables": ["child_dob", "age_in_days", "caregiver_dob"],
                "transformed_variables": ["years_old", "months_old", "days_old", "a1_years_old"],
                "process": "Dates converted to age in years, months, and days; age groups created for analysis"
            },
            "Eligibility Flags": {
                "description": "Eligibility determination based on 9 criteria (CID1-CID9)",
                "raw_variables": ["eq001", "eq002", "eq003", "compensation acknowledgment fields", "geographic fields", "survey completion fields"],
                "transformed_variables": ["eligible", "authentic", "include"],
                "process": "Multiple eligibility criteria evaluated; overall inclusion flags created"
            }
        }
        return mappings

    def apply_category_mapping(self, df):
        """Apply user-friendly category names to transformed variables"""
        if df.empty:
            return df

        category_mapping = {
            "age": "Age Variables",
            "caregiver relationship": "Caregiver Relationships",
            "education": "Education Categories",
            "race": "Race/Ethnicity",
            "sex": "Sex and Gender",
            "income": "Income and Poverty",
            "eligibility": "Eligibility Flags",
            "geography": "Geographic Variables"
        }

        df = df.copy()
        df['category_mapped'] = df['category'].map(category_mapping).fillna(df['category'])
        df['missing_percentage'] = pd.to_numeric(df['missing_percentage'], errors='coerce').round(1)

        return df.sort_values(['category_mapped', 'variable_name'])

    def export_comprehensive_json(self):
        """Export all dictionary data to comprehensive JSON file"""
        print("[INFO] Starting comprehensive JSON export...")

        try:
            # Connect to database
            conn = duckdb.connect(str(self.db_path), read_only=True)
            print(f"[SUCCESS] Connected to database: {self.db_path}")

            # Get all data components
            raw_vars_df = self.get_raw_variables(conn)
            transformed_vars_df = self.get_transformed_variables(conn)
            matrix_df = self.create_variable_project_matrix(raw_vars_df)
            transformation_mappings = self.get_transformation_mappings()

            # Apply category mapping to transformed variables
            if not transformed_vars_df.empty:
                transformed_vars_df = self.apply_category_mapping(transformed_vars_df)

            # Build comprehensive JSON structure
            dictionary_json = {
                "metadata": {
                    "generated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "study": "ne25",
                    "total_raw_variables": len(raw_vars_df),
                    "total_transformed_variables": len(transformed_vars_df),
                    "total_projects": len(raw_vars_df['pid'].unique()) if not raw_vars_df.empty else 0,
                    "project_pids": sorted(raw_vars_df['pid'].unique().tolist()) if not raw_vars_df.empty else [],
                    "generated_by": "Kidsights Data Platform - Interactive Dictionary (Python)"
                },
                "variable_project_matrix": {
                    "description": "Matrix showing which variables appear in which REDCap projects",
                    "total_variables": len(matrix_df),
                    "data": matrix_df.to_dict(orient='records') if not matrix_df.empty else []
                },
                "raw_variables": {
                    "description": "Raw variables from REDCap projects with complete field information",
                    "total_variables": len(raw_vars_df),
                    "data": raw_vars_df.to_dict(orient='records') if not raw_vars_df.empty else []
                },
                "transformed_variables": {
                    "description": "Transformed and harmonized variables after pipeline processing",
                    "total_variables": len(transformed_vars_df),
                    "data": transformed_vars_df.to_dict(orient='records') if not transformed_vars_df.empty else []
                },
                "transformation_mappings": {
                    "description": "Documentation of how raw variables are transformed into harmonized variables",
                    "data": transformation_mappings
                }
            }

            # Write JSON file using streaming for memory efficiency
            output_path = self.output_dir / "ne25_dictionary.json"

            print(f"[INFO] Writing JSON to: {output_path}")
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(dictionary_json, f, indent=2, ensure_ascii=False, default=str)

            # Close database connection
            conn.close()

            # Print summary
            print("[SUCCESS] JSON export completed successfully!")
            print(f"[SUMMARY] Statistics:")
            print(f"   * Raw variables: {len(raw_vars_df)}")
            print(f"   * Transformed variables: {len(transformed_vars_df)}")
            print(f"   * Projects: {len(raw_vars_df['pid'].unique()) if not raw_vars_df.empty else 0}")
            print(f"   * File size: {output_path.stat().st_size / 1024 / 1024:.2f} MB")
            print(f"[OUTPUT] File location: {output_path}")

            return str(output_path)

        except Exception as e:
            print(f"[ERROR] JSON export failed: {e}")
            return None


def main():
    """Main function for command line execution"""
    parser = argparse.ArgumentParser(
        description='Generate comprehensive JSON export for NE25 Interactive Data Dictionary'
    )
    parser.add_argument(
        '--db-path',
        default="data/duckdb/kidsights_local.duckdb",
        help='Path to DuckDB database file'
    )
    parser.add_argument(
        '--output-dir',
        default="docs/data_dictionary/ne25",
        help='Output directory for JSON file'
    )

    args = parser.parse_args()

    try:
        exporter = InteractiveDictionaryExporter(args.db_path, args.output_dir)
        result = exporter.export_comprehensive_json()

        if result:
            print(f"\n[SUCCESS] JSON exported to: {result}")
            sys.exit(0)
        else:
            print(f"\n[FAILED] Export failed!")
            sys.exit(1)

    except Exception as e:
        print(f"[FATAL] Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
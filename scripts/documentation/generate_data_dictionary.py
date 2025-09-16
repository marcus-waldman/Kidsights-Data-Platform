#!/usr/bin/env python3
"""
NE25 Data Dictionary Generator

Generates a comprehensive Markdown data dictionary from the metadata stored in DuckDB.
This ensures the documentation stays consistent with the actual transformed data.

Usage:
    python generate_data_dictionary.py [options]

Requirements:
    pip install duckdb pandas markdown2

Author: Kidsights Data Platform
"""

import duckdb
import pandas as pd
import json
import argparse
import os
from datetime import datetime
from pathlib import Path


class DataDictionaryGenerator:
    """Generates data dictionary from NE25 metadata"""

    def __init__(self, db_path, output_dir="docs/data_dictionary"):
        """
        Initialize the data dictionary generator

        Args:
            db_path (str): Path to DuckDB database file
            output_dir (str): Directory to save output files
        """
        self.db_path = db_path
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Category order for consistent organization
        self.category_order = [
            "include", "race", "caregiver relationship",
            "education", "sex", "age", "income"
        ]

    def connect_db(self):
        """Connect to DuckDB and return connection"""
        return duckdb.connect(self.db_path)

    def load_metadata(self):
        """Load all metadata from database"""
        conn = self.connect_db()

        # Load metadata with proper ordering
        query = """
        SELECT * FROM ne25_metadata
        ORDER BY category, variable_name
        """

        metadata_df = conn.execute(query).df()
        conn.close()

        return metadata_df

    def load_summary_stats(self):
        """Load summary statistics by category"""
        conn = self.connect_db()

        # Get category summaries
        query = """
        SELECT
            category,
            COUNT(*) as n_variables,
            ROUND(AVG(missing_percentage), 2) as avg_missing_pct,
            COUNT(CASE WHEN data_type = 'factor' THEN 1 END) as n_factors,
            COUNT(CASE WHEN data_type = 'numeric' THEN 1 END) as n_numeric,
            COUNT(CASE WHEN data_type = 'logical' THEN 1 END) as n_logical,
            COUNT(CASE WHEN data_type = 'character' THEN 1 END) as n_character
        FROM ne25_metadata
        GROUP BY category
        ORDER BY category
        """

        summary_df = conn.execute(query).df()

        # Get total dataset info
        total_query = """
        SELECT
            COUNT(*) as total_variables,
            COUNT(DISTINCT category) as total_categories,
            MAX(n_total) as total_records
        FROM ne25_metadata
        """

        totals = conn.execute(total_query).df().iloc[0]
        conn.close()

        return summary_df, totals

    def parse_json_field(self, json_str):
        """Safely parse JSON field, return dict or empty dict"""
        if pd.isna(json_str) or json_str == "":
            return {}
        try:
            return json.loads(json_str)
        except (json.JSONDecodeError, TypeError):
            return {}

    def format_value_labels(self, value_labels_json):
        """Format value labels for display"""
        if not value_labels_json:
            return "N/A"

        labels = self.parse_json_field(value_labels_json)
        if not labels:
            return "N/A"

        # Format as "Label (count), Label (count)"
        formatted = []
        for label, count in labels.items():
            if label != "NA" and str(count) != "0":  # Skip NA and zero counts
                formatted.append(f"{label} ({count})")

        return ", ".join(formatted[:5]) + ("..." if len(formatted) > 5 else "")

    def format_summary_stats(self, summary_stats_json, data_type):
        """Format summary statistics based on data type"""
        if not summary_stats_json:
            return "N/A"

        stats = self.parse_json_field(summary_stats_json)
        if not stats:
            return "N/A"

        if data_type == "numeric":
            return f"Min: {stats.get('min', 'NA')}, Max: {stats.get('max', 'NA')}, Mean: {stats.get('mean', 'NA'):.2f}" if stats.get('mean') else "N/A"
        elif data_type == "logical":
            return f"True: {stats.get('n_true', 0)}, False: {stats.get('n_false', 0)}"
        elif data_type == "character":
            return f"Unique values: {stats.get('unique_values', 'NA')}"
        else:
            return "N/A"

    def generate_category_descriptions(self):
        """Define category descriptions"""
        return {
            "include": "Eligibility and inclusion flags indicating which participants meet study criteria",
            "race": "Race and ethnicity variables for children and primary caregivers, including harmonized categories",
            "caregiver relationship": "Variables describing relationships between caregivers and children, including gender and maternal status",
            "education": "Education level variables using multiple categorization systems (4, 6, and 8 categories)",
            "sex": "Child's biological sex and gender indicator variables",
            "age": "Age variables for children and caregivers in different units (days, months, years)",
            "income": "Household income, family size, and federal poverty level calculations"
        }

    def generate_markdown(self, format_type="full"):
        """
        Generate complete markdown data dictionary

        Args:
            format_type (str): "full" or "summary"
        """
        metadata_df = self.load_metadata()
        summary_df, totals = self.load_summary_stats()
        category_descriptions = self.generate_category_descriptions()

        # Start building markdown
        md_lines = []

        # Header
        md_lines.extend([
            "# NE25 Data Dictionary",
            "",
            f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  ",
            f"**Total Records:** {int(totals['total_records'])}  ",
            f"**Total Variables:** {int(totals['total_variables'])}  ",
            f"**Categories:** {int(totals['total_categories'])}  ",
            "",
            "## Overview",
            "",
            "This data dictionary describes all variables in the NE25 transformed dataset. ",
            "The data comes from REDCap surveys and has been processed through the Kidsights ",
            "data transformation pipeline, which applies standardized harmonization rules ",
            "for race/ethnicity, education categories, and other demographic variables.",
            "",
        ])

        # Sort categories by predefined order
        ordered_categories = []
        for cat in self.category_order:
            if cat in summary_df['category'].values:
                ordered_categories.append(cat)
        # Add any additional categories not in predefined order
        for cat in summary_df['category'].values:
            if cat not in ordered_categories:
                ordered_categories.append(cat)

        # Table of contents
        if format_type == "full":
            md_lines.extend([
                "## Table of Contents",
                "",
            ])

            for category in ordered_categories:
                cat_summary = summary_df[summary_df['category'] == category].iloc[0]
                md_lines.append(f"- [{category.title()}](#{category.lower().replace(' ', '-')}) "
                              f"({int(cat_summary['n_variables'])} variables)")

            md_lines.append("")

        # Category sections
        for category in ordered_categories:
            cat_data = metadata_df[metadata_df['category'] == category].copy()
            cat_summary = summary_df[summary_df['category'] == category].iloc[0]

            # Category header
            md_lines.extend([
                f"## {category.title()}",
                "",
                f"**Description:** {category_descriptions.get(category, 'No description available')}",
                "",
                f"**Variables:** {int(cat_summary['n_variables'])}  ",
                f"**Average Missing:** {cat_summary['avg_missing_pct']:.1f}%  ",
                f"**Data Types:** {int(cat_summary['n_factors'])} factors, "
                f"{int(cat_summary['n_numeric'])} numeric, "
                f"{int(cat_summary['n_logical'])} logical, "
                f"{int(cat_summary['n_character'])} character",
                "",
            ])

            if format_type == "full":
                # Detailed variable table
                md_lines.extend([
                    "| Variable | Label | Type | Missing | Details |",
                    "|----------|-------|------|---------|---------|",
                ])

                for _, row in cat_data.iterrows():
                    # Format details based on data type
                    if row['data_type'] == 'factor':
                        details = self.format_value_labels(row['value_labels'])
                    else:
                        details = self.format_summary_stats(row['summary_statistics'], row['data_type'])

                    # Clean up text for markdown table
                    variable = str(row['variable_name']).replace('|', '\\|')
                    label = str(row['variable_label']).replace('|', '\\|')
                    missing_pct = f"{row['missing_percentage']:.1f}%" if pd.notna(row['missing_percentage']) else "N/A"
                    details = str(details).replace('|', '\\|')

                    md_lines.append(f"| `{variable}` | {label} | {row['data_type']} | {missing_pct} | {details} |")

            else:  # Summary format
                # Just list variable names
                var_names = [f"`{var}`" for var in cat_data['variable_name'].tolist()]
                md_lines.append(f"**Variables:** {', '.join(var_names)}")

            md_lines.append("")

        # Footer
        md_lines.extend([
            "---",
            "",
            "## Notes",
            "",
            "- **Missing percentages** are calculated as (missing values / total records) × 100",
            "- **Factor variables** show the most common levels with their counts",
            "- **Numeric variables** display min, max, and mean values where available",
            "- **Logical variables** show counts of TRUE and FALSE values",
            "",
            f"*Generated automatically from metadata on {datetime.now().strftime('%Y-%m-%d')} by the Kidsights Data Platform*",
            ""
        ])

        return "\n".join(md_lines)

    def save_dictionary(self, content, filename="ne25_data_dictionary.md"):
        """Save data dictionary to file"""
        output_path = self.output_dir / filename

        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(content)

        print(f"Data dictionary saved to: {output_path}")
        return output_path

    def generate_json_export(self):
        """Generate JSON export of metadata for external use"""
        metadata_df = self.load_metadata()

        # Build structured JSON data
        json_data = {
            "metadata": {
                "generated": datetime.now().isoformat(),
                "total_variables": len(metadata_df),
                "total_categories": metadata_df['category'].nunique(),
                "data_source": "NE25 transformed dataset"
            },
            "variables": []
        }

        for _, row in metadata_df.iterrows():
            variable_data = {
                'variable_name': row['variable_name'],
                'category': row['category'],
                'variable_label': row['variable_label'],
                'data_type': row['data_type'],
                'storage_mode': row['storage_mode'],
                'n_total': int(row['n_total']) if pd.notna(row['n_total']) else None,
                'n_missing': int(row['n_missing']) if pd.notna(row['n_missing']) else None,
                'missing_percentage': float(row['missing_percentage']) if pd.notna(row['missing_percentage']) else None,
                'min_value': float(row['min_value']) if pd.notna(row['min_value']) else None,
                'max_value': float(row['max_value']) if pd.notna(row['max_value']) else None,
                'mean_value': float(row['mean_value']) if pd.notna(row['mean_value']) else None,
                'unique_values': int(row['unique_values']) if pd.notna(row['unique_values']) else None,
                'creation_date': row['creation_date']
            }

            # Add parsed JSON data as nested objects
            variable_data['value_labels'] = self.parse_json_field(row['value_labels'])
            variable_data['summary_statistics'] = self.parse_json_field(row['summary_statistics'])

            json_data['variables'].append(variable_data)

        json_path = self.output_dir / "ne25_metadata_export.json"
        with open(json_path, 'w', encoding='utf-8') as f:
            json.dump(json_data, f, indent=2, ensure_ascii=False, default=str)

        print(f"JSON export saved to: {json_path}")
        return json_path

    def generate_html(self, markdown_content, filename="ne25_data_dictionary.html"):
        """Convert Markdown to HTML with styling"""
        try:
            import markdown2
        except ImportError:
            print("Warning: markdown2 not installed. Install with: pip install markdown2")
            return None

        # CSS styling for professional documentation
        css_styles = """
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
        }
        h1, h2, h3 { color: #2c3e50; border-bottom: 2px solid #ecf0f1; padding-bottom: 0.3rem; }
        h1 { font-size: 2.5rem; }
        h2 { font-size: 2rem; margin-top: 2rem; }
        h3 { font-size: 1.5rem; }
        table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f8f9fa; font-weight: 600; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        code { background-color: #f1f2f6; padding: 2px 4px; border-radius: 3px; font-family: 'Consolas', monospace; }
        .toc { background-color: #f8f9fa; padding: 1rem; border-radius: 5px; margin: 1rem 0; }
        .metadata-header { background-color: #e8f4fd; padding: 1rem; border-radius: 5px; margin: 1rem 0; }
        .category-description { font-style: italic; color: #7f8c8d; margin: 0.5rem 0; }
        .stats { background-color: #f0f8ff; padding: 0.5rem; border-radius: 3px; margin: 0.5rem 0; }
        .footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid #ecf0f1; text-align: center; color: #7f8c8d; }
        </style>
        """

        # Convert markdown to HTML
        html_content = markdown2.markdown(markdown_content, extras=['tables', 'fenced-code-blocks'])

        # Wrap in full HTML document
        full_html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NE25 Data Dictionary</title>
    {css_styles}
</head>
<body>
    {html_content}
</body>
</html>
        """

        # Save HTML file
        html_path = self.output_dir / filename
        with open(html_path, 'w', encoding='utf-8') as f:
            f.write(full_html)

        print(f"HTML dictionary saved to: {html_path}")
        return html_path


def main():
    """Main function with command line interface"""
    parser = argparse.ArgumentParser(description="Generate NE25 Data Dictionary from metadata")
    parser.add_argument(
        "--db-path",
        default="C:/Users/waldmanm/OneDrive - The University of Colorado Denver/Kidsights-duckDB/kidsights.duckdb",
        help="Path to DuckDB database file"
    )
    parser.add_argument(
        "--output-dir",
        default="docs/data_dictionary",
        help="Output directory for generated files"
    )
    parser.add_argument(
        "--format",
        choices=["full", "summary"],
        default="full",
        help="Format type: full (detailed tables) or summary (variable lists)"
    )
    parser.add_argument(
        "--export-json",
        action="store_true",
        help="Also generate JSON export of metadata"
    )
    parser.add_argument(
        "--export-html",
        action="store_true",
        help="Also generate HTML version of the data dictionary"
    )

    args = parser.parse_args()

    # Check if database exists
    if not os.path.exists(args.db_path):
        print(f"Database not found: {args.db_path}")
        return 1

    try:
        # Initialize generator
        generator = DataDictionaryGenerator(args.db_path, args.output_dir)

        print(f"Generating {args.format} data dictionary from {args.db_path}")

        # Generate markdown
        markdown_content = generator.generate_markdown(args.format)

        # Save files
        filename = f"ne25_data_dictionary_{args.format}.md"
        generator.save_dictionary(markdown_content, filename)

        if args.export_json:
            generator.generate_json_export()

        if args.export_html:
            html_filename = f"ne25_data_dictionary_{args.format}.html"
            generator.generate_html(markdown_content, html_filename)

        print("Data dictionary generation completed successfully!")
        return 0

    except Exception as e:
        print(f"Error generating data dictionary: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit(main())
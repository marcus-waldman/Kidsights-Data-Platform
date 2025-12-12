# Generate HTML Codebook for SES Analytic Dataset
# Creates a clean, readable HTML table from the CSV codebook
#
# Author: Kidsights Data Platform
# Date: December 2025

library(dplyr)
library(knitr)
library(kableExtra)

cat("===========================================\n")
cat("  HTML Codebook Generator\n")
cat("===========================================\n\n")

# Read codebook
cat("[INFO] Reading codebook...\n")
codebook_path <- file.path("data", "analyses", "ses_analytic_codebook.csv")
codebook <- read.csv(codebook_path, stringsAsFactors = FALSE)

cat("[OK]   Loaded", nrow(codebook), "variables\n\n")

# Create HTML output
cat("[INFO] Generating HTML table...\n")
output_path <- file.path("data", "analyses", "ses_analytic_codebook.html")

# Build HTML document
html_header <- '
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SES Analytic Dataset - Codebook</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }

        .header h1 {
            margin: 0 0 10px 0;
            font-size: 2em;
        }

        .header p {
            margin: 5px 0;
            opacity: 0.9;
        }

        .summary-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }

        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }

        .stat-card .number {
            font-size: 2em;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 5px;
        }

        .stat-card .label {
            color: #666;
            font-size: 0.9em;
        }

        .table-container {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            overflow-x: auto;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9em;
        }

        thead {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            position: sticky;
            top: 0;
            z-index: 10;
        }

        th {
            padding: 15px 10px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #764ba2;
        }

        td {
            padding: 12px 10px;
            border-bottom: 1px solid #eee;
            vertical-align: top;
        }

        tr:hover {
            background-color: #f8f9ff;
        }

        .var-name {
            font-family: "Courier New", monospace;
            font-weight: 600;
            color: #2d3748;
            white-space: nowrap;
        }

        .data-type {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 0.85em;
            font-weight: 500;
        }

        .type-numeric { background: #e6f7ff; color: #0066cc; }
        .type-logical { background: #f0fff0; color: #008800; }
        .type-factor { background: #fff0e6; color: #cc6600; }
        .type-character { background: #f5f0ff; color: #6600cc; }

        .response-options {
            font-size: 0.85em;
            color: #555;
            line-height: 1.4;
        }

        .transformation {
            font-size: 0.85em;
            color: #666;
            font-style: italic;
            background: #f8f9fa;
            padding: 5px 8px;
            border-radius: 4px;
            border-left: 3px solid #667eea;
        }

        .missing-pct {
            text-align: right;
        }

        .high-missing {
            color: #cc0000;
            font-weight: 600;
        }

        .research-question {
            font-size: 0.85em;
            color: #764ba2;
            font-weight: 500;
        }

        .search-container {
            margin-bottom: 20px;
        }

        #searchBox {
            width: 100%;
            padding: 12px 15px;
            font-size: 1em;
            border: 2px solid #e2e8f0;
            border-radius: 8px;
            transition: border-color 0.3s;
        }

        #searchBox:focus {
            outline: none;
            border-color: #667eea;
        }

        .footer {
            text-align: center;
            margin-top: 30px;
            padding: 20px;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>SES Analytic Dataset - Codebook</h1>
        <p>Nebraska Child Development Study (NE25)</p>
        <p>Generated: '
html_header <- paste0(html_header, format(Sys.time(), "%B %d, %Y"), '</p>
    </div>

    <div class="summary-stats">
        <div class="stat-card">
            <div class="number">', nrow(codebook), '</div>
            <div class="label">Total Variables</div>
        </div>
        <div class="stat-card">
            <div class="number">', sum(!is.na(codebook$response_options)), '</div>
            <div class="label">With Response Options</div>
        </div>
        <div class="stat-card">
            <div class="number">', sum(!is.na(codebook$transformation)), '</div>
            <div class="label">With Transformations</div>
        </div>
        <div class="stat-card">
            <div class="number">2,645</div>
            <div class="label">Sample Size</div>
        </div>
    </div>

    <div class="table-container">
        <div class="search-container">
            <input type="text" id="searchBox" placeholder="Search variables, labels, or response options..." onkeyup="searchTable()">
        </div>

        <table id="codeTable">
            <thead>
                <tr>
                    <th style="width: 12%;">Variable Name</th>
                    <th style="width: 20%;">Variable Label</th>
                    <th style="width: 8%;">Data Type</th>
                    <th style="width: 8%;">Missing %</th>
                    <th style="width: 25%;">Response Options</th>
                    <th style="width: 20%;">Transformation</th>
                    <th style="width: 7%;">Research Question</th>
                </tr>
            </thead>
            <tbody>
')

# Build table rows
table_rows <- ""
for (i in seq_len(nrow(codebook))) {
  row <- codebook[i, ]

  # Format data type badge
  type_class <- paste0("type-", tolower(row$data_type))
  type_badge <- sprintf('<span class="data-type %s">%s</span>', type_class, row$data_type)

  # Format missing percentage
  missing_class <- ifelse(row$missing_percentage > 50, "high-missing", "")
  missing_text <- sprintf('<span class="%s">%.1f%%</span>', missing_class, row$missing_percentage)

  # Format response options (replace pipes with line breaks)
  response_text <- ifelse(
    is.na(row$response_options) || row$response_options == "",
    '<span style="color: #ccc;">—</span>',
    gsub(" \\| ", "<br>", row$response_options)
  )

  # Format transformation
  transform_text <- ifelse(
    is.na(row$transformation) || row$transformation == "",
    '<span style="color: #ccc;">—</span>',
    sprintf('<div class="transformation">%s</div>', row$transformation)
  )

  # Format research question
  rq_text <- ifelse(
    is.na(row$research_question) || row$research_question == "",
    '<span style="color: #ccc;">—</span>',
    sprintf('<span class="research-question">%s</span>', row$research_question)
  )

  # Build row HTML
  table_rows <- paste0(table_rows, sprintf('
                <tr>
                    <td class="var-name">%s</td>
                    <td>%s</td>
                    <td>%s</td>
                    <td class="missing-pct">%s</td>
                    <td class="response-options">%s</td>
                    <td>%s</td>
                    <td>%s</td>
                </tr>
',
    row$variable_name,
    row$variable_label,
    type_badge,
    missing_text,
    response_text,
    transform_text,
    rq_text
  ))
}

# JavaScript for search functionality
html_footer <- '
            </tbody>
        </table>
    </div>

    <div class="footer">
        <p><strong>Kidsights Data Platform</strong> | Nebraska Child Development Study</p>
        <p>University of Nebraska Medical Center</p>
    </div>

    <script>
        function searchTable() {
            const input = document.getElementById("searchBox");
            const filter = input.value.toLowerCase();
            const table = document.getElementById("codeTable");
            const rows = table.getElementsByTagName("tr");

            for (let i = 1; i < rows.length; i++) {
                const cells = rows[i].getElementsByTagName("td");
                let found = false;

                for (let j = 0; j < cells.length; j++) {
                    const cell = cells[j];
                    if (cell) {
                        const text = cell.textContent || cell.innerText;
                        if (text.toLowerCase().indexOf(filter) > -1) {
                            found = true;
                            break;
                        }
                    }
                }

                rows[i].style.display = found ? "" : "none";
            }
        }
    </script>
</body>
</html>
'

# Write complete HTML file
html_content <- paste0(html_header, table_rows, html_footer)
writeLines(html_content, output_path)

cat("[OK]   HTML codebook created:", output_path, "\n\n")

cat("===========================================\n")
cat("  Generation Complete!\n")
cat("===========================================\n")
cat("\nOpen the HTML file in your browser:\n")
cat("  ", output_path, "\n\n")

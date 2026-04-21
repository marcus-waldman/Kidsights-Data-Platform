# data/analyses/

Paper-specific analytic datasets produced from the NE25 pipeline outputs. Shared with external collaborators in CSV / RDS / SPSS / Stata.

## These files are gitignored

Everything in this directory EXCEPT this README is ignored by git. The dataset files live only on the maintainer's local machine. To (re)generate them, run the construction scripts below from the repo root after populating the DuckDB database (requires the NE25 + imputation + raking + scoring pipelines to have run — see CLAUDE.md → Running Pipelines).

---

## SES Analytic Dataset (Nebraska 2025)

Supports SES-focused research questions (material hardship, food security, home learning environment, child development outcomes). Actively used by external collaborators.

**Files produced (all local, gitignored):**

| File | Format | Purpose |
|---|---|---|
| `ses_analytic_dataset.csv` | CSV | Tabular, universal |
| `ses_analytic_dataset.rds` | R | Native R format, compressed |
| `ses_analytic_dataset.sav` | SPSS | For SPSS collaborators |
| `ses_analytic_dataset.dta` | Stata | For Stata collaborators |
| `ses_analytic_codebook.csv` | CSV | Variable metadata |
| `ses_analytic_codebook.html` | HTML | Rendered codebook for sharing |

**Construction scripts:**

- [`scripts/analyses/create_ses_analytic_dataset.R`](../../scripts/analyses/create_ses_analytic_dataset.R) — builds the dataset files + codebook CSV
- [`scripts/analyses/generate_codebook_html.R`](../../scripts/analyses/generate_codebook_html.R) — renders the codebook HTML

**Full data guide:** [`docs/analyses/ses_analytic_data_guide.qmd`](../../docs/analyses/ses_analytic_data_guide.qmd) — 114 variables across 17 domains, sample composition, transformation log, variable-renaming map, masking rules. Rendered HTML version served on GitHub Pages.

**Maintenance rule:** When NE25 pipeline outputs change (new derived variables, renamed columns, updated scoring), rerun the construction scripts AND re-render the data guide. The guide imports the `.rds` at render time, so a stale `.rds` means a stale guide.

---

## See also

- **Public onboarding page** — [`docs/index.html`](../../docs/index.html) → Section 08 "Analysis artifacts"
- **Maintainer handoff notes** — [`HANDOFF.md`](../../HANDOFF.md) → "Analysis Artifacts" section

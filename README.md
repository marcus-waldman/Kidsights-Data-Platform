# Kidsights Data Platform

A multi-source ETL platform for childhood development research. Combines local survey data (REDCap) with national datasets (ACS, NHIS, NSCH) to support post-stratification weighting, multiple imputation, and IRT scoring.

> **📖 Authoritative current reference: [CLAUDE.md](CLAUDE.md)**
>
> This README is intentionally short and stable. For current pipeline status, record counts, table inventories, derived variable lists, and operational details, **always read [CLAUDE.md](CLAUDE.md) first** — it's kept in sync with the live system. For per-pipeline detail, see [`docs/`](docs/).

---

## The Eight Pipelines

| # | Pipeline | Purpose | Source |
|---|---|---|---|
| 1 | **NE25** | Nebraska 2025 childhood development survey | REDCap (4 projects) |
| 2 | **MN26** | Minnesota 2026 multi-child household survey | REDCap (NORC-administered) |
| 3 | **ACS** | Census demographics for raking targets | IPUMS USA API |
| 4 | **NHIS** | National benchmarking — mental health, ACEs | IPUMS NHIS API |
| 5 | **NSCH** | National Survey of Children's Health | SPSS files |
| 6 | **Raking Targets** | Population-representative weighting targets | ACS + NHIS + NSCH |
| 7 | **Imputation** | Multiple imputation across geography, sociodem, childcare, mental health, child ACEs | NE25 transformed |
| 8 | **IRT Calibration** | Mplus-compatible psychometric calibration dataset | Multi-study lexicon harmonization |

Each pipeline runs independently and writes to a shared local DuckDB. See [CLAUDE.md → Current Status](CLAUDE.md#current-status-april-2026) for live status of each.

---

## Quick Start

```bash
# 1. Configure environment (one-time)
cp .env.template .env
# Edit .env to set IPUMS_API_KEY_PATH and REDCAP_API_CREDENTIALS_PATH for your machine

# 2. Run the NE25 pipeline (most common entry point)
"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R
```

For the other 7 pipelines, see [CLAUDE.md → Running Pipelines](CLAUDE.md#running-pipelines) for the exact commands.

---

## Installation & Setup

- **Full install guide:** [docs/setup/INSTALLATION_GUIDE.md](docs/setup/INSTALLATION_GUIDE.md)
- **Environment variables:** [docs/setup/ENVIRONMENT_SETUP.md](docs/setup/ENVIRONMENT_SETUP.md)

### Requirements (summary)

- **R 4.5.1+** with `arrow`, `duckdb`, `dplyr`
- **Python 3.13+** with `duckdb`, `pandas`, `pyyaml`, `ipumspy`, `python-dotenv`
- **API keys** configured via `.env` file (see [Environment Configuration](CLAUDE.md#environment-configuration))

The `.env` file is gitignored. Each collaborator maintains their own with machine-specific paths.

---

## Architecture (one paragraph)

**Hybrid R + Python design.** R handles statistical transformations, derived-variable construction, and analysis (REDCap extraction, recoding, IRT scoring, imputation models). Python handles all DuckDB operations (writes, schema management, queries) — this split was introduced in September 2025 to eliminate persistent R DuckDB segmentation faults. The two sides exchange data via Apache Arrow Feather files for fast, type-preserving handoff. All persistent state lives in `data/duckdb/kidsights_local.duckdb`.

For full architectural detail: [docs/architecture/PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md).

---

## Data Storage

| Type | Location |
|---|---|
| Main database | `data/duckdb/kidsights_local.duckdb` |
| NE25 temp Feather | `tempdir()/ne25_pipeline/*.feather` |
| ACS raw | `data/acs/{state}/{year_range}/raw.feather` |
| NHIS raw | `data/nhis/{year_range}/raw.feather` |
| NSCH raw | `data/nsch/{year}/raw.feather` |

The `data/` directory is gitignored.

---

## Top-Level Project Structure

```
Kidsights-Data-Platform/
├── CLAUDE.md                       # Authoritative platform reference
├── README.md                       # This file
├── run_ne25_pipeline.R             # NE25 pipeline orchestrator
├── run_mn26_pipeline.R             # MN26 pipeline orchestrator
├── .env.template                   # Environment variable template (copy to .env)
│
├── R/                              # R source: extract, transform, score, utils
├── python/                         # Python source: db, imputation, ACS/NHIS/NSCH ops
├── pipelines/                      # Pipeline orchestrators (R) and Python pipeline scripts
├── scripts/                        # Utility scripts: imputation, raking, IRT, NSCH, HRTL
├── config/                         # YAML configs (per-source, per-study)
├── codebook/                       # JSON codebook + Quarto dashboard
├── calibration/                    # Manual calibration workflows
├── docs/                           # Documentation (see docs/INDEX.md)
└── data/                           # Local data storage (gitignored)
```

For complete directory detail: [docs/DIRECTORY_STRUCTURE.md](docs/DIRECTORY_STRUCTURE.md).

---

## Documentation Map

- **[CLAUDE.md](CLAUDE.md)** — Authoritative reference: pipeline status, derived variables, coding standards, run commands
- **[docs/INDEX.md](docs/INDEX.md)** — Index of all platform documentation
- **[docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** — Command cheatsheet for all 8 pipelines
- **[docs/architecture/PIPELINE_OVERVIEW.md](docs/architecture/PIPELINE_OVERVIEW.md)** — Architecture details
- **[docs/architecture/PIPELINE_STEPS.md](docs/architecture/PIPELINE_STEPS.md)** — Step-by-step execution
- **[docs/guides/CODING_STANDARDS.md](docs/guides/CODING_STANDARDS.md)** — R namespacing, Windows console, missing data, safe joins
- **[docs/guides/MISSING_DATA_GUIDE.md](docs/guides/MISSING_DATA_GUIDE.md)** — Critical: how missing data is handled in derived variables

Per-pipeline guides live under `docs/{acs,nhis,nsch,raking,imputation,irt_scoring,mn26}/`.

---

## Contributing

1. Read [CLAUDE.md](CLAUDE.md) for current platform state and coding standards
2. Follow R namespacing requirements (e.g., `dplyr::select()` not `select()`) — see [CODING_STANDARDS.md](docs/guides/CODING_STANDARDS.md)
3. Use `recode_missing()` before composite-variable derivation — see [MISSING_DATA_GUIDE.md](docs/guides/MISSING_DATA_GUIDE.md)
4. Use `safe_left_join()` instead of `dplyr::left_join()` (column collision detection)
5. Never commit `.env` or API credential files

---

## License

[Add license information]

---

*Last refreshed: April 2026 (slim rewrite during pre-handoff doc audit). Pipeline counts, record sizes, and statuses live in [CLAUDE.md](CLAUDE.md), not here, to prevent README drift.*

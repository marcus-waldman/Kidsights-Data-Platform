# Authenticity Screening Documentation

**Authenticity screening** identifies and flags inauthentic or careless response patterns in developmental survey data using IRT-based influence diagnostics. Also known as "influence diagnostics" in some scripts.

> ⚠️ **MANUAL workflow.** Authenticity screening is **not automated** in the NE25 pipeline. It must be run separately with researcher review at multiple decision points. See [`scripts/influence_diagnostics/README.md`](../../scripts/influence_diagnostics/README.md) for the full rationale.

## Documents in This Directory

| Doc | Purpose |
|---|---|
| **[AUTHENTICITY_DATA_ARCHITECTURE.md](AUTHENTICITY_DATA_ARCHITECTURE.md)** | Schema and data flow for authenticity screening tables and intermediate artifacts |
| **[ETA_ESTIMATE_EXTRACTION.md](ETA_ESTIMATE_EXTRACTION.md)** | How to extract eta (latent factor score) estimates from Mplus output for influence diagnostics |
| **[authenticity_screening_results.md](authenticity_screening_results.md)** | Results from a specific run of the authenticity screening workflow |

## Related Code

- **Workflow scripts:** [`scripts/influence_diagnostics/`](../../scripts/influence_diagnostics/) — also see the README there for the manual screening procedure
- **Authenticity proposal:** [`models/in_development/authenticity_gamma_weights_proposal.md`](../../models/in_development/authenticity_gamma_weights_proposal.md) and [`models/SKEWNESS_PENALIZED_AUTHENTICITY.md`](../../models/SKEWNESS_PENALIZED_AUTHENTICITY.md)

## Pipeline Integration

The NE25 pipeline (Step 6.5) **conditionally joins** influence diagnostics from the `ne25_flagged_observations` table if it exists. The pipeline does NOT run the authenticity screening itself — that's an out-of-band manual workflow whose output is loaded into the database for downstream use.

For current status and integration details, see [`CLAUDE.md → NE25 Pipeline → Influential Observations`](../../CLAUDE.md#-ne25-pipeline---production-ready-december-2025).

---

*Created: April 2026 (during pre-handoff doc audit)*

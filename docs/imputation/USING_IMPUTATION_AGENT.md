# Using the Imputation Specialist Agent

**Created:** October 2025
**Purpose:** Guide for using the Claude Code imputation specialist subagent

---

## What is the Imputation Specialist Agent?

The imputation specialist is a **domain-expert Claude Code subagent** specifically trained on:

- Geographic imputation pipeline architecture
- Multiple imputation methodology and theory
- Database schema for imputation storage
- Python and R helper functions for retrieving completed datasets
- Configuration management and scaling M

This agent has deep knowledge of the imputation pipeline documentation and can help with common tasks more efficiently than the general-purpose agent.

---

## When to Use the Imputation Agent

Use the imputation specialist when you need help with:

✅ **Scaling M** - Changing from M=5 to M=20 or more imputations
✅ **Adding variables** - Extending imputation to new geographic or non-geographic variables
✅ **Helper functions** - Guidance on using `get_completed_dataset()`, `get_all_imputations()`, etc.
✅ **Variance estimation** - Implementing Rubin's rules for combining results across imputations
✅ **Database queries** - Querying imputation tables directly when helper functions aren't suitable
✅ **Troubleshooting** - Diagnosing issues with imputation generation or retrieval
✅ **Multi-study support** - Configuring imputation for new studies (NC26, etc.)
✅ **Statistical consultation** - Understanding MI theory, allocation factors, selective storage

**Don't use the imputation agent for:**

❌ General coding tasks unrelated to imputation
❌ Other pipeline work (use raking-specialist for raking targets)
❌ Database management outside of imputation tables
❌ REDCap or survey data processing (use general agent)

---

## Agent Configuration

**Location:** `.claude/agents/imputation-specialist.yaml`

**Available Tools:**
- Read - Read imputation scripts, configs, and documentation
- Glob - Find imputation-related files
- Grep - Search for specific patterns in imputation code
- Bash - Run Python/R imputation scripts
- Edit - Modify imputation code
- Write - Create new imputation scripts or docs

**Key Documentation the Agent Knows:**
- `docs/imputation/IMPUTATION_PIPELINE.md` - Complete architecture
- `docs/imputation/IMPUTATION_SETUP_COMPLETE.md` - Setup and usage guide
- `config/imputation/imputation_config.yaml` - Configuration source of truth

---

## Example Use Cases

### Use Case 1: Scaling M from 5 to 20

**Question:** "How do I increase the number of imputations from M=5 to M=20?"

**Agent Response Would Include:**
1. Edit `config/imputation/imputation_config.yaml`: change `n_imputations: 5` to `n_imputations: 20`
2. Re-run `python scripts/imputation/01_impute_geography.py`
3. Estimated runtime: ~5-10 seconds (4x more imputations)
4. Storage impact: 101,932 rows (4x current 25,483)
5. Validation: Run `python -m python.imputation.helpers` to confirm M=20

### Use Case 2: Understanding Census Tract Ambiguity

**Question:** "Why do 94% of records have census tract ambiguity? Is this an error?"

**Agent Response Would Include:**
- This is EXPECTED behavior, not an error
- ZIP codes often span multiple census tracts (complex geographic boundaries)
- PUMA has lower ambiguity (26.1%) because PUMAs are larger geographic units
- Only 5.9% of records have deterministic census tract assignment (afact = 1)
- This reflects real geographic uncertainty in the source data

### Use Case 3: Adding a New Imputed Variable

**Question:** "How do I extend the imputation pipeline to handle income uncertainty?"

**Agent Response Would Include:**
1. Add `income` to `config/imputation/imputation_config.yaml` under new section
2. Create SQL table in `sql/imputation/create_imputation_tables.sql`
3. Extend `scripts/imputation/01_impute_geography.py` with new imputation logic
4. Update `python/imputation/helpers.py` to handle income variable
5. Update `R/imputation/helpers.R` (no changes needed if using reticulate properly)
6. Document the new variable in `docs/imputation/IMPUTATION_PIPELINE.md`

### Use Case 4: Using Helper Functions in R

**Question:** "How do I retrieve all M=5 imputations in R for variance estimation?"

**Agent Response Would Include:**
```r
library(reticulate)
source("R/imputation/helpers.R")

# Get all imputations in long format (M × N rows)
all_imp <- get_all_imputations(
  variables = c("puma", "county", "census_tract"),
  study_id = "ne25"
)

# Get list format for survey package
imp_list <- get_imputation_list(
  variables = c("puma", "county", "census_tract"),
  study_id = "ne25"
)

# Now you have list(data1, data2, data3, data4, data5) for MI analysis
```

---

## Agent Limitations

The imputation specialist agent:

- **Only knows imputation domain** - Won't help with NE25 pipeline, raking targets, or general R/Python tasks
- **Knows current implementation** - Docs updated October 2025, reflects M=5 production state
- **Can't run code directly** - Can show you commands and explain, but you execute them
- **Focused on geography** - Primary expertise is PUMA/county/tract imputation (can generalize to other variables)

---

## Comparison with General Agent

| Task | General Agent | Imputation Specialist |
|------|---------------|----------------------|
| Scale M from 5 to 20 | Can help, but slower | Fast, knows exact file and line |
| Debug database query | General knowledge | Knows exact schema and indexes |
| Explain afact system | Would need to read docs | Instant, deep understanding |
| Add new imputed variable | Can help with guidance | Step-by-step with examples |
| NE25 pipeline issue | Better choice | Not specialized for this |
| Raking targets question | Can help | Use raking-specialist instead |

---

## Tips for Best Results

1. **Be specific** - "How do I scale M to 20?" is better than "How do I change config?"
2. **Mention context** - "I'm using R via reticulate" helps agent give relevant examples
3. **Ask for examples** - Agent knows the codebase, can show actual file locations
4. **Request validation steps** - Agent can suggest specific checks to run after changes
5. **Combine with Task tool** - General agent can invoke imputation-specialist for sub-tasks

---

## Related Agents

- **raking-specialist** - For raking targets pipeline, bootstrap variance, survey weighting
- **general** - For NE25 pipeline, ACS/NHIS/NSCH pipelines, database management

---

**Last Updated:** October 2025
**Status:** Production ready, aligned with M=5 imputation implementation

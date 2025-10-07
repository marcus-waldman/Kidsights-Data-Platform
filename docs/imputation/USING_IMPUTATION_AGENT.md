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
✅ **Helper functions** - Guidance on using `get_completed_dataset()`, `get_all_imputations()`, `validate_imputations()`, etc.
✅ **Variance estimation** - Implementing Rubin's rules for combining results across imputations (mitools in R)
✅ **Database queries** - Querying study-specific imputation tables (`{study_id}_imputed_{variable}`)
✅ **Troubleshooting** - Diagnosing issues with imputation generation, retrieval, or validation
✅ **Multi-study support** - Adding new studies (ia26, co27, etc.) using automated setup script
✅ **Cross-study analysis** - Pooling data across studies, meta-analysis with proper MI variance
✅ **Statistical consultation** - Understanding MI theory, MICE methods, allocation factors, study-specific architecture

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
- `docs/imputation/STUDY_SPECIFIC_MIGRATION_PLAN.md` - Multi-study architecture guide
- `docs/imputation/ADDING_NEW_STUDY.md` - Complete onboarding guide for new studies
- `python/imputation/README.md` - Python helper functions documentation
- `R/imputation/README.md` - R interface documentation
- `examples/imputation/README.md` - Usage examples for all scenarios
- `config/imputation/ne25_config.yaml` - Study-specific configuration example

---

## Example Use Cases

### Use Case 1: Scaling M from 5 to 20

**Question:** "How do I increase the number of imputations from M=5 to M=20 for study ne25?"

**Agent Response Would Include:**
1. Edit `config/imputation/ne25_config.yaml`: change `n_imputations: 5` to `n_imputations: 20`
2. Re-run geography imputation:
   ```bash
   python scripts/imputation/ne25/01_impute_geography.py
   ```
3. Re-run sociodemographic imputation:
   ```bash
   "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/02_impute_sociodemographic.R
   python scripts/imputation/ne25/02b_insert_sociodem_imputations.py
   ```
4. Estimated runtime: Geography (~10 seconds), Sociodem (~90 seconds)
5. Storage impact: Geography 101,932 rows (4x current 25,483), Sociodem ~52,000 rows
6. Validation: Run `validate_imputations(study_id='ne25')` to confirm M=20

### Use Case 2: Understanding Census Tract Ambiguity

**Question:** "Why do 94% of records have census tract ambiguity? Is this an error?"

**Agent Response Would Include:**
- This is EXPECTED behavior, not an error
- ZIP codes often span multiple census tracts (complex geographic boundaries)
- PUMA has lower ambiguity (26.1%) because PUMAs are larger geographic units
- Only 5.9% of records have deterministic census tract assignment (afact = 1)
- This reflects real geographic uncertainty in the source data

### Use Case 3: Querying Childcare Imputations

**Question:** "How do I retrieve childcare variables from the imputation pipeline?"

**Agent Response Would Include:**
```python
from python.imputation.helpers import get_childcare_imputations, get_complete_dataset

# Option 1: Get just childcare variables (4 variables)
childcare = get_childcare_imputations(study_id='ne25', imputation_number=1)
# Returns: cc_receives_care, cc_primary_type, cc_hours_per_week, childcare_10hrs_nonfamily

# Option 2: Get ALL 14 imputed variables (geography + sociodem + childcare)
complete = get_complete_dataset(study_id='ne25', imputation_number=1)
# Returns: puma, county, census_tract, female, raceG, educ_mom, educ_a2,
#          income, family_size, fplcat, + 4 childcare variables

# Option 3: Get with base data for additional covariates
complete_with_base = get_complete_dataset(
    study_id='ne25',
    imputation_number=1,
    include_base_data=True
)
# Returns: All transformed variables + 14 imputed variables
```

**Childcare Pipeline Architecture (3-Stage Sequential):**
1. **Stage 1:** Impute `cc_receives_care` (Yes/No) using CART
2. **Stage 2:** Conditional imputation of `cc_primary_type` and `cc_hours_per_week`
   - Only for records with `cc_receives_care = "Yes"`
3. **Stage 3:** Derive `childcare_10hrs_nonfamily` from completed upstream variables
   - TRUE if hours ≥10 AND type ≠ "Relative care"

**Key Features:**
- Defensive NULL filtering prevents database constraint violations
- Data cleaning caps hours at 168/week (prevents outlier propagation)
- Conditional logic maintained (type/hours only imputed for "Yes" responses)

**Complete examples:** `examples/imputation/04_advanced_multistudy_queries.py`

### Use Case 4: Adding a New Study

**Question:** "How do I set up imputation for a new study (ia26)?"

**Agent Response Would Include:**
1. Run automated setup script:
   ```bash
   python scripts/imputation/create_new_study.py --study-id ia26 --study-name "Iowa 2026"
   ```
2. Customize `config/imputation/ia26_config.yaml`:
   - Update variable lists (geography, sociodemographic)
   - Update auxiliary variables for MICE
   - Adjust MICE methods if needed
3. Review and customize pipeline scripts in `scripts/imputation/ia26/`
4. Create database schema:
   ```bash
   python scripts/imputation/00_setup_imputation_schema.py --study-id ia26
   ```
5. Run full pipeline:
   ```bash
   "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ia26/run_full_imputation_pipeline.R
   ```
6. Validate results:
   ```python
   from python.imputation.helpers import validate_imputations
   validate_imputations(study_id='ia26')
   ```
7. Complete guide: `docs/imputation/ADDING_NEW_STUDY.md`

### Use Case 4: Using Helper Functions in R

**Question:** "How do I retrieve all M=5 imputations in R for variance estimation for study ne25?"

**Agent Response Would Include:**
```r
library(reticulate)
source("R/imputation/helpers.R")

# Get all imputations in long format (M × N rows)
all_imp <- get_all_imputations(
  variables = c("puma", "county", "census_tract"),
  study_id = "ne25"
)

# Get list format for mitools package (for Rubin's rules)
imp_list <- get_imputation_list(
  variables = c("puma", "county", "census_tract"),
  study_id = "ne25"
)

# Now you have list(data1, data2, data3, data4, data5) for MI analysis
# Example: Survey-weighted analysis with MI
library(survey)
library(mitools)

designs <- lapply(imp_list, function(df) {
  svydesign(ids = ~1, weights = ~weight, data = df)
})

results <- lapply(designs, function(d) svymean(~age, d))
combined <- MIcombine(results)
summary(combined)
```

**Complete examples:** `examples/imputation/02_survey_analysis_r.R`

---

## Agent Limitations

The imputation specialist agent:

- **Only knows imputation domain** - Won't help with NE25 pipeline, raking targets, or general R/Python tasks
- **Knows current implementation** - Docs updated October 2025, reflects multi-study architecture with M=5 default
- **Can't run code directly** - Can show you commands and explain, but you execute them
- **Focused on geography + sociodem + childcare** - Primary expertise is PUMA/county/tract + sociodemographic + childcare imputation via MICE (3-stage sequential)

---

## Comparison with General Agent

| Task | General Agent | Imputation Specialist |
|------|---------------|----------------------|
| Scale M from 5 to 20 | Can help, but slower | Fast, knows exact study config file |
| Add new study (ia26) | Can help with guidance | Automated script + complete checklist |
| Debug database query | General knowledge | Knows study-specific table schema |
| Explain afact system | Would need to read docs | Instant, deep understanding |
| Cross-study analysis | Can help | Knows pooling patterns, meta-analysis |
| MICE configuration | General knowledge | Knows method selection, auxiliary vars |
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

## Troubleshooting Childcare Imputations

### Issue 1: NULL Constraint Violation in Childcare Tables

**Error:** `NOT NULL constraint failed` when inserting childcare imputations

**Cause:** Records with incomplete auxiliary variables (missing geography or sociodem) cannot be imputed

**Solution:** This is expected behavior with defensive programming
- Imputation scripts filter out NULL values before database insertion
- Only successfully imputed records are stored
- Check `scripts/imputation/ne25/03a_impute_cc_receives_care.R` lines 286-289 for NULL filtering

**Validation:**
```python
from python.imputation.helpers import validate_imputations
results = validate_imputations(study_id='ne25')
# Should show 0 NULL values
```

### Issue 2: Impossible Hours Values (>168 hours/week)

**Error:** Validation shows hours > 168 (impossible - only 168 hours in a week)

**Cause:** Data entry error in source data propagated via mice PMM (predictive mean matching)

**Solution:** Data cleaning is now built into `03b_impute_cc_type_hours.R` (lines 149-166)
- Caps `cc_hours_per_week` at 168 before imputation
- Sets outliers to NA (will be imputed with plausible values)

**Verification:**
```bash
Rscript scripts/imputation/ne25/test_childcare_diagnostics.R
# Check 1 should show Max=95.0, Outliers=0
```

### Issue 3: cc_primary_type Present When cc_receives_care = "No"

**Error:** Records have childcare type but no childcare usage

**Cause:** Conditional imputation logic not working

**Solution:** Verify Stage 2 filters to `cc_receives_care = TRUE` only
- Check `scripts/imputation/ne25/03b_impute_cc_type_hours.R` line 277
- Should see: `Filtered to cc_receives_care = TRUE: XXXX records`

**Diagnostic:**
```bash
Rscript scripts/imputation/ne25/test_childcare_diagnostics.R
# Check 3 should show 0 inconsistencies
```

### Issue 4: All Imputations Identical (No Variation)

**Error:** All M imputations have the same values

**Cause:**
1. Observed values (not imputed) naturally show 100% constancy
2. Derived variables inherit stability from upstream variables

**Solution:** Check variance diagnostics
```bash
Rscript scripts/imputation/ne25/test_childcare_diagnostics.R
# Diagnostic 2 shows constancy rates
# Expected: ~50% for imputed values, ~96% for derived childcare_10hrs_nonfamily
```

**Note:** High constancy in `childcare_10hrs_nonfamily` (96%) is EXPECTED
- This is a derived variable that inherits from upstream stable values
- Not a sign of convergence issues

### Issue 5: Childcare Variables Missing from get_complete_dataset()

**Error:** `get_complete_dataset()` doesn't include childcare variables

**Cause:** Using old version of helper function (pre-childcare)

**Solution:** Update to latest helpers:
```python
from python.imputation.helpers import get_complete_dataset

# This should return ALL 14 variables (3 geo + 7 sociodem + 4 childcare)
df = get_complete_dataset(study_id='ne25', imputation_number=1)
print(df.columns)
# Should include: cc_receives_care, cc_primary_type, cc_hours_per_week, childcare_10hrs_nonfamily
```

---

## Related Agents

- **raking-specialist** - For raking targets pipeline, bootstrap variance, survey weighting
- **general** - For NE25 pipeline, ACS/NHIS/NSCH pipelines, database management

---

## Quick Reference: Multi-Study Commands

**Check available studies:**
```python
from python.imputation.helpers import get_imputation_metadata
metadata = get_imputation_metadata()
print(metadata['study_id'].unique())  # ['ne25', 'ia26', ...]
```

**Add new study:**
```bash
python scripts/imputation/create_new_study.py --study-id ia26 --study-name "Iowa 2026"
```

**Run study-specific pipeline:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/{study_id}/run_full_imputation_pipeline.R
```

**Validate study:**
```python
from python.imputation.helpers import validate_imputations
validate_imputations(study_id='ne25')
```

**Cross-study analysis examples:** `examples/imputation/04_advanced_multistudy_queries.py`

---

**Last Updated:** October 2025
**Status:** Production ready, aligned with multi-study architecture (study_id parameter throughout)

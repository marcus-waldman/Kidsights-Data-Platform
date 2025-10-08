# Using the Imputation Stage Builder Agent

**Last Updated:** October 8, 2025 | **Version:** 1.0.0

**Purpose:** Complete guide for using the `imputation-stage-builder` agent to add new imputation stages

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [What is the Stage Builder Agent?](#what-is-the-stage-builder-agent)
3. [When to Use This Agent](#when-to-use-this-agent)
4. [Detailed Usage Guide](#detailed-usage-guide)
5. [Examples](#examples)
6. [Completing TODO Markers](#completing-todo-markers)
7. [Troubleshooting](#troubleshooting)
8. [FAQ](#faq)

---

## Quick Start

**3-Step Process to Add a New Imputation Stage:**

### Step 1: Invoke the Agent

```
User: "I want to add [domain] imputation to the pipeline"
```

Example:
```
User: "I want to add adult depression (PHQ-9) imputation to the pipeline"
```

### Step 2: Answer Questions

The agent will ask you for:
1. **Stage number** - Next sequential number (check existing stages)
2. **Domain name** - Short identifier (e.g., "adult_depression")
3. **Variables** - List of variable names to impute
4. **Data types** - INTEGER, DOUBLE, BOOLEAN, or VARCHAR for each variable
5. **MICE method** - cart, rf, pmm, or logreg
6. **Derived variables** - Any calculated from imputed values
7. **Conditional logic** - Whether imputation depends on other variables
8. **Auxiliary variables** - Which predictors to make available
9. **Study ID** - Usually "ne25"

###Step 3: Complete TODOs and Test

The agent generates files with TODO markers. You must:
1. Complete all TODO markers (statistical decisions, domain logic)
2. Test R script: `Rscript scripts/imputation/ne25/XX_impute_{domain}.R`
3. Test Python script: `py scripts/imputation/ne25/XXb_insert_{domain}.py`
4. Request integration: "Please integrate this stage into the pipeline"

**Time Savings:** ~3.5 hours (from 4 hours manual to 30 minutes with agent)

---

## What is the Stage Builder Agent?

The `imputation-stage-builder` is a specialized Claude Code agent that **automates the mechanical work** of adding new imputation stages while preserving the need for **statistical expertise**.

### Agent Capabilities (What It DOES)

✅ **Scaffolding Mode:**
- Generates R imputation script templates (~1300 lines)
- Generates Python database insertion scripts (~800 lines)
- Creates directory structure for Feather files
- Enforces all mechanical patterns (seeds, filtering, naming)
- Inserts TODO markers for decisions requiring expertise

✅ **Integration Mode:**
- Generates pipeline orchestrator code
- Generates Python helper functions
- Provides documentation update snippets

✅ **Validation Mode:**
- Audits existing implementations
- Checks 8 critical patterns
- Generates compliance reports
- Offers fixes for violations

### What It Does NOT Do (Requires Human Expertise)

❌ **Statistical Decisions:**
- Choosing MICE method (cart vs. rf vs. pmm vs. logreg)
- Selecting auxiliary variables for predictor matrix
- Setting method parameters (maxit, ntree, etc.)
- Validating statistical assumptions

❌ **Domain Logic:**
- Defining variable relationships
- Writing derived variable formulas
- Creating validation rules
- Interpreting missing data patterns

❌ **Data Analysis:**
- Examining correlation structures
- Assessing sample size adequacy
- Diagnosing convergence issues
- Evaluating imputation quality

### Design Philosophy

**70% Automation + 30% Expertise = 100% Quality**

The agent handles repetitive pattern-following so you can focus on the intellectual work that requires domain knowledge and statistical judgment.

---

## When to Use This Agent

### Use the Agent For:

✅ **Adding new imputation stages** - Primary use case
✅ **Validating existing implementations** - Quality assurance
✅ **Learning imputation patterns** - Educational tool for new team members
✅ **Ensuring pattern compliance** - Before committing code

### Do NOT Use the Agent For:

❌ General-purpose coding tasks
❌ Modifying core imputation infrastructure
❌ Statistical analysis of imputation results
❌ Database management outside imputation tables
❌ Other pipeline work (use appropriate specialist agents)

### When to Implement Manually:

Consider manual implementation if:
- Imputation logic is highly unusual and doesn't fit patterns
- You're experimenting with new MICE methods
- Integration with external imputation tools is needed
- The domain requires custom algorithms

---

## Detailed Usage Guide

### Mode 1: Scaffolding New Stages

**When:** Adding a new imputation stage from scratch

**Process:**

#### 1. Prepare Information

Before invoking the agent, gather:
- **Variable list** - Check codebook for exact names
- **Data types** - Query database or check transformed table
- **Sample data** - Understand value ranges and missing patterns
- **Theoretical model** - Which variables should predict which

#### 2. Invoke Agent

```
User: "I want to add {domain} imputation using {method}"
```

Examples:
```
User: "I want to add perceived stress imputation using CART"
User: "I want to add employment status and details with conditional imputation"
```

#### 3. Answer Questions

Agent asks 9 questions. Answer carefully:

**Q1: Stage Number**
```
Agent: "What stage number should this be?"
```
- Check existing: `ls scripts/imputation/ne25/*_impute_*.R`
- Use next sequential number
- Agent warns if you skip numbers

**Q2: Domain Name**
```
Agent: "What domain are these variables from?"
```
- Use lowercase, underscores (e.g., "adult_depression")
- Keep concise (used in function names)
- Avoid special characters

**Q3: Variables**
```
Agent: "What are the exact variable names to impute?"
```
- Provide complete list
- Separate items from derived variables
- Specify data types for each

**Q4: MICE Method**
```
Agent: "What imputation method(s)?"
```
- **cart**: Classification/regression trees (robust, most common)
- **rf**: Random forest (best for complex interactions, needs N > 100)
- **pmm**: Predictive mean matching (preserves distribution, continuous vars)
- **logreg**: Logistic regression (binary variables)

**Q5: Derived Variables**
```
Agent: "Are there any derived variables?"
```
- List variables calculated AFTER imputation
- Provide formulas (e.g., "sum of items 1-9")
- Specify if conditional on other variables

**Q6: Conditional Logic**
```
Agent: "Does this require conditional imputation?"
```
- **No**: All variables imputed for all eligible records
- **Yes**: Some variables only imputed if condition met
  - Provide gating variable and condition
  - Example: "hours_per_week only if employed = 1"

**Q7: Auxiliary Variables**
```
Agent: "Which auxiliary variables should be available?"
```
- Always available: puma, female, age_years, authentic.x
- From previous stages: sociodem vars, mental health vars, etc.
- Consider theoretical relationships

**Q8: Study ID**
```
Agent: "Which study?"
```
- Default: "ne25"
- Future: "ia26", "co27", etc.

#### 4. Confirm Generation

Agent shows what it will create:
```
Based on your input, I'll create:

📁 R Script: scripts/imputation/ne25/07_impute_perceived_stress.R
📁 Python Script: scripts/imputation/ne25/07b_insert_perceived_stress.py
📁 Output Directory: data/imputation/ne25/perceived_stress_feather/

Variables to impute: pss_1, pss_2, pss_3, pss_4
Derived variables: pss_total
Method: cart
Conditional: No

Is this correct?
```

Type "yes" to proceed.

#### 5. Review Generated Files

Agent creates files and provides checklist:
```
✅ Files Created:
- [x] R script: scripts/imputation/ne25/07_impute_perceived_stress.R (1306 lines)
- [x] Python script: scripts/imputation/ne25/07b_insert_perceived_stress.py (818 lines)
- [x] Output directory: data/imputation/ne25/perceived_stress_feather/

📝 Your Next Steps (Complete TODOs):
1. Review R Script - Configure predictor matrix, verify MICE methods
2. Review Python Script - Verify data types, add validation rules
3. Test Execution - Run R script, check output, run Python script
4. Integration - Request pipeline integration when ready
```

---

### Mode 2: Validation of Existing Stages

**When:** Quality assurance, debugging, before committing

**Process:**

#### 1. Invoke Validation

```
User: "Validate Stage 7"
User: "Check if scripts/imputation/ne25/05_impute_adult_mental_health.R follows patterns"
```

#### 2. Agent Reads Files

Agent automatically:
- Finds R and Python scripts
- Reads both files
- Runs 8 critical pattern checks

#### 3. Review Validation Report

Agent generates detailed report:
```
=============================================================================
VALIDATION REPORT: Stage 07 (perceived_stress)
=============================================================================

Files Validated:
  R Script: scripts/imputation/ne25/07_impute_perceived_stress.R
  Python Script: scripts/imputation/ne25/07b_insert_perceived_stress.py

CRITICAL CHECKS
=============================================================================

✅ PASS: Seed Usage Pattern
   Found: set.seed(seed + m) at line 439

❌ FAIL: Storage Convention
   Line 268: Saving all records instead of only originally_missing
   Impact: IMPORTANT - May overwrite observed values

IMPORTANT CHECKS
=============================================================================

❌ FAIL: Metadata Tracking
   Expected: 5 update_metadata() calls (one per variable)
   Found: 0 calls
   Impact: IMPORTANT - Prevents auditing

...

SUMMARY
=============================================================================

Overall Status: ❌ FAILED (2 failures, 0 warnings)

Would you like me to generate corrected code for these issues?
```

#### 4. Fix Issues

If failures found:
```
User: "Yes, please fix these issues"
```

Agent provides corrected code snippets.

---

### Mode 3: Pipeline Integration

**When:** After R and Python scripts are complete and tested

**Process:**

#### 1. Request Integration

```
User: "Please integrate Stage 7 (perceived stress) into the pipeline"
```

#### 2. Agent Generates Code

Agent provides 3 code snippets:

**Snippet 1: Pipeline Orchestrator**
```r
# Code to add to run_full_imputation_pipeline.R
# Shows where to insert (after last existing stage)
```

**Snippet 2: Python Helper Function**
```python
# Code to add to python/imputation/helpers.py
def get_perceived_stress_imputations(...):
    ...
```

**Snippet 3: Documentation Updates**
```markdown
# Snippets for CLAUDE.md, PIPELINE_OVERVIEW.md, QUICK_REFERENCE.md
```

#### 3. Apply Updates

Manually add code to files or request agent to do it:
```
User: "Please add the orchestrator code to the pipeline file"
```

---

## Examples

### Example 1: Simple Unconditional Imputation (PSS-4)

**Scenario:** Add Perceived Stress Scale (4 items + total score)

**Dialog:**
```
User: "I want to add perceived stress imputation using CART"

Agent: "I'll help you add perceived stress imputation. I need some information:
1. What stage number should this be?"

User: "Stage 7"

Agent: "2. What domain are these variables from?"

User: "perceived_stress"

Agent: "3. What are the exact variable names to impute?"

User: "pss_1, pss_2, pss_3, pss_4 - all are INTEGER (0-4 Likert scale)"

Agent: "4. Are there any derived variables?"

User: "Yes, pss_total which is the sum of the 4 items (0-16 range)"

Agent: "5. Does this require conditional imputation?"

User: "No, impute all variables for all eligible records"

Agent: "6. Which auxiliary variables should be available?"

User: "puma, female, age_years, raceG, income, educ_mom, phq2_positive"

Agent: "Based on your input, I'll create:
...
Is this correct?"

User: "Yes"

Agent: [Generates files with TODO markers]
```

**TODO Completion:**
1. R Script: Configure predictor matrix (which aux vars predict which PSS items?)
2. R Script: Decide if PSS items should predict each other
3. Python Script: Add validation for 0-4 range on items, 0-16 range on total

**Testing:**
```bash
"C:\Program Files\R\R-4.5.1\bin\Rscript.exe" scripts/imputation/ne25/07_impute_perceived_stress.R
# Check: data/imputation/ne25/perceived_stress_feather/ has 5 * M files

py scripts/imputation/ne25/07b_insert_perceived_stress.py
# Check: Database has 5 new tables
```

---

### Example 2: Conditional Imputation (Employment)

**Scenario:** Employment status gates hours and job type

**Dialog:**
```
User: "I want to add employment imputation with conditional logic"

Agent: [Standard questions...]

User: "Variables: employed (INTEGER binary), hours_per_week (DOUBLE), job_type (VARCHAR)"

Agent: "Does this require conditional imputation?"

User: "Yes, hours_per_week and job_type should only be imputed if employed = 1"

Agent: "I'll create a two-stage conditional imputation:
  Stage 1: Impute employed unconditionally
  Stage 2: Filter to employed==1, impute hours_per_week and job_type

Is this correct?"

User: "Yes"
```

**TODO Completion:**
1. R Script: Handle case where no one is employed in imputation m (nrow() == 0)
2. R Script: Decide if employed should predict hours/job_type
3. Python Script: Handle missing Feather files (required=False)
4. Python Script: Add validation for 1-80 hours range, valid job_type categories

---

### Example 3: Multi-Item Scale (PSI-SF)

**Scenario:** 12-item parenting stress scale with subscales

**Dialog:**
```
User: "I want to add parenting stress (PSI-SF 12 items) using random forest"

Agent: [Questions about 12 items...]

User: "Derived variables: psi_total (sum of 12), plus 3 subscales (each sum of 4 items), plus psi_high_stress (total >= 33)"

Agent: "Random forest with 12 variables will be computationally intensive.
Recommendations:
- Ensure N > 100 for adequate sample size
- Consider ntree=10 for performance
- Increase maxit to 10 for convergence

Should I proceed with these parameters?"

User: "Yes, use ntree=10 and maxit=10"
```

**TODO Completion:**
1. R Script: Verify sample size is adequate (N > 100)
2. R Script: Configure predictor matrix - should all 12 items predict each other?
3. R Script: Verify subscale groupings are correct
4. Python Script: Add validation for 1-5 range (items), 4-20 (subscales), 12-60 (total)

---

## Completing TODO Markers

The agent inserts TODO markers in 6 categories. Here's how to complete each:

### [DOMAIN LOGIC] - Requires domain expertise

**What:** Decisions about variable relationships and domain-specific logic

**Examples:**
```r
# TODO: [DOMAIN LOGIC] Configure predictor matrix
# Which auxiliary variables should predict which target variables?
```

**How to Complete:**
1. Consider theoretical model (what predicts what?)
2. Review correlation matrix between targets and auxiliaries
3. Consult literature on similar measures
4. Start conservative (fewer predictors), expand if needed

**Resources:**
- Codebook for variable definitions
- Literature on the construct being measured
- Existing similar implementations in pipeline

---

### [STATISTICAL DECISION] - Requires statistical judgment

**What:** Choices about imputation methods and parameters

**Examples:**
```r
# TODO: [STATISTICAL DECISION] Verify MICE method is appropriate
# Current method: cart
# Is variable type matched to method?
```

**How to Complete:**
1. Match method to variable type:
   - Binary → logreg or cart
   - Ordinal (3-5 categories) → cart
   - Continuous → pmm or cart
   - Categorical (>5 categories) → cart or polyreg
2. Consider sample size (rf needs N > 100)
3. Review MICE diagnostics after test run

**Resources:**
- `mice` package documentation
- van Buuren "Flexible Imputation of Missing Data"
- Similar implementations in existing stages

---

### [VALIDATION RULE] - Requires domain-specific validation

**What:** Checks for data quality and plausibility

**Examples:**
```python
# TODO: [VALIDATION RULE] Add value range validation for pss_total
# Expected range: 0-16 (sum of 4 items, each 0-4)
```

**How to Complete:**
1. Define expected range from codebook
2. Add query to check violations:
```python
if variable == "pss_total":
    range_check = conn.execute(
        f"SELECT COUNT(*) FROM {table_prefix}_imputed_pss_total
        WHERE pss_total < 0 OR pss_total > 16"
    ).fetchone()[0]
    if range_check > 0:
        print(f"  [WARN] pss_total: {range_check} values out of expected range")
```
3. Consider logical relationships (e.g., total should equal sum of items)

---

### [DATA TYPE] - Requires verification

**What:** SQL data type selection for each variable

**Examples:**
```python
# TODO: [DATA TYPE] Verify INTEGER for 0-4 Likert scale
```

**How to Complete:**
- **INTEGER**: Whole numbers (binary, Likert scales, counts)
- **DOUBLE**: Decimals (continuous measures, percentages)
- **BOOLEAN**: True/false (rare in imputation)
- **VARCHAR**: Text categories (job titles, etc.)

**Rule of thumb:** If codebook shows decimal values, use DOUBLE. Otherwise INTEGER.

---

### [CONFIGURATION] - Requires confirmation

**What:** File paths, study settings, parameters

**Examples:**
```r
# TODO: [CONFIGURATION] Review configuration values
```

**How to Complete:**
1. Verify study_id is correct
2. Check output paths exist and are writable
3. Confirm M and seed values from config
4. No changes usually needed (defaults are correct)

---

### [SETUP] - Requires environment verification

**What:** Package installation, versions, environment

**Examples:**
```r
# TODO: [SETUP] Verify all required packages are installed
# Run: install.packages(c("duckdb", "dplyr", "mice", "arrow"))
```

**How to Complete:**
1. Run package installation command if needed
2. Verify R version >= 4.5.1
3. Check mice version (>= 3.16.0 recommended)
4. Test script runs without library load errors

---

## Troubleshooting

### Issue 1: Agent Doesn't Understand My Request

**Symptom:** Agent asks clarifying questions or seems confused

**Solutions:**
- Be more specific: "Add PHQ-9 depression scale imputation" not "Add depression"
- Include method: "using CART" or "using random forest"
- Mention if conditional: "with conditional logic for employment"

**Good Example:**
```
"I want to add GAD-7 anxiety scale imputation (7 items + total) using CART method"
```

---

### Issue 2: Generated Code Has Syntax Errors

**Symptom:** R or Python script won't run

**Solutions:**
1. Check if you completed all TODO markers
2. Verify variable names match exactly (case-sensitive)
3. Run validation mode: "Validate Stage X"
4. Check for missing commas in variable lists
5. Verify quotes are balanced in SQL statements

**Common Errors:**
- Missing closing parenthesis in MICE call
- Unmatched quotes in SQL
- Variable name typos

---

### Issue 3: MICE Doesn't Converge

**Symptom:** R script runs very long or fails to complete

**Solutions:**
1. Increase `maxit` parameter (try 10 or 20)
2. Simplify predictor matrix (fewer auxiliary variables)
3. Check for perfect collinearity in auxiliaries
4. Reduce `ntree` if using random forest (try 10 instead of default)
5. Check sample size (N > 100 for rf, N > 50 for cart)

**Debug Command:**
```r
# Add to R script temporarily
plot(mice_result)  # View convergence diagnostics
```

---

### Issue 4: Database Insertion Fails

**Symptom:** Python script crashes with database error

**Solutions:**
1. Check for NULL values in NOT NULL columns:
```python
# Before insertion
print(f"NULL count: {data[variable].isna().sum()}")
data = data[~data[variable].isna()]  # Filter NULLs
```
2. Verify data types match table definition
3. Check primary key violations (duplicate records)
4. Ensure database file is not locked (close other connections)

---

### Issue 5: Validation Mode Reports Failures

**Symptom:** Agent finds pattern violations

**Solutions:**
- **Seed Usage Failure**: Change `set.seed(seed)` to `set.seed(seed + m)`
- **Defensive Filtering Failure**: Add `WHERE "eligible.x" = TRUE AND "authentic.x" = TRUE` to all queries
- **Metadata Tracking Failure**: Add `update_metadata()` calls in Python script
- **Index Creation Failure**: Add CREATE INDEX statements after table creation

Request fixes: "Please fix these validation issues"

---

### Issue 6: Too Many TODO Markers

**Symptom:** Overwhelmed by number of TODOs

**Strategy:**
1. **Start with CRITICAL:** Complete [DOMAIN LOGIC] and [STATISTICAL DECISION] first
2. **Test early:** Run with defaults to see if it works
3. **Iterate:** Refine predictor matrix and validation rules after initial success
4. **Get help:** "How should I configure the predictor matrix for PSS items?"

**Remember:** Not all TODOs must be completed before first test. Start simple, then enhance.

---

## FAQ

### Q1: When should I use the agent vs. implement manually?

**Use agent when:**
- Imputation follows standard patterns (unconditional, conditional, multi-item scales)
- You want to ensure pattern compliance
- You're new to the imputation pipeline
- You want to save time on boilerplate

**Implement manually when:**
- Highly custom imputation logic needed
- Integrating external tools (e.g., Amelia, mi)
- Experimental methods not supported by MICE
- You need to understand every line of code

---

### Q2: What statistical decisions does the agent NOT make?

The agent **never** decides:
- Which MICE method to use (you choose)
- Which auxiliary variables to include (you specify)
- Predictor matrix configuration (you complete TODO)
- Method parameters like maxit, ntree (you review/modify)
- Derived variable formulas (you provide)
- Validation rules and ranges (you define)

**You are always in control of statistical decisions.**

---

### Q3: How do I modify generated code?

**You can modify anything** in the generated files. The agent provides a starting point.

**Common modifications:**
- Add additional helper functions
- Customize MICE diagnostics
- Add progress reporting
- Implement custom validation logic
- Change output file structure

**Best practice:** Make modifications, then run validation mode to ensure patterns still compliant.

---

### Q4: Can I use the agent for multiple studies?

**Yes!** Specify study_id when invoking:
```
User: "Add perceived stress imputation for study ia26"
```

Agent adapts:
- File paths: `scripts/imputation/ia26/`
- Table names: `ia26_imputed_pss_1`
- Configuration: Loads from `config/imputation/ia26_config.yaml`

---

### Q5: What if I have a unique imputation scenario?

**Two options:**

1. **Use agent for structure**, then heavily modify:
   - Let agent create basic structure
   - Replace MICE logic with custom algorithm
   - Keep file organization and pattern compliance

2. **Implement manually**, then use **validation mode**:
   - Write your own implementation
   - Request validation to check patterns
   - Fix any compliance issues

---

### Q6: How do I test if imputation worked correctly?

**4-Level Testing:**

**Level 1: File Creation**
```bash
# Check Feather files exist
ls data/imputation/ne25/{domain}_feather/
# Should see: {variable}_m1.feather, {variable}_m2.feather, etc.
```

**Level 2: Record Counts**
```python
import pyarrow.feather as feather
data_m1 = feather.read_feather("data/imputation/ne25/{domain}_feather/{variable}_m1.feather")
print(f"Rows imputed in m=1: {len(data_m1)}")
```

**Level 3: Database Validation**
```python
from python.db.connection import DatabaseManager
db = DatabaseManager()
result = db.execute_query("SELECT COUNT(*) FROM ne25_imputed_{variable}")
print(f"Total rows in database: {result[0][0]}")
```

**Level 4: Statistical Checks**
```python
from python.imputation.helpers import get_{domain}_imputations
data = get_{domain}_imputations(imputation_number=1)
print(data['{variable}'].describe())  # Check range, mean, etc.
```

---

### Q7: Can the agent help with debugging existing stages?

**Yes!** Use validation mode:
```
User: "Validate Stage 5 and explain any issues found"
```

Agent:
- Reads R and Python scripts
- Checks 8 critical patterns
- Explains what each failure means
- Offers corrected code

Great for:
- Onboarding new team members
- Code review before merging
- Debugging mysterious issues
- Learning best practices

---

### Q8: How often should I validate stages?

**Recommended schedule:**
- **Before committing**: Always validate before git commit
- **After modifications**: Re-validate if you change core logic
- **Periodic audits**: Validate all stages quarterly for quality assurance
- **When debugging**: First step when investigating issues

**Command:**
```bash
# Validate all stages
for i in {01..11}; do
  echo "Validating Stage $i"
  # Request validation via agent
done
```

---

### Q9: What happens if I make a mistake?

**The agent provides safety nets:**

1. **Pre-flight checks**: Detects stage number conflicts before generating
2. **Validation mode**: Catches pattern violations
3. **TODO markers**: Prevent forgetting critical decisions
4. **Defensive patterns**: Built-in NULL filtering, error handling

**If you do make a mistake:**
- Validation mode will likely catch it
- Test scripts before running full pipeline
- Database uses transactions (can rollback on error)
- Feather files are temporary (can regenerate)

**Worst case:** Delete generated files and start over (agent makes this painless).

---

### Q10: How do I contribute improvements to the agent?

**Agent lives in:** `.claude/agents/imputation-stage-builder.yaml`

**To improve:**
1. Identify pattern or check that's missing
2. Add to agent specification or template files
3. Update documentation (VALIDATION_CHECKS.md, STAGE_TEMPLATES.md)
4. Test with existing stages
5. Commit with clear description

**Common improvements:**
- New TODO marker categories
- Additional validation checks
- Enhanced error messages
- Better examples in prompts

---

## Additional Resources

**Documentation:**
- `docs/imputation/ADDING_IMPUTATION_STAGES.md` - Complete pattern guide
- `docs/imputation/STAGE_TEMPLATES.md` - R and Python templates
- `docs/imputation/VALIDATION_CHECKS.md` - 8 critical pattern checks
- `docs/imputation/TEST_SCENARIOS.md` - Example scenarios for testing
- `docs/guides/MISSING_DATA_GUIDE.md` - Missing data handling
- `docs/guides/CODING_STANDARDS.md` - R namespacing, conventions

**Agent Files:**
- `.claude/agents/imputation-stage-builder.yaml` - Agent specification
- `docs/imputation/AGENT_IMPLEMENTATION_TASKS.md` - Development roadmap

**Statistical References:**
- van Buuren, S. (2018). *Flexible Imputation of Missing Data*. 2nd ed.
- `mice` package documentation: https://amices.org/mice/
- Rubin, D.B. (1987). *Multiple Imputation for Nonresponse in Surveys*.

---

**For questions or issues, consult the documentation above or invoke the agent with your specific question.**

**Last Updated:** October 8, 2025

# Missing Data Handling Guide

**Last Updated:** October 2025

This document provides comprehensive guidance on missing data handling in the Kidsights Data Platform, specifically for the NE25 pipeline. Proper missing data handling is critical to prevent sentinel values from contaminating composite scores and producing invalid statistical results.

---

## Table of Contents

1. [Overview](#overview)
2. [Critical Requirements](#critical-requirements)
3. [Requirements for Adding New Derived Variables](#requirements-for-adding-new-derived-variables)
4. [Common Missing Value Codes](#common-missing-value-codes)
5. [Complete Composite Variables Inventory](#complete-composite-variables-inventory)
6. [Creating New Composite Variables](#creating-new-composite-variables)
7. [Validation Procedures](#validation-procedures)
8. [Historical Context](#historical-context)

---

## Overview

### The Problem

Survey instruments often use **sentinel values** (e.g., 99 = "Prefer not to answer", 9 = "Don't know") to encode missing data. If these sentinel values are not properly recoded to `NA` before transformation, they contaminate composite scores with invalid values.

**Example of contamination:**
```r
# If raw data has: item1=2, item2=99, item3=1
# Without recoding: ace_total = 2 + 99 + 1 = 102 (INVALID!)
# With proper recoding: ace_total = 2 + NA + 1 = NA (CORRECT)
```

### The Solution

**All derived variables MUST use `recode_missing()` before transformation to prevent sentinel values from contaminating composite scores.**

### Conservative Approach

All composite scores in the NE25 pipeline use **`na.rm = FALSE`** in calculations. This conservative approach ensures that if ANY component item is missing, the total score is marked as `NA` rather than creating potentially misleading partial scores.

**Rationale:**
- **Data integrity:** Partial scores can be misleading (e.g., someone who answered 1 ACE item and declined 9 would appear to have low ACE exposure)
- **Statistical validity:** Composite scores assume all components contribute to the construct
- **Transparency:** Missing totals clearly indicate incomplete data rather than hiding missingness

---

## Critical Requirements

### Requirement 1: Always Use recode_missing()

**Correct Pattern:**
```r
# ✅ CORRECT - Recode missing values before transformation
for(old_name in names(variable_mapping)) {
  if(old_name %in% names(dat)) {
    new_name <- variable_mapping[[old_name]]
    # Convert 99 (Prefer not to answer) to NA before assignment
    derived_df[[new_name]] <- recode_missing(dat[[old_name]], missing_codes = c(99))
  }
}
```

**Incorrect Pattern:**
```r
# ❌ INCORRECT - Copying raw values directly
for(old_name in names(variable_mapping)) {
  if(old_name %in% names(dat)) {
    new_name <- variable_mapping[[old_name]]
    derived_df[[new_name]] <- dat[[old_name]]  # 99 values persist!
  }
}
```

### Requirement 2: Use na.rm = FALSE for Composite Scores

**Correct Pattern:**
```r
# ✅ CORRECT - Preserves missingness
total_score <- rowSums(item_df[item_cols], na.rm = FALSE)
# If ANY item is NA, total is NA (conservative, prevents misleading partial scores)
```

**Incorrect Pattern:**
```r
# ❌ INCORRECT - Creates misleading partial scores
total_score <- rowSums(item_df[item_cols], na.rm = TRUE)
# Person who answered 1 item and declined 9 would appear to have low score
```

**Why this is wrong:**

| Scenario | Item 1 | Item 2 | Item 3 | With na.rm=TRUE | With na.rm=FALSE | Interpretation |
|----------|--------|--------|--------|-----------------|------------------|----------------|
| Complete response | 2 | 1 | 0 | 3 | 3 | Valid score |
| Partial response | 2 | NA | 0 | 2 | NA | **na.rm=TRUE misleads** (looks like low score) |
| All refused | NA | NA | NA | 0 | NA | **na.rm=TRUE very misleading** (appears as zero) |

---

## Requirements for Adding New Derived Variables

When creating any new derived variable, follow these four steps:

### 1. Check REDCap Data Dictionary

Before implementing any transformation, query the REDCap data dictionary to identify missing value codes:

```r
# Check response options for variable
dict_entry <- redcap_dict[[variable_name]]
response_options <- dict_entry$select_choices_or_calculations

# Look for: "99, Prefer not to answer", "9, Don't know", etc.
print(response_options)
```

**Example output:**
```
"0, No | 1, Yes | 99, Prefer not to answer"
```

### 2. Apply Defensive Recoding

Even if no current missing codes exist, apply `recode_missing()` as a safeguard:

```r
# Defensive recoding (future-proofs against survey changes)
clean_var <- recode_missing(raw_var, missing_codes = c(99, 9))
```

**Why defensive?**
- Survey instruments may change over time
- New missing value codes may be added
- Ensures consistent handling across all variables

### 3. Use Conservative Composite Score Calculation

Always use `na.rm = FALSE` in `rowSums()` or aggregation functions:

```r
# ✅ CORRECT - Preserves missingness
total_score <- rowSums(item_df[item_cols], na.rm = FALSE)
# If ANY item is NA, total is NA (conservative, prevents misleading partial scores)
```

**Alternatives for other aggregation functions:**

```r
# Mean scores
mean_score <- rowMeans(item_df[item_cols], na.rm = FALSE)

# Sum with conditional logic
total_score <- ifelse(
  rowSums(is.na(item_df[item_cols])) > 0,
  NA_real_,
  rowSums(item_df[item_cols])
)

# Using dplyr
result <- item_df %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    total = if (any(is.na(c_across(item_cols)))) NA_real_ else sum(c_across(item_cols))
  )
```

### 4. Document Missing Codes

Add code comments explaining which missing codes are used:

```r
# Recode missing values (99 = "Prefer not to answer", 9 = "Don't know")
# This ensures invalid responses don't contaminate the total score calculation
phq2_item1_clean <- recode_missing(dat$phq2_item1, missing_codes = c(99, 9))
phq2_item2_clean <- recode_missing(dat$phq2_item2, missing_codes = c(99, 9))
```

---

## Common Missing Value Codes

### NE25 Survey Missing Codes

| Code | Meaning | Frequency | Used In |
|------|---------|-----------|---------|
| `99` | "Prefer not to answer" | Most common | Mental health, ACEs, demographics |
| `9` | "Don't know" | Occasional | Age estimates, dates |
| `-99` | Alternative missing code | Rare | Legacy variables |
| `999` | Alternative missing code | Rare | Income, continuous variables |
| `9999` | Alternative missing code | Very rare | Large-scale numeric variables |
| Factor level "Missing" | Categorical missing | Occasional | Childcare variables |

### How to Identify Missing Codes

**Method 1: REDCap Data Dictionary**
```r
# Query data dictionary for a specific variable
redcap_dict <- load_redcap_dictionary()
variable_info <- redcap_dict[[variable_name]]
response_options <- variable_info$select_choices_or_calculations

# Parse response options (format: "code1, label1 | code2, label2")
if (grepl("99", response_options)) {
  cat("Variable", variable_name, "uses 99 as missing code\n")
}
```

**Method 2: Data Exploration**
```r
# Check for unusual values
summary(dat$variable_name)
table(dat$variable_name, useNA = "always")

# Check for values outside expected range
ace_items <- c("ace_item1", "ace_item2", ..., "ace_item10")
for (item in ace_items) {
  invalid <- which(dat[[item]] > 1 & dat[[item]] != 99)
  if (length(invalid) > 0) {
    cat("Warning:", item, "has", length(invalid), "values outside range [0,1]\n")
  }
}
```

**Method 3: Codebook Documentation**
```r
# Check codebook for missing value conventions
source("R/codebook/load_codebook.R")
codebook <- load_codebook("codebook/data/codebook.json")

# Extract response sets for NE25 study
ne25_responses <- codebook_extract_response_sets(codebook, study = "NE25")
```

---

## Complete Composite Variables Inventory

The NE25 pipeline creates 12 composite variables from component items. All use defensive recoding and conservative missing data handling.

| Composite Variable | Components | Valid Range | Missing Policy | Defensive Recoding |
|-------------------|-----------|-------------|---------------|-------------------|
| `phq2_total` | 2 depression items | 0-6 | na.rm = FALSE | ✓ c(99, 9) |
| `gad2_total` | 2 anxiety items | 0-6 | na.rm = FALSE | ✓ c(99, 9) |
| `ace_total` | 10 caregiver ACE items | 0-10 | na.rm = FALSE | ✓ c(99) |
| `child_ace_total` | 8 child ACE items | 0-8 | na.rm = FALSE | ✓ c(99, 9) |
| `family_size` | fqlive1_1 + fqlive1_2 + 1 | 1-99 | conditional | ✓ via < 999 check |
| `fpl` | income / threshold × 100 | 0-∞ | NA if components NA | Via family_size |
| `fplcat` | Factor from fpl | 5 categories | Factor NA | Via fpl |
| `years_old` | age_in_days / 365.25 | 0-5 | NA if source NA | No sentinel values |
| `months_old` | years_old × 12 | 0-60 | NA if source NA | Via years_old |
| `urban_pct` | % urban from ZIP | 0-100 | NA if ZIP not found | Database lookup |
| `cc_weekly_cost_*` | Childcare costs | 0-∞ | conditional | Factor "Missing" |
| `cc_any_support` | family OR subsidy | Binary | conditional | Factor "Missing" |

### Impact on Sample Size (N=4,900)

Understanding missingness patterns helps with power calculations and interpretation:

| Variable | Non-Missing | Missing | Completion Rate |
|----------|-------------|---------|-----------------|
| `phq2_total` | 3,108 (63.4%) | 1,792 (36.6%) | 63.4% |
| `gad2_total` | 3,100 (63.3%) | 1,800 (36.7%) | 63.3% |
| `ace_total` | 2,704 (55.2%) | 2,196 (44.8%) | 55.2% |
| `child_ace_total` | 3,881 (99.6%) | 19 (0.4%) | 99.6% |
| `fpl` | 3,773 (97.4%) | 127 (2.6%) | 97.4% |

**Interpretation:**
- **Mental health scales (PHQ-2, GAD-2):** ~37% missing due to optional screener
- **Caregiver ACEs:** ~45% missing due to sensitive questions
- **Child ACEs:** Very high completion (99.6%) - less sensitive questions
- **FPL:** High completion (97.4%) - essential demographic variable

### Detailed Implementation

See `R/transform/README.md` section "Composite Variables: Complete Inventory and Missing Data Policy" for:
- Full R code implementation
- Validation queries
- Sample data patterns
- Quality assurance procedures

---

## Creating New Composite Variables

When adding a new composite variable to the NE25 pipeline, follow this comprehensive checklist:

### Step 1: Implementation (R/transform/ne25_transforms.R)

**Checklist:**
- [ ] Apply `recode_missing()` to ALL component variables before calculation
- [ ] Use `na.rm = FALSE` in `rowSums()` or aggregation functions
- [ ] Document valid range in code comments (e.g., "0-10 for ACE total")
- [ ] Add descriptive variable label using `labelled::var_label()`
- [ ] Test with sample data containing sentinel values (99, 9, etc.)

**Example Implementation:**
```r
# New composite variable: xyz_total (3-item scale, range 0-9)
# Components: xyz_item1, xyz_item2, xyz_item3

# Step 1.1: Defensive recoding
xyz_df <- dat %>%
  dplyr::mutate(
    xyz_item1_clean = recode_missing(dat$xyz_item1, missing_codes = c(99, 9)),
    xyz_item2_clean = recode_missing(dat$xyz_item2, missing_codes = c(99, 9)),
    xyz_item3_clean = recode_missing(dat$xyz_item3, missing_codes = c(99, 9))
  )

# Step 1.2: Calculate composite (na.rm = FALSE)
# Valid range: 0-9 (sum of three 0-3 items)
xyz_df$xyz_total <- rowSums(
  xyz_df[c("xyz_item1_clean", "xyz_item2_clean", "xyz_item3_clean")],
  na.rm = FALSE  # Conservative: ANY missing component → NA total
)

# Step 1.3: Add variable label
labelled::var_label(xyz_df$xyz_total) <- "XYZ Total Score (0-9, higher = more xyz)"

# Step 1.4: Validate range
invalid_values <- which(xyz_df$xyz_total < 0 | xyz_df$xyz_total > 9)
if (length(invalid_values) > 0) {
  stop("xyz_total has ", length(invalid_values), " values outside valid range [0-9]")
}

cat("xyz_total: ", sum(!is.na(xyz_df$xyz_total)), " non-missing, ",
    sum(is.na(xyz_df$xyz_total)), " missing\n")
```

### Step 2: Validation

**Checklist:**
- [ ] Create validation query to check for values outside valid range
- [ ] Verify no sentinel values (99, 9, -99, 999) persist in transformed data
- [ ] Run automated validation script: `python scripts/validation/validate_composite_variables.py`
- [ ] Document missing data patterns and sample size impact

**Validation Queries (Python/DuckDB):**
```python
from python.db.connection import DatabaseManager

db = DatabaseManager()

# Check 1: No values outside valid range
result = db.execute_query("""
    SELECT COUNT(*) as invalid_count
    FROM ne25_transformed
    WHERE xyz_total > 9 OR xyz_total < 0
""")
print(f"Invalid values: {result[0][0]}")  # Should be 0

# Check 2: Missing data patterns
result = db.execute_query("""
    SELECT
        COUNT(*) as total_records,
        COUNT(xyz_total) as non_missing,
        COUNT(*) - COUNT(xyz_total) as missing,
        ROUND(100.0 * COUNT(xyz_total) / COUNT(*), 1) as completion_rate
    FROM ne25_transformed
""")
print(f"Completion: {result[0][3]}%")

# Check 3: Sentinel values check
result = db.execute_query("""
    SELECT COUNT(*) as sentinel_count
    FROM ne25_transformed
    WHERE xyz_total IN (9, 99, 999, -99)
""")
print(f"Sentinel values: {result[0][0]}")  # Should be 0
```

**Automated Validation Script:**
```bash
# Run comprehensive validation
python scripts/validation/validate_composite_variables.py --variable xyz_total
```

### Step 3: Documentation Updates (REQUIRED)

**Checklist:**
- [ ] Add variable to `config/derived_variables.yaml` composite_variables section
- [ ] Add variable to composite inventory table in `R/transform/README.md`
- [ ] Add variable to composite inventory table in `docs/guides/MISSING_DATA_GUIDE.md`
- [ ] Update derived variable count in documentation

**config/derived_variables.yaml:**
```yaml
derived_variables:
  composite_variables:
    xyz_total:
      is_composite: true
      components: ["xyz_item1", "xyz_item2", "xyz_item3"]
      valid_range: [0, 9]
      missing_policy: "na.rm = FALSE"
      defensive_recoding: "c(99, 9)"
      category: "Behavioral Health"
      description: "XYZ total score (sum of 3 items)"
      sample_size_impact: "TBD - calculate after first production run"
```

**R/transform/README.md:**
Add row to composite variables table (around line 617-638):
```markdown
| `xyz_total` | 3 XYZ items | 0-9 | na.rm = FALSE | ✓ c(99, 9) |
```

**This file (MISSING_DATA_GUIDE.md):**
Add row to inventory table in this document.

### Step 4: Template Available

See `R/transform/composite_variable_template.R` for complete example code including:
- Defensive recoding pattern
- Composite calculation
- Range validation
- Missing data documentation
- Sample queries

### Critical Reminders

⚠️ **NEVER** use `na.rm = TRUE` for composite scores (creates misleading partial scores)

⚠️ **ALWAYS** apply `recode_missing()` before calculation (prevents sentinel value contamination)

⚠️ **ALWAYS** update all 3 documentation locations:
1. `config/derived_variables.yaml`
2. `R/transform/README.md`
3. `docs/guides/MISSING_DATA_GUIDE.md`

---

## Validation Procedures

### Pre-Deployment Validation Checklist

Before merging new composite variables to production:

- [ ] Checked REDCap data dictionary for missing codes
- [ ] Applied `recode_missing()` before variable assignment
- [ ] Used `na.rm = FALSE` in composite score calculation
- [ ] Tested with sample data containing 99 values
- [ ] Verified no sentinel values (99, 9, etc.) persist in transformed data
- [ ] Confirmed composite scores are NA when any component is missing
- [ ] Validated all composite variables against expected valid ranges
- [ ] Documented missing data patterns and sample size impact
- [ ] Updated composite variables inventory table in all 3 locations

### Automated Testing

**Test with sample data:**
```r
# Create test data with sentinel values
test_data <- data.frame(
  pid = 1:5,
  item1 = c(0, 1, 99, 1, 0),   # Row 3 has sentinel value
  item2 = c(1, 0, 1, 99, 1),   # Row 4 has sentinel value
  item3 = c(0, 1, 0, 1, 9)     # Row 5 has sentinel value
)

# Apply transformation
test_data$item1_clean <- recode_missing(test_data$item1, c(99, 9))
test_data$item2_clean <- recode_missing(test_data$item2, c(99, 9))
test_data$item3_clean <- recode_missing(test_data$item3, c(99, 9))

test_data$total <- rowSums(
  test_data[c("item1_clean", "item2_clean", "item3_clean")],
  na.rm = FALSE
)

# Expected results:
# Row 1: 0 + 1 + 0 = 1 ✓
# Row 2: 1 + 0 + 1 = 2 ✓
# Row 3: NA + 1 + 0 = NA ✓ (item1 was 99)
# Row 4: 1 + NA + 1 = NA ✓ (item2 was 99)
# Row 5: 0 + 1 + NA = NA ✓ (item3 was 9)

print(test_data)
stopifnot(test_data$total[1] == 1)
stopifnot(test_data$total[2] == 2)
stopifnot(is.na(test_data$total[3]))
stopifnot(is.na(test_data$total[4]))
stopifnot(is.na(test_data$total[5]))

cat("[OK] All tests passed\n")
```

### Production Validation

After pipeline runs on full dataset:

```sql
-- Check 1: No sentinel values in composite variables
SELECT COUNT(*) as sentinel_count
FROM ne25_transformed
WHERE phq2_total IN (9, 99, 999, -99)
   OR gad2_total IN (9, 99, 999, -99)
   OR ace_total IN (99, 999, -99);
-- Expected: 0

-- Check 2: All composites within valid ranges
SELECT
  COUNT(*) FILTER (WHERE phq2_total < 0 OR phq2_total > 6) as phq2_invalid,
  COUNT(*) FILTER (WHERE gad2_total < 0 OR gad2_total > 6) as gad2_invalid,
  COUNT(*) FILTER (WHERE ace_total < 0 OR ace_total > 10) as ace_invalid
FROM ne25_transformed;
-- Expected: All 0

-- Check 3: Missing data patterns reasonable
SELECT
  ROUND(100.0 * COUNT(phq2_total) / COUNT(*), 1) as phq2_completion,
  ROUND(100.0 * COUNT(gad2_total) / COUNT(*), 1) as gad2_completion,
  ROUND(100.0 * COUNT(ace_total) / COUNT(*), 1) as ace_completion
FROM ne25_transformed;
-- Expected: Roughly 55-65% for PHQ-2/GAD-2, 50-60% for ACE
```

---

## Historical Context

### Critical Issue Prevented

The `recode_missing()` function was added in October 2025 after discovering that **254+ records (5.2% of dataset)** had invalid ACE total scores (99-990 instead of 0-10) due to "Prefer not to answer" (99) being summed directly.

**The Bug:**
```r
# Original code (INCORRECT)
ace_total <- rowSums(ace_df[ace_items])

# If participant answered:
# ace_item1 = 1 (Yes)
# ace_item2 = 99 (Prefer not to answer)
# ace_item3 = 0 (No)
# Result: ace_total = 100 (INVALID!)
```

**The Fix:**
```r
# Fixed code (CORRECT)
ace_items_clean <- lapply(ace_items, function(item) {
  recode_missing(ace_df[[item]], missing_codes = c(99))
})
ace_total <- rowSums(do.call(cbind, ace_items_clean), na.rm = FALSE)

# Same participant now:
# ace_item1_clean = 1 (Yes)
# ace_item2_clean = NA (recoded from 99)
# ace_item3_clean = 0 (No)
# Result: ace_total = NA (CORRECT - incomplete data)
```

### Full Audit Report

See `docs/fixes/missing_data_audit_2025_10.md` for:
- Complete analysis of sentinel value contamination
- Affected variables and record counts
- Before/after comparison
- Lessons learned
- Prevention measures implemented

### Prevention Measures

Since the October 2025 audit, the following measures prevent recurrence:

1. **Mandatory `recode_missing()`:** All transformations use defensive recoding
2. **Automated validation:** `validate_composite_variables.py` runs after every pipeline execution
3. **Documentation requirements:** New variables must document missing codes in 3 locations
4. **Code review checklist:** PRs must confirm `na.rm = FALSE` usage
5. **Test data:** CI/CD pipeline tests with sentinel value fixtures

---

## Related Documentation

- **R/transform/README.md:** Implementation details for composite variables
- **config/derived_variables.yaml:** Machine-readable variable definitions
- **docs/fixes/missing_data_audit_2025_10.md:** Historical audit report
- **CODING_STANDARDS.md:** General R coding standards
- **R/transform/composite_variable_template.R:** Code template for new variables

---

*Last Updated: October 2025*

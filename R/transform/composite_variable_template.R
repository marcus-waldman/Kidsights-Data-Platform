#==============================================================================
# COMPOSITE VARIABLE TEMPLATE
# Created: 2025-10-03 (Phase 5: Future Prevention)
#
# Purpose: Template for creating new composite variables with proper missing
#          data handling and comprehensive documentation
#
# INSTRUCTIONS:
# 1. Copy this template to ne25_transforms.R at the appropriate section
# 2. Replace all "EXAMPLE" placeholders with your variable names
# 3. Follow each numbered step carefully
# 4. Update all 3 documentation files (README.md, CLAUDE.md, YAML)
# 5. Run validation script to verify: python scripts/validation/validate_composite_variables.py
#
# CRITICAL PRINCIPLES:
# - ALWAYS use recode_missing() on component variables
# - ALWAYS use na.rm = FALSE in composite calculations
# - ALWAYS update all 3 documentation locations
#==============================================================================

# Example: Creating a 4-item scale called "stress_total" (range 0-12)
# Component items: stress_item1, stress_item2, stress_item3, stress_item4
# Raw REDCap variables: rawstress1, rawstress2, rawstress3, rawstress4
# Missing codes: 99 = "Prefer not to answer", 9 = "Don't know"

#------------------------------------------------------------------------------
# STEP 1: DEFENSIVE RECODING OF COMPONENT VARIABLES
#------------------------------------------------------------------------------
# Convert sentinel missing value codes (99, 9, etc.) to NA BEFORE calculation
# This prevents invalid values from contaminating the composite score

# Create data frame with defensive recoding
stress_df <- dat %>%
  dplyr::select(pid, record_id) %>%
  dplyr::mutate(
    # Recode each component variable individually
    # missing_codes argument specifies which values to convert to NA
    stress_item1 = recode_missing(dat$rawstress1, missing_codes = c(99, 9)),
    stress_item2 = recode_missing(dat$rawstress2, missing_codes = c(99, 9)),
    stress_item3 = recode_missing(dat$rawstress3, missing_codes = c(99, 9)),
    stress_item4 = recode_missing(dat$rawstress4, missing_codes = c(99, 9))
  )

# Add variable labels (recommended for documentation)
if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
  labelled::var_label(stress_df$stress_item1) <- "Stress item 1: Feeling overwhelmed"
  labelled::var_label(stress_df$stress_item2) <- "Stress item 2: Difficulty managing responsibilities"
  labelled::var_label(stress_df$stress_item3) <- "Stress item 3: Feeling unable to cope"
  labelled::var_label(stress_df$stress_item4) <- "Stress item 4: Worrying excessively"
}

#------------------------------------------------------------------------------
# STEP 2: CALCULATE COMPOSITE SCORE
#------------------------------------------------------------------------------
# Use na.rm = FALSE to ensure that if ANY component is missing,
# the total score is marked as NA (conservative approach)

# Calculate total score
stress_df$stress_total <- rowSums(
  stress_df[c("stress_item1", "stress_item2", "stress_item3", "stress_item4")],
  na.rm = FALSE  # CRITICAL: Do NOT change to TRUE
)

# Explanation of na.rm = FALSE:
# - If person answered 2 items (scores 3,3) but declined 2 items → stress_total = NA
# - With na.rm = TRUE, would incorrectly show stress_total = 6 (misleading partial score)
# - With na.rm = FALSE, correctly shows stress_total = NA (incomplete data)

# Add variable label
if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
  labelled::var_label(stress_df$stress_total) <- "Stress Total Score (0-12)"
}

#------------------------------------------------------------------------------
# STEP 3: CREATE RISK CATEGORIES (OPTIONAL)
#------------------------------------------------------------------------------
# If your composite needs categorical risk levels

stress_df$stress_risk_cat <- factor(
  case_when(
    stress_df$stress_total <= 3 ~ "Low",
    stress_df$stress_total <= 6 ~ "Moderate",
    stress_df$stress_total <= 9 ~ "High",
    stress_df$stress_total >= 10 ~ "Severe",
    TRUE ~ NA_character_
  ),
  levels = c("Low", "Moderate", "High", "Severe")
)

# Set reference level (usually "Low" or "None")
if(relevel_it) {
  stress_df$stress_risk_cat <- relevel(stress_df$stress_risk_cat, ref = "Low")
}

# Add variable label
if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
  labelled::var_label(stress_df$stress_risk_cat) <- "Stress Risk Category"
}

#------------------------------------------------------------------------------
# STEP 4: VALIDATION QUERIES (To be run AFTER pipeline execution)
#------------------------------------------------------------------------------
# These validation queries should be added to:
# scripts/validation/validate_composite_variables.py

# Python/DuckDB validation queries:
#
# # Check for values outside valid range (should return 0)
# SELECT COUNT(*) as invalid_high
# FROM ne25_transformed
# WHERE stress_total > 12
#
# # Check for values below minimum (should return 0)
# SELECT COUNT(*) as invalid_low
# FROM ne25_transformed
# WHERE stress_total < 0
#
# # Check for persisting sentinel values (should return 0)
# SELECT COUNT(*) as sentinel_values
# FROM ne25_transformed
# WHERE stress_total IN (9, 99, 999, -99, -999)
#
# # Check missing data patterns
# SELECT
#     COUNT(*) as total_records,
#     COUNT(stress_total) as non_missing,
#     COUNT(*) - COUNT(stress_total) as missing,
#     ROUND(100.0 * (COUNT(*) - COUNT(stress_total)) / COUNT(*), 1) as missing_pct
# FROM ne25_transformed

#------------------------------------------------------------------------------
# STEP 5: DOCUMENTATION UPDATES (REQUIRED)
#------------------------------------------------------------------------------
# You MUST update all 3 documentation files when adding a new composite:

# A. config/derived_variables.yaml
#    Add to composite_variables section:
#
# stress_total:
#   is_composite: true
#   components: ["stress_item1", "stress_item2", "stress_item3", "stress_item4"]
#   valid_range: [0, 12]
#   missing_policy: "na.rm = FALSE"
#   defensive_recoding: "c(99, 9)"
#   category: "Mental Health"  # or appropriate category
#   sample_size_impact: "X,XXX non-missing (XX.X%), X,XXX missing (XX.X%)"

# B. R/transform/README.md
#    Add row to composite inventory table (lines 617-638):
#
# | `stress_total` | 4 stress items | 0-12 | na.rm = FALSE | ✓ Yes (c(99, 9)) | October 2025 |

# C. CLAUDE.md
#    Add row to composite inventory table (lines 424-437):
#
# | `stress_total` | 4 stress items | 0-12 | na.rm = FALSE | ✓ c(99, 9) |

#------------------------------------------------------------------------------
# STEP 6: UPDATE DERIVED VARIABLE COUNT
#------------------------------------------------------------------------------
# Update variable counts in documentation:
# - CLAUDE.md: Search for "99 derived variables" and increment
# - R/transform/README.md: Update total count
# - config/derived_variables.yaml: Add to all_derived_variables list

#------------------------------------------------------------------------------
# STEP 7: VALIDATION TESTING
#------------------------------------------------------------------------------
# Before committing, run these validation steps:

# 1. Test with sample data containing sentinel values:
#    test_data <- data.frame(
#      pid = 1:5,
#      record_id = 1:5,
#      rawstress1 = c(0, 1, 2, 99, 3),  # 99 should become NA
#      rawstress2 = c(1, 2, 3, 0, 9),   # 9 should become NA
#      rawstress3 = c(2, 3, 0, 1, 2),
#      rawstress4 = c(3, 0, 1, 2, 3)
#    )
#    # Expected stress_total: c(6, 6, 6, NA, NA)

# 2. Run full pipeline:
#    source("pipelines/orchestration/run_ne25_pipeline.R")

# 3. Run automated validation:
#    python scripts/validation/validate_composite_variables.py
#    # Should show stress_total with 0 invalid values

# 4. Check missing data patterns:
#    library(duckdb)
#    conn <- dbConnect(duckdb(), "data/duckdb/kidsights_local.duckdb")
#    dbGetQuery(conn, "
#      SELECT
#        COUNT(*) - COUNT(stress_total) as missing,
#        ROUND(100.0 * (COUNT(*) - COUNT(stress_total)) / COUNT(*), 1) as missing_pct
#      FROM ne25_transformed
#    ")

#------------------------------------------------------------------------------
# COMMON PITFALLS TO AVOID
#------------------------------------------------------------------------------
# ❌ DO NOT use na.rm = TRUE (creates misleading partial scores)
# ❌ DO NOT skip recode_missing() (sentinel values will contaminate totals)
# ❌ DO NOT forget to update all 3 documentation files
# ❌ DO NOT commit without running validation script
# ❌ DO NOT use inline calculations without defensive recoding:
#      WRONG: stress_total <- dat$rawstress1 + dat$rawstress2 + dat$rawstress3
#      RIGHT: Use defensive recoding first, then rowSums with na.rm = FALSE

#------------------------------------------------------------------------------
# EXAMPLE OUTPUT VALIDATION
#------------------------------------------------------------------------------
# After implementing this template, your validation should show:
#
# stress_total (Stress Total Score)
#   Total records:     4,900
#   Non-missing:       3,XXX
#   Missing (NA):      1,XXX (XX.X%)
#   Valid range:       0-12
#   Observed range:    0.0-12.0
#   Below minimum:     0
#   Above maximum:     0
#   Sentinel values:   0
#   Status:            [OK]

#==============================================================================
# END OF TEMPLATE
#==============================================================================
# Additional Resources:
# - Full documentation: R/transform/README.md (lines 604-733)
# - Project policy: CLAUDE.md (lines 356-519)
# - Implementation plan: docs/fixes/composite_variables_missing_data_plan.md
# - Missing data audit: docs/fixes/missing_data_audit_2025_10.md
#==============================================================================

---
name: Age Gradient Explorer Bugs
about: Two bugs in the Age Gradient Explorer Shiny app (response options display and masking toggle)
title: '[Bug] Age Gradient Explorer: Response options incomplete and masking toggle non-functional'
labels: bug, shiny-app
assignees: ''
---

## Issue Summary

Two bugs identified in the Age Gradient Explorer Shiny app affecting data visualization and metadata display.

## Bug 1: Incomplete Response Options Display

**Expected Behavior:**
All response options for selected items should be displayed below the item stem and domain in the subtitle area.

**Actual Behavior:**
Not all response options are showing for items. Some items may be missing response categories or displaying incomplete option sets.

**Impact:**
Users cannot see the full response scale structure when reviewing item age gradients, making it difficult to interpret the visualizations and understand threshold patterns.

**Affected Component:**
- `scripts/shiny/age_gradient_explorer/server.R` (response set extraction logic, lines ~304-340)

## Bug 2: Masking Toggle Does Not Update Plot

**Expected Behavior:**
When toggling between "Before Masking (original data)" and "After Masking (QA cleaned)", the plot should update to reflect the filtered dataset (removing observations with `maskflag=1` in "After" mode).

**Actual Behavior:**
The plot does not change when toggling the masking radio buttons. The visualization remains static regardless of the selected masking mode.

**Impact:**
Users cannot compare pre-QA vs post-QA data distributions, defeating the purpose of the masking toggle feature. This prevents validation of influence masking effects on age-response gradients.

**Affected Components:**
- `scripts/shiny/age_gradient_explorer/server.R` (reactive filtering logic)
- `scripts/shiny/age_gradient_explorer/ui.R` (masking toggle radio buttons)

## Steps to Reproduce

**For Bug 1:**
1. Launch app: `shiny::runApp("scripts/shiny/age_gradient_explorer")`
2. Select any item from the dropdown
3. Observe the response options displayed below the item stem and domain
4. Verify if all response categories are present

**For Bug 2:**
1. Launch app with default "After Masking (QA cleaned)" selected
2. Note the current plot visualization
3. Switch to "Before Masking (original data)"
4. Observe that the plot does not update

## Environment

- **R Version:** 4.5.1
- **Shiny Version:** [Latest]
- **Database:** DuckDB (kidsights_local.duckdb)
- **Data Table:** calibration_dataset_long (1,216,539 rows)

## Related Files

- `scripts/shiny/age_gradient_explorer/server.R`
- `scripts/shiny/age_gradient_explorer/ui.R`
- `scripts/shiny/age_gradient_explorer/global.R`
- `codebook/data/codebook.json`

## Potential Root Causes

**Bug 1:**
- Incorrect response_set_id extraction from `item$content$response_options`
- Missing response sets in codebook.json for certain items
- JSON parsing issue with nested response set structures

**Bug 2:**
- Reactive dependency issue between `input$maskflag_mode` and plot rendering
- Masking filter not being applied to the data pipeline
- Cached plot output not invalidating when toggle changes

## Priority

**High** - These bugs affect core functionality of the QA tool and prevent proper validation of calibration data quality.

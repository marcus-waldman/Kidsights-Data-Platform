# Codebook Utility Functions

## Overview

The codebook utility functions provide an easy way to extract and transform data from the codebook.json file into analysis-ready dataframes. These functions follow the naming convention `codebook_extract_*` and are designed for statistical analysis workflows.

## Function Summary

| Function | Purpose | Output Format |
|----------|---------|---------------|
| `codebook_extract_lexicon_crosswalk()` | Cross-reference item IDs across studies | Wide dataframe with lexicon columns |
| `codebook_extract_irt_parameters()` | Extract IRT discrimination/threshold parameters | Long or wide format |
| `codebook_extract_response_sets()` | Get response options and value labels | Long format with value/label pairs |
| `codebook_extract_item_content()` | Extract item text, domains, age ranges | Wide format with metadata |
| `codebook_extract_study_summary()` | Study-level summary statistics | Summary statistics table |
| `codebook_pivot_irt_to_wide()` | IRT parameters in wide format | Wide format (convenience function) |

## Setup

```r
# Load required libraries
source("R/codebook/load_codebook.R")
source("R/codebook/extract_codebook.R")

# Load the codebook
codebook <- load_codebook("codebook/data/codebook.json")
```

## Common Workflows

### 1. Creating Lexicon Crosswalks

When you need to map item IDs between different studies or naming conventions:

```r
# Get complete crosswalk for all items
crosswalk <- codebook_extract_lexicon_crosswalk(codebook)
head(crosswalk)
#   item_id equate kidsight ne25 ne22 ne20 credi gsed
#   AA4     AA4    AA4      C020 C020 C20  LF5   crosec004
#   AA5     AA5    AA5      C023 C023 C23  LF3   croclc006

# Get crosswalk for specific studies only
ne_crosswalk <- codebook_extract_lexicon_crosswalk(
  codebook,
  studies = c("NE25", "NE22", "NE20")
)

# Use crosswalk to merge datasets
ne25_data <- ne25_data %>%
  dplyr::left_join(ne_crosswalk, by = c("variable" = "ne25")) %>%
  dplyr::select(record_id, item_id, value, equate)
```

### 2. Extracting IRT Parameters for Analysis

For psychometric analysis with IRT parameters:

```r
# Get NE22 parameters in long format (good for modeling)
ne22_params_long <- codebook_extract_irt_parameters(codebook, "NE22")
head(ne22_params_long)
#   item_id factor    loading threshold_num threshold_value
#   AA5     kidsights 1.824   1             17.010
#   PS001   gen       0.492   1             -2.782
#   PS001   eat       1.447   2             -0.193

# Get parameters in wide format (good for data analysis)
ne22_params_wide <- codebook_extract_irt_parameters(codebook, "NE22", format = "wide")
head(ne22_params_wide)
#   item_id n_factors factor_1  loading_1 factor_2 loading_2 threshold_1 threshold_2
#   AA5     1         kidsights 1.824     NA       NA        17.010      NA
#   PS001   2         gen       0.492     eat      1.447     -2.782      -0.193

# Use for IRT analysis
library(mirt)
item_params <- ne22_params_wide %>%
  dplyr::select(item_id, loading_1, threshold_1, threshold_2) %>%
  dplyr::filter(!is.na(loading_1))
```

### 3. Working with Response Sets

To understand response options and missing data coding:

```r
# Get all response sets for NE25
ne25_responses <- codebook_extract_response_sets(codebook, study = "NE25")
head(ne25_responses)
#   item_id study response_set          value label       missing
#   AA4     NE25  standard_binary_ne25  1     Yes         FALSE
#   AA4     NE25  standard_binary_ne25  0     No          FALSE
#   AA4     NE25  standard_binary_ne25  9     Don't Know  TRUE

# Get specific response set definition
ps_frequency <- codebook_extract_response_sets(
  codebook,
  response_set = "ps_frequency_ne25"
)

# Create value label lookup
value_labels <- ne25_responses %>%
  dplyr::select(response_set, value, label) %>%
  dplyr::distinct() %>%
  split(.$response_set)

# Apply labels to data
ne25_data <- ne25_data %>%
  dplyr::mutate(
    value_labeled = dplyr::case_when(
      response_set == "standard_binary_ne25" & value == 1 ~ "Yes",
      response_set == "standard_binary_ne25" & value == 0 ~ "No",
      response_set == "standard_binary_ne25" & value == 9 ~ "Don't Know",
      TRUE ~ as.character(value)
    )
  )
```

### 4. Item Content and Metadata

For understanding what items measure:

```r
# Get all motor domain items
motor_items <- codebook_extract_item_content(codebook, domains = "motor")
head(motor_items)
#   item_id studies           stem                          domain age_min age_max reverse_scored
#   GM1     NE25, NE22, NE20  Does your child roll over?    motor  0       72      FALSE

# Get NE25 items with content
ne25_content <- codebook_extract_item_content(codebook, studies = "NE25")

# Create item documentation
item_docs <- ne25_content %>%
  dplyr::select(item_id, stem, domain, age_min, age_max) %>%
  dplyr::arrange(domain, item_id)

# Filter by age range
infant_items <- ne25_content %>%
  dplyr::filter(age_min <= 12 & age_max >= 12) %>%  # 12 month items
  dplyr::arrange(domain)
```

### 5. Study Summaries and Coverage

To understand study characteristics:

```r
# Get summary for NE25
ne25_summary <- codebook_extract_study_summary(codebook, "NE25")
print(ne25_summary)
#   study total_items items_with_irt items_with_thresholds irt_coverage domains...

# Compare all studies
all_studies <- c("NE25", "NE22", "NE20", "CREDI", "GSED_PF")
study_comparison <- purrr::map_df(all_studies, ~ {
  codebook_extract_study_summary(codebook, .x)
})

print(study_comparison)
#   study total_items items_with_irt irt_coverage threshold_coverage...

# Create coverage visualization
library(ggplot2)
study_comparison %>%
  dplyr::select(study, total_items, items_with_irt, items_with_thresholds) %>%
  tidyr::pivot_longer(cols = -study, names_to = "metric", values_to = "count") %>%
  ggplot2::ggplot(ggplot2::aes(x = study, y = count, fill = metric)) +
  ggplot2::geom_col(position = "dodge") +
  ggplot2::labs(title = "IRT Parameter Coverage by Study")
```

## Advanced Examples

### Combining Multiple Extractions

```r
# Create comprehensive item analysis dataset
create_item_analysis_data <- function(codebook, study) {
  # Get basic content
  content <- codebook_extract_item_content(codebook, studies = study)

  # Get IRT parameters
  irt_params <- codebook_extract_irt_parameters(codebook, study, format = "wide")

  # Get response sets
  responses <- codebook_extract_response_sets(codebook, study = study) %>%
    dplyr::group_by(item_id) %>%
    dplyr::summarise(
      response_set = dplyr::first(response_set),
      n_options = dplyr::n(),
      has_missing = any(missing),
      .groups = "drop"
    )

  # Get lexicon mapping
  lexicons <- codebook_extract_lexicon_crosswalk(codebook, studies = study) %>%
    dplyr::select(item_id, equate, !!study := paste0(tolower(study)))

  # Combine all information
  content %>%
    dplyr::left_join(irt_params, by = "item_id") %>%
    dplyr::left_join(responses, by = "item_id") %>%
    dplyr::left_join(lexicons, by = "item_id") %>%
    dplyr::arrange(domain, item_id)
}

# Use the function
ne25_analysis <- create_item_analysis_data(codebook, "NE25")
```

### Cross-Study Item Comparison

```r
# Compare item coverage across studies
compare_item_coverage <- function(codebook, studies) {
  # Get lexicon crosswalk
  crosswalk <- codebook_extract_lexicon_crosswalk(codebook, studies = studies)

  # Check which studies each item appears in
  items_list <- codebook$items

  coverage_data <- purrr::map_df(names(items_list), function(item_id) {
    item <- items_list[[item_id]]

    # Check presence in each study
    study_presence <- purrr::map_lgl(studies, ~ .x %in% item$studies)
    names(study_presence) <- studies

    tibble::tibble(
      item_id = item_id,
      !!!study_presence,
      total_studies = sum(study_presence)
    )
  })

  return(coverage_data)
}

# Use the function
ne_coverage <- compare_item_coverage(codebook, c("NE25", "NE22", "NE20"))

# Items that appear in all three studies
core_items <- ne_coverage %>%
  dplyr::filter(total_studies == 3) %>%
  dplyr::pull(item_id)
```

## Error Handling

The functions include comprehensive error checking:

```r
# Invalid codebook object
try(codebook_extract_lexicon_crosswalk("not_a_codebook"))
# Error: Input must be a codebook object created with load_codebook()

# Invalid study name
try(codebook_extract_irt_parameters(codebook, "INVALID_STUDY"))
# Warning: No items found for study: INVALID_STUDY

# Multiple studies (when single study required)
try(codebook_extract_irt_parameters(codebook, c("NE25", "NE22")))
# Error: Please specify exactly one study
```

## Performance Tips

1. **Cache the codebook object**: Loading is slow, so keep it in memory for multiple extractions
2. **Filter early**: Use study/domain filters to reduce processing time
3. **Choose appropriate format**: Use wide format for analysis, long format for modeling
4. **Batch similar extractions**: Combine multiple extractions in one workflow

## Integration with Analysis Pipelines

### Example: IRT Analysis Pipeline

```r
# Complete IRT analysis workflow
run_irt_analysis <- function(study_name) {
  # Load codebook
  codebook <- load_codebook("codebook/data/codebook.json")

  # Get items with IRT parameters
  items_with_irt <- codebook_extract_irt_parameters(codebook, study_name, format = "wide") %>%
    dplyr::filter(!is.na(loading_1))

  # Get item content for interpretation
  item_content <- codebook_extract_item_content(codebook, studies = study_name) %>%
    dplyr::filter(item_id %in% items_with_irt$item_id)

  # Get study summary
  study_summary <- codebook_extract_study_summary(codebook, study_name)

  # Return comprehensive results
  list(
    study = study_name,
    summary = study_summary,
    items = items_with_irt,
    content = item_content,
    n_items_with_irt = nrow(items_with_irt)
  )
}

# Run analysis
ne22_analysis <- run_irt_analysis("NE22")
```

## Future Extensions

Potential additional functions to add:

- `codebook_extract_domain_structure()` - Hierarchical domain relationships
- `codebook_extract_age_brackets()` - Age-appropriate item sets
- `codebook_extract_scoring_rules()` - Reverse coding and transformation rules
- `codebook_validate_data()` - Check data against codebook constraints
- `codebook_export_spss()` - Export codebook in SPSS format

---

*Documentation updated: September 2025*
*Functions available in: `R/codebook/extract_codebook.R`*
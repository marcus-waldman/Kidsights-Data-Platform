# ==============================================================================
# MN26 vs NE25 Variable Reconciliation Audit
# ==============================================================================
# Compares REDCap data dictionaries field-by-field to identify all variable
# changes between NE25 (Nebraska 2025) and MN26 (Minnesota 2026) studies.
#
# Outputs:
#   - reports/mn26/reconciliation_audit.html  (interactive HTML report)
#   - config/mappings/ne25_to_mn26_field_map.csv (machine-readable mapping)
#   - data/export/mn26/mn26_data_dictionary_full.csv (cached MN26 dictionary)
#   - data/export/mn26/mn26_data_dictionary_active.csv (active fields only)
#
# Usage:
#   Rscript scripts/mn26/reconciliation_audit.R
#
# Prerequisites:
#   - MN26 REDCap API credentials at C:/my_auths/kidsights_redcap_norc_MN_2026.csv
#   - NE25 dictionary cached at data/export/ne25/ne25_data_dictionary.csv
#   - kidsights-norc repo at C:/Users/marcu/git-repositories/kidsights-norc
# ==============================================================================

cat("\n========================================\n")
cat("MN26 vs NE25 Reconciliation Audit\n")
cat("========================================\n\n")

# --- Setup -------------------------------------------------------------------

required_packages <- c("dplyr", "tidyr", "httr", "stringr", "knitr", "htmltools")
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, repos = "https://cloud.r-project.org")
  }
  library(pkg, character.only = TRUE)
}

# Paths
project_root <- normalizePath(".", winslash = "/")
norc_repo    <- "C:/Users/marcu/git-repositories/kidsights-norc"
mn26_creds   <- "C:/my_auths/kidsights_redcap_norc_MN_2026.csv"
ne25_dict_path <- file.path(project_root, "data/export/ne25/ne25_data_dictionary.csv")
redcap_url   <- "https://unmcredcap.unmc.edu/redcap/api/"

# Output paths
output_html  <- file.path(project_root, "reports/mn26/reconciliation_audit.html")
output_csv   <- file.path(project_root, "config/mappings/ne25_to_mn26_field_map.csv")
mn26_dict_full_path   <- file.path(project_root, "data/export/mn26/mn26_data_dictionary_full.csv")
mn26_dict_active_path <- file.path(project_root, "data/export/mn26/mn26_data_dictionary_active.csv")

# Create output directories
dir.create(dirname(output_html), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(output_csv), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(mn26_dict_full_path), recursive = TRUE, showWarnings = FALSE)

# Source kidsights-norc utilities for API access
source(file.path(norc_repo, "progress-monitoring/mn26/utils/redcap_utils.R"))

# ==============================================================================
# STEP 1: Load NE25 Dictionary (from cached CSV)
# ==============================================================================
cat("Step 1: Loading NE25 dictionary from CSV...\n")

ne25_raw <- read.csv(ne25_dict_path, stringsAsFactors = FALSE)
cat("  NE25 fields: ", nrow(ne25_raw), "\n")

# Normalize to standard columns
ne25_df <- ne25_raw %>%
  dplyr::select(
    field_name,
    form_name,
    field_type,
    field_label,
    select_choices = select_choices_or_calculations,
    field_annotation,
    branching_logic,
    required_field
  ) %>%
  dplyr::mutate(
    study = "NE25",
    is_hidden = grepl("@HIDDEN", field_annotation, ignore.case = TRUE),
    # Clean HTML from labels for comparison
    label_clean = gsub("<[^>]+>", "", field_label) %>%
      stringr::str_squish() %>%
      tolower()
  )

# ==============================================================================
# STEP 2: Pull MN26 Dictionary (live API)
# ==============================================================================
cat("\nStep 2: Pulling MN26 dictionary from REDCap API...\n")

creds <- load_api_credentials(mn26_creds)
token <- creds$api_code[1]

# Pull full dictionary (includes @HIDDEN)
mn26_full_list <- get_data_dictionary(redcap_url, token, exclude_hidden = FALSE)

# Pull active dictionary (excludes @HIDDEN)
mn26_active_list <- get_data_dictionary(redcap_url, token, exclude_hidden = TRUE)

cat("  MN26 full fields:   ", length(mn26_full_list), "\n")
cat("  MN26 active fields: ", length(mn26_active_list), "\n")
cat("  MN26 hidden fields: ", length(mn26_full_list) - length(mn26_active_list), "\n")

# Convert API list to data frame
api_list_to_df <- function(dict_list, study_label) {
  rows <- lapply(names(dict_list), function(fname) {
    d <- dict_list[[fname]]
    data.frame(
      field_name      = fname,
      form_name       = if (is.null(d$form_name)) NA_character_ else d$form_name,
      field_type      = if (is.null(d$field_type)) NA_character_ else d$field_type,
      field_label     = if (is.null(d$field_label)) NA_character_ else d$field_label,
      select_choices  = if (is.null(d$select_choices_or_calculations)) NA_character_ else d$select_choices_or_calculations,
      field_annotation = if (is.null(d$field_annotation)) NA_character_ else d$field_annotation,
      branching_logic = if (is.null(d$branching_logic)) NA_character_ else d$branching_logic,
      required_field  = if (is.null(d$required_field)) NA_character_ else d$required_field,
      stringsAsFactors = FALSE
    )
  })
  df <- dplyr::bind_rows(rows) %>%
    dplyr::mutate(
      study = study_label,
      is_hidden = grepl("@HIDDEN", field_annotation, ignore.case = TRUE),
      label_clean = gsub("<[^>]+>", "", field_label) %>%
        stringr::str_squish() %>%
        tolower()
    )
  return(df)
}

mn26_full_df   <- api_list_to_df(mn26_full_list, "MN26_full")
mn26_active_df <- api_list_to_df(mn26_active_list, "MN26_active")

# Cache MN26 dictionaries as CSV for future reference
write.csv(mn26_full_df, mn26_dict_full_path, row.names = FALSE)
write.csv(mn26_active_df, mn26_dict_active_path, row.names = FALSE)
cat("  Cached MN26 dictionaries to data/export/mn26/\n")

# ==============================================================================
# STEP 3: Known Seed Mappings
# ==============================================================================
cat("\nStep 3: Loading known seed mappings...\n")

# Known field renames (NE25 → MN26)
seed_renames <- data.frame(
  ne25_field = c("cqr002",     "age_in_days",   "eqstate"),
  mn26_field = c("mn2",        "age_in_days_n", "mn_eqstate"),
  notes      = c("Parent gender: renamed, added Non-binary=97",
                  "Child age in days: renamed",
                  "State eligibility: renamed for Minnesota"),
  stringsAsFactors = FALSE
)

# Known structural changes (checkbox reorganization)
# NOTE: REDCap dictionaries list checkboxes as base field names (e.g., "cqr010")
# not expanded names (e.g., "cqr010___1"). Match on base names.
seed_structural <- data.frame(
  ne25_base = c("cqr010",  "sq002"),
  mn26_base = c("cqr010b", "sq002b"),
  notes     = c("Child race: 15 granular categories (1-15) collapsed to 6 (100-105)",
                 "Parent race: 15 granular categories (1-15) collapsed to 6 (100-105)"),
  stringsAsFactors = FALSE
)

cat("  Seed renames: ", nrow(seed_renames), "\n")
cat("  Seed structural: ", nrow(seed_structural), "\n")

# ==============================================================================
# STEP 4: Classify Each Field
# ==============================================================================
cat("\nStep 4: Classifying fields...\n")

# Get active MN26 field names and NE25 field names
mn26_fields <- mn26_active_df$field_name
ne25_fields <- ne25_df$field_name

# Identify hidden MN26 fields (present in full but not active)
mn26_hidden_fields <- setdiff(mn26_full_df$field_name, mn26_active_df$field_name)

# Build classification table
results <- list()

# --- 4a: Check fields present in both ---
shared_fields <- intersect(ne25_fields, mn26_fields)
for (fld in shared_fields) {
  ne25_row <- ne25_df[ne25_df$field_name == fld, ]
  mn26_row <- mn26_active_df[mn26_active_df$field_name == fld, ]

  ne25_type    <- ne25_row$field_type[1]
  mn26_type    <- mn26_row$field_type[1]
  ne25_choices <- ne25_row$select_choices[1]
  mn26_choices <- mn26_row$select_choices[1]

  # Normalize NA/empty for comparison
  ne25_choices_norm <- if (is.na(ne25_choices) || ne25_choices == "") "" else trimws(ne25_choices)
  mn26_choices_norm <- if (is.na(mn26_choices) || mn26_choices == "") "" else trimws(mn26_choices)

  if (ne25_type == mn26_type && ne25_choices_norm == mn26_choices_norm) {
    category <- "IDENTICAL"
    choice_diff <- ""
  } else if (ne25_type != mn26_type) {
    category <- "TYPE_CHANGED"
    choice_diff <- paste0("NE25: ", ne25_type, " -> MN26: ", mn26_type)
  } else {
    category <- "RECODED"
    choice_diff <- paste0("NE25: ", substr(ne25_choices_norm, 1, 120),
                          " | MN26: ", substr(mn26_choices_norm, 1, 120))
  }

  results[[length(results) + 1]] <- data.frame(
    ne25_field  = fld,
    mn26_field  = fld,
    category    = category,
    ne25_form   = ne25_row$form_name[1],
    mn26_form   = mn26_row$form_name[1],
    field_type  = mn26_type,
    ne25_label  = substr(ne25_row$field_label[1], 1, 200),
    mn26_label  = substr(mn26_row$field_label[1], 1, 200),
    choice_diff = choice_diff,
    high_risk   = FALSE,
    notes       = "",
    stringsAsFactors = FALSE
  )
}

# --- 4b: Check seed renames ---
# Check against FULL MN26 dictionary (not just active) because some renamed
# fields like age_in_days_n are @HIDDEN calc fields used in branching logic
for (i in 1:nrow(seed_renames)) {
  ne25_fld <- seed_renames$ne25_field[i]
  mn26_fld <- seed_renames$mn26_field[i]

  ne25_row <- ne25_df[ne25_df$field_name == ne25_fld, ]
  # Check active first, then fall back to full dictionary
  mn26_row <- mn26_active_df[mn26_active_df$field_name == mn26_fld, ]
  mn26_hidden <- FALSE
  if (nrow(mn26_row) == 0) {
    mn26_row <- mn26_full_df[mn26_full_df$field_name == mn26_fld, ]
    mn26_hidden <- TRUE
  }

  if (nrow(ne25_row) > 0 && nrow(mn26_row) > 0) {
    ne25_choices <- if (is.na(ne25_row$select_choices[1])) "" else ne25_row$select_choices[1]
    mn26_choices <- if (is.na(mn26_row$select_choices[1])) "" else mn26_row$select_choices[1]
    hidden_note <- if (mn26_hidden) " [both @HIDDEN calc fields]" else ""

    results[[length(results) + 1]] <- data.frame(
      ne25_field  = ne25_fld,
      mn26_field  = mn26_fld,
      category    = "RENAMED",
      ne25_form   = ne25_row$form_name[1],
      mn26_form   = mn26_row$form_name[1],
      field_type  = mn26_row$field_type[1],
      ne25_label  = substr(ne25_row$field_label[1], 1, 200),
      mn26_label  = substr(mn26_row$field_label[1], 1, 200),
      choice_diff = if (ne25_choices != mn26_choices)
        paste0("NE25: ", substr(ne25_choices, 1, 120), " | MN26: ", substr(mn26_choices, 1, 120))
      else "",
      high_risk   = TRUE,
      notes       = paste0(seed_renames$notes[i], hidden_note),
      stringsAsFactors = FALSE
    )
  } else {
    cat("  [WARN] Seed rename not found: ", ne25_fld, " -> ", mn26_fld,
        " (NE25 rows: ", nrow(ne25_row), ", MN26 rows: ", nrow(mn26_row), ")\n")
  }
}

# --- 4c: Check structural changes (checkbox reorganization) ---
# REDCap dictionaries list checkbox fields as base names (e.g., "cqr010")
# with all options in select_choices. Compare base-to-base.
for (i in 1:nrow(seed_structural)) {
  ne25_base <- seed_structural$ne25_base[i]
  mn26_base <- seed_structural$mn26_base[i]

  ne25_row <- ne25_df[ne25_df$field_name == ne25_base, ]
  mn26_row <- mn26_active_df[mn26_active_df$field_name == mn26_base, ]

  ne25_choices <- if (nrow(ne25_row) > 0 && !is.na(ne25_row$select_choices[1])) ne25_row$select_choices[1] else ""
  mn26_choices <- if (nrow(mn26_row) > 0 && !is.na(mn26_row$select_choices[1])) mn26_row$select_choices[1] else ""

  # Count options by splitting on "|"
  ne25_n_opts <- if (ne25_choices == "") 0 else length(strsplit(ne25_choices, "\\|")[[1]])
  mn26_n_opts <- if (mn26_choices == "") 0 else length(strsplit(mn26_choices, "\\|")[[1]])

  results[[length(results) + 1]] <- data.frame(
    ne25_field  = ne25_base,
    mn26_field  = mn26_base,
    category    = "STRUCTURAL",
    ne25_form   = if (nrow(ne25_row) > 0) ne25_row$form_name[1] else NA,
    mn26_form   = if (nrow(mn26_row) > 0) mn26_row$form_name[1] else NA,
    field_type  = "checkbox",
    ne25_label  = if (nrow(ne25_row) > 0) substr(ne25_row$field_label[1], 1, 200) else NA,
    mn26_label  = if (nrow(mn26_row) > 0) substr(mn26_row$field_label[1], 1, 200) else NA,
    choice_diff = paste0(ne25_n_opts, " NE25 options -> ", mn26_n_opts, " MN26 options. ",
                         "NE25: ", substr(ne25_choices, 1, 100), " | MN26: ", substr(mn26_choices, 1, 100)),
    high_risk   = TRUE,
    notes       = seed_structural$notes[i],
    stringsAsFactors = FALSE
  )
}

# --- 4d: NE25-only fields (not in MN26 active, not a seed rename/structural source) ---
# THREE-WAY comparison: check if field exists in MN26 FULL (hidden) dictionary
# and compare choices to determine if it's truly removed vs hidden-but-present
seed_ne25_fields <- c(seed_renames$ne25_field, seed_structural$ne25_base)

ne25_only <- setdiff(ne25_fields, c(mn26_fields, seed_ne25_fields))
for (fld in ne25_only) {
  ne25_row <- ne25_df[ne25_df$field_name == fld, ]

  if (fld %in% mn26_hidden_fields) {
    # Field exists in MN26 but is @HIDDEN — compare choices to determine status
    mn26_hid_row <- mn26_full_df[mn26_full_df$field_name == fld, ]

    ne25_type    <- ne25_row$field_type[1]
    mn26_type    <- mn26_hid_row$field_type[1]
    ne25_choices <- ne25_row$select_choices[1]
    mn26_choices <- mn26_hid_row$select_choices[1]

    ne25_ch_norm <- if (is.na(ne25_choices) || ne25_choices == "") "" else trimws(ne25_choices)
    mn26_ch_norm <- if (is.na(mn26_choices) || mn26_choices == "") "" else trimws(mn26_choices)

    if (ne25_type == mn26_type && ne25_ch_norm == mn26_ch_norm) {
      cat_label <- "HIDDEN_IDENTICAL"
      diff_text <- ""
    } else {
      cat_label <- "HIDDEN_RECODED"
      diff_text <- paste0("NE25: ", substr(ne25_ch_norm, 1, 120),
                          " | MN26(@HIDDEN): ", substr(mn26_ch_norm, 1, 120))
    }

    results[[length(results) + 1]] <- data.frame(
      ne25_field  = fld,
      mn26_field  = paste0(fld, " (@HIDDEN)"),
      category    = cat_label,
      ne25_form   = ne25_row$form_name[1],
      mn26_form   = mn26_hid_row$form_name[1],
      field_type  = mn26_type,
      ne25_label  = substr(ne25_row$field_label[1], 1, 200),
      mn26_label  = substr(mn26_hid_row$field_label[1], 1, 200),
      choice_diff = diff_text,
      high_risk   = FALSE,
      notes       = "@HIDDEN in MN26 but still in data — pipeline-relevant",
      stringsAsFactors = FALSE
    )
  } else {
    # Field truly absent from MN26 dictionary entirely
    # Try fuzzy match on label
    fuzzy_match <- ""
    if (!is.na(ne25_row$label_clean[1]) && nchar(ne25_row$label_clean[1]) > 10) {
      candidates <- mn26_active_df %>%
        dplyr::filter(!field_name %in% shared_fields) %>%
        dplyr::filter(!is.na(label_clean), nchar(label_clean) > 10)

      if (nrow(candidates) > 0) {
        dists <- stringdist::stringdist(ne25_row$label_clean[1], candidates$label_clean, method = "jw")
        best_idx <- which.min(dists)
        if (length(best_idx) > 0 && dists[best_idx] < 0.15) {
          fuzzy_match <- paste0("Possible match: ", candidates$field_name[best_idx],
                                " (dist=", round(dists[best_idx], 3), ")")
        }
      }
    }

    results[[length(results) + 1]] <- data.frame(
      ne25_field  = fld,
      mn26_field  = NA_character_,
      category    = "REMOVED_ABSENT",
      ne25_form   = ne25_row$form_name[1],
      mn26_form   = NA_character_,
      field_type  = ne25_row$field_type[1],
      ne25_label  = substr(ne25_row$field_label[1], 1, 200),
      mn26_label  = NA_character_,
      choice_diff = "",
      high_risk   = FALSE,
      notes       = fuzzy_match,
      stringsAsFactors = FALSE
    )
  }
}

# --- 4e: MN26-only fields (active + hidden) ---
seed_mn26_fields <- c(seed_renames$mn26_field, seed_structural$mn26_base)

# Active MN26-only fields
mn26_only <- setdiff(mn26_fields, c(ne25_fields, seed_mn26_fields))

# Separate child 2 fields from truly new fields
c2_fields <- mn26_only[grepl("_c2|_2_complete|child_information_2", mn26_only)]
new_fields <- setdiff(mn26_only, c2_fields)

for (fld in c2_fields) {
  mn26_row <- mn26_active_df[mn26_active_df$field_name == fld, ]
  results[[length(results) + 1]] <- data.frame(
    ne25_field  = NA_character_,
    mn26_field  = fld,
    category    = "NEW_CHILD2",
    ne25_form   = NA_character_,
    mn26_form   = mn26_row$form_name[1],
    field_type  = mn26_row$field_type[1],
    ne25_label  = NA_character_,
    mn26_label  = substr(mn26_row$field_label[1], 1, 200),
    choice_diff = "",
    high_risk   = FALSE,
    notes       = "Child 2 variable (multi-child support)",
    stringsAsFactors = FALSE
  )
}

for (fld in new_fields) {
  mn26_row <- mn26_active_df[mn26_active_df$field_name == fld, ]
  results[[length(results) + 1]] <- data.frame(
    ne25_field  = NA_character_,
    mn26_field  = fld,
    category    = "NEW_MN26",
    ne25_form   = NA_character_,
    mn26_form   = mn26_row$form_name[1],
    field_type  = mn26_row$field_type[1],
    ne25_label  = NA_character_,
    mn26_label  = substr(mn26_row$field_label[1], 1, 200),
    choice_diff = "",
    high_risk   = FALSE,
    notes       = "",
    stringsAsFactors = FALSE
  )
}

# --- 4f-extra: Hidden MN26-only fields (in full but not active, and not in NE25) ---
# These are NEW fields added for MN26 but marked @HIDDEN
mn26_hidden_only <- setdiff(mn26_hidden_fields, c(ne25_fields, seed_mn26_fields, seed_renames$mn26_field))
# Exclude fields already handled as hidden versions of NE25 fields
mn26_hidden_only <- setdiff(mn26_hidden_only, ne25_only[ne25_only %in% mn26_hidden_fields])

# Also find child 2 hidden fields
c2_hidden <- mn26_hidden_only[grepl("_c2|_2_complete|child_information_2", mn26_hidden_only)]
new_hidden <- setdiff(mn26_hidden_only, c2_hidden)

for (fld in c2_hidden) {
  mn26_row <- mn26_full_df[mn26_full_df$field_name == fld, ]
  results[[length(results) + 1]] <- data.frame(
    ne25_field  = NA_character_,
    mn26_field  = paste0(fld, " (@HIDDEN)"),
    category    = "NEW_CHILD2",
    ne25_form   = NA_character_,
    mn26_form   = mn26_row$form_name[1],
    field_type  = mn26_row$field_type[1],
    ne25_label  = NA_character_,
    mn26_label  = substr(mn26_row$field_label[1], 1, 200),
    choice_diff = "",
    high_risk   = FALSE,
    notes       = "Child 2 variable (@HIDDEN in MN26 but still in data)",
    stringsAsFactors = FALSE
  )
}

for (fld in new_hidden) {
  mn26_row <- mn26_full_df[mn26_full_df$field_name == fld, ]
  results[[length(results) + 1]] <- data.frame(
    ne25_field  = NA_character_,
    mn26_field  = paste0(fld, " (@HIDDEN)"),
    category    = "NEW_MN26_HIDDEN",
    ne25_form   = NA_character_,
    mn26_form   = mn26_row$form_name[1],
    field_type  = mn26_row$field_type[1],
    ne25_label  = NA_character_,
    mn26_label  = substr(mn26_row$field_label[1], 1, 200),
    choice_diff = "",
    high_risk   = FALSE,
    notes       = "@HIDDEN in MN26, no NE25 equivalent",
    stringsAsFactors = FALSE
  )
}

# --- 4f: Flag high-risk RECODED fields ---
audit_df <- dplyr::bind_rows(results)

# NOTE: cqr009 sex codes are IDENTICAL in both dictionaries (1=Female, 0=Male).
# Earlier analysis incorrectly claimed they were swapped. Verified 2026-04-04.

# Flag eligibility variables
eligibility_vars <- c("eq001", "eq002", "eq003", "eqstate", "mn_eqstate", "age_in_days", "age_in_days_n")
audit_df$high_risk[audit_df$ne25_field %in% eligibility_vars | audit_df$mn26_field %in% eligibility_vars] <- TRUE

# Flag composite score components
composite_vars <- c("cqfb013", "cqfb014", "cqfb015", "cqfb016",
                     paste0("cace", 1:10), paste0("cqr0", 17:24))
audit_df$high_risk[audit_df$ne25_field %in% composite_vars | audit_df$mn26_field %in% composite_vars] <- TRUE

cat("  Total classified: ", nrow(audit_df), "\n")

# ==============================================================================
# STEP 5: Summary Statistics
# ==============================================================================
cat("\nStep 5: Computing summary statistics...\n")

summary_counts <- audit_df %>%
  dplyr::count(category) %>%
  dplyr::arrange(dplyr::desc(n))

cat("\n  --- Classification Summary ---\n")
for (i in 1:nrow(summary_counts)) {
  cat(sprintf("  %-20s %d\n", summary_counts$category[i], summary_counts$n[i]))
}
cat(sprintf("  %-20s %d\n", "TOTAL", sum(summary_counts$n)))

high_risk_count <- sum(audit_df$high_risk, na.rm = TRUE)
cat(sprintf("\n  High-risk fields: %d\n", high_risk_count))

# Form/instrument comparison
ne25_forms <- unique(ne25_df$form_name)
mn26_forms <- unique(mn26_active_df$form_name)
cat("\n  NE25 instruments: ", length(ne25_forms), "\n")
cat("  MN26 instruments: ", length(mn26_forms), "\n")
cat("  Shared instruments: ", length(intersect(ne25_forms, mn26_forms)), "\n")
cat("  NE25-only instruments: ", length(setdiff(ne25_forms, mn26_forms)), "\n")
cat("  MN26-only instruments: ", length(setdiff(mn26_forms, ne25_forms)), "\n")

# ==============================================================================
# STEP 6: Save Machine-Readable CSV
# ==============================================================================
cat("\nStep 6: Saving field mapping CSV...\n")

# Sort by category for readability
audit_df_sorted <- audit_df %>%
  dplyr::arrange(
    factor(category, levels = c(
      "RENAMED", "RECODED", "HIDDEN_RECODED", "STRUCTURAL", "TYPE_CHANGED",
      "NEW_CHILD2", "NEW_MN26", "NEW_MN26_HIDDEN",
      "REMOVED_ABSENT",
      "HIDDEN_IDENTICAL", "IDENTICAL"
    )),
    ne25_field, mn26_field
  )

write.csv(audit_df_sorted, output_csv, row.names = FALSE)
cat("  Saved: ", output_csv, "\n")

# ==============================================================================
# STEP 7: Generate HTML Report
# ==============================================================================
cat("\nStep 7: Generating HTML report...\n")

# Build HTML manually (avoids rmarkdown/quarto dependency)
html_parts <- list()

# --- CSS ---
html_parts$css <- '
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; max-width: 1400px; }
  h1 { color: #1a1a2e; border-bottom: 3px solid #16213e; padding-bottom: 10px; }
  h2 { color: #16213e; margin-top: 30px; }
  h3 { color: #0f3460; }
  .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin: 20px 0; }
  .summary-card { background: #f8f9fa; border-radius: 8px; padding: 15px; text-align: center; border-left: 4px solid #ccc; }
  .summary-card.identical { border-left-color: #28a745; }
  .summary-card.recoded { border-left-color: #fd7e14; }
  .summary-card.renamed { border-left-color: #007bff; }
  .summary-card.structural { border-left-color: #6f42c1; }
  .summary-card.new { border-left-color: #20c997; }
  .summary-card.removed { border-left-color: #dc3545; }
  .summary-card .count { font-size: 2em; font-weight: bold; color: #1a1a2e; }
  .summary-card .label { font-size: 0.85em; color: #6c757d; }
  table { border-collapse: collapse; width: 100%; margin: 15px 0; font-size: 0.85em; }
  th { background: #16213e; color: white; padding: 10px; text-align: left; position: sticky; top: 0; }
  td { padding: 8px 10px; border-bottom: 1px solid #dee2e6; vertical-align: top; max-width: 300px; overflow: hidden; text-overflow: ellipsis; }
  tr:hover { background: #f1f3f5; }
  .high-risk { background: #fff3cd !important; }
  .tag { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75em; font-weight: bold; }
  .tag-identical { background: #d4edda; color: #155724; }
  .tag-recoded { background: #ffe5d0; color: #8a4500; }
  .tag-renamed { background: #cce5ff; color: #004085; }
  .tag-structural { background: #e2d5f1; color: #4a1486; }
  .tag-new { background: #c3fae8; color: #087f5b; }
  .tag-removed { background: #f8d7da; color: #721c24; }
  .tag-hidden { background: #e9ecef; color: #495057; }
  .tag-type { background: #ffeaa7; color: #6c5ce7; }
  .risk-badge { background: #dc3545; color: white; padding: 2px 6px; border-radius: 3px; font-size: 0.7em; }
  .filter-bar { margin: 15px 0; }
  .filter-bar input { padding: 8px 12px; width: 300px; border: 1px solid #ced4da; border-radius: 4px; font-size: 0.9em; }
  .filter-bar select { padding: 8px; border: 1px solid #ced4da; border-radius: 4px; margin-left: 10px; }
  .instrument-list { columns: 2; margin: 10px 0; }
  .instrument-list li { margin: 3px 0; }
  .choice-diff { font-family: monospace; font-size: 0.8em; color: #495057; word-break: break-all; }
</style>
'

# --- Header ---
html_parts$header <- sprintf('
<h1>MN26 vs NE25 Variable Reconciliation Audit</h1>
<p><strong>Generated:</strong> %s | <strong>NE25 fields:</strong> %d | <strong>MN26 active fields:</strong> %d | <strong>MN26 hidden:</strong> %d</p>
', format(Sys.time(), "%Y-%m-%d %H:%M"), nrow(ne25_df), nrow(mn26_active_df),
   length(mn26_hidden_fields))

# --- Summary cards ---
card_data <- list(
  list(cat = "IDENTICAL",         class = "identical",  label = "Identical"),
  list(cat = "HIDDEN_IDENTICAL",  class = "identical",  label = "Hidden Identical"),
  list(cat = "RECODED",           class = "recoded",    label = "Recoded"),
  list(cat = "HIDDEN_RECODED",    class = "recoded",    label = "Hidden Recoded"),
  list(cat = "RENAMED",           class = "renamed",    label = "Renamed"),
  list(cat = "STRUCTURAL",        class = "structural", label = "Structural"),
  list(cat = "TYPE_CHANGED",      class = "recoded",    label = "Type Changed"),
  list(cat = "NEW_CHILD2",        class = "new",        label = "New (Child 2)"),
  list(cat = "NEW_MN26",          class = "new",        label = "New (MN26 active)"),
  list(cat = "NEW_MN26_HIDDEN",   class = "new",        label = "New (MN26 hidden)"),
  list(cat = "REMOVED_ABSENT",    class = "removed",    label = "Removed (Absent)")
)

cards_html <- '<h2>Summary</h2>\n<div class="summary-grid">\n'
for (cd in card_data) {
  n <- sum(audit_df$category == cd$cat, na.rm = TRUE)
  if (n > 0) {
    cards_html <- paste0(cards_html, sprintf(
      '<div class="summary-card %s"><div class="count">%d</div><div class="label">%s</div></div>\n',
      cd$class, n, cd$label
    ))
  }
}
cards_html <- paste0(cards_html, sprintf(
  '<div class="summary-card"><div class="count" style="color:#dc3545;">%d</div><div class="label">High Risk</div></div>\n',
  high_risk_count
))
cards_html <- paste0(cards_html, '</div>\n')
html_parts$summary <- cards_html

# --- High-risk table ---
high_risk_df <- audit_df_sorted %>% dplyr::filter(high_risk == TRUE)
if (nrow(high_risk_df) > 0) {
  hr_html <- '<h2>High-Risk Changes</h2>\n<p>These fields affect eligibility, joins, or composite scores and require careful handling in MN26 transforms.</p>\n'
  hr_html <- paste0(hr_html, '<table>\n<tr><th>Category</th><th>NE25 Field</th><th>MN26 Field</th><th>Type</th><th>Details</th><th>Notes</th></tr>\n')
  for (i in 1:nrow(high_risk_df)) {
    r <- high_risk_df[i, ]
    tag_class <- tolower(gsub("_.*", "", r$category))
    hr_html <- paste0(hr_html, sprintf(
      '<tr class="high-risk"><td><span class="tag tag-%s">%s</span></td><td>%s</td><td>%s</td><td>%s</td><td class="choice-diff">%s</td><td>%s</td></tr>\n',
      tag_class, r$category,
      if (is.na(r$ne25_field)) "-" else htmltools::htmlEscape(r$ne25_field),
      if (is.na(r$mn26_field)) "-" else htmltools::htmlEscape(r$mn26_field),
      if (is.na(r$field_type)) "-" else r$field_type,
      if (is.na(r$choice_diff) || r$choice_diff == "") "-" else htmltools::htmlEscape(r$choice_diff),
      if (is.na(r$notes) || r$notes == "") "-" else htmltools::htmlEscape(r$notes)
    ))
  }
  hr_html <- paste0(hr_html, '</table>\n')
  html_parts$high_risk <- hr_html
}

# --- Instrument comparison ---
inst_html <- '<h2>Instrument Comparison</h2>\n'
shared_inst <- intersect(ne25_forms, mn26_forms)
ne25_only_inst <- setdiff(ne25_forms, mn26_forms)
mn26_only_inst <- setdiff(mn26_forms, ne25_forms)

inst_html <- paste0(inst_html, sprintf('<h3>Shared Instruments (%d)</h3>\n<ul class="instrument-list">', length(shared_inst)))
for (inst in sort(shared_inst)) inst_html <- paste0(inst_html, '<li>', htmltools::htmlEscape(inst), '</li>')
inst_html <- paste0(inst_html, '</ul>\n')

if (length(ne25_only_inst) > 0) {
  inst_html <- paste0(inst_html, sprintf('<h3>NE25-Only Instruments (%d)</h3>\n<ul class="instrument-list">', length(ne25_only_inst)))
  for (inst in sort(ne25_only_inst)) inst_html <- paste0(inst_html, '<li>', htmltools::htmlEscape(inst), '</li>')
  inst_html <- paste0(inst_html, '</ul>\n')
}
if (length(mn26_only_inst) > 0) {
  inst_html <- paste0(inst_html, sprintf('<h3>MN26-Only Instruments (%d)</h3>\n<ul class="instrument-list">', length(mn26_only_inst)))
  for (inst in sort(mn26_only_inst)) inst_html <- paste0(inst_html, '<li>', htmltools::htmlEscape(inst), '</li>')
  inst_html <- paste0(inst_html, '</ul>\n')
}
html_parts$instruments <- inst_html

# --- Full audit table with filter ---
full_html <- '<h2>Full Field Audit</h2>\n'
full_html <- paste0(full_html, '
<div class="filter-bar">
  <input type="text" id="searchInput" placeholder="Search fields..." onkeyup="filterTable()">
  <select id="categoryFilter" onchange="filterTable()">
    <option value="">All Categories</option>
')
for (cat in sort(unique(audit_df_sorted$category))) {
  full_html <- paste0(full_html, sprintf('    <option value="%s">%s</option>\n', cat, cat))
}
full_html <- paste0(full_html, '  </select>
  <label style="margin-left:10px"><input type="checkbox" id="riskOnly" onchange="filterTable()"> High-risk only</label>
</div>
')

full_html <- paste0(full_html, '<table id="auditTable">\n<thead><tr><th>Category</th><th>NE25 Field</th><th>MN26 Field</th><th>NE25 Form</th><th>MN26 Form</th><th>Type</th><th>Choice Diff</th><th>Notes</th></tr></thead>\n<tbody>\n')
for (i in 1:nrow(audit_df_sorted)) {
  r <- audit_df_sorted[i, ]
  tag_class <- tolower(gsub("_.*", "", r$category))
  row_class <- if (isTRUE(r$high_risk)) ' class="high-risk"' else ''
  risk_badge <- if (isTRUE(r$high_risk)) ' <span class="risk-badge">RISK</span>' else ''

  full_html <- paste0(full_html, sprintf(
    '<tr%s data-category="%s" data-risk="%s"><td><span class="tag tag-%s">%s</span>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td class="choice-diff">%s</td><td>%s</td></tr>\n',
    row_class, r$category, if (isTRUE(r$high_risk)) "true" else "false",
    tag_class, r$category, risk_badge,
    if (is.na(r$ne25_field)) "-" else htmltools::htmlEscape(r$ne25_field),
    if (is.na(r$mn26_field)) "-" else htmltools::htmlEscape(r$mn26_field),
    if (is.na(r$ne25_form)) "-" else htmltools::htmlEscape(r$ne25_form),
    if (is.na(r$mn26_form)) "-" else htmltools::htmlEscape(r$mn26_form),
    if (is.na(r$field_type)) "-" else r$field_type,
    if (is.na(r$choice_diff) || r$choice_diff == "") "-" else htmltools::htmlEscape(r$choice_diff),
    if (is.na(r$notes) || r$notes == "") "-" else htmltools::htmlEscape(r$notes)
  ))
}
full_html <- paste0(full_html, '</tbody></table>\n')

# Filter JS
full_html <- paste0(full_html, '
<script>
function filterTable() {
  var search = document.getElementById("searchInput").value.toLowerCase();
  var category = document.getElementById("categoryFilter").value;
  var riskOnly = document.getElementById("riskOnly").checked;
  var rows = document.querySelectorAll("#auditTable tbody tr");
  rows.forEach(function(row) {
    var text = row.textContent.toLowerCase();
    var cat = row.getAttribute("data-category");
    var risk = row.getAttribute("data-risk");
    var show = true;
    if (search && text.indexOf(search) === -1) show = false;
    if (category && cat !== category) show = false;
    if (riskOnly && risk !== "true") show = false;
    row.style.display = show ? "" : "none";
  });
}
</script>
')
html_parts$full_table <- full_html

# --- Assemble HTML ---
final_html <- paste0(
  '<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="UTF-8">\n<title>MN26 vs NE25 Reconciliation Audit</title>\n',
  html_parts$css,
  '\n</head>\n<body>\n',
  html_parts$header,
  html_parts$summary,
  if (!is.null(html_parts$high_risk)) html_parts$high_risk else "",
  html_parts$instruments,
  html_parts$full_table,
  '\n</body>\n</html>'
)

writeLines(final_html, output_html)
cat("  Saved: ", output_html, "\n")

# ==============================================================================
# DONE
# ==============================================================================
cat("\n========================================\n")
cat("Reconciliation audit complete!\n")
cat("========================================\n")
cat("\nOutputs:\n")
cat("  HTML report:  ", output_html, "\n")
cat("  Field mapping: ", output_csv, "\n")
cat("  MN26 dict (full):   ", mn26_dict_full_path, "\n")
cat("  MN26 dict (active): ", mn26_dict_active_path, "\n")
cat("\nNext step: Review the HTML report together before proceeding to Phase 2.\n")

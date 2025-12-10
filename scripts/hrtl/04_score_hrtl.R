################################################################################
# Test HRTL On-Track Percentages by Domain
################################################################################

library(dplyr)
library(readxl)

message("=== Testing HRTL On-Track Percentages ===\n")

# ==============================================================================
# 1. LOAD DATA
# ==============================================================================
message("1. Loading data...")

imputed_datasets <- readRDS("scripts/hrtl/hrtl_data_imputed_allages.rds")
domain_datasets <- readRDS("scripts/hrtl/hrtl_domain_datasets.rds")
thresholds <- readRDS("scripts/hrtl/hrtl_thresholds.rds")
itemdict_csv <- readRDS("scripts/hrtl/hrtl_itemdict_csv.rds")
ne25_cahmi_map <- readRDS("scripts/hrtl/hrtl_ne25_cahmi_map.rds")

message(sprintf("  Loaded %d domains with imputed data\n", length(imputed_datasets)))

# ==============================================================================
# 2. SCORE EACH DOMAIN
# ==============================================================================

domains <- names(imputed_datasets)
domain_results <- list()

for (domain in domains) {
  message(sprintf("\nDomain: %s", domain))
  message(strrep("-", 70))

  # Get data
  domain_data <- domain_datasets[[domain]]$data
  imputed_items <- as.data.frame(imputed_datasets[[domain]])  # Just item matrix
  item_vars <- domain_datasets[[domain]]$variables
  cahmi_codes <- domain_datasets[[domain]]$cahmi_codes

  # Ensure imputed_items has same column names as item_vars
  colnames(imputed_items) <- item_vars

  # Get NE25 to CAHMI mappings for this domain
  ne25_to_cahmi <- ne25_cahmi_map %>%
    dplyr::filter(ne25 %in% item_vars) %>%
    dplyr::select(ne25, cahmi22) %>%
    dplyr::distinct()

  # Manually add DailyAct_22 mapping (derived variable not in codebook)
  if ("dailyact_22" %in% item_vars) {
    ne25_to_cahmi <- rbind(
      ne25_to_cahmi,
      data.frame(ne25 = "dailyact_22", cahmi22 = "DailyAct", stringsAsFactors = FALSE)
    )
  }

  # Filter to HRTL-eligible ages (3-5 years, floor age)
  hrtl_ages <- floor(domain_data$years_old) %in% c(3, 4, 5)
  domain_data_hrtl <- domain_data[hrtl_ages, ]
  imputed_items_hrtl <- imputed_items[hrtl_ages, ]

  message(sprintf("  Items: %d", length(item_vars)))
  message(sprintf("  Sample: %d children total, %d HRTL-eligible (ages 3-5)",
                  nrow(domain_data), nrow(domain_data_hrtl)))

  # Code each item on 1-3 scale based on CAHMI thresholds
  coded_data <- domain_data_hrtl %>%
    dplyr::select(pid, record_id, years_old)

  for (ne25_var in item_vars) {
    # Get CAHMI code for this NE25 variable
    cahmi_row <- ne25_to_cahmi %>% dplyr::filter(ne25 == ne25_var)

    if (nrow(cahmi_row) == 0) {
      message(sprintf("    [WARN] No CAHMI mapping for %s", ne25_var))
      next
    }

    cahmi_code <- cahmi_row$cahmi22[1]

    # Get age-specific thresholds for this item
    # Strip "_22" suffix AND underscores from threshold var_cahmi for matching
    # (e.g., "CountToR_22" → "COUNTTORSTR", "COUNTTO_R" → "COUNTTORSTR")
    item_thresholds <- thresholds %>%
      dplyr::mutate(
        var_cahmi_clean = gsub("_", "", toupper(gsub("_\\d+$", "", var_cahmi)))
      ) %>%
      dplyr::filter(var_cahmi_clean == gsub("_", "", toupper(cahmi_code))) %>%
      dplyr::select(-var_cahmi_clean)

    if (nrow(item_thresholds) == 0) {
      message(sprintf("    [WARN] No thresholds for %s (%s)", ne25_var, cahmi_code))
      next
    }

    # Get item values from imputed data (HRTL-eligible only)
    item_values <- imputed_items_hrtl[[ne25_var]]

    # Initialize coded column
    coded_col <- rep(NA_real_, nrow(domain_data_hrtl))

    # Code for each age group
    for (age in unique(item_thresholds$SC_AGE_YEARS)) {
      # Match children with floor(years_old) == age (e.g., 3.5 years → age 3)
      age_mask <- floor(domain_data_hrtl$years_old) == age

      if (sum(age_mask, na.rm = TRUE) == 0) next

      age_thresholds <- item_thresholds %>%
        dplyr::filter(SC_AGE_YEARS == age)

      if (nrow(age_thresholds) == 0) next

      on_track_threshold <- age_thresholds$on_track[1]
      emerging_threshold <- age_thresholds$emerging[1]

      # Apply coding logic
      coded_col[age_mask] <- 1  # Default: Needs Support
      coded_col[age_mask & item_values >= emerging_threshold] <- 2  # Emerging
      coded_col[age_mask & item_values >= on_track_threshold] <- 3  # On-Track
    }

    coded_data[[ne25_var]] <- coded_col
  }

  # Calculate domain average (exclude pid, record_id, years_old)
  item_cols <- setdiff(names(coded_data), c("pid", "record_id", "years_old"))
  coded_data$avg_score <- rowMeans(coded_data[, item_cols], na.rm = TRUE)

  # Classify domain status
  coded_data <- coded_data %>%
    dplyr::mutate(
      status = dplyr::case_when(
        avg_score < 2.0 ~ "Needs Support",
        avg_score >= 2.0 & avg_score < 2.5 ~ "Emerging",
        avg_score >= 2.5 ~ "On-Track",
        TRUE ~ NA_character_
      )
    )

  # Calculate percentages
  status_counts <- coded_data %>%
    dplyr::count(status) %>%
    dplyr::mutate(pct = 100 * n / sum(n))

  message(sprintf("  Status distribution:"))
  for (i in 1:nrow(status_counts)) {
    message(sprintf("    %s: %d (%.1f%%)",
                    status_counts$status[i],
                    status_counts$n[i],
                    status_counts$pct[i]))
  }

  on_track_pct <- status_counts %>%
    dplyr::filter(status == "On-Track") %>%
    dplyr::pull(pct)

  if (length(on_track_pct) == 0) on_track_pct <- 0

  domain_results[[domain]] <- list(
    on_track_pct = on_track_pct,
    status_counts = status_counts,
    coded_data = coded_data
  )
}

# ==============================================================================
# 3. CALCULATE OVERALL HRTL
# ==============================================================================

message("\n\n", strrep("=", 70))
message("CALCULATING OVERALL HRTL")
message(strrep("=", 70), "\n")

# Get all children who appear in all 5 domains (complete HRTL assessment)
# Use the domain with most restrictive sample (Motor Development at 1,412)
all_children_ids <- domain_results[["Motor Development"]]$coded_data %>%
  dplyr::select(pid, record_id)

# Create wide format with domain status for each child
hrtl_data <- all_children_ids

for (domain in names(domain_results)) {
  domain_status <- domain_results[[domain]]$coded_data %>%
    dplyr::select(pid, record_id, status)

  colnames(domain_status)[3] <- paste0("status_", gsub(" ", "_", domain))

  hrtl_data <- hrtl_data %>%
    dplyr::left_join(domain_status, by = c("pid", "record_id"))
}

# Count domains on-track and needs-support per child
hrtl_data <- hrtl_data %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    n_on_track = sum(dplyr::c_across(starts_with("status_")) == "On-Track", na.rm = TRUE),
    n_needs_support = sum(dplyr::c_across(starts_with("status_")) == "Needs Support", na.rm = TRUE)
  ) %>%
  dplyr::ungroup()

# HRTL criteria: ≥4 domains on-track AND 0 domains needs support
hrtl_data <- hrtl_data %>%
  dplyr::mutate(
    hrtl = (n_on_track >= 4 & n_needs_support == 0)
  )

# Calculate overall HRTL percentage
hrtl_count <- sum(hrtl_data$hrtl, na.rm = TRUE)
total_count <- nrow(hrtl_data)
hrtl_pct <- 100 * hrtl_count / total_count

message(sprintf("Total children assessed: %d", total_count))
message(sprintf("Children meeting HRTL criteria: %d (%.1f%%)", hrtl_count, hrtl_pct))
message(sprintf("\nHRTL Criteria: ≥4 domains on-track AND 0 domains needs support"))

# Distribution of on-track domains
on_track_dist <- hrtl_data %>%
  dplyr::count(n_on_track) %>%
  dplyr::mutate(pct = 100 * n / sum(n))

message("\nDistribution of on-track domains:")
for (i in 1:nrow(on_track_dist)) {
  message(sprintf("  %d domains on-track: %d children (%.1f%%)",
                  on_track_dist$n_on_track[i],
                  on_track_dist$n[i],
                  on_track_dist$pct[i]))
}

# ==============================================================================
# 4. SUMMARY
# ==============================================================================

message("\n\n", strrep("=", 70))
message("SUMMARY: ON-TRACK PERCENTAGES BY DOMAIN")
message(strrep("=", 70), "\n")

for (domain in names(domain_results)) {
  pct <- domain_results[[domain]]$on_track_pct
  message(sprintf("  %s: %.1f%%", domain, pct))
}

message("\n", strrep("=", 70))
message(sprintf("OVERALL HRTL: %.1f%% (≥4 on-track, 0 needs support)", hrtl_pct))
message(strrep("=", 70))

message("\nTest complete - Ready to implement production scoring function")

################################################################################
# Phase 2b: Fit Rasch Models and Create EAP Conversion Tables
################################################################################

library(dplyr)
library(mirt)
library(readxl)

message("=== Phase 2b: Fitting Rasch Models & Creating EAP Conversions ===\n")

# Load domain datasets
domain_datasets <- readRDS("scripts/temp/hrtl_domain_datasets.rds")
thresholds <- readRDS("scripts/temp/hrtl_thresholds.rds")
itemdict_csv <- readRDS("scripts/temp/hrtl_itemdict_csv.rds")
ne25_cahmi_map <- readRDS("scripts/temp/hrtl_ne25_cahmi_map.rds")

rasch_models <- list()
conversion_tables <- list()
model_diagnostics <- list()

domains <- names(domain_datasets)

for (domain in domains) {
  message(sprintf("\n%s", strrep("=", 70)))
  message(sprintf("Domain: %s", domain))
  message(sprintf("%s\n", strrep("=", 70)))
  
  domain_data <- domain_datasets[[domain]]$data %>% 
    dplyr::mutate(across(kidsights_2022:general_gsed_pf_2022, function(x)scale(x)))
  item_vars <- domain_datasets[[domain]]$variables
  
  message(sprintf("Fitting Rasch model with %d items, %d children\n", 
                  length(item_vars), nrow(domain_data)))
  
  # ==============================================================================
  # 1. PREPARE DATA FOR MIRT
  # ==============================================================================
  
  # Extract item columns as numeric matrix
  item_matrix <- as.matrix(domain_data[, item_vars])
  
  # Check data type and range
  message(sprintf("Item data summary:"))
  message(sprintf("  Dimensions: %d children x %d items", nrow(item_matrix), ncol(item_matrix)))
  message(sprintf("  Range: [%.1f, %.1f]", min(item_matrix, na.rm=TRUE), 
                                            max(item_matrix, na.rm=TRUE)))
  
  n_missing <- sum(is.na(item_matrix))
  pct_missing <- 100 * n_missing / (nrow(item_matrix) * ncol(item_matrix))
  message(sprintf("  Missing data: %d (%.2f%%)\n", n_missing, pct_missing))
  
  # ==============================================================================
  # 2. FIT RASCH MODEL
  # ==============================================================================
  
  message("Fitting Rasch model (1PL IRT)...")
  
  tryCatch({
    # Create constraint for equal slopes across all items
    pars <- mirt(item_matrix, 1, itemtype = 'graded', pars = 'values')
    slopes <- pars[pars$name == 'a1', 'parnum']
    rasch_fit <- mirt(
      data = item_matrix,
      model = 1,
      itemtype = 'graded',
      covdata = domain_data %>% dplyr::select(kidsights_2022, general_gsed_pf_2022),
      formula = ~ kidsights_2022 + general_gsed_pf_2022,
      constrain = list(slopes)
    )
    message("  Model fitted successfully\n")
    
    # ==============================================================================
    # 3. GET MODEL DIAGNOSTICS
    # ==============================================================================
    
    message("Extracting model diagnostics...")
    
    # Extract item parameters
    item_params <- coef(rasch_fit, simplify = TRUE)$items
    #message(sprintf("  Item difficulty (d) range: [%.2f, %.2f]", 
    #                min(item_params[, 'd']), max(item_params[, 'd'])))
    
    # Calculate EAP scores for all respondents
    eap_scores <- fscores(rasch_fit, method = "EAP", full.scores = TRUE,full.scores.SE = T) 
    colnames(eap_scores) <- c("theta", "se")
    
    message(sprintf("  EAP theta range: [%.2f, %.2f]", min(eap_scores[, 1]), max(eap_scores[, 1])))
    message(sprintf("  EAP SEM range: [%.2f, %.2f]\n", min(eap_scores[, 2]), max(eap_scores[, 2])))
    
    # ==============================================================================
    # 4. CREATE EAP-TO-EXPECTED-SUM CONVERSION TABLE
    # ==============================================================================
    
    message("Creating EAP to expected sum score conversion table...")
    
    # Generate theta range
    theta_range <- sort(unique(eap_scores))
    expected_sums <- expected.test(rasch_fit, Theta = matrix(theta_range)) %>% round(0)
    
    conversion_table <- data.frame(
      theta = theta_range,
      expected_sum = as.numeric(expected_sums),
      stringsAsFactors = FALSE
    )
    
    message(sprintf("  Theta range: [%.2f, %.2f]", min(theta_range), max(theta_range)))
    message(sprintf("  Expected sum range: [%.2f, %.2f]", 
                    min(conversion_table$expected_sum), 
                    max(conversion_table$expected_sum)))
    
    # ==============================================================================
    # 5. STORE CAHMI THRESHOLDS FOR SCORING (RAW, UNPROJECTED)
    # ==============================================================================

    message("\nLoading CAHMI thresholds for scoring...")

    # Get CAHMI codes for this domain (already stored from Phase 2a)
    cahmi_codes <- domain_datasets[[domain]]$cahmi_codes

    message(sprintf("  Domain CAHMI codes (%d items): %s",
                    length(cahmi_codes),
                    paste(head(cahmi_codes, 3), collapse=", ")))

    # Get CAHMI thresholds for this domain (for all ages)
    # The thresholds var_cahmi column has format "RecogBegin_22", "SameSound_22", etc.
    # Need to strip the "_22" suffix and match case-insensitively with CAHMI codes
    domain_thresholds <- thresholds %>%
      dplyr::mutate(var_cahmi_clean = toupper(gsub("_\\d+$", "", var_cahmi))) %>%
      dplyr::filter(var_cahmi_clean %in% toupper(cahmi_codes)) %>%
      dplyr::select(-var_cahmi_clean)

    message(sprintf("  Found %d age-specific threshold rows", nrow(domain_thresholds)))
    message(sprintf("    on_track range: [%.1f, %.1f]",
                    min(domain_thresholds$on_track, na.rm=TRUE),
                    max(domain_thresholds$on_track, na.rm=TRUE)))
    message(sprintf("    emerging range: [%.1f, %.1f]\n",
                    min(domain_thresholds$emerging, na.rm=TRUE),
                    max(domain_thresholds$emerging, na.rm=TRUE)))
    
    # ==============================================================================
    # 6. SAVE RESULTS
    # ==============================================================================
    
    rasch_models[[domain]] <- rasch_fit

    conversion_tables[[domain]] <- list(
      theta_to_sum = conversion_table,
      cahmi_thresholds = domain_thresholds,
      eap_scores = eap_scores
    )
    
    model_diagnostics[[domain]] <- list(
      n_children = nrow(item_matrix),
      n_items = ncol(item_matrix),
      pct_missing = pct_missing,
      item_difficulty = item_params[, 'd'],
      theta_range = range(eap_scores[, 1]),
      theta_mean = mean(eap_scores[, 1], na.rm=TRUE),
      theta_sd = sd(eap_scores[, 1], na.rm=TRUE)
    )
    
    message(sprintf("Domain %s: COMPLETE\n", domain))
    
  }, error = function(e) {
    message(sprintf("ERROR fitting Rasch model for %s:", domain))
    message(sprintf("  %s\n", e$message))
  })
}

# ==============================================================================
# SAVE ALL RESULTS
# ==============================================================================

message("\n", strrep("=", 70))
message("SAVING PHASE 2B RESULTS")
message(strrep("=", 70), "\n")

saveRDS(rasch_models, "scripts/temp/hrtl_rasch_models.rds")
saveRDS(conversion_tables, "scripts/temp/hrtl_conversion_tables.rds")
saveRDS(model_diagnostics, "scripts/temp/hrtl_model_diagnostics.rds")

message("Saved:")
message("  - rasch_models: Full mirt Rasch models for each domain")
message("  - conversion_tables: EAP <-> sum score mappings")
message("  - model_diagnostics: Fit statistics and EAP distributions")

message("\nDomains with successful Rasch fits:", length(rasch_models))
for (domain in names(rasch_models)) {
  diag <- model_diagnostics[[domain]]
  message(sprintf("  [OK] %s: theta=%+.2f(SD=%.2f)", domain, diag$theta_mean, diag$theta_sd))
}

message("\nPhase 2b complete - Ready for production HRTL scoring functions")


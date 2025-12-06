################################################################################
# Person-Level Influence Analysis for Latent Factor Scores
################################################################################
# Purpose: Identify influential observations in multivariate regression models
#          predicting latent developmental (f_dev) and psychosocial (f_psych)
#          factor scores from demographic and clinical covariates.
#
# Methods:
#   1. Exclude high-influence persons identified from prior Mplus analysis
#   2. Impute missing person-level covariates using CART
#   3. Engineer demographic/clinical predictors and age interactions
#   4. Extract Mplus Model 1f factor scores (f_dev, f_psych)
#   5. Fit multivariate regression: cbind(f_dev, f_psych) ~ covariates
#   6. Compute Cook's distance for both outcomes
#   7. Create composite influence score via PCA
#
# Historical Notes:
#   - Items EG39a, EG41_2, EG30d, EG30e, AA56, EG44_2 had improper reverse coding
#     (fixed in codebook.json)
#   - Persons 7943/746 and 7999/1171 identified as high-influence outliers
#     (overall_influence > 5.5) and excluded from analysis
################################################################################

rm(list = ls())

library(tidyverse)
library(MplusAutomation)
library(mice)

# Load Stage 1 data and safe join utilities
source("scripts/authenticity_screening/manual_screening/00_load_item_response_data.R")
source("R/utils/safe_joins.R")

################################################################################
# STEP 1: Load Stage 1 Data
################################################################################

out_list_00 <- load_stage1_data()
wide_dat <- out_list_00$wide_data          # Item responses (269 items)
person_dat <- out_list_00$person_data      # Person-level covariates
item_metadata <- out_list_00$item_metadata # Item metadata

################################################################################
# STEP 2: Filter High-Influence Persons and Impute Missing Covariates
################################################################################

# Exclude 2 high-influence persons identified from prior Mplus Model 1f analysis
# These persons had overall_influence > 5.5 (extreme outliers in latent space)
person_dat_imp <- person_dat %>%
  dplyr::mutate(
    # Create exclusion flag for high-influence persons
    flag = ifelse(pid == 7943 & recordid == 746, FALSE, TRUE),
    flag = ifelse(pid == 7999 & recordid == 1171, FALSE, flag)
  ) %>%
  dplyr::filter(flag) %>%  # Remove flagged persons
  # Impute missing values using CART (Classification and Regression Trees)
  # m=1: Single imputation (not multiple imputation)
  # maxit=20: 20 iterations for convergence
  mice::mice(method = "cart", m = 1, maxit = 5, remove.collinear = FALSE, seet.seed = 42) %>%
  mice::complete(1)  # Extract first (only) imputed dataset

################################################################################
# STEP 3: Engineer Demographic and Clinical Predictors
################################################################################

person_dat_imp <- person_dat_imp %>%
  dplyr::mutate(
    # --- Binary demographic indicators ---
    # College education: Bachelor's degree or higher
    college = as.integer(educ_a1 %in% c(
      "Bachelor's Degree (BA, BS, AB)",
      "Master's Degree (MA, MS, MSW, MBA)",
      "Doctorate (PhD, EdD) or Professional Degree (MD, DDS, DVM, JD)"
    )),
    nohs = as.integer(educ_a1 %in% c(
      "8th grade or less", 
      "9th-12th grade, No diploma"
    )), 
    school = dplyr::case_when(
      educ_a1 == "8th grade or less" ~ 8, 
      educ_a1 == "9th-12th grade, No diploma" ~ 10, 
      educ_a1 == "High School Graduate or GED Completed" ~ 12,
      educ_a1 == "Completed a vocational, trade, or business school program" ~ 12,
      educ_a1 == "Some College Credit, but No Degree" ~ 13, 
      educ_a1 == "Associate Degree (AA, AS)" ~14, 
      educ_a1 == "Bachelor's Degree (BA, BS, AB)" ~16, 
      educ_a1 == "Master's Degree (MA, MS, MSW, MBA)" ~ 18, 
      educ_a1 == "Doctorate (PhD, EdD) or Professional Degree (MD, DDS, DVM, JD)" ~ 20
    ),
    # Federal poverty line
    logfpl = log(fpl+100),
    # Race; 
    hisp = as.integer(raceG == "Hispanic"),
    black = as.integer(raceG == "Black or African American, non-Hisp."), 
    other = as.integer(raceG!= "White, non-Hisp." & black==0 & hisp == 0), 
    # --- PHQ-2 depression screening indicators ---
    # No depression symptoms: PHQ-2 total = 0
    phq2 = phq2_total,
  ) %>%
  dplyr::mutate(
    # --- Age-related predictors ---
    female = as.integer(female),          # Convert logical to 0/1
    logyrs = log(years + 1),              # Logarithmic age scaling
    yrs3 = (years - 3),                   # Age centered at 3 years
    femXyrs3 = female * (years - 3)       # Gender × age interaction
  ) %>%
  dplyr::select(
    # Identifiers
    pid,
    recordid,
    # Main effects
    female,
    logyrs,
    yrs3,
    # Moderators for age interactions
    college,
    nohs,
    school,
    logfpl,
    phq2, 
    black,
    hisp,
    other
  ) %>% 
  dplyr::mutate(
    school = scale(school), 
    logfpl = scale(logfpl), 
    phq2 = scale(phq2)
  )


################################################################################
# STEP 4: Extract Mplus Model 1f Factor Scores
################################################################################

# Read Mplus Model 1f output (bifactor model: f_dev, f_psych)
# Model 1f is the final calibrated two-factor model with:
#   - f_dev: Developmental factor (cognitive, language, motor, social-emotional)
#   - f_psych: Psychosocial problems factor (internalizing, externalizing)
out_list_1f_full <- MplusAutomation::readModels(
  target = file.path("scripts/authenticity_screening/manual_screening", "mplus/model_1a"),
  filefilter = "model_1f"  # Filter to Model 1f outputs only
)

# Extract factor scores from savedata (Mplus exports in uppercase)
fscores_1f_full <- out_list_1f_full$savedata %>%
  dplyr::rename_all(tolower)  # Convert to lowercase for consistency

################################################################################
# STEP 5: Merge Factor Scores with Person-Level Covariates
################################################################################

# Use safe_left_join to prevent column collisions
person_dat_imp <- person_dat_imp %>%
  safe_left_join(
    fscores_1f_full %>% dplyr::select(pid, recordid, f_dev, f_psych),
    by_vars = c("pid", "recordid")
  ) %>%
  na.omit()  # Remove any cases with missing factor scores

# Let's look at marginal effects
lm(cbind(f_dev, f_psych) ~ logyrs + female*yrs3 + black*yrs3 + hisp*yrs3 + other*yrs3 + school*yrs3 + logfpl*yrs3 + phq2*yrs3, data = person_dat_imp) %>% 
  summary()





################################################################################
# STEP 6: Person-Level Cutoff Optimization via LOOCV (Serial)
################################################################################

# Load the optimize_person_cutoff_serial function
source("R/authenticity_screening/optimize_person_cutoff.R")
source("R/authenticity_screening/optimize_person_cutoff_1d.R")
source("R/authenticity_screening/plot_coefficient_stability.R")
source("R/authenticity_screening/plot_coefficient_stability_1d.R")


# Set up parallel cluster
cl <- parallel::makeCluster(4)


# Run serial cutoff optimization
out_list <- optimize_person_cutoff(
  person_data = person_dat_imp, 
  #outcome_var = c("f_dev", "f_psych"),
  formula_rhs = "logyrs + female*yrs3 + hisp*yrs3 + black*yrs3 + other*yrs3 + school*yrs3 + logfpl*yrs3 + phq2*yrs3 + as.factor(pid)*yrs3",
  target_params = c("school", "yrs3:school","logfpl", "yrs3:logfpl","phq2", "yrs3:phq2"),  # Changed order,
  max_k = 100,
  verbose = TRUE, 
  cl = cl, 
  iterative_influence = TRUE
)

# Stop cluster after this k iteration
parallel::stopCluster(cl)

write_rds(out_list, file = file.path("scripts/authenticity_screening/manual_screening/loocv_optimize_person_cutoff_iterative_dfbeta.rds"))


# Create plots

# Define custom panel groups for your variables
custom_groups <- list(
  top_left = c("female", "yrs3:female"),
  top_right = c("school", "yrs3:school"),
  bottom_left = c("logfpl", "yrs3:logfpl"),
  bottom_right = c("phq2", "yrs3:phq2")
)

# Define custom panel titles
custom_labels <- c(
  "Female × Age",
  "Education × Age",
  "Income (log FPL) × Age",
  "Depression (PHQ-2) × Age"
)

# Create plots
plots <- plot_coefficient_stability(
  out_list$coefficient_results,
  panel_groups = custom_groups,
  panel_labels = custom_labels
)

plots <- plot_coefficient_stability(out_list$coefficient_results)

# View
print(plots$plot_f_dev)
print(plots$plot_f_psych)

ggplot(out_list$cutoff_results, aes(x = k, y = overall_influence_cutoff )) + geom_point()

out_list$cutoff_results %>% dplyr::slice(1:3)



k_to_remove = 2

to_remove = out_list$cutoff_results %>% 
  dplyr::filter(k %in% seq(1,k_to_remove)) %>% 
  dplyr::select(pid = removed_pid, record_id = removed_record_id) %>% 
  dplyr::mutate(id = paste0(pid,"_", record_id))


person_dat_imp = person_dat_imp %>% 
  dplyr::mutate(flag = paste0(pid,"_", recordid) %in% to_remove$id)

lm(cbind(f_dev, f_psych) ~ logyrs + female*yrs3 + black*yrs3 + hisp*yrs3 + other*yrs3 + school*yrs3 + logfpl*yrs3 + phq2*yrs3, 
   data = person_dat_imp %>% dplyr::filter(!flag)) %>% 
  summary()


lm(cbind(f_dev, f_psych) ~ logyrs + female*yrs3 + black*yrs3 + hisp*yrs3 + other*yrs3 + school*yrs3, 
   data = person_dat_imp %>% dplyr::filter(!flag)) %>% 
  summary()

lm(cbind(f_dev, f_psych) ~ logyrs + female*yrs3 + black*yrs3 + hisp*yrs3 + other*yrs3 + logfpl*yrs3, 
   data = person_dat_imp %>% dplyr::filter(!flag)) %>% 
  summary()



lm(cbind(f_dev, f_psych) ~ logyrs + female*yrs3 + black*yrs3 + hisp*yrs3 + other*yrs3 + phq2*yrs3, 
   data = person_dat_imp %>% dplyr::filter(!flag)) %>% 
  summary()



# So final
ne25_flagged_observations = person_dat %>%
  dplyr::mutate(
    # Create exclusion flag for high-influence persons
    flag = ifelse(pid == 7943 & recordid == 746, "Remove due to poor person fit", NA),
    flag = ifelse(pid == 7999 & recordid == 1171, "Remove due to poor person fit", flag), 
    flag = ifelse(paste0(pid,"_", recordid) %in% to_remove$id, "Remove due to high latent regression influence", flag), 
  ) %>% 
  dplyr::filter(!is.na(flag)) %>% 
  dplyr::select(pid,recordid,flag)



# Load required packages
library(duckdb)
library(DBI)

# Connect to the DuckDB database
db_path <- "data/duckdb/kidsights_local.duckdb"
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)

# Write the data frame to the database
# This will overwrite if table already exists
DBI::dbWriteTable(
  conn = con,
  name = "ne25_flagged_observations",
  value = ne25_flagged_observations,
  overwrite = TRUE
)

# Verify the table was created
cat(sprintf("Table created with %d rows\n", DBI::dbGetQuery(con, "SELECT COUNT(*) FROM
  ne25_flagged_observations")[[1]]))

# Preview the first few rows
cat("\nFirst 5 rows:\n")
print(DBI::dbGetQuery(con, "SELECT * FROM ne25_flagged_observations LIMIT 5"))

# Disconnect
DBI::dbDisconnect(con, shutdown = TRUE)





### 



# Save RDS file with timestamp for versioning
output_dir = "output/ne25/authenticity_screening/manual_screening"
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
rds_path <- file.path(output_dir, sprintf("ne25_flagged_observations_%s.rds", timestamp))
saveRDS(ne25_flagged_observations, rds_path)

cat(sprintf("[OK] RDS backup saved: %s\n", rds_path))

# Also save a "latest" version for easy access
latest_path <- file.path(output_dir, "ne25_flagged_observations_latest.rds")
saveRDS(ne25_flagged_observations, latest_path)

cat(sprintf("[OK] Latest version saved: %s\n", latest_path))

# 
# person_cutoff_results = out_list$cutoff_results
# 
# # Identify optimal k (MAXIMUM log-likelihood)
# # Higher log-likelihood = better fit to held-out data
# optimal_k <- person_cutoff_results %>%
#   dplyr::filter(mean_log_lik == max(mean_log_lik, na.rm = TRUE)) %>%
#   dplyr::slice(1) %>%
#   dplyr::pull(k)
# 
# # Sort by influence for removal
# person_dat_sorted <- person_dat_with_influence %>%
#   dplyr::arrange(dplyr::desc(overall_influence))
# 
# optimal_cutoff <- person_cutoff_results %>%
#   dplyr::filter(k == optimal_k) %>%
#   dplyr::pull(overall_influence_cutoff)
# 
# cat("\n=== OPTIMAL CUTOFF ===\n")
# cat(sprintf("Optimal k: %d persons removed\n", optimal_k))
# cat(sprintf("Overall influence cutoff: %.4f\n", optimal_cutoff))
# cat(sprintf("Mean log-likelihood: %.4f\n",
#             person_cutoff_results$mean_log_lik[person_cutoff_results$k == optimal_k]))
# cat(sprintf("Persons remaining: %d\n\n",
#             person_cutoff_results$n_persons_remaining[person_cutoff_results$k == optimal_k]))
# 
# # Visualize optimization results
# library(ggplot2)
# 
# p1 <- ggplot2::ggplot(person_cutoff_results, ggplot2::aes(x = k, y = mean_log_lik)) +
#   ggplot2::geom_line(color = "steelblue", size = 1) +
#   ggplot2::geom_point(size = 2, color = "steelblue") +
#   ggplot2::geom_vline(xintercept = optimal_k, linetype = "dashed", color = "red") +
#   ggplot2::annotate("text", x = optimal_k, y = max(person_cutoff_results$mean_log_lik),
#                     label = sprintf("Optimal k = %d", optimal_k),
#                     hjust = -0.1, color = "red") +
#   ggplot2::labs(
#     title = "Person-Level Cutoff Optimization (LOOCV)",
#     subtitle = "Bivariate normal log-likelihood: cbind(f_dev, f_psych) ~ covariates",
#     x = "Number of high-influence persons removed (k)",
#     y = "Mean log-likelihood (out-of-sample)",
#     caption = "Higher log-likelihood = better predictive performance"
#   ) +
#   ggplot2::theme_minimal() +
#   ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))
# 
# print(p1)
# 
# # Marginal improvement plot
# person_cutoff_marginal <- person_cutoff_results %>%
#   dplyr::mutate(
#     marginal_improvement = mean_log_lik - dplyr::lag(mean_log_lik),
#     cumulative_improvement = mean_log_lik - mean_log_lik[1]
#   )
# 
# p2 <- ggplot2::ggplot(person_cutoff_marginal, ggplot2::aes(x = k, y = marginal_improvement)) +
#   ggplot2::geom_col(fill = "steelblue", alpha = 0.7) +
#   ggplot2::geom_hline(yintercept = 0, linetype = "dashed") +
#   ggplot2::labs(
#     title = "Marginal Improvement from Each Additional Removal",
#     x = "Number of persons removed (k)",
#     y = "Marginal change in log-likelihood"
#   ) +
#   ggplot2::theme_minimal()
# 
# print(p2)
# 
# # Cumulative improvement plot
# p3 <- ggplot2::ggplot(person_cutoff_marginal %>% dplyr::filter(k > 0),
#                       ggplot2::aes(x = k, y = cumulative_improvement)) +
#   ggplot2::geom_line(color = "darkgreen", size = 1) +
#   ggplot2::geom_point(size = 2, color = "darkgreen") +
#   ggplot2::geom_hline(yintercept = 0, linetype = "dashed") +
#   ggplot2::labs(
#     title = "Cumulative Improvement from Baseline (k=0)",
#     x = "Number of persons removed (k)",
#     y = "Cumulative change in log-likelihood"
#   ) +
#   ggplot2::theme_minimal()
# 
# print(p3)
# 
# # Use optimal cutoff for final analysis
# person_dat_final <- person_dat_sorted %>%
#   dplyr::filter(overall_influence <= optimal_cutoff)
# 
# cat(sprintf("\n[OK] Final dataset: %d persons after removing k=%d high-influence cases\n\n",
#             nrow(person_dat_final), optimal_k))
# 
# ################################################################################
# # STEP 7: Fit Final Multivariate Regression Model (Post-Filtering)
# ################################################################################
# 
# # Fit model on filtered dataset (after removing optimal k persons)
# #
# # Model specification:
# #   cbind(f_dev, f_psych) ~ logyrs + yrs3 + femXyrs3 +
# #                           college*yrs3 + fpl*yrs3 + nophq2*yrs3 + mdd*yrs3
# #
# # Main effects:
# #   - logyrs: Logarithmic age trend (non-linear growth)
# #   - yrs3: Linear age trend (centered at 3 years)
# #   - femXyrs3: Gender × age interaction
# #
# # Interaction terms (covariate × yrs3):
# #   - college*yrs3: Does developmental slope differ by parental education?
# #   - fpl*yrs3: Does developmental slope differ by income?
# #   - nophq2*yrs3: Does developmental slope differ for no depression symptoms?
# #   - mdd*yrs3: Does developmental slope differ for positive depression screen?
# #
# # Total parameters: 13 (1 intercept + 3 main effects + 4 moderators + 4 interactions + 1 error correlation)
# 
# fit_final <- lm(
#   cbind(f_dev, f_psych) ~ logyrs + yrs3 + femXyrs3 +
#     college * yrs3 + fpl * yrs3 + nophq2 * yrs3 + mdd * yrs3,
#   data = person_dat_final
# )
# summary(fit_final)
# 
# # Compute Cook's distance threshold for final model
# # Rule of thumb: 4 / (n - p - 1) where n = sample size, p = number of predictors
# # Observations exceeding this threshold are considered influential
# thresh_final <- 4 / (nrow(person_dat_final) - 13 - 1)
# 
# cat(sprintf("\n=== FINAL MODEL DIAGNOSTICS ===\n"))
# cat(sprintf("Cook's D threshold: %.6f\n", thresh_final))
# cat(sprintf("Sample size: %d persons\n\n", nrow(person_dat_final)))
# 
# ################################################################################
# # STEP 8: Visualize Age Trends in Factor Scores (Post-Filtering)
# ################################################################################
# 
# # Plot f_dev vs. age (centered at 3 years) - AFTER removing high-influence persons
# # Expected pattern: Positive slope (development increases with age)
# ggplot2::ggplot(person_dat_final, ggplot2::aes(x = yrs3, y = f_dev)) +
#   ggplot2::geom_point(alpha = 0.2) +
#   ggplot2::geom_smooth() +
#   ggplot2::labs(
#     title = "Developmental Factor Score vs. Age (Post-Filtering)",
#     subtitle = sprintf("N = %d after removing k = %d high-influence persons",
#                        nrow(person_dat_final), optimal_k),
#     x = "Age (years, centered at 3)",
#     y = "f_dev (Developmental Factor)"
#   )
# 
# # Plot f_psych vs. age (centered at 3 years) - AFTER removing high-influence persons
# # Expected pattern: Varies by study; may be flat or slightly negative
# ggplot2::ggplot(person_dat_final, ggplot2::aes(x = yrs3, y = f_psych)) +
#   ggplot2::geom_point(alpha = 0.2) +
#   ggplot2::geom_smooth() +
#   ggplot2::labs(
#     title = "Psychosocial Problems Factor Score vs. Age (Post-Filtering)",
#     subtitle = sprintf("N = %d after removing k = %d high-influence persons",
#                        nrow(person_dat_final), optimal_k),
#     x = "Age (years, centered at 3)",
#     y = "f_psych (Psychosocial Problems Factor)"
#   )
# 
# ################################################################################
# # STEP 9: Final Influence Diagnostics (Post-Filtering)
# ################################################################################
# 
# # Compute Cook's distance on final filtered dataset
# # This shows residual influence after optimal cutoff applied
# person_dat_final <- person_dat_final %>%
#   dplyr::bind_cols(
#     cooks.distance(fit_final) %>%
#       data.frame() %>%
#       dplyr::rename(cooks_dev_final = f_dev, cooks_psych_final = f_psych)
#   )
# 
# # Visualize residual bivariate Cook's distance
# # Any remaining influential points after filtering?
# ggplot2::ggplot(person_dat_final, ggplot2::aes(x = cooks_dev_final, y = cooks_psych_final)) +
#   ggplot2::geom_point() +
#   ggplot2::geom_hline(yintercept = thresh_final, linetype = "dashed", color = "red") +
#   ggplot2::geom_vline(xintercept = thresh_final, linetype = "dashed", color = "red") +
#   ggplot2::labs(
#     title = "Bivariate Cook's Distance (Post-Filtering)",
#     subtitle = sprintf("Threshold = %.6f (4/(n-p-1) rule)", thresh_final),
#     x = "Cook's D (f_dev)",
#     y = "Cook's D (f_psych)"
#   )
# 
# # Count remaining influential observations
# n_influential_dev <- sum(person_dat_final$cooks_dev_final > thresh_final, na.rm = TRUE)
# n_influential_psych <- sum(person_dat_final$cooks_psych_final > thresh_final, na.rm = TRUE)
# n_influential_both <- sum(
#   person_dat_final$cooks_dev_final > thresh_final &
#     person_dat_final$cooks_psych_final > thresh_final,
#   na.rm = TRUE
# )
# 
# cat(sprintf("\n=== RESIDUAL INFLUENCE (POST-FILTERING) ===\n"))
# cat(sprintf("Influential for f_dev: %d persons (%.1f%%)\n",
#             n_influential_dev, 100 * n_influential_dev / nrow(person_dat_final)))
# cat(sprintf("Influential for f_psych: %d persons (%.1f%%)\n",
#             n_influential_psych, 100 * n_influential_psych / nrow(person_dat_final)))
# cat(sprintf("Influential for BOTH: %d persons (%.1f%%)\n\n",
#             n_influential_both, 100 * n_influential_both / nrow(person_dat_final)))
# 
# ################################################################################
# # OUTPUT: Final Datasets
# ################################################################################
# #
# # person_dat_sorted (Full dataset with influence scores):
# #   - All persons ranked by overall_influence
# #   - Columns: pid, recordid, covariates, f_dev, f_psych, cooks_dev, cooks_psych, overall_influence
# #
# # person_dat_final (Filtered dataset):
# #   - N = nrow(person_dat_final) after removing k = optimal_k high-influence persons
# #   - Columns: Same as person_dat_sorted + cooks_dev_final, cooks_psych_final
# #
# # person_cutoff_results (Optimization results):
# #   - k = 0 to max_k cutoff values tested
# #   - Columns: k, n_persons_remaining, mean_log_lik, sd_log_lik
# #
# # Next steps:
# #   1. Use person_dat_final for downstream IRT calibration
# #   2. Flag removed persons in Mplus dataset (optional)
# #   3. Re-run Model 1f with filtered dataset if needed
# #   4. Export person_cutoff_results for reproducibility
# #
# ################################################################################
# 
# # Export optimization results
# timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
# output_file <- file.path(
#   "scripts/authenticity_screening/manual_screening",
#   sprintf("person_cutoff_optimization_%s.csv", timestamp)
# )
# readr::write_csv(person_cutoff_results, output_file)
# 
# cat(sprintf("\n[OK] Cutoff optimization results exported to:\n     %s\n\n", output_file))
# 
# # Export list of removed persons
# removed_persons <- person_dat_sorted %>%
#   dplyr::slice(1:optimal_k) %>%
#   dplyr::select(pid, recordid, overall_influence, cooks_dev, cooks_psych)
# 
# output_file_removed <- file.path(
#   "scripts/authenticity_screening/manual_screening",
#   sprintf("removed_persons_%s.csv", timestamp)
# )
# readr::write_csv(removed_persons, output_file_removed)
# 
# cat(sprintf("[OK] Removed persons list exported to:\n     %s\n\n", output_file_removed))
# 
# 
# 
# #

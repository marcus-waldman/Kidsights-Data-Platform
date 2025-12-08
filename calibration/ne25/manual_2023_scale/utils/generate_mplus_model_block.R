# Generate Mplus MODEL block from mirt calibration parameters
# Purpose: Convert 2023 mirt calibration to Mplus fixed parameter syntax
# Output: MODEL block with fixed slopes/thresholds for anchor items + free parameters for new items

library(dplyr)
library(jsonlite)

# ==============================================================================
# 1. Define all items to be calibrated
# ==============================================================================

all_items <- c(
  # AA series (42 items)
  "AA4", "AA5", "AA6", "AA7", "AA9", "AA11", "AA12", "AA13", "AA14", "AA15",
  "AA17", "AA19", "AA20", "AA21", "AA24", "AA26", "AA27", "AA28", "AA29", "AA30",
  "AA31", "AA34", "AA36", "AA38", "AA41", "AA43", "AA46", "AA47", "AA49", "AA50",
  "AA54", "AA55", "AA56", "AA57", "AA60", "AA65", "AA68", "AA69", "AA71", "AA72",
  "AA102", "AA104",
  # AA new items (2 items)
  "AA203", "AA205",
  # BB series (2 items)
  "BB5", "BB6",
  # BB new items (1 item)
  "BB201",
  # CC series (62 items)
  "CC4", "CC5", "CC6", "CC8", "CC9", "CC10", "CC11", "CC12", "CC13", "CC14",
  "CC15", "CC16", "CC17", "CC18", "CC19", "CC20", "CC21", "CC25", "CC26", "CC27",
  "CC28", "CC29", "CC30", "CC31", "CC32", "CC33", "CC34", "CC35", "CC36", "CC37",
  "CC39", "CC40", "CC41", "CC42", "CC43", "CC45", "CC46", "CC48", "CC50", "CC51",
  "CC52", "CC53", "CC54", "CC56", "CC60", "CC61", "CC62", "CC64", "CC65", "CC66",
  "CC67", "CC68", "CC69", "CC71", "CC72", "CC74", "CC75", "CC76", "CC78", "CC79y",
  "CC80", "CC83", "CC84", "CC85", "CC87", "CC89",
  # DD series (5 items)
  "DD15", "DD19", "DD103", "DD205", "DD207", "DD221", "DD299",
  # EG series (99 items)
  "EG1_1", "EG1_2", "EG2_1", "EG3_1", "EG4a_1", "EG4b_2", "EG5a", "EG5b", "EG6_1", "EG6_2",
  "EG7_1", "EG7_2", "EG8_1", "EG8_2", "EG9a", "EG10a", "EG11_1", "EG12a", "EG13a", "EG14a",
  "EG14b", "EG15_1", "EG15_2", "EG16a_1", "EG16a_2", "EG16b", "EG16c", "EG17a", "EG17b", "EG18a",
  "EG18b", "EG19a_2", "EG19a_3", "EG19a_4", "EG20a", "EG20b_1", "EG20c", "EG20d", "EG20e_1", "EG20e_2",
  "EG21a", "EG21b", "EG22_1", "EG22_2", "EG23a", "EG23b", "EG24b", "EG25a", "EG25b", "EG26b",
  "EG27a", "EG27b_1", "EG28a", "EG28b", "EG28c", "EG29a", "EG29b", "EG29c", "EG30a", "EG30c",
  "EG30d", "EG30e", "EG30f", "EG31a_1", "EG31a_2", "EG31b", "EG32a", "EG32b", "EG33a", "EG33b",
  "EG34a", "EG34b", "EG35b", "EG36b", "EG37_1", "EG37_2", "EG38a", "EG38b", "EG38c", "EG39a",
  "EG39b", "EG40_1", "EG41_1", "EG41_2", "EG42a", "EG42c", "EG43a_1", "EG43a_2", "EG43b", "EG44_1",
  "EG44_2", "EG45_1", "EG45_2", "EG46a_1", "EG46a_2", "EG46b", "EG46c", "EG46d", "EG47a", "EG47b",
  "EG48_2", "EG49_1", "EG49_2", "EG50b"
)

cat("Target items for calibration:\n")
cat("  Total items:", length(all_items), "\n")
cat("  AA series:", sum(grepl("^AA", all_items)), "\n")
cat("  BB series:", sum(grepl("^BB", all_items)), "\n")
cat("  CC series:", sum(grepl("^CC", all_items)), "\n")
cat("  DD series:", sum(grepl("^DD", all_items)), "\n")
cat("  EG series:", sum(grepl("^EG", all_items)), "\n\n")

# ==============================================================================
# 2. Load historical mirt calibration
# ==============================================================================

mirt_file <- "todo/kidsights-calibration/kidsight_calibration_mirt.rds"
mirt_obj <- readRDS(mirt_file)

pars <- mirt_obj$pars
codebook_mirt <- mirt_obj$codebook

cat("Loaded mirt calibration:\n")
cat("  Parameters:", nrow(pars), "rows\n")
cat("  Codebook:", nrow(codebook_mirt), "items\n\n")

# ==============================================================================
# 3. Load current codebook to get lex_equate mappings
# ==============================================================================

codebook_json <- jsonlite::fromJSON("codebook/data/codebook.json", simplifyVector = FALSE)

# Extract lex_equate mappings (using 'equate' lexicon field)
lex_mapping <- lapply(codebook_json$items, function(item) {
  data.frame(
    lex_equate = if(!is.null(item$lex$equate)) item$lex$equate else NA_character_,
    lex_ne22 = if(!is.null(item$lex$ne22)) item$lex$ne22 else NA_character_,
    stringsAsFactors = FALSE
  )
}) |> dplyr::bind_rows()

cat("Loaded current codebook:\n")
cat("  Total items:", nrow(lex_mapping), "\n")
cat("  Items with ne22 lexicon:", sum(!is.na(lex_mapping$lex_ne22)), "\n\n")

# ==============================================================================
# 4. Extract item parameters (slopes and thresholds) from mirt
# ==============================================================================

# Get slopes (a1 parameter)
slopes <- pars |>
  dplyr::filter(name == "a1") |>
  dplyr::select(item, a = value)

# Get difficulties/thresholds (d parameter)
# NOTE: Mplus uses -d (flip sign from mirt parameterization)
thresholds <- pars |>
  dplyr::filter(name == "d") |>
  dplyr::mutate(tau = -value) |>
  dplyr::select(item, tau)

# Merge parameters
item_params_fixed <- slopes |>
  dplyr::inner_join(thresholds, by = "item") |>
  dplyr::inner_join(
    codebook_mirt |> dplyr::select(item = lex_kidsight, lex_ne22),
    by = "item"
  ) |>
  dplyr::left_join(lex_mapping, by = "lex_ne22") |>
  dplyr::filter(!is.na(lex_equate)) |>
  dplyr::select(lex_equate, a, tau) |>
  dplyr::arrange(lex_equate)

cat("Items with 2023 calibration parameters:\n")
cat("  Fixed items:", nrow(item_params_fixed), "\n")
print(head(item_params_fixed, 5))
cat("  ...\n\n")

# ==============================================================================
# 5. Identify which target items are fixed vs free
# ==============================================================================

target_items_df <- data.frame(
  lex_equate = all_items,
  stringsAsFactors = FALSE
)

# Join with fixed parameters
target_items_df <- target_items_df |>
  dplyr::left_join(item_params_fixed, by = "lex_equate") |>
  dplyr::mutate(
    is_fixed = !is.na(a),
    param_status = ifelse(is_fixed, "FIXED (2023 calib)", "FREE (new item)")
  ) |>
  dplyr::arrange(lex_equate)

cat("Target items status:\n")
cat("  Fixed (with 2023 parameters):", sum(target_items_df$is_fixed), "\n")
cat("  Free (new items to estimate):", sum(!target_items_df$is_fixed), "\n\n")

cat("Items WITHOUT 2023 parameters (will be free-to-estimate):\n")
free_items <- target_items_df |> dplyr::filter(!is_fixed)
cat(paste(free_items$lex_equate, collapse = ", "), "\n\n")

# ==============================================================================
# 6. Generate Mplus MODEL block
# ==============================================================================

# Separate fixed and free items
fixed_items <- target_items_df |> dplyr::filter(is_fixed)
free_items <- target_items_df |> dplyr::filter(!is_fixed)

# Generate factor loading block
loading_lines <- character()

# Fixed loadings
if (nrow(fixed_items) > 0) {
  fixed_loading_lines <- paste0("       ", fixed_items$lex_equate, "@",
                                sprintf("%.6f", fixed_items$a))
  loading_lines <- c(loading_lines, fixed_loading_lines)
}

# Free loadings (no @ notation)
if (nrow(free_items) > 0) {
  free_loading_lines <- paste0("       ", free_items$lex_equate)
  loading_lines <- c(loading_lines, free_loading_lines)
}

loadings_block <- c(
  "MODEL:",
  "  ! Single developmental factor",
  "  ! Fixed slopes: From 2023 calibration (188 anchor items)",
  "  ! Free slopes: New NE25 items to be estimated",
  paste0("  F BY ", loading_lines[1]),
  loading_lines[-1],
  "       ;"
)

# Generate threshold block
threshold_lines <- character()

# Fixed thresholds
if (nrow(fixed_items) > 0) {
  fixed_threshold_lines <- paste0("  [", fixed_items$lex_equate, "$1@",
                                  sprintf("%.6f", fixed_items$tau), "];")
  threshold_lines <- c(threshold_lines, fixed_threshold_lines)
}

# Free thresholds
if (nrow(free_items) > 0) {
  free_threshold_lines <- paste0("  [", free_items$lex_equate, "$1];")
  threshold_lines <- c(threshold_lines, free_threshold_lines)
}

thresholds_block <- c(
  "",
  "  ! Fixed thresholds: From 2023 mirt calibration (tau_mplus = -d_mirt)",
  "  ! Free thresholds: New NE25 items to be estimated",
  threshold_lines
)

# Combine
model_block <- c(loadings_block, thresholds_block)

# ==============================================================================
# 7. Write output
# ==============================================================================

output_file <- "calibration/ne25/manual_2023_scale/utils/mplus_model_block.txt"
writeLines(model_block, output_file)

cat("[OK] MODEL block written to:", output_file, "\n")
cat("  Total items in MODEL:", length(all_items), "\n")
cat("  Fixed parameters:", sum(target_items_df$is_fixed), "\n")
cat("  Free parameters:", sum(!target_items_df$is_fixed), "\n")
cat("  Total lines in MODEL block:", length(model_block), "\n\n")
cat("Preview (first 20 lines):\n\n")
cat(paste(head(model_block, 20), collapse = "\n"), "\n")

# Federal Poverty Level Utility
# Returns year/family-size specific federal poverty guidelines.
# Extracted from R/transform/ne25_transforms.R — study-agnostic.
#
# Data source: Colorado DOLA Federal Poverty Level Chart + HHS Federal Register
# Hardcoded guidelines for 2020-2026 (48 contiguous states)

get_poverty_threshold <- function(dates, family_size, return_flag = FALSE) {
  year_vec <- lubridate::year(dates)
  if (any(is.na(year_vec))) {
    message("Invalid dates supplied. Assuming median of observed dates.")
    year_vec[is.na(year_vec)] <- stats::median(year_vec, na.rm = TRUE)
  }

  poverty_guidelines <- data.frame(
    year = rep(c(2020, 2021, 2022, 2023, 2024, 2025, 2026), each = 8),
    family_size = rep(1:8, 7),
    threshold = c(
      # 2020
      12760, 17240, 21720, 26200, 30680, 35160, 39640, 44120,
      # 2021
      12880, 17420, 21960, 26500, 31040, 35580, 40120, 44660,
      # 2022
      13590, 18310, 23030, 27750, 32470, 37190, 41910, 46630,
      # 2023
      14580, 19720, 24860, 30000, 35140, 40280, 45420, 50560,
      # 2024
      15060, 20440, 25820, 31200, 36580, 41960, 47340, 52720,
      # 2025
      15650, 21150, 26650, 32150, 37650, 43150, 48650, 54150,
      # 2026 (projected — update when HHS publishes)
      15650, 21150, 26650, 32150, 37650, 43150, 48650, 54150
    )
  )

  additional_amounts <- data.frame(
    year = c(2020, 2021, 2022, 2023, 2024, 2025, 2026),
    additional = c(4480, 4540, 4720, 5140, 5380, 5500, 5500)
  )

  final_df <- data.frame(date = dates, year = year_vec, family_size = family_size) %>%
    dplyr::mutate(
      above9 = ifelse(family_size > 8, family_size - 8, 0),
      family_size_lookup = ifelse(family_size > 8, 8, family_size),
      year_available = year %in% 2020:2026,
      year_lookup = dplyr::case_when(
        year < 2020 ~ 2020,
        year > 2026 ~ 2026,
        TRUE ~ year
      )
    ) %>%
    safe_left_join(poverty_guidelines, by_vars = c("year_lookup" = "year", "family_size_lookup" = "family_size")) %>%
    safe_left_join(additional_amounts, by_vars = c("year_lookup" = "year")) %>%
    dplyr::mutate(
      threshold = threshold + additional * above9,
      fpl_derivation_flag = dplyr::case_when(
        !year_available & above9 > 0 ~ paste0("extrapolated_", year_lookup, "_family_9plus"),
        !year_available ~ paste0("extrapolated_", year_lookup),
        above9 > 0 ~ paste0("guideline_", year_lookup, "_family_9plus"),
        TRUE ~ paste0("guideline_", year_lookup)
      )
    )

  if (return_flag) {
    return(list(threshold = final_df$threshold, flag = final_df$fpl_derivation_flag))
  } else {
    return(final_df$threshold)
  }
}

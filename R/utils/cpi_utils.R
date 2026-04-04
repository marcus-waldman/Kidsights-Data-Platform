# CPI Adjustment Utility
# Downloads CPI data from FRED API and calculates 1999 adjustment ratios.
# Extracted from R/transform/ne25_transforms.R — study-agnostic.

cpi_ratio_1999 <- function(date_vector, api_key_file = NULL) {
  # Get API key file path from .env if not provided
  if (is.null(api_key_file)) {
    if (!exists("get_fred_api_key_path", mode = "function")) {
      source("R/utils/environment_config.R")
    }
    api_key_file <- get_fred_api_key_path()
  }

  fred_api_key <- readLines(api_key_file, warn = FALSE)[1]
  fredr::fredr_set_key(fred_api_key)

  cpi_raw <- fredr::fredr(series_id = "CPIAUCSL")

  cpi_data <- cpi_raw %>%
    dplyr::mutate(
      year = lubridate::year(date),
      month = lubridate::month(date),
      cpi = value
    ) %>%
    dplyr::select(month, year, cpi)

  cpi_1999 <- cpi_data %>%
    dplyr::filter(year == 1999) %>%
    dplyr::select(month, cpi_1999 = cpi)

  input_df <- dplyr::tibble(
    original_date = as.Date(date_vector),
    year = lubridate::year(original_date),
    month = lubridate::month(original_date)
  )

  final_df <- input_df %>%
    safe_left_join(cpi_data, by_vars = c("month", "year")) %>%
    safe_left_join(cpi_1999, by_vars = "month") %>%
    dplyr::mutate(ratio = cpi_1999/cpi)

  final_df <- final_df %>%
    dplyr::mutate(rid = 1:dplyr::n()) %>%
    dplyr::arrange(original_date) %>%
    tidyr::fill(dplyr::everything(), .direction = "down") %>%
    dplyr::arrange(rid)

  return(final_df$ratio)
}

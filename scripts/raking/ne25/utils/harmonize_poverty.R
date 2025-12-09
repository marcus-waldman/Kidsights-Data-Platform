# Harmonize NHIS POVERTY categorical codes to continuous scale
#
# NHIS POVERTY uses categorical codes (11-37) representing poverty ratio ranges
# ACS POVERTY uses continuous values (1-501) representing percentage of FPL
#
# Strategy: Map both to common midpoint scale for calibration
# This ensures ACS targets match NHIS coding scheme

harmonize_nhis_poverty <- function(poverty_code) {
  # Map NHIS categorical codes to midpoint percentages
  # Multiply by 100 to convert ratio to percentage (to match ACS 1-501 scale)

  dplyr::case_when(
    poverty_code == 11 ~ 25,   # Under 0.50 → midpoint 0.25 → 25% FPL
    poverty_code == 12 ~ 62,   # 0.50 to 0.74 → midpoint 0.62 → 62% FPL
    poverty_code == 13 ~ 87,   # 0.75 to 0.99 → midpoint 0.87 → 87% FPL
    poverty_code == 14 ~ 50,   # Less than 1.0 (no detail) → midpoint 0.50 → 50% FPL

    poverty_code == 21 ~ 112,  # 1.00 to 1.24 → midpoint 1.12 → 112% FPL
    poverty_code == 22 ~ 137,  # 1.25 to 1.49 → midpoint 1.37 → 137% FPL
    poverty_code == 23 ~ 162,  # 1.50 to 1.74 → midpoint 1.62 → 162% FPL
    poverty_code == 24 ~ 187,  # 1.75 to 1.99 → midpoint 1.87 → 187% FPL
    poverty_code == 25 ~ 150,  # 1.00 to 1.99 (no detail) → midpoint 1.50 → 150% FPL

    poverty_code == 31 ~ 225,  # 2.00 to 2.49 → midpoint 2.25 → 225% FPL
    poverty_code == 32 ~ 275,  # 2.50 to 2.99 → midpoint 2.75 → 275% FPL
    poverty_code == 33 ~ 325,  # 3.00 to 3.49 → midpoint 3.25 → 325% FPL
    poverty_code == 34 ~ 375,  # 3.50 to 3.99 → midpoint 3.75 → 375% FPL
    poverty_code == 35 ~ 425,  # 4.00 to 4.49 → midpoint 4.25 → 425% FPL
    poverty_code == 36 ~ 475,  # 4.50 to 4.99 → midpoint 4.75 → 475% FPL
    poverty_code == 37 ~ 501,  # 5.00 and over → use ACS top-code 501 (500%+ FPL)
    poverty_code == 38 ~ 350,  # 2.00 and over (no detail) → rough midpoint 3.50 → 350% FPL

    poverty_code == 98 ~ NA_real_,  # Undefinable
    poverty_code == 99 ~ NA_real_,  # Unknown
    TRUE ~ NA_real_  # Any other value
  )
}

# Harmonize ACS POVERTY continuous values to match NHIS categorical midpoints
#
# ACS POVERTY is continuous (1-501 representing % of FPL)
# We bin it into NHIS-compatible categories and assign midpoint values
# This creates comparable distributions for calibration

harmonize_acs_poverty <- function(poverty_pct, cap_at_400 = FALSE) {
  # ACS POVERTY is continuous (1-501 representing % of FPL)
  #
  # For NHIS calibration: Bin into categorical midpoints to match NHIS coding
  # For NSCH calibration: Keep continuous, cap at 400 to match NSCH FPL_I1 range (50-400)

  if (cap_at_400) {
    # Keep continuous, cap at 400 for NSCH compatibility
    dplyr::case_when(
      is.na(poverty_pct) ~ NA_real_,
      poverty_pct > 400 ~ 400,  # Cap at 400% FPL to match NSCH range
      TRUE ~ poverty_pct         # Otherwise keep original value
    )
  } else {
    # Bin into NHIS-compatible categorical midpoints
    dplyr::case_when(
      is.na(poverty_pct) ~ NA_real_,
      poverty_pct < 50 ~ 25,      # Under 0.50 → 25% FPL
      poverty_pct < 75 ~ 62,      # 0.50 to 0.74 → 62% FPL
      poverty_pct < 100 ~ 87,     # 0.75 to 0.99 → 87% FPL
      poverty_pct < 125 ~ 112,    # 1.00 to 1.24 → 112% FPL
      poverty_pct < 150 ~ 137,    # 1.25 to 1.49 → 137% FPL
      poverty_pct < 175 ~ 162,    # 1.50 to 1.74 → 162% FPL
      poverty_pct < 200 ~ 187,    # 1.75 to 1.99 → 187% FPL
      poverty_pct < 250 ~ 225,    # 2.00 to 2.49 → 225% FPL
      poverty_pct < 300 ~ 275,    # 2.50 to 2.99 → 275% FPL
      poverty_pct < 350 ~ 325,    # 3.00 to 3.49 → 325% FPL
      poverty_pct < 400 ~ 375,    # 3.50 to 3.99 → 375% FPL
      poverty_pct < 450 ~ 425,    # 4.00 to 4.49 → 425% FPL
      poverty_pct < 500 ~ 475,    # 4.50 to 4.99 → 475% FPL
      poverty_pct >= 500 ~ 501,   # 5.00 and over → 501% FPL (top-code)
      TRUE ~ NA_real_
    )
  }
}

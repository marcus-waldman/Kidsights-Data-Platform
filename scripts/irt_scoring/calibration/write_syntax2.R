# =============================================================================
# Mplus MODEL Syntax Generation for IRT Calibration
# =============================================================================
# Purpose: Generate MODEL, MODEL CONSTRAINT, and MODEL PRIOR syntax for
#          IRT item calibration using graded response models
#
# Migrated from: Update-KidsightsPublic/utils/write_model_constraint_syntax.R
# Version: 1.0 (Kidsights-Data-Platform migration)
# Created: November 2025
# =============================================================================

# Load required packages
library(dplyr)
library(purrr)
library(tibble)
library(tidyr)
library(stringr)
library(writexl)

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

#' Extract EG Reference Item Names
#'
#' Extracts item names starting with "EG" from constraint text
#'
#' @param sentence Character string containing constraint specification
#' @return Character vector of EG item names, or NA if none found
extract_EG <- function(sentence) {
  words <- stringr::str_split(sentence, "\\s+", simplify = TRUE)
  match <- stringr::str_subset(words, regex("^EG", ignore_case = TRUE))
  if (length(match) > 0) {
    return(match)  # Return the first match
  } else {
    return(NA)  # Return NA if no match is found
  }
}

#' Extract Tau Threshold Names
#'
#' Extracts threshold names starting with "tau" from constraint text
#'
#' @param sentence Character string containing constraint specification
#' @return Character string of tau threshold name, or empty string if none found
extract_tau <- function(sentence) {
  words <- stringr::str_split(sentence, "\\s+", simplify = TRUE)
  match <- stringr::str_subset(words, regex("^tau", ignore_case = TRUE))
  if (length(match) > 0) {
    return(match[1])  # Return the first match
  } else {
    return("")  # Return empty string if no match is found
  }
}

# -----------------------------------------------------------------------------
# Main Function: write_syntax2
# -----------------------------------------------------------------------------

#' Generate Mplus MODEL Syntax for IRT Calibration
#'
#' Generates MODEL, MODEL CONSTRAINT, and MODEL PRIOR syntax for Mplus
#' IRT calibration using a graded response model with parameter constraints.
#'
#' Constraint types supported:
#' - "Constrain all to ITEM" - Share all parameters with reference item
#' - "Constrain slope to ITEM" - Share discrimination parameter only
#' - "Constrain tau$K to be greater than ITEM$K" - Threshold ordering
#' - "Constrain tau$K to be less than ITEM$K" - Reverse threshold ordering
#' - "Constrain tau$K to be a simplex between ITEM1$K and ITEM2$K" - Interpolation
#' - Unconstrained items - Automatic 1-PL (Rasch) constraints and N(1,1) priors
#'
#' @param codebook_df Data frame with columns:
#'   - jid: Item ID (numeric)
#'   - lex_equate: Lexicon-equated item name (character)
#'   - param_constraints: Constraint specification text (character, may be NA)
#' @param calibdat Data frame containing item response data
#'   - Should have item columns matching lex_equate names in codebook_df
#' @param output_xlsx Path for Excel output file (default: "mplus/generated_syntax.xlsx")
#' @param apply_1pl Logical, apply 1-PL/Rasch constraints to unconstrained items (default: FALSE)
#'   - TRUE: All unconstrained items share equal discrimination parameters
#'   - FALSE: Each item gets unique discrimination parameter (2-PL model)
#' @param verbose Logical, print progress messages (default: TRUE)
#'
#' @return List with components:
#'   - model: Data frame with MODEL section syntax
#'   - constraint: Data frame with MODEL CONSTRAINT section syntax
#'   - prior: Data frame with MODEL PRIOR section syntax
#'   - excel_path: Path to written Excel file
#'
#' @examples
#' # Minimal example
#' codebook_df <- tibble::tibble(
#'   jid = c(1, 2, 3),
#'   lex_equate = c("AA102", "AA104", "AA105"),
#'   param_constraints = c(NA, "Constrain all to AA102", NA)
#' )
#'
#' syntax <- write_syntax2(
#'   codebook_df = codebook_df,
#'   calibdat = my_calibration_data,
#'   output_xlsx = "mplus/generated_syntax.xlsx"
#' )
#'
#' @export
write_syntax2 <- function(
  codebook_df,
  calibdat,
  output_xlsx = "mplus/generated_syntax.xlsx",
  apply_1pl = FALSE,
  verbose = TRUE
) {

  if (verbose) {
    cat("\n", strrep("=", 70), "\n")
    cat("GENERATING MPLUS MODEL SYNTAX\n")
    cat(strrep("=", 70), "\n\n")
  }

  # ---------------------------------------------------------------------------
  # Step 1: Calculate maximum response categories for each item
  # ---------------------------------------------------------------------------

  if (verbose) cat("[1/5] Calculating maximum response categories (Ks)...\n")

  J <- max(codebook_df$jid)

  # Get item columns (all columns that match lex_equate names)
  item_cols <- codebook_df$lex_equate[codebook_df$lex_equate %in% names(calibdat)]

  Ks <- calibdat %>%
    dplyr::select(dplyr::all_of(item_cols)) %>%
    apply(2, max, na.rm = TRUE)

  # Add categories to codebook_df
  codebook_df$categories <- Ks[codebook_df$lex_equate] - 1

  if (verbose) {
    cat(sprintf("     Total items (J): %d\n", J))
    cat(sprintf("     Category range: %d to %d\n\n",
                min(Ks, na.rm = TRUE), max(Ks, na.rm = TRUE)))
  }

  # ---------------------------------------------------------------------------
  # Step 2: Extract constrained items
  # ---------------------------------------------------------------------------

  if (verbose) cat("[2/5] Extracting constrained items...\n")

  constraints <- codebook_df %>%
    dplyr::select(jid, lex_equate, param_constraints) %>%
    tidyr::drop_na(param_constraints)

  jds_constrained <- constraints$jid

  if (verbose) {
    cat(sprintf("     Constrained items: %d\n", length(jds_constrained)))
    cat(sprintf("     Unconstrained items: %d\n\n", J - length(jds_constrained)))
  }

  # ---------------------------------------------------------------------------
  # Step 3: Generate MODEL section
  # ---------------------------------------------------------------------------

  if (verbose) cat("[3/5] Generating MODEL syntax...\n")

  MODEL_txt <- lapply(codebook_df$jid, function(jdx) {

    # Base MODEL syntax for this item
    out_df <- with(codebook_df, {

      # Get starting values for this item
      alpha_start <- alpha_start[jid == jdx]
      tau_start <- tau_start[[which(jid == jdx)]]

      # Build factor loading syntax with optional starting value
      # Format: f BY item*1.234 (a_1); if starting value exists
      # Format: f BY item* (a_1); if no starting value
      if (!is.na(alpha_start) && length(alpha_start) > 0) {
        factor_syntax <- paste0("f BY ", lex_equate[jid == jdx], "*", alpha_start, " (a_", jdx, ");")
      } else {
        factor_syntax <- paste0("f BY ", lex_equate[jid == jdx], "* (a_", jdx, ");")
      }

      # Build threshold syntax with optional starting values
      # Format: [item$1*0.567] (t1_1); if starting value exists
      # Format: [item$1*] (t1_1); if no starting value
      threshold_syntaxes <- list()

      # Threshold 1 (always present)
      if (!is.null(tau_start) && !is.na(tau_start[1])) {
        threshold_syntaxes[[1]] <- paste0("[", lex_equate[jid == jdx], "$1*", tau_start[1], "] (t1_", jdx, ");")
      } else {
        threshold_syntaxes[[1]] <- paste0("[", lex_equate[jid == jdx], "$1*] (t1_", jdx, ");")
      }

      # Threshold 2 (if K >= 2)
      if (!is.na(Ks[jdx]) && Ks[jdx] >= 2) {
        if (!is.null(tau_start) && length(tau_start) >= 2 && !is.na(tau_start[2])) {
          threshold_syntaxes[[2]] <- paste0("[", lex_equate[jid == jdx], "$2*", tau_start[2], "] (t2_", jdx, ");")
        } else {
          threshold_syntaxes[[2]] <- paste0("[", lex_equate[jid == jdx], "$2*] (t2_", jdx, ");")
        }
      }

      # Threshold 3 (if K >= 3)
      if (!is.na(Ks[jdx]) && Ks[jdx] >= 3) {
        if (!is.null(tau_start) && length(tau_start) >= 3 && !is.na(tau_start[3])) {
          threshold_syntaxes[[3]] <- paste0("[", lex_equate[jid == jdx], "$3*", tau_start[3], "] (t3_", jdx, ");")
        } else {
          threshold_syntaxes[[3]] <- paste0("[", lex_equate[jid == jdx], "$3*] (t3_", jdx, ");")
        }
      }

      # Threshold 4 (if K >= 4)
      if (!is.na(Ks[jdx]) && Ks[jdx] >= 4) {
        if (!is.null(tau_start) && length(tau_start) >= 4 && !is.na(tau_start[4])) {
          threshold_syntaxes[[4]] <- paste0("[", lex_equate[jid == jdx], "$4*", tau_start[4], "] (t4_", jdx, ");")
        } else {
          threshold_syntaxes[[4]] <- paste0("[", lex_equate[jid == jdx], "$4*] (t4_", jdx, ");")
        }
      }

      # Threshold 5 (if K >= 5)
      if (!is.na(Ks[jdx]) && Ks[jdx] >= 5) {
        if (!is.null(tau_start) && length(tau_start) >= 5 && !is.na(tau_start[5])) {
          threshold_syntaxes[[5]] <- paste0("[", lex_equate[jid == jdx], "$5*", tau_start[5], "] (t5_", jdx, ");")
        } else {
          threshold_syntaxes[[5]] <- paste0("[", lex_equate[jid == jdx], "$5*] (t5_", jdx, ");")
        }
      }

      # Build complete syntax lines
      syntax_lines <- c(
        "",
        paste0("!ITEM: ", lex_equate[jid == jdx], " | jid = ", jdx),
        if (jdx %in% jds_constrained) paste0("!", codebook_df %>% dplyr::filter(jid == jdx) %>% purrr::pluck("param_constraints")),
        factor_syntax,
        unlist(threshold_syntaxes)
      )

      # Remove NULL entries and create tibble
      tibble::tibble(MODEL = syntax_lines[!sapply(syntax_lines, is.null)])
    })

    # If unconstrained, return base syntax
    if (!(jdx %in% jds_constrained)) { return(out_df) }

    # Parse constraints for this item
    constraints_j <- constraints %>% dplyr::filter(jid == jdx)
    parsed_j <- constraints_j %>%
      purrr::pluck("param_constraints") %>%
      stringr::str_replace_all(";", "\\.") %>%
      stringr::str_split_1("\\.")

    # Add comment markers to parsed constraints
    parsed0_j <- parsed_j
    for (k in 1:length(parsed0_j)) {
      parsed0_j[k] <- paste0("!", stringr::str_squish(parsed0_j[k]))
    }

    # Remove empty constraints
    ids_keep <- which(parsed0_j != "!")
    parsed0_j <- parsed0_j[ids_keep]
    parsed_j <- parsed_j[ids_keep]

    # Extract reference item from first constraint
    EGref <- extract_EG(parsed_j[[1]])
    refjid <- with(codebook_df, jid[lex_equate == EGref])

    # Parse each constraint statement
    parsed_j <- lapply(1:length(parsed_j), function(x) {

      foo <- list(
        operation = dplyr::case_when(
          stringr::str_detect(parsed_j[x], "simplex") ~ "simplex",
          stringr::str_detect(parsed_j[x], "between") & !stringr::str_detect(parsed_j[x], "simplex") ~ "between",
          stringr::str_detect(parsed_j[x], "greater than") ~ "greater than",
          stringr::str_detect(parsed_j[x], "less than") ~ "less than",
          .default = "equal"
        ),
        tau = extract_tau(parsed_j[x]) %>% stringr::str_split_1("\\$"),
        EG = extract_EG(parsed_j[x]) %>% stringr::str_split("\\$")
      )

      foo$refid <- with(codebook_df, jid[lex_equate == foo$EG[[1]][startsWith(foo$EG[[1]], "EG")]])

      return(foo)

    })

    # Apply slope constraint (share discrimination parameter)
    if (stringr::str_detect(constraints_j$param_constraints[[1]], "slope")) {
      out_df <- out_df %>%
        dplyr::mutate(MODEL = stringr::str_replace_all(MODEL, paste0("a_", jdx), paste0("a_", refjid)))
    }

    # Apply "constrain all" (share all parameters)
    if (stringr::str_detect(constraints_j$param_constraints[[1]], "all")) {
      out_df <- out_df %>%
        dplyr::mutate(MODEL = stringr::str_replace_all(MODEL, paste0("\\_", jdx), paste0("\\_", refjid)))
    }

    # Apply threshold equality constraints
    if (length(parsed_j) > 1) {
      for (k in 2:length(parsed_j)) {

        if (parsed_j[[k]]$operation != "equal") { next }

        parsed_j[[k]]$tau <- paste0(stringr::str_replace_all(parsed_j[[k]]$tau, "tau", "t"), collapse = "") %>%
          paste0(., "_", jdx)

        parsed_j[[k]]$EG <- lapply(1:length(parsed_j[[k]]$EG), function(kk) {
          for (kkk in 1:length(parsed_j[[k]]$EG[[kk]])) {
            parsed_j[[k]]$EG[[kk]][kkk] <- stringr::str_replace_all(
              parsed_j[[k]]$EG[[kk]][kkk],
              parsed_j[[k]]$EG[[kk]][1],
              "t"
            )
          }
          return(paste0(unlist(parsed_j[[k]]$EG[kk]), collapse = "") %>% paste0(., "_", parsed_j[[k]]$refid[1]))
        })

        out_df <- out_df %>%
          dplyr::mutate(
            MODEL = stringr::str_replace_all(
              MODEL,
              paste0("\\(", parsed_j[[k]]$tau, "\\)"),
              paste0("\\(", parsed_j[[k]]$EG[[1]], "\\)")
            )
          )

      }
    }

    return(out_df)

  }) %>% dplyr::bind_rows()

  if (verbose) {
    cat(sprintf("     MODEL syntax lines: %d\n\n", nrow(MODEL_txt)))
  }

  # ---------------------------------------------------------------------------
  # Step 4: Generate MODEL CONSTRAINT section
  # ---------------------------------------------------------------------------

  if (verbose) cat("[4/5] Generating MODEL CONSTRAINT syntax...\n")

  constraint_syntax <- lapply(constraints$jid, function(jdx) {

    if (verbose) cat(sprintf("     Processing constraints for jid %d...\n", jdx))

    constraints_j <- constraints %>% dplyr::filter(jid == jdx)
    parsed_j <- constraints_j %>%
      purrr::pluck("param_constraints") %>%
      stringr::str_replace_all(";", "\\.") %>%
      stringr::str_split_1("\\.")

    # Add comment markers
    parsed0_j <- parsed_j
    for (k in 1:length(parsed0_j)) {
      parsed0_j[k] <- paste0("!", stringr::str_squish(parsed0_j[k]))
    }

    # Remove empty constraints
    ids_keep <- which(parsed0_j != "!")
    parsed0_j <- parsed0_j[ids_keep]
    parsed_j <- parsed_j[ids_keep]

    # Extract reference item
    EGref <- extract_EG(parsed_j[[1]])
    refjid <- with(codebook_df, jid[lex_equate == EGref])

    # Parse constraint operations
    parsed_j <- lapply(1:length(parsed_j), function(x) {

      foo <- list(
        operation = dplyr::case_when(
          stringr::str_detect(parsed_j[x], "simplex") ~ "simplex",
          stringr::str_detect(parsed_j[x], "between") & !stringr::str_detect(parsed_j[x], "simplex") ~ "between",
          stringr::str_detect(parsed_j[x], "greater than") ~ "greater than",
          stringr::str_detect(parsed_j[x], "less than") ~ "less than",
          .default = "equal"
        ),
        tau = extract_tau(parsed_j[x]) %>% stringr::str_split_1("\\$"),
        EG = extract_EG(parsed_j[x]) %>% stringr::str_split("\\$")
      )

      foo$refid <- with(codebook_df, jid[lex_equate == foo$EG[[1]][startsWith(foo$EG[[1]], "EG")]])

      return(foo)

    })

    # Generate slope constraint if needed
    slope_constraint <- NULL
    slope <- stringr::str_detect(constraints_j$param_constraints[[1]], "slope") |
             stringr::str_detect(constraints_j$param_constraints[[1]], "all")

    if (slope) {
      slope_constraint <- paste0("0 = a_", jdx, " - a_", parsed_j[[1]]$refid, ";")
    }

    # Generate threshold constraints
    tau_constraints <- NULL
    if (stringr::str_detect(constraints_j$param_constraints[[1]], "all")) {
      tau_constraints <- NA
    }

    if (length(parsed_j) > 1) {
      for (k in 2:length(parsed_j)) {
        parsed_j[[k]]$tau <- paste0(stringr::str_replace_all(parsed_j[[k]]$tau, "tau", "t"), collapse = "") %>%
          paste0(., "_", jdx)

        parsed_j[[k]]$EG <- lapply(1:length(parsed_j[[k]]$EG), function(kk) {
          for (kkk in 1:length(parsed_j[[k]]$EG[[kk]])) {
            parsed_j[[k]]$EG[[kk]][kkk] <- stringr::str_replace_all(
              parsed_j[[k]]$EG[[kk]][kkk],
              parsed_j[[k]]$EG[[kk]][1],
              "t"
            )
          }
          return(paste0(unlist(parsed_j[[k]]$EG[kk]), collapse = "") %>% paste0(., "_", parsed_j[[k]]$refid[1]))
        })
      }

      tau_constraints <- sapply(2:length(parsed_j), function(k) {
        if (parsed_j[[k]]$operation == "greater than") {
          return(paste0("0 > ", parsed_j[[k]]$EG, " - ", parsed_j[[k]]$tau, ";"))
        }
        if (parsed_j[[k]]$operation == "less than") {
          return(paste0("0 < ", parsed_j[[k]]$EG, " - ", parsed_j[[k]]$tau, ";"))
        }
        if (parsed_j[[k]]$operation == "equal") {
          return(NA)
        }
        if (parsed_j[[k]]$operation == "simplex") {
          return(paste0(parsed_j[[k]]$tau, " = p*", parsed_j[[k]]$EG[1], " + (1-p)*", parsed_j[[k]]$EG[2], ";"))
        }
        if (parsed_j[[k]]$operation == "between") {
          return(
            c(
              paste0("0 > ", parsed_j[[k]]$EG[1], " - ", parsed_j[[k]]$tau, ";"),
              paste0("0 < ", parsed_j[[k]]$EG[2], " - ", parsed_j[[k]]$tau, ";")
            )
          )
        }
      })
    }

    # Build constraint lines, handling NULL tau_constraints
    constraint_lines <- c(
      "",
      paste0("!ITEM: ", constraints_j$lex_equate, " | jid = ", jdx),
      parsed0_j
    )

    # Add tau_constraints if they exist
    if (!is.null(tau_constraints) && length(tau_constraints) > 0) {
      tau_clean <- tau_constraints[!is.na(tau_constraints)]
      if (length(tau_clean) > 0) {
        constraint_lines <- c(constraint_lines, tau_clean)
      }
    }

    out <- tibble::tibble(`MODEL CONSTRAINT:` = constraint_lines)

    return(out %>% dplyr::filter(`MODEL CONSTRAINT:` != "!"))

  }) %>% dplyr::bind_rows()

  # Add New(p*) declaration at top
  constraint_syntax <- tibble::tibble(
    `MODEL CONSTRAINT:` = c("New(p*);", " ", constraint_syntax$`MODEL CONSTRAINT:`)
  )

  # Optionally add 1-PL constraints for unconstrained items
  if (apply_1pl && length(setdiff(codebook_df$jid, constraints$jid)) > 1) {
    unconstrained_params <- paste0("a_", setdiff(codebook_df$jid, constraints$jid))
    rasch_left <- paste0("0 = ", unconstrained_params[1], " - ")
    rasch_right <- paste0(unconstrained_params[-1], ";")

    if (verbose) {
      cat(sprintf("     Constraint syntax lines: %d\n", nrow(constraint_syntax)))
      cat(sprintf("     1-PL constraints: %d\n\n", length(rasch_right)))
    }
  } else {
    rasch_left <- character(0)
    rasch_right <- character(0)

    if (verbose) {
      cat(sprintf("     Constraint syntax lines: %d\n", nrow(constraint_syntax)))
      if (apply_1pl) {
        cat("     1-PL constraints: 0 (not enough unconstrained items)\n\n")
      } else {
        cat("     1-PL constraints: 0 (apply_1pl = FALSE, using 2-PL model)\n\n")
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Step 5: Generate MODEL PRIOR section
  # ---------------------------------------------------------------------------

  if (verbose) cat("[5/5] Generating MODEL PRIOR syntax...\n")

  prior_syntax <- data.frame(
    `MODEL PRIOR` = paste0("a_", setdiff(codebook_df$jid, constraints$jid), " ~ N(1,1);")
  )

  if (verbose) {
    cat(sprintf("     Prior syntax lines: %d\n\n", nrow(prior_syntax)))
  }

  # ---------------------------------------------------------------------------
  # Combine into final syntax list
  # ---------------------------------------------------------------------------

  syntax_list <- list(
    MODEL = MODEL_txt,
    `MODEL CONSTRAINT` = data.frame(
      `MODEL.CONSTRAINT` = c(
        constraint_syntax$`MODEL CONSTRAINT:`,
        " ",
        "!1-PL Constraints",
        paste0(rasch_left, rasch_right)
      )
    ),
    `MODEL PRIOR` = prior_syntax
  )

  # ---------------------------------------------------------------------------
  # Write Excel file
  # ---------------------------------------------------------------------------

  if (verbose) cat("Writing Excel file...\n")

  # Create output directory if needed
  output_dir <- dirname(output_xlsx)
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  writexl::write_xlsx(syntax_list, output_xlsx)

  if (verbose) {
    cat(sprintf("\n[OK] Syntax generation complete!\n"))
    cat(sprintf("     Excel file: %s\n", output_xlsx))
    cat(sprintf("     Sheets: MODEL, MODEL CONSTRAINT, MODEL PRIOR\n\n"))
  }

  # ---------------------------------------------------------------------------
  # Return syntax components
  # ---------------------------------------------------------------------------

  return(invisible(list(
    model = MODEL_txt,
    constraint = syntax_list$`MODEL CONSTRAINT`,
    prior = syntax_list$`MODEL PRIOR`,
    excel_path = output_xlsx
  )))

}

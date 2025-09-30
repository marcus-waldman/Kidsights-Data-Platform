# NE25 Data Transformation Functions
# Ported from Kidsights Dashboard utils-etl.R

# Automatic package installation and loading for transformations
install_transformation_packages <- function() {
  # Required packages for transformations
  required_packages <- c(
    "plyr",       # For mapvalues (MUST load before dplyr)
    "dplyr",      # Data manipulation
    "tidyr",      # Data tidying
    "stringr",    # String operations
    "labelled"    # Variable labels
  )

  # Check which packages are missing
  missing_packages <- setdiff(required_packages, installed.packages()[,"Package"])

  # Install missing packages
  if(length(missing_packages) > 0) {
    message("Installing missing packages for transformations: ",
            paste(missing_packages, collapse = ", "))

    install.packages(missing_packages,
                    dependencies = TRUE,
                    repos = "https://cran.rstudio.com/",
                    quiet = TRUE)

    message("Transformation packages installation completed.")
  }

  # Load packages in correct order (plyr BEFORE dplyr to avoid conflicts)
  load_order <- c("plyr", setdiff(required_packages, "plyr"))

  for(pkg in load_order) {
    if(pkg %in% installed.packages()[,"Package"]) {
      suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    } else {
      warning(paste("Package", pkg, "failed to install and could not be loaded"))
    }
  }

  # Check for critical conflicts
  if("plyr" %in% loadedNamespaces() && "dplyr" %in% loadedNamespaces()) {
    # Verify plyr was loaded first
    search_order <- search()
    plyr_pos <- which(grepl("plyr", search_order))
    dplyr_pos <- which(grepl("dplyr", search_order))

    if(length(plyr_pos) > 0 && length(dplyr_pos) > 0 && any(plyr_pos > min(dplyr_pos))) {
      warning("Package loading order issue: dplyr loaded before plyr. ",
              "This may cause mapvalues() function conflicts.")
    }
  }

  return(list(
    installed = required_packages,
    missing = missing_packages
  ))
}

# Initialize transformation packages
transformation_packages <- install_transformation_packages()

# Helper function to get value labels from REDCap dictionary
value_labels <- function(lex, dict, varname = "lex_ne25") {
  cat("=== VALUE_LABELS TRANSFORM DEBUG ===\n")
  cat("Lex:", lex, "\n")
  cat("Varname:", varname, "\n")
  cat("Dict type:", class(dict), "\n")
  cat("Dict length:", length(dict), "\n")

  # Save test data for rapid debugging
  test_data_dir <- "temp/value_labels_transform_test_data"
  if (!dir.exists(test_data_dir)) dir.create(test_data_dir, recursive = TRUE)

  saveRDS(lex, file.path(test_data_dir, "lex.rds"))
  saveRDS(dict, file.path(test_data_dir, "dict.rds"))
  saveRDS(varname, file.path(test_data_dir, "varname.rds"))
  cat("Transform test data saved to:", test_data_dir, "\n")

  # Check if the field exists in the dictionary
  if (is.null(dict) || is.null(dict[[lex]]) || is.null(dict[[lex]]$select_choices_or_calculations)) {
    warning(paste("Dictionary entry not found for field:", lex, "- returning empty labels"))
    return(data.frame(
      lex_ne25 = character(0),
      value = character(0),
      label = character(0)
    ))
  }

  # Note issue in education labels due to commas in description
  choices_str <- dict[[lex]]$select_choices_or_calculations
  cat("Choices_str type:", class(choices_str), "\n")
  cat("Choices_str length:", length(choices_str), "\n")
  cat("Choices_str content (first 100 chars):", substr(paste(choices_str, collapse=" | "), 1, 100), "\n")

  if (is.na(choices_str) || all(choices_str == "")) {
    warning(paste("Empty choices for field:", lex, "- returning empty labels"))
    return(data.frame(
      lex_ne25 = character(0),
      value = character(0),
      label = character(0)
    ))
  }

  cat("About to call str_split_1 on choices_str...\n")
  tmp <- tryCatch({
    choices_str %>% stringr::str_split_1(" \\| ")
  }, error = function(e) {
    cat("ERROR in str_split_1 on choices_str:\n")
    cat("Message:", e$message, "\n")
    cat("Choices_str causing error:", choices_str, "\n")
    stop(e)
  })

  outdf <- data.frame(value = rep(NA, length(tmp)), label = NA)

  for(i in 1:length(tmp)) {
    cat("Processing tmp[", i, "]:", tmp[i], "\n")
    tmp_i <- tryCatch({
      tmp[i] %>% stringr::str_split_1(", ")
    }, error = function(e) {
      cat("ERROR in str_split_1 for tmp[", i, "]:", tmp[i], "\n")
      cat("Error message:", e$message, "\n")
      stop(e)
    })
    outdf$value[i] <- tmp_i[1]
    outdf$label[i] <- paste0(tmp_i[-1], collapse = ", ")
  }

  outdf <- outdf %>%
    dplyr::mutate(var = lex) %>%
    dplyr::relocate(var)

  names(outdf)[1] <- varname

  return(outdf)
}

# CPI adjustment function (simplified version)
cpi_ratio_1999 <- function(date_vector) {
  # For simplicity, return 1.0 for now
  # Full implementation would download CPI data from FRED
  rep(1.0, length(date_vector))
}

# Poverty threshold function (simplified)
get_poverty_threshold <- function(dates, family_size) {
  # Simplified poverty thresholds for 2024
  thresholds <- c(15060, 20440, 25820, 31200, 36580, 41960, 47340, 52720)

  # Use family size to get threshold, default to family of 4
  sapply(family_size, function(fs) {
    if(is.na(fs) || fs > 8) return(31200)  # Default to family of 4
    return(thresholds[fs])
  })
}

# Main transformation function
recode__ <- function(dat, dict, my_API = NULL, what = NULL, relevel_it = TRUE, add_labels = TRUE) {

  recodes_df <- NULL

  if(what %in% c("include")) {
    recodes_df <- dat %>%
      dplyr::select(pid, record_id, eligibility, authenticity) %>%
      dplyr::mutate(
        eligible = (eligibility == "Pass"),
        authentic = (authenticity == "Pass"),
        include = (eligible & authentic)
      ) %>%
      dplyr::select(-eligibility, -authenticity)

    if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
      labelled::var_label(recodes_df$eligible) <- "Meets study inclusion criteria"
      labelled::var_label(recodes_df$authentic) <- "Passes authenticity screening"
      labelled::var_label(recodes_df$include) <- "Meets inclusion criteria (inclusion + authenticity)"
    }
  }

  if(what %in% c("race", "ethnicity")) {
    #---------------------------------------------------------------------------
    # Child Race
    #---------------------------------------------------------------------------
    raceth_df <- dat %>%
      dplyr::select(pid, record_id, dplyr::starts_with("cqr011"), dplyr::starts_with("cqr010_")) %>%
      tidyr::pivot_longer(dplyr::starts_with("cqr010"), names_to = "var", values_to = "response") %>%
      dplyr::left_join(
        value_labels("cqr010", dict = dict) %>%
          dplyr::mutate(var = paste(lex_ne25, value, sep = "___")) %>%
          dplyr::select(var, label),
        by = "var"
      ) %>%
      dplyr::mutate(
        label = ifelse(label %in% c("Asian Indian", "Chinese", "Filipino", "Japanese", "Korean", "Vietnamese", "Native Hawaiian", "Guamanian or Chamorro", "Samoan", "Other Pacific Islander"), "Asian or Pacific Islander", label),
        label = ifelse(label %in% c("Middle Eastern", "Some other race"), "Some Other Race", label)
      ) %>%
      dplyr::filter(response == 1) %>%
      dplyr::group_by(pid, record_id, label) %>%
      dplyr::reframe(hisp = ifelse(cqr011[1] == 1, "Hispanic", "non-Hisp.")) %>%
      dplyr::ungroup() %>%
      dplyr::group_by(pid, record_id) %>%
      dplyr::reframe(hisp = hisp[1], race = ifelse(n() > 1, "Two or More", label[1])) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(raceG = ifelse(hisp == "Hispanic", "Hispanic", paste0(race, ", non-Hisp."))) %>%
      dplyr::mutate(raceG = ifelse(raceG == "Other Asian, non-Hisp.", "Asian or Pacific Islander, non-Hisp.", raceG)) %>%
      dplyr::mutate(across(where(is.character), as.factor)) %>%
      dplyr::select(pid:record_id, hisp, race, raceG)

    if(relevel_it) {
      # Set baseline categories
      raceth_df$hisp <- relevel(raceth_df$hisp, ref = "non-Hisp.")
      raceth_df$race <- relevel(raceth_df$race, ref = "White")
      raceth_df$raceG <- relevel(raceth_df$raceG, ref = "White, non-Hisp.")
    }

    #---------------------------------------------------------------------------
    # Caregiver's Race
    #---------------------------------------------------------------------------
    a1_raceth_df <- dat %>%
      dplyr::select(pid, record_id, dplyr::starts_with("sq003"), dplyr::starts_with("sq002_")) %>%
      tidyr::pivot_longer(dplyr::starts_with("sq002_"), names_to = "var", values_to = "response") %>%
      dplyr::left_join(
        value_labels("sq002", dict = dict) %>%
          dplyr::mutate(var = paste(lex_ne25, value, sep = "___")) %>%
          dplyr::select(var, label),
        by = "var"
      ) %>%
      dplyr::mutate(
        label = ifelse(label %in% c("Asian Indian", "Chinese", "Filipino", "Japanese", "Korean", "Vietnamese", "Native Hawaiian", "Guamanian or Chamorro", "Samoan", "Other Pacific Islander"), "Asian or Pacific Islander", label),
        label = ifelse(label %in% c("Middle Eastern", "Some other race"), "Some Other Race", label)
      ) %>%
      dplyr::filter(response == 1) %>%
      dplyr::group_by(pid, record_id, label) %>%
      dplyr::reframe(a1_hisp = ifelse(sq003[1] == 1, "Hispanic", "non-Hisp.")) %>%
      dplyr::ungroup() %>%
      dplyr::group_by(pid, record_id) %>%
      dplyr::reframe(a1_hisp = a1_hisp[1], a1_race = ifelse(n() > 1, "Two or More", label[1])) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(a1_raceG = ifelse(a1_hisp == "Hispanic", "Hispanic", paste0(a1_race, ", non-Hisp."))) %>%
      dplyr::mutate(a1_raceG = ifelse(a1_raceG == "Other Asian, non-Hisp.", "Asian or Pacific Islander, non-Hisp.", a1_raceG)) %>%
      dplyr::mutate(across(where(is.character), as.factor)) %>%
      dplyr::select(pid:record_id, a1_hisp, a1_race, a1_raceG)

    if(relevel_it) {
      # Set baseline categories
      a1_raceth_df$a1_hisp <- relevel(a1_raceth_df$a1_hisp, ref = "non-Hisp.")
      a1_raceth_df$a1_race <- relevel(a1_raceth_df$a1_race, ref = "White")
      a1_raceth_df$a1_raceG <- relevel(a1_raceth_df$a1_raceG, ref = "White, non-Hisp.")
    }

    recodes_df <- raceth_df %>% dplyr::left_join(a1_raceth_df, by = c("pid", "record_id"))

    # Add labels after creating variables
    if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
      labelled::var_label(recodes_df$hisp) <- "Child Hispanic/Latino ethnicity"
      labelled::var_label(recodes_df$race) <- "Child race (collapsed categories)"
      labelled::var_label(recodes_df$raceG) <- "Child race/ethnicity combined"
      labelled::var_label(recodes_df$a1_hisp) <- "Primary caregiver Hispanic/Latino ethnicity"
      labelled::var_label(recodes_df$a1_race) <- "Primary caregiver race (collapsed categories)"
      labelled::var_label(recodes_df$a1_raceG) <- "Primary caregiver race/ethnicity combined"
    }
  }

  if(what %in% c("caregiver relationship")) {
    # responding caregiver
    relate_df <- dat %>%
      dplyr::mutate(
        relation1 = tryCatch({
          labels <- value_labels(lex = "cqr008", dict = dict)
          if (nrow(labels) > 0) {
            plyr::mapvalues(cqr008, from = labels$value, to = labels$label, warn_missing = F)
          } else {
            as.character(cqr008)
          }
        }, error = function(e) { as.character(cqr008) }),
        relation2 = tryCatch({
          labels <- value_labels(lex = "nschj013", dict = dict)
          if (nrow(labels) > 0) {
            plyr::mapvalues(nschj013, from = labels$value, to = labels$label, warn_missing = F)
          } else {
            as.character(nschj013)
          }
        }, error = function(e) { as.character(nschj013) }),
        female_a1 = as.logical(cqr002 == 0),
        mom_a1 = tryCatch({
          labels <- value_labels(lex = "cqr008", dict = dict)
          if (nrow(labels) > 0) {
            as.logical(relation1 == labels$label[1] & female_a1)
          } else {
            as.logical(FALSE)
          }
        }, error = function(e) { as.logical(FALSE) })
      ) %>%
      dplyr::select(pid, record_id, relation1:mom_a1) %>%
      dplyr::mutate(across(where(is.character), as.factor))

    if(relevel_it) {
      relate_df$relation2 <- relevel(relate_df$relation2, value_labels(lex = "nschj013", dict = dict)$label[1])
    }

    # Add labels after creating variables
    if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
      labelled::var_label(relate_df$relation1) <- "Primary caregiver relationship to child"
      labelled::var_label(relate_df$relation2) <- "Secondary caregiver relationship to child"
      labelled::var_label(relate_df$female_a1) <- "Primary caregiver is female"
      labelled::var_label(relate_df$mom_a1) <- "Primary caregiver is mother"
    }

    recodes_df <- relate_df
  }

  if(what == "sex") {
    sex_df <- dat %>%
      dplyr::select(pid, record_id, cqr009) %>%
      dplyr::mutate(
        sex = tryCatch({
          labels <- value_labels(lex = "cqr009", dict = dict)
          if (nrow(labels) > 0) {
            plyr::mapvalues(cqr009, from = labels$value, to = labels$label, warn_missing = F)
          } else {
            as.character(cqr009)
          }
        }, error = function(e) { as.character(cqr009) }),
        female = (sex == "Female")
      ) %>%
      dplyr::mutate(across(where(is.character), as.factor))

    if(relevel_it) {
      sex_df$sex <- relevel(sex_df$sex, ref = "Female")
    }

    # Add labels after creating variables
    if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
      labelled::var_label(sex_df$sex) <- "Child's sex"
      labelled::var_label(sex_df$female) <- "Child is female"
    }

    recodes_df <- sex_df %>% dplyr::select(-cqr009)
  }

  if(what == "age") {
    age_df <- dat %>%
      dplyr::select(pid, record_id, age_in_days, cqr003) %>%
      dplyr::mutate(
        days_old = age_in_days,
        years_old = age_in_days / 365.25,
        months_old = years_old * 12,
        a1_years_old = cqr003
      )

    # Add labels after creating variables
    if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
      labelled::var_label(age_df$days_old) <- "Child's age (days)"
      labelled::var_label(age_df$years_old) <- "Child's age (years)"
      labelled::var_label(age_df$months_old) <- "Child's age (months)"
      labelled::var_label(age_df$a1_years_old) <- "Primary caregiver age (years)"
    }

    recodes_df <- age_df %>% dplyr::select(-cqr003, -age_in_days)
  }

  if(what == "income") {
    income_df <- dat %>%
      dplyr::select(consent_date, pid, record_id, cqr006, fqlive1_1, fqlive1_2) %>%
      dplyr::rename(income = cqr006) %>%
      dplyr::mutate(
        cpi99 = cpi_ratio_1999(consent_date),
        inc99 = income * cpi99,
        family_size = dplyr::case_when(
          fqlive1_1 < 999 & fqlive1_2 < 999 ~ fqlive1_1 + fqlive1_2,
          fqlive1_1 < 999 & fqlive1_2 == 999 ~ fqlive1_2 + 1,
          .default = NA
        ),
        federal_poverty_threshold = get_poverty_threshold(dates = consent_date, family_size = family_size),
        fpl = round(100 * income / federal_poverty_threshold, 0),
        fplcat = cut(fpl, c(-Inf, 100, 200, 300, 400, Inf), labels = c("<100% FPL", "100-199% FPL", "200-299% FPL", "300-399% FPL", "400+% FPL"))
      )

    if(relevel_it) {
      income_df$fplcat <- relevel(income_df$fplcat, ref = "400+% FPL")
    }

    # Add labels after creating variables
    if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
      labelled::var_label(income_df$income) <- "Household annual income (nominal dollars)"
      labelled::var_label(income_df$cpi99) <- "CPI adjustment ratio to 1999 dollars"
      labelled::var_label(income_df$inc99) <- "Household annual income (1999 dollars)"
      labelled::var_label(income_df$family_size) <- "Family size (number of people in household)"
      labelled::var_label(income_df$federal_poverty_threshold) <- "Federal poverty threshold for family size"
      labelled::var_label(income_df$fpl) <- "Household income as percentage of federal poverty level"
      labelled::var_label(income_df$fplcat) <- "Household income as percentage of federal poverty level (categories)"
    }

    recodes_df <- income_df %>% dplyr::select(-consent_date, -cpi99)
  }

  if(what %in% c("education")) {

    # Try to get education labels, but handle missing dictionary gracefully
    cqr004_labels <- tryCatch({
      value_labels(lex = "cqr004", dict = dict)
    }, error = function(e) {
      warning("Education dictionary not found - skipping education transformations")
      return(NULL)
    })

    if (is.null(cqr004_labels) || nrow(cqr004_labels) == 0) {
      warning("Education transformations skipped - missing dictionary")
      # Return empty data frame with required structure
      return(data.frame(
        pid = integer(0),
        record_id = integer(0)
      ))
    }

    simple_educ_label <- data.frame(
      educ = cqr004_labels$label) %>%
      dplyr::mutate(
        educ4 = c(rep("Less than High School Graduate", 2),
                  rep("High School Graduate (including Equivalency)", 1),
                  rep("Some College or Associate's Degree", 3),
                  rep("College Degree", 3)
        ),
        educ6 = c(rep("Less than High School Graduate", 2),
                  rep("High School Graduate (including Equivalency)", 1),
                  rep("Some College or Associate's Degree", 3),
                  rep("Bachelor's Degree", 1),
                  rep("Master's Degree", 1),
                  rep("Doctorate or Professional Degree", 1)
        )
      )

    simple_educ_value <- data.frame(
      label = value_labels(lex = "cqr004", dict = dict)$label,
      educ = value_labels(lex = "cqr004", dict = dict)$value) %>%
      dplyr::mutate(educ4 = c(rep(0, 2),
                              rep(1, 1),
                              rep(2, 3),
                              rep(3, 3)
      ),
      educ6 = c(rep(0, 2),
                rep(1, 1),
                rep(2, 3),
                rep(3, 1),
                rep(4, 1),
                rep(5, 1)
      )
      )

    # Get caregiver relationship variables needed for maternal education
    relate_vars <- recode__(dat = dat, dict = dict, what = "caregiver relationship",
                            relevel_it = relevel_it, add_labels = FALSE)

    educ_df <- dat %>%
      dplyr::select(-dplyr::any_of(c("relation1", "relation2", "mom_a1"))) %>%
      dplyr::left_join(relate_vars, by = c("pid", "record_id")) %>%
      dplyr::mutate(
        ## Maximum education of caregivers (8 categories)
        educ_max =
          dplyr::case_when(
            nschj017 > cqr004 ~ nschj017,
            is.na(cqr004) & !is.na(nschj017) ~ nschj017,
            .default = cqr004
          ) %>%
          factor(
            levels = value_labels(lex = "cqr004", dict = dict)$value,
            labels = value_labels(lex = "cqr004", dict = dict)$label
          ),

        # Caregiver 1 and 2 education (8 categories)
        educ_a1 = factor(cqr004, levels = value_labels(lex = "cqr004", dict = dict)$value, labels = value_labels(lex = "cqr004", dict = dict)$label),
        educ_a2 = factor(nschj017, levels = value_labels(lex = "nschj017", dict = dict)$value, labels = value_labels(lex = "nschj017", dict = dict)$label),

        # Maternal education (8 categories)
        educ_mom = ifelse(mom_a1, educ_a1, NA) %>% factor(levels = value_labels(lex = "cqr004", dict = dict)$value, labels = value_labels(lex = "cqr004", dict = dict)$label),

        # Convert to four categories
        educ4_max = plyr::mapvalues(as.character(educ_max), from = simple_educ_label$educ, to = simple_educ_label$educ4) %>%
          plyr::mapvalues(from = simple_educ_label$educ4, to = simple_educ_value$educ4) %>%
          factor(levels = simple_educ_value$educ4, labels = simple_educ_label$educ4),
        educ4_a1 = plyr::mapvalues(as.character(educ_a1), from = simple_educ_label$educ, to = simple_educ_label$educ4) %>%
          plyr::mapvalues(from = simple_educ_label$educ4, to = simple_educ_value$educ4) %>%
          factor(levels = simple_educ_value$educ4, labels = simple_educ_label$educ4),
        educ4_a2 = plyr::mapvalues(as.character(educ_a2), from = simple_educ_label$educ, to = simple_educ_label$educ4) %>%
          plyr::mapvalues(from = simple_educ_label$educ4, to = simple_educ_value$educ4) %>%
          factor(levels = simple_educ_value$educ4, labels = simple_educ_label$educ4),
        educ4_mom = plyr::mapvalues(as.character(educ_mom), from = simple_educ_label$educ, to = simple_educ_label$educ4) %>%
          plyr::mapvalues(from = simple_educ_label$educ4, to = simple_educ_value$educ4) %>%
          factor(levels = simple_educ_value$educ4, labels = simple_educ_label$educ4),

        # Convert to 6 categories
        educ6_max = plyr::mapvalues(as.character(educ_max), from = simple_educ_label$educ, to = simple_educ_label$educ6) %>%
          plyr::mapvalues(from = simple_educ_label$educ6, to = simple_educ_value$educ6) %>%
          factor(levels = simple_educ_value$educ6, labels = simple_educ_label$educ6),
        educ6_a1 = plyr::mapvalues(as.character(educ_a1), from = simple_educ_label$educ, to = simple_educ_label$educ6) %>%
          plyr::mapvalues(from = simple_educ_label$educ6, to = simple_educ_value$educ6) %>%
          factor(levels = simple_educ_value$educ6, labels = simple_educ_label$educ6),
        educ6_a2 = plyr::mapvalues(as.character(educ_a2), from = simple_educ_label$educ, to = simple_educ_label$educ6) %>%
          plyr::mapvalues(from = simple_educ_label$educ6, to = simple_educ_value$educ6) %>%
          factor(levels = simple_educ_value$educ6, labels = simple_educ_label$educ6),
        educ6_mom = plyr::mapvalues(as.character(educ_mom), from = simple_educ_label$educ, to = simple_educ_label$educ6) %>%
          plyr::mapvalues(from = simple_educ_label$educ6, to = simple_educ_value$educ6) %>%
          factor(levels = simple_educ_value$educ6, labels = simple_educ_label$educ6)

      ) %>%
      dplyr::select(pid, record_id, educ_max:educ6_mom) %>%
      dplyr::mutate(across(where(is.character), as.factor))


    if(relevel_it) {
      # relevel
      educ_df$educ_max <- relevel(as.factor(educ_df$educ_max), ref = simple_educ_label$educ[7]) #BA/BS as reference
      educ_df$educ_a1 <- relevel(as.factor(educ_df$educ_a1), ref = simple_educ_label$educ[7]) #BA/BS as reference
      educ_df$educ_a2 <- relevel(as.factor(educ_df$educ_a2), ref = simple_educ_label$educ[7]) #BA/BS as reference

      educ_df$educ4_max <- relevel(as.factor(educ_df$educ4_max), ref = simple_educ_label$educ4[7]) #College degree reference
      educ_df$educ4_a1 <- relevel(as.factor(educ_df$educ4_a1), ref = simple_educ_label$educ4[7]) #College degree reference
      educ_df$educ4_a2 <- relevel(as.factor(educ_df$educ4_a2), ref = simple_educ_label$educ4[7]) #College degree reference

      educ_df$educ6_max <- relevel(as.factor(educ_df$educ6_max), ref = simple_educ_label$educ6[7]) #College degree reference
      educ_df$educ6_a1 <- relevel(as.factor(educ_df$educ6_a1), ref = simple_educ_label$educ6[7]) #College degree reference
      educ_df$educ6_a2 <- relevel(as.factor(educ_df$educ6_a2), ref = simple_educ_label$educ6[7]) #College degree reference
    }

    # Add labels after creating variables
    if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
      labelled::var_label(educ_df$educ_max) <- "Maximum education level among caregivers (8 categories)"
      labelled::var_label(educ_df$educ_a1) <- "Primary caregiver education level (8 categories)"
      labelled::var_label(educ_df$educ_a2) <- "Secondary caregiver education level (8 categories)"
      labelled::var_label(educ_df$educ_mom) <- "Maternal education level (8 categories)"
      labelled::var_label(educ_df$educ4_max) <- "Maximum education level among caregivers (4 categories)"
      labelled::var_label(educ_df$educ4_a1) <- "Primary caregiver education level (4 categories)"
      labelled::var_label(educ_df$educ4_a2) <- "Secondary caregiver education level (4 categories)"
      labelled::var_label(educ_df$educ4_mom) <- "Maternal education level (4 categories)"
      labelled::var_label(educ_df$educ6_max) <- "Maximum education level among caregivers (6 categories)"
      labelled::var_label(educ_df$educ6_a1) <- "Primary caregiver education level (6 categories)"
      labelled::var_label(educ_df$educ6_a2) <- "Secondary caregiver education level (6 categories)"
      labelled::var_label(educ_df$educ6_mom) <- "Maternal education level (6 categories)"
    }

    recodes_df <- educ_df
  }

  if(what %in% c("geographic", "geography")) {
    #---------------------------------------------------------------------------
    # Geographic Variables: ZIP Code Crosswalks from DuckDB
    #
    # Queries 10 reference tables from DuckDB using hybrid Python→Feather→R
    # approach to avoid R DuckDB segmentation faults. Creates 27 derived
    # variables with semicolon-separated multi-value format to preserve all
    # geographic associations (e.g., ZIP codes spanning multiple counties).
    #
    # Output Variables (27):
    #   PUMA: puma, puma_afact
    #   County: county, county_name, county_afact
    #   Census Tract: tract, tract_afact
    #   CBSA: cbsa, cbsa_name, cbsa_afact
    #   Urban/Rural: urban_rural, urban_rural_afact, urban_pct
    #   School District: school_dist, school_name, school_afact
    #   State Legislative Lower: sldl, sldl_afact
    #   State Legislative Upper: sldu, sldu_afact
    #   Congressional District: congress_dist, congress_afact
    #   Native Lands (AIANNH): aiannh_code, aiannh_name, aiannh_afact
    #
    # Database Tables: geo_zip_to_* (10 tables, 126K rows)
    #   Loaded via: pipelines/python/load_geo_crosswalks_sql.py
    #   Query utility: R/utils/query_geo_crosswalk.R
    #
    # Allocation Factors: For ZIPs spanning multiple geographies, all assignments
    #   are preserved in semicolon-separated format, ordered by descending afact.
    #   Example: ZIP 68007 → PUMA "00901; 00701" with afact "0.9866; 0.0134"
    #
    # Documentation: See CLAUDE.md → "Geographic Crosswalk System"
    #---------------------------------------------------------------------------

    # Source the database query utility function
    source("R/utils/query_geo_crosswalk.R")

    # Query ZIP to PUMA crosswalk from database
    zip_puma_raw <- query_geo_crosswalk("geo_zip_to_puma")
    if (is.null(zip_puma_raw)) {
      warning("Failed to load PUMA crosswalk from database")
      return(NULL)
    }

    zip_puma_crosswalk <- zip_puma_raw %>%
      dplyr::select(zcta, puma22, afact) %>%
      dplyr::rename(zip = zcta, puma = puma22, puma_afact = afact) %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(puma_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        puma = paste(puma, collapse = "; "),
        puma_afact = paste(puma_afact, collapse = "; "),
        .groups = "drop"
      )

    # Query ZIP to County crosswalk from database
    zip_county_raw <- query_geo_crosswalk("geo_zip_to_county")
    zip_county_crosswalk <- zip_county_raw %>%
      dplyr::select(zcta, county, CountyName, afact) %>%
      dplyr::rename(zip = zcta, county_afact = afact) %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(county_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        county = paste(county, collapse = "; "),
        county_name = paste(CountyName, collapse = "; "),
        county_afact = paste(county_afact, collapse = "; "),
        .groups = "drop"
      )

    # Query ZIP to Census Tract crosswalk from database
    zip_tract_raw <- query_geo_crosswalk("geo_zip_to_tract")
    zip_tract_crosswalk <- zip_tract_raw %>%
      dplyr::select(zcta, county, tract, afact) %>%
      dplyr::mutate(
        # Create full tract FIPS (county + tract)
        tract_fips = paste0(county, tract)
      ) %>%
      dplyr::rename(zip = zcta, tract_afact = afact) %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(tract_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        tract = paste(tract_fips, collapse = "; "),
        tract_afact = paste(tract_afact, collapse = "; "),
        .groups = "drop"
      )

    # Query ZIP to CBSA crosswalk from database
    zip_cbsa_raw <- query_geo_crosswalk("geo_zip_to_cbsa")
    zip_cbsa_crosswalk <- zip_cbsa_raw %>%
      dplyr::select(zcta, cbsa20, CBSAName20, afact) %>%
      dplyr::rename(zip = zcta, cbsa = cbsa20, cbsa_name = CBSAName20, cbsa_afact = afact) %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(cbsa_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        cbsa = paste(cbsa, collapse = "; "),
        cbsa_name = paste(cbsa_name, collapse = "; "),
        cbsa_afact = paste(cbsa_afact, collapse = "; "),
        .groups = "drop"
      )

    # Query ZIP to Urban/Rural crosswalk from database
    zip_ur_raw <- query_geo_crosswalk("geo_zip_to_urban_rural") %>%
      dplyr::select(zcta, ur, pop20, afact) %>%
      dplyr::rename(zip = zcta, urban_rural_code = ur, ur_pop = pop20, ur_afact = afact) %>%
      dplyr::mutate(ur_afact = as.numeric(ur_afact))

    # Calculate urban percentage for each ZIP (sum of afact where code is "U")
    urban_only <- zip_ur_raw %>% dplyr::filter(urban_rural_code == "U")
    zip_urban_pct <- aggregate(ur_afact ~ zip, data = urban_only, FUN = function(x) sum(x) * 100)
    names(zip_urban_pct)[2] <- "urban_pct"

    # Create semicolon-separated strings for urban/rural codes and allocation factors
    zip_ur_crosswalk <- zip_ur_raw %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(ur_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        urban_rural = paste(urban_rural_code, collapse = "; "),
        urban_rural_afact = paste(ur_afact, collapse = "; "),
        .groups = "drop"
      ) %>%
      dplyr::left_join(zip_urban_pct, by = "zip") %>%
      dplyr::mutate(
        # If no urban rows exist for this ZIP, urban_pct should be 0
        urban_pct = dplyr::if_else(is.na(urban_pct), 0, urban_pct)
      )

    # Query ZIP to School District crosswalk from database
    zip_school_raw <- query_geo_crosswalk("geo_zip_to_school_dist")
    zip_school_crosswalk <- zip_school_raw %>%
      dplyr::select(zcta, sdbest20, bschlnm20, afact) %>%
      dplyr::rename(zip = zcta, school_dist = sdbest20, school_name = bschlnm20, school_afact = afact) %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(school_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        school_dist = paste(school_dist, collapse = "; "),
        school_name = paste(school_name, collapse = "; "),
        school_afact = paste(school_afact, collapse = "; "),
        .groups = "drop"
      )

    # Query ZIP to State Legislative District (Lower) crosswalk from database
    zip_sldl_raw <- query_geo_crosswalk("geo_zip_to_state_leg_lower")
    zip_sldl_crosswalk <- zip_sldl_raw %>%
      dplyr::select(zcta, sldl24, afact) %>%
      dplyr::rename(zip = zcta, sldl = sldl24, sldl_afact = afact) %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(sldl_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        sldl = paste(sldl, collapse = "; "),
        sldl_afact = paste(sldl_afact, collapse = "; "),
        .groups = "drop"
      )

    # Query ZIP to State Legislative District (Upper) crosswalk from database
    zip_sldu_raw <- query_geo_crosswalk("geo_zip_to_state_leg_upper")
    zip_sldu_crosswalk <- zip_sldu_raw %>%
      dplyr::select(zcta, sldu24, afact) %>%
      dplyr::rename(zip = zcta, sldu = sldu24, sldu_afact = afact) %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(sldu_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        sldu = paste(sldu, collapse = "; "),
        sldu_afact = paste(sldu_afact, collapse = "; "),
        .groups = "drop"
      )

    # Query ZIP to US Congressional District crosswalk from database
    zip_congress_raw <- query_geo_crosswalk("geo_zip_to_congress")
    zip_congress_crosswalk <- zip_congress_raw %>%
      dplyr::select(zcta, cd119, afact) %>%
      dplyr::rename(zip = zcta, congress_dist = cd119, congress_afact = afact) %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(congress_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        congress_dist = paste(congress_dist, collapse = "; "),
        congress_afact = paste(congress_afact, collapse = "; "),
        .groups = "drop"
      )

    # Query ZIP to Native Lands (AIANNH) crosswalk from database
    # Note: Most ZIPs will have blank/NA values (not on tribal lands)
    zip_aiannh_raw <- query_geo_crosswalk("geo_zip_to_native_lands")
    zip_aiannh_crosswalk <- zip_aiannh_raw %>%
      dplyr::select(zcta, aiannh, aiannhName, afact) %>%
      dplyr::rename(zip = zcta, aiannh_code = aiannh, aiannh_name = aiannhName, aiannh_afact = afact) %>%
      # Filter out blank/missing AIANNH values
      dplyr::filter(!is.na(aiannh_code) & stringr::str_trim(aiannh_code) != "") %>%
      dplyr::group_by(zip) %>%
      dplyr::arrange(dplyr::desc(aiannh_afact), .by_group = TRUE) %>%
      dplyr::summarise(
        aiannh_code = paste(aiannh_code, collapse = "; "),
        aiannh_name = paste(aiannh_name, collapse = "; "),
        aiannh_afact = paste(aiannh_afact, collapse = "; "),
        .groups = "drop"
      )

    # Join all geographic data to participant data using sq001 (ZIP code)
    geographic_df <- dat %>%
      dplyr::select(pid, record_id, sq001) %>%
      dplyr::mutate(
        # Clean ZIP code: remove spaces, convert to 5-digit string
        zip_clean = stringr::str_trim(as.character(sq001)),
        zip_clean = stringr::str_pad(zip_clean, width = 5, side = "left", pad = "0")
      ) %>%
      dplyr::left_join(zip_puma_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_county_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_tract_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_cbsa_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_ur_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_school_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_sldl_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_sldu_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_congress_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::left_join(zip_aiannh_crosswalk, by = c("zip_clean" = "zip")) %>%
      dplyr::select(pid, record_id,
                   puma, puma_afact,
                   county, county_name, county_afact,
                   tract, tract_afact,
                   cbsa, cbsa_name, cbsa_afact,
                   urban_rural, urban_rural_afact, urban_pct,
                   school_dist, school_name, school_afact,
                   sldl, sldl_afact,
                   sldu, sldu_afact,
                   congress_dist, congress_afact,
                   aiannh_code, aiannh_name, aiannh_afact)

    # Add labels after creating variables
    if(add_labels && requireNamespace("labelled", quietly = TRUE)) {
      labelled::var_label(geographic_df$puma) <- "Public Use Microdata Area(s) - semicolon-separated if ZIP spans multiple PUMAs (2020 Census)"
      labelled::var_label(geographic_df$puma_afact) <- "ZIP to PUMA allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$county) <- "County FIPS code(s) - semicolon-separated if ZIP spans multiple counties"
      labelled::var_label(geographic_df$county_name) <- "County name(s) - semicolon-separated if ZIP spans multiple counties"
      labelled::var_label(geographic_df$county_afact) <- "ZIP to county allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$tract) <- "Census tract FIPS code(s) - semicolon-separated if ZIP spans multiple tracts"
      labelled::var_label(geographic_df$tract_afact) <- "ZIP to census tract allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$cbsa) <- "Core-Based Statistical Area code(s) - semicolon-separated if ZIP spans multiple CBSAs"
      labelled::var_label(geographic_df$cbsa_name) <- "CBSA name(s) - semicolon-separated if ZIP spans multiple CBSAs"
      labelled::var_label(geographic_df$cbsa_afact) <- "ZIP to CBSA allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$urban_rural) <- "Urban/Rural classification(s) (U=Urban, R=Rural) - semicolon-separated if ZIP is mixed (2022 Census)"
      labelled::var_label(geographic_df$urban_rural_afact) <- "Urban/Rural allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$urban_pct) <- "Percentage of ZIP population in urban areas (0-100)"
      labelled::var_label(geographic_df$school_dist) <- "School district code(s) - semicolon-separated if ZIP spans multiple districts (2020)"
      labelled::var_label(geographic_df$school_name) <- "School district name(s) - semicolon-separated if ZIP spans multiple districts"
      labelled::var_label(geographic_df$school_afact) <- "ZIP to school district allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$sldl) <- "State legislative district (lower/house) code(s) - semicolon-separated if ZIP spans multiple districts (2024)"
      labelled::var_label(geographic_df$sldl_afact) <- "ZIP to state leg lower allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$sldu) <- "State legislative district (upper/senate) code(s) - semicolon-separated if ZIP spans multiple districts (2024)"
      labelled::var_label(geographic_df$sldu_afact) <- "ZIP to state leg upper allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$congress_dist) <- "US Congressional district code(s) - semicolon-separated if ZIP spans multiple districts (119th Congress)"
      labelled::var_label(geographic_df$congress_afact) <- "ZIP to congressional district allocation factor(s) - semicolon-separated, ordered by likelihood"
      labelled::var_label(geographic_df$aiannh_code) <- "Native lands (AIANNH) code(s) - semicolon-separated if ZIP spans multiple areas (2021)"
      labelled::var_label(geographic_df$aiannh_name) <- "Native lands (AIANNH) name(s) - semicolon-separated if ZIP spans multiple areas"
      labelled::var_label(geographic_df$aiannh_afact) <- "ZIP to AIANNH allocation factor(s) - semicolon-separated, ordered by likelihood"
    }

    recodes_df <- geographic_df
  }

  return(recodes_df)
}

# Master transformation function that applies all transformations
recode_it <- function(dat, dict, my_API = NULL, what = "all") {
  if(what == "all") {
    vars <- c("include", "race", "caregiver relationship", "education", "sex", "age", "income", "geographic")
  } else {
    vars <- what
  }

  recoded_dat <- dat
  for(v in vars) {
    message(paste("Processing transformation:", v))

    tryCatch({
      recode_result <- recode__(dat = dat, dict = dict, my_API = my_API, what = v)
      if(!is.null(recode_result)) {
        recoded_dat <- recoded_dat %>%
          dplyr::left_join(recode_result, by = c("pid", "record_id"))
      }
    }, error = function(e) {
      message(paste("Warning: Failed to process", v, ":", e$message))
    })
  }

  return(recoded_dat)
}
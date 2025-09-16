# NE25 Data Transformation Functions
# Ported from Kidsights Dashboard utils-etl.R

# Helper function to get value labels from REDCap dictionary
value_labels <- function(lex, dict, varname = "lex_ne25") {
  # Note issue in education labels due to commas in description
  tmp <- dict[[lex]]$select_choices_or_calculations %>%
    stringr::str_split_1(" \\| ")

  outdf <- data.frame(value = rep(NA, length(tmp)), label = NA)

  for(i in 1:length(tmp)) {
    tmp_i <- tmp[i] %>% stringr::str_split_1(", ")
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
        relation1 = plyr::mapvalues(cqr008, from = value_labels(lex = "cqr008", dict = dict)$value, to = value_labels(lex = "cqr008", dict = dict)$label, warn_missing = F),
        relation2 = plyr::mapvalues(nschj013, from = value_labels(lex = "nschj013", dict = dict)$value, to = value_labels(lex = "nschj013", dict = dict)$label, warn_missing = F),
        female_a1 = as.logical(cqr002 == 0),
        mom_a1 = as.logical(relation1 == value_labels(lex = "cqr008", dict = dict)$label[1] & female_a1)
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
        sex = plyr::mapvalues(cqr009, from = value_labels(lex = "cqr009", dict = dict)$value, to = value_labels(lex = "cqr009", dict = dict)$label, warn_missing = F),
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

    simple_educ_label <- data.frame(
      educ = value_labels(lex = "cqr004", dict = dict)$label) %>%
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

  return(recodes_df)
}

# Master transformation function that applies all transformations
recode_it <- function(dat, dict, my_API = NULL, what = "all") {
  if(what == "all") {
    vars <- c("include", "race", "caregiver relationship", "education", "sex", "age", "income")
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
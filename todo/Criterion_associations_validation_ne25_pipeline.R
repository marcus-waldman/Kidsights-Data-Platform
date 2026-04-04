library(duckdb)
library(DBI)
library(dplyr)

con <- DBI::dbConnect(duckdb::duckdb(), "data/duckdb/kidsights_local.duckdb")

ne25_data <- dplyr::tbl(con, "ne25_transformed") %>%
  dplyr::collect()

DBI::dbDisconnect(con)


library(ggplot2)
library(mice)

dat = ne25_data %>%
  dplyr::filter(meets_inclusion) %>% 
  dplyr::select(
    calibrated_weight, 
    kidsights_2022,
    general_gsed_pf_2022,
    female, 
    years_old, 
    phq2_total, 
    fpl, 
    urban_pct, 
    educ4_a1
  ) %>% 
  mice(method = "cart", m = 1) %>% 
  complete(1)


# Kidsights score: Overall summary flipped gradients with earlty adversity demonstrating higher scores but then trends reversing in later years. 
#Income
fit = lm(kidsights_2022~log(years_old+1) + female*years_old + log(fpl+1)*years_old, data = dat, weights = dat$calibrated_weight)
summary(fit)
#Education
fit = lm(kidsights_2022~log(years_old+1) + female*years_old + educ4_a1*years_old, data = dat, weights = dat$calibrated_weight)
summary(fit)
#Urbanicity
fit = lm(kidsights_2022~log(years_old+1) + female*years_old + urban_pct*years_old, data = dat, weights = dat$calibrated_weight)
summary(fit)
#Depression
fit = lm(kidsights_2022~log(years_old+1) + female*years_old + phq2_total*years_old, data = dat, weights = dat$calibrated_weight)
summary(fit)



# Psychosocial score: Overall summary flipped gradients with earlty adversity demonstrating higher scores but then trends reversing in later years. 
#Income #
fit = lm(general_gsed_pf_2022~female*years_old + log(fpl+1)*years_old, data = dat, weights = dat$calibrated_weight)
summary(fit)
#Education
fit = lm(general_gsed_pf_2022~female*years_old + educ4_a1*years_old, data = dat, weights = dat$calibrated_weight)
summary(fit)
#Urbanicity
fit = lm(general_gsed_pf_2022~female*years_old + urban_pct*years_old, data = dat, weights = dat$calibrated_weight)
summary(fit)
#Depression
fit = lm(general_gsed_pf_2022~female*years_old + phq2_total*years_old, data = dat, weights = dat$calibrated_weight)
summary(fit)

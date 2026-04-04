# rawdat = raw22
# itemdict = get_itemdict22(verbose=F)
# coding_tholds = readxl::read_xlsx("datasets/intermediate/HRTL-2022-Scoring-Thresholds.xlsx") %>% 
#   dplyr::mutate(lex_ifa = paste0("y22_",stringr::str_remove(as.character(jid),".22")))

hrtl_scoring_2022<-function(rawdat, itemdict, coding_tholds){

  # Initialize domain summary cutscores  (See Ghandhour 2021)
  cutscore_22 = 2.5
  
  dat = rawdat %>%
    dplyr::filter(SC_AGE_YEARS==3 | SC_AGE_YEARS==4 |SC_AGE_YEARS==5)
  #nrow(dat) #11,121 -- Matches Ghandour (2021)
   
  # Recode HHRTL items into IFA coding 
  ifadat = dplyr::bind_cols(dat %>% dplyr::select(HHID,SC_AGE_YEARS), recode_cahmi2ifa(inputdat=dat, itemdict=itemdict))
  

  # Code individual items into 3-point scale based on age gradients (see Ghandour 2024 )
  longdat = ifadat %>% 
    tidyr::pivot_longer(starts_with("y22_"), names_to = "lex_ifa", values_to = "y") %>% 
    dplyr::left_join(itemdict %>% dplyr::select(lex_ifa,domain_2022), by = "lex_ifa") %>% 
    dplyr::filter(!is.na(domain_2022)) %>% 
    dplyr::left_join(coding_tholds %>% dplyr::select(lex_ifa, SC_AGE_YEARS, on_track, emerging), by = c("SC_AGE_YEARS","lex_ifa")) %>% 
    dplyr::mutate(code_hrtl22 = ifelse(is.na(y),NA,1))  #Score of 1 is needs support(Ghandour, 2024)
  longdat$code_hrtl22[longdat$y>=longdat$emerging] = 2 #Score of 2 is "emergin
  longdat$code_hrtl22[longdat$y>=longdat$on_track] = 3 # Score of 3 is on-track
  
  # Create a sum-score by domain from the 3-point scoring scheme above (see Ghandour 2024)
  summdat = longdat %>% 
    dplyr::group_by(HHID,domain_2022) %>% 
    dplyr::summarise(avg_score = mean(code_hrtl22, na.rm = T))
  summdat$avg_score[is.nan(summdat$avg_score)] = NA
  
  # Classify as on track (2), needs support (1), or Needs Support (0) for each domain (see Ghandour 2019)
  summdat = summdat %>% dplyr::mutate(index_cat = NA)
  summdat$index_cat[summdat$avg_score<2] = 1
  summdat$index_cat[summdat$avg_score>=2] = 2
  summdat$index_cat[summdat$avg_score>=2.5] = 3
  summdat = summdat %>% dplyr::mutate(code = ordered(index_cat, levels = c(1,2,3), labels = c("Needs Support", "Emerging", "On-Track")))
  
  summdat = summdat %>% dplyr::ungroup() %>% dplyr::select(HHID, domain_2022, code)
  
  # make an overall determination
  determine_hrtl = summdat %>% dplyr::ungroup() %>% dplyr::group_by(HHID) %>% dplyr::summarise(n_on_track = sum(code=="On-Track"), n_needs_support = sum(code=="Needs Support")) %>% 
    dplyr::mutate(hrtl = (n_on_track>=4 & n_needs_support==0) ) # "Children “on track” in 4 to 5 domains with no domain that “needs support” were considered HRTL, forming the definition for the Title V National Outcome Measure for School Readiness." (Ghandour, 2024, p. 2)
  
  return(
    list(
      overall = determine_hrtl %>% 
                    dplyr::left_join(dat %>% dplyr::select(HHID,FWC), by = "HHID") %>% 
                    dplyr::mutate(across(everything(), zap_all)), 
      by_domain = summdat %>% 
                    dplyr::left_join(dat %>% dplyr::select(HHID,FWC), by = "HHID") %>% 
                    dplyr::mutate(across(everything(), zap_all))
    )
  )
}
recode_it<-function(rawdat, year, lex, var_cahmi, reverse=F, reverse_in_mplus=F, force_value_missing = NULL) {
  
  rawdat%>% 
    dplyr::select(HHID, FWC, SC_AGE_YEARS) %>% 
    dplyr::mutate(year = year) %>% 
    dplyr::relocate(year) %>% 
    dplyr::bind_cols(
      rawdat %>% 
        recode_cahmi2ifa(inputdat = ., 
                         itemdict = 
                           tibble(var_cahmi = var_cahmi, 
                                  values_map = list( get_cahmi_values_map(rawdat = rawdat, var = var_cahmi, reverse=reverse, reverse_in_mplus=reverse_in_mplus, force_value_missing = force_value_missing) ),
                                  lex_ifa = lex
                           )
        ) #end recode_cahmi2ifa
    ) %>%  #End bind_cols
    return()
}



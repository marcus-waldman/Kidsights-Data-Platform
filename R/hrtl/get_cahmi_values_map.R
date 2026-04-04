get_cahmi_values_map <- function(rawdat, var, reverse, reverse_in_mplus=F, force_value_missing = NULL){
  
  
  #Input: 
    # rawdat - data.frame of raw CAHMI dataset
    # var -  string indicating the variable inside the CAHMI dataset
  
  #Output: 
    # data.frame that maps variable values in raw format to format that allows for item factor analysis.
  

  require(tidyverse)
  require(sjlabelled)
  require(purrr)
  
  
  values_map = data.frame(labels = sjlabelled::get_labels(rawdat %>% purrr::pluck(var)), 
                          values_raw = sjlabelled::get_values(rawdat %>% purrr::pluck(var))
                          ) %>% 
    dplyr::mutate(dv = c(1,diff(values_raw)), 
                  values_ifa = NA)
  if(!identical(unique(values_map$dv),1)){
    idx = seq(1,min(which(values_map$dv!=1))-1)
    if(!is.null(force_value_missing)){
      idx = setdiff(idx, which(values_map$values_raw%in%force_value_missing))
    }
  } else {
    idx = 1:nrow(values_map)
  }
  values_map$values_ifa[idx] = values_map$values_raw[idx]-1
  values_map = values_map %>% dplyr::select(labels,values_raw, values_ifa)
  
  # Reverse code items, as appropriate
  if(reverse){
    values_map$values_ifa = with(values_map, plyr::mapvalues(values_ifa, from = values_ifa %>% na.omit(), to = sort(values_ifa, decreasing = T)))
  }
  
  # If raw variable statrted at zero, it will produce a negative number. Subtract off this smallest negative to start at zero.
  values_map$values_ifa = values_map$values_ifa - min(values_map$values_ifa, na.rm = T)
  
  # Get an mplus codes
  values_map$values_mplus = values_map$values_ifa
  if(reverse_in_mplus){values_map$values_mplus = with(values_map, abs(values_ifa-max(values_ifa, na.rm = T)))}
  
  
  return(values_map)
  
}



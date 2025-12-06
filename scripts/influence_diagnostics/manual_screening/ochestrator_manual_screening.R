library(tidyverse)
library(MplusAutomation)

source("scripts/authenticity_screening/manual_screening/00_load_item_response_data.R")

# Obtain wide item response dataset
out_list_00<-load_stage1_data()
wide_dat = out_list_00$wide_data
person_dat = out_list_00$person_data


get_itemdict22<-function(raw22, verbose = T){
  
  
  # Obtain HRTL survey questions 
  itemdict22 = tibble(year = 2022,
                      jid = seq(1,9+6+5+4+3+1, by = 1)+.22,
                      domain_2016 = c(
                        rep("Early Learning Skills", 9),
                        rep("Social-Emotional Development", 6), 
                        rep("Self-Regulation", 5), 
                        rep("Physical Health and Motor Development", 7), 
                        rep("Social-Emotional Development")
                      ) %>% as.factor(),
                      domain_2022 = c(
                        rep("Early Learning Skills", 9),
                        rep("Social-Emotional Development", 6), 
                        rep("Self-Regulation", 5), 
                        rep("Motor Development", 4), 
                        rep("Health",3), 
                        NA
                      ) %>% as.factor(), 
                      var_cahmi = c(
                        "RecogBegin_22", 
                        "SameSound_22", 
                        "RhymeWordR_22", 
                        "RecogLetter_22", 
                        "WriteName_22", 
                        "ReadOneDigit_22", 
                        "COUNTTO_R",
                        "GroupOfObjects_22",
                        "SimpleAddition_22", 
                        "ClearExp_22", 
                        "NameEmotions_22", 
                        "ShareToys_22", 
                        "PlayWell_22", 
                        "HurtSad_22", 
                        "FocusOn_22",
                        "StartNewAct_22", 
                        "CalmDownR_22", 
                        "WaitForTurn_22", 
                        "distracted_22", 
                        "temperR_22", 
                        "DrawCircle_22", 
                        "DrawFace_22", 
                        "DrawPerson_22", 
                        "BounceBall_22", 
                        "K2Q01", 
                        "K2Q01_D", 
                        "DailyAct_22", 
                        "K6Q73_R" 
                      ), 
                      lex_ifa = paste0("y22_",1:length(jid)),
                      stem = c(
                        "How often can this child recognize the beginning sound of a word (e.g., 'ball' starts with 'buh' sound)?",
                        "How often can this child come up with words that start with the same sound (e.g., 'sock' and 'sun')?",
                        "How well can this child come up with words that rhyme (e.g., 'cat' and 'mat')?", 
                        "About how many letters of the alphabet can this child recognize?", 
                        "How often can this child write their first name, even if some of the letters aren't quite right or are backwards?", 
                        "How often can this child read one-digit numbers (e.g., 2 or 8)?", 
                        "If asked to count objects, how can can this child count correctly?", 
                        "How often can this child tell which group of objects has more (e.g., group of 7 blocks has more than groups of 4)?", 
                        "How often can this child correctly do simple addition (e.g., 2 blocks and 3 blocks add to 5 blocks)?",
                        "How often can this child explain things they have seen or done so that you know what happened?",
                        "How often can this child recognize and name their own emotions?", 
                        "How often does this child share toys or games with other children?", 
                        "How often does this child play well with other children?", 
                        "How often does this child show concern when they see others who are hurt or unhappy?", 
                        "How often can this child focus on a task you give them for at least a few minutes?", 
                        "How often does this child have difficulty when asked to end one activity and start a new activity?", 
                        "How often does this child have trouble calming down?", 
                        "How often does this child have difficulty waiting for their turn?", 
                        "How often does this child get easily distracted?", 
                        "How often does this child lose their temper?", 
                        "How well can this child draw a circle?", 
                        "How well can this child draw a face or eyes and mouth?", 
                        "How well can this child draw a person with a head, body, arms, and legs?", 
                        "How well can this child bounce a ball for several seconds?", 
                        "In general how would describe this child's health?", 
                        "How would you describe the condition of this child's teeth?", 
                        "DURING THE PAST 12 MONTHS, how often have this child's health conditions or problems affected their ability to do things other children their age can do? AND To what extend do this child's health conditions or porblems affect their ability to do things?", 
                        "This child bounces back quickly when things do not go his or her way?"
                      )
                      
  ) 
  
  # Get the reverse coded items
  items22_reverse= c(1.22, 2.22, 4.22, 5.22, 6.22, 8.22, 9.22, 10.22, 11.22, 12.22, 13.22, 14.22, 15.22, 25.22, 26.22, 27.22, 28.22)
  itemdict22 = itemdict22 %>% 
    dplyr::mutate(
      reverse_coded = ifelse(jid %in% items22_reverse, TRUE, FALSE), 
      reverse_only_in_mplus = (startsWith(var_cahmi, "DailyAct"))
    )
  
  
  # Get a values mapping crosswalk to go from raw responses to one that can be analyzed
  for(j in 1:length(itemdict22$var_cahmi)){
    var_j = itemdict22$var_cahmi[j]
    force_missing = NULL
    if(var_j=="K2Q01_D"){
      force_missing = 6
    }
    itemdict22$values_map[[j]] = get_cahmi_values_map(raw22,var_j, 
                                                      itemdict22$reverse_coded[j], 
                                                      itemdict22$reverse_only_in_mplus[j],
                                                      force_missing)
  }
  #
  
  # Print out recoding to to assess correctness
  if(verbose){
    (cat("Recoding Map: CAHMI 2022"))
    (cat("\n-----------------------"))
    for(j in 1:nrow(itemdict22)){
      (cat(" \n"))
      (cat(" \n"))
      (cat(paste0(itemdict22$jid[j], ") ", itemdict22$var_cahmi[j]), ": ", itemdict22$stem[j], sep = ""))
      (cat("\n"))
      print(itemdict22$values_map[[j]])
    }
  }
  
  
  return(itemdict22)
  

}
# NE25 Data Dictionary

**Generated:** 2025-12-09 18:17:57  
**Total Records:** 4966  
**Total Variables:** 660  
**Categories:** 16  

## Overview

This data dictionary describes all variables in the NE25 transformed dataset. 
The data comes from REDCap surveys and has been processed through the Kidsights 
data transformation pipeline, which applies standardized harmonization rules 
for race/ethnicity, education categories, and other demographic variables.

## Table of Contents

- [Race](#race) (6 variables)
- [Caregiver Relationship](#caregiver-relationship) (4 variables)
- [Education](#education) (13 variables)
- [Sex](#sex) (3 variables)
- [Age](#age) (7 variables)
- [Income](#income) (6 variables)
- [Adverse_Experiences](#adverse_experiences) (32 variables)
- [Childcare](#childcare) (21 variables)
- [Coglan](#coglan) (79 variables)
- [Eligibility](#eligibility) (1 variables)
- [Geography](#geography) (4 variables)
- [Mental_Health](#mental_health) (10 variables)
- [Motor](#motor) (74 variables)
- [Other](#other) (329 variables)
- [Psychosocial_Problems_General](#psychosocial_problems_general) (16 variables)
- [Socemo](#socemo) (55 variables)

## Race

**Description:** Race and ethnicity variables for children and primary caregivers, including harmonized categories

**Variables:** 6  
**Average Missing:** 40.1%  
**Data Types:** 6 factors, 0 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `a1_hisp` | Primary caregiver Hispanic/Latino ethnicity | factor | 40.8% | 1 (Hispanic), 2 (non-Hisp.) |
| `a1_race` | Primary caregiver race (collapsed categories) | factor | 40.2% | 1 (American Indian or Alaska Native), 2 (Asian or Pacific Islander), 3 (Black or African American), 4 (Other Asian), 5 (Some Other Race)... |
| `a1_raceG` | Primary caregiver race/ethnicity combined | factor | 40.8% | 1 (American Indian or Alaska Native, non-Hisp.), 2 (Asian or Pacific Islander, non-Hisp.), 3 (Black or African American, non-Hisp.), 4 (Hispanic), 5 (Some Other Race, non-Hisp.)... |
| `hisp` | Child Hispanic/Latino ethnicity | factor | 39.9% | 1 (Hispanic), 2 (non-Hisp.) |
| `race` | Child race (collapsed categories) | factor | 39.1% | 1 (American Indian or Alaska Native), 2 (Asian or Pacific Islander), 3 (Black or African American), 4 (Other Asian), 5 (Some Other Race)... |
| `raceG` | Child race/ethnicity combined | factor | 39.9% | 1 (American Indian or Alaska Native, non-Hisp.), 2 (Asian or Pacific Islander, non-Hisp.), 3 (Black or African American, non-Hisp.), 4 (Hispanic), 5 (Some Other Race, non-Hisp.)... |

## Caregiver Relationship

**Description:** Variables describing relationships between caregivers and children, including gender and maternal status

**Variables:** 4  
**Average Missing:** 33.6%  
**Data Types:** 2 factors, 1 numeric, 0 logical, 1 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `module_7_child_emotions_and_relationships_complete` | Module 7 Child Emotions And Relationships Complete | numeric | 0.0% | N/A |
| `module_7_child_emotions_and_relationships_timestamp` | Module 7 Child Emotions And Relationships Timestamp | character | 46.8% | N/A |
| `relation1` | Relation1 | factor | 36.1% | 1 (Biological or Adoptive Parent), 2 (Foster Parent), 3 (Grandparent), 4 (Other: Non-Relative), 5 (Other: Relative)... |
| `relation2` | Relation2 | factor | 51.2% | 1 (Biological or Adoptive Parent), 2 (Foster Parent), 3 (Grandparent), 4 (Other: Non-Relative), 5 (Other: Relative)... |

## Education

**Description:** Education level variables using multiple categorization systems (4, 6, and 8 categories)

**Variables:** 13  
**Average Missing:** 43.7%  
**Data Types:** 12 factors, 0 numeric, 1 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `educ4_a1` | Primary caregiver education level (4 categories) | factor | 35.7% | 1 (Less than High School Graduate), 2 (High School Graduate (including Equivalency)), 3 (Some College or Associate's Degree), 4 (College Degree) |
| `educ4_a2` | Secondary caregiver education level (4 categories) | factor | 51.4% | 1 (Less than High School Graduate), 2 (High School Graduate (including Equivalency)), 3 (Some College or Associate's Degree), 4 (College Degree) |
| `educ4_max` | Maximum education level among caregivers (4 categories) | factor | 35.4% | 1 (Less than High School Graduate), 2 (High School Graduate (including Equivalency)), 3 (Some College or Associate's Degree), 4 (College Degree) |
| `educ4_mom` | Maternal education level (4 categories) | factor | 55.0% | 1 (Less than High School Graduate), 2 (High School Graduate (including Equivalency)), 3 (Some College or Associate's Degree), 4 (College Degree) |
| `educ6_a1` | Primary caregiver education level (6 categories) | factor | 35.7% | 1 (Less than High School Graduate), 2 (High School Graduate (including Equivalency)), 3 (Some College or Associate's Degree), 4 (Bachelor's Degree), 5 (Master's Degree)... |
| `educ6_a2` | Secondary caregiver education level (6 categories) | factor | 51.4% | 1 (Less than High School Graduate), 2 (High School Graduate (including Equivalency)), 3 (Some College or Associate's Degree), 4 (Bachelor's Degree), 5 (Master's Degree)... |
| `educ6_max` | Maximum education level among caregivers (6 categories) | factor | 35.4% | 1 (Less than High School Graduate), 2 (High School Graduate (including Equivalency)), 3 (Some College or Associate's Degree), 4 (Bachelor's Degree), 5 (Master's Degree)... |
| `educ6_mom` | Maternal education level (6 categories) | factor | 55.0% | 1 (Less than High School Graduate), 2 (High School Graduate (including Equivalency)), 3 (Some College or Associate's Degree), 4 (Master's Degree), 5 (Doctorate or Professional Degree)... |
| `educ_a1` | Primary caregiver education level (8 categories) | factor | 35.7% | 1 (Bachelor's Degree (BA, BS, AB)), 2 (Master's Degree (MA, MS, MSW, MBA)), 3 (High School Graduate or GED Completed), 4 (Some College Credit, but No Degree), 5 (Associate Degree (AA, AS))... |
| `educ_a2` | Secondary caregiver education level (8 categories) | factor | 51.4% | 1 (Bachelor's Degree (BA, BS, AB)), 2 (High School Graduate or GED Completed), 3 (Master's Degree (MA, MS, MSW, MBA)), 4 (Some College Credit, but No Degree), 5 (Associate Degree (AA, AS))... |
| `educ_max` | Maximum education level among caregivers (8 categories) | factor | 35.4% | 1 (Bachelor's Degree (BA, BS, AB)), 2 (Master's Degree (MA, MS, MSW, MBA)), 3 (High School Graduate or GED Completed), 4 (Some College Credit, but No Degree), 5 (Associate Degree (AA, AS))... |
| `educ_mom` | Maternal education level (8 categories) | factor | 55.0% | 1 (Master's Degree (MA, MS, MSW, MBA)), 2 (Doctorate (PhD, EdD) or Professional Degree (MD, DDS, DVM, JD)), 3 (Associate Degree (AA, AS)), 4 (Completed a vocational, trade, or business school program), 5 (Bachelor's Degree (BA, BS, AB))... |
| `mom_a1` | Mom A1 | logical | 36.3% | N/A |

## Sex

**Description:** Child's biological sex and gender indicator variables

**Variables:** 3  
**Average Missing:** 38.2%  
**Data Types:** 1 factors, 0 numeric, 2 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `female` | Female | logical | 39.4% | N/A |
| `female_a1` | Female A1 | logical | 35.8% | N/A |
| `sex` | Sex | factor | 39.4% | 1 (Female), 2 (Male) |

## Age

**Description:** Age variables for children and caregivers in different units (days, months, years)

**Variables:** 7  
**Average Missing:** 34.4%  
**Data Types:** 1 factors, 6 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `a1_years_old` | A1 Years Old | numeric | 36.8% | N/A |
| `age_in_days` | Age Calculator | numeric | 25.2% | N/A |
| `days_old` | Days Old | numeric | 25.2% | N/A |
| `language` | Language preference | factor | 3.4% | 1 (en), 2 (es) |
| `language_preference` | Language Preference | numeric | 100.0% | N/A |
| `months_old` | Months Old | numeric | 25.2% | N/A |
| `years_old` | Years Old | numeric | 25.2% | N/A |

## Income

**Description:** Household income, family size, and federal poverty level calculations

**Variables:** 6  
**Average Missing:** 31.6%  
**Data Types:** 2 factors, 4 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `family_size` | Family Size | numeric | 38.3% | N/A |
| `federal_poverty_threshold` | Federal Poverty Threshold | numeric | 38.5% | N/A |
| `fpl` | Fpl | numeric | 38.7% | N/A |
| `fpl_derivation_flag` | Fpl Derivation Flag | factor | 0.0% | 1 (guideline_2025), 2 (guideline_2025_family_9plus) |
| `fplcat` | Fplcat | factor | 38.7% | 1 (<100% FPL), 2 (100-199% FPL), 3 (200-299% FPL), 4 (300-399% FPL), 5 (400+% FPL) |
| `income` | Income | numeric | 35.4% | N/A |

## Adverse_Experiences

**Description:** No description available

**Variables:** 32  
**Average Missing:** 39.0%  
**Data Types:** 2 factors, 30 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `ace_domestic_violence` | ACE - Witnessed domestic violence between parents/adults | numeric | 38.7% | N/A |
| `ace_emotional_neglect` | ACE - Felt unloved or not special in family | numeric | 38.6% | N/A |
| `ace_incarceration` | ACE - Lived with someone who went to jail/prison | numeric | 38.2% | N/A |
| `ace_mental_illness` | ACE - Lived with someone with mental illness/depression/suicide | numeric | 38.0% | N/A |
| `ace_neglect` | ACE - Physical/emotional neglect during childhood | numeric | 37.9% | N/A |
| `ace_parent_loss` | ACE - Lost parent through divorce, abandonment, death | numeric | 37.6% | N/A |
| `ace_physical_abuse` | ACE - Experienced physical abuse from parent/adult | numeric | 38.8% | N/A |
| `ace_risk_cat` | ACE Risk Category - No ACEs (0), 1 ACE, 2-3 ACEs, 4+ ACEs (High Risk) | factor | 44.9% | 1 (1 ACE), 2 (2-3 ACEs), 3 (4+ ACEs), 4 (No ACEs) |
| `ace_sexual_abuse` | ACE - Experienced unwanted sexual contact | numeric | 38.8% | N/A |
| `ace_substance_use` | ACE - Lived with someone with alcohol/drug problems | numeric | 38.0% | N/A |
| `ace_total` | ACE Total Score (0-10) - Total count of adverse childhood experiences | numeric | 44.9% | N/A |
| `ace_verbal_abuse` | ACE - Experienced verbal/emotional abuse from parent/adult | numeric | 38.5% | N/A |
| `cace1` | Did you feel that you didn't have enough to eat, had to wear dirty clothes, or had no one to protect or take care of you? | numeric | 36.4% | N/A |
| `cace10` | Did you experience unwanted sexual contact, such as fondling or oral/anal/vaginal intercourse or penetration? | numeric | 36.7% | N/A |
| `cace2` | Did you lose a parent through divorce, abandonment, death, or other reason? | numeric | 36.5% | N/A |
| `cace3` | Did you live with anyone who was depressed, mentally ill, or attempted suicide? | numeric | 36.5% | N/A |
| `cace4` | Did you live with anyone who had a problem with drinking or using drugs, including prescription drugs? | numeric | 36.8% | N/A |
| `cace5` | Did your parents or adults in your home ever hit, punch, beat, or threaten to harm each other? | numeric | 36.8% | N/A |
| `cace6` | Did you live with anyone who went to jail or prison? | numeric | 36.8% | N/A |
| `cace7` | Did a parent or adult in your home ever swear at you, insult you, or put you down? | numeric | 36.8% | N/A |
| `cace8` | Did a parent or adult in your home ever hit, beat, kick, or physically hurt you in any way? | numeric | 37.0% | N/A |
| `cace9` | Did you feel that no one in your family loved you or thought you were special? | numeric | 36.8% | N/A |
| `child_ace_discrimination` | Child ACE - Child treated unfairly due to race/ethnicity | numeric | 40.1% | N/A |
| `child_ace_domestic_violence` | Child ACE - Child saw/heard parents or adults hit each other in home | numeric | 40.2% | N/A |
| `child_ace_mental_illness` | Child ACE - Child lived with someone mentally ill, suicidal, or severely depressed | numeric | 40.4% | N/A |
| `child_ace_neighborhood_violence` | Child ACE - Child was victim/witnessed violence in neighborhood | numeric | 40.3% | N/A |
| `child_ace_parent_death` | Child ACE - Child experienced parent/guardian death | numeric | 40.0% | N/A |
| `child_ace_parent_divorce` | Child ACE - Child experienced parent/guardian divorce or separation | numeric | 40.1% | N/A |
| `child_ace_parent_jail` | Child ACE - Child's parent/guardian served time in jail | numeric | 40.4% | N/A |
| `child_ace_risk_cat` | Child ACE Risk Category - No ACEs (0), 1 ACE, 2-3 ACEs, 4+ ACEs (High Risk) | factor | 42.6% | 1 (1 ACE), 2 (2-3 ACEs), 3 (4+ ACEs), 4 (No ACEs) |
| `child_ace_substance_use` | Child ACE - Child lived with someone with alcohol/drug problems | numeric | 40.4% | N/A |
| `child_ace_total` | Child ACE Total Score (0-8) - Total count of child's adverse childhood experiences | numeric | 42.6% | N/A |

## Childcare

**Description:** No description available

**Variables:** 21  
**Average Missing:** 64.2%  
**Data Types:** 15 factors, 6 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `cc_access_difficulty` | Difficulty finding child care (past 12 months) | factor | 39.2% | 1 (Did not need childcare), 2 (Missing), 3 (Not difficult), 4 (Somewhat difficult), 5 (Very difficult) |
| `cc_any_support` | Receives any child care financial support (family or subsidy) | factor | 0.0% | 1 (No), 2 (Yes) |
| `cc_difficulty_reason` | Main reason child care was difficult to find | factor | 89.0% | 1 (Cost too high), 2 (Hours not suitable), 3 (Location not convenient), 4 (Missing), 5 (No openings)... |
| `cc_family_support_all` | Weekly family financial support - all children ($) | numeric | 74.2% | N/A |
| `cc_family_support_child` | Weekly family financial support - this child ($) | numeric | 66.0% | N/A |
| `cc_financial_hardship` | Child care costs create financial hardship | factor | 73.4% | 1 (Missing), 2 (No), 3 (Yes) |
| `cc_formal_care` | Uses formal child care (center/preschool/Head Start) | factor | 71.5% | 1 (No), 2 (Yes) |
| `cc_hours_per_week` | Total hours in child care per week | numeric | 64.7% | N/A |
| `cc_intensity` | Child care intensity level (part-time/full-time/extended) | factor | 64.7% | 1 (Extended (>50 hrs)), 2 (Full-time (30-50 hrs)), 3 (Part-time (<30 hrs)) |
| `cc_nonstandard_hours` | Requires evening/weekend/overnight care | factor | 39.5% | 1 (Missing), 2 (No), 3 (Yes) |
| `cc_pays_multiple_children` | Pays for childcare for multiple children (10+ hrs/week) | factor | 39.1% | 1 (Missing), 2 (No), 3 (Yes) |
| `cc_primary_type` | Primary child care arrangement type | factor | 71.5% | 1 (Childcare center), 2 (Head Start/Early Head Start), 3 (Missing), 4 (Non-relative care), 5 (Other)... |
| `cc_quality_satisfaction` | Satisfaction with primary child care quality | factor | 65.2% | 1 (Dissatisfied), 2 (Missing), 3 (Neither), 4 (Satisfied), 5 (Very dissatisfied)... |
| `cc_receives_care` | Child receives non-parental care (10+ hours/week) | factor | 39.1% | 1 (Missing), 2 (No), 3 (Yes) |
| `cc_receives_subsidy` | Receives child care subsidy assistance | factor | 64.6% | 1 (Missing), 2 (No), 3 (Yes) |
| `cc_subsidy_sat_amount` | Satisfaction with subsidy amount | factor | 93.4% | 1 (Dissatisfied), 2 (Missing), 3 (Neither), 4 (Satisfied), 5 (Very dissatisfied)... |
| `cc_subsidy_sat_options` | Satisfaction with subsidy care options | factor | 93.5% | 1 (Dissatisfied), 2 (Missing), 3 (Neither), 4 (Satisfied), 5 (Very dissatisfied)... |
| `cc_subsidy_sat_process` | Satisfaction with subsidy application process | factor | 93.5% | 1 (Dissatisfied), 2 (Missing), 3 (Neither), 4 (Satisfied), 5 (Very dissatisfied)... |
| `cc_weekly_cost_all` | Weekly household child care costs - all children ($) | numeric | 74.3% | N/A |
| `cc_weekly_cost_primary` | Weekly cost - primary child care arrangement ($) | numeric | 65.7% | N/A |
| `cc_weekly_cost_total` | Weekly cost - all arrangements this child ($) | numeric | 66.0% | N/A |

## Coglan

**Description:** No description available

**Variables:** 79  
**Average Missing:** 91.8%  
**Data Types:** 0 factors, 79 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `c007` | Does your child look at a person when that person starts talking or making noise? | numeric | 99.5% | N/A |
| `c012` | When you talk to your child, does he/she smile, make noise, or more arms, legs or trunk in response? | numeric | 99.5% | N/A |
| `c019` | Does your child make noise or gesture to get your attention? | numeric | 99.5% | N/A |
| `c021` | Does your child turn his/her head towards your voice or some noise? | numeric | 99.5% | N/A |
| `c022` | Does your child make sounds when LOOKING at toys or people (not crying)? | numeric | 99.5% | N/A |
| `c023` | Does your child laugh? | numeric | 99.0% | N/A |
| `c027` | Does your child make single sounds like "buh" or "duh" or "muh"? | numeric | 99.2% | N/A |
| `c033` | Does your child recognize you or other family members? For example, smile when they enter a room or move toward them? | numeric | 99.0% | N/A |
| `c034` | <div class="rich-text-field-label"><p>Does your child show interest in new objects that are put in front of him/her by reaching out for them?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155609&doc_id_hash=048050645c24a3fb52bc232350a54c6f04891894" width="400" height="234"></p></div> | numeric | 99.0% | N/A |
| `c046` | Does your child look for an object of interest when it is removed from sight or hidden from him/her, such as putting it under a cover or behind another object? | numeric | 99.5% | N/A |
| `c047` | <div class="rich-text-field-label"><p>Does your child play by tapping an object on the ground or a table?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155619&doc_id_hash=f5c348369bf02899c3c80634f6ea87a0aba0749c" alt="" width="400" height="198"></p></div> | numeric | 99.5% | N/A |
| `c048` | <div class="rich-text-field-label"><p>Does your child intentionally move or change his/her position to get objects that are out of reach?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155618&doc_id_hash=bd82cef1148f769f434f79472e193fa0fa4235c1" alt="" width="400" height="177"></p></div> | numeric | 99.4% | N/A |
| `c051` | Does your child make two similar sounds together like baba, mumu, pepe, didi (single consonant vowel combinations)? | numeric | 95.1% | N/A |
| `c059` | Does your child stop what he/she is doing when you say "Stop!" even if just for a second? | numeric | 95.4% | N/A |
| `c068` | Does your child make a gesture to indicate "No", such as shaking his/her head? | numeric | 96.6% | N/A |
| `c072` | Can your child follow a simple spoken command or direction without you making a gesture or motion? | numeric | 92.8% | N/A |
| `c073` | Can your child fetch something when asked? | numeric | 94.3% | N/A |
| `c081` | Can your child follow directions with more than one step? For example, "Go to the kitchen and bring me a spoon." | numeric | 97.0% | N/A |
| `c089` | Can your child say five or more separate words, such as names like "Mama" or objects like "ball"? | numeric | 94.9% | N/A |
| `c090` | Can your child say ten or more words in addition to "Mama" and "Dada"? | numeric | 97.1% | N/A |
| `c091` | Can your child speak using short sentences of two words that go together? For example, "Mama go" or "Dada eat." | numeric | 92.8% | N/A |
| `c093` | Can your child ask for something, such as food or water, by name when he/she wants it? | numeric | 97.7% | N/A |
| `c096` | Can your child correctly name at least one family member other than mom and dad? For example, name of brother, sister, aunt, or uncle. | numeric | 96.7% | N/A |
| `c098` | When looking at pictures, if you say to your child "what is this?", can they say the name of the object that you point to? | numeric | 92.8% | N/A |
| `c099` | Can your child recognize at least seven objects? 

For example, if you ask, "Where is the ball, spoon, cup, cloth, door, plate, or bucket?" does your child look at, point to, or even name the objects? | numeric | 96.8% | N/A |
| `c100` | Can your child name at least two body parts, such as arm, eye, or nose? | numeric | 97.0% | N/A |
| `c101` | If you show your child an object he/she knows well, such as a cup or an animal, can he/she consistently name it? | numeric | 97.3% | N/A |
| `c102` | Does your child usually communicate with words what he/she wants in a way that is understandable to others? | numeric | 93.5% | N/A |
| `c105` | Can your child say 15 or more separate words, such as names like "Mama" or objects like "ball"? | numeric | 92.7% | N/A |
| `c107` | Can your child sing a short song or repeat parts of a rhyme from memory by him/herself? | numeric | 94.2% | N/A |
| `c108` | Can your child tell you or someone familiar his/her own name/nickname when asked to? | numeric | 94.2% | N/A |
| `c111` | Does your child know the difference between the words "big" and "small"? 

For example, if you ask, "Give me the big spoon" can your child understand which one to give if there are two different sizes? | numeric | 89.9% | N/A |
| `c112` | Can your child speak using sentences of three or more words that go together? For example, "I want water." or "The house is big." | numeric | 89.1% | N/A |
| `c113` | Can your child correctly use any of the words "I," "you," "she," or "he"? 

For example, "I go to store." or "He eats rice." | numeric | 92.5% | N/A |
| `c115` | Can your child correctly ask questions using any of the words "what," "which," "where," or "who"? | numeric | 92.2% | N/A |
| `c116` | Does your child pronounce most of his/her words correctly? | numeric | 90.1% | N/A |
| `c117` | If you show your child two objects or people of a different size, can he/she tell you which one is the big one and which is the small one? | numeric | 90.3% | N/A |
| `c118` | Can your child count objects, such as fingers or people, up to five?  | numeric | 91.3% | N/A |
| `c119` | Can your child explain in words what common objects like a cup or chair are used for? | numeric | 92.8% | N/A |
| `c120` | If you point to an object, can your child correctly use the words "on," "in," or "under" to describe where it is?

For example, "The cup is on the table" instead of "The cup is in the table." | numeric | 93.9% | N/A |
| `c121` | Does your child regularly use describing words such as "fast," "short," "hot," "fat," or "beautiful" correctly? | numeric | 92.8% | N/A |
| `c122` | Can the child name at least one color, such as red, blue, or yellow? | numeric | 93.9% | N/A |
| `c124` | Does your child ask "why" questions? 

For example, "Why are you tall?" | numeric | 94.1% | N/A |
| `c126` | If you ask your child to give you three objects, such as stones or beans, does the child give you the correct amount? | numeric | 94.2% | N/A |
| `c127` | Can your child tell a story? | numeric | 95.2% | N/A |
| `c131` | <div class="rich-text-field-label"><p>Does your child understand the term 'longest'?</p> <p> </p> <p>For example, if you ask them to choose "Which is the longest of three objects, such as three spoons or sticks?" would they be able to choose the longest?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155657&doc_id_hash=1e4524b040b74f6000cdc7a35d12280ce59d90dd" alt="" width="400" height="200"></p></div> | numeric | 95.9% | N/A |
| `c136` | Can your child say what others like or dislike? For example, "Mama doesn't like fruit," or "Papa likes football." | numeric | 94.0% | N/A |
| `c138` | Can your child talk about things that have happened in the past using correct language? 

For example, "Yesterday I played with my friend" or "Last week she went to the market." | numeric | 91.8% | N/A |
| `c139` | Can your child talk about things that will happen in the future using correct language?

For example, "Tomorrow he will attend school," or "Next week we will go to the market." | numeric | 91.6% | N/A |
| `ecdi009x` | If you show your child an object he/she knows well, such as a cup or animal, can he/she consistently name it? 

By consistently, we mean that he/she uses the same word to refer to the same object, even if the word used is not fully correct. | numeric | 94.8% | N/A |
| `ecdi010` | Can your child recognize at least 5 letters of the alphabet? | numeric | 95.2% | N/A |
| `ecdi011` | Can your child write his/her own name? | numeric | 62.3% | N/A |
| `ecdi014` | Can your child count 10 objects, such as fingers or blocks, without mistakes? | numeric | 89.9% | N/A |
| `nom001` | Is this child able to understand in, on, and under? | numeric | 94.3% | N/A |
| `nom002` | How often can your child recognize the beginning sound of a word? For example, the word ball starts with the 'buh' sound? | numeric | 82.1% | N/A |
| `nom002x` | How often can your child recognize the beginning sound of a word? For example, can this child tell you that the word "ball" starts with the "buh" sound? | numeric | 80.5% | N/A |
| `nom003` | When you say a word, how often can your child come up with another word that starts with the same sound? | numeric | 82.2% | N/A |
| `nom003x` | How often can your child come up with words that start with the same sound? 

For example, can this child come up with the words "sock" and "sun"? | numeric | 80.5% | N/A |
| `nom005` | If you say the word cat, how often can this child tell you a word that rhymes with cat? | numeric | 82.2% | N/A |
| `nom005x` | How well can this child come up with words that rhyme? For example, can this child come up with "cat" and "mat?" | numeric | 80.5% | N/A |
| `nom006x` | How often can your child explain things they have seen or done so that you know what happened? | numeric | 95.4% | N/A |
| `nom009` | Can this child sort objects by color? | numeric | 94.4% | N/A |
| `nom012` | Can your child sort objects by length? | numeric | 89.7% | N/A |
| `nom014` | If asked to count objects, how high could your child count correctly?  | numeric | 95.9% | N/A |
| `nom014x` | If asked to count objects, how high can your child count correctly? | numeric | 96.0% | N/A |
| `nom015` | If you had four objects, could your child divide them in half so you have two and they have two? | numeric | 91.0% | N/A |
| `nom017` | Can your child read one-digit numbers, such as 4 or 7? | numeric | 94.8% | N/A |
| `nom017x` | How often can your child read one-digit numbers? For example, can your child read the numbers 2 or 8? | numeric | 94.9% | N/A |
| `nom018` | How often can this child correctly add two numbers, like 2 plus 3? | numeric | 82.3% | N/A |
| `nom018x` | How often can this child correctly do simple addition? For example, can this child tell you that two blocks and three blocks add to a total of five blocks? | numeric | 80.5% | N/A |
| `nom019` | How often can this child correctly subtract two numbers, like 5 take away 2? | numeric | 62.9% | N/A |
| `nom022` | Can your child identify a triangle? | numeric | 82.1% | N/A |
| `nom022x` | How often can your child identify basic shapes such as a triangle, circle, or square? | numeric | 80.5% | N/A |
| `nom024` | Can your child consistently write his/her first name, even if some of the letters aren't quite right or are backwards? | numeric | 82.1% | N/A |
| `nom026` | How many letters of the alphabet can your child recognize? | numeric | 96.0% | N/A |
| `nom026x` | About how many letters of the alphabet can your child recognize?  | numeric | 96.0% | N/A |
| `nom2205` | How often can this child tell which group of objects has more? For example, can this child tell you a group of seven blocks has more than a group of four blocks? | numeric | 63.1% | N/A |
| `sf122` | If you show your child two objects or people of different sizes, can he/she tell you which one is the big one and which is the small one? | numeric | 92.5% | N/A |
| `sf127` | If you ask your child to give you three objects, such as stones or beans, does the child give you the correct number? | numeric | 94.9% | N/A |

## Eligibility

**Description:** No description available

**Variables:** 1  
**Average Missing:** 0.0%  
**Data Types:** 0 factors, 0 numeric, 1 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `eligible` | Meets study inclusion criteria | logical | 0.0% | N/A |

## Geography

**Description:** No description available

**Variables:** 4  
**Average Missing:** 6.4%  
**Data Types:** 1 factors, 3 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `eqstate` | Do you and your child currently live in the state of Nebraska? | numeric | 25.5% | N/A |
| `extraction_id` | Extraction Id | factor | 0.0% | 1 (ne25_20251209_181621) |
| `state_law_prohibits_sending_compensation_electronically___1` | State Law Prohibits Sending Compensation Electronically   1 | numeric | 0.0% | N/A |
| `state_law_requires_that_kidsights_data_collect_my_name___1` | State Law Requires That Kidsights Data Collect My Name   1 | numeric | 0.0% | N/A |

## Mental_Health

**Description:** No description available

**Variables:** 10  
**Average Missing:** 36.6%  
**Data Types:** 2 factors, 8 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `gad2_nervous` | GAD-2 Item 1 - Feeling nervous, anxious, or on edge (past 2 weeks) | numeric | 36.6% | N/A |
| `gad2_positive` | GAD-2 Positive Screen (â‰¥3) - Indicates likely anxiety, further evaluation needed | numeric | 36.8% | N/A |
| `gad2_risk_cat` | GAD-2 Risk Category - Minimal/None (0-1), Mild (2), Moderate (3-4), Severe (5-6) | factor | 36.8% | 1 (Mild), 2 (Minimal/None), 3 (Moderate), 4 (Severe) |
| `gad2_total` | GAD-2 Total Score (0-6) - Anxiety screening score | numeric | 36.8% | N/A |
| `gad2_worry` | GAD-2 Item 2 - Not being able to stop or control worrying (past 2 weeks) | numeric | 36.5% | N/A |
| `phq2_depressed` | PHQ-2 Item 2 - Feeling down, depressed, or hopeless (past 2 weeks) | numeric | 36.6% | N/A |
| `phq2_interest` | PHQ-2 Item 1 - Little interest or pleasure in doing things (past 2 weeks) | numeric | 36.3% | N/A |
| `phq2_positive` | PHQ-2 Positive Screen (â‰¥3) - Indicates likely depression, further evaluation needed | numeric | 36.6% | N/A |
| `phq2_risk_cat` | PHQ-2 Risk Category - Minimal/None (0-1), Mild (2), Moderate/Severe (3-6) | factor | 36.6% | 1 (Mild), 2 (Minimal/None), 3 (Moderate/Severe) |
| `phq2_total` | PHQ-2 Total Score (0-6) - Depression screening score | numeric | 36.6% | N/A |

## Motor

**Description:** No description available

**Variables:** 74  
**Average Missing:** 94.3%  
**Data Types:** 0 factors, 74 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `c005` | <div class="rich-text-field-label"><p>Does your child try to move his/her head (or eyes) to follow an object or person?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155596&doc_id_hash=0fdc518e75637d9a3863ecc748429982df54c690" alt="" width="400" height="183"></p></div> | numeric | 99.5% | N/A |
| `c013` | <div class="rich-text-field-label"><p>When your child is on his/her stomach, can he/she turn his/her head to the side?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155592&doc_id_hash=541b16d6b9f12c82cec60461ee8d13e9b35ee857" alt="" width="400" height="193"></p></div> | numeric | 99.5% | N/A |
| `c017` | While your child is on his/her back, can he/she bring his/her hands together? | numeric | 99.5% | N/A |
| `c018` | <div class="rich-text-field-label"><p>When your child is on his/her stomach, can he/she hold his/her head up off the ground?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155599&doc_id_hash=f4d409e5808c742bdc4034c200ab19d9325391e1" alt="" width="400" height="184"></p></div> | numeric | 99.5% | N/A |
| `c024` | Can your child hold his/her head steady for at least a few seconds, without it flopping to the side? | numeric | 99.5% | N/A |
| `c026` | <div class="rich-text-field-label"><p>Does your child grasp onto a small object, such as your finger or a spoon, when it is in his/her hand?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155605&doc_id_hash=2e5c5312e4e69a8627168044d40520a27513e1c8" alt="" width="400" height="269"></p></div> | numeric | 99.5% | N/A |
| `c028` | <div class="rich-text-field-label"><p>Does your child try to reach for objects that are in front of him/her by extending one or both arms?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155615&doc_id_hash=d2cf51595a77c9c27eafe4a3a966f324580ad691" alt="" width="400" height="270"></p></div> | numeric | 99.2% | N/A |
| `c029` | When he/she is on his/her tummy, can your child hold his/her head straight up, looking around for more than a few seconds? He/she can rest on his/her arms while doing this. | numeric | 99.5% | N/A |
| `c029x` | <div class="rich-text-field-label"><p><span style="background-color: #f1c40f \|;">When he/she is on his/her tummy, can your child hold his/her head straight up, looking around for more than a few seconds? Your child can rest on his/her arms while doing this.</span></p> <p><span style="background-color: #f1c40f \|;"><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155607&doc_id_hash=d04392e586bdaa341b78f08586285a1c1bebabed" alt="" width="400" height="222"></span></p></div> | numeric | 99.5% | N/A |
| `c030` | Can your child roll from his/her back to stomach or stomach to his/her side? | numeric | 99.5% | N/A |
| `c030x` | <div class="rich-text-field-label"><p><span style="color: #000000 \| background-color: #f1c40f \|;">Can your child roll from his/her back to stomach or stomach to side?</span></p> <p><span style="color: #000000 \| background-color: #f1c40f \|;"><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155612&doc_id_hash=bb79bf50a2a1e188bcd9a945163167bb8ebe548c" alt="" width="400" height="187"></span></p></div> | numeric | 99.6% | N/A |
| `c035` | <div class="rich-text-field-label"><p>Can your child reach for AND HOLD an object, at least for a few seconds?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155610&doc_id_hash=d2c241da092c33edebcb6d47f9c4a55461588079" alt="" width="400" height="195"></p></div> | numeric | 99.0% | N/A |
| `c036` | When you put your child on the floor, can she lean on her hands while sitting? If your child already sits up straight without leaning on her hands, mark 'yes' for this item. | numeric | 95.0% | N/A |
| `c037` | <div class="rich-text-field-label"><p>When held in a sitting position, can your child hold his/her head steady and straight?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155606&doc_id_hash=ebbae14d7a72ec80f9dcf8a37f30c3919ba88640" alt="" width="400" height="253"></p></div> | numeric | 99.0% | N/A |
| `c038` | <div class="rich-text-field-label"><p>Can your child roll from his/her back to stomach, or stomach to back, on his/her own?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155613&doc_id_hash=6956b0cd2db64a66cabf8f072c38c82058eb2f9e" alt="" width="400" height="208"></p></div> | numeric | 99.2% | N/A |
| `c039` | Can your child eat food from your fingers or off a spoon you hold? | numeric | 99.5% | N/A |
| `c040` | <div class="rich-text-field-label"><p>Can your child pick up a small object, such as a small toy or small stone, using just one hand?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155617&doc_id_hash=e94b277c8c5e9556c00b6a78c55c4288cbc5cabe" alt="" width="400" height="186"></p></div> | numeric | 99.4% | N/A |
| `c041` | <div class="rich-text-field-label"><p>If an object falls to the ground out of view, does your child look for it?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155621&doc_id_hash=f9cb8e88c9de796e3e2485f730c30dce3810fd33" alt="" width="400" height="180"></p></div> | numeric | 99.6% | N/A |
| `c042` | <div class="rich-text-field-label"><p>When lying on his/her stomach, can your child hold his/her head and chest off the ground using only his/her hands and arms for support?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155611&doc_id_hash=b5d9280191e10f2941ed71dc4e33fd8270daf672" alt="" width="400" height="218"></p></div> | numeric | 99.0% | N/A |
| `c043` | <div class="rich-text-field-label"><p>When lying on his/her back, does the child grab his/her feet?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155616&doc_id_hash=f91216143ae25a267ca39d8fe578c3f6b0133ed1" alt="" width="400" height="232"></p></div> | numeric | 99.2% | N/A |
| `c044` | <div class="rich-text-field-label"><p>Can your child sit with support, either leaning against something (furniture or person) or by leaning forward on his/ her hands?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155614&doc_id_hash=b3c9f14d24488b713e702016b4d00445b9f4aeb1" alt="" width="400" height="273"></p></div> | numeric | 99.2% | N/A |
| `c049` | <div class="rich-text-field-label"><p>Can your child hold him/herself in a sitting position without help or support for longer than a few seconds?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155622&doc_id_hash=fc9b79a8c3ec90bfadc1b2205f55a3b4634ceadc" alt="" width="400" height="270"></p></div> | numeric | 99.5% | N/A |
| `c050` | <div class="rich-text-field-label"><p>Can your child bang objects together, or bang an object on the table or on the ground?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155624&doc_id_hash=db237af495999fbb2a749ea8d589d43a1d20402f" alt="" width="400" height="247"></p></div> | numeric | 95.0% | N/A |
| `c052` | <div class="rich-text-field-label"><p>Can your child pass a small object from one hand to the other?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155625&doc_id_hash=edcdbe2c4de1c0a413e7841a450df29c6b206753" alt="" width="400" height="195"></p></div> | numeric | 95.2% | N/A |
| `c053` | <div class="rich-text-field-label"><p>Can your child pick up a small object, such as a piece of food, small toy, or small stone, with just his/her thumb and one finger?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155628&doc_id_hash=8c10b4994c266218f4d03ba5b8d5bd0267f8fca6" alt="" width="400" height="200"></p></div> | numeric | 95.2% | N/A |
| `c054` | <div class="rich-text-field-label"><p>Can your child maintain a standing position while holding onto a person or object, such as a wall or piece of furniture?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155626&doc_id_hash=ba81e6dac56feb60c6fd3efe66a55d31a2b1a1ea" alt="" width="400" height="342"></p></div> | numeric | 95.0% | N/A |
| `c055` | <div class="rich-text-field-label"><p>While holding onto furniture, does your child bend down and pick up a small object from the floor and then return to a standing position?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155632&doc_id_hash=f6bc566f62f228d8c7d9435bb2b3d04b42e72106" alt="" width="400" height="270"></p></div> | numeric | 95.7% | N/A |
| `c056` | <div class="rich-text-field-label"><p>Can your child pull themselves up from the floor while holding onto something? For example, can they pull themselves up using a chair, a person, or some other object?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155630&doc_id_hash=057636e6d5bd0325b6189b7f16021d165523befd" alt="" width="400" height="186"></p></div> | numeric | 95.3% | N/A |
| `c057` | <div class="rich-text-field-label"><p>While holding onto furniture, does your child squat with control without falling or flopping down?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155631&doc_id_hash=3ab814e6ceaa7262758f27680cf0314fefc7ee76" alt="" width="400" height="222"></p></div> | numeric | 95.5% | N/A |
| `c058` | <div class="rich-text-field-label"><p>Can your child pick up and drop a small object (e.g., a small toy or small stone) into a bucket or bowl while sitting?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=158398&doc_id_hash=ece6fd33a012796962c438ec9125840799cdcd49" alt="" width="400" height="298"></p></div> | numeric | 95.9% | N/A |
| `c060` | <div class="rich-text-field-label"><p>Can your child walk several steps while holding on to a person or object, such as a wall or piece of furniture?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155633&doc_id_hash=226b6068a9bcd07ae2c6221d42ad8b6320acb773" alt="" width="400" height="275"></p></div> | numeric | 95.6% | N/A |
| `c061` | <div class="rich-text-field-label"><p>Can your child stand up without holding onto anything, even if just for a few seconds?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155634&doc_id_hash=951b1f667c798c2a173c8bc79bb0645711a09da6" alt="" width="400" height="288"></p></div> | numeric | 95.9% | N/A |
| `c062` | <div class="rich-text-field-label"><p>Can your child maintain a standing position on his/her own, without holding on or receiving support?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155642&doc_id_hash=05e933e8fd1751141459bb3a6ef0494c88ec2cb3" alt="" width="400" height="300"></p></div> | numeric | 92.8% | N/A |
| `c063` | <div class="rich-text-field-label"><p>Can your child make any light marks on paper or in dirt with a crayon or a stick?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155639&doc_id_hash=11b9ddb859a2f7e801a0ba98097187f087070fa4" alt="" width="400" height="379"></p></div> | numeric | 93.4% | N/A |
| `c064` | <div class="rich-text-field-label"><p>Can your child pick up small bits of food and feed him/her-self using his/her hand?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155627&doc_id_hash=f73463ea467ec77ef0856dca1a294ac826916425" alt="" width="400" height="277"></p></div> | numeric | 95.1% | N/A |
| `c065` | <div class="rich-text-field-label"><p>Can your child climb onto an object? For example, a rock, porch, step, chair, bed, or low table.</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155638&doc_id_hash=1ea8b726c21f6aa946dc494dc93f52553fdf04db" alt="" width="400" height="369"></p> <p> </p></div> | numeric | 92.3% | N/A |
| `c066` | <div class="rich-text-field-label"><p>Can your child take several steps (3-5) forward without holding onto any person or object, even if they fall down immediately afterward?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155644&doc_id_hash=228c9a68e57f1fcb333ac5d72f9d549927617ea7" alt="" width="400" height="178"></p></div> | numeric | 93.4% | N/A |
| `c067` | Can your child move around by walking, rather than by crawling on his hands and knees? | numeric | 93.4% | N/A |
| `c069` | <div class="rich-text-field-label"><p>Can your child stand up from sitting by himself and take several steps forward?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155645&doc_id_hash=6c2f9d47bbb0d5ba3dd5aaeedb50dd449505875a" alt="" width="400" height="208"></p></div> | numeric | 93.5% | N/A |
| `c070` | <div class="rich-text-field-label"><p>Can your child bend down or squat to pick up an object from the floor and then stand up again, without help from a person or object?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155643&doc_id_hash=fb4176428ea45b9283017426d36be3a826746ad7" alt="" width="400" height="300"></p></div> | numeric | 93.2% | N/A |
| `c071` | <div class="rich-text-field-label"><p>Can your child make a scribble on paper, or in dirt, in a back and forth manner? For example, can he or she move the pen or pencil or stick back and forth?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155641&doc_id_hash=fea870520b80fabc30cde3bee7d71cb083cdaafd" alt="" width="400" height="300"></p></div> | numeric | 93.7% | N/A |
| `c074` | Can your child drink from an open cup without help? | numeric | 95.0% | N/A |
| `c076` | <div class="rich-text-field-label"><p>While standing, can your child purposefully throw the ball and not just drop it?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155647&doc_id_hash=d7944db99fca3f1bae3b69d963a15b7a7f10e0bf" alt="" width="400" height="282"></p></div> | numeric | 93.7% | N/A |
| `c077` | <div class="rich-text-field-label"><p>Can your child walk well, with coordination, without falling down often? With one foot in front of the other rather than shifting weight side to side, stiff-legged?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155648&doc_id_hash=4b00e78e86322d049e3f673fbd5a4422c586ac4d" alt="" width="400" height="290"></p></div> | numeric | 94.3% | N/A |
| `c078` | <div class="rich-text-field-label"><p>Can your child stack at least two objects on top of each other, such as bottle tops, blocks, or stones?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155640&doc_id_hash=cf646becea765d39614cb86740af28571d2f6080" alt="" width="400" height="300"></p></div> | numeric | 92.8% | N/A |
| `c079` | <div class="rich-text-field-label"><p>Can your child kick a ball or other round object forward using his/her foot?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155649&doc_id_hash=7e852efe19d0fb57d1e9c9e848f9c842768d33bc" alt="" width="400" height="294"></p></div> | numeric | 95.2% | N/A |
| `c080` | <div class="rich-text-field-label"><p>While standing, can your child kick a ball by swinging his/her leg forward?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155652&doc_id_hash=218f60ff44ce3c8e91d72843afa1ef94c3281d8a" alt="" width="400" height="274"></p></div> | numeric | 95.8% | N/A |
| `c083` | <div class="rich-text-field-label"><p>Can your child stack three or more small objects, such as blocks, cups, or bottle caps, on top of each other?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155651&doc_id_hash=89753eb8437d1c017cc1c7f613b5027862878875" alt="" width="400" height="300"></p></div> | numeric | 95.4% | N/A |
| `c084` | <div class="rich-text-field-label"><p>Can your child run well, without falling or bumping into objects?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155653&doc_id_hash=600194da4958436f186964408a7b2a0db991c877" alt="" width="400" height="300"></p></div> | numeric | 95.5% | N/A |
| `c087` | Does your child dry hands by herself/himself after you have washed them? | numeric | 92.9% | N/A |
| `c092` | Can your child wash hands by him/herself? | numeric | 90.8% | N/A |
| `c097` | Can your child walk on an uneven surface, like a bumpy or steep road, without falling? | numeric | 95.2% | N/A |
| `c103` | Can your child draw a straight line? | numeric | 92.5% | N/A |
| `c104` | Can your child remove an item of clothing, such as take off his/her shirt? | numeric | 97.5% | N/A |
| `c106` | <div class="rich-text-field-label"><p>Can your child jump with both feet leaving the ground?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155654&doc_id_hash=94b42d6bcc0486ba83e0ce821a48ea46786abcd1" alt="" width="400" height="221"></p></div> | numeric | 94.3% | N/A |
| `c109` | Can your child put on at least one piece of clothing by himself? | numeric | 90.1% | N/A |
| `c110` | <div class="rich-text-field-label"><p>Can your child unscrew the lid from a bottle or jar?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155656&doc_id_hash=19e23f88ac5ef5b1a73408f76c537d3946ed0e2d" alt="" width="400" height="200"></p></div> | numeric | 91.3% | N/A |
| `c129` | Can your child dress him/herself completely, except for shoelaces, buttons, and zippers? | numeric | 91.6% | N/A |
| `c132` | Can your child fasten and unfasten buttons without help? | numeric | 64.2% | N/A |
| `c133` | If you draw a circle, can your child do it, just as you did? | numeric | 90.8% | N/A |
| `c135` | <div class="rich-text-field-label"><p>Can your child stand on one foot WITHOUT any support for at least a few seconds?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155655&doc_id_hash=431105b1ac949a03f4db3d10146acaf83701da12" alt="" width="400" height="300"></p></div> | numeric | 91.2% | N/A |
| `nom024x` | How often can your child write his/her first name, even if some of the letters aren't quite right or are backwards? | numeric | 80.5% | N/A |
| `nom028` | Can your child draw a triangle? | numeric | 92.0% | N/A |
| `nom029` | Can your child draw a square? | numeric | 96.0% | N/A |
| `nom029x` | How well can your child draw a circle? | numeric | 96.0% | N/A |
| `nom031` | Can your child make a tower of three or more blocks? | numeric | 96.7% | N/A |
| `nom033` | Can your child draw a face with eyes and mouth? | numeric | 95.6% | N/A |
| `nom033x` | How well can your child draw a face with eyes and mouth? | numeric | 95.4% | N/A |
| `nom034` | Can your child draw a person with arms and legs? | numeric | 96.0% | N/A |
| `nom034x` | How well can your child draw a person with a head, body, arms, and legs? | numeric | 96.0% | N/A |
| `nom035` | When using a pencil, can your child use fingers to hold it? | numeric | 81.7% | N/A |
| `nom035x` | How does your child usually hold a pencil? | numeric | 80.3% | N/A |
| `nom042x` | How well can this child bounce a ball for several seconds? | numeric | 62.9% | N/A |
| `sf054` | <div class="rich-text-field-label"><p>Can your child pick up and drop a small object, such as a piece of food, small toy, or small stone, into a bucket or bowl while sitting?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155629&doc_id_hash=392e90813ab18c7873cd0625944a40dce552fa22" alt="" width="400" height="298"></p></div> | numeric | 95.7% | N/A |

## Other

**Description:** No description available

**Variables:** 329  
**Average Missing:** 39.5%  
**Data Types:** 4 factors, 289 numeric, 4 logical, 32 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `calibrated_weight` | Calibrated Weight | numeric | 43.9% | N/A |
| `cfqb001` | In general, how is your physical health? | numeric | 36.3% | N/A |
| `cname1` | What is this child's name? (First name or nickname ONLY)

Providing your child's name is optional. We will only use if we follow-up in the future and would like to ask questions about this child | character | 72.6% | N/A |
| `compensation` | Compensation | factor | 0.0% | 1 (Fail), 2 (Pass) |
| `consecutive_nos_180_364` | Consecutive Nos | numeric | 94.9% | N/A |
| `consecutive_nos_365_548` | 5 Consecutive Nos | numeric | 92.2% | N/A |
| `consecutive_nos_549_731` | 5 Consecutive Nos | numeric | 92.5% | N/A |
| `consecutive_nos_732_914` | 5 Consecutive Nos | numeric | 88.1% | N/A |
| `consecutive_nos_90_179` | 5 Consecutive Nos | numeric | 99.0% | N/A |
| `consecutive_nos_915_1096` | 5 Consecutive Nos | numeric | 89.5% | N/A |
| `consecutive_nos_count` | 5 Consecutive Nos Count | numeric | 99.4% | N/A |
| `consent_date` | Today's Date | character | 24.9% | N/A |
| `consent_doc_complete` | Consent Doc Complete | numeric | 0.0% | N/A |
| `consent_doc_timestamp` | Consent Doc Timestamp | character | 6.5% | N/A |
| `cqfa001` | What is your marital status? | numeric | 36.8% | N/A |
| `cqfa002` | In general, how would you describe your child's health? | numeric | 39.4% | N/A |
| `cqfa005` | Since your child was born, how often has it been very hard to cover the basics, like food and housing, on your family's income? | numeric | 36.0% | N/A |
| `cqfa006` | DURING THE PAST 12 MONTHS, which of these statements best describes your household's ability to afford the food you need? | numeric | 36.2% | N/A |
| `cqfa009` | How many times has your child moved to a new address since he or she was born? | numeric | 36.2% | N/A |
| `cqfa010` | DURING THE PAST 12 MONTHS, was there someone that you could turn to for day-to-day emotional support with parenting or raising children? | numeric | 36.0% | N/A |
| `cqfa010a___1` | Cqfa010A   1 | numeric | 0.0% | N/A |
| `cqfa010a___2` | Cqfa010A   2 | numeric | 0.0% | N/A |
| `cqfa010a___3` | Cqfa010A   3 | numeric | 0.0% | N/A |
| `cqfa010a___4` | Cqfa010A   4 | numeric | 0.0% | N/A |
| `cqfa010a___5` | Cqfa010A   5 | numeric | 0.0% | N/A |
| `cqfa010a___6` | Cqfa010A   6 | numeric | 0.0% | N/A |
| `cqfa013` | DURING THE PAST WEEK, how many hours of sleep did your child get on an average weeknight? | numeric | 39.5% | N/A |
| `cqfb002` | In general, how is your mental or emotional health? | numeric | 36.1% | N/A |
| `cqfb007x` | <div class="rich-text-field-label"><p><span style="text-decoration: underline;">The rest of the questions ask only about the child whose birthdate you entered at the beginning of the survey.</span><br><br>Does your child receive care for at least 10 hours per week from someone other than a parent or guardian?</p> <p>This could be a daycare center, preschool, Head Start program, family childcare home, nanny, au pair, babysitter, or relative.</p></div> | numeric | 39.1% | N/A |
| `cqfb008` | DURING THE PAST 12 MONTHS, did you or anyone in the family have to quit a job, not take a job, or greatly change your job because of problems with childcare for your child? | numeric | 37.3% | N/A |
| `cqfb009` | People in this neighborhood help each other out. | numeric | 36.3% | N/A |
| `cqfb010` | We watch out for each other's children in this neighborhood. | numeric | 36.5% | N/A |
| `cqfb011` | This child is safe in our neighborhood. | numeric | 36.2% | N/A |
| `cqfb012` | When we encounter difficulties, we know where to go for help in our community. | numeric | 36.5% | N/A |
| `cqfb013` | Little interest or pleasure in doing things? | numeric | 36.3% | N/A |
| `cqfb014` | Feeling down, depressed or hopeless? | numeric | 36.6% | N/A |
| `cqfb015` | Feeling nervous, anxious or on edge? | numeric | 36.6% | N/A |
| `cqfb016` | Not being able to stop or control worrying? | numeric | 36.5% | N/A |
| `cqr0011` | DURING THE PAST WEEK, has your child been sick or unwell?

For example, fever, earache, vomiting, and diarrhea. | numeric | 39.8% | N/A |
| `cqr002` | What is your sex? | numeric | 35.8% | N/A |
| `cqr003` | <div class="rich-text-field-label"><p>What is your age?</p></div> | numeric | 36.8% | N/A |
| `cqr004` | What is the highest grade or level of school you have completed? | numeric | 35.7% | N/A |
| `cqr006` | What was your total family income, before taxes, for the year 2024?

 Include money from jobs, child support, Social Security, retirement income, unemployment payments, public assistance, and other sources. Also, include income from interest, dividends, net income from business, farm, or rent, and any other money income received.

Use the slider to select a value that best represents this value. | numeric | 35.4% | N/A |
| `cqr007___1` | Cqr007   1 | numeric | 0.0% | N/A |
| `cqr007___2` | Cqr007   2 | numeric | 0.0% | N/A |
| `cqr007___3` | Cqr007   3 | numeric | 0.0% | N/A |
| `cqr007___4` | Cqr007   4 | numeric | 0.0% | N/A |
| `cqr007___5` | Cqr007   5 | numeric | 0.0% | N/A |
| `cqr007___6` | Cqr007   6 | numeric | 0.0% | N/A |
| `cqr007___7` | Cqr007   7 | numeric | 0.0% | N/A |
| `cqr008` | How are you related to your child? | numeric | 36.1% | N/A |
| `cqr009` | What is your child's sex? | numeric | 39.4% | N/A |
| `cqr010___1` | Cqr010   1 | numeric | 0.0% | N/A |
| `cqr010___10` | Cqr010   10 | numeric | 0.0% | N/A |
| `cqr010___11` | Cqr010   11 | numeric | 0.0% | N/A |
| `cqr010___12` | Cqr010   12 | numeric | 0.0% | N/A |
| `cqr010___13` | Cqr010   13 | numeric | 0.0% | N/A |
| `cqr010___14` | Cqr010   14 | numeric | 0.0% | N/A |
| `cqr010___15` | Cqr010   15 | numeric | 0.0% | N/A |
| `cqr010___16` | Cqr010   16 | numeric | 0.0% | N/A |
| `cqr010___2` | Cqr010   2 | numeric | 0.0% | N/A |
| `cqr010___3` | Cqr010   3 | numeric | 0.0% | N/A |
| `cqr010___4` | Cqr010   4 | numeric | 0.0% | N/A |
| `cqr010___5` | Cqr010   5 | numeric | 0.0% | N/A |
| `cqr010___6` | Cqr010   6 | numeric | 0.0% | N/A |
| `cqr010___7` | Cqr010   7 | numeric | 0.0% | N/A |
| `cqr010___8` | Cqr010   8 | numeric | 0.0% | N/A |
| `cqr010___9` | Cqr010   9 | numeric | 0.0% | N/A |
| `cqr011` | Is your child of Hispanic, Latino, or Spanish origin? | numeric | 39.0% | N/A |
| `cqr013` | Does your child need or use more medical care, mental health, or educational services than is usual for most children of the same age? | numeric | 40.0% | N/A |
| `cqr014x` | DURING THE PAST 12 MONTHS, how often have your child's health conditions or problems affected their ability to do things other children their age do? | numeric | 39.5% | N/A |
| `cqr015` | Does your child need or get special therapy, such as physical, occupational, or speech therapy? | numeric | 40.0% | N/A |
| `cqr016` | Does your child have any emotional, developmental, or behavioral problems for which he/she needs treatment or counseling? | numeric | 39.8% | N/A |
| `cqr017` | Parent or guardian divorced or separated? | numeric | 40.1% | N/A |
| `cqr018` | Parent or guardian died? | numeric | 40.0% | N/A |
| `cqr019` | Parent or guardian served time in jail? | numeric | 40.4% | N/A |
| `cqr020` | Saw or heard parents or adults slap, hit, kick, punch one another in the home? | numeric | 40.2% | N/A |
| `cqr021` | Was a victim of violence or witnessed violence in his or her neighborhood? | numeric | 40.3% | N/A |
| `cqr022` | Lived with anyone who was mentally ill, suicidal, or severely depressed? | numeric | 40.4% | N/A |
| `cqr023` | Lived with anyone who had a problem with alcohol or drugs? | numeric | 40.4% | N/A |
| `cqr024` | Treated or judged unfairly because of his or her race or ethnic group? | numeric | 40.1% | N/A |
| `cqrn012` | To your knowledge, has your child ever been screened for developmental delays OR has a health professional suggested that your child be screened for developmental delays? | numeric | 39.9% | N/A |
| `data_quality` | Data Quality | logical | 0.0% | N/A |
| `date_complete_check` | Date Complete Check (It make sure the branching logic doesnot appear until the user finishes typing the date)  | numeric | 40.5% | N/A |
| `dob` | <div class="rich-text-field-label"><p><span style="text-decoration: underline;">This survey is about the one child whose birthday you will enter here.</span></p> <p><br>What is your child's date of birth?</p> <p><span style="color: #e03e2d;">Please enter your child's birthdate in the following format: MM/DD/YYYY (Month/Day/Year).</span></p></div> | character | 25.2% | N/A |
| `dob_match` | Dob Match | numeric | 24.9% | N/A |
| `ecdi007` | Can your child speak using sentences of 5 or more words that go together? | numeric | 94.0% | N/A |
| `eligibility` | Eligibility | factor | 0.0% | 1 (Fail), 2 (Pass) |
| `eligibility_form_complete` | Eligibility Form Complete | numeric | 0.0% | N/A |
| `eligibility_form_timestamp` | Eligibility Form Timestamp | character | 24.8% | N/A |
| `email` | Email | character | 84.3% | N/A |
| `email_followup` | Please provide email for contact | character | 66.1% | N/A |
| `email_registration_complete` | Email Registration Complete | numeric | 84.2% | N/A |
| `email_registration_timestamp` | Email Registration Timestamp | character | 84.2% | N/A |
| `eq001` | Do you consent to participate in this survey? | numeric | 25.1% | N/A |
| `eq002` | Are you a primary caregiver for your child?

A primary caregiver, most often a parent or guardian, is a person who is often responsible for the care of the child, spends a significant amount of time with the child (at least 40 hours per week), and can speak to what the child can do and how the child behaves.  | numeric | 25.1% | N/A |
| `eq003` | Are you 19 years of age or older? | numeric | 24.9% | N/A |
| `eq004a` | <div class="rich-text-field-label"><p>Please confirm your child's date of birth<br><span style="color: #e03e2d;">Please enter the birthdate in MM/DD/YYYY format (e.g., 12/31/2000)</span></p></div> | character | 40.6% | N/A |
| `exclusion_reason` | Exclusion Reason | factor | 85.5% | 1 (Insufficient responses (n=0, threshold=5)), 2 (Insufficient responses (n=1, threshold=5)), 3 (Insufficient responses (n=2, threshold=5)), 4 (Insufficient responses (n=3, threshold=5)) |
| `externalizing_gsed_pf_2022` | Externalizing Gsed Pf 2022 | numeric | 43.9% | N/A |
| `externalizing_gsed_pf_2022_csem` | Externalizing Gsed Pf 2022 Csem | numeric | 43.9% | N/A |
| `fci_a_1` | About how many books are there in the home, including schoolbooks, novels, and religious books?

Do not include books meant for very young children, such as picture books. | numeric | 39.8% | N/A |
| `fci_a_2` | How many magazines and newspapers are there in the household? | numeric | 40.4% | N/A |
| `fci_a_3` | How many times in a week does your child see you or other members of the household reading books, magazines or newspapers? | numeric | 40.2% | N/A |
| `fci_b_1` | Do you have children's books or picture books at home for your child? | numeric | 40.6% | N/A |
| `fci_b_2` | How many books do you have in your home for your child? | numeric | 43.0% | N/A |
| `fci_c_1` | Home-made toys? For example, home-made play-dough, puppets, balls made of plastic papers, clay dolls, wire cars, or other toys made at home. | numeric | 40.2% | N/A |
| `fci_c_10` | Things for pretending? | numeric | 40.5% | N/A |
| `fci_c_11` | Does your child play with electronic devices other than radio or TV? | numeric | 40.2% | N/A |
| `fci_c_2` | Toys from a shop or manufactured toys? For example, balls, dolls, cars, or other toys from a shop/store. | numeric | 40.1% | N/A |
| `fci_c_3` | Household objects? For example, bowls, spoons, empty matchboxes, empty bottles or pots, large cardboard boxes. OR objects found outside? For example, sticks, rocks, animal shells or leaves. | numeric | 40.2% | N/A |
| `fci_c_4` | Things which make or play music? | numeric | 40.1% | N/A |
| `fci_c_5` | Things for drawing or writing? | numeric | 40.2% | N/A |
| `fci_c_6` | Picture books for children that are not schoolbooks? | numeric | 40.6% | N/A |
| `fci_c_7` | Things meant for stacking, constructing, or building? For example, blocks, logs, maize cobs to build a pretend house, small pieces of timber, stones, small pieces of brick. | numeric | 40.6% | N/A |
| `fci_c_8` | Things that encourage movement, like rolling, crawling, walking, or running? | numeric | 40.3% | N/A |
| `fci_c_9` | Toys for learning colors or shapes, like circle, square, triangle? | numeric | 40.4% | N/A |
| `fci_d_1` | Read books to or look at picture books, photos or posters with your child? | numeric | 40.3% | N/A |
| `fci_d_10` | Do physical activities with your child? For example, walk, play on swings or slides, ride in toy tricycle, play in pool. | numeric | 40.5% | N/A |
| `fci_d_11` | Does your child have a place of their own to keep toys or treasures? | numeric | 40.4% | N/A |
| `fci_d_2` | Tell stories to your child? | numeric | 40.3% | N/A |
| `fci_d_3` | Sing songs or say rhymes with your child including lullabies? | numeric | 40.8% | N/A |
| `fci_d_4` | Take your child outside the home or yard or enclosure? For example, play dates with other children, visiting other family, going to beach or park. | numeric | 40.5% | N/A |
| `fci_d_5` | Play with your child? For example, peek-a-boo, hand games (pat-a-cake), pretend play with dolls or other toys. | numeric | 40.5% | N/A |
| `fci_d_6` | Count things with your child? | numeric | 40.4% | N/A |
| `fci_d_7` | Draw or paint things with your child? | numeric | 40.5% | N/A |
| `fci_d_8` | Construct things with your child? | numeric | 40.6% | N/A |
| `fci_d_9` | Do any household chores with your child and talk while doing the work? For example, child put things away, sweep, set the table, do dishes, cook. | numeric | 40.7% | N/A |
| `feeding_gsed_pf_2022` | Feeding Gsed Pf 2022 | numeric | 43.9% | N/A |
| `feeding_gsed_pf_2022_csem` | Feeding Gsed Pf 2022 Csem | numeric | 43.9% | N/A |
| `financial_compensation_be_sent_to_a_nebraska_residential_address___1` | Financial Compensation Be Sent To A Nebraska Residential Address   1 | numeric | 0.0% | N/A |
| `first_5_nos_1097_2191` | First 5 Consecutive Nos | numeric | 61.9% | N/A |
| `first_5_nos_180_364` | First 5 Nos count | numeric | 94.9% | N/A |
| `first_5_nos_365_548` | First 5 Nos count | numeric | 92.2% | N/A |
| `first_5_nos_549_731` | First 5 Nos count | numeric | 92.5% | N/A |
| `first_5_nos_732_914` | First 5 Nos | numeric | 88.1% | N/A |
| `first_5_nos_90_179` | First 5 Nos Count | numeric | 99.0% | N/A |
| `first_5_nos_915_1096` | First 5 Nos | numeric | 89.5% | N/A |
| `fq001` | Which county do you live in? | numeric | 25.4% | N/A |
| `fq005` | Is your child enrolled in Early Head Start or Head Start? | numeric | 39.6% | N/A |
| `fqlive1_1` | Children, birth through 18 years | numeric | 36.7% | N/A |
| `fqlive1_2` | Adults, 19- 65 years of age | numeric | 37.0% | N/A |
| `fqlive1_3` | Adults, 66 years or older | numeric | 54.0% | N/A |
| `general_gsed_pf_2022` | General Gsed Pf 2022 | numeric | 43.9% | N/A |
| `general_gsed_pf_2022_csem` | General Gsed Pf 2022 Csem | numeric | 43.9% | N/A |
| `inc99` | Inc99 | numeric | 35.4% | N/A |
| `ineligible_flag` | Ineligible Flag:

Do not proceed to the next session if:
CHILD is identified as white
AND CHILD identified as non-Hispanic
AND CHILD is 1096 days OR older
AND the responding caregiver has a Bachelors  degree OR a masters degree OR a doctorate
Otherwise, proceed with the survey | numeric | 98.6% | N/A |
| `influential` | Influential | logical | 0.0% | N/A |
| `internalizing_gsed_pf_2022` | Internalizing Gsed Pf 2022 | numeric | 43.9% | N/A |
| `internalizing_gsed_pf_2022_csem` | Internalizing Gsed Pf 2022 Csem | numeric | 43.9% | N/A |
| `kidsights_2022` | Kidsights 2022 | numeric | 43.9% | N/A |
| `kidsights_2022_csem` | Kidsights 2022 Csem | numeric | 43.9% | N/A |
| `kidsights_data_reviews_all_responses_for_quality___1` | Kidsights Data Reviews All Responses For Quality   1 | numeric | 0.0% | N/A |
| `meets_inclusion` | Meets Inclusion | logical | 0.0% | N/A |
| `mmi000` | This question asks about your child's primary childcare arrangement. 

In a typical week, what type of childcare does your child receive the most? | numeric | 64.2% | N/A |
| `mmi003` | In a typical week, about how much does your household pay for your child's primary childcare arrangement?

Use the slider to select a value that best represents this value $[mmi003]
 | numeric | 65.7% | N/A |
| `mmi003b` | In a typical week, about how much does your household pay for all childcare arrangements for your child?

Use the slider to select a value that best represents this value $[mmi003b] | numeric | 66.0% | N/A |
| `mmi009` | Do childcare costs affect your family's ability to pay for basic necessities such as food, housing, medicine, health care, and clothing? | numeric | 73.4% | N/A |
| `mmi013` | DURING THE PAST 12 MONTHS, how difficult was it to find childcare when you needed it? | numeric | 39.2% | N/A |
| `mmi014` | What was the main reason that it was difficult to find childcare? | numeric | 81.1% | N/A |
| `mmi018` | Is your primary childcare arrangement paid for, at least in part, by a childcare subsidy program? | numeric | 64.6% | N/A |
| `mmi019_1` | Application process? | numeric | 93.3% | N/A |
| `mmi019_2` | Amount of assistance? | numeric | 93.3% | N/A |
| `mmi019_3` | Childcare options you can access with the subsidy? | numeric | 93.3% | N/A |
| `mmi100` | Does your child require childcare on evenings, weekends, or overnight?  | numeric | 39.5% | N/A |
| `mmi101` | DURING THE PAST 12 MONTHS, has a lack of reliable transportation kept you from getting to work, school, medical appointments, or other daily needs? | numeric | 36.5% | N/A |
| `mmi110` | how often is this child affectionate and tender? | numeric | 40.6% | N/A |
| `mmi111` | how often does this child bounce back quickly when things do not go their way? | numeric | 40.6% | N/A |
| `mmi112` | how often does this child show interest and curiosity in learning new things? | numeric | 40.8% | N/A |
| `mmi113` | how often does this child smile and laugh? | numeric | 40.7% | N/A |
| `mmi120` | Talk together about what to do? | numeric | 35.9% | N/A |
| `mmi121` | Work together to solve our problems? | numeric | 36.2% | N/A |
| `mmi122` | Know we have strengths to draw on? | numeric | 36.4% | N/A |
| `mmi123` | Stay hopeful even in difficult times? | numeric | 36.5% | N/A |
| `mmifs009` | You were worried you would not have enough food to eat? | numeric | 76.0% | N/A |
| `mmifs010` | You were unable to eat healthy and nutritious food? | numeric | 76.1% | N/A |
| `mmifs011` | You ate only a few kinds of food? | numeric | 76.1% | N/A |
| `mmifs012` | You had to skip a meal? | numeric | 76.2% | N/A |
| `mmifs013` | You ate less than you thought you should? | numeric | 76.1% | N/A |
| `mmifs014` | Your household ran out of food? | numeric | 76.1% | N/A |
| `mmifs015` | You were hungry but did not eat? | numeric | 76.1% | N/A |
| `mmifs016` | You went without eating for a whole day? | numeric | 76.2% | N/A |
| `mmihl002` | Is English the primary language spoken at home? | numeric | 36.6% | N/A |
| `module_2_family_information_complete` | Module 2 Family Information Complete | numeric | 0.0% | N/A |
| `module_2_family_information_timestamp` | Module 2 Family Information Timestamp | character | 35.2% | N/A |
| `module_3_child_information_complete` | Module 3 Child Information Complete | numeric | 0.0% | N/A |
| `module_3_child_information_timestamp` | Module 3 Child Information Timestamp | character | 38.2% | N/A |
| `module_4_home_learning_environment_complete` | Module 4 Home Learning Environment Complete | numeric | 0.0% | N/A |
| `module_4_home_learning_environment_timestamp` | Module 4 Home Learning Environment Timestamp | character | 39.4% | N/A |
| `module_5_birthdate_confirmation_complete` | Module 5 Birthdate Confirmation Complete | numeric | 0.0% | N/A |
| `module_5_birthdate_confirmation_timestamp` | Module 5 Birthdate Confirmation Timestamp | character | 40.5% | N/A |
| `module_6_0_89_complete` | Module 6 0 89 Complete | numeric | 0.0% | N/A |
| `module_6_0_89_timestamp` | Module 6 0 89 Timestamp | character | 99.4% | N/A |
| `module_6_1097_2191_complete` | Module 6 1097 2191 Complete | numeric | 0.0% | N/A |
| `module_6_1097_2191_timestamp` | Module 6 1097 2191 Timestamp | character | 61.9% | N/A |
| `module_6_180_364_complete` | Module 6 180 364 Complete | numeric | 0.0% | N/A |
| `module_6_180_364_timestamp` | Module 6 180 364 Timestamp | character | 94.9% | N/A |
| `module_6_365_548_complete` | Module 6 365 548 Complete | numeric | 0.0% | N/A |
| `module_6_365_548_timestamp` | Module 6 365 548 Timestamp | character | 92.2% | N/A |
| `module_6_549_731_complete` | Module 6 549 731 Complete | numeric | 0.0% | N/A |
| `module_6_549_731_timestamp` | Module 6 549 731 Timestamp | character | 92.5% | N/A |
| `module_6_732_914_complete` | Module 6 732 914 Complete | numeric | 0.0% | N/A |
| `module_6_732_914_timestamp` | Module 6 732 914 Timestamp | character | 88.1% | N/A |
| `module_6_90_179_complete` | Module 6 90 179 Complete | numeric | 0.0% | N/A |
| `module_6_90_179_timestamp` | Module 6 90 179 Timestamp | character | 99.0% | N/A |
| `module_6_915_1096_complete` | Module 6 915 1096 Complete | numeric | 0.0% | N/A |
| `module_6_915_1096_timestamp` | Module 6 915 1096 Timestamp | character | 89.5% | N/A |
| `module_8_followup_information_complete` | Module 8 Followup Information Complete | numeric | 0.0% | N/A |
| `module_8_followup_information_timestamp` | Module 8 Followup Information Timestamp | character | 50.5% | N/A |
| `module_9_compensation_information_complete` | Module 9 Compensation Information Complete | numeric | 0.0% | N/A |
| `module_9_compensation_information_timestamp` | Module 9 Compensation Information Timestamp | character | 49.9% | N/A |
| `mrw001` | This question is about all of your children. 

Does your household pay for at least 10 hours of childcare per week for more than one child? 

This could be a childcare center, preschool, family childcare home, nanny, au pair, babysitter, before/after school program, or relative. | numeric | 39.1% | N/A |
| `mrw002` | This question is about all of your children. 

In a typical week, about how much does your household pay for childcare total across all childcare arrangements? | numeric | 74.3% | N/A |
| `mrw003_1` | This question is about all of your children. 

In a typical week, about how much financial support do you receive from other individuals, including family, to help cover the cost of childcare?  

Enter 0 if you receive no such financial support. | numeric | 74.2% | N/A |
| `mrw003_2` | In a typical week, about how much financial support do you receive from other individuals, including family, to help cover the cost of childcare for your child?  

Enter 0 if you receive no such financial support.

Use the slider to select a value that best represents this value $[mrw003_2] | numeric | 66.0% | N/A |
| `n_kidsight_psychosocial_responses` | N Kidsight Psychosocial Responses | numeric | 85.5% | N/A |
| `nom044` | To what extent do your child's health conditions or problems affect their ability to do things? | numeric | 100.0% | N/A |
| `nom046x` | How would you describe the condition of your child's teeth? | numeric | 39.4% | N/A |
| `nom047` | How often does this child show concern when they see others are hurt or unhappy? | numeric | 98.7% | N/A |
| `nos` | 5 Nos | numeric | 99.4% | N/A |
| `nos_count_90_179` | 3 consecutive No's count  | numeric | 99.0% | N/A |
| `nschj012` | Does your child have another parent or adult caregiver who lives in this household? | numeric | 36.7% | N/A |
| `nschj013` | How is this other caregiver related to your child? | numeric | 51.2% | N/A |
| `nschj017` | What is the highest grade or level of school this caregiver has completed? | numeric | 51.4% | N/A |
| `ps001` | Do you have any concerns about how your child behaves? | numeric | 48.2% | N/A |
| `ps002` | Does your child eat too little? | numeric | 48.3% | N/A |
| `ps003` | Does your child seem fussy or cry, and you are not able to console him/her? | numeric | 48.2% | N/A |
| `ps004` | Does your child show little interest in things around him/her? | numeric | 48.3% | N/A |
| `ps005` | Does your child sleep less than other children of the same age? | numeric | 50.3% | N/A |
| `ps006` | Is your child irritable or fussy? | numeric | 48.4% | N/A |
| `ps007` | Does your child have a hard time calming down even when you soothe him/her? | numeric | 48.2% | N/A |
| `ps008` | If your child gets upset, do they cry for a long time? | numeric | 48.2% | N/A |
| `ps009` | Does your child reject or turn away from affection (e.g., refuses or pulls away from hugs from well-known family members)? | numeric | 48.2% | N/A |
| `ps010` | Does your child have difficulty staying asleep? | numeric | 48.2% | N/A |
| `ps011` | Does your child have difficulty falling asleep at night? | numeric | 48.1% | N/A |
| `ps013` | Does your child wake up more than two times at night and want your attentions (e.g., cries, asks for you)? | numeric | 48.2% | N/A |
| `ps014` | When upset, does your child get very still, freeze or does not move? | numeric | 48.8% | N/A |
| `ps015` | Do you have any concerns about how your child gets along with others? | numeric | 48.5% | N/A |
| `ps016` | Does your child at times isolate themself or become withdrawn? | numeric | 48.9% | N/A |
| `ps017` | Does your child have an irregular eating pattern? | numeric | 48.6% | N/A |
| `ps018` | Does your child become afraid around strangers, even when you are with him/her? | numeric | 48.4% | N/A |
| `ps019` | Does your child become extremely distressed/upset/disturbed (e.g., cries, screams) in response to loud sounds or bright lights? | numeric | 48.3% | N/A |
| `ps020` | Does your child cry or whine when he/she is made to wait for something he/she wants (e.g., toy or food)? | numeric | 48.5% | N/A |
| `ps022` | Does your child intentionally try to hurt you or other familiar adults? | numeric | 48.6% | N/A |
| `ps023` | Does your child kick, bite, or hit familiar adults? | numeric | 48.7% | N/A |
| `ps024` | Does your child kick, bite, or hit other children for no apparent reason? | numeric | 48.5% | N/A |
| `ps025` | Does your child not seem hungry when it is time to eat? | numeric | 48.5% | N/A |
| `ps026` | Does your child cry for no reason (e.g., when he/she is not hungry or not tired)? | numeric | 48.5% | N/A |
| `ps027` | Does your child have extreme changes in emotions (e.g., quickly changing from very happy to very angry) for not apparent reason? | numeric | 48.5% | N/A |
| `ps028` | Does your child lose their temper? | numeric | 48.6% | N/A |
| `ps029` | Does your child show panic or fear for no reason? | numeric | 48.7% | N/A |
| `ps030` | Does your child refuse to eat foods that you think are healthy? | numeric | 48.4% | N/A |
| `ps031` | Does your child resist eating? | numeric | 48.6% | N/A |
| `ps032` | Is your child intentionally mean to other children? | numeric | 48.6% | N/A |
| `ps034` | Does your child have trouble paying attention? | numeric | 48.8% | N/A |
| `ps035` | Does your child prefer to play alone, even when other children are present? | numeric | 49.1% | N/A |
| `ps036` | Does your child act impulsively without thinking (e.g., running into the street without looking or doing other dangerous behaviors)? | numeric | 49.3% | N/A |
| `ps037` | Does your child get easily frustrated with everyday tasks? | numeric | 49.4% | N/A |
| `ps038` | Does your child have difficulty taking turns when playing with others? | numeric | 49.8% | N/A |
| `ps039` | Does your child ignore you or seem angry with you when you do not immediately respond to him/her? | numeric | 49.0% | N/A |
| `ps040` | Does your child get worried or anxious? | numeric | 50.4% | N/A |
| `ps041` | Does your child have difficulty getting along with other children? | numeric | 49.3% | N/A |
| `ps042` | Does your child refuse to play with other children? | numeric | 49.3% | N/A |
| `ps043` | Does your child scream while still asleep and cannot be comforted? | numeric | 48.8% | N/A |
| `ps044` | After you have been separated, does your child seem upset (e.g., angry or withdrawn) when you are reunited? | numeric | 49.0% | N/A |
| `ps045` | Is your child intentionally cruel to animals? | numeric | 48.8% | N/A |
| `ps046` | Is your child impatient or unwilling to wait when you ask him/her to? | numeric | 49.3% | N/A |
| `ps047` | Is your child unable to sit still? | numeric | 49.1% | N/A |
| `ps048` | Is your child sad or unhappy? | numeric | 48.7% | N/A |
| `ps049` | Does your child hurt himself/herself intentionally (e.g. pulling his/her hair out or banging his/her head)? | numeric | 48.2% | N/A |
| `q1347` | Are you interested in participating in future research? | numeric | 50.7% | N/A |
| `q1348` | Please provide your mobile phone number if you prefer phone contact. | character | 85.3% | N/A |
| `q1394` | First Name: | character | 51.8% | N/A |
| `q1394a` | Last Name: | character | 51.8% | N/A |
| `q1395` | Street Address: | character | 52.4% | N/A |
| `q1396` | Town/City: | character | 52.4% | N/A |
| `q1397` | State: | character | 52.3% | N/A |
| `q1398` | Zip code: | character | 52.3% | N/A |
| `q1502` | How well do you think you are handling the day-to-day demands of raising children? | numeric | 36.2% | N/A |
| `q1503` | Angry with your child? | numeric | 36.3% | N/A |
| `q1504` | That your child does things that really bother you a lot? | numeric | 36.7% | N/A |
| `q1505` | That your child is much harder to care for than most children his or her age? | numeric | 36.5% | N/A |
| `q939___1` | Q939   1 | numeric | 0.0% | N/A |
| `q939___2` | Q939   2 | numeric | 0.0% | N/A |
| `q939___3` | Q939   3 | numeric | 0.0% | N/A |
| `q939___4` | Q939   4 | numeric | 0.0% | N/A |
| `q939___5` | Q939   5 | numeric | 0.0% | N/A |
| `q939___6` | Q939   6 | numeric | 0.0% | N/A |
| `q939___7` | Q939   7 | numeric | 0.0% | N/A |
| `q939___8` | Q939   8 | numeric | 0.0% | N/A |
| `q940` | How many times has your care arrangement for your child changed in the past 12 months? | numeric | 64.3% | N/A |
| `q941` | Overall, how satisfied are you with the quality of care and education that your primary childcare arrangement provides to your child? | numeric | 64.4% | N/A |
| `q943` | How many hours per week do you usually work outside the home? | numeric | 36.1% | N/A |
| `q958` | Across all providers, how many total hours does your child spend in childcare during a regular week? 

Please enter a number, such as 20. | character | 64.7% | N/A |
| `q959___1` | Q959   1 | numeric | 0.0% | N/A |
| `q959___2` | Q959   2 | numeric | 0.0% | N/A |
| `q959___3` | Q959   3 | numeric | 0.0% | N/A |
| `q959___4` | Q959   4 | numeric | 0.0% | N/A |
| `q959___5` | Q959   5 | numeric | 0.0% | N/A |
| `q959___6` | Q959   6 | numeric | 0.0% | N/A |
| `q960` | DURING THE PAST YEAR, is there anything that you think has affected your child's development, positively or negatively? | numeric | 39.9% | N/A |
| `redcap_survey_identifier` | Redcap Survey Identifier | numeric | 93.9% | N/A |
| `sf018` | While your child is on his/her back, can he/she bring his/her hands together such that the hands touch each other? | numeric | 99.5% | N/A |
| `sf019` | Does your child move excitedly, kick legs, move arms or trunk, or make coo noises when a known person enters the room or speaks to him/her? | numeric | 99.5% | N/A |
| `sleeping_gsed_pf_2022` | Sleeping Gsed Pf 2022 | numeric | 43.9% | N/A |
| `sleeping_gsed_pf_2022_csem` | Sleeping Gsed Pf 2022 Csem | numeric | 43.9% | N/A |
| `social_competency_gsed_pf_2022` | Social Competency Gsed Pf 2022 | numeric | 43.9% | N/A |
| `social_competency_gsed_pf_2022_csem` | Social Competency Gsed Pf 2022 Csem | numeric | 43.9% | N/A |
| `source_project` | Source Project | factor | 0.0% | 1 (kidsights_data_survey), 2 (kidsights_email_registration), 3 (kidsights_public), 4 (kidsights_public_birth) |
| `sq001` | Please enter your 5-digit zip code. | character | 25.4% | N/A |
| `sq002___1` | Sq002   1 | numeric | 0.0% | N/A |
| `sq002___10` | Sq002   10 | numeric | 0.0% | N/A |
| `sq002___11` | Sq002   11 | numeric | 0.0% | N/A |
| `sq002___12` | Sq002   12 | numeric | 0.0% | N/A |
| `sq002___13` | Sq002   13 | numeric | 0.0% | N/A |
| `sq002___14` | Sq002   14 | numeric | 0.0% | N/A |
| `sq002___15` | Sq002   15 | numeric | 0.0% | N/A |
| `sq002___16` | Sq002   16 | numeric | 0.0% | N/A |
| `sq002___2` | Sq002   2 | numeric | 0.0% | N/A |
| `sq002___3` | Sq002   3 | numeric | 0.0% | N/A |
| `sq002___4` | Sq002   4 | numeric | 0.0% | N/A |
| `sq002___5` | Sq002   5 | numeric | 0.0% | N/A |
| `sq002___6` | Sq002   6 | numeric | 0.0% | N/A |
| `sq002___7` | Sq002   7 | numeric | 0.0% | N/A |
| `sq002___8` | Sq002   8 | numeric | 0.0% | N/A |
| `sq002___9` | Sq002   9 | numeric | 0.0% | N/A |
| `sq003` | Are you of Hispanic, Latino or Spanish origin? | numeric | 36.4% | N/A |
| `survey_stop` | survey Stop | numeric | 99.4% | N/A |
| `too_few_item_responses` | Too Few Item Responses | logical | 85.5% | N/A |

## Psychosocial_Problems_General

**Description:** No description available

**Variables:** 16  
**Average Missing:** 83.2%  
**Data Types:** 0 factors, 16 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `credi030` | Does your child involve others in play? For example, play interactive games with other children. | numeric | 97.1% | N/A |
| `credi031` | When the child is upset, does he/she calm down quickly on his/her own? | numeric | 95.5% | N/A |
| `credi045` | Is your child kind to younger children? For example, speaks to them nicely and touches them gently. | numeric | 95.8% | N/A |
| `ecdi018` | Does your child get along well with other children? | numeric | 93.6% | N/A |
| `nom047x` | How often does this child show concern when they see others who are hurt or unhappy?  | numeric | 98.9% | N/A |
| `nom048x` | Compared to other children his or her age, how much difficulty does this child have making or keeping friends? | numeric | 63.2% | N/A |
| `nom049` | How often does this child play well with others? | numeric | 98.7% | N/A |
| `nom049x` | How often does this child play well with other children? | numeric | 98.9% | N/A |
| `nom052y` | How often does this child lose their temper? | numeric | 63.2% | N/A |
| `nom054x` | How often does this child get easily distracted? | numeric | 63.2% | N/A |
| `nom056x` | How often does this child have difficulty waiting for their turn? | numeric | 62.9% | N/A |
| `nom059` | How often does your child show concern when they see others are hurt or unhappy? | numeric | 82.1% | N/A |
| `nom060y` | How often does this child have trouble calming down? | numeric | 62.9% | N/A |
| `nom061` | My child bounces back easily when things do not go his/her way. | numeric | 96.0% | N/A |
| `nom061x` | Does your child bounce back quickly when things do not go their way? | numeric | 96.0% | N/A |
| `nom062y` | How often does this child have difficulty when asked to end one activity and start a new activity? | numeric | 62.9% | N/A |

## Socemo

**Description:** No description available

**Variables:** 55  
**Average Missing:** 91.0%  
**Data Types:** 0 factors, 55 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `c004` | <div class="rich-text-field-label"><p>Does your child smile?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155602&doc_id_hash=e02d922a37d0c566bc68918464b6f1928dd4054e" alt="" width="400" height="206"></p></div> | numeric | 99.5% | N/A |
| `c010` | Does your child smile when you smile or talk with him/her? | numeric | 99.5% | N/A |
| `c014` | When you are about to pick up your child, does he/she act happy or excited? | numeric | 99.5% | N/A |
| `c015` | <div class="rich-text-field-label"><p>Does your child look at your face when you speak to him/her?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155595&doc_id_hash=ee82ca918253f66679d4620c67e1b29112c381aa" width="400" height="222"></p></div> | numeric | 99.5% | N/A |
| `c016` | Does your child stop crying or calm down when you come to the room after being out of sight, or when you pick him or her up? | numeric | 99.4% | N/A |
| `c020` | <div class="rich-text-field-label"><p>Does your child sometimes suck his/her thumb or fingers?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155590&doc_id_hash=784fa9e7d6a3a650e3e2fb955c46e6a451df1d5f" alt="" width="400" height="300"></p></div> | numeric | 99.4% | N/A |
| `c025` | Does your child move excitedly, kick legs, move arms or trunk, or make coo noises when a known person enters the room or speaks to them? | numeric | 99.5% | N/A |
| `c031` | If you play a game with your child, does he/she respond with interest? For example, if you play peek-a-boo, pat-a-cake, wave bye-bye, etc. does your child smile, widen their eyes, kick or move arms or vocalize? | numeric | 99.0% | N/A |
| `c032` | Does your child smile or become excited when seeing someone familiar? | numeric | 99.0% | N/A |
| `c045` | Is your child interested when he/she sees other children playing? Does she or he watch, smile, or look excited? | numeric | 99.2% | N/A |
| `c075` | Does your child put his/her hands out to have them washed? | numeric | 94.3% | N/A |
| `c082` | Even if your child is unable to do singing games, does he/she enjoy them and want to be a part of them? | numeric | 95.2% | N/A |
| `c085` | Can your child greet people either by giving his/her hand or saying "hello"? | numeric | 93.1% | N/A |
| `c086` | Does your child share with others? For example, food. | numeric | 92.5% | N/A |
| `c088` | Is your child able to go poo or pee without having accidents, like wetting or soiling themselves? | numeric | 62.2% | N/A |
| `c094` | Can your child break off pieces of food and feed them to him/her-self? | numeric | 93.6% | N/A |
| `c095` | Does your child show independence, such as wanting to pick their own clothes, choose their own activities, or try to go outside alone? | numeric | 95.9% | N/A |
| `c114` | Can your child say what he/she likes or dislikes? For example, "I like sweets." | numeric | 91.2% | N/A |
| `c123` | Does your child know to keep quiet when the situation requires it? For example, at ceremonies, or when someone is asleep. | numeric | 90.8% | N/A |
| `c125` | Can your child tell you when he/she is happy, angry, or sad? | numeric | 88.7% | N/A |
| `c128` | Can your child tell you when others are happy, angry, or sad? | numeric | 94.6% | N/A |
| `c130` | Does your child help out around the house with simple chores, even if he/she doesn't do them well? | numeric | 97.6% | N/A |
| `c134` | Can your child go to the toilet by him/herself? | numeric | 89.8% | N/A |
| `c137` | Does your child show respect around elders? | numeric | 95.1% | N/A |
| `credi001` | Does the child smile when others smile at him/her? | numeric | 99.6% | N/A |
| `credi005` | Does your child react differently according to the tone of your voice? For example, smile when you say something in a happy tone. | numeric | 99.6% | N/A |
| `credi017` | Does your child often show affection toward others? For example, hugging parents, brothers, or sisters. | numeric | 99.2% | N/A |
| `credi019` | Can the child indicate when he/she needs to go to the toilet? | numeric | 93.5% | N/A |
| `credi020` | Can your child sit or play on his/her own for at least 20 minutes? | numeric | 94.8% | N/A |
| `credi021` | Does the child listen to someone telling a story with interest? | numeric | 97.7% | N/A |
| `credi025` | Does the child imitate others' behaviors, such as washing hands or dishes? | numeric | 96.1% | N/A |
| `credi028` | Does your child usually follow rules and obey adults? For example, "Go there" or "Don't do that." | numeric | 94.6% | N/A |
| `credi029` | Can the child sit still when asked to by an adult? For example, for two minutes. | numeric | 93.7% | N/A |
| `credi036` | Can your child concentrate on one task, such as playing with friends or eating a meal, for 20 minutes? | numeric | 94.2% | N/A |
| `credi038` | Does your child usually finish an activity he/she enjoys, such as a game or book? | numeric | 94.2% | N/A |
| `credi041` | Can your child tell you when he/she is tired or hungry? | numeric | 96.6% | N/A |
| `credi046` | Does the child greet neighbors or other people he/she knows without being told? For example, by saying hello or gesturing hello. | numeric | 92.8% | N/A |
| `credi052` | Does your child sometimes save things like candy or new toys for the future? | numeric | 91.7% | N/A |
| `credi058` | Does your child ask about familiar people other than parents when they are not there? For example, "Where is the neighbor?" | numeric | 88.7% | N/A |
| `ecdi015` | Can your child do an activity such as coloring without repeatedly asking for help or giving up too quickly? | numeric | 94.0% | N/A |
| `ecdi015x` | Can your child do an activity, such as coloring or playing with building blocks, without repeatedly asking for help or giving up too quickly? | numeric | 88.5% | N/A |
| `ecdi016` | Does your child ask about familiar people other than parents when they are not there? For example, "Where is Grandma?" | numeric | 94.1% | N/A |
| `ecdi017` | Does your child offer to help someone who seems to need help? | numeric | 91.0% | N/A |
| `nom006` | How often can your child explain things they have seen or done so that you understand? | numeric | 95.6% | N/A |
| `nom053` | Can your child recognize and name emotions in themselves? | numeric | 81.7% | N/A |
| `nom053x` | How often can your child recognize and name their own emotions? | numeric | 80.3% | N/A |
| `nom057` | How often does your child take turns during games or fun activities? | numeric | 91.0% | N/A |
| `nom059x` | How often does your child keep working on a task even when it is hard for them? | numeric | 80.5% | N/A |
| `nom102` | How often does this child keep working at something until he or she is finished? | numeric | 62.9% | N/A |
| `nom103` | When this child is paying attention, how often can he or she follow instructions to complete a simple task? | numeric | 63.0% | N/A |
| `nom104` | Compared to other children their age, how often is this child able to sit still? | numeric | 63.0% | N/A |
| `nom2202` | How often can this child focus on a task you give them for at least a few minutes? For example, can this child focus on simple chores? | numeric | 63.0% | N/A |
| `nom2208` | How often does this child share toys or games with other children? | numeric | 63.1% | N/A |
| `sf021` | <div class="rich-text-field-label"><p>If you play a game with your child, does he/she respond with interest? For example, if you play peek-a-boo, pat-a-cake, wave bye-bye, etc. does your child smile, widen his/her eyes, kick or move arms or vocalize?</p> <p><img src="https://unmcredcap.unmc.edu/redcap/redcap_v15.1.0/DataEntry/image_view.php?pid=7679&id=155603&doc_id_hash=99f6ddcda0c611bd8a9a0a1d5d64694c28c5ea8a" alt="" width="400" height="225"></p></div> | numeric | 99.5% | N/A |
| `sf093` | Does your child show independence? For example, wants to go to visit a friend's house. | numeric | 97.0% | N/A |

---

## Notes

- **Missing percentages** are calculated as (missing values / total records) × 100
- **Factor variables** show the most common levels with their counts
- **Numeric variables** display min, max, and mean values where available
- **Logical variables** show counts of TRUE and FALSE values

*Generated automatically from metadata on 2025-12-09 by the Kidsights Data Platform*

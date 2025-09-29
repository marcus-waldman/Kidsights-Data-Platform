# NE25 Data Dictionary

**Generated:** 2025-09-29 14:00:29  
**Total Records:** 4826  
**Total Variables:** 554  
**Categories:** 5  

## Overview

This data dictionary describes all variables in the NE25 transformed dataset. 
The data comes from REDCap surveys and has been processed through the Kidsights 
data transformation pipeline, which applies standardized harmonization rules 
for race/ethnicity, education categories, and other demographic variables.

## Table of Contents

- [Caregiver Relationship](#caregiver-relationship) (2 variables)
- [Age](#age) (3 variables)
- [Eligibility](#eligibility) (3 variables)
- [Geography](#geography) (3 variables)
- [Other](#other) (543 variables)

## Caregiver Relationship

**Description:** Variables describing relationships between caregivers and children, including gender and maternal status

**Variables:** 2  
**Average Missing:** 23.3%  
**Data Types:** 0 factors, 1 numeric, 0 logical, 1 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `module_7_child_emotions_and_relationships_complete` | Module 7 Child Emotions And Relationships Complete | numeric | 0.0% | N/A |
| `module_7_child_emotions_and_relationships_timestamp` | Module 7 Child Emotions And Relationships Timestamp | character | 46.6% | N/A |

## Age

**Description:** Age variables for children and caregivers in different units (days, months, years)

**Variables:** 3  
**Average Missing:** 42.9%  
**Data Types:** 1 factors, 2 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `age_in_days` | Age In Days | numeric | 25.2% | N/A |
| `language` | Language | factor | 3.5% | 1 (en), 2 (es) |
| `language_preference` | Language Preference | numeric | 100.0% | N/A |

## Eligibility

**Description:** No description available

**Variables:** 3  
**Average Missing:** 0.0%  
**Data Types:** 0 factors, 0 numeric, 3 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `authentic` | Authentic | logical | 0.0% | N/A |
| `eligible` | Eligible | logical | 0.0% | N/A |
| `include` | Include | logical | 0.0% | N/A |

## Geography

**Description:** No description available

**Variables:** 3  
**Average Missing:** 8.5%  
**Data Types:** 0 factors, 3 numeric, 0 logical, 0 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `eqstate` | Eqstate | numeric | 25.4% | N/A |
| `state_law_prohibits_sending_compensation_electronically___1` | State Law Prohibits Sending Compensation Electronically   1 | numeric | 0.0% | N/A |
| `state_law_requires_that_kidsights_data_collect_my_name___1` | State Law Requires That Kidsights Data Collect My Name   1 | numeric | 0.0% | N/A |

## Other

**Description:** No description available

**Variables:** 543  
**Average Missing:** 60.6%  
**Data Types:** 5 factors, 506 numeric, 0 logical, 32 character

| Variable | Label | Type | Missing | Details |
|----------|-------|------|---------|---------|
| `authenticity` | Authenticity | factor | 0.0% | 1 (Fail), 2 (Pass) |
| `c004` | C004 | numeric | 99.5% | N/A |
| `c005` | C005 | numeric | 99.5% | N/A |
| `c007` | C007 | numeric | 99.5% | N/A |
| `c010` | C010 | numeric | 99.5% | N/A |
| `c012` | C012 | numeric | 99.5% | N/A |
| `c013` | C013 | numeric | 99.5% | N/A |
| `c014` | C014 | numeric | 99.5% | N/A |
| `c015` | C015 | numeric | 99.5% | N/A |
| `c016` | C016 | numeric | 99.4% | N/A |
| `c017` | C017 | numeric | 99.5% | N/A |
| `c018` | C018 | numeric | 99.5% | N/A |
| `c019` | C019 | numeric | 99.5% | N/A |
| `c020` | C020 | numeric | 99.4% | N/A |
| `c021` | C021 | numeric | 99.5% | N/A |
| `c022` | C022 | numeric | 99.5% | N/A |
| `c023` | C023 | numeric | 99.0% | N/A |
| `c024` | C024 | numeric | 99.5% | N/A |
| `c025` | C025 | numeric | 99.5% | N/A |
| `c026` | C026 | numeric | 99.5% | N/A |
| `c027` | C027 | numeric | 99.1% | N/A |
| `c028` | C028 | numeric | 99.2% | N/A |
| `c029` | C029 | numeric | 99.4% | N/A |
| `c029x` | C029X | numeric | 99.5% | N/A |
| `c030` | C030 | numeric | 99.5% | N/A |
| `c030x` | C030X | numeric | 99.6% | N/A |
| `c031` | C031 | numeric | 99.0% | N/A |
| `c032` | C032 | numeric | 99.0% | N/A |
| `c033` | C033 | numeric | 99.0% | N/A |
| `c034` | C034 | numeric | 99.0% | N/A |
| `c035` | C035 | numeric | 99.0% | N/A |
| `c036` | C036 | numeric | 94.9% | N/A |
| `c037` | C037 | numeric | 99.0% | N/A |
| `c038` | C038 | numeric | 99.2% | N/A |
| `c039` | C039 | numeric | 99.5% | N/A |
| `c040` | C040 | numeric | 99.3% | N/A |
| `c041` | C041 | numeric | 99.5% | N/A |
| `c042` | C042 | numeric | 99.0% | N/A |
| `c043` | C043 | numeric | 99.2% | N/A |
| `c044` | C044 | numeric | 99.2% | N/A |
| `c045` | C045 | numeric | 99.0% | N/A |
| `c046` | C046 | numeric | 99.4% | N/A |
| `c047` | C047 | numeric | 99.5% | N/A |
| `c048` | C048 | numeric | 99.3% | N/A |
| `c049` | C049 | numeric | 99.5% | N/A |
| `c050` | C050 | numeric | 94.9% | N/A |
| `c051` | C051 | numeric | 94.9% | N/A |
| `c052` | C052 | numeric | 94.9% | N/A |
| `c053` | C053 | numeric | 94.9% | N/A |
| `c054` | C054 | numeric | 94.9% | N/A |
| `c055` | C055 | numeric | 95.4% | N/A |
| `c056` | C056 | numeric | 95.2% | N/A |
| `c057` | C057 | numeric | 95.3% | N/A |
| `c058` | C058 | numeric | 95.2% | N/A |
| `c059` | C059 | numeric | 95.0% | N/A |
| `c060` | C060 | numeric | 95.5% | N/A |
| `c061` | C061 | numeric | 95.8% | N/A |
| `c062` | C062 | numeric | 92.8% | N/A |
| `c063` | C063 | numeric | 92.2% | N/A |
| `c064` | C064 | numeric | 94.9% | N/A |
| `c065` | C065 | numeric | 92.2% | N/A |
| `c066` | C066 | numeric | 93.3% | N/A |
| `c067` | C067 | numeric | 93.3% | N/A |
| `c068` | C068 | numeric | 96.5% | N/A |
| `c069` | C069 | numeric | 93.4% | N/A |
| `c070` | C070 | numeric | 93.1% | N/A |
| `c071` | C071 | numeric | 92.6% | N/A |
| `c072` | C072 | numeric | 92.2% | N/A |
| `c073` | C073 | numeric | 94.0% | N/A |
| `c074` | C074 | numeric | 94.8% | N/A |
| `c075` | C075 | numeric | 94.0% | N/A |
| `c076` | C076 | numeric | 93.4% | N/A |
| `c077` | C077 | numeric | 94.1% | N/A |
| `c078` | C078 | numeric | 92.2% | N/A |
| `c079` | C079 | numeric | 94.6% | N/A |
| `c080` | C080 | numeric | 95.0% | N/A |
| `c081` | C081 | numeric | 96.7% | N/A |
| `c082` | C082 | numeric | 94.9% | N/A |
| `c083` | C083 | numeric | 94.7% | N/A |
| `c084` | C084 | numeric | 95.3% | N/A |
| `c085` | C085 | numeric | 93.0% | N/A |
| `c086` | C086 | numeric | 92.2% | N/A |
| `c087` | C087 | numeric | 92.6% | N/A |
| `c088` | C088 | numeric | 61.9% | N/A |
| `c089` | C089 | numeric | 94.8% | N/A |
| `c090` | C090 | numeric | 97.0% | N/A |
| `c091` | C091 | numeric | 92.7% | N/A |
| `c092` | C092 | numeric | 90.7% | N/A |
| `c093` | C093 | numeric | 97.5% | N/A |
| `c094` | C094 | numeric | 93.4% | N/A |
| `c095` | C095 | numeric | 95.8% | N/A |
| `c096` | C096 | numeric | 96.4% | N/A |
| `c097` | C097 | numeric | 94.9% | N/A |
| `c098` | C098 | numeric | 92.6% | N/A |
| `c099` | C099 | numeric | 96.3% | N/A |
| `c100` | C100 | numeric | 96.8% | N/A |
| `c101` | C101 | numeric | 97.1% | N/A |
| `c102` | C102 | numeric | 93.2% | N/A |
| `c103` | C103 | numeric | 91.4% | N/A |
| `c104` | C104 | numeric | 97.5% | N/A |
| `c105` | C105 | numeric | 92.6% | N/A |
| `c106` | C106 | numeric | 93.8% | N/A |
| `c107` | C107 | numeric | 94.0% | N/A |
| `c108` | C108 | numeric | 94.0% | N/A |
| `c109` | C109 | numeric | 89.8% | N/A |
| `c110` | C110 | numeric | 90.5% | N/A |
| `c111` | C111 | numeric | 88.2% | N/A |
| `c112` | C112 | numeric | 88.8% | N/A |
| `c113` | C113 | numeric | 92.0% | N/A |
| `c114` | C114 | numeric | 90.8% | N/A |
| `c115` | C115 | numeric | 91.6% | N/A |
| `c116` | C116 | numeric | 89.9% | N/A |
| `c117` | C117 | numeric | 88.2% | N/A |
| `c118` | C118 | numeric | 91.1% | N/A |
| `c119` | C119 | numeric | 92.2% | N/A |
| `c120` | C120 | numeric | 93.0% | N/A |
| `c121` | C121 | numeric | 92.5% | N/A |
| `c122` | C122 | numeric | 93.6% | N/A |
| `c123` | C123 | numeric | 90.1% | N/A |
| `c124` | C124 | numeric | 93.9% | N/A |
| `c125` | C125 | numeric | 88.2% | N/A |
| `c126` | C126 | numeric | 92.8% | N/A |
| `c127` | C127 | numeric | 94.8% | N/A |
| `c128` | C128 | numeric | 94.2% | N/A |
| `c129` | C129 | numeric | 91.4% | N/A |
| `c130` | C130 | numeric | 97.5% | N/A |
| `c131` | C131 | numeric | 94.4% | N/A |
| `c132` | C132 | numeric | 61.9% | N/A |
| `c133` | C133 | numeric | 89.8% | N/A |
| `c134` | C134 | numeric | 89.9% | N/A |
| `c135` | C135 | numeric | 89.6% | N/A |
| `c136` | C136 | numeric | 93.5% | N/A |
| `c137` | C137 | numeric | 93.9% | N/A |
| `c138` | C138 | numeric | 91.2% | N/A |
| `c139` | C139 | numeric | 91.1% | N/A |
| `cace1` | Cace1 | numeric | 36.3% | N/A |
| `cace10` | Cace10 | numeric | 36.6% | N/A |
| `cace2` | Cace2 | numeric | 36.3% | N/A |
| `cace3` | Cace3 | numeric | 36.5% | N/A |
| `cace4` | Cace4 | numeric | 36.6% | N/A |
| `cace5` | Cace5 | numeric | 36.7% | N/A |
| `cace6` | Cace6 | numeric | 36.7% | N/A |
| `cace7` | Cace7 | numeric | 36.7% | N/A |
| `cace8` | Cace8 | numeric | 36.9% | N/A |
| `cace9` | Cace9 | numeric | 36.7% | N/A |
| `cfqb001` | Cfqb001 | numeric | 36.2% | N/A |
| `cname1` | Cname1 | character | 72.4% | N/A |
| `compensation` | Compensation | factor | 0.0% | 1 (Fail), 2 (Pass) |
| `consecutive_nos_180_364` | Consecutive Nos 180 364 | numeric | 94.9% | N/A |
| `consecutive_nos_365_548` | Consecutive Nos 365 548 | numeric | 92.2% | N/A |
| `consecutive_nos_549_731` | Consecutive Nos 549 731 | numeric | 92.6% | N/A |
| `consecutive_nos_732_914` | Consecutive Nos 732 914 | numeric | 88.1% | N/A |
| `consecutive_nos_90_179` | Consecutive Nos 90 179 | numeric | 99.0% | N/A |
| `consecutive_nos_915_1096` | Consecutive Nos 915 1096 | numeric | 89.7% | N/A |
| `consecutive_nos_count` | Consecutive Nos Count | numeric | 99.4% | N/A |
| `consent_date` | Consent Date | character | 24.9% | N/A |
| `consent_doc_complete` | Consent Doc Complete | numeric | 0.0% | N/A |
| `consent_doc_timestamp` | Consent Doc Timestamp | character | 6.6% | N/A |
| `cqfa001` | Cqfa001 | numeric | 36.6% | N/A |
| `cqfa002` | Cqfa002 | numeric | 39.4% | N/A |
| `cqfa005` | Cqfa005 | numeric | 36.0% | N/A |
| `cqfa006` | Cqfa006 | numeric | 36.1% | N/A |
| `cqfa009` | Cqfa009 | numeric | 36.2% | N/A |
| `cqfa010` | Cqfa010 | numeric | 35.9% | N/A |
| `cqfa010a___1` | Cqfa010A   1 | numeric | 0.0% | N/A |
| `cqfa010a___2` | Cqfa010A   2 | numeric | 0.0% | N/A |
| `cqfa010a___3` | Cqfa010A   3 | numeric | 0.0% | N/A |
| `cqfa010a___4` | Cqfa010A   4 | numeric | 0.0% | N/A |
| `cqfa010a___5` | Cqfa010A   5 | numeric | 0.0% | N/A |
| `cqfa010a___6` | Cqfa010A   6 | numeric | 0.0% | N/A |
| `cqfa013` | Cqfa013 | numeric | 39.5% | N/A |
| `cqfb002` | Cqfb002 | numeric | 36.0% | N/A |
| `cqfb007x` | Cqfb007X | numeric | 39.1% | N/A |
| `cqfb008` | Cqfb008 | numeric | 37.2% | N/A |
| `cqfb009` | Cqfb009 | numeric | 36.2% | N/A |
| `cqfb010` | Cqfb010 | numeric | 36.4% | N/A |
| `cqfb011` | Cqfb011 | numeric | 36.2% | N/A |
| `cqfb012` | Cqfb012 | numeric | 36.4% | N/A |
| `cqfb013` | Cqfb013 | numeric | 36.2% | N/A |
| `cqfb014` | Cqfb014 | numeric | 36.5% | N/A |
| `cqfb015` | Cqfb015 | numeric | 36.6% | N/A |
| `cqfb016` | Cqfb016 | numeric | 36.4% | N/A |
| `cqr0011` | Cqr0011 | numeric | 39.7% | N/A |
| `cqr002` | Cqr002 | numeric | 35.7% | N/A |
| `cqr003` | Cqr003 | numeric | 36.7% | N/A |
| `cqr004` | Cqr004 | numeric | 35.7% | N/A |
| `cqr006` | Cqr006 | numeric | 35.3% | N/A |
| `cqr007___1` | Cqr007   1 | numeric | 0.0% | N/A |
| `cqr007___2` | Cqr007   2 | numeric | 0.0% | N/A |
| `cqr007___3` | Cqr007   3 | numeric | 0.0% | N/A |
| `cqr007___4` | Cqr007   4 | numeric | 0.0% | N/A |
| `cqr007___5` | Cqr007   5 | numeric | 0.0% | N/A |
| `cqr007___6` | Cqr007   6 | numeric | 0.0% | N/A |
| `cqr007___7` | Cqr007   7 | numeric | 0.0% | N/A |
| `cqr008` | Cqr008 | numeric | 36.1% | N/A |
| `cqr009` | Cqr009 | numeric | 39.3% | N/A |
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
| `cqr011` | Cqr011 | numeric | 39.1% | N/A |
| `cqr013` | Cqr013 | numeric | 40.0% | N/A |
| `cqr014x` | Cqr014X | numeric | 39.4% | N/A |
| `cqr015` | Cqr015 | numeric | 40.0% | N/A |
| `cqr016` | Cqr016 | numeric | 39.7% | N/A |
| `cqr017` | Cqr017 | numeric | 40.0% | N/A |
| `cqr018` | Cqr018 | numeric | 39.9% | N/A |
| `cqr019` | Cqr019 | numeric | 40.3% | N/A |
| `cqr020` | Cqr020 | numeric | 40.1% | N/A |
| `cqr021` | Cqr021 | numeric | 40.3% | N/A |
| `cqr022` | Cqr022 | numeric | 40.3% | N/A |
| `cqr023` | Cqr023 | numeric | 40.3% | N/A |
| `cqr024` | Cqr024 | numeric | 40.1% | N/A |
| `cqrn012` | Cqrn012 | numeric | 39.9% | N/A |
| `credi001` | Credi001 | numeric | 99.5% | N/A |
| `credi005` | Credi005 | numeric | 99.5% | N/A |
| `credi017` | Credi017 | numeric | 99.1% | N/A |
| `credi019` | Credi019 | numeric | 93.3% | N/A |
| `credi020` | Credi020 | numeric | 94.7% | N/A |
| `credi021` | Credi021 | numeric | 97.4% | N/A |
| `credi025` | Credi025 | numeric | 95.7% | N/A |
| `credi028` | Credi028 | numeric | 94.5% | N/A |
| `credi029` | Credi029 | numeric | 93.2% | N/A |
| `credi030` | Credi030 | numeric | 96.7% | N/A |
| `credi031` | Credi031 | numeric | 95.2% | N/A |
| `credi036` | Credi036 | numeric | 94.0% | N/A |
| `credi038` | Credi038 | numeric | 94.0% | N/A |
| `credi041` | Credi041 | numeric | 96.6% | N/A |
| `credi045` | Credi045 | numeric | 94.6% | N/A |
| `credi046` | Credi046 | numeric | 92.6% | N/A |
| `credi052` | Credi052 | numeric | 91.2% | N/A |
| `credi058` | Credi058 | numeric | 88.2% | N/A |
| `date_complete_check` | Date Complete Check | numeric | 40.4% | N/A |
| `dob` | Dob | character | 25.2% | N/A |
| `dob_match` | Dob Match | numeric | 24.8% | N/A |
| `ecdi007` | Ecdi007 | numeric | 94.1% | N/A |
| `ecdi009x` | Ecdi009X | numeric | 94.5% | N/A |
| `ecdi010` | Ecdi010 | numeric | 94.7% | N/A |
| `ecdi011` | Ecdi011 | numeric | 61.9% | N/A |
| `ecdi014` | Ecdi014 | numeric | 89.8% | N/A |
| `ecdi015` | Ecdi015 | numeric | 93.6% | N/A |
| `ecdi015x` | Ecdi015X | numeric | 88.1% | N/A |
| `ecdi016` | Ecdi016 | numeric | 94.0% | N/A |
| `ecdi017` | Ecdi017 | numeric | 90.3% | N/A |
| `ecdi018` | Ecdi018 | numeric | 93.3% | N/A |
| `eligibility` | Eligibility | factor | 0.0% | 1 (Fail), 2 (Pass) |
| `eligibility_form_complete` | Eligibility Form Complete | numeric | 0.0% | N/A |
| `eligibility_form_timestamp` | Eligibility Form Timestamp | character | 24.7% | N/A |
| `email` | Email | character | 84.6% | N/A |
| `email_followup` | Email Followup | character | 66.0% | N/A |
| `email_registration_complete` | Email Registration Complete | numeric | 84.6% | N/A |
| `email_registration_timestamp` | Email Registration Timestamp | character | 84.6% | N/A |
| `eq001` | Eq001 | numeric | 25.0% | N/A |
| `eq002` | Eq002 | numeric | 25.1% | N/A |
| `eq003` | Eq003 | numeric | 24.9% | N/A |
| `eq004a` | Eq004A | character | 40.5% | N/A |
| `extraction_id` | Extraction Id | factor | 0.0% | 1 (ne25_20250929_135849) |
| `fci_a_1` | Fci A 1 | numeric | 39.7% | N/A |
| `fci_a_2` | Fci A 2 | numeric | 40.3% | N/A |
| `fci_a_3` | Fci A 3 | numeric | 40.2% | N/A |
| `fci_b_1` | Fci B 1 | numeric | 40.5% | N/A |
| `fci_b_2` | Fci B 2 | numeric | 42.9% | N/A |
| `fci_c_1` | Fci C 1 | numeric | 40.1% | N/A |
| `fci_c_10` | Fci C 10 | numeric | 40.5% | N/A |
| `fci_c_11` | Fci C 11 | numeric | 40.2% | N/A |
| `fci_c_2` | Fci C 2 | numeric | 40.0% | N/A |
| `fci_c_3` | Fci C 3 | numeric | 40.1% | N/A |
| `fci_c_4` | Fci C 4 | numeric | 40.0% | N/A |
| `fci_c_5` | Fci C 5 | numeric | 40.2% | N/A |
| `fci_c_6` | Fci C 6 | numeric | 40.5% | N/A |
| `fci_c_7` | Fci C 7 | numeric | 40.5% | N/A |
| `fci_c_8` | Fci C 8 | numeric | 40.2% | N/A |
| `fci_c_9` | Fci C 9 | numeric | 40.3% | N/A |
| `fci_d_1` | Fci D 1 | numeric | 40.2% | N/A |
| `fci_d_10` | Fci D 10 | numeric | 40.4% | N/A |
| `fci_d_11` | Fci D 11 | numeric | 40.3% | N/A |
| `fci_d_2` | Fci D 2 | numeric | 40.2% | N/A |
| `fci_d_3` | Fci D 3 | numeric | 40.8% | N/A |
| `fci_d_4` | Fci D 4 | numeric | 40.4% | N/A |
| `fci_d_5` | Fci D 5 | numeric | 40.5% | N/A |
| `fci_d_6` | Fci D 6 | numeric | 40.3% | N/A |
| `fci_d_7` | Fci D 7 | numeric | 40.4% | N/A |
| `fci_d_8` | Fci D 8 | numeric | 40.5% | N/A |
| `fci_d_9` | Fci D 9 | numeric | 40.6% | N/A |
| `financial_compensation_be_sent_to_a_nebraska_residential_address___1` | Financial Compensation Be Sent To A Nebraska Residential Address   1 | numeric | 0.0% | N/A |
| `first_5_nos_1097_2191` | First 5 Nos 1097 2191 | numeric | 61.8% | N/A |
| `first_5_nos_180_364` | First 5 Nos 180 364 | numeric | 94.9% | N/A |
| `first_5_nos_365_548` | First 5 Nos 365 548 | numeric | 92.2% | N/A |
| `first_5_nos_549_731` | First 5 Nos 549 731 | numeric | 92.6% | N/A |
| `first_5_nos_732_914` | First 5 Nos 732 914 | numeric | 88.1% | N/A |
| `first_5_nos_90_179` | First 5 Nos 90 179 | numeric | 99.0% | N/A |
| `first_5_nos_915_1096` | First 5 Nos 915 1096 | numeric | 89.7% | N/A |
| `fq001` | Fq001 | numeric | 25.4% | N/A |
| `fq005` | Fq005 | numeric | 39.6% | N/A |
| `fqlive1_1` | Fqlive1 1 | numeric | 36.7% | N/A |
| `fqlive1_2` | Fqlive1 2 | numeric | 36.9% | N/A |
| `fqlive1_3` | Fqlive1 3 | numeric | 53.9% | N/A |
| `ineligible_flag` | Ineligible Flag | numeric | 99.4% | N/A |
| `kidsights_data_reviews_all_responses_for_quality___1` | Kidsights Data Reviews All Responses For Quality   1 | numeric | 0.0% | N/A |
| `mmi000` | Mmi000 | numeric | 64.3% | N/A |
| `mmi003` | Mmi003 | numeric | 65.7% | N/A |
| `mmi003b` | Mmi003B | numeric | 66.0% | N/A |
| `mmi009` | Mmi009 | numeric | 73.6% | N/A |
| `mmi013` | Mmi013 | numeric | 39.1% | N/A |
| `mmi014` | Mmi014 | numeric | 81.3% | N/A |
| `mmi018` | Mmi018 | numeric | 64.6% | N/A |
| `mmi019_1` | Mmi019 1 | numeric | 93.5% | N/A |
| `mmi019_2` | Mmi019 2 | numeric | 93.5% | N/A |
| `mmi019_3` | Mmi019 3 | numeric | 93.5% | N/A |
| `mmi100` | Mmi100 | numeric | 39.5% | N/A |
| `mmi101` | Mmi101 | numeric | 36.4% | N/A |
| `mmi110` | Mmi110 | numeric | 40.6% | N/A |
| `mmi111` | Mmi111 | numeric | 40.6% | N/A |
| `mmi112` | Mmi112 | numeric | 40.8% | N/A |
| `mmi113` | Mmi113 | numeric | 40.7% | N/A |
| `mmi120` | Mmi120 | numeric | 35.8% | N/A |
| `mmi121` | Mmi121 | numeric | 36.2% | N/A |
| `mmi122` | Mmi122 | numeric | 36.3% | N/A |
| `mmi123` | Mmi123 | numeric | 36.5% | N/A |
| `mmifs009` | Mmifs009 | numeric | 76.4% | N/A |
| `mmifs010` | Mmifs010 | numeric | 76.5% | N/A |
| `mmifs011` | Mmifs011 | numeric | 76.5% | N/A |
| `mmifs012` | Mmifs012 | numeric | 76.5% | N/A |
| `mmifs013` | Mmifs013 | numeric | 76.5% | N/A |
| `mmifs014` | Mmifs014 | numeric | 76.5% | N/A |
| `mmifs015` | Mmifs015 | numeric | 76.5% | N/A |
| `mmifs016` | Mmifs016 | numeric | 76.6% | N/A |
| `mmihl002` | Mmihl002 | numeric | 36.5% | N/A |
| `module_2_family_information_complete` | Module 2 Family Information Complete | numeric | 0.0% | N/A |
| `module_2_family_information_timestamp` | Module 2 Family Information Timestamp | character | 35.1% | N/A |
| `module_3_child_information_complete` | Module 3 Child Information Complete | numeric | 0.0% | N/A |
| `module_3_child_information_timestamp` | Module 3 Child Information Timestamp | character | 38.1% | N/A |
| `module_4_home_learning_environment_complete` | Module 4 Home Learning Environment Complete | numeric | 0.0% | N/A |
| `module_4_home_learning_environment_timestamp` | Module 4 Home Learning Environment Timestamp | character | 39.2% | N/A |
| `module_5_birthdate_confirmation_complete` | Module 5 Birthdate Confirmation Complete | numeric | 0.0% | N/A |
| `module_5_birthdate_confirmation_timestamp` | Module 5 Birthdate Confirmation Timestamp | character | 40.4% | N/A |
| `module_6_0_89_complete` | Module 6 0 89 Complete | numeric | 0.0% | N/A |
| `module_6_0_89_timestamp` | Module 6 0 89 Timestamp | character | 99.4% | N/A |
| `module_6_1097_2191_complete` | Module 6 1097 2191 Complete | numeric | 0.0% | N/A |
| `module_6_1097_2191_timestamp` | Module 6 1097 2191 Timestamp | character | 61.8% | N/A |
| `module_6_180_364_complete` | Module 6 180 364 Complete | numeric | 0.0% | N/A |
| `module_6_180_364_timestamp` | Module 6 180 364 Timestamp | character | 94.9% | N/A |
| `module_6_365_548_complete` | Module 6 365 548 Complete | numeric | 0.0% | N/A |
| `module_6_365_548_timestamp` | Module 6 365 548 Timestamp | character | 92.2% | N/A |
| `module_6_549_731_complete` | Module 6 549 731 Complete | numeric | 0.0% | N/A |
| `module_6_549_731_timestamp` | Module 6 549 731 Timestamp | character | 92.6% | N/A |
| `module_6_732_914_complete` | Module 6 732 914 Complete | numeric | 0.0% | N/A |
| `module_6_732_914_timestamp` | Module 6 732 914 Timestamp | character | 88.1% | N/A |
| `module_6_90_179_complete` | Module 6 90 179 Complete | numeric | 0.0% | N/A |
| `module_6_90_179_timestamp` | Module 6 90 179 Timestamp | character | 99.0% | N/A |
| `module_6_915_1096_complete` | Module 6 915 1096 Complete | numeric | 0.0% | N/A |
| `module_6_915_1096_timestamp` | Module 6 915 1096 Timestamp | character | 89.7% | N/A |
| `module_8_followup_information_complete` | Module 8 Followup Information Complete | numeric | 0.0% | N/A |
| `module_8_followup_information_timestamp` | Module 8 Followup Information Timestamp | character | 50.3% | N/A |
| `module_9_compensation_information_complete` | Module 9 Compensation Information Complete | numeric | 0.0% | N/A |
| `module_9_compensation_information_timestamp` | Module 9 Compensation Information Timestamp | character | 49.7% | N/A |
| `mrw001` | Mrw001 | numeric | 39.0% | N/A |
| `mrw002` | Mrw002 | numeric | 74.4% | N/A |
| `mrw003_1` | Mrw003 1 | numeric | 74.3% | N/A |
| `mrw003_2` | Mrw003 2 | numeric | 65.9% | N/A |
| `nom001` | Nom001 | numeric | 94.3% | N/A |
| `nom002` | Nom002 | numeric | 82.0% | N/A |
| `nom002x` | Nom002X | numeric | 80.4% | N/A |
| `nom003` | Nom003 | numeric | 82.1% | N/A |
| `nom003x` | Nom003X | numeric | 80.5% | N/A |
| `nom005` | Nom005 | numeric | 82.1% | N/A |
| `nom005x` | Nom005X | numeric | 80.5% | N/A |
| `nom006` | Nom006 | numeric | 95.7% | N/A |
| `nom006x` | Nom006X | numeric | 95.5% | N/A |
| `nom009` | Nom009 | numeric | 94.5% | N/A |
| `nom012` | Nom012 | numeric | 89.9% | N/A |
| `nom014` | Nom014 | numeric | 96.0% | N/A |
| `nom014x` | Nom014X | numeric | 96.0% | N/A |
| `nom015` | Nom015 | numeric | 91.2% | N/A |
| `nom017` | Nom017 | numeric | 94.9% | N/A |
| `nom017x` | Nom017X | numeric | 95.0% | N/A |
| `nom018` | Nom018 | numeric | 82.2% | N/A |
| `nom018x` | Nom018X | numeric | 80.5% | N/A |
| `nom019` | Nom019 | numeric | 62.7% | N/A |
| `nom022` | Nom022 | numeric | 82.0% | N/A |
| `nom022x` | Nom022X | numeric | 80.4% | N/A |
| `nom024` | Nom024 | numeric | 82.0% | N/A |
| `nom024x` | Nom024X | numeric | 80.4% | N/A |
| `nom026` | Nom026 | numeric | 96.2% | N/A |
| `nom026x` | Nom026X | numeric | 96.1% | N/A |
| `nom028` | Nom028 | numeric | 92.2% | N/A |
| `nom029` | Nom029 | numeric | 96.1% | N/A |
| `nom029x` | Nom029X | numeric | 96.0% | N/A |
| `nom031` | Nom031 | numeric | 96.7% | N/A |
| `nom033` | Nom033 | numeric | 95.7% | N/A |
| `nom033x` | Nom033X | numeric | 95.5% | N/A |
| `nom034` | Nom034 | numeric | 96.1% | N/A |
| `nom034x` | Nom034X | numeric | 96.1% | N/A |
| `nom035` | Nom035 | numeric | 81.7% | N/A |
| `nom035x` | Nom035X | numeric | 80.2% | N/A |
| `nom042x` | Nom042X | numeric | 62.7% | N/A |
| `nom044` | Nom044 | numeric | 100.0% | N/A |
| `nom046x` | Nom046X | numeric | 39.3% | N/A |
| `nom047` | Nom047 | numeric | 98.7% | N/A |
| `nom047x` | Nom047X | numeric | 98.9% | N/A |
| `nom048x` | Nom048X | numeric | 63.0% | N/A |
| `nom049` | Nom049 | numeric | 98.7% | N/A |
| `nom049x` | Nom049X | numeric | 98.9% | N/A |
| `nom052y` | Nom052Y | numeric | 63.0% | N/A |
| `nom053` | Nom053 | numeric | 81.7% | N/A |
| `nom053x` | Nom053X | numeric | 80.3% | N/A |
| `nom054x` | Nom054X | numeric | 63.0% | N/A |
| `nom056x` | Nom056X | numeric | 62.7% | N/A |
| `nom057` | Nom057 | numeric | 91.2% | N/A |
| `nom059` | Nom059 | numeric | 82.0% | N/A |
| `nom059x` | Nom059X | numeric | 80.5% | N/A |
| `nom060y` | Nom060Y | numeric | 62.7% | N/A |
| `nom061` | Nom061 | numeric | 96.1% | N/A |
| `nom061x` | Nom061X | numeric | 96.0% | N/A |
| `nom062y` | Nom062Y | numeric | 62.7% | N/A |
| `nom102` | Nom102 | numeric | 62.7% | N/A |
| `nom103` | Nom103 | numeric | 62.8% | N/A |
| `nom104` | Nom104 | numeric | 62.8% | N/A |
| `nom2202` | Nom2202 | numeric | 62.9% | N/A |
| `nom2205` | Nom2205 | numeric | 62.9% | N/A |
| `nom2208` | Nom2208 | numeric | 62.9% | N/A |
| `nos` | Nos | numeric | 99.4% | N/A |
| `nos_count_90_179` | Nos Count 90 179 | numeric | 99.0% | N/A |
| `nschj012` | Nschj012 | numeric | 36.6% | N/A |
| `nschj013` | Nschj013 | numeric | 51.0% | N/A |
| `nschj017` | Nschj017 | numeric | 51.1% | N/A |
| `ps001` | Ps001 | numeric | 47.2% | N/A |
| `ps002` | Ps002 | numeric | 47.6% | N/A |
| `ps003` | Ps003 | numeric | 47.5% | N/A |
| `ps004` | Ps004 | numeric | 47.6% | N/A |
| `ps005` | Ps005 | numeric | 47.4% | N/A |
| `ps006` | Ps006 | numeric | 47.5% | N/A |
| `ps007` | Ps007 | numeric | 47.6% | N/A |
| `ps008` | Ps008 | numeric | 47.5% | N/A |
| `ps009` | Ps009 | numeric | 47.5% | N/A |
| `ps010` | Ps010 | numeric | 47.6% | N/A |
| `ps011` | Ps011 | numeric | 47.6% | N/A |
| `ps013` | Ps013 | numeric | 47.6% | N/A |
| `ps014` | Ps014 | numeric | 47.6% | N/A |
| `ps015` | Ps015 | numeric | 47.6% | N/A |
| `ps016` | Ps016 | numeric | 47.8% | N/A |
| `ps017` | Ps017 | numeric | 47.7% | N/A |
| `ps018` | Ps018 | numeric | 47.6% | N/A |
| `ps019` | Ps019 | numeric | 47.6% | N/A |
| `ps020` | Ps020 | numeric | 47.8% | N/A |
| `ps022` | Ps022 | numeric | 47.8% | N/A |
| `ps023` | Ps023 | numeric | 47.9% | N/A |
| `ps024` | Ps024 | numeric | 47.7% | N/A |
| `ps025` | Ps025 | numeric | 47.8% | N/A |
| `ps026` | Ps026 | numeric | 47.8% | N/A |
| `ps027` | Ps027 | numeric | 47.6% | N/A |
| `ps028` | Ps028 | numeric | 47.6% | N/A |
| `ps029` | Ps029 | numeric | 47.7% | N/A |
| `ps030` | Ps030 | numeric | 47.6% | N/A |
| `ps031` | Ps031 | numeric | 47.8% | N/A |
| `ps032` | Ps032 | numeric | 47.7% | N/A |
| `ps034` | Ps034 | numeric | 47.7% | N/A |
| `ps035` | Ps035 | numeric | 47.8% | N/A |
| `ps036` | Ps036 | numeric | 47.7% | N/A |
| `ps037` | Ps037 | numeric | 48.0% | N/A |
| `ps038` | Ps038 | numeric | 47.9% | N/A |
| `ps039` | Ps039 | numeric | 47.9% | N/A |
| `ps040` | Ps040 | numeric | 48.0% | N/A |
| `ps041` | Ps041 | numeric | 48.0% | N/A |
| `ps042` | Ps042 | numeric | 47.9% | N/A |
| `ps043` | Ps043 | numeric | 48.0% | N/A |
| `ps044` | Ps044 | numeric | 48.0% | N/A |
| `ps045` | Ps045 | numeric | 48.0% | N/A |
| `ps046` | Ps046 | numeric | 47.9% | N/A |
| `ps047` | Ps047 | numeric | 48.0% | N/A |
| `ps048` | Ps048 | numeric | 47.8% | N/A |
| `ps049` | Ps049 | numeric | 47.7% | N/A |
| `q1347` | Q1347 | numeric | 50.5% | N/A |
| `q1348` | Q1348 | character | 85.4% | N/A |
| `q1394` | Q1394 | character | 51.6% | N/A |
| `q1394a` | Q1394A | character | 51.6% | N/A |
| `q1395` | Q1395 | character | 52.2% | N/A |
| `q1396` | Q1396 | character | 52.2% | N/A |
| `q1397` | Q1397 | character | 52.1% | N/A |
| `q1398` | Q1398 | character | 52.1% | N/A |
| `q1502` | Q1502 | numeric | 36.2% | N/A |
| `q1503` | Q1503 | numeric | 36.3% | N/A |
| `q1504` | Q1504 | numeric | 36.6% | N/A |
| `q1505` | Q1505 | numeric | 36.4% | N/A |
| `q939___1` | Q939   1 | numeric | 0.0% | N/A |
| `q939___2` | Q939   2 | numeric | 0.0% | N/A |
| `q939___3` | Q939   3 | numeric | 0.0% | N/A |
| `q939___4` | Q939   4 | numeric | 0.0% | N/A |
| `q939___5` | Q939   5 | numeric | 0.0% | N/A |
| `q939___6` | Q939   6 | numeric | 0.0% | N/A |
| `q939___7` | Q939   7 | numeric | 0.0% | N/A |
| `q939___8` | Q939   8 | numeric | 0.0% | N/A |
| `q940` | Q940 | numeric | 64.4% | N/A |
| `q941` | Q941 | numeric | 64.4% | N/A |
| `q943` | Q943 | numeric | 36.0% | N/A |
| `q958` | Q958 | character | 64.8% | N/A |
| `q959___1` | Q959   1 | numeric | 0.0% | N/A |
| `q959___2` | Q959   2 | numeric | 0.0% | N/A |
| `q959___3` | Q959   3 | numeric | 0.0% | N/A |
| `q959___4` | Q959   4 | numeric | 0.0% | N/A |
| `q959___5` | Q959   5 | numeric | 0.0% | N/A |
| `q959___6` | Q959   6 | numeric | 0.0% | N/A |
| `q960` | Q960 | numeric | 39.9% | N/A |
| `redcap_survey_identifier` | Redcap Survey Identifier | numeric | 93.8% | N/A |
| `sf018` | Sf018 | numeric | 99.5% | N/A |
| `sf019` | Sf019 | numeric | 99.5% | N/A |
| `sf021` | Sf021 | numeric | 99.5% | N/A |
| `sf054` | Sf054 | numeric | 95.0% | N/A |
| `sf093` | Sf093 | numeric | 96.7% | N/A |
| `sf122` | Sf122 | numeric | 91.0% | N/A |
| `sf127` | Sf127 | numeric | 93.6% | N/A |
| `source_project` | Source Project | factor | 0.0% | 1 (kidsights_data_survey), 2 (kidsights_email_registration), 3 (kidsights_public), 4 (kidsights_public_birth) |
| `sq001` | Sq001 | character | 25.4% | N/A |
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
| `sq003` | Sq003 | numeric | 36.3% | N/A |
| `survey_stop` | Survey Stop | numeric | 99.4% | N/A |

---

## Notes

- **Missing percentages** are calculated as (missing values / total records) × 100
- **Factor variables** show the most common levels with their counts
- **Numeric variables** display min, max, and mean values where available
- **Logical variables** show counts of TRUE and FALSE values

*Generated automatically from metadata on 2025-09-29 by the Kidsights Data Platform*

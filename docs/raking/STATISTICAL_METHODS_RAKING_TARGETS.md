# Statistical Methods for Raking Target Estimation

**Document Type:** Peer-Reviewed Publication Methods Section
**Date:** October 2025
**Purpose:** Estimation of population-level targets for post-stratification raking of state-level survey data

---

## Overview

### Background

Post-stratification raking is a widely used technique to adjust survey sampling weights to match known population marginal distributions on key demographic and health characteristics (Battaglia et al., 2004; Brick, 2013). This iterative proportional fitting procedure requires population-level target estimates for each stratification variable. We developed a comprehensive set of 34 population targets stratified by child age (0-5 years) using three nationally representative data sources: the American Community Survey (ACS), the National Health Interview Survey (NHIS), and the National Survey of Children's Health (NSCH).

### Objective

The objective of this analysis was to produce age-stratified population estimates for a Midwestern state to serve as raking targets for calibrating weights in a state-level child development survey conducted in 2025 (N=4,900 children ages 0-5 years). The targets span demographic characteristics (sex, race/ethnicity, income, geography), parent mental health and adverse childhood experiences (ACEs), and child health and developmental outcomes.

---

## Data Sources

### American Community Survey (ACS)

We used pooled 5-year ACS data (2019-2023) obtained through the Integrated Public Use Microdata Series (IPUMS USA; Ruggles et al., 2024). The sample included 6,657 children ages 0-5 residing in the target state across five annual survey years. The ACS is an ongoing survey administered by the U.S. Census Bureau with a complex, multistage probability sampling design. We incorporated survey design features including person-level sampling weights, primary sampling unit identifiers, and stratification variables to account for the complex sampling structure in all analyses.

**Sample characteristics:**
- **Total sample:** 6,657 children ages 0-5 (1,331 per year on average)
- **Age distribution:** Approximately 1,100 children per single-year age bin
- **Geographic scope:** State-level (Federal Information Processing Standard state code 31)
- **Survey design:** Complex multistage probability sample with clustering and stratification

### National Health Interview Survey (NHIS)

We used NHIS data from 2019-2024 obtained through IPUMS Health Surveys (Blewett et al., 2024). The NHIS is a cross-sectional household interview survey conducted by the National Center for Health Statistics with a multistage area probability design. Because NHIS does not identify individual states, we used the North Central census region as a proxy for the target state.

A critical methodological challenge was that NHIS collects data on all household members, but parent-level variables (depression, ACEs) are only available on adult records, not child records. We therefore implemented a two-step household linkage procedure:

1. **Identify target households:** Selected households containing at least one sample child ages 0-5 using household identifiers and child sampling indicators
2. **Link to parent records:** Joined adult records within these households identified as parents of the sample child

This procedure yielded 15,208 parent records linked to children ages 0-5 across six survey years.

**Sample characteristics by outcome:**
- **Depression (PHQ-8 available):** 4,022 parents from 2019 and 2022 survey years
- **ACEs:** 7,657 parents from 2019, 2021, 2022, and 2023 survey years
- **Geographic scope:** North Central census region (includes Iowa, Kansas, Minnesota, Missouri, Nebraska, North Dakota, South Dakota)
- **Survey design:** Multistage area probability sample with regional stratification

### National Survey of Children's Health (NSCH)

We used NSCH 2023 data, a household survey sponsored by the Health Resources and Services Administration and conducted by the U.S. Census Bureau. The NSCH employs a complex sample design with state-level stratification to produce state-representative estimates. We restricted the sample to children ages 0-5 residing in the target state.

**Sample characteristics:**
- **Total sample:** 21,524 children ages 0-5 in target state (2023 wave)
- **Age distribution:** Variable by age, approximately 3,000-4,000 per single-year age bin
- **Geographic scope:** State-level
- **Survey design:** Stratified random sample with state-level representativeness

---

## Statistical Methods

### General Approach

We used model-based estimation approaches to leverage temporal trends, reduce sampling variability, and provide principled measures of uncertainty. The specific modeling strategy varied by data source based on data structure and availability:

1. **ACS:** Survey-weighted generalized linear models (GLM) with temporal effects
2. **NHIS:** Generalized linear mixed models (GLMM) with regional random effects
3. **NSCH:** Age-stratified generalized linear mixed models with state-level random effects

All models incorporated survey design features (weights, clustering, stratification) to produce design-based variance estimates.

### ACS Estimation: Survey-Weighted GLM with Temporal Trends

#### Rationale

The ACS 5-year pooled sample contains data from five distinct survey years (2019-2023), which provides an opportunity to borrow strength across years for more efficient estimation. Rather than computing naive stratified proportions within a single year, we modeled outcomes as a function of child age, survey year, and their interaction. This approach:

1. Increases precision by pooling information across years
2. Smooths year-to-year sampling variability
3. Provides estimates at the most recent survey year (2023) while incorporating historical trends
4. Yields proper design-based standard errors accounting for survey structure

#### Model Specification

For a binary outcome Y (e.g., child is male, mother has bachelor's degree), we fit a survey-weighted logistic regression model:

$$\text{logit}(P(Y_{ijk} = 1)) = \beta_0 + \beta_1 \text{Age}_i + \beta_2 \text{Year}_j + \beta_3 (\text{Age}_i \times \text{Year}_j)$$

where:
- $Y_{ijk}$ is the binary outcome for child $k$ at age $i$ in survey year $j$
- $\text{Age}_i$ is child age in years (0-5)
- $\text{Year}_j$ is the actual survey year (2019-2023, as a continuous variable)
- The interaction term $\beta_3$ captures differential temporal trends by age

We incorporated survey design features using the survey package in R (Lumley, 2004):
- **Sampling weights:** Person-level weights to represent the population
- **Clustering:** Primary sampling unit identifiers
- **Stratification:** Survey strata for variance estimation

The model was estimated using weighted quasi-likelihood to account for the survey design, producing asymptotically design-unbiased estimates with design-based standard errors.

#### Model Selection

To avoid overfitting, we tested whether the age × year interaction term significantly improved model fit using a design-adjusted F-test comparing the full model to a main-effects-only model:

$$\text{logit}(P(Y_{ijk} = 1)) = \beta_0 + \beta_1 \text{Age}_i + \beta_2 \text{Year}_j$$

If the interaction term was not statistically significant (p > 0.05), we used the simpler main-effects model for prediction.

#### Prediction Strategy

For both model forms, we predicted age-specific probabilities at the most recent survey year (2023):

$$\hat{p}_i = \text{expit}(\hat{\beta}_0 + \hat{\beta}_1 \text{Age}_i + \hat{\beta}_2 \times 2023 + \hat{\beta}_3 (\text{Age}_i \times 2023))$$

where $\text{expit}(x) = \frac{e^x}{1 + e^x}$ is the inverse logit function. This yields six age-stratified estimates (ages 0-5) representing the most current population distributions while incorporating information from all five survey years.

#### Estimands

We computed the following 26 population targets using this approach:

**1. Sex (1 estimand):**
- Proportion of children who are male

**2. Race and ethnicity (3 estimands):**
- Proportion white alone, non-Hispanic
- Proportion Black (any combination, including Hispanic)
- Proportion Hispanic (any race)

**3. Federal Poverty Level (5 estimands):**
- Proportion at 0-99% FPL
- Proportion at 100-199% FPL
- Proportion at 200-299% FPL
- Proportion at 300-399% FPL
- Proportion at 400%+ FPL

Categories were derived from the income-to-poverty ratio variable, which represents household income as a percentage of the federal poverty threshold for the household size and composition.

**4. Public Use Microdata Areas (14 estimands):**
- Proportion residing in each of 14 state-specific PUMAs

PUMAs are geographic units defined for census data with populations of approximately 100,000. They represent the finest geographic resolution available in ACS public-use microdata.

**5. Mother's educational attainment (1 estimand, age-stratified):**
- Proportion of children whose mother has a bachelor's degree or higher

Mother's education was derived by linking children to mother's household position using household relationship variables, then extracting the mother's educational attainment. Approximately 95% of children had mothers successfully linked within the household. Children without mothers in the household were excluded from this specific model (missing data).

Mother's education showed age variation (range: 44-47% across ages 0-5), likely reflecting cohort effects in maternal educational attainment and timing of childbearing. We therefore estimated age-specific values rather than assuming a constant proportion.

**6. Mother's marital status (1 estimand, age-stratified):**
- Proportion of children whose mother is currently married, spouse present

Mother's marital status was derived using household head marital status as a proxy. This approach leverages the household structure: (a) if the mother is the household head, the household head's marital status directly reflects her status; (b) if the mother is the spouse of the household head, she is married by definition. This proxy accurately represents mother's marital status for approximately 92% of children in the sample.

Marital status showed meaningful age variation (range: 79-84% married across ages 0-5), potentially reflecting changes in marriage patterns after childbearing or differential attrition. We therefore estimated age-specific values.

---

### NHIS Estimation: Regional Mixed Models

#### Rationale

NHIS does not provide state-level identifiers due to confidentiality protections, reporting only four broad census regions. To estimate state-level targets, we modeled regional variation using generalized linear mixed models with regional random intercepts. This approach:

1. Accounts for unmeasured heterogeneity across regions
2. Provides partial pooling toward the national mean
3. Yields predictions for the North Central region, which serves as a proxy for the target state

#### Model Specification

For binary outcomes related to parent mental health and adverse childhood experiences, we fit:

$$\text{logit}(P(Y_{ir} = 1)) = \beta_0 + u_r$$

where:
- $Y_{ir}$ is the binary outcome for parent $i$ in region $r$
- $\beta_0$ is the fixed intercept (national mean on logit scale)
- $u_r \sim N(0, \sigma_u^2)$ is a region-specific random intercept

The model was estimated using adaptive Gaussian quadrature in a generalized linear mixed model framework, with inverse-variance weighting using survey sampling weights.

We predicted probabilities for the North Central region (census region 2) by extracting the region-specific random effect:

$$\hat{p}_{\text{NC}} = \text{expit}(\hat{\beta}_0 + \hat{u}_{\text{NC}})$$

#### Household Linkage Procedure

Because depression and ACE variables are measured on adult records, we implemented a two-step linkage:

1. Identified households containing at least one sample child ages 0-5 using household identifiers and child sampling flags
2. Selected adult records within these households flagged as parents of the sample child

This ensured all estimates reflect parents of young children (ages 0-5) rather than parents of children of all ages.

#### Estimands

**1. Maternal depression symptoms (2 estimands):**
- Proportion reporting no/minimal depressive symptoms (PHQ-8 score 0-4)
- Proportion reporting moderately severe/severe depressive symptoms (PHQ-8 score ≥15)

The Patient Health Questionnaire-8 (PHQ-8) was available in 2019 and 2022 survey years only (N=4,022 parents with children 0-5). PHQ-8 is a validated 8-item depression screening instrument with scores ranging 0-24 (Kroenke et al., 2009).

**2. Maternal adverse childhood experiences (2 estimands):**
- Proportion exposed to exactly one ACE
- Proportion exposed to two or more ACEs

We constructed an ACE total score by summing eight binary indicators of childhood adversity: living with someone with mental illness, substance use problems, or who was incarcerated; experiencing violence in the home; physical abuse; racial discrimination; sexual orientation/gender discrimination; and economic hardship (inability to afford basic needs). This ACE module was available in 2019, 2021, 2022, and 2023 (N=7,657 parents with children 0-5).

---

### NSCH Estimation: Age-Stratified State-Level Mixed Models

#### Rationale

Unlike ACS and NHIS, NSCH child health and developmental outcomes vary substantially by child age, requiring age-specific estimates. Additionally, NSCH includes all 50 states, allowing us to model state-level heterogeneity. We fit separate mixed models for each single-year age bin (0, 1, 2, 3, 4, 5 years) with state-level random intercepts.

#### Model Specification

For each age $a$ and binary outcome $Y$, we fit:

$$\text{logit}(P(Y_{is} = 1 | \text{Age} = a)) = \beta_{0a} + u_s$$

where:
- $Y_{is}$ is the binary outcome for child $i$ in state $s$
- $\beta_{0a}$ is the age-specific fixed intercept
- $u_s \sim N(0, \sigma_{ua}^2)$ is a state-specific random intercept

Models were estimated separately for each age bin using survey sampling weights. We predicted probabilities for the target state (state code 31) at each age:

$$\hat{p}_{a} = \text{expit}(\hat{\beta}_{0a} + \hat{u}_{31})$$

This yields six distinct estimates per outcome (one for each age 0-5).

#### Estimands

**1. Child ACE exposure (1 estimand, age-stratified):**
- Proportion exposed to at least one adverse childhood experience

Child ACE exposure in NSCH includes indicators such as economic hardship, parental divorce/separation, parental death, parental incarceration, witnessing domestic violence, experiencing or witnessing neighborhood violence, household mental illness, household substance abuse, and discrimination. The specific items vary slightly by survey year; we used the 2023 composite indicator.

**2. Emotional/developmental/behavioral problems (1 estimand, age-stratified):**
- Proportion with a problem requiring treatment or counseling

This item is only asked for children ages 3-17 in NSCH. For ages 0-2, we assigned missing values (NA) as no comparable screening measure exists for this age range.

**3. Parent-rated health status (1 estimand, age-stratified):**
- Proportion rated as "excellent" health (vs. very good, good, fair, or poor)

General health status is a single-item global health rating on a 5-point scale, widely used as a summary measure of child health (Seid et al., 2004).

**4. Regular non-parental child care (1 estimand, age-stratified):**
- Proportion receiving care from someone other than a parent or guardian for 10+ hours per week

This indicator captures formal and informal child care arrangements, which vary substantially by child age as children transition from infancy through preschool.

---

## Validation

### Completeness and Range Checks

We verified that all 204 target estimates (34 estimands × 6 age bins) were successfully computed with values in the valid probability range [0, 1].

### Internal Consistency

For categorical variables that partition the population (race/ethnicity, federal poverty level, geographic units), we verified that proportions summed to 1.0 within each age bin (within rounding error of ±0.01).

### Age Pattern Consistency

We verified the expected age patterns in estimates:
- **ACS demographic characteristics:** Should show minimal age variation (same population proportions across ages 0-5)
- **NSCH child outcomes:** Should show meaningful age variation (developmental changes across ages 0-5)

### External Validation

We compared selected estimates to published official statistics to assess face validity:

**ACS demographic estimates:**
We validated sex, race/ethnicity, and poverty distributions against published ACS 1-year estimates for the target state (2023) from the U.S. Census Bureau's data dissemination system (data.census.gov). Specifically, we compared our aggregated estimates (across ages 0-5) to:
- Table B01001: Sex by age (proportion male for "Under 5 years" category)
- Table B01001H: White alone, not Hispanic or Latino ("Under 5 years" category)
- Table B17024: Age by ratio of income to poverty level ("Under 6 years" category)

Note: Published ACS tables use coarse age groupings (Under 5, Under 6) rather than single-year ages. We aggregated our single-year age estimates (0-5) to match the published age categories. Expected agreement: Our pooled 5-year GLM predictions at 2023 should align closely (±2-3 percentage points) with published 1-year estimates, with some divergence due to temporal smoothing.

**NSCH child health estimates:**
We validated child health and ACE indicators against published NSCH 2023 state-level estimates from the Data Resource Center for Child and Adolescent Health (nschdata.org). The NSCH Interactive Data Query system allows filtering to children ages 0-5 specifically. We compared:
- Child ACE exposure prevalence (1+ ACE) for ages 0-5
- Proportion rated in excellent health for ages 0-5
- Child care utilization (10+ hours/week) for ages 0-5

Expected agreement: Our state-level mixed model predictions should match published state profiles within confidence intervals, accounting for differences in weighting methodology and potential differences in age aggregation (our six single-year estimates averaged vs. their pooled ages 0-5 estimate).

**NHIS estimates - no external validation available:**
External validation of NHIS-based estimates is not feasible because published NHIS tables report outcomes for all adults in a region, not specifically for parents of children ages 0-5. The household linkage procedure we used (linking parents to children's ages) is only possible in restricted-use microdata and is not reflected in any published NHIS tabulations. Therefore, we cannot compare our parent-specific estimates to published regional statistics. Instead, we rely on internal validation (model diagnostics, plausibility checks against known population patterns) and consistency with peer-reviewed literature on parent mental health and ACE prevalence in similar populations.

---

## Software and Reproducibility

All analyses were conducted in R version 4.5.1 (R Core Team, 2024) and Python 3.13. Survey-weighted analyses used the survey package in R (Lumley, 2004). Mixed models were estimated using the lme4 package (Bates et al., 2015). Data management used DuckDB for efficient querying of large datasets.

Statistical code is available in the project repository with documentation of data sources, variable definitions, and estimation procedures to facilitate reproducibility. However, access to restricted-use IPUMS microdata requires separate user registration and data use agreements.

---

## Ethical Considerations

This analysis used only publicly available or restricted-access datasets with no direct identifiers. ACS and NSCH public-use files do not contain individual identifiers. NHIS restricted-use files accessed through IPUMS comply with National Center for Health Statistics confidentiality protections and do not identify individual states, counties, or detailed geographic locations. All analyses aggregated data to population-level estimates; no individual-level results are reported.

The use of regional estimates (NHIS North Central region) as proxies for state-level estimates introduces geographic imprecision, as the region includes seven states with potentially heterogeneous population characteristics. Sensitivity analyses comparing state-specific estimates from other data sources (ACS, NSCH) to regional estimates could quantify this geographic aggregation bias.

---

## Limitations

1. **NHIS geographic aggregation:** Use of census region as proxy for state-level estimates may not capture state-specific patterns in parent mental health and ACEs. The North Central region is heterogeneous, including both highly urban (e.g., Minneapolis, Kansas City) and rural states.

2. **Temporal alignment:** ACS data span 2019-2023, NHIS data span 2019-2024, and NSCH data represent a single year (2023). Population characteristics may have changed between data collection and the target survey year (2025), particularly in the context of COVID-19 pandemic effects on household structure, employment, and mental health.

3. **Mother linkage coverage:** Approximately 5% of children in ACS could not be linked to mothers within the household. If these children differ systematically (e.g., foster care, kinship care, institutional settings), mother education and marital status estimates may not fully represent the target population.

4. **Age heaping and measurement error:** Parent-reported child age may be subject to rounding error, particularly at boundaries of age categories. This could lead to minor misclassification between adjacent age bins.

5. **Model assumptions:** GLM and GLMM approaches assume specific functional forms (logit link, linear effects of age/year). Sensitivity analyses using alternative model specifications (e.g., splines for nonlinear age trends) could assess robustness.

---

## References

Battaglia, M. P., Hoaglin, D. C., & Frankel, M. R. (2004). Practical considerations in raking survey data. *Survey Practice*, 2(5), 1-10.

Bates, D., Mächler, M., Bolker, B., & Walker, S. (2015). Fitting linear mixed-effects models using lme4. *Journal of Statistical Software*, 67(1), 1-48.

Blewett, L. A., Rivera Drew, J. A., King, M. L., Williams, K. C. W., Chen, A., Richards, S., Perfectly, T., & Oh, S. (2024). IPUMS Health Surveys: National Health Interview Survey, Version 7.3 [dataset]. IPUMS. https://doi.org/10.18128/D070.V7.3

Brick, J. M. (2013). Unit nonresponse and weighting adjustments: A critical review. *Journal of Official Statistics*, 29(3), 329-353.

Kroenke, K., Strine, T. W., Spitzer, R. L., Williams, J. B., Berry, J. T., & Mokdad, A. H. (2009). The PHQ-8 as a measure of current depression in the general population. *Journal of Affective Disorders*, 114(1-3), 163-173.

Lumley, T. (2004). Analysis of complex survey samples. *Journal of Statistical Software*, 9(1), 1-19.

R Core Team (2024). R: A language and environment for statistical computing. R Foundation for Statistical Computing, Vienna, Austria.

Ruggles, S., Flood, S., Sobek, M., Backman, D., Chen, A., Cooper, G., Richards, S., Rodgers, R., & Schouweiler, M. (2024). IPUMS USA: Version 15.0 [dataset]. IPUMS. https://doi.org/10.18128/D010.V15.0

Seid, M., Sobo, E. J., Gelhard, L. R., & Varni, J. W. (2004). Parents' reports of barriers to care for children with special health care needs: Development and validation of the Barriers to Care Questionnaire. *Ambulatory Pediatrics*, 4(4), 323-331.

---

*Prepared for the Kidsights Data Platform | Statistical Methods Documentation*
*Date: October 2025*

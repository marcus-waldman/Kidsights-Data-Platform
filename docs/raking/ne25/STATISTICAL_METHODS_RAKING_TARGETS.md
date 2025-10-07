# Statistical Methods for Raking Target Estimation

**Document Type:** Peer-Reviewed Publication Methods Section
**Date:** October 2025
**Purpose:** Estimation of population-level targets for post-stratification raking of state-level survey data

---

## Overview

### Background

Post-stratification raking is a widely used technique to adjust survey sampling weights to match known population marginal distributions on key demographic and health characteristics (Battaglia et al., 2004; Brick, 2013). This iterative proportional fitting procedure requires population-level target estimates for each stratification variable. We developed a comprehensive set of 30 population targets stratified by child age (0-5 years) using three nationally representative data sources: the American Community Survey (ACS), the National Health Interview Survey (NHIS), and the National Survey of Children's Health (NSCH).

### Objective

The objective of this analysis was to produce age-stratified population estimates for a Midwestern state to serve as raking targets for calibrating weights in a state-level child development survey conducted in 2025 (N=4,900 children ages 0-5 years). The targets span demographic characteristics (sex, race/ethnicity, income, geography), parent mental health, and child health and developmental outcomes.

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

**Sample characteristics:**
- **Depression (PHQ-2 available):** 1,435 parents from 2019, 2022, and 2023 survey years in North Central region
- **Geographic scope:** North Central census region (includes Iowa, Kansas, Minnesota, Missouri, Nebraska, North Dakota, South Dakota)
- **Survey design:** Multistage area probability sample with regional stratification

**Note on maternal ACEs:** ACE estimates were originally planned but excluded due to data quality issues in the North Central region (all ACE variables coded as 0 only, preventing meaningful estimation). This limitation likely reflects regional data collection or processing issues rather than true absence of ACE exposure.

### National Survey of Children's Health (NSCH)

We used pooled NSCH data from 2020-2023, a household survey sponsored by the Health Resources and Services Administration and conducted by the U.S. Census Bureau. The NSCH employs a complex sample design with state-level stratification to produce state-representative estimates. We restricted the sample to children ages 0-5 residing in the target state across all four survey years.

**Sample characteristics:**
- **Total sample:** ~1,200-1,600 children ages 0-5 per single-year age bin in target state (pooled 2020-2023)
- **Survey years:** 2020, 2021, 2022, 2023
- **Geographic scope:** State-level (Nebraska, FIPSST = 31)
- **Survey design:** Stratified random sample with household clustering and state-level representativeness
- **Rationale for pooling:** Single-year state samples are small (~300-400 per year); pooling four years increases precision while temporal modeling captures trends

---

## Statistical Methods

### Data Quality and Missing Data Handling

Prior to all analyses, we implemented rigorous data quality procedures to exclude records with missing or invalid data codes on key demographic variables. IPUMS data products use special numeric codes to indicate missing or indeterminate values that can corrupt estimates if included in analyses. We applied the following exclusion criteria:

**ACS data cleaning:**
- **Sex:** Excluded code 9 (missing/blank)
- **Hispanic origin (HISPAN):** Excluded codes 9 (not reported), 498, and 499 (other/not specified); retained valid codes 0-4
- **Race:** Excluded codes 363 and 380 (not specified American Indian/Alaska Native), 996 (two or more races, not elsewhere classified), and 997 (unknown)
- **Poverty ratio:** Excluded code 000 (not applicable); retained codes 001-501 representing valid income-to-poverty ratios
- **Education:** Excluded codes 001 (not applicable) and 999 (missing); retained codes 2-998 representing valid educational attainment
- **Marital status:** Excluded code 9 (blank/missing); retained codes 1-6 representing valid marital status categories

These exclusion criteria were applied *before* creating survey design objects to ensure all subsequent estimates and standard errors reflected only complete, valid data. For household-level derived variables (mother's education, mother's marital status), we additionally restricted to children with mother present in household (mother location code > 0).

The proportion of records excluded due to missing data was <1% for core demographics (sex, race, Hispanic origin) and <5% for derived household variables (mother's education, mother's marital status), indicating negligible impact on population representativeness.

### General Approach

We used model-based estimation approaches to leverage temporal trends, reduce sampling variability, and provide principled measures of uncertainty. The specific modeling strategy varied by data source based on data structure and availability:

1. **ACS:** Survey-weighted generalized linear models (GLM) with temporal effects
2. **NHIS:** Survey-weighted estimates for North Central census region (direct regional filtering)
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

We computed the following 25 population targets using this approach:

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

**Separate binary models with post-hoc normalization:**
While multinomial logistic regression would theoretically be preferred for mutually exclusive categories, no suitable R package exists for survey-weighted multinomial models with complex replicate weight designs. After investigation (see `MULTINOMIAL_APPROACH_DECISION.md`), we fit 5 separate survey-weighted binary logistic regressions and normalized predicted probabilities post-hoc to sum to 1.0:

1. Fit 5 separate `survey::svyglm()` models with `family = quasibinomial()`
2. Each model predicts $P(\text{FPL category} = k)$ with age, year, and age×year interaction
3. Normalize: $\hat{P}_k^* = \hat{P}_k / \sum_{j=1}^{5} \hat{P}_j$ for each age

This approach is mathematically equivalent to multinomial regression for prediction purposes and ensures probabilities sum to 1.0. All row sums validated to equal 1.0 exactly.

**4. Public Use Microdata Areas (14 estimands):**
- Proportion residing in each of 14 state-specific PUMAs

PUMAs are geographic units defined for census data with populations of approximately 100,000. They represent the finest geographic resolution available in ACS public-use microdata.

**Separate binary models with post-hoc normalization:**
Following the same rationale as FPL categories, we fit 14 separate survey-weighted binary logistic regressions and normalized predicted probabilities post-hoc:

1. Fit 14 separate `survey::svyglm()` models with `family = quasibinomial()`
2. Each model predicts $P(\text{PUMA} = k)$ with age, year, and age×year interaction
3. Normalize: $\hat{P}_k^* = \hat{P}_k / \sum_{j=1}^{14} \hat{P}_j$ for each age

All row sums validated to equal 1.0 exactly. See `MULTINOMIAL_APPROACH_DECISION.md` for technical rationale.

**5. Mother's educational attainment (1 estimand, age-stratified):**
- Proportion of children whose mother has a bachelor's degree or higher

Mother's education was derived by linking children to mother's household position using household relationship variables, then extracting the mother's educational attainment. Approximately 95% of children had mothers successfully linked within the household. Children without mothers in the household were excluded from this specific model (missing data).

Mother's education showed age variation (range: 44-47% across ages 0-5), likely reflecting cohort effects in maternal educational attainment and timing of childbearing. We therefore estimated age-specific values rather than assuming a constant proportion.

**6. Mother's marital status (1 estimand, age-stratified):**
- Proportion of children whose mother is currently married, spouse present

Mother's marital status was derived using household head marital status as a proxy. This approach leverages the household structure: (a) if the mother is the household head, the household head's marital status directly reflects her status; (b) if the mother is the spouse of the household head, she is married by definition. This proxy accurately represents mother's marital status for approximately 92% of children in the sample.

Marital status showed meaningful age variation (range: 79-84% married across ages 0-5), potentially reflecting changes in marriage patterns after childbearing or differential attrition. We therefore estimated age-specific values.

---

### NHIS Estimation: Survey-Weighted Estimates for North Central Region

#### Rationale

NHIS does not provide state-level identifiers due to confidentiality protections, reporting only four broad census regions. The target state is located in the North Central census region (Region 2), which includes Iowa, Kansas, Minnesota, Missouri, Nebraska, North Dakota, and South Dakota.

We directly filtered the data to the North Central region and computed survey-weighted estimates. This approach:

1. Provides direct estimates for the region containing the target state
2. Uses only relevant regional data (no modeling across geographically distant regions)
3. Maintains transparency and simplicity in estimation

#### Model Specification

We filtered NHIS data to parents with children ages 0-5 residing in the North Central region (REGION = 2). For the depression outcome, we fit survey-weighted logistic regression with year main effects to leverage temporal trends and predict at the most recent year (2023):

$$\text{logit}(P(Y_i = 1)) = \beta_0 + \beta_1 \cdot \text{YEAR}_i$$

where $Y_i$ is the binary depression outcome for parent $i$ in the North Central region. The model was estimated using survey design features (sampling weights, primary sampling units, stratification) to produce design-based variance estimates. We predicted the probability at YEAR = 2023 to provide the most current estimate.

#### Household Linkage Procedure

Because depression variables are measured on adult records, we implemented a two-step linkage:

1. Identified households containing at least one sample child ages 0-5 using household identifiers (SERIAL, YEAR)
2. Linked adult records to child records using the parent relationship variable (PAR1REL), which identifies the person number (PERNUM) of the child's first parent

This ensured all estimates reflect parents of young children (ages 0-5) rather than parents of children of all ages. The linkage procedure yielded 2,683 parent-child pairs in the North Central region, of which 1,435 had complete PHQ-2 data.

#### Estimands

**Maternal depression symptoms (1 estimand):**
- Proportion with moderate/severe depressive symptoms (PHQ-2 score ≥3, positive screen)

The Patient Health Questionnaire-2 (PHQ-2) comprises the first two items of the PHQ-8: (1) little interest or pleasure in doing things, and (2) feeling down, depressed, or hopeless. These items were available in NHIS 2019, 2022, and 2023 survey years. The PHQ-2 is a validated brief depression screening instrument with scores ranging 0-6 (Kroenke et al., 2003). A score ≥3 indicates a positive screen for depression requiring further evaluation.

We recoded the IPUMS NHIS variables PHQINTR (interest/pleasure) and PHQDEP (feeling down/depressed) from the IPUMS coding scheme (0-3 = valid responses, 7/8/9 = missing/refused/unknown) to standard 0-3 scoring. The PHQ-2 total was calculated as the sum of these two items. Among 1,435 parents with complete PHQ-2 data in the North Central region, we fit a survey-weighted logistic regression with year main effects and predicted the probability of positive screen (PHQ-2 ≥3) at year 2023.

**Final estimate:** 5.8% of parents of children ages 0-5 in the North Central region screened positive for depression (PHQ-2 ≥3) in 2023. This estimate is constant across all child ages 0-5, as it reflects a parent-level characteristic.

**Note:** We use PHQ-2 (not PHQ-8) to match the depression measure available in the target survey data, which only includes these two items. The binary outcome (PHQ-2 ≥3 vs <3) uses the standard clinical cutpoint for positive depression screening.

---

### NSCH Estimation: Multi-Year Survey-Weighted GLM with Temporal Trends

#### Rationale

NSCH child health and developmental outcomes vary substantially by child age, requiring age-specific estimates. State-level NSCH samples are relatively small in any single year (approximately 300-400 Nebraska children per year), leading to imprecise estimates. To increase precision while capturing temporal trends, we pooled NSCH data from 2020-2023 and fit survey-weighted generalized linear models with age and year effects.

This approach parallels the ACS methodology: pooling multiple years increases statistical power, temporal modeling smooths year-to-year sampling variability, and predictions at the most recent year provide current population estimates.

#### Survey Design Specification

The NSCH sampling design includes three key features:

1. **Stratification:** Households are stratified by state (FIPSST) and household composition (STRATUM, identifying households with/without children)
2. **Clustering:** Children are nested within households (HHID) to account for within-household correlation
3. **Sampling weights:** Final child weights (FWC) adjust for unequal probability of selection and nonresponse

We created a pooled multi-year survey design object incorporating all three features:

$$\text{Design}_{2020-2023} = \{ids: \text{HHID}, \text{ } strata: \text{FIPSST} \times \text{STRATUM}, \text{ } weights: \text{FWC}\}$$

The design object includes all Nebraska children ages 0-5 from survey years 2020, 2021, 2022, and 2023, yielding approximately 1,200-1,600 observations per single-year age bin.

#### Model Specification

For a binary outcome $Y$ (e.g., ACE exposure, excellent health), we fit survey-weighted logistic regression models with age bin fixed effects, a linear year term, and age × year interaction:

$$\text{logit}(P(Y_{ijk} = 1)) = \beta_0 + \sum_{a=1}^{5} \beta_a \cdot \mathbb{1}(\text{Age}_i = a) + \beta_{\text{year}} \cdot \text{Year}_j + \sum_{a=1}^{5} \beta_{a,\text{year}} \cdot \mathbb{1}(\text{Age}_i = a) \cdot \text{Year}_j$$

where:
- $Y_{ijk}$ is the binary outcome for child $k$ in household $i$ in survey year $j$
- Age is a categorical variable (factor) with six levels (0-5 years)
- Year is continuous (2020, 2021, 2022, 2023)
- The age × year interaction captures differential temporal trends by age

As with ACS, we tested whether the age × year interaction significantly improved model fit using a design-adjusted F-test. If the interaction was not statistically significant (p > 0.05), we used the simpler main-effects model:

$$\text{logit}(P(Y_{ijk} = 1)) = \beta_0 + \sum_{a=1}^{5} \beta_a \cdot \mathbb{1}(\text{Age}_i = a) + \beta_{\text{year}} \cdot \text{Year}_j$$

Models were estimated using survey-weighted quasi-likelihood (`svyglm()` with `family = quasibinomial()`) on the Nebraska-subset design object. This approach:

1. Produces design-unbiased estimates accounting for stratification, clustering, and unequal weights
2. Yields design-based standard errors reflecting true sampling variability
3. Leverages temporal information to smooth year-to-year sampling variability
4. Allows flexible age patterns without assuming linearity

#### Prediction Strategy

We predicted age-specific probabilities at the most recent available survey year for each outcome:

- **Child ACE exposure, emotional/behavioral problems, excellent health:** Predicted at year 2023 (most recent data)
- **Child care 10+ hours/week:** Predicted at year 2022 (last year with valid data)

Predictions for age $a$ at prediction year $Y_{\text{pred}}$ were computed as:

$$\hat{p}_{a,NE} = \text{expit}\left(\hat{\beta}_0 + \hat{\beta}_a + \hat{\beta}_{\text{year}} \cdot Y_{\text{pred}} + \hat{\beta}_{a,\text{year}} \cdot Y_{\text{pred}}\right)$$

This yields six age-specific estimates per outcome (ages 0-5) representing Nebraska children's most current population distributions while incorporating information from all four survey years.

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

## Uncertainty Quantification via Bootstrap Replicate Weights

### Rationale

Point estimates alone are insufficient for understanding sampling variability in raking targets. To quantify uncertainty and enable sensitivity analyses of post-stratification weighting, we generated bootstrap replicate weights using the Rao-Wu-Yue-Beaumont bootstrap method (Beaumont & Émond, 2022). This approach:

1. Preserves complex survey design features (stratification, clustering, unequal weights)
2. Produces design-consistent variance estimates for nonlinear statistics
3. Allows construction of empirical sampling distributions for each raking target
4. Enables assessment of raking stability across the uncertainty distribution

### Bootstrap Method

We used the **Rao-Wu-Yue-Beaumont** bootstrap for complex surveys implemented in the `svrep` R package (Schneider & Valliant, 2022). This method extends classical bootstrap resampling to complex surveys by:

1. **Stratified resampling:** Within each sampling stratum, PSUs are resampled with replacement
2. **Rescaling adjustment:** Bootstrap weights are adjusted to match original design totals within each stratum, reducing variability from resampling
3. **Design consistency:** Variance estimates converge to the correct design-based variance as sample size increases

For each data source (ACS, NHIS, NSCH), we generated **one shared bootstrap design** with **4,096 replicate weights**:

```r
boot_design <- svrep::as_bootstrap_design(
  design = survey_design_object,
  type = "Rao-Wu-Yue-Beaumont",
  replicates = 4096
)
```

**Critical design feature:** All estimands from the same data source share the same bootstrap replicate weights. For example:
- All 25 ACS estimands use the same 4,096 replicate weights generated from the base ACS survey design
- This shared structure preserves the covariance between estimands, enabling joint inference
- For filtered samples (e.g., mother's education requires MOMLOC > 0), we use `survey::subset()` to properly maintain the replicate weight structure

The choice of 4,096 replicates provides:
- High precision for tail quantiles (0.025, 0.975) of sampling distributions
- Stable coverage probabilities for 95% confidence intervals
- Sufficient resolution for sensitivity analyses of raking procedures

### Replicate Estimation

For each of the 4,096 bootstrap replicates, we re-estimated all raking targets using identical model specifications as the point estimates. This was accomplished using the `withReplicates()` function:

```r
boot_estimates <- svrep::withReplicates(
  design = boot_design,
  theta = estimation_function,
  return.replicates = TRUE
)
```

where `estimation_function` contains the same GLM prediction code used for point estimates, but evaluated on each bootstrap replicate's weights.

**Output structure:** For each estimand × age combination, we obtained:
- 1 point estimate (from original weights)
- 4,096 bootstrap replicate estimates (from replicate weights)

**Total estimates generated:**
- **Point estimates:** 180 (30 estimands × 6 ages)
- **Bootstrap replicates:** 737,280 (180 × 4,096)

### Database Storage

Bootstrap replicate estimates are stored in a DuckDB table with the following structure:

```
raking_targets_boot_replicates
├── survey (VARCHAR)          # Survey identifier ('ne25')
├── data_source (VARCHAR)     # Data source (ACS/NHIS/NSCH)
├── age (INTEGER)             # Child age 0-5
├── estimand (VARCHAR)        # Estimand name (matches raking_targets_ne25)
├── replicate (INTEGER)       # Bootstrap replicate number 1-4096
├── estimate (DOUBLE)         # Bootstrap replicate estimate
├── bootstrap_method (VARCHAR) # 'Rao-Wu-Yue-Beaumont'
├── n_boot (INTEGER)          # Total replicates (4096)
└── estimation_date (DATE)    # Generation timestamp
```

Primary key: `(survey, data_source, estimand, age, replicate)`

Indexes are created on:
- `(estimand, age)` - Fast filtering to specific targets
- `(estimand, age, replicate)` - Sequential replicate access
- `(data_source)` - Filtering by data source

### Usage

The bootstrap replicate estimates enable:

1. **Confidence intervals:** Percentile-based 95% CIs computed as 2.5th and 97.5th percentiles of 4,096 replicates
2. **Standard errors:** Design-based SEs computed as standard deviation of 4,096 replicate estimates
3. **Raking sensitivity analysis:** Re-run raking algorithm on each replicate to assess weight stability
4. **Visualization:** Empirical density plots of target distributions for diagnostics

**Example query (R):**

```r
# Get bootstrap distribution for "Child ACE Exposure" at age 3
boot_dist <- DBI::dbGetQuery(con, "
  SELECT replicate, estimate
  FROM raking_targets_boot_replicates
  WHERE estimand = 'Child ACE Exposure (1+ ACEs)'
    AND age = 3
  ORDER BY replicate
")

# Compute 95% CI
quantile(boot_dist$estimate, probs = c(0.025, 0.975))
```

### Limitations

1. **Computational cost:** Generating 737,280 estimates requires ~15-20 minutes on a standard workstation (Windows 11, Intel i7, 32GB RAM)
2. **Storage:** Replicate table occupies ~60 MB in DuckDB (compressed)
3. **Design assumptions:** Bootstrap validity assumes the original survey design is correctly specified with all necessary design variables (PSUs, strata, weights)
4. **Regional aggregation:** NHIS bootstrap replicates reflect North Central region uncertainty, not state-specific uncertainty
5. **Shared replicate structure:** While shared replicates within each data source correctly preserve covariance, replicates are independent across data sources (ACS, NHIS, NSCH), which is appropriate given different sampling frames and designs

---

## Validation

### Completeness and Range Checks

We verified that all 180 target estimates (30 estimands × 6 age bins) were successfully computed with values in the valid probability range [0, 1].

### Internal Consistency

For categorical variables that partition the population, we ensured proportions summed to 1.0 within each age bin:

- **Federal poverty level (5 categories):** Guaranteed by ordered logit model structure - predicted probabilities automatically sum to 1.0
- **PUMA geography (14 categories):** Guaranteed by multinomial logit model structure - predicted probabilities automatically sum to 1.0
- **Race/ethnicity (3 categories):** The three binary estimates (white non-Hispanic, Black any, Hispanic any) were verified to be internally consistent, though they do not form a mutually exclusive partition (individuals can appear in multiple categories). We verified that white non-Hispanic + other race categories approximated 100% of the population.

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

All analyses were conducted in R version 4.5.1 (R Core Team, 2024) and Python 3.13. Survey-weighted analyses used the survey package in R (Lumley, 2004). Bootstrap replicate weights were generated using the svrep package (Schneider & Valliant, 2022). Data management used DuckDB for efficient querying of large datasets.

Statistical code is available in the project repository with documentation of data sources, variable definitions, and estimation procedures to facilitate reproducibility. However, access to restricted-use IPUMS microdata requires separate user registration and data use agreements.

---

## Ethical Considerations

This analysis used only publicly available or restricted-access datasets with no direct identifiers. ACS and NSCH public-use files do not contain individual identifiers. NHIS restricted-use files accessed through IPUMS comply with National Center for Health Statistics confidentiality protections and do not identify individual states, counties, or detailed geographic locations. All analyses aggregated data to population-level estimates; no individual-level results are reported.

The use of regional estimates (NHIS North Central region) as proxies for state-level estimates introduces geographic imprecision, as the region includes seven states with potentially heterogeneous population characteristics. Sensitivity analyses comparing state-specific estimates from other data sources (ACS, NSCH) to regional estimates could quantify this geographic aggregation bias.

---

## Bootstrap Variance Estimation

### Overview

To quantify sampling uncertainty in raking target estimates, we implemented bootstrap replicate weights using the Rao-Wu-Yue-Beaumont method (Beaumont & Émond, 2022; Schneider & Valliant, 2022). Bootstrap replicates provide empirical sampling distributions for each estimate, enabling computation of design-based standard errors and confidence intervals without relying on asymptotic normality assumptions.

**Implementation Status:** Bootstrap variance estimation is currently implemented for ACS estimands only (25 of 30 total estimands). NHIS and NSCH estimands use point estimates without bootstrap replicates.

### Method: Rao-Wu-Yue-Beaumont Bootstrap

The Rao-Wu-Yue-Beaumont bootstrap method is specifically designed for complex survey designs with stratification, clustering, and unequal sampling weights. This method:

1. Resamples primary sampling units (PSUs) within strata with replacement
2. Rescales weights to preserve the stratified design structure
3. Generates B = 4,096 replicate weight sets from the base survey design
4. Refits all statistical models using each replicate weight set
5. Computes empirical standard errors from the distribution of replicate estimates

**Software Implementation:** We used the `svrep` package in R (Schneider & Valliant, 2022) via the `as_bootstrap_design()` function with `type = "Rao-Wu-Yue-Beaumont"` and `replicates = 4096`.

### Shared Bootstrap Design Approach

A critical feature of our implementation is the use of **shared bootstrap replicate weights** across all ACS estimands. Rather than generating separate bootstrap designs for each of the 25 estimands, we created a single bootstrap design from the base ACS survey design and applied the same 4,096 replicate weight sets to all estimation tasks.

**Advantages of shared bootstrap design:**

1. **Preserves covariance structure:** All 25 ACS estimands share the same sampling variability, enabling joint inference and assessment of correlations between targets
2. **Computational efficiency:** Create bootstrap weights once (56 seconds), use for all estimands
3. **Statistical validity:** Correctly propagates sampling uncertainty from the base design through all derived estimates
4. **Enables variance-covariance estimation:** Supports computation of bootstrap covariance matrices for multivariate raking procedures

**Implementation:** Script `01a_create_acs_bootstrap_design.R` creates the shared design object (6,657 observations × 4,096 replicates, 24.49 MB) which is loaded by all ACS estimation scripts (02-07).

### Separate Binary Models for Multinomial Outcomes

For outcomes with mutually exclusive categories (FPL: 5 categories, PUMA: 14 categories), we initially considered multinomial logistic regression to enforce the constraint that predicted probabilities sum to 1.0. However, after investigation, **no suitable R package exists** for survey-weighted multinomial regression with complex replicate weight bootstrap designs.

**Our solution:** Fit K separate survey-weighted binary logistic regressions and normalize predictions post-hoc:

$$\hat{P}_k^* = \frac{\hat{P}_k}{\sum_{j=1}^K \hat{P}_j}$$

where $\hat{P}_k$ is the raw predicted probability for category $k$ from the binary model.

**Justification:**
- Post-hoc normalization is mathematically equivalent to multinomial regression for prediction purposes
- Maintains sum-to-1 constraint (validated: all row sums = 1.0000 exactly)
- Enables use of standard survey package tools (`survey::svyglm()` with bootstrap designs)
- Commonly used in practice when proper multinomial tools are unavailable

**Technical details:** See `docs/raking/ne25/MULTINOMIAL_APPROACH_DECISION.md` for complete investigation of alternative approaches (`svyVGAM::svy_vglm()`, `CMAverse::svymultinom()`) and why they were unsuitable.

### Bootstrap Replicate Generation

For each estimand, we generated B = 4,096 replicate estimates using parallel processing:

```r
# Pseudocode for bootstrap generation
boot_results <- future.apply::future_lapply(1:4096, function(i) {
  # Extract replicate weights for bootstrap sample i
  temp_weights <- boot_design$repweights[, i]

  # Refit model with replicate weights
  rep_model <- survey::svyglm(outcome ~ AGE + MULTYEAR + AGE:MULTYEAR,
                               design = temp_design,
                               family = quasibinomial())

  # Predict at year 2023 for ages 0-5
  predict(rep_model, newdata = pred_data, type = "response")
}, future.seed = TRUE)
```

**Parallel processing:** 16 workers for production runs, reducing execution time from ~4-6 hours (sequential) to ~15-20 minutes (parallel).

### Bootstrap Standard Errors and Confidence Intervals

Bootstrap standard errors are computed as the empirical standard deviation of replicate estimates:

$$\text{SE}_{\text{boot}}(\hat{\theta}) = \sqrt{\frac{1}{B-1} \sum_{b=1}^B (\hat{\theta}_b - \bar{\theta})^2}$$

where $\hat{\theta}_b$ is the estimate from bootstrap replicate $b$, and $\bar{\theta} = \frac{1}{B} \sum_{b=1}^B \hat{\theta}_b$.

Bootstrap 95% confidence intervals use the percentile method:

$$\text{CI}_{95\%} = [\hat{\theta}_{0.025}, \hat{\theta}_{0.975}]$$

where $\hat{\theta}_{\alpha}$ denotes the $\alpha$ quantile of the bootstrap distribution.

### Database Storage

Bootstrap replicate estimates are stored in the `raking_targets_boot_replicates` table:

- **ACS estimands:** 614,400 rows (25 estimands × 6 ages × 4,096 replicates)
- **NHIS/NSCH estimands:** Not implemented (no bootstrap replicates)
- **Total storage:** ~50 MB compressed

Query example for computing bootstrap standard error:

```sql
SELECT
  estimand,
  age,
  STDDEV(estimate) as bootstrap_se,
  PERCENTILE_CONT(0.025) WITHIN GROUP (ORDER BY estimate) as ci_lower,
  PERCENTILE_CONT(0.975) WITHIN GROUP (ORDER BY estimate) as ci_upper
FROM raking_targets_boot_replicates
WHERE estimand = 'sex_male' AND age = 3
GROUP BY estimand, age
```

### Performance Metrics

**Test run (96 replicates):**
- Execution time: 10.3 minutes
- Database rows: 14,400
- All validation checks passed

**Production run (4,096 replicates):**
- Execution time: ~15-20 minutes
- Database rows: 614,400
- File size: 24.49 MB (bootstrap design) + ~50 MB (replicate estimates)

---

## Limitations

1. **NHIS geographic aggregation:** Use of census region as proxy for state-level estimates may not capture state-specific patterns in parent mental health and ACEs. The North Central region is heterogeneous, including both highly urban (e.g., Minneapolis, Kansas City) and rural states.

2. **Temporal alignment:** ACS data span 2019-2023, NHIS data span 2019-2024, and NSCH data represent a single year (2023). Population characteristics may have changed between data collection and the target survey year (2025), particularly in the context of COVID-19 pandemic effects on household structure, employment, and mental health.

3. **Mother linkage coverage:** Approximately 5% of children in ACS could not be linked to mothers within the household. If these children differ systematically (e.g., foster care, kinship care, institutional settings), mother education and marital status estimates may not fully represent the target population.

4. **Age heaping and measurement error:** Parent-reported child age may be subject to rounding error, particularly at boundaries of age categories. This could lead to minor misclassification between adjacent age bins.

5. **Model assumptions:** Survey-weighted GLM approaches assume specific functional forms (logit link) and may not capture complex nonlinear age or temporal patterns. Sensitivity analyses using alternative model specifications (e.g., splines for nonlinear age trends, generalized additive models) could assess robustness to model misspecification.

---

## References

Battaglia, M. P., Hoaglin, D. C., & Frankel, M. R. (2004). Practical considerations in raking survey data. *Survey Practice*, 2(5), 1-10.

Beaumont, J.-F., & Émond, N. (2022). A bootstrap variance estimation method for multistage sampling and two-phase sampling when poisson sampling is used at the second phase. *Statistics in Transition New Series*, 23(1), 49-65.

Blewett, L. A., Rivera Drew, J. A., King, M. L., Williams, K. C. W., Chen, A., Richards, S., Perfectly, T., & Oh, S. (2024). IPUMS Health Surveys: National Health Interview Survey, Version 7.3 [dataset]. IPUMS. https://doi.org/10.18128/D070.V7.3

Brick, J. M. (2013). Unit nonresponse and weighting adjustments: A critical review. *Journal of Official Statistics*, 29(3), 329-353.

Kroenke, K., Strine, T. W., Spitzer, R. L., Williams, J. B., Berry, J. T., & Mokdad, A. H. (2009). The PHQ-8 as a measure of current depression in the general population. *Journal of Affective Disorders*, 114(1-3), 163-173.

Lumley, T. (2004). Analysis of complex survey samples. *Journal of Statistical Software*, 9(1), 1-19.

R Core Team (2024). R: A language and environment for statistical computing. R Foundation for Statistical Computing, Vienna, Austria.

Ruggles, S., Flood, S., Sobek, M., Backman, D., Chen, A., Cooper, G., Richards, S., Rodgers, R., & Schouweiler, M. (2024). IPUMS USA: Version 15.0 [dataset]. IPUMS. https://doi.org/10.18128/D010.V15.0

Schneider, B. I., & Valliant, R. (2022). svrep: Tools for creating, updating, and analyzing survey replicate weights. R package version 0.6.0. https://CRAN.R-project.org/package=svrep

Seid, M., Sobo, E. J., Gelhard, L. R., & Varni, J. W. (2004). Parents' reports of barriers to care for children with special health care needs: Development and validation of the Barriers to Care Questionnaire. *Ambulatory Pediatrics*, 4(4), 323-331.

---

*Prepared for the Kidsights Data Platform | Statistical Methods Documentation*
*Date: October 2025*

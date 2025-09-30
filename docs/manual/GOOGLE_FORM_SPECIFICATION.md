# Google Form Specification: New Transformed Variable Request

## Form Title
**Kidsights Data Platform: New Transformed Variable Request**

## Form Description
Use this form to request a new transformed (derived) variable for the Kidsights Data Platform. Please provide enough detail that a developer can implement your transformation. See the examples in Question 9 for the level of detail needed.

Your submission will be reviewed by the data team and technical lead before implementation.

---

## Questions

### **Section 1: Basic Information**

#### Q1: Your Name
- **Type:** Short answer
- **Required:** Yes

#### Q2: Your Email
- **Type:** Email
- **Required:** Yes

#### Q3: Variable Name(s)
- **Type:** Short answer
- **Required:** Yes
- **Help text:**
  ```
  Use snake_case format. If creating multiple related variables, list all.

  Examples:
  - educ4_max
  - eligible, authentic, include
  - hisp, race, raceG
  ```

#### Q4: Brief Description
- **Type:** Paragraph
- **Required:** Yes
- **Help text:**
  ```
  One or two sentences describing what this variable represents.

  Example: "Maximum education level achieved by either primary or
  secondary caregiver, collapsed into 4 categories for regression analyses."
  ```

---

### **Section 2: Source Data**

#### Q5: REDCap Field Names
- **Type:** Paragraph
- **Required:** Yes
- **Help text:**
  ```
  List the REDCap variable names (lexicon names) needed for this transformation.
  Put one field name per line.

  Examples:
  cqr004
  nschj017

  OR for checkbox variables:
  cqr010___1
  cqr010___2
  cqr010___3
  (etc. - list all checkbox options)
  ```

#### Q6: Project IDs
- **Type:** Short answer
- **Required:** Yes
- **Help text:**
  ```
  Which REDCap project(s) contain these fields?

  Examples:
  7679
  7679, 7999
  ```

#### Q7: Existing Derived Variables Needed?
- **Type:** Multiple choice
- **Required:** Yes
- **Options:**
  - No, only REDCap fields
  - Yes (specify in the box below)
- **If "Yes" selected, show follow-up:**
  - **Type:** Short answer
  - **Help text:**
    ```
    List derived variable names needed (comma-separated).

    Example: mom_a1, educ_a1
    ```

---

### **Section 3: Variable Type & Transformation**

#### Q8: Data Type
- **Type:** Multiple choice
- **Required:** Yes
- **Options:**
  - Numeric (continuous or count)
  - Logical (TRUE/FALSE)
  - Factor (categorical with levels)

---

#### Q9: Transformation Description
- **Type:** Paragraph
- **Required:** Yes
- **Character limit:** 10,000
- **Help text:**
  ```
  IMPORTANT: Describe the transformation step-by-step with enough detail
  that a developer can implement it. See the 4 examples below for the
  level of detail needed.

  ═══════════════════════════════════════════════════════════════════════

  EXAMPLE 1: Simple Boolean Logic (eligible, authentic, include variables)
  ═══════════════════════════════════════════════════════════════════════

  Source Fields:
  - eligibility (from pipeline, values: "Pass" or "Fail")
  - authenticity (from pipeline, values: "Pass" or "Fail")

  Transformation Logic:
  1. Create 'eligible' = TRUE if eligibility == "Pass", FALSE otherwise
  2. Create 'authentic' = TRUE if authenticity == "Pass", FALSE otherwise
  3. Create 'include' = TRUE if BOTH eligible AND authentic are TRUE

  Variable Labels:
  - eligible: "Meets study inclusion criteria"
  - authentic: "Passes authenticity screening"
  - include: "Meets inclusion criteria (inclusion + authenticity)"

  Missing Data: If either eligibility or authenticity is missing,
  that variable becomes FALSE (conservative approach).

  ═══════════════════════════════════════════════════════════════════════

  EXAMPLE 2: Direct Mapping with Factor Creation (sex variable)
  ═══════════════════════════════════════════════════════════════════════

  Source Field:
  - cqr009 (numeric values: 0 = Female, 1 = Male)

  Transformation Logic:
  1. Map cqr009 values to text labels using REDCap data dictionary:
     0 → "Female"
     1 → "Male"
  2. Convert to factor variable with levels: Female, Male
  3. Create additional logical variable 'female' = TRUE if sex == "Female"
  4. Set reference level to "Female" (for regression interpretation)

  Variable Labels:
  - sex: "Child's sex"
  - female: "Child is female"

  Missing Data: If cqr009 is missing, both sex and female are NA.

  ═══════════════════════════════════════════════════════════════════════

  EXAMPLE 3: Checkbox Pivoting + Category Collapsing (race/ethnicity)
  ═══════════════════════════════════════════════════════════════════════

  Source Fields:
  - cqr010___1 through cqr010___15 (checkbox for each race category, 1=selected)
  - cqr011 (Hispanic ethnicity: 1=Yes, 0=No)

  Transformation Logic:
  1. Pivot checkbox variables from wide to long format:
     - Each cqr010___X becomes a row if value = 1
     - Look up text label for each selected option from data dictionary

  2. Collapse detailed race categories:
     - "Asian Indian", "Chinese", "Filipino", "Japanese", "Korean",
       "Vietnamese" → "Asian or Pacific Islander"
     - "Native Hawaiian", "Guamanian or Chamorro", "Samoan",
       "Other Pacific Islander" → "Asian or Pacific Islander"
     - "Middle Eastern", "Some other race" → "Some Other Race"
     - Keep "White", "Black", "American Indian/Alaska Native" as-is

  3. Create 'hisp' variable:
     - If cqr011 == 1, then "Hispanic"
     - If cqr011 == 0, then "non-Hisp."

  4. Create 'race' variable:
     - If person selected multiple race categories: "Two or More"
     - If person selected only one: use that collapsed category

  5. Create 'raceG' (combined race/ethnicity):
     - If hisp == "Hispanic", then raceG = "Hispanic" (regardless of race)
     - Otherwise, raceG = race + ", non-Hisp."
       (e.g., "White, non-Hisp.", "Black, non-Hisp.")

  Factor Levels (in order):
  - hisp: "non-Hisp.", "Hispanic"
  - race: "White", "Black", "Asian or Pacific Islander",
          "American Indian/Alaska Native", "Some Other Race", "Two or More"
  - raceG: "White, non-Hisp.", "Black, non-Hisp.", "Hispanic",
           "Asian or Pacific Islander, non-Hisp.", "Two or More, non-Hisp.",
           "Some Other Race, non-Hisp."

  Reference Levels:
  - hisp: "non-Hisp."
  - race: "White"
  - raceG: "White, non-Hisp." (majority group for statistical comparisons)

  Variable Labels:
  - hisp: "Child Hispanic/Latino ethnicity"
  - race: "Child race (collapsed categories)"
  - raceG: "Child race/ethnicity combined"

  Missing Data: If no race boxes are checked and cqr011 is missing,
  all three variables are NA.

  ═══════════════════════════════════════════════════════════════════════

  EXAMPLE 4: Taking Maximum + Category Collapsing (education)
  ═══════════════════════════════════════════════════════════════════════

  Source Fields:
  - cqr004 (primary caregiver education, numeric 1-9)
  - nschj017 (secondary caregiver education, numeric 1-9)

  REDCap Values (both fields use same scale):
  1 = 8th grade or less
  2 = 9th-11th grade, no diploma
  3 = High school graduate or GED
  4 = Vocational/trade school
  5 = Some college
  6 = Associate degree
  7 = Bachelor's degree
  8 = Master's degree
  9 = Doctorate or professional degree

  Transformation Logic:

  1. Create educ_max (8-category):
     - If both cqr004 and nschj017 are available: take the HIGHER value
     - If only cqr004 is available: use cqr004
     - If only nschj017 is available: use nschj017
     - If both are missing: NA
     - Convert numeric values to factor with text labels from data dictionary

  2. Create educ4_max (4-category collapsed version):
     - Collapse the 8 categories into 4:
       * Values 1-2 → "Less than High School Graduate"
       * Value 3 → "High School Graduate (including Equivalency)"
       * Values 4-6 → "Some College or Associate's Degree"
       * Values 7-9 → "College Degree"
     - Use plyr::mapvalues() to map old labels to new labels

  Factor Levels (educ4_max):
  0 = "Less than High School Graduate"
  1 = "High School Graduate (including Equivalency)"
  2 = "Some College or Associate's Degree"
  3 = "College Degree"

  Reference Level: "College Degree" (level 3)
  Rationale: Highest education as reference for comparing lower levels

  Variable Labels:
  - educ_max: "Maximum education level among caregivers (8 categories)"
  - educ4_max: "Maximum education level among caregivers (4 categories)"

  Missing Data: If both source fields are NA, output is NA.

  ═══════════════════════════════════════════════════════════════════════

  YOUR TRANSFORMATION (write here):
  ```

---

#### Q10: If Factor - List Levels
- **Type:** Paragraph
- **Required:** No (conditional on Q8)
- **Help text:**
  ```
  List all factor levels IN ORDER (one per line).
  For ordered factors (like education), list from lowest to highest.

  Example for 4-category education:
  Less than High School Graduate
  High School Graduate (including Equivalency)
  Some College or Associate's Degree
  College Degree
  ```

#### Q11: If Factor - Reference Level
- **Type:** Short answer
- **Required:** No (conditional on Q8)
- **Help text:**
  ```
  Which level should be the reference (baseline) for statistical comparisons?

  Common choices:
  - Most common category (for stability)
  - Theoretically meaningful baseline (e.g., "White" for race)
  - Highest level (e.g., "College Degree" for education)

  Example: College Degree
  ```

#### Q12: If Factor - Why This Reference?
- **Type:** Short answer
- **Required:** No (conditional on Q8)
- **Help text:**
  ```
  Brief rationale for reference level choice.

  Example: "Highest education level provides clearest interpretation
  of education effects - coefficients show difference from college-educated."
  ```

---

### **Section 4: Validation**

#### Q13: Example Cases (Input → Output)
- **Type:** Paragraph
- **Required:** Yes
- **Help text:**
  ```
  Provide 3-5 examples showing specific input values and expected output.
  This helps validate the implementation.

  Format: input_var=value, input_var2=value → output_var=result

  Examples:
  cqr004=7, nschj017=8 → educ_max=8 (Master's)
  cqr004=5, nschj017=NA → educ_max=5 (Some college)
  cqr004=NA, nschj017=NA → educ_max=NA

  eligibility="Pass", authenticity="Pass" → include=TRUE
  eligibility="Fail", authenticity="Pass" → include=FALSE
  ```

#### Q14: Missing Data Handling
- **Type:** Multiple choice
- **Required:** Yes
- **Options:**
  - If ANY input is missing → output is NA
  - Use available values; only NA if ALL inputs are missing
  - Missing inputs become FALSE/0 (conservative approach)
  - Custom logic (explain below)
- **If "Custom logic" selected:**
  - **Type:** Short answer
  - **Help text:** "Describe how missing data should be handled"

---

### **Section 5: Research Context**

#### Q15: Why is this variable needed?
- **Type:** Paragraph
- **Required:** Yes
- **Help text:**
  ```
  What research question or analysis requires this variable?
  This helps us prioritize implementation.

  Example: "We need to examine whether maternal education moderates
  the relationship between early intervention and child outcomes at
  age 5. Current education variables don't distinguish maternal from
  paternal education."
  ```

---

### **Section 6: Review Before Submitting**

**Display response summary**

**Confirmation checkbox:**
- [ ] I confirm this specification is complete and ready for technical review

**Submit button**

---

## Post-Submission

**Confirmation email** sent to submitter with:
- Copy of all responses
- Estimated review timeline (1-2 weeks)
- Contact information for questions

**Notification email** sent to data team with:
- Link to response in Google Sheets
- Summary of request
- Assigned reviewer field (to be filled)

---

## Google Sheets Output

Responses collect in a Google Sheet with these columns:
1. Timestamp
2. Name
3. Email
4. Variable Names
5. Brief Description
6. REDCap Fields
7. Project IDs
8. Existing Derived Variables (if any)
9. Data Type
10. Transformation Description
11. Factor Levels (if applicable)
12. Reference Level (if applicable)
13. Reference Rationale (if applicable)
14. Example Cases
15. Missing Data Handling
16. Research Justification
17. **Status** (manually added by reviewer: Pending/Under Review/Approved/Implemented)
18. **Reviewer Notes** (manually added)
19. **Implementation Date** (manually added)
20. **Developer Assigned** (manually added)

---

## Implementation Workflow

1. **Submission received** → Auto-email to data team
2. **Initial review** (1-3 days) → Check completeness, clarify if needed
3. **Domain expert review** (3-7 days) → Validate research logic
4. **Technical review** (3-7 days) → Confirm feasibility, estimate effort
5. **Approval** → Update status in sheet, assign to developer
6. **Implementation** → Developer adds to `recode__()` function
7. **Testing** → Validate with example cases from form
8. **Deployment** → Add to pipeline, update documentation
9. **Notification** → Email submitter that variable is available

---

## Tips for Form Builders

**Google Forms settings to enable:**
- Collect email addresses automatically
- Limit to 1 response per user
- Allow response editing after submit (for clarifications)
- Send confirmation email
- Create response summary

**Conditional logic to set up:**
- Q7: Show follow-up if "Yes" selected
- Q10-12: Only show if Q8 = "Factor"
- Q14: Show follow-up if "Custom logic" selected

**Validation rules:**
- Q2: Validate email format
- Q3: Require non-empty answer
- Q9: Set minimum character count (500 characters to encourage detail)

---

## Key Design Principles

1. **Learn by example:** Extensive examples in Q9 show exactly what detail is needed
2. **Minimal questions:** Only 15 questions (fewer with conditional logic)
3. **Focus on implementation:** Every question provides information developers need
4. **Validate with test cases:** Q13 ensures submitter has thought through edge cases
5. **Justify priority:** Q15 helps team prioritize multiple requests

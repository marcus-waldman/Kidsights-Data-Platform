# Documentation Update: Age-Response Gradient Explorer

**Status:** Not Started
**Created:** 2025-11-12
**Purpose:** Document the new Age-Response Gradient Explorer Shiny app across all relevant documentation files

**Classification:** Quality Assurance utility (mandatory step in IRT Calibration Pipeline)
**Commit:** e003a36 - "Add interactive Shiny app for IRT age gradient exploration"

---

## Phase 1: High-Visibility Quick Wins

**Goal:** Update main project documentation for immediate discoverability
**Files:** CLAUDE.md (3 sections)
**Estimated Time:** 15-20 minutes

### Tasks

- [ ] **CLAUDE.md - Add "Launch Quality Assurance Tools" subsection**
  - **Location:** "Common Tasks" section (after line 321, before "Quick Debugging")
  - **Content:**
    ```markdown
    ### Launch Quality Assurance Tools
    ```bash
    # Age-Response Gradient Explorer (IRT calibration QA - REQUIRED)
    shiny::runApp("scripts/shiny/age_gradient_explorer")
    ```
    **Purpose:** Mandatory visual inspection of age-response gradients before Mplus calibration
    **Prerequisites:** Calibration dataset created (`calibration_dataset_2020_2025` table)
    **What it does:**
    - Box plots showing age distributions at each response level
    - GAM smoothing for non-linear developmental trends
    - Quality flag warnings (negative correlations, category mismatches)
    - Multi-study filtering (6 studies: NE20, NE22, NE25, NSCH21, NSCH22, USA24)
    ```

- [ ] **CLAUDE.md - Update "Current Status" → IRT Pipeline section**
  - **Location:** Lines 452-471 (IRT Calibration Pipeline status)
  - **Action:** Add bullet point under "Development Status" (after line 471):
    ```markdown
    - **Quality Assurance Tools:** Age-Response Gradient Explorer Shiny app (production-ready, REQUIRED)
      - Mandatory pre-calibration visual inspection of 308 developmental items
      - Box plots + GAM smoothing across 6 calibration studies
      - Quality flag integration (negative correlations, category mismatches)
      - Launch: `shiny::runApp("scripts/shiny/age_gradient_explorer")`
      - Documentation: [scripts/shiny/age_gradient_explorer/README.md](scripts/shiny/age_gradient_explorer/README.md)
    ```

- [ ] **CLAUDE.md - Update "Documentation Directory" section**
  - **Location:** Line 355 (Pipeline-Specific Documentation)
  - **Action:** Update IRT Calibration entry to mention QA tools:
    ```markdown
    - **IRT Calibration:** [docs/irt_scoring/](docs/irt_scoring/) - Calibration pipeline, Mplus workflow, constraint specification, quality assurance tools
    ```

- [ ] **→ CHECKPOINT: Phase 1 Complete - Load Phase 2 Tasks**

---

## Phase 2: Reference Documentation

**Goal:** Update command reference and workflow integration guides
**Files:** QUICK_REFERENCE.md, CALIBRATION_PIPELINE_USAGE.md
**Estimated Time:** 20-25 minutes

### Tasks

- [ ] **docs/QUICK_REFERENCE.md - Add to Table of Contents**
  - **Location:** Near line 9-15 (Table of Contents)
  - **Action:** Add new section link:
    ```markdown
    6. [Interactive Tools](#interactive-tools)
    ```

- [ ] **docs/QUICK_REFERENCE.md - Add "Interactive Tools" section**
  - **Location:** After "Common Tasks" section (around line 700-750), before "Render Codebook Dashboard"
  - **Content:**
    ```markdown
    ---

    ## Interactive Tools

    ### Launch Age-Response Gradient Explorer (REQUIRED QA)

    **Purpose:** Mandatory visual quality assurance for IRT calibration before Mplus

    ```r
    # Launch from project root
    shiny::runApp("scripts/shiny/age_gradient_explorer")
    ```

    **What it does:**
    - Box-and-whisker plots showing age distributions at each response level
    - GAM smoothing (b-splines) for non-linear age trends
    - Multi-study filtering (6 studies: NE20, NE22, NE25, NSCH21, NSCH22, USA24)
    - Quality flag warnings (negative correlations, category mismatches)
    - Codebook metadata integration
    - Interactive controls for GAM smoothness (k=3-10)

    **Prerequisites:**
    - Calibration dataset created (`calibration_dataset_2020_2025` table)
    - Required R packages: shiny, duckdb, dplyr, ggplot2, mgcv, jsonlite, DT

    **Quality Assurance Checklist:**
    1. **Developmental Gradients:** Verify positive age-response correlations for skill items
    2. **Negative Flags:** Investigate items with negative gradients (may need exclusion/recoding)
    3. **Category Separation:** Check box plot overlap - overlapping categories indicate poor discrimination
    4. **Study Consistency:** Compare age patterns across all 6 studies

    **Timing:** 3-5 seconds startup, <1 second plot rendering, 15-30 minutes thorough review

    **Documentation:** [scripts/shiny/age_gradient_explorer/README.md](../scripts/shiny/age_gradient_explorer/README.md)

    ---
    ```

- [ ] **docs/QUICK_REFERENCE.md - Add note to IRT Calibration section**
  - **Location:** Around lines 250-260 (IRT calibration dataset section)
  - **Action:** Add note after calibration dataset commands:
    ```markdown
    **⚠️ REQUIRED NEXT STEP:** After creating the calibration dataset, you MUST run the Age-Response Gradient Explorer for visual quality assurance before proceeding to Mplus calibration.

    ```r
    # Launch QA tool
    shiny::runApp("scripts/shiny/age_gradient_explorer")
    ```

    See [Interactive Tools](#interactive-tools) section for detailed QA checklist.
    ```

- [ ] **docs/irt_scoring/CALIBRATION_PIPELINE_USAGE.md - Add QA section**
  - **Location:** After "Quick Start" section (around line 30)
  - **Content:**
    ```markdown
    ---

    ## Visual Quality Assurance (REQUIRED STEP)

    ### Age-Response Gradient Explorer

    **⚠️ MANDATORY:** Before running Mplus calibration, you MUST use the Age-Response Gradient Explorer to visually inspect item quality.

    ```r
    # Launch interactive explorer
    shiny::runApp("scripts/shiny/age_gradient_explorer")
    ```

    ### Quality Assurance Checklist

    **Required Checks (allow 15-30 minutes):**

    1. **✓ Developmental Gradients**
       - Verify positive age-response correlations for skill items
       - Items should show increasing response values with age
       - Look for smooth GAM curves trending upward

    2. **✓ Negative Correlation Flags**
       - Review all items flagged with NEGATIVE_CORRELATION
       - Investigate unexpected negative age-response relationships
       - Document decisions: exclude, recode, or justify retention

    3. **✓ Category Separation**
       - Check box plot overlap at each response level
       - Overlapping boxes indicate poor discrimination between categories
       - Consider collapsing categories or excluding items with severe overlap

    4. **✓ Study Consistency**
       - Compare age patterns across NE20, NE22, NE25, NSCH21, NSCH22, USA24
       - Flag items with dramatically different patterns across studies
       - Verify sufficient sample size in each study

    ### Quality Flags Integrated

    - **NEGATIVE_CORRELATION:** Unexpected negative age-response relationship
    - **CATEGORY_MISMATCH:** Observed categories don't match codebook expectations
    - **NON_SEQUENTIAL:** Non-consecutive response values

    ### Output

    Document your QA findings:
    - List of items to exclude from calibration
    - Items requiring recoding or category collapsing
    - Items flagged for further investigation
    - Justification notes for borderline decisions

    **Documentation:** See [scripts/shiny/age_gradient_explorer/README.md](../../scripts/shiny/age_gradient_explorer/README.md) for detailed app usage.

    ---
    ```

- [ ] **→ CHECKPOINT: Phase 2 Complete - Load Phase 3 Tasks**

---

## Phase 3: Architecture & Structure Documentation

**Goal:** Update technical architecture and directory structure guides
**Files:** PIPELINE_OVERVIEW.md, DIRECTORY_STRUCTURE.md
**Estimated Time:** 15-20 minutes

### Tasks

- [ ] **docs/architecture/PIPELINE_OVERVIEW.md - Update IRT Technical Components**
  - **Location:** IRT Calibration Pipeline section (lines 357-613), "Technical Components" subsection (around line 500-550)
  - **Action:** Add bullet point for quality assurance tools:
    ```markdown
    - **Quality Assurance Tools:**
      - Age-Response Gradient Explorer Shiny app (`scripts/shiny/age_gradient_explorer/`)
      - Box plots + GAM smoothing for 308 items across 6 studies
      - Real-time filtering by item, study, and quality flags
      - Codebook metadata integration
      - **Role:** Mandatory pre-calibration visual inspection of age gradients
      - **Status:** Production-ready (15 test scenarios passed)
      - **Launch:** `shiny::runApp("scripts/shiny/age_gradient_explorer")`
    ```

- [ ] **docs/architecture/PIPELINE_OVERVIEW.md - Update "Next Steps" section**
  - **Location:** "Next Steps for IRT Calibration" (line 605)
  - **Action:** Update Step 1 to reference mandatory QA:
    ```markdown
    1. **Quality Assurance (REQUIRED)** - Use Age-Response Gradient Explorer to inspect age-response patterns
       - Launch: `shiny::runApp("scripts/shiny/age_gradient_explorer")`
       - Complete QA checklist: developmental gradients, negative flags, category separation, study consistency
       - Document item exclusion decisions (items with negative correlations, poor discrimination, etc.)
       - Export quality summary for calibration notes
       - **Timing:** 15-30 minutes for thorough review of 308 items
       - **Output:** Documented list of items to exclude or investigate before Mplus calibration
    ```

- [ ] **docs/DIRECTORY_STRUCTURE.md - Add scripts/shiny/ to "/scripts/" section**
  - **Location:** "/scripts/" section (lines 144-150)
  - **Action:** Add new subdirectory entry:
    ```markdown
    - `shiny/` - Interactive Shiny applications for data exploration and quality assurance
      - `age_gradient_explorer/` - IRT calibration age-response visualization (REQUIRED QA tool)
    ```

- [ ] **docs/DIRECTORY_STRUCTURE.md - Add detailed "/scripts/shiny/" section**
  - **Location:** After "/scripts/" section
  - **Content:**
    ```markdown
    ### `/scripts/shiny/`
    **Purpose:** Interactive Shiny applications for exploratory analysis and quality assurance

    **Current Apps:**
    - **`age_gradient_explorer/`** - Age-response gradient visualization for IRT calibration
      - **Classification:** Quality assurance utility (mandatory pre-calibration step)
      - **Purpose:** Visual inspection of developmental gradients before Mplus calibration
      - **Features:**
        - Box plots showing age distributions at each response category
        - GAM smoothing for non-linear developmental trends
        - Multi-study filtering across 6 calibration studies
        - Quality flag integration (negative correlations, category mismatches)
      - **Launch:** `shiny::runApp("scripts/shiny/age_gradient_explorer")`
      - **Prerequisites:** `calibration_dataset_2020_2025` table exists
      - **Status:** Production-ready (commit e003a36)

    **Architecture:**
    - `app.R` - Launcher script (sources ui.R and server.R)
    - `global.R` - Data loading (runs once on startup)
    - `ui.R` - User interface definition
    - `server.R` - Server logic and reactivity
    - `README.md` - Usage documentation and interpretation guide
    - `TEST_REPORT.md` - Production validation results

    **Design Pattern:** Traditional Shiny multi-file structure for maintainability
    ```

- [ ] **→ CHECKPOINT: Phase 3 Complete - Load Phase 4 Tasks**

---

## Phase 4: Workflow Integration & Finalization

**Goal:** Integrate QA tool into Mplus workflow and complete documentation
**Files:** MPLUS_CALIBRATION_WORKFLOW.md, docs/README.md (if needed)
**Estimated Time:** 15-20 minutes + commit

### Tasks

- [ ] **docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md - Add Stage 0**
  - **Location:** Before "Stage 1: Create Calibration Dataset" section
  - **Content:**
    ```markdown
    ## Stage 0: Visual Quality Assurance (REQUIRED)

    **Purpose:** Mandatory visual inspection of item quality before formal Mplus calibration

    **Tool:** Age-Response Gradient Explorer Shiny app

    ```r
    # Launch interactive explorer
    shiny::runApp("scripts/shiny/age_gradient_explorer")
    ```

    ### Quality Assurance Checklist

    **⚠️ You MUST complete all 4 checks before proceeding to Stage 1:**

    - [ ] **Developmental Gradients** - Verify positive age-response correlations for skill items
      - Items should show increasing response values with age
      - GAM curves should trend upward for developmental items
      - Flag items with flat or negative trends

    - [ ] **Negative Correlation Flags** - Investigate items with unexpected patterns
      - Review all items flagged with NEGATIVE_CORRELATION
      - Document decisions: exclude, recode, or justify retention
      - Export list of items to exclude from calibration

    - [ ] **Category Separation** - Check box plot overlap
      - Overlapping boxes indicate poor discrimination between categories
      - Consider collapsing categories or excluding items with severe overlap
      - Verify adequate spread in age distributions across response levels

    - [ ] **Study Consistency** - Compare patterns across all 6 studies
      - NE20, NE22, NE25 (Nebraska studies)
      - NSCH21, NSCH22 (National benchmarking samples)
      - USA24 (National validation study)
      - Flag items with dramatically different patterns across studies

    ### Timing

    - **Startup:** 3-5 seconds (data loading)
    - **Per-item review:** 30-60 seconds (thorough inspection)
    - **Complete review:** 15-30 minutes for all 308 items

    ### Output

    **Required documentation before proceeding:**
    - List of items to exclude from calibration (with justification)
    - Items requiring recoding or category collapsing
    - Items flagged for further investigation
    - Quality summary notes for calibration documentation

    ### Next Step

    Once QA is complete and exclusion list is documented, proceed to Stage 1 (Create Calibration Dataset) with the refined item list.

    ---
    ```

- [ ] **Check docs/README.md (if file exists)**
  - **Action:** Read `docs/README.md` to check if it's a documentation index
  - **If index exists:** Add Age-Response Gradient Explorer to tools/utilities section
  - **If no index:** Skip this task

- [ ] **Verify documentation consistency**
  - **Check:** All files use same classification ("Quality Assurance utility")
  - **Check:** All files emphasize mandatory nature ("REQUIRED", "MUST")
  - **Check:** All files use same launch command: `shiny::runApp("scripts/shiny/age_gradient_explorer")`
  - **Check:** All files link to app README: `scripts/shiny/age_gradient_explorer/README.md`
  - **Check:** Version number still 3.4.0 (no bump)

- [ ] **→ FINAL TASK: Git commit and push documentation updates**
  - **Command:**
    ```bash
    # Stage documentation changes
    git add CLAUDE.md docs/

    # Create commit
    git commit -m "$(cat <<'EOF'
    Document Age-Response Gradient Explorer as mandatory IRT QA tool

    Updates 7 documentation files to integrate the Age-Response Gradient Explorer Shiny app into the IRT Calibration Pipeline workflow as a mandatory quality assurance step.

    Documentation updates:
    - CLAUDE.md: Add QA tools to Common Tasks and Current Status sections
    - docs/QUICK_REFERENCE.md: New Interactive Tools section with detailed QA checklist
    - docs/irt_scoring/CALIBRATION_PIPELINE_USAGE.md: Add required QA section
    - docs/architecture/PIPELINE_OVERVIEW.md: Update IRT technical components and next steps
    - docs/DIRECTORY_STRUCTURE.md: Document scripts/shiny/ directory structure
    - docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md: Add Stage 0 (mandatory QA step)
    - docs/README.md: Add QA tools reference if index exists

    Classification: Quality assurance utility (not a separate pipeline)
    Workflow integration: Mandatory pre-calibration step between dataset creation and Mplus syntax generation

    Related commit: e003a36 (Add interactive Shiny app for IRT age gradient exploration)

    🤖 Generated with [Claude Code](https://claude.com/claude-code)

    Co-Authored-By: Claude <noreply@anthropic.com>
    EOF
    )"

    # Push to remote
    git push
    ```

---

## Completion Checklist

- [ ] All 7 files updated
- [ ] Documentation consistent across files
- [ ] QA tool framed as mandatory (not optional)
- [ ] Launch command identical in all locations
- [ ] Links between documents verified
- [ ] Version number unchanged (3.4.0)
- [ ] Git commit created with detailed message
- [ ] Changes pushed to remote repository

---

## Notes

**User Decisions:**
- **Classification:** Quality Assurance utility (not a pipeline)
- **Workflow Role:** Mandatory (required step before Mplus calibration)
- **Versioning:** Keep at 3.4.0 (no version bump)
- **Scope:** All files (comprehensive update)

**Key Messaging:**
- Use "REQUIRED", "MUST", "Mandatory" throughout
- Emphasize pre-calibration workflow placement
- Consistent 4-item QA checklist across documents
- 15-30 minute time expectation for thorough review

**Commit Reference:**
- Original Shiny app commit: e003a36
- Documentation commit: (to be created in Phase 4)

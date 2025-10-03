# CLAUDE.md Streamlining - Phased Task List

**Goal:** Reduce CLAUDE.md from 899 lines to ~300 lines while preserving all information in well-organized reference documents.

**Strategy:** Extract detailed content to topic-specific guides, keep CLAUDE.md as concise quick reference with links.

---

## Phase 1: Create New Architecture Documentation

**Objective:** Offload detailed pipeline architecture from CLAUDE.md to dedicated docs.

- [ ] Create `docs/architecture/PIPELINE_OVERVIEW.md`
  - [ ] Add NE25 Pipeline architecture (CLAUDE.md lines 64-78)
  - [ ] Add ACS Pipeline architecture (CLAUDE.md lines 80-95)
  - [ ] Add NHIS Pipeline architecture (CLAUDE.md lines 97-125)
  - [ ] Add NSCH Pipeline architecture (CLAUDE.md lines 127-155)
  - [ ] Add ACS Metadata System (CLAUDE.md lines 157-246)
  - [ ] Add Pipeline Integration section (CLAUDE.md lines 764-829)
  - [ ] Include ASCII diagrams for data flow
  - [ ] Add design rationales for each pipeline

- [ ] Create `docs/architecture/PIPELINE_STEPS.md`
  - [ ] Add NE25 Pipeline steps (CLAUDE.md lines 541-547)
  - [ ] Add ACS Pipeline steps (CLAUDE.md lines 549-586)
  - [ ] Include timing expectations and troubleshooting

- [ ] **Verification Task:** Review Phase 1 deliverables
  - [ ] Verify all architecture content is captured
  - [ ] Verify ASCII diagrams render correctly
  - [ ] Check all internal links work
  - [ ] Confirm no duplication with existing docs

- [ ] **Load Phase 2 tasks into Claude todo list**

---

## Phase 2: Create Coding Standards Documentation

**Objective:** Extract detailed coding standards to separate guide.

- [ ] Create `docs/guides/CODING_STANDARDS.md`
  - [ ] Add R Coding Standards section (CLAUDE.md lines 304-326)
    - [ ] Include namespace requirements with examples
    - [ ] Add required prefixes table
  - [ ] Add Windows Console Output section (CLAUDE.md lines 328-354)
    - [ ] Include rationale and standard replacements
    - [ ] Add code examples (correct vs incorrect)
  - [ ] Add File Naming conventions (CLAUDE.md lines 521-524)
  - [ ] Add R Execution Guidelines (CLAUDE.md lines 528-539)
    - [ ] Temp script pattern
    - [ ] Segfault avoidance

- [ ] Create `docs/guides/PYTHON_UTILITIES.md`
  - [ ] Add R Executor section (CLAUDE.md lines 591-600)
  - [ ] Add Database Operations (CLAUDE.md lines 602-607)
  - [ ] Add Data Refresh Strategy (CLAUDE.md lines 609-610)
  - [ ] Include code examples for each utility

- [ ] **Verification Task:** Review Phase 2 deliverables
  - [ ] Verify all coding standards captured
  - [ ] Test code examples for correctness
  - [ ] Ensure examples follow the standards they document
  - [ ] Check cross-references to other docs

- [ ] **Load Phase 3 tasks into Claude todo list**

---

## Phase 3: Create Missing Data Guide

**Objective:** Extract comprehensive missing data handling to dedicated guide.

- [ ] Create `docs/guides/MISSING_DATA_GUIDE.md`
  - [ ] Add overview section (CLAUDE.md lines 356-377)
    - [ ] recode_missing() requirement
    - [ ] Code examples (correct vs incorrect)
  - [ ] Add "Requirements for Adding New Derived Variables" (CLAUDE.md lines 379-417)
    - [ ] Check REDCap data dictionary
    - [ ] Apply defensive recoding
    - [ ] Conservative composite score calculation
    - [ ] Documentation requirements
  - [ ] Add Common Missing Value Codes (CLAUDE.md lines 412-416)
  - [ ] Add Critical Issue Prevention (CLAUDE.md lines 418-420)
  - [ ] Add Complete Composite Variables Inventory (CLAUDE.md lines 422-444)
    - [ ] Table with all 12 composite variables
    - [ ] Sample size impact statistics
  - [ ] Add Validation Checklist (CLAUDE.md lines 448-457)
  - [ ] Add "Creating New Composite Variables" section (CLAUDE.md lines 459-519)
    - [ ] Implementation checklist
    - [ ] Validation steps
    - [ ] Documentation updates
    - [ ] Template reference
    - [ ] Complete example
    - [ ] Critical reminders

- [ ] **Verification Task:** Review Phase 3 deliverables
  - [ ] Verify completeness of missing data guidance
  - [ ] Check that composite variables table matches current implementation
  - [ ] Validate all checklist items are actionable
  - [ ] Confirm link to R/transform/README.md is correct

- [ ] **Load Phase 4 tasks into Claude todo list**

---

## Phase 4: Create Directory Structure & Geographic Guides

**Objective:** Document directory structure and geographic crosswalk system.

- [ ] Create `docs/DIRECTORY_STRUCTURE.md`
  - [ ] Add Core Directories (NE25) (CLAUDE.md lines 250-257)
  - [ ] Add ACS Pipeline Directories (CLAUDE.md lines 259-267)
  - [ ] Add NHIS Pipeline Directories (CLAUDE.md lines 269-277)
  - [ ] Add NSCH Pipeline Directories (CLAUDE.md lines 279-287)
  - [ ] Add Data Storage section (CLAUDE.md lines 289-300)
  - [ ] Add purpose/description for each major directory

- [ ] Create `docs/guides/GEOGRAPHIC_CROSSWALKS.md`
  - [ ] Add overview (CLAUDE.md lines 632-636)
  - [ ] Add database tables list (CLAUDE.md lines 638-648)
  - [ ] Add loading instructions (CLAUDE.md lines 650-654)
  - [ ] Add querying from R (CLAUDE.md lines 656-664)
  - [ ] Add derived variables list (CLAUDE.md lines 666-676)
  - [ ] Add format explanation (CLAUDE.md lines 678)
  - [ ] Add source files reference (CLAUDE.md lines 680-684)

- [ ] **Verification Task:** Review Phase 4 deliverables
  - [ ] Verify directory structure matches actual codebase
  - [ ] Check geographic crosswalk examples work
  - [ ] Validate all file paths are correct
  - [ ] Test R code snippets

- [ ] **Load Phase 5 tasks into Claude todo list**

---

## Phase 5: Create Quick Reference & Variable System Docs

**Objective:** Extract operational procedures and variable system details.

- [ ] Create `docs/QUICK_REFERENCE.md`
  - [ ] Add Quick Start commands (CLAUDE.md lines 12-52)
    - [ ] All 4 pipeline run commands
    - [ ] Key requirements
  - [ ] Add ACS Utility Scripts (CLAUDE.md lines 565-586)
  - [ ] Add Quick Debugging (CLAUDE.md lines 891-896)
  - [ ] Add environment paths (CLAUDE.md lines 833-844)
  - [ ] Format as cheatsheet (command → description → example)

- [ ] Create `docs/guides/DERIVED_VARIABLES_SYSTEM.md`
  - [ ] Add overview (CLAUDE.md lines 612-614)
  - [ ] Add 99 derived variables breakdown (CLAUDE.md lines 616-625)
    - [ ] Organize by category with counts
  - [ ] Add configuration section (CLAUDE.md lines 627-630)
  - [ ] Link to config/derived_variables.yaml
  - [ ] Link to R/transform/README.md

- [ ] Enhance `docs/codebook/README.md` (if not already complete)
  - [ ] Add JSON-Based Metadata section (CLAUDE.md lines 688-693)
  - [ ] Add Key Functions (CLAUDE.md lines 695-728)
  - [ ] Add IRT Parameters (CLAUDE.md lines 730-757)
  - [ ] Add Dashboard rendering command (CLAUDE.md lines 759-762)

- [ ] **Verification Task:** Review Phase 5 deliverables
  - [ ] Test all commands in QUICK_REFERENCE.md
  - [ ] Verify derived variables count (99) is accurate
  - [ ] Check codebook functions are documented correctly
  - [ ] Validate all cross-references

- [ ] **Load Phase 6 tasks into Claude todo list**

---

## Phase 6: Rewrite Streamlined CLAUDE.md

**Objective:** Reduce CLAUDE.md to ~300 lines with links to detailed docs.

- [ ] Create new CLAUDE.md structure
  - [ ] Header and introduction (20 lines)
  - [ ] Quick Start section (60 lines)
    - [ ] Brief 4-pipeline overview with run commands
    - [ ] Key requirements (condensed)
    - [ ] Link to QUICK_REFERENCE.md for details
  - [ ] Critical Coding Standards (80 lines)
    - [ ] R namespacing (brief example + link to CODING_STANDARDS.md)
    - [ ] Windows ASCII (brief example + link to CODING_STANDARDS.md)
    - [ ] Missing data principles (3-4 key points + link to MISSING_DATA_GUIDE.md)
  - [ ] Common Tasks (40 lines)
    - [ ] Running pipelines (brief)
    - [ ] Testing changes
    - [ ] Debugging issues
    - [ ] Link to QUICK_REFERENCE.md
  - [ ] Documentation Directory (50 lines)
    - [ ] Architecture → docs/architecture/
    - [ ] Coding standards → docs/guides/CODING_STANDARDS.md
    - [ ] Missing data → docs/guides/MISSING_DATA_GUIDE.md
    - [ ] Geographic crosswalks → docs/guides/GEOGRAPHIC_CROSSWALKS.md
    - [ ] Variables → docs/guides/DERIVED_VARIABLES_SYSTEM.md
    - [ ] Directory structure → docs/DIRECTORY_STRUCTURE.md
    - [ ] Quick reference → docs/QUICK_REFERENCE.md
  - [ ] Environment Setup (20 lines)
    - [ ] Software paths
    - [ ] Python packages
  - [ ] Current Status (30 lines)
    - [ ] Brief 1-paragraph summary per pipeline
    - [ ] Link to architecture docs for details

- [ ] Backup current CLAUDE.md
  - [ ] Copy to docs/archive/CLAUDE.md.899lines.backup

- [ ] Replace CLAUDE.md with streamlined version

- [ ] **Verification Task:** Review Phase 6 deliverables
  - [ ] Count lines in new CLAUDE.md (target: ~300)
  - [ ] Verify all critical information is present or linked
  - [ ] Test that links resolve correctly
  - [ ] Compare with backup to ensure no information loss
  - [ ] Read through as AI assistant - is it clear and actionable?

- [ ] **Load Phase 7 tasks into Claude todo list**

---

## Phase 7: Update Index & Cross-References

**Objective:** Ensure all documentation is discoverable and properly linked.

- [ ] Update `docs/INDEX.md`
  - [ ] Add new guides under appropriate sections
  - [ ] Add QUICK_REFERENCE.md
  - [ ] Add DIRECTORY_STRUCTURE.md
  - [ ] Add architecture/PIPELINE_OVERVIEW.md
  - [ ] Add architecture/PIPELINE_STEPS.md
  - [ ] Add guides/CODING_STANDARDS.md
  - [ ] Add guides/MISSING_DATA_GUIDE.md
  - [ ] Add guides/GEOGRAPHIC_CROSSWALKS.md
  - [ ] Add guides/DERIVED_VARIABLES_SYSTEM.md
  - [ ] Add guides/PYTHON_UTILITIES.md

- [ ] Update `docs/README.md`
  - [ ] Add references to new guides
  - [ ] Update quick start links
  - [ ] Ensure structure matches new organization

- [ ] Update pipeline-specific READMEs
  - [ ] Add metadata system overview to docs/acs/README.md (if not exists)
  - [ ] Verify docs/nhis/README.md completeness
  - [ ] Verify docs/nsch/README.md completeness

- [ ] Create `docs/guides/README.md` (if not exists)
  - [ ] List all guides with descriptions
  - [ ] Organize by category (coding, data, operations)

- [ ] **Verification Task:** Review Phase 7 deliverables
  - [ ] Check all new docs appear in docs/INDEX.md
  - [ ] Verify navigation paths from INDEX.md to all guides work
  - [ ] Test reverse navigation (guides back to INDEX.md)
  - [ ] Ensure no orphaned documents

- [ ] **Load Phase 8 tasks into Claude todo list**

---

## Phase 8: Final Validation & Cleanup

**Objective:** Comprehensive testing and quality assurance.

- [ ] Documentation validation
  - [ ] Read through entire new CLAUDE.md as AI assistant
  - [ ] Follow all links from CLAUDE.md to verify they resolve
  - [ ] Check that each linked document contains expected content
  - [ ] Verify no critical information was lost in migration

- [ ] Completeness check
  - [ ] Compare old CLAUDE.md line count (899) vs new (~300)
  - [ ] Verify 66%+ reduction achieved
  - [ ] Ensure all 10 new/enhanced docs exist
  - [ ] Count total documentation lines (should be similar to original)

- [ ] Cross-reference validation
  - [ ] Test all internal links in new docs
  - [ ] Verify code examples run correctly
  - [ ] Check file paths are accurate
  - [ ] Validate command examples

- [ ] AI assistant usability test
  - [ ] Can AI quickly find pipeline run commands?
  - [ ] Can AI quickly find coding standards?
  - [ ] Can AI quickly find missing data guidance?
  - [ ] Is navigation intuitive?

- [ ] Create migration summary document
  - [ ] Document what moved where
  - [ ] List all new files created
  - [ ] Note any breaking changes
  - [ ] Add metrics (line count reduction, # of docs created)

- [ ] Update version number
  - [ ] Update CLAUDE.md footer (v3.1.0 → v3.2.0)
  - [ ] Update docs/README.md if versioned

- [ ] **Final Verification Task:** Complete project checklist
  - [ ] All 8 phases complete
  - [ ] All verification tasks passed
  - [ ] No broken links
  - [ ] CLAUDE.md ~300 lines
  - [ ] All information preserved
  - [ ] Documentation is more navigable than before

---

## Metrics & Success Criteria

**Before:**
- CLAUDE.md: 899 lines
- All content in single file

**After (Target):**
- CLAUDE.md: ~300 lines (66% reduction)
- 10 new/enhanced reference documents
- Clear navigation paths
- No information loss
- Improved discoverability

**Success Criteria:**
- [ ] CLAUDE.md ≤ 350 lines
- [ ] All 10 reference docs created
- [ ] Zero broken links
- [ ] All critical coding standards accessible within 2 clicks from CLAUDE.md
- [ ] AI assistant can find any topic in <30 seconds

---

## Document Inventory

**New Documents (10):**
1. `docs/architecture/PIPELINE_OVERVIEW.md`
2. `docs/architecture/PIPELINE_STEPS.md`
3. `docs/guides/CODING_STANDARDS.md`
4. `docs/guides/PYTHON_UTILITIES.md`
5. `docs/guides/MISSING_DATA_GUIDE.md`
6. `docs/DIRECTORY_STRUCTURE.md`
7. `docs/guides/GEOGRAPHIC_CROSSWALKS.md`
8. `docs/QUICK_REFERENCE.md`
9. `docs/guides/DERIVED_VARIABLES_SYSTEM.md`
10. `docs/guides/README.md` (if needed)

**Enhanced Documents (3):**
1. `docs/codebook/README.md`
2. `docs/INDEX.md`
3. `docs/README.md`

**Backup:**
1. `docs/archive/CLAUDE.md.899lines.backup`

---

## Notes

- Each phase builds on previous phases
- Verification tasks ensure quality gates
- Loading next phase into todo list maintains focus
- Can pause between phases if needed
- All content preserved, just reorganized

# Claude Code Specialist Agents

This directory contains domain-expert subagents for the Kidsights Data Platform. Each agent is specialized for a specific pipeline or methodology.

---

## Available Agents

### 1. Raking Specialist (`raking-specialist.yaml`)

**Purpose:** Expert in NE25 raking targets pipeline, bootstrap variance estimation, and survey weighting

**Use for:**
- Running raking targets pipeline (point estimates or bootstrap)
- Troubleshooting estimation scripts (02-07)
- Performance optimization (worker counts, replicate numbers)
- Statistical consultation (separate binary models, Rao-Wu-Yue-Beaumont bootstrap)
- Database queries for raking targets

**Key Documentation:**
- `docs/raking/README.md`
- `docs/raking/NE25_RAKING_TARGETS_PIPELINE.md`
- `docs/raking/ne25/BOOTSTRAP_IMPLEMENTATION_PLAN.md`

**Created:** October 2025
**Status:** Production ready

---

### 2. Imputation Specialist (`imputation-specialist.yaml`)

**Purpose:** Expert in geographic imputation pipeline, multiple imputation methodology, and helper functions

**Use for:**
- Scaling M (e.g., M=5 to M=20)
- Adding new imputed variables
- Using Python/R helper functions (`get_completed_dataset()`, etc.)
- Variance estimation (Rubin's rules)
- Troubleshooting imputation generation or retrieval
- Multi-study imputation configuration

**Key Documentation:**
- `docs/imputation/IMPUTATION_PIPELINE.md`
- `docs/imputation/IMPUTATION_SETUP_COMPLETE.md`
- `docs/imputation/USING_IMPUTATION_AGENT.md`

**Created:** October 2025
**Status:** Production ready

---

### 3. Imputation Stage Builder (`imputation-stage-builder.yaml`)

**Purpose:** Automates creation of new imputation stages with pattern enforcement and validation

**Use for:**
- Adding new imputation stages to the pipeline
- Generating R imputation scripts (~1300 lines)
- Generating Python database insertion scripts (~800 lines)
- Validating existing imputation implementations
- Integrating stages with pipeline orchestrator
- Ensuring pattern compliance before committing

**Capabilities:**
- ✅ Scaffolding mode: Generates complete file structure with TODO markers
- ✅ Integration mode: Creates orchestrator and helper function code
- ✅ Validation mode: Audits existing stages against 8 critical patterns
- ✅ Documentation mode: Provides update snippets for CLAUDE.md, PIPELINE_OVERVIEW.md

**Time Savings:** ~3.5 hours per stage (from 4 hours manual to 30 minutes)

**Quick Start:**
```
User: "I want to add [domain] imputation using [method]"
Example: "I want to add adult depression (PHQ-9) imputation using CART"
```

**Key Documentation:**
- `docs/imputation/USING_STAGE_BUILDER_AGENT.md` - Complete usage guide
- `docs/imputation/ADDING_IMPUTATION_STAGES.md` - Pattern reference
- `docs/imputation/STAGE_TEMPLATES.md` - R and Python templates
- `docs/imputation/VALIDATION_CHECKS.md` - 8 critical pattern checks
- `docs/imputation/TEST_SCENARIOS.md` - Example test cases

**What It Does:**
- Generates boilerplate with correct patterns (seeds, filtering, metadata)
- Inserts TODO markers for decisions requiring expertise
- Validates compliance automatically
- Provides integration code

**What It Does NOT Do:**
- Make statistical decisions (MICE method, predictors)
- Define domain logic (relationships, formulas)
- Perform data analysis

**Design Philosophy:** 70% Automation + 30% Expertise = 100% Quality

**Created:** October 2025
**Status:** Production ready (Phases 1-4 complete)

---

### 4. Psychometric Specialist (`psychometric-specialist.yaml`)

**Purpose:** Expert in IRT scoring with MAP estimation, codebook maintenance, and Mplus calibration workflows

**Use for:**
- IRT score construction (MAP with latent regression via IRTScoring)
- Updating codebook with new IRT parameters
- Preparing datasets and Mplus syntax for recalibration
- Validating IRT scores and comparing with classical scores
- Drafting GitHub issues for IRTScoring feature requests

**Key Documentation:**
- `docs/irt_scoring/USING_PSYCHOMETRIC_AGENT.md`
- `docs/irt_scoring/CONFIGURATION_GUIDE.md`
- `docs/codebook/UPDATING_IRT_PARAMETERS.md`
- `docs/irt_scoring/MPLUS_CALIBRATION_WORKFLOW.md`

**Priority Scales:**
- Kidsights developmental scores (203 items, unidimensional)
- Psychosocial bifactor scores (44 items, 6 factors)

**Created:** January 2025
**Status:** In development (Phase 1 of 5 complete)

---

## How to Use Agents

### From Command Line

```bash
# If your Claude Code CLI supports agent selection:
claude --agent raking-specialist "How do I run bootstrap with 96 replicates?"
claude --agent imputation-specialist "How do I scale to M=20 imputations?"
```

### From AI Assistant (Task Tool)

If you're an AI assistant, you can invoke specialist agents for domain-specific sub-tasks. Refer to the individual agent YAML files for their specialized prompts and capabilities.

---

## When to Use Which Agent

| Task | Agent to Use |
|------|--------------|
| **Raking Targets** | |
| Raking targets point estimates | raking-specialist |
| Bootstrap variance estimation | raking-specialist |
| Survey-weighted GLM questions | raking-specialist |
| Performance issues with bootstrap | raking-specialist |
| **Imputation - Adding Stages** | |
| Add new imputation stage | **imputation-stage-builder** |
| Generate R/Python scripts | **imputation-stage-builder** |
| Validate existing implementation | **imputation-stage-builder** |
| Integrate stage with pipeline | **imputation-stage-builder** |
| **Imputation - Using/Querying** | |
| Geographic imputation (PUMA/county/tract) | imputation-specialist |
| Scaling M in imputation config | imputation-specialist |
| Helper function usage (Python/R) | imputation-specialist |
| Multiple imputation theory | imputation-specialist |
| Querying imputed data | imputation-specialist |
| **IRT Scoring & Psychometrics** | |
| Calculate IRT scores (MAP with latent regression) | psychometric-specialist |
| Update codebook with new IRT parameters | psychometric-specialist |
| Prepare data/syntax for Mplus recalibration | psychometric-specialist |
| Validate IRT scores vs classical scores | psychometric-specialist |
| Draft IRTScoring package feature requests | psychometric-specialist |
| **General Tasks** | |
| NE25 pipeline (REDCap → DuckDB) | general agent |
| ACS/NHIS/NSCH data extraction | general agent |
| Database management (outside raking/imputation) | general agent |
| General coding questions | general agent |

---

## Agent Capabilities

All specialist agents have access to:

- **Read** - Read scripts, configs, documentation
- **Glob** - Find files by pattern
- **Grep** - Search for specific patterns
- **Bash** - Run commands
- **Edit** - Modify existing files
- **Write** - Create new files

---

## Agent Maintenance

**When to Update Agents:**

1. **Major pipeline changes** - If architecture or key scripts change significantly
2. **New features** - When adding new capabilities to raking/imputation pipelines
3. **Performance improvements** - When optimizations change recommended approaches
4. **Documentation updates** - When docs referenced in agent prompts are restructured

**How to Update Agents:**

1. Edit the `.yaml` file in this directory
2. Update the `prompt:` section with new knowledge
3. Update documentation references if paths change
4. Test the agent with sample questions

---

**Last Updated:** January 4, 2025
**Total Agents:** 4 (raking-specialist, imputation-specialist, imputation-stage-builder, psychometric-specialist)

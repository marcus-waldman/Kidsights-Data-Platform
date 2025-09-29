# User Guides

This directory contains step-by-step guides for common platform tasks and workflows.

## Contents

- **`migration-guide.md`** - Guide for migrating data or system updates

## Available Guides

### For Developers
- Development standards in main `CLAUDE.md`
- R coding standards (explicit namespacing requirements)
- Pipeline execution guidelines

### For Data Managers
- How to run the NE25 pipeline: `"C:\Program Files\R\R-4.5.1\bin\R.exe" --slave --no-restore --file=run_ne25_pipeline.R`
- Understanding derived variables (see `/docs/data_dictionary/`)
- Codebook query examples (see `/docs/codebook/`)

## Guide Structure

User guides should include:
- **Purpose** - What the guide helps you accomplish
- **Prerequisites** - Required software, credentials, or setup
- **Step-by-Step Instructions** - Numbered steps with code examples
- **Troubleshooting** - Common issues and solutions
- **Related Documentation** - Links to relevant technical docs

## Related Files

- Main `CLAUDE.md` - Quick start and development guidelines
- `/docs/pipeline/overview.md` - Pipeline architecture overview
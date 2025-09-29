# System Fixes & Patches

This directory documents critical bug fixes and system patches applied to the platform.

## Contents

- **`2025-09-17_cid8_fixes.md`** - Documentation of CID8 (eligibility criterion 8) removal and related fixes

## Fix Documentation Standards

Each fix document should include:
- **Date** - When the fix was applied
- **Problem** - Detailed description of the bug or issue
- **Root Cause** - Technical explanation of why it occurred
- **Solution** - How the fix was implemented
- **Impact** - What changed as a result
- **Related Commits** - Git commit references

## Major Fixes Applied

### CID8 Removal (September 2025)
Removed complex IRT-based eligibility criterion that was causing pipeline instability. Simplified to 8 eligibility criteria (CID1-7 + completion check).

## Related Files

- `/scripts/audit/` - Audit scripts for validation after fixes
- Git commit history for detailed change tracking
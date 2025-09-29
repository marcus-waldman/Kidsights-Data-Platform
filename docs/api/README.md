# API Documentation

This directory contains documentation for API integrations and endpoints used in the Kidsights Data Platform.

## REDCap API Integration

The platform extracts data from 4 REDCap projects using the REDCapR package:
- **API Credentials**: Stored securely at `C:/Users/waldmanm/my-APIs/kidsights_redcap_api.csv`
- **Configuration**: Project-specific configs in `/config/sources/`

## Related Files

- Main CLAUDE.md for API credential paths
- `/R/extract/` - R functions using REDCapR for data extraction
- `/config/sources/*.yaml` - Project configurations with API specifications
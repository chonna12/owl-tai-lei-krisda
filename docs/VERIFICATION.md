# Backend-only branch verification

The branch excludes Frontend files. npm test creates an isolated PostgreSQL database and tests the API: catalog, buyer login/checkout, address ownership, seller offers/edits, photo persistence/validation and approved-offer protection. The root / route returns Backend service information. No UI tests or UI files are required.

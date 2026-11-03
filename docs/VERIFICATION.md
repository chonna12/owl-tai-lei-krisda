# Verification notes

Before removal, the automated suite checked catalog access, buyer checkout, address ownership, seller offer creation and edits, photo persistence and validation, and protection of approved offers in an isolated temporary PostgreSQL database.

The automated test files and npm test scripts are no longer included. To verify the current app manually, submit a seller offer with a photo, reload the offers list to confirm persistence, and confirm that an approved offer cannot be edited.

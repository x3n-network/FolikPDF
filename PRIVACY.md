# Privacy

Folik is designed to work without an account, backend service, advertising SDK, or analytics SDK.

## Documents

PDFs selected through Files are copied into Folik's local app container so they remain available offline. When the user chooses Scan Document, Folik requests camera access and uses Apple's document camera to capture and correct page images. Captured pages are converted into a PDF inside Folik's local app container. Folik uses Apple's Vision framework on the device to recognize text and add a searchable text layer to scanned PDFs. Reading, searching, thumbnail generation, password unlocking, scanning, text recognition, and markup are performed on the device using Apple frameworks.

Folik does not upload documents or document contents. A document leaves the app only when the user explicitly chooses a destination through the system share sheet or Files interface.

## Passwords

Passwords entered for protected PDFs are passed to PDFKit for the active document session. Folik does not save them.

When the user creates a password-protected copy, Folik passes the confirmed password to PDFKit, verifies the output is locked and can be reopened with that password, then clears the password fields. The password is not written to Folik's library metadata or retained for recovery. The newly protected PDF remains in the local app container after the user explicitly saves it, just like other library documents.

## Signatures and initials

Reusable signatures and initials are stored as files in Folik's local app container using iOS data protection (`completeUnlessOpen`). Folik does not upload them. Removing Folik removes these saved assets unless they are restored as part of an operating-system device backup. A signature already placed in a PDF becomes part of that local document copy and is included when the user exports or shares the PDF.

Folik never overwrites the original when preparing an editable, flattened, redacted, or sanitized export. Flattened copies remove interactive form and annotation objects after painting their visible content onto the pages. A sanitized copy rebuilds every page as an image so source metadata, selectable or hidden text, links, outlines, attachments, scripts/actions, and editable objects are not copied. This intentionally removes document accessibility text and invalidates existing digital signatures in the new copy.

## Privacy reports

PDF privacy reports are generated on-device and are not retained as separate records. Folik inspects common metadata and supported PDF structures, including forms, annotations, links, outlines, attachments, embedded files, catalog-level scripts/actions, and digital-signature fields. Signature reporting can distinguish an unsigned field from a field that contains a PDF signature dictionary, but it does not cryptographically verify identity, certificate trust, or integrity. A report is a bounded compatibility check, not a guarantee that every vendor-specific or malformed PDF object can be identified.

Folik's Sanitize PDF Shortcuts action receives the file the user supplies through Apple's App Intents system, performs the same image-only operation locally, and returns a new file to the shortcut. Folik does not upload or retain a separate copy through this action.

## Network access

The current app does not require network access for its functionality.

## Diagnostics

The open-source app does not include third-party analytics or tracking. Apple may provide developers with aggregated App Store or crash information according to a user's device and App Store privacy settings.

This document describes the current source tree. Any future feature that changes these guarantees must update this file before release.

Removed library PDFs are retained locally in Recently Deleted until the user restores them or explicitly deletes them permanently. Recovery preserves organization, favorites, bookmarks, and reading position. Folik does not automatically expire removed PDFs.

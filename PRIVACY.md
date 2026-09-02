# Privacy

Folik is designed to work without an account, backend service, advertising SDK, or analytics SDK.

## Documents

PDFs selected through Files are copied into Folik's local app container so they remain available offline. When the user chooses Scan Document, Folik requests camera access and uses Apple's document camera to capture and correct page images. Captured pages are converted into a PDF inside Folik's local app container. Folik uses Apple's Vision framework on the device to recognize text and add a searchable text layer to scanned PDFs. Reading, searching, thumbnail generation, password unlocking, scanning, text recognition, and markup are performed on the device using Apple frameworks.

Folik does not upload documents or document contents. A document leaves the app only when the user explicitly chooses a destination through the system share sheet or Files interface.

## Passwords

Passwords entered for protected PDFs are passed to PDFKit for the active document session. Folik does not save them.

## Signatures and initials

Reusable signatures and initials are stored as files in Folik's local app container using iOS data protection (`completeUnlessOpen`). Folik does not upload them. Removing Folik removes these saved assets unless they are restored as part of an operating-system device backup. A signature already placed in a PDF becomes part of that local document copy and is included when the user exports or shares the PDF.

Folik never overwrites the original when preparing an editable or flattened export. Flattened copies remove interactive form and annotation objects after painting their visible content onto the pages.

## Network access

The current app does not require network access for its functionality.

## Diagnostics

The open-source app does not include third-party analytics or tracking. Apple may provide developers with aggregated App Store or crash information according to a user's device and App Store privacy settings.

This document describes the current source tree. Any future feature that changes these guarantees must update this file before release.

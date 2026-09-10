# Folik 1.0.3

Folik 1.0.3 makes private document libraries faster to search, easier to manage, and safer from casual access on an unlocked device.

## App Store “What’s New”

- Search unchanged PDFs faster with a private on-device text index.
- See matching-page counts and highlighted excerpts in library results.
- Optionally protect Folik with Face ID, Touch ID, or your device passcode.
- Duplicate PDFs while keeping their folder, tags, and favorite state.
- Restore or permanently delete several removed documents together.

Your documents and search index remain on your device. No accounts, ads, analytics, or uploads.

## Faster private search

- Caches extracted PDF page text in the system Caches directory so follow-up library searches do not reopen and re-read every unchanged document.
- Invalidates cached text when a PDF changes and removes records for documents that leave the library.
- Limits the cache to 8 MB of text per document and 48 MB overall; oversized documents remain searchable without being cached.
- Treats the index as disposable: cache corruption or a failed cache write cannot prevent library search.
- Shows the number of matching pages and up to three contextual excerpts per document, with the search phrase highlighted.
- Continues to identify scanned PDFs without selectable text and offer the existing on-device OCR workflow.

## Optional App Lock

- Adds an opt-in App Lock using Face ID, Touch ID, or the device passcode.
- Offers immediate, one-minute, and five-minute relock delays.
- Covers document content whenever the app becomes inactive so previews do not remain visible in the app switcher.
- Requires successful authentication before App Lock can be enabled, preventing an unsupported device from becoming stuck behind the lock screen.
- Explains that App Lock protects access to Folik but does not add encryption to individual PDF files.

## Library and recovery polish

- Adds Duplicate to each document's actions while preserving its PDF bytes, folder, tags, and favorite state.
- Shows the live selected-document count in the library title.
- Adds selection mode, Restore All, Delete All, restore-selected, and delete-selected controls to Recently Deleted.
- Retains explicit confirmation before any bulk permanent deletion.

## Compatibility and privacy

- Documents, extracted search text, authentication state, and processing remain on-device.
- The search index is stored in the disposable Caches directory with iOS file protection and is never required to open a document.
- Existing PDFs and library metadata remain compatible; no document rewrite or migration is performed.

## Validation

- Debug and Release generic iOS Simulator builds succeed, and Xcode static analysis passes.
- The complete simulator unit suite passed 98 tests; one optional private-document fixture test was skipped.
- The complete iPhone 17e UI suite passed 39 tests; one optional App Store screenshot fixture test was skipped.
- Focused iPad mini UI checks passed for multi-page search results, document duplication, bulk recovery, and the lock-screen cover.
- New unit coverage exercises search-index persistence and invalidation, document duplication, App Lock enrollment, startup state, and relock delays.
- App Lock authentication passed deterministic automated coverage and a physical-iPhone Face ID smoke test. Touch ID remains a manual release check.

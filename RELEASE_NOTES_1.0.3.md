# Folik 1.0.3

Folik 1.0.3 makes private document libraries faster to search, easier to manage, safer from casual access on an unlocked device, and safer to share.

## App Store “What’s New”

- Search unchanged PDFs faster with a private on-device text index.
- See matching-page counts and highlighted excerpts in library results.
- Optionally protect Folik with Face ID, Touch ID, or your device passcode.
- Duplicate PDFs while keeping their folder, tags, and favorite state.
- Restore or permanently delete several removed documents together.
- Inspect what a PDF carries beyond its visible pages and make a sanitized image-only copy.
- Run Sanitize PDF directly from Shortcuts, Siri, Spotlight, or an automation.
- Create a verified password-protected copy without storing its password.
- Compare two PDFs privately and review added, removed, or changed pages.
- Send up to 20 PDFs directly to Folik from the system share sheet.
- Drag PDFs into the iPad library and open documents in dedicated Split View or Stage Manager windows.

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

## Inspect & Sanitize

- Reports common metadata, selectable-text pages, filled forms, comments, links, outlines, attachments or embedded files, catalog-level scripts/actions, and digital-signature fields entirely on-device.
- Creates an image-only copy whose visible pages can be reviewed before saving.
- Does not copy source metadata, selectable or hidden text, links, outlines, attachments, scripts/actions, or editable form and annotation objects.
- Clearly warns that sanitizing removes search, text selection, interactive features, accessibility text, and existing digital-signature validity.
- Keeps the source PDF unchanged and rejects protected or oversized input.
- Exposes the same local operation as a composable Apple Shortcuts action that returns a new PDF file.

## Password protection and signature status

- Creates a separately named PDF that requires the chosen password to open while preserving the unchanged original.
- Validates and confirms the password, verifies the output remains locked without it, then verifies the chosen password before saving is offered.
- Clears password fields after processing and never stores the password for recovery.
- Distinguishes unsigned digital-signature fields from fields containing signed data without claiming cryptographic verification Folik cannot perform.

## Local PDF comparison

- Compares selectable PDF text entirely on-device without retaining a comparison history.
- Aligns unchanged pages across insertions and removals so later pages do not all appear changed.
- Reports added, removed, changed, and unchanged page counts with bounded before/after excerpts.
- Clearly labels the result as text-based: image, layout, color, font, and annotation-only changes are not detected.
- Directs scanned documents through the existing OCR workflow and rejects protected or oversized input.

## Add to Folik

- Adds an **Add to Folik** action to the system share sheet in Files, Mail, Safari, and other apps that provide PDFs.
- Validates readable PDF content and accepts up to 20 files and 100 MB total per share.
- Copies files into a private App Group inbox, then atomically moves them into the Folik library when the app becomes active.
- Keeps source files unchanged, gives duplicate names numbered suffixes, and retains failed queued files for a later retry.
- Works entirely on-device without an account, analytics, uploads, or network access.

## iPad windows and drag and drop

- Adds **Open in New Window** to document actions when iPadOS supports multiple scenes.
- Keys dedicated windows by document filename, bringing an existing window forward when the same PDF is requested again.
- Keeps navigation and reader panels independent in each window while coordinating App Lock across every active scene.
- Starts the App Lock relock timer only after the last Folik scene enters the background, preventing one window from locking another active window.
- Accepts file-backed PDF drops across the full library with visible, Dynamic Type-friendly feedback and the existing Files picker as an accessible alternative.
- Validates up to 20 readable PDFs and 100 MB total, imports off the main thread, preserves sources, and removes temporary transfer files.

## Compatibility and privacy

- Documents, extracted search text, authentication state, and processing remain on-device.
- PDFs awaiting import from the share extension remain in the private Folik App Group container.
- The search index is stored in the disposable Caches directory with iOS file protection and is never required to open a document.
- Existing PDFs and library metadata remain compatible; no document rewrite or migration is performed.

## Validation

- Debug and Release generic iOS Simulator builds succeed, and Xcode static analysis passes.
- The complete simulator unit suite passed 119 tests; one optional private-document fixture test was skipped.
- The complete iPhone 17 UI suite passed 45 tests; the optional App Store screenshot fixture and iPad-only multi-window test were skipped.
- Focused iPad mini UI checks passed for multi-page search results, document duplication, bulk recovery, and the lock-screen cover.
- Focused iPhone and iPad mini UI checks passed for inspecting, previewing, saving, and preserving the original during sanitizing.
- New unit coverage exercises search-index persistence and invalidation, document duplication, App Lock enrollment, startup state, single- and multi-scene relock delays, privacy reporting, catalog-level active/embedded content detection, sanitized-output structure, share-inbox validation and transfer, and file-backed drop staging and cleanup.
- App Lock authentication passed deterministic automated coverage and a physical-iPhone Face ID smoke test. Touch ID remains a manual release check.
- A signed generic-device build verifies matching App Group entitlements and provisioning for Folik and its embedded share extension.

# Folik 1.0.2 — Everyday polish

## App Store “What’s New”

- Pick up where you left off: Folik now remembers the last page and page layout for each PDF.
- Rename and favorite documents directly from the library.
- Sort by newest, oldest, name, or file size, with favorites kept at the top.
- Select multiple documents to organize, favorite, share, or remove them together.
- Find every workflow more easily in the new grouped Add & Tools screen.
- Find text and common sensitive information on-device, review the matches, and add selected areas to a redacted copy.

Your documents and reading activity remain on your device. No accounts, ads, analytics, or uploads.

## Detailed changes

### Reading continuity

- Persists the last-viewed page and continuous, single-page, or two-page layout independently for each local PDF.
- Clamps saved page positions if a document later contains fewer pages.
- Restores reading state after unlocking a password-protected document without storing its password.
- Removes saved reading state when the local document is removed.

### Library management

- Adds rename with filename validation and collision handling.
- Migrates folders, tags, favorite status, bookmarks, and reading state when a document is renamed.
- Adds favorite and remove-favorite actions, with favorites pinned before the chosen secondary sort order.
- Adds newest, oldest, filename, and file-size sorting.
- Adds a dedicated Select/Done mode with visible selection indicators and bulk Organize, Favorite, Share, and Remove actions.
- Preserves existing folder and tag metadata through a backward-compatible metadata decode.

### Library design and document tools

- Puts documents first with compact Sort and Filter menus and a small on-device privacy footer.
- Groups favorites under a labeled section, with a Favorites-only filter alongside folder and tag filters.
- Shows active filters and offers a one-tap reset, including when no documents match.
- Uses larger PDF previews, quieter metadata, and adaptive document rows for accessibility text sizes.
- Keeps selection indicators tappable and clears selections that leave the visible results.
- Opens Make PDF Searchable, Compress PDF, and Redact PDF directly from a document’s Tools menu with that PDF loaded.
- Shows the selected source filename, supports choosing another PDF, and keeps existing preview/save-as-copy workflows.
- Clears source-specific redaction state when loading another PDF so failed replacement loads cannot reuse the previous document’s marks.

### Tool discovery

- Replaces the long Add menu with a grouped Add & Tools screen.
- Separates Capture and import, Convert to PDF, and Improve and protect workflows.
- Keeps system-native navigation, Dynamic Type, VoiceOver labels, and minimum touch targets.

### Smarter redaction review

- Finds literal text without case or accent sensitivity in selectable PDFs.
- Suggests email addresses, phone numbers, and US Social Security numbers using on-device pattern matching.
- Requires a review step where individual suggestions can be selected or cleared before any redaction areas are added.
- Supports rotated pages and directs image-only PDFs to Make PDF Searchable first.
- Keeps the existing image-only redaction output, page review, cancellation, and 500-area safety limit.

## Compatibility and privacy

- Existing PDFs are not rewritten by library organization, favorites, sorting, rename metadata migration, or reading-state persistence.
- Reading position and layout are stored locally in app preferences.
- Library organization and favorite status remain in the protected app-local sidecar.
- No account, network service, analytics, or document upload was added.

## Validation

- The complete simulator unit-test run passed 88 tests, with one optional private-document test skipped.
- The complete iPhone simulator UI suite passed 24 tests; one fixture-dependent App Store screenshot test was intentionally skipped.
- Focused iPad mini checks passed for library navigation, import controls, smart redaction, form-field navigation, annotations, and search.
- A final focused deletion test confirmed that removing a document clears both bookmarks and saved reading state.
- The unsigned iOS Simulator build succeeded. Validation is simulator-based; physical-device testing and App Store submission are not claimed.

### Validation after the library redesign

- Re-ran the complete unit suite: 88 passed; one optional private-document fixture test skipped.
- Seven distinct focused iPhone UI scenarios passed across the redesign runs: Add & Tools discovery, compressed-copy save, all three document tools and clean global-tool state after cancellation, Favorites-only filtering/reset, organization/content search, bulk favorites, and largest-text long-filename navigation.
- Three focused iPad mini scenarios passed: compressed-copy save, document-tool routing/cancellation, and Favorites filtering/reset.
- The final iPhone run verified compression/save, Favorites filtering, and largest Dynamic Type in dark mode after the spacing correction. Portrait and landscape screenshots were inspected; long document rows remain scrollable.
- Reviewed final iPad light-mode and iPhone dark-mode screenshots, including source filenames in tool sheets. Corrected an oversized controls row and restored visible menu labels during visual QA.
- Generic simulator build and final whitespace checks passed. An initial UI-test failure was caused by the test not scrolling to Compress PDF on iPhone 17e; the corrected workflow passed on iPhone and iPad.
- This was focused post-redesign UI validation, not a repeat of the earlier complete UI suite. Physical-device, manual VoiceOver, and large-PDF performance checks remain release QA tasks. The mobile audit script does not inspect Swift files and supplied no useful coverage.

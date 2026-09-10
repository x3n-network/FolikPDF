# Everyday PDF polish — included in 1.0.4

This first pass and the subsequent optimization pass ship together as **1.0.4**. See [the combined release notes](RELEASE_NOTES_1.0.4.md).

Sharing now ends active field editing and waits for confirmed persistence before preparing a copy. If saving fails, sharing stops, the in-memory edits remain available, and the reader offers a retry through its save status. The share sheet shows the filename and explains editable versus flattened copies in plain language.

Sign is directly available in Annotations and Forms. A saved signature begins placement immediately; creating a signature opens the existing on-device capture flow. Existing signature and initials management remains in the Add menu.

Pages includes a Contents switch. The reader has four main controls and places Forms before Annotations when fields are present. Forms remains available on scans for field creation. The page navigation area shows local save status.

OCR, compression, redaction, sanitizing, and fillable-copy previews use task-specific titles. OCR shows recognized and preserved page counts; compression prominently shows the before/after size. Reviewed copies use Save Copy and display their filename. The existing save completion flow opens the resulting document.

Add & Tools puts Scan Document, Choose PDFs, and Images to PDF together first, followed by other conversion and document tools.

## Validation

- Final unit suite: 127 passed, one optional private-document fixture skipped, zero failures.
- Focused UI coverage passed across iPhone 17, iPhone 17e, and iPad mini: saving/export handoff, signature creation and reuse, Contents navigation, import discovery, reader navigation and annotations, scan field authoring, OCR, compression, redaction, and sanitizing.
- Large accessibility text and portrait/landscape checks passed on both iPhone sizes and iPad mini. Light and dark screenshots were visually inspected.
- The initial direct-signature test exposed a capture-state reset. Moving sheet presentation to stable panel state fixed it; creation/placement and reuse tests subsequently passed.
- The iPad OCR test initially failed because the tool was below the sheet viewport. The test now scrolls to it, and the preview/save flow passed.
- Debug simulator builds and the final whitespace check passed. Physical-device and manual VoiceOver testing were not performed in this pass.

Result bundles are in `/tmp/folik-polish-*.xcresult`; screenshot exports are in `/tmp/folik-polish-*-images` and `/tmp/folik-polish-small-images`.


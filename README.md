# Folik

Folik is a native, local-first PDF reader and workspace for iPhone and iPad. It is free, open source, and built without accounts, ads, analytics, document uploads, or in-app purchases.

[Download FolikPDF on the App Store](https://apps.apple.com/app/folikpdf/id6808051666)

## Current capabilities

- Import one or more PDFs from Files
- Make existing scanned PDFs searchable with on-device OCR, progress, cancellation, and review before saving a new copy
- Convert JPEG, PNG, or HEIC images from Photos or Files into a named, ordered, searchable multipage PDF (up to 30 images, 20 MB each and 100 MB total)
- Convert Word DOCX and LibreOffice ODT documents on-device, review the generated PDF and conversion notes, then save the exact preview to the library
- Convert TXT (UTF-8/UTF-16) or basic RTF documents up to 5 MB into searchable PDFs with Letter-size pages; complex layouts and attachments are not supported
- Open PDFs in Folik from Files, Mail, Safari, and other apps using the system share sheet or Open In menu
- Scan multi-page paper documents with automatic edge detection and perspective correction, then add an on-device searchable text layer and save them as local PDFs
- Keep a private on-device document library with virtual folders and tags
- Search filenames, folders, tags, and selectable PDF text across the library, with matching page excerpts
- Read PDFs with native PDFKit rendering
- Browse page thumbnails and document outlines
- Bookmark important pages locally and filter the Pages panel to return to them quickly
- Organize pages in a safe new copy: reorder, rotate, duplicate, delete, extract, insert blanks, or add pages from another PDF—with multi-step undo
- Find text incrementally with result context, progress, and previous/next navigation
- Fill standard AcroForm text, multiline, checkbox, radio, and choice fields, then save values into the local copy
- See required fields, current values, and form progress, then jump directly to the next unfinished field
- Open password-protected PDFs without retaining the password
- Switch between continuous, single-page, and two-page layouts
- Highlight, underline, or strike selected text and save the result
- Draw with a finger or Apple Pencil using selectable colors and widths
- Browse every supported annotation by page, navigate to it, and delete it with undo support
- Place notes, text boxes, rectangles, and circles with multi-step annotation undo and redo
- Add standard Approved, Draft, Confidential, and Final stamps that remain editable in other PDF apps
- Select annotations on the page, drag to move them, resize supported types, or use precise Move and Size controls
- Change annotation colors and adjust drawing or shape line widths with undo and redo
- Create a handwritten or typed signature/initials, keep it locally on-device, and reuse it across PDFs
- Share the original, create an editable copy, or export a flattened copy that makes forms, signatures, and annotations part of the page
- Adapt navigation for compact iPhone and regular iPad layouts
- Support Dynamic Type, VoiceOver labels, light mode, and dark mode
- Open Folik settings for the [Folik open-source project website](https://www.x3n.network/opensource/folik/), X3N website, team feedback email, privacy details, version, and Apple Standard EULA

Folik is at the beginning of its development. Keep an original copy of important documents while editing behavior is hardened against a broad compatibility corpus.

### Form compatibility

Folik supports the standard AcroForm widgets that PDFKit can edit on iOS. Checkbox and radio state is saved and restored independently from a field's display string, and radio options with the same field name are counted as one logical field. Required fields are identified from standard field flags and prioritized by the next-field navigator. For documents that expose internal field IDs instead of readable labels, Folik derives a concise label from nearby page text. Folik can place a visual handwritten or typed signature over a document, but it does not yet apply certificate-backed cryptographic signatures to digital-signature fields. XFA-only forms cannot be filled by iOS; Folik detects them and explains the limitation instead of showing an empty or misleading editor. JavaScript calculations and other vendor-specific form behavior may vary, so keep an original copy of important forms.

### PDF redaction

Choose **Add (+) → Redact PDF**, mark rectangles by dragging or entering page percentages, then create and review a new copy before saving. Marked regions are painted into rendered pixels before a fresh image-only PDF is created. Source text, metadata, links, outlines, attachments, and editable form/annotation objects are not copied. Visible annotation appearances are flattened where supported. All output pages lose text selection and interactive features; rendering is limited to 200 dpi and 3,500 pixels on the longest side. Review every page before sharing. The original retains its original information. Protected files are rejected; input/output is limited to 100 MB, 500 pages, and 500 marked regions.

### Batch conversion

Choose **Add (+) → Batch to PDF** for up to 20 files and 100 MB total. Add PDFs, supported Office documents, TXT/RTF, or images; move items up/down or remove them before preparing separate PDFs or one combined document. Review each prepared result and its conversion notes, then save the batch. Duplicate filenames get unique suffixes. Preparation failures save nothing; library saving stages and validates every PDF first and rolls back newly moved files on a handled failure. Originals remain unchanged. Combined PDFs can change outlines and page destinations, and retain the conversion limits of each source format.

### Library organization and search

Use a document’s **… → Organize** menu to assign a virtual folder and comma-separated tags. Folder and tag filters narrow the library without moving or renaming files. Organization is stored atomically in an app-local sidecar; unreadable metadata is not silently overwritten. Folder names are limited to 80 characters, with up to 20 tags of 40 characters each.

Library search matches filenames, folder/tag labels, and selectable PDF text, with the first matching page and an excerpt. Search runs off the main thread, debounces typing, and cancels superseded requests. Text is read fresh for each search and is not stored in a persistent index. Locked, unreadable, or oversized documents are skipped with a count. Scanned documents need OCR first.

### PDF compression

Choose **Add (+) → Compress PDF**, then Keep Resolution, Screen Optimized, or Smaller File. Native PDFKit image optimization preserves selectable text and annotations without deliberately flattening them. The preview shows original and result sizes; if optimization would make the file larger, the original bytes are retained and labeled already optimized. Image quality can change, so review before saving a new copy. Protected PDFs are not accepted. Cancellation discards the result after an in-progress native write finishes.

### Existing-PDF OCR

Choose **Add (+) → Make PDF Searchable**. Folik adds an invisible text layer to scanned pages and saves a reviewed new copy. Pages already containing text or annotations are preserved and skipped; the preview reports the counts. OCR can make mistakes, and page destinations/outlines may change. Protected PDFs are not accepted. Input/output limits are 100 MB, 500 pages, and page dimensions up to 40 inches; raster recognition is limited to 3,500 pixels on the longest side. Original page graphics are retained on processed pages.

### Office document conversion

Choose **Add (+) → Documents to PDF** for DOCX, ODT, legacy DOC, and Pages files up to 25 MB. The engine supports styled paragraphs, headings, decimal/alphabetic/Roman lists, embedded raster images (including images in table cells), source margins and table column proportions, horizontal table-cell spans, and searchable text. External web/email links remain clickable. Text boxes enter the reading flow, and footnotes/endnotes are collected at the end. Long paragraphs and table cells continue across PDF pages. Conversion happens entirely on-device, and nothing enters the library until you review the PDF and tap **Save to Library**.

This is a limited document renderer, not a full Word/LibreOffice layout implementation. Fonts may be substituted; image placement, complex table sizing, and pagination may change. Nested tables flow in reading order inside their parent cell. Headers, footers, comments, linked images, charts, and some other objects are unsupported; conversion notes identify detected limitations. Review important documents against their originals. Space-aligned text can have a different extraction/selection order in PDF viewers.

Legacy Word 97–2003 `.doc` files have a **text recovery** mode. It preserves the main text, Unicode, basic paragraph/cell boundaries, page breaks and saved field results. Formatting, images, notes, text boxes and other rich content are omitted, and tracked deletions may appear. The preview explicitly labels this mode. Export DOCX or PDF from Word when fidelity matters.

Pages support is limited to extracting `QuickLook/Preview.pdf` from a ZIP or directory package when present. Those PDF bytes are preserved exactly. Saved previews can be outdated or incomplete; modern Pages files without one require **Export → PDF** in Pages. Thumbnail images are never treated as complete documents.

Google Docs can export a DOCX copy for conversion. Direct Google account access, full Pages layout parsing, and full legacy Word formatting are not included.

See [the conversion engine architecture and compatibility notes](CONVERSION_ENGINE.md).

## Requirements

- iOS or iPadOS 18.6 or later
- Xcode 26.6 or later for development

## Build

Open `Folik.xcodeproj` in Xcode and run the `Folik` scheme, or build an unsigned simulator app:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project Folik.xcodeproj \
  -scheme Folik \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Test

`FolikTests` covers document import, scanned-image PDF generation with extractable OCR text, navigation, per-document bookmark persistence, incremental search, ink annotation persistence, note/text/shape/signature placement, protected reusable-signature storage and migration, annotation movement, resizing, and appearance, multi-step annotation undo and redo, source-preserving page organization, editable and flattened export, and a synthetic form corpus containing text, multiline, checkbox, grouped radio, choice, signature, and XFA cases. A checked-in copy of the official [IRS Form W-9 (revision March 2024)](https://www.irs.gov/pub/irs-pdf/fw9.pdf) provides a public real-world regression case for text fields, checkboxes, XFA/AcroForm coexistence, save/reopen, readable field labels, and flattening. Persistence tests reopen written PDFs and verify annotation data, widget values, signature strokes, and the canonical AcroForm field tree. `FolikUITests` launches with generated document and scanned-page fixtures and exercises the library add menu, reader, page navigation and bookmark filtering, page organizer, annotation workspace, shape and signature placement, accessible annotation movement and appearance controls, drawing mode, Forms panel, regular and OCR-backed Find result navigation, About screen, and export choices.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project Folik.xcodeproj \
  -scheme Folik \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

## Visual identity

The app icon uses Folik's folded-page **F** in standard, dark, and tinted appearances. Source-ready icon variants live in `Folik/Assets.xcassets/AppIcon.appiconset`; the in-app mark is rendered natively in `FolikTheme.swift` so it stays crisp with Dynamic Type and appearance changes.

## Architecture

```text
DocumentLibrary    Imports and owns local PDF copies
DocumentScanner    Native camera capture and scanned-image PDF generation
PDFConverter       Local image and paginated TXT/RTF conversion
PDFConversionView  Image/text selection, image ordering, and conversion review
OfficeDocumentEngine  DOCX/ODT parsing and conversion orchestration
OfficePackage / OfficeXML  Bounded ZIP/XML readers
DOCXReader / ODTReader  Format-specific content and styles
OfficePDFRenderer  Shared searchable text, image and table pagination
OfficeConversionView  Document selection, compatibility notes, PDF preview and save
DocumentSession    Document state, forms, search, navigation, annotations, and persistence
DocumentExporter   Original, editable-copy, and flattened-copy export
PageOrganizer      Source-preserving page operations, merge/extract, and undo
SignatureStore     Protected local storage and legacy migration for reusable signatures
BookmarkStore      Private app-local page bookmarks, isolated by document
PDFKitView         Native PDFView bridge and live ink gesture capture
LibraryView        Library and import experience
ReaderView         Adaptive iPhone/iPad reader chrome
ReaderInspector    Pages, outline, search, and form tools
SettingsView       About, privacy, support, company, and legal links
```

The project intentionally keeps document operations out of SwiftUI views so that OCR, redaction, page editing, and SPDFV-compatible operations can be tested independently.

## Privacy

Folik processes documents locally. See [PRIVACY.md](PRIVACY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Small, focused changes with reproducible PDF fixtures are preferred.

## License

Folik is available under the [MIT License](LICENSE).

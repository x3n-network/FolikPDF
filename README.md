# Folik

Folik is a native, local-first PDF reader and workspace for iPhone and iPad. It is free, open source, and built without accounts, ads, analytics, document uploads, or in-app purchases.

[Download FolikPDF on the App Store](https://apps.apple.com/app/folikpdf/id6808051666)

## Current capabilities

- Import one or more PDFs from Files
- Scan multi-page paper documents with automatic edge detection and perspective correction, then add an on-device searchable text layer and save them as local PDFs
- Keep a private on-device document library
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
- Open Folik settings for the X3N website, team feedback email, privacy details, version, and Apple Standard EULA

Folik is at the beginning of its development. Keep an original copy of important documents while editing behavior is hardened against a broad compatibility corpus.

### Form compatibility

Folik supports the standard AcroForm widgets that PDFKit can edit on iOS. Checkbox and radio state is saved and restored independently from a field's display string, and radio options with the same field name are counted as one logical field. Required fields are identified from standard field flags and prioritized by the next-field navigator. For documents that expose internal field IDs instead of readable labels, Folik derives a concise label from nearby page text. Folik can place a visual handwritten or typed signature over a document, but it does not yet apply certificate-backed cryptographic signatures to digital-signature fields. XFA-only forms cannot be filled by iOS; Folik detects them and explains the limitation instead of showing an empty or misleading editor. JavaScript calculations and other vendor-specific form behavior may vary, so keep an original copy of important forms.

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

The project intentionally keeps document operations out of SwiftUI views so that OCR, future redaction, page editing, and SPDFV-compatible operations can be tested independently.

## Privacy

Folik processes documents locally. See [PRIVACY.md](PRIVACY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Small, focused changes with reproducible PDF fixtures are preferred.

## License

Folik is available under the [MIT License](LICENSE).

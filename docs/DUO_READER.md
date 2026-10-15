# Adaptive reader development checkpoint

The approved Duo study is integrated into Folik’s real reader on `feat/duo-adaptive-reader`, based on the clean 1.0.5 checkpoint `a80cb39`. This is development work, not release approval. No push, archive, upload, signing change, or version bump is part of this integration.

## Shipping design

- Preserve FolikTheme, cobalt accents, native typography, system surfaces, and the cool PDF canvas.
- One reader with native, navigation-container-provided Read / Fill / Build actions. Pages, Find, annotation, layout, bookmark, save, and sharing workflows remain available.
- Read starts without a companion. The actual PDFKit viewport stays at the same structural position as tools open, tasks change, and available width changes.
- At sufficient available container width (620 points or more), ordinary text sizes use a right companion. Its width follows the container, bounded between 280 and 420 points; Build receives a larger share than Fill.
- Wide Fill edits one selected real PDF field, with a field menu, completion progress, and pinned Next unfinished / save actions. Selection belongs to the document session. Opening the pane itself does not navigate or refit the PDF.
- Build reuses the shipping PDF field placement, layout, properties, suggestion, undo, and persistence tools rather than the lab’s placeholder actions.
- Compact and accessibility text sizes keep the familiar modal tools workflow. Presentation depends on available width and text size, not a device-name check or keyboard height.
- Companion opening/closing uses a restrained 0.18-second transition; Reduce Motion and accessibility reading layouts suppress the explicit animation. This is not hinge-driven motion or a hardware performance claim.
- All field writes validate current PDF permissions and widget state. Radio options, multiselect/custom choices, and signature fields retain explicit page-workflow fallbacks rather than unreliable companion edits or pretend certificate signing.

## Source map

- `Folik/ReaderView.swift`: stable PDF-first composition, container measurement, native toolbar tasks, sheets, and companion transition.
- `Folik/ReaderInspector.swift`: inline companion header versus modal navigation toolbar; no nested NavigationStack in the wide companion.
- `Folik/ReaderFillCompanion.swift`: selected-field controls and pinned actions.
- `Folik/DocumentSession.swift`: session-owned selection, live widget mutation, and existing PDF persistence.
- `Folik/ReaderPDFProbe.swift` and the `PDFKitView` probe hook: DEBUG-only inspection of the actual rendered PDFView/document/page/zoom/native selection.
- `FolikUITests/AdaptiveReaderUITests.swift`: native task, width-change, draft, containment, and accessibility-sheet acceptance.
- `FolikTests/ReaderFillCompanionTests.swift`: actual PDF widget edits, save/reopen, logical duplicates, permissions, unsupported-field safety, and field identity regression.

## Evidence boundaries

Native controlled-width tests use the shipping reader and isolated `--ui-test-fixture` PDFs. `--ui-test-reader-continuity` enables the real viewport probe; `--ui-test-reader-resize` changes only the reader’s test container width between 382 and 951 points. Neither argument folds the simulator or represents a shipping layout switch. These controls are compiled out of Release.

The wide host is `Folik Duo Layout Lab`, an iPad Pro simulator on iOS 27.0. Compact regression uses iPhone 17e on iOS 27.0. Do not label those captures as physical Duo poses. The latest Duo integration diagnostic exposed unreliable inner-display input/default capture behavior; its failed bundle is retained. Real Duo outer/inner pose coverage, live folding, reserved-region avoidance, and hardware animation performance remain separate acceptance gates.

An annotation menu test (`FolikUITests/testAnnotationEditingOffersAccessibleMovementControls`, Bold line-width accessibility lookup) also fails on a clean detached `a80cb39` source snapshot on the same iPhone simulator. It is a verified baseline failure, not treated as a passing test. The full app UI suite has not been claimed as passing.

## Final verification

- `folik-production-wide-final2.xcresult`: 182 passed, 1 optional-fixture skip, 0 failures. Includes the complete unit target and two wide/adaptive native UI tests, after the field-identity fix.
- `folik-production-compact-final2.xcresult`: 14 affected compact UI tests passed, 0 failures, after the final source edits.
- Release simulator build passed; `folik-duo-production-release-final.log` contains the actual build output.
- Independent Sonnet source re-review passed with no security concerns or concrete logic errors. Minor UX and additional mixed native-page/companion-editor coverage suggestions remain nonblocking.
- The compact SwiftUI “Publishing changes from within view updates” warning also appears in the clean-baseline run of the 12 corresponding tests. It is preserved as a known baseline warning, not silently ignored.

All result bundles and raw logs are under `/Users/josephspears/.hermes/cache/scratch/`. Machine-readable counts, baseline comparisons, reviewer findings, and acceptance boundaries are recorded in [DUO_READER_VERIFICATION.json](DUO_READER_VERIFICATION.json).

Final shipping-reader captures are in [the evidence gallery](evidence/duo-reader/README.md). They use real PDF fixture edits in an explicitly labeled controlled-width host, not hardware folding. Only orientation was corrected; no content was cropped or composited.

## Apple references and approved study

- https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo
- https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo

The separately preserved native study, sourced guidance, and historical comparison evidence live at `/Users/josephspears/Documents/FolikPDF Design Preview/NativeDuo`. Private hinge transport research remains there and is not included in shipping code.

# FolikPDF 1.0.4

Status: development release; includes both the everyday PDF polish pass and the subsequent optimization pass. App and share extension use marketing version 1.0.4, build 1. Historical 1.0.3 notes and older screenshots retain their original versions.

## App Store — What’s New

FolikPDF 1.0.4 makes everyday PDF work smoother:

- Clearer sharing options, with your latest edits saved before a copy is prepared.
- Sign directly from Forms or Annotations, and find Contents inside Pages.
- Clearer preview titles, filenames, and results when creating a copy.
- Easier access to scanning, PDF import, and Images to PDF.
- Faster library refreshes, reusable document previews, and smoother rapid annotation edits.
- More responsive document preparation and better memory cleanup.
- More efficient library text search and automatic cleanup of temporary sharing copies.
- Clearer save recovery, accessible processing controls, keyboard shortcuts, and easier first steps.
- Compatibility updates for iOS 27, including more reliable editable form fields and consistently visible field outlines.

Free, private, and on your device.

## Workflow finishing polish

- Library search excerpts now open the exact matching page with the query already active in Find.
- Search results show a concise first set of matching pages and can expand in place to reveal the rest of the retained matches.
- Duplicate, favorite, organize, rename, delete, and restore actions provide brief confirmation; reversible library actions include Undo. Undoing a duplicate now removes the new copy outright instead of sending it to Recently Deleted.
- Shared action feedback announces completion once and avoids sliding motion when Reduce Motion is enabled.
- Page organization and batch conversion ask before abandoning changed drafts, while unchanged workflows still dismiss immediately.
- Reader, inspector, page-organizer, and form-builder controls support the full accessibility Dynamic Type range with scrollable compact controls where needed.
- Add & Tools remembers up to three recently used tools while keeping the existing grouped catalog.
- Form building gives clearer placement guidance, identifies the selected field, exposes Edit and Duplicate nearby, and confirms placement with restrained haptic feedback.
- Comparison reports can preview each changed, added, or removed page, side by side on wider layouts and with an Original/Revised switch on compact layouts.
- Form templates show page thumbnails, and personal templates can be renamed from swipe actions or their context menu.
- Settings includes an on-device Using Folik guide for search, organization, forms, signatures, and export choices.

Validation for this finishing pass: the full iPhone 17e native suite passed with 167 tests and one optional private fixture skipped. Six focused iPhone UI workflows passed for exact duplicate Undo, expandable matching pages, batch and page-organizer discard protection, large-text reader rotation, and large-text form building. The latter two search/form workflows also passed on iPad mini. Earlier focused coverage remains in place for exact-page search, comparison previews, Help/version, templates, and form layout/fill order. The final Release simulator build passed for both architectures; the app and share extension report 1.0.4 (build 1). Physical Reduce Motion, VoiceOver, touch, interruption, and cross-viewer checks remain in the device QA checklist.

## iOS 27 compatibility

- The project has been updated for Xcode 27 while retaining iOS 18.6 as the minimum deployment target.
- Editable saves, organized documents, extracted pages, and personal templates repair Folik-created widgets into the canonical AcroForm field catalog when PDFKit omits them. Field values are synchronized without modifying encrypted files.
- Checkbox borders and flattened-export borders receive explicit drawing support where iOS 27 no longer reliably produces the prior PDFKit appearance.
- Folik-created field outlines remain visible in both Build and Fill, and now track scrolling, inertial deceleration, zoom, focus changes, and recycled PDF page tiles.
- Compatibility tests account for documented viewer-dependent PDFKit behavior while continuing to verify field names, values, widgets, editable exports, flattened exports, and signed/encrypted-document safeguards.

Final iOS 27 validation: 169 unit tests passed with one optional private fixture skipped, the Fill-mode outline UI regression passed, the focused iOS 26.5 compatibility check passed, and the unsigned Release build succeeded. The final simulator screenshot shows a complete field outline without focus or selection.

## Included usability polish

Sharing ends native form editing and waits for a confirmed save. A failed save keeps the in-memory edits available, prevents exporting an outdated copy, and offers retry through the save status. The export chooser identifies the filename and explains editable PDFs and flattened copies.

Sign is directly available in Forms and Annotations, using the existing local signature capture and reuse workflow. Pages contains a Contents switch; the reader has four main controls, with Forms placed earlier when fields exist. Scans retain access to form authoring.

OCR, compression, redaction, sanitizing, and fillable-copy previews have task-specific titles and filenames. OCR summarizes recognized/preserved pages, compression displays before/after sizes, and reviewed results use Save Copy. Add & Tools prioritizes Scan Document, Choose PDFs, and Images to PDF.

## Included optimizations

- **Library inventory:** startup, import completion, and returning to the library enumerate PDFs in a background task. Files with unchanged size and modification time reuse page metadata. Overlapping refreshes discard stale snapshots, unchanged document lists avoid republishing, and bulk delete/restore operations scan once after the batch. Initial loading has visible progress.
- **Thumbnails:** file-backed library and reader previews share a worker-owned PDFKit renderer and an in-memory cache, with a 32 MiB cost limit and 128-entry limit. Keys include file modification time, size, page, dimensions, and save revision. Visible view tasks cancel obsolete requests. Unsaved page-organizer drafts and unlocked encrypted documents retain their live-document preview path.
- **Annotation saves:** the reader combines edits within a 250 ms idle window into one staged write and atomic replacement. Explicit save, sharing, page organization, leaving the reader, and app deactivation still request a flush. Save status remains visible. This reduces repeated PDF serialization; serialization itself still runs with the live document on the main actor.
- **Sharing storage:** each export receives its own UUID directory while preserving a readable filename. Completed/dismissed share sheets schedule cleanup after a 60-second grace period. Launch cleanup removes owned exports older than 24 hours; original library documents and unrelated directories are excluded.
- **Search:** uncached PDFs are matched one page at a time. Cache-eligible text is retained up to 8 MiB per document and 48 MiB across the index; oversized documents continue matching without accumulating their text. Results retain matching-page counts and up to 50 lightweight excerpts per document, initially showing a compact subset that the user can expand, plus image-only/skipped-document reporting. The archive size is checked before reading its data. These are retained-text budgets, not a hard process-memory ceiling.

## Validation

- Full unit suite passed on iPhone 17 and iPad mini: 135 passed, one optional private-document fixture skipped, zero failures on each device.
- Eight focused iPhone UI tests passed: reader/form navigation, library grid, multi-document recovery, system sharing, matching-page search, page organization, bookmarks, and large-text rotation.
- Release simulator build passed for arm64 and x86_64. The built app and embedded share extension both report 1.0.4 (build 1).
- Regression tests caught stale thumbnail metadata after file replacement and a library visibility regression with damaged organization metadata; both were fixed and the suite rerun successfully.
- Dark-mode iPhone grid thumbnails and large-text reader/share screenshots were visually inspected. The first usability pass has additional iPhone 17e and light/dark coverage in [POLISH_NOTES.md](POLISH_NOTES.md).
- This initial optimization pass used simulator validation; subsequent physical-device checks are recorded below. Manual VoiceOver testing remains outstanding.

Artifacts: `/tmp/folik104-final-unit.xcresult`, `/tmp/folik104-iphone.xcresult`, `/tmp/folik104-ipad.xcresult`, `/tmp/folik104-release.log`, and `/tmp/folik104-iphone-images`.

Three focused iPad mini UI tests passed: grid layout and document tools, a dedicated PDF window, and large-text portrait/landscape reader and sharing layouts. Light-mode iPad grid and landscape screenshots were visually inspected; attachments are in `/tmp/folik104-ipad-images`. The final whitespace check passed.

The synthetic save benchmark uses a 150-page PDF and 30 ink strokes across three pages, including the final save and a check that all strokes survive reopening. Before optimization: 2,681 ms. Optimized iPhone runs: 94–96 ms; final iPad run: 95 ms. Rapid edits require one write instead of 30. Simulator measurements are illustrative and do not establish physical-device performance.

## Additional confidence and accessibility pass

- Unsaved changes use a save-before-back action. A failed save keeps the reader available for retry. Save requests receive a short iOS background execution allowance and retain the session through completion; this does not promise recovery after a crash, force-quit, or a background time limit.
- Staged replacement is now independently tested against a simulated full-disk error: original bytes remain intact, temporary staging files are removed, and retry persists the latest edits. Tests also cover requesting a save immediately before releasing the reader session.
- Find uses Command-F, Share uses Command-Shift-E, and the visible save action uses Command-S. Accessibility focus returns to the originating reader panel or export button after dismissal. Processing errors receive accessibility focus.
- OCR, compression, redaction, sanitizing, Office conversion, and image/text conversion share a consistent Cancel Processing control and an immediate Stopping state. Cancellation waits for the current non-interruptible PDFKit step where necessary. Conversion cancels its worker and removes a just-created copy on cancellation; export preparation can also be cancelled and cleans up its temporary copy.
- The empty library explains the open → sign → share workflow and retains direct Scan and Files actions.

Current simulator unit validation: 139 passed, one optional private-document fixture skipped. The strengthened scan benchmark uses 60 distinct image pages, about 14.2 MB, and verifies all 30 annotations after reopening; one measured simulator save took 217 ms. The existing 150-page text fixture took 99 ms in the same run. These measurements include rapid edits and the final write; neither is a physical-device result.

Automated accessibility semantics audits passed for the empty library and share chooser. Automated keyboard tests passed for Command-F and Command-Shift-E. The save-failure UI test confirms visible retry status, successful save-before-back, and the signature remaining after reopening. The initial recovery UI test used the wrong accessibility element type; querying the save button fixed the test.

Physical iPhone 17 Pro Max checks passed in a separate Folik Polish QA app with its own bundle identifier and no shared app-group access: simulated failed replacement/retry, the official IRS W-9 text/checkbox save/reopen/flatten workflow, and both save benchmarks. Final device timings were 87 ms for the 150-page text fixture and 105 ms for 60 distinct image pages (14.2 MB). These are Debug-build synthetic workload measurements, not universal timing guarantees. Results: `/tmp/folik104-device.xcresult` and `/tmp/folik104-device-final.xcresult`.

Review of the processing layouts found that progress controls could fall below the form viewport. Progress and cancellation now stay in the bottom action area for OCR/compression, sanitizing, and redaction. Manual VoiceOver traversal, physical keyboard feel, and interruption/actual low-storage behavior still need hands-on verification; the full-disk condition was injected in a test, not created by filling the phone.

Additional result bundles and logs use `/tmp/folik104-confidence-*`; device preparation uses `/tmp/folik104-device-qa` and `/tmp/folik104-device.log`.

The remaining manual steps are in [DEVICE_QA_1.0.4.md](DEVICE_QA_1.0.4.md).

Final additional-pass validation: 139 unit tests passed with one optional fixture skipped; 11 distinct UI workflows passed across the focused runs, including cancellation/retry on iPhone 17e and large-text rotation on iPhone 17. First-use and share semantics audits passed on both iPhone sizes. Recovery and processing-control screenshots were visually inspected in dark and light modes. The cancellation test now waits for the tool sheet and enabled Preview action before tapping; its initial immediate tap raced sheet presentation. The final Release simulator build and whitespace check passed. Test-only timing and failure switches are excluded from Release builds.

## Reader responsiveness and resource lifecycle pass

- Reader construction opens the PDF before discovering forms and annotations. Tool preparation runs in eight-page batches on the main actor, yielding between batches and supporting cancellation. A visible preparing indicator keeps editing disabled until the metadata is ready. Locked PDFs retain their existing unlock preparation path.
- Saving and form-value changes update already-discovered fields instead of scanning all pages again. Adding, removing, undoing, and redoing widget structure still refresh the field inventory.
- Memory warnings release the shared thumbnail cache and its renderer's retained document. Offscreen thumbnail views release their image reference. Search releases its in-memory archive on backgrounding or memory warning while preserving the reusable disk index.
- Detached file reads and preview renderers inherit the waiting screen's cancellation. Cancellation checks reject stale results around file reads; individual PDFKit and filesystem operations may still finish before cancellation takes effect.

The latest generated 150-page, 3,000-annotation simulator workload measured 3.34 ms for initial reader construction, 130.63 ms through complete preparation, and 7.07 ms for the longest eight-page metadata batch. The same run's synchronous path took 123.91 ms. These measure model preparation, not first-frame latency or a physical-device guarantee. See [PERFORMANCE_1.0.4.md](PERFORMANCE_1.0.4.md) for the workload, memory observations, and profiling limitations.

Final validation for this pass: 143 unit tests passed with one optional fixture skipped. After the final instrumentation and offscreen-image cleanup, all 15 focused release-regression tests and eight affected UI workflows passed: navigation, form authoring, save failure/retry, system sharing, library search, grid tools, password protection, and processing cancellation/retry. Release simulator build and whitespace validation passed; the app and embedded share extension both report 1.0.4 (build 1).

## Direct form builder entry

Make Fillable Copy opens an autosaved working copy directly in the editor with Forms ready. The redundant unchanged-PDF preview and upfront naming step are removed. Finish saves pending edits and offers a final name; name conflicts and save failures retain the editor for retry. The original PDF stays unchanged.

Validation: the source-preservation/save/rename regression and direct-entry/Finish UI test passed on iPhone 17e Simulator. Result: `/tmp/folik-form-entry.xcresult`.

## Build and Fill modes

Forms now separates field authoring and arrangement from signing, completion tracking, and next-field navigation. New fillable copies enter Build. Fill uses the actual PDF values, and its instructions explain that test entries are saved. Switching modes ends placement and layout selection without clearing data.

Validation: mode-switch value preservation, Build/Fill UI separation, and scanned form authoring/deletion passed on iPhone 17e Simulator. Both mode screenshots were reviewed. Result: `/tmp/folik-form-modes.xcresult`.

## Faster form placement

Build keeps field tools beside the page. Choose a type once and tap repeatedly, or use Place center. Arrange supports editing labels and required flags after placement, independent blank duplicates, and undo/redo. Field sizes are reused within the editing session. Dragged fields snap nearby matching edges and show alignment guides. Form layout supports page scrolling and pinch zoom; Fill keeps a clean stroke-only field outline without the Build-mode tint.

Validation: repeat placement, independent duplicates, required/label undo and redo, remembered sizes, save/reopen, and edge snapping passed unit checks. iPhone UI checks passed after fixing a largest-text landscape overflow. iPad placement, large-text rotation, and suggested-field zoom checks passed; screenshots reviewed. Results: `/tmp/folik-form-quick.xcresult`, `/tmp/folik-form-quick-fixed.xcresult`, `/tmp/folik-form-quick-ipad.xcresult`.

## Optional sample form

Try a Sample Form is available in the empty library and Add tools. It creates a local practice PDF and opens Fill with text, multiline, and checkbox fields plus guidance for signing and sharing. Each request creates a fresh blank copy without changing prior samples. No sample is inserted automatically and no network access is needed.

Validation for this form workflow pass: 148 unique unit tests passed across the full regression and focused correction runs, with one optional private fixture skipped. Eight affected iPhone UI workflows passed; iPad placement, suggestions/zoom, large-text rotation, and dark-mode sample/builder checks also passed. The original sample generator exposed missing untouched fields in PDFKit's form catalog. The final bundled sample has four independent canonical fields; native save/reopen tests verify all field names plus text and checkbox values, and pypdf independently verifies the asset's field/widget values and normal appearances. The final blank page render was visually reviewed.

Results: `/tmp/folik-forms-regression.xcresult` (the sample structure failure before correction), `/tmp/folik-sample-bundled.xcresult` (final sample regression), `/tmp/folik-form-dark-ipad.xcresult`, and `/tmp/folik-form-release-bundled.log`. New form workflows are simulator-validated; physical VoiceOver and touch testing remain in the device QA checklist.

## Offline form templates

- Added bundled Work Order, Inspection Checklist, Meeting Notes, Expense Report, Weekly Timesheet, Project Brief, and Inventory Count forms. Open Form Templates from Add & Tools or the empty library, preview a form, and choose Start Form to open a fresh fillable copy.
- Blank masters remain in the app bundle; each use imports an independent PDF through the existing collision-safe library importer. No network or account is required. Build mode can customize the new copy.
- Added a reproducible ReportLab generator under `Tools/create_form_templates.py`; the seven assets total about 95 KiB and add no app runtime dependency.
- Validation: iPhone preview/start UI and initial template persistence passed in `/tmp/folik-templates-tests.xcresult`. iPad preview/start passed in `/tmp/folik-templates-ipad.xcresult`; corrected a test selector that tapped a background control, then gallery navigation and expanded single-line, multiline, and checkbox persistence passed in `/tmp/folik-templates-ipad-final.xcresult`. Tests verify canonical AcroForm values after saving, fresh blank copies, unique destinations, and unchanged masters. Inspected blank and filled page renders for the original templates.
- Release simulator build passed (`/tmp/folik-templates-release.log`), and the original bundled assets match the source PDFs. Physical-device airplane-mode and VoiceOver checks remain in the device QA checklist.
- Final iPhone regression checks passed for the populated-library template gallery and the existing sample signing/sharing flow (`/tmp/folik-templates-regression.xcresult`).
- Expansion validation covers all seven bundled templates. An independent pypdf audit found matching canonical fields and page widgets, nonempty normal appearances, and blank starting values in every file. The four new pages were rendered with Poppler and visually inspected; the populated-library gallery test passed on iOS 27 iPhone 17e and iPad mini simulators, and all five template unit tests passed.

## My Templates

Forms now offers Save as My Template with cleared answers or retained defaults. Personal masters live separately from working documents, support multipage previews, and can be deleted without removing library copies. Source page content and drawn annotations remain; digitally signed inputs require an unsigned original. Template names use collision-safe suffixes.

Validation: save UI and bundled-template regression passed in `/tmp/folik-personal-tests2.xcresult`; after correcting widget subtype matching, canonical blank/default text and checkbox values, restart discovery, source preservation, and independent copies passed in `/tmp/folik-personal-final.xcresult`.

## On-page field suggestion review

Review proposed fields on a zoomable, disposable PDF copy, toggle inclusion by tapping a box or its list control, and edit labels/types before applying. Page navigation covers multipage suggestions. Preview annotations never enter the working document.

Validation: the scan → suggest → preview/zoom → edit → add UI flow passed on iPhone and iPad (`/tmp/folik-suggestions-tests.xcresult`, `/tmp/folik-suggestions-final.xcresult`). Field inference and standard-widget/source-preservation unit tests passed in the latter. Inspected iPhone preview rendering and moved selection controls out of the crowded navigation bar.

## Bulk form layout and filling order

Build → Layout tools now aligns selected fields, matches width/height/size, and distributes spacing within one page. Changes stay within page bounds and are grouped into one undo action. Filling order has accessible earlier/later controls and persists as Folik-specific PDF annotation metadata; required unfinished fields retain priority and external readers may use their own order.

Validation: bulk geometry, batch undo/redo, spacing, matching size, preserved values, saved/reopened filling order, and the layout/order UI flow passed in `/tmp/folik-layout-final.xcresult` on iPhone.

## Contextual next actions

New scans show dismissible next actions: add form fields on a working copy, find recognized text, or make the scan searchable when the current page has no text. Finishing a form opens Fill immediately. Returning to the library clears the scan-action launch context.

Validation: finish-to-Fill passed in `/tmp/folik-next-actions.xcresult`; scan-to-builder passed after fixing inherited accessibility identifiers in `/tmp/folik-next-final.xcresult`. Scan actions have at least 44-point label targets.

## Sharing clarity and export previews

Sharing now describes editable versus flattened copies in plain language. Either can be shared directly or previewed page by page before sharing the exact prepared file. Previews load from the temporary export URL to avoid another full in-memory byte copy. Leaving an unshared preview removes the temporary export. Unanswered required fields offer a non-blocking return-to-field action.

Validation: direct sharing, editable/flattened output preservation, and export cleanup passed in `/tmp/folik-share-tests.xcresult`. Expanded the sharing sheet after UI checks found lower options offscreen; preview sharing, both choices, and required-field review passed in `/tmp/folik-share-final.xcresult`.

## Final five-feature regression

`/tmp/folik-five-features-final.xcresult`: 156 passed (151 unit tests and five iPad UI tests), zero failures, one optional private-document fixture test skipped. The iPad checks cover personal-template saving, layout/fill order, suggested-field preview/editing, export preview sharing, and first-use/share accessibility semantics. Inspected iPhone and iPad screenshots. Release simulator build passed in `/tmp/folik-five-features-release.log`; bundle version remains 1.0.4. Physical VoiceOver, keyboard, interruption, rotated-page, and cross-viewer checks remain in the device QA checklist and are not marked complete by simulator results.

## Signature placement correction

- Handwritten signatures and initials now render inside the annotation centered on the tapped page point. Previously, stroke coordinates included the page offset twice, which could displace or hide the signature.
- Moving and resizing ink annotations now preserve local stroke coordinates, including undo and redo. Existing saved signature assets can be reused; already misplaced annotations should be deleted and placed again.
- The regression test compares rendered pixels after saving and reopening a plain PDF and the bundled sample form, covering placement, movement, resizing, undo, and redo for both signatures and initials. The initial test reproduced the bug before the fix.
- Validation: all 38 DocumentSessionTests passed on the iPhone 17e simulator; artifact `/tmp/folik-signature-verified.xcresult`. Physical-device retesting remains pending.

## Placement and form editing interaction pass

- The resize handle follows the visible bottom-right corner on rotated PDFs, keeping the opposite corner anchored. Dragging now uses the final finger position when ending the gesture.
- Native gesture-handler regression coverage uses real PDFView coordinate conversion on page two, with nonzero crop origins, 0/90/180/270-degree rotations, and two zoom levels. It covers field placement, resizing, and undo. The test failed before the correction.
- All 39 interaction and document-session tests passed on iPhone 17e simulator (`/tmp/folik-interaction-resize.xcresult`).

- On-page selection no longer issues a navigation command, preserving the current viewport. Selection outlines and resize handles refresh during PDFView layout changes, including zoom and scrolling layout updates.
- Native regression coverage also checks text boxes, stamps, handwritten signatures, final movement events, cancelled drags, and undo across all page rotations. Selection-jump and stale-outline tests reproduced both issues before the fix.
- Final validation: 41 native interaction/document-session tests passed on both iPhone 17e and iPad mini simulators. Actual tap-and-drag UI tests passed on both, verifying movement through the existing accessible position description, undo, zoom, and opening field properties. Two additional iPad UI tests passed for field properties/duplication and large text/device rotation.
- Artifacts: `/tmp/folik-touch-iphone.xcresult`, `/tmp/folik-touch-ipad.xcresult`, and `/tmp/folik-touch-ipad-final.xcresult`. The first iPad run exposed an overly strict percentage-movement assertion; after correcting that device-size assumption, the focused UI rerun passed. Phone and tablet drag/zoom screenshots were visually checked. Physical-device touch and VoiceOver verification remain pending.

## Visible borders for added form fields

- New Folik fields now store PDF widget appearance characteristics, including a border color, so their outlines remain visible in Fill mode without tapping or selecting them. The builder overlay had previously hidden the missing saved border.
- Text, paragraph, date, and checkbox fields use the widget /MK appearance. Signature fields supply a drawn border appearance because PDFKit does not render their /MK border by itself. These appearances persist when saving and flattening. Existing fields from the source PDF retain their original styling. Automatic repair for older Folik fields is described below.
- Validation: 45 focused form, template, editing, interaction, and UI tests passed on iPhone 17e simulator (`/tmp/folik-borders-final.xcresult`). The regression test adds each field type to the bundled existing sample form, verifies all four rendered border sides after reopening and flattening, and checks that original field names remain. Fill-mode screenshot visually verified with no active selection. Physical-device retesting remains pending.

## Repair older Folik field borders

- Opening an eligible older form restores missing borders on Folik-created fields, including fields from before the FolikFieldKind metadata was introduced. Values, defaults, labels, flags, field order, and geometry are retained. Cached blank appearances are regenerated, and signature widgets receive a persistent border drawing.
- Only visible, printable, editable fields carrying Folik’s authoring marker and missing a border color qualify. External fields, custom border styling, restricted documents, and signed documents are preserved. The signature check reads the original PDF bytes before any rewrite.
- Repairs use the existing atomic save and retry path. A failed save leaves the original file intact and keeps the repaired document available for retry. Subsequent openings do not rewrite already repaired files.
- Validation: full iPhone 17e unit suite passed, 161 tests with one optional private-fixture test skipped (`/tmp/folik-repair-verified.xcresult`). All nine repair and interaction tests passed on iPad mini (`/tmp/folik-repair-ipad.xcresult`). Coverage includes rendered border sides after reopen/flatten, preserved existing answers and metadata, older authoring markers, custom styling/read-only exclusions, a structurally signed fixture, deferred preparation, and failed-save retry. Physical-device retesting remains pending.

## Flattened export appearance

- Flattened copies draw each visible annotation once. This avoids darker translucent annotations and prevents the extra drawing pass from rendering hidden annotations.
- Each output page uses its visible crop, including crop offsets and page rotation, with the correct per-page dimensions. The source and editable copy stay byte-for-byte unchanged.
- Rendered comparisons reproduce the old failures and pass after the fix across full pages, cropped pages, and all four rotations. The focused export/interaction/document-session suite passed on iPhone 17e (`/tmp/folik-export-after.xcresult`).

## Background save and reopen verification

- A native UI regression enters a field value through the on-screen keyboard, backgrounds the app with the editor active, terminates after the background-save interval, and reopens the document from the library. Both the field answer and existing signature survive. This passed on iPhone 17e and iPad mini simulators; no save-path code change was needed.
- Failed-save/back-navigation recovery and flattened-preview-to-share UI tests passed on iPhone. The rendered export comparison also passed on iPad. This verifies these workflows, not force-quitting in the middle of a write.
- Validation artifacts: 48 focused native tests passed in `/tmp/folik-export-after.xcresult`; recovery and sharing checks are in `/tmp/folik-save-export-ui.xcresult`; the completed background test passed in `/tmp/folik-background-verified.xcresult`; iPad export and background checks passed in `/tmp/folik-save-export-ipad.xcresult`. Initial background-test failures were automation issues (PDFKit keyboard-focus exposure and the debug auto-open shortcut); the final test uses actual keyboard taps and library navigation. The reopened field/signature screenshot was visually verified.
- Physical-device and cross-viewer checks in Preview, Files, and Acrobat remain outstanding.


## Keep authored fields in the PDF form catalog

- Added and reattached fields now register with PDFKit after attachment to a page. This prevents blank fields, unsigned signature fields, and repaired fields from disappearing from the exported AcroForm catalog while remaining visible on the page. The same registration runs for duplication, suggested fields, and undo/redo insertion.
- Text and checkbox registration retains the existing value. Folik's empty signature widgets register without creating a signature value; digitally signed fields are excluded from that workaround.
- Regression coverage verifies catalog names before filling, saved text/checkbox answers after exporting, and original answers after border repair. Existing border, metadata, signed-document exclusion, placement, and save-failure checks still pass. The original compatibility test reproduced the missing signature entry; independent inspection also reproduced missing repaired text fields.
- Full iPhone native suite: 163 passed, one optional private-fixture test skipped, zero failures (`/tmp/folik-catalog-verified.xcresult`). All 12 focused form/template/interaction tests also passed on iPad mini (`/tmp/folik-catalog-ipad.xcresult`).
- `Tools/check_export_compatibility.py` audits extracted XCTest PDF attachments with pypdf and renders them with PDFium. Nine fixtures passed value agreement, nonempty appearances, unsigned-signature state, and flattened-form removal checks. Editable and flattened previews were visually inspected: answers and borders are present; PDFium's interactive appearance regeneration changes fonts and checkmarks compared with the flattened appearance.
- Remaining limitation: PDFKit emits separate, unlinked same-name catalog and page-widget objects even after registration (also seen in existing personal-template output). Values agree in the audited fixtures, but this does not verify correct round-trip editing in other viewers. No PDF object rewriting was introduced. Acrobat, Files, Preview editing, and physical-device checks remain pending; this pass does not claim complete cross-viewer compatibility.


## External-editor round-trip regression

- Verified a Folik editable export through PDFium's actual form event APIs: replace an original text answer, replace a Folik-added text answer, and uncheck an original checkbox. The generated fixture intentionally retains PDFium's updated catalog values alongside the older page-widget values.
- Folik/PDFKit resolves the updated answers correctly when opening this file. A new native regression checks both text answers, checkbox state, unchanged source bytes on open, another edit in Folik, all nine catalog fields after saving, and editable/flattened export. No app behavior change was necessary for this case.
- Reproduction: export the FormTemplateTests attachments with xcresulttool, then run `python Tools/create_pdfium_roundtrip_fixture.py ATTACHMENTS OUTPUT.pdf` using pypdfium2 and pypdf. The checked-in `FolikTests/Fixtures/PDFiumRoundTrip.pdf` is synthetic, derived from Folik's bundled practice form, and was generated with PDFium through pypdfium2 5.13.0. It contains no user document data.
- Validation: all four FormTemplateTests passed on iPhone (`/tmp/folik-roundtrip.xcresult`); the new round-trip test passed on iPad (`/tmp/folik-roundtrip-ipad.xcresult`). The independent export audit passed all six extracted PDF fixtures and specifically checked returned round-trip answers. Folik's reopened preview and PDFium's editable/flattened output were visually inspected.
- Scope: this verifies PDFium form editing followed by Folik open/edit/save and PDFium rendering of returned exports. It does not establish Acrobat, Preview, or Files editing behavior. Separate catalog/widget objects and viewer-dependent font/checkmark appearance remain documented limitations.

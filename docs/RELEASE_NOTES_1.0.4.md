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

Free, private, and on your device.

## Included usability polish

Sharing ends native form editing and waits for a confirmed save. A failed save keeps the in-memory edits available, prevents exporting an outdated copy, and offers retry through the save status. The export chooser identifies the filename and explains editable PDFs and flattened copies.

Sign is directly available in Forms and Annotations, using the existing local signature capture and reuse workflow. Pages contains a Contents switch; the reader has four main controls, with Forms placed earlier when fields exist. Scans retain access to form authoring.

OCR, compression, redaction, sanitizing, and fillable-copy previews have task-specific titles and filenames. OCR summarizes recognized/preserved pages, compression displays before/after sizes, and reviewed results use Save Copy. Add & Tools prioritizes Scan Document, Choose PDFs, and Images to PDF.

## Included optimizations

- **Library inventory:** startup, import completion, and returning to the library enumerate PDFs in a background task. Files with unchanged size and modification time reuse page metadata. Overlapping refreshes discard stale snapshots, unchanged document lists avoid republishing, and bulk delete/restore operations scan once after the batch. Initial loading has visible progress.
- **Thumbnails:** file-backed library and reader previews share a worker-owned PDFKit renderer and an in-memory cache, with a 32 MiB cost limit and 128-entry limit. Keys include file modification time, size, page, dimensions, and save revision. Visible view tasks cancel obsolete requests. Unsaved page-organizer drafts and unlocked encrypted documents retain their live-document preview path.
- **Annotation saves:** the reader combines edits within a 250 ms idle window into one staged write and atomic replacement. Explicit save, sharing, page organization, leaving the reader, and app deactivation still request a flush. Save status remains visible. This reduces repeated PDF serialization; serialization itself still runs with the live document on the main actor.
- **Sharing storage:** each export receives its own UUID directory while preserving a readable filename. Completed/dismissed share sheets schedule cleanup after a 60-second grace period. Launch cleanup removes owned exports older than 24 hours; original library documents and unrelated directories are excluded.
- **Search:** uncached PDFs are matched one page at a time. Cache-eligible text is retained up to 8 MiB per document and 48 MiB across the index; oversized documents continue matching without accumulating their text. Results retain matching-page counts, up to three excerpts, and image-only/skipped-document reporting. The archive size is checked before reading its data. These are retained-text budgets, not a hard process-memory ceiling.

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

Build keeps field tools beside the page. Choose a type once and tap repeatedly, or use Place center. Arrange supports editing labels and required flags after placement, independent blank duplicates, and undo/redo. Field sizes are reused within the editing session. Dragged fields snap nearby matching edges and show alignment guides. Form layout supports page scrolling and pinch zoom; Fill hides the authoring outlines.

Validation: repeat placement, independent duplicates, required/label undo and redo, remembered sizes, save/reopen, and edge snapping passed unit checks. iPhone UI checks passed after fixing a largest-text landscape overflow. iPad placement, large-text rotation, and suggested-field zoom checks passed; screenshots reviewed. Results: `/tmp/folik-form-quick.xcresult`, `/tmp/folik-form-quick-fixed.xcresult`, `/tmp/folik-form-quick-ipad.xcresult`.

## Optional sample form

Try a Sample Form is available in the empty library and Add tools. It creates a local practice PDF and opens Fill with text, multiline, and checkbox fields plus guidance for signing and sharing. Each request creates a fresh blank copy without changing prior samples. No sample is inserted automatically and no network access is needed.

Validation for this form workflow pass: 148 unique unit tests passed across the full regression and focused correction runs, with one optional private fixture skipped. Eight affected iPhone UI workflows passed; iPad placement, suggestions/zoom, large-text rotation, and dark-mode sample/builder checks also passed. The original sample generator exposed missing untouched fields in PDFKit's form catalog. The final bundled sample has four independent canonical fields; native save/reopen tests verify all field names plus text and checkbox values, and pypdf independently verifies the asset's field/widget values and normal appearances. The final blank page render was visually reviewed.

Results: `/tmp/folik-forms-regression.xcresult` (the sample structure failure before correction), `/tmp/folik-sample-bundled.xcresult` (final sample regression), `/tmp/folik-form-dark-ipad.xcresult`, and `/tmp/folik-form-release-bundled.log`. New form workflows are simulator-validated; physical VoiceOver and touch testing remain in the device QA checklist.

## Offline form templates

- Added bundled Work Order, Inspection Checklist, and Meeting Notes forms. Open Form Templates from Add & Tools or the empty library, preview a form, and choose Start Form to open a fresh fillable copy.
- Blank masters remain in the app bundle; each use imports an independent PDF through the existing collision-safe library importer. No network or account is required. Build mode can customize the new copy.
- Added a reproducible ReportLab generator under `Tools/create_form_templates.py`; the three assets total about 36 KB and add no app runtime dependency.
- Validation: iPhone preview/start UI and initial template persistence passed in `/tmp/folik-templates-tests.xcresult`. iPad preview/start passed in `/tmp/folik-templates-ipad.xcresult`; corrected a test selector that tapped a background control, then gallery navigation and expanded single-line, multiline, and checkbox persistence passed in `/tmp/folik-templates-ipad-final.xcresult`. Tests verify canonical AcroForm values after saving, fresh blank copies, unique destinations, and unchanged masters. Inspected blank and filled page renders for all three templates.
- Release simulator build passed (`/tmp/folik-templates-release.log`), and all three bundled assets match the source PDFs. Physical-device airplane-mode and VoiceOver checks remain in the device QA checklist.
- Final iPhone regression checks passed for the populated-library template gallery and the existing sample signing/sharing flow (`/tmp/folik-templates-regression.xcresult`).

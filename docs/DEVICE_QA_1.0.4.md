# FolikPDF 1.0.4 — hands-on checks

Automated simulator tests and targeted iPhone 17 Pro Max tests have run. These remaining checks require a person using VoiceOver, a keyboard, and normal device interruption workflows. They are not marked complete by the automated accessibility semantics audit.

Use the separately installed **Folik Polish QA** app for exploratory device checks. It uses `com.x3nllc.Folik.PolishQA`, separate document storage, and no shared app-group access. Import expendable copies through Files. The QA app is a development build; the shipping project retains its normal bundle identifier and version 1.0.4.

1. Turn on VoiceOver. From the empty library, locate Scan and Choose PDFs. Open a PDF, traverse Pages/Find/Forms/Annotations, and verify that labels, selected state, and reading order make sense aloud.
2. Open and dismiss each reader panel and the share chooser. Check that focus returns to the control you used. Trigger a processing error with an unreadable test PDF and confirm that its message is announced and retry controls are reachable.
3. Connect a keyboard. Try Command-F, Command-Shift-E, and Command-S when the save action is visible. Fill a text field and verify that Tab moves predictably between fields and that saving commits the active field.
4. Add an annotation and immediately tap Back. Reopen the PDF and confirm the annotation remains. Repeat while editing a native form field, then with the Home gesture, app switching, and device locking. Reopen and check the exact latest values.
5. Use a large scan for OCR/compression. Ensure progress and Cancel Processing remain visible at large text sizes and in landscape. Cancel, wait for the current step to finish, and retry. Confirm no cancelled copy appears in the library. Cancel export preparation and then share again.
6. Observe a real document you regularly use for scrolling, thumbnail rendering, form entry, and saving. Record its page count/file size, device/build, and any visible pause without adding its private contents to the repository.

## Workflow finishing checks

- Search for text that appears on several pages, expand and collapse the matching pages, activate early and later excerpts with touch and VoiceOver, and confirm the reader opens the stated page with Find still populated.
- Duplicate, favorite, delete, restore, rename, and organize documents. Confirm feedback is announced once, Undo restores the exact prior state where offered, undoing a duplicate does not add it to Recently Deleted, and the banner does not cover essential controls at large text sizes.
- Enable Reduce Motion and repeat a reversible library action. Confirm the feedback fades without sliding and remains understandable through VoiceOver.
- Change a page-organizer draft and a Batch to PDF draft, then try Cancel and an interactive sheet dismissal. Confirm each offers Keep Editing and a destructive discard action; unchanged drafts should close without a warning.
- At the largest accessibility text size, traverse reader, inspector, form-builder, and page-organizer controls in portrait and landscape. Confirm compact toolbars scroll and no required action is clipped.
- Open several different entries in Add & Tools, reopen it, and verify Recent reflects the last three distinct tools without making the grouped list harder to navigate.
- In Build, place and select fields on iPhone and iPad. Confirm the guidance is understandable, haptics are restrained, and Edit/Duplicate remain reachable in portrait, landscape, and large text.
- Preview modified, added, and removed comparison pages. Check the compact Original/Revised switch, iPad side-by-side layout, and VoiceOver descriptions.
- Verify bundled and personal template thumbnails, then rename a personal template with touch and VoiceOver. Reopen it and confirm its PDF is unchanged.
- Open Settings → Using Folik and check reading order, terminology, Dynamic Type layout, and Back navigation.

Do not treat the injected full-disk test as a real low-storage device test. It confirms original-byte preservation, staging cleanup, retained edits, and retry after a failed replacement. Neither the background execution allowance nor the Back safeguard guarantees recovery after force-quitting, a crash, or iOS ending the process.

## Completed device checks

On iPhone 17 Pro Max, a separate QA app passed simulated replacement failure/retry and the official IRS W-9 text/checkbox save/reopen/flatten test. Final Debug-build save measurements were approximately 87 ms for a 150-page text PDF with 30 strokes, and 105 ms for a 60-page synthetic image PDF of 14.2 MB with 30 strokes. Every stroke was checked after reopening. These do not establish a timing bound for arbitrary PDFs.

Artifacts: `/tmp/folik104-device.xcresult`, `/tmp/folik104-device-final.xcresult`.

## Additional optimization profiling

The reader batching, form-value refresh, cache release, and detached-worker cancellation pass has simulator coverage. Instruments reported the physical iPhone offline during this pass; the earlier device save results above predate these changes. Reinstall the latest isolated QA build before checking them on the phone. Capture Allocations and Time Profiler while opening an annotation-heavy PDF, filling/saving a large form, and running OCR on a real scan. Compare peak allocations and main-thread pauses with the prior build. See [PERFORMANCE_1.0.4.md](PERFORMANCE_1.0.4.md) for measured simulator results and limitations.

## New form workflow checks

The direct builder, Build/Fill modes, repeated placement, properties, duplication, and sample flow have simulator coverage. On a physical iPhone and iPad, create a five-field form using only touch, then repeat using VoiceOver and Place center/Move/Size controls. Check dragging and snapping near page edges at different zoom levels. Switch to Fill, enter distinct values, finish naming, reopen, and share to another PDF reader. Confirm field independence, required flags, and checkbox states. Verify an interrupted working copy remains in the library and the source is unchanged. Try the optional sample from an empty library, fill it, sign on the line, and share it. These hands-on checks are not yet marked complete.

### Offline template library — physical-device follow-up

- In airplane mode, open Form Templates from both an empty library and Add & Tools. Preview all three templates and start each one.
- Fill single-line and multiline text, check a box, close and reopen, and export. Confirm values remain editable in the exported PDF.
- Start the same template again; confirm it is blank and the previously filled copy is unchanged.
- With VoiceOver and larger text, confirm template descriptions, Back, and Start Form remain accessible. Check iPad split view and landscape.

### Personal templates

Save a multipage form both with cleared answers and retained defaults. Restart the app, preview every page, start two copies, and confirm their values are independent. Check saved choices/radio groups in another PDF viewer, template deletion, long names, and VoiceOver access to save options. Page artwork and drawn signatures are retained by design; inspect the save explanation.

### On-page suggestion review

On a rotated, cropped, multipage scan, pinch and pan the preview and toggle boxes by touch. Confirm list selection matches each box, edit a label/type, cancel without changes, then repeat and add only selected fields. Verify VoiceOver can perform the same review through the list controls.

### Bulk form layout and filling order

Select mixed-size fields, align and distribute them, undo/redo, then reopen to check geometry and answers. Try page edges and rotated pages. Change fill order across multiple pages with both touch and VoiceOver controls; verify required-field priority and preservation after saving. Other readers may ignore Folik’s filling-order metadata.

### Contextual next actions

Scan a page with recognizable text and one without. Check the relevant Find text/Make searchable action, create a fillable copy from the scan banner, and finish into Fill mode. Dismiss the banner and return to the library; normal document reopening should remain unobstructed.

### Sharing preview and required fields

Edit the currently focused field, open sharing, and check both export previews against the latest value. Navigate pages, cancel an unfinished preview, retry, and share to a second PDF viewer. Review an unanswered required field from the sharing reminder. Check VoiceOver focus after preview cancellation and the system share sheet, plus large text and iPad split view.

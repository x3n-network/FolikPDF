# FolikPDF 1.0.4 — hands-on checks

Automated simulator tests and targeted iPhone 17 Pro Max tests have run. These remaining checks require a person using VoiceOver, a keyboard, and normal device interruption workflows. They are not marked complete by the automated accessibility semantics audit.

Use the separately installed **Folik Polish QA** app for exploratory device checks. It uses `com.x3nllc.Folik.PolishQA`, separate document storage, and no shared app-group access. Import expendable copies through Files. The QA app is a development build; the shipping project retains its normal bundle identifier and version 1.0.4.

1. Turn on VoiceOver. From the empty library, locate Scan and Choose PDFs. Open a PDF, traverse Pages/Find/Forms/Annotations, and verify that labels, selected state, and reading order make sense aloud.
2. Open and dismiss each reader panel and the share chooser. Check that focus returns to the control you used. Trigger a processing error with an unreadable test PDF and confirm that its message is announced and retry controls are reachable.
3. Connect a keyboard. Try Command-F, Command-Shift-E, and Command-S when the save action is visible. Fill a text field and verify that Tab moves predictably between fields and that saving commits the active field.
4. Add an annotation and immediately tap Back. Reopen the PDF and confirm the annotation remains. Repeat while editing a native form field, then with the Home gesture, app switching, and device locking. Reopen and check the exact latest values.
5. Use a large scan for OCR/compression. Ensure progress and Cancel Processing remain visible at large text sizes and in landscape. Cancel, wait for the current step to finish, and retry. Confirm no cancelled copy appears in the library. Cancel export preparation and then share again.
6. Observe a real document you regularly use for scrolling, thumbnail rendering, form entry, and saving. Record its page count/file size, device/build, and any visible pause without adding its private contents to the repository.

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

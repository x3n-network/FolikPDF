# FolikPDF 1.0.4 performance measurements

## Scope and reproducibility

Debug builds, generated expendable PDFs, iPhone 17 simulator. The opt-in `PerformanceProbe` generates a 150-page PDF with 20 square annotations on every page, then a 12-page scanned-text PDF for OCR. It measures document model setup, preparation batches, OCR duration, and process physical-footprint samples between OCR pages. Fixtures are removed after the workload. The probe is excluded from Release builds.

Run `FolikTests/Release104Tests/testOpeningAndOCRPerformanceProbe` serially to reproduce the test. Debug launch argument `--profile-memory` runs the same workload after a five-second delay and writes `Documents/PerformanceReport.json`. Only use that launch argument with the isolated Folik Polish QA app when profiling a device. It has its own bundle identifier and no app-group entitlements.

## Observations

| Measurement | Before this pass | Latest validation |
| --- | ---: | ---: |
| Synchronous session construction | 141.09 ms | 123.91 ms |
| Production reader initial construction | Synchronous path above | 3.34 ms |
| Reader construction plus full tool preparation | Synchronous path above | 130.63 ms |
| Metadata preparation batches | One synchronous scan | 19 batches, at most 8 pages each |
| Longest metadata batch | Not separately measured | 7.07 ms |
| Discovered annotations | 3,000 | 3,000 |
| OCR duration, 12 pages | 8.94 s | 8.90 s |
| Physical footprint sampled between OCR pages | 36.75–40.08 MiB | 36.58–39.85 MiB |

Single-run figures are illustrative. Initial PDF opening and live PDFKit metadata access remain on the main actor. Yielding reduces uninterrupted work; it does not eliminate total preparation time, guarantee a frame budget, or measure actual first paint. Very complex individual pages and outline processing can still take longer. Editing stays disabled until preparation completes. Encrypted-document unlocking still prepares synchronously.

The OCR samples are taken between pages, not during rendering or recognition; they do **not** establish peak memory. They showed no substantial accumulation across this generated workload, so this pass did not rewrite OCR or claim an OCR speedup. Allocator reuse, simulator conditions, and earlier tests affect footprint measurements. A cold, repeated physical-device comparison is still needed before claiming peak-memory improvements.

## Resource and save changes

Memory pressure purges the shared thumbnail cache and its retained PDF document; disappeared thumbnail views drop their own image reference. Search can discard its retained archive while keeping the on-disk index. A regression verifies the next search returns the same matches without deleting that disk index.

Form-value refreshes reuse discovered field records. Structural edits still rescan the field inventory, including widget deletion and undo/redo. This avoids repeated full-document scans around ordinary saves. PDF serialization itself remains synchronous on the live document's main actor; this pass does not claim removal of all save pauses.

Cancellation propagates from waiting tool tasks into detached workers. File reads check cancellation before and after access; a non-interruptible PDFKit or filesystem operation can finish first. Existing processing cancellation/retry behavior is retained.

## Validation and profiler limitations

The full unit run executed 144 tests: 143 passed and one optional private-document fixture skipped, with no failures. A subsequent focused run passed all 15 release-regression tests, including the final batch instrumentation. The final Release simulator build also passed. Widget deletion regression failures found during development were fixed before the successful full run.

Instruments listed the physical iPhone as offline. Simulator Allocations/Time Profiler launch attempts failed or stalled with the app suspended; those attempts produced no usable peak-memory result and were stopped. Do not treat their trace directories as completed profiles. Device allocation peaks, real-document scrolling, and save-pause profiling remain hands-on follow-up work.

Artifacts: `/tmp/folik104-memory-baseline-serial.log`, `/tmp/folik104-memory-final-unit.xcresult`, `/tmp/folik104-optimization-ui.xcresult`. Temporary artifacts are local and may be cleaned up by the OS; the methodology and observations are recorded here durably.

Final validation for this pass: 143 unit tests passed with one optional fixture skipped. After the final instrumentation and offscreen-image cleanup, all 15 focused release-regression tests and eight affected UI workflows passed: navigation, form authoring, save failure/retry, system sharing, library search, grid tools, password protection, and processing cancellation/retry. Release simulator build and whitespace validation passed; the app and embedded share extension both report 1.0.4 (build 1).

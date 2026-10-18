# Document-opening transition fix

Baseline: clean `0ff08a4` on `feat/duo-adaptive-reader`. Development fix only; no push, release, archive, signing change, or version bump.

## Changes

- Keep the Library under the same searchable navigation root when its first PDF arrives. The former empty/nonempty wrapper branches replaced LibraryView's state during the push; a DEBUG identity probe and native regression reproduce that replacement.
- Keep Add Document's native Label unchanged while importing, and disable the button as before. Replacing its label with a bare ProgressView caused the Duo native glass toolbar to show an oversized empty rounded shape during the transition. Existing library status feedback still reports import progress.
- Samples and template copies open the PDF first, with Fill available explicitly. The existing deliberate Finish Form → Fill workflow is preserved.
- Reset adaptive UI-test orientation before each test. An earlier accessibility test left the ordinary phone in landscape, causing the compact-only viewport continuity test to find a valid companion instead of its expected sheet. No production layout change was made to accommodate that test.

## Verification

All paths below are under `/Users/josephspears/.hermes/cache/scratch/`.

- `folik-opening-red.xcresult`: expected native failure for automatic Forms presentation.
- `folik-opening-identity-red2.xcresult`: expected native identity mismatch after creating the first sample. The earlier identity-red bundle was a selector diagnostic, not behavior RED.
- `folik-opening-toolbar-red.xcresult`: expected native failure: the importing Add Document button lost its accessible label.
- `folik-opening-duo-final2.xcresult`: **4 passed, 0 failures**, actual iPhone Duo simulator, iOS 27.1. Covers sample opening, explicit Fill/dismiss, retained Library identity, stable importing toolbar label/bounds, and ordinary document-first opening.
- `folik-opening-phone-final2.xcresult`: **193 passed, 1 optional-fixture skip, 0 failures**, iPhone 18 Pro, iOS 27.0. Entire unit target (180 passed, 1 optional-private-files skip) plus 13 focused native UI tests for the changed opening paths, save/share, templates, builder completion, search, deletion/restore, accessibility, and PDF viewport continuity.
- `folik-opening-release-final2.log`: Release simulator build passed, code signing disabled only for that build command.
- `folik-opening-stable-toolbar.mp4`: explicit-display native recording of the fixed sample opening and subsequent explicit Fill. `folik-opening-toolbar-transition-30fps.png` inspects the opening at 30 sampled frames/second. The earlier stable-root-only recording still contains a brief toolbar bubble and is diagnostic, not final visual acceptance.
- `folik-opening-phone-green.xcresult` retains the orientation-contaminated failure; final/final2 supersede it after the test setup correction.

[Initial reader on the real Duo simulator](evidence/duo-reader/opening-document-first.png). This is native simulator evidence, not physical-device or live-fold acceptance. No new open/partial hinge-pose coverage is claimed. Full unfiltered UI regression was not run.

## Reproduce focused Duo acceptance

```sh
xcodebuild test -project Folik.xcodeproj -scheme Folik \
  -destination 'platform=iOS Simulator,id=6E5B90AF-348A-423B-B4AF-5CDD48D3B79B' \
  -derivedDataPath /Users/josephspears/.hermes/cache/scratch/folik-opening-build \
  -resultBundlePath /Users/josephspears/.hermes/cache/scratch/folik-opening-rerun.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:FolikUITests/AdaptiveReaderUITests/testFirstSamplePreservesLibraryNavigationIdentity \
  -only-testing:FolikUITests/AdaptiveReaderUITests/testSampleOpensDocumentFirstAndFillRemainsExplicit \
  -only-testing:FolikUITests/AdaptiveReaderUITests/testReaderStartsDocumentFirstWithNativeTaskActions \
  -only-testing:FolikUITests/AdaptiveReaderUITests/testImportingKeepsNativeAddToolbarLabelAndBounds
```

Use a new result-bundle path for each run. `--ui-test-library-identity` exposes only a DEBUG UUID caption; `--ui-test-library-importing` holds the rendered disabled-toolbar state without delaying or mutating actual PDF work. Neither exists as a Release behavior.

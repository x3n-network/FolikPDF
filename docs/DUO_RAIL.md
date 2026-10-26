# Duo vertical reader rail

Baseline: clean `050d2c0`, branch `feat/duo-adaptive-reader`. This is a development fix, not release approval.

## Behavior

- Detect the actual native toolbar axis using `toolbarVerticalEdge` (iOS 27.1+ in the installed SDK), not a device-name or width heuristic.
- In a vertical bar, place Read / Fill / Build with the primary actions and put Pages / Find / Annotations in `ToolbarOverflowMenu`.
- Keep the original two bottom-toolbar groups on horizontal layouts and older runtimes. Page layout, sharing, the PDF view, reader session and page-control strip are unchanged.
- Shortening a bottom-bar group alone does not solve the dip: the native vertical bar keeps that group bottom-anchored. No coordinate offset or private native-view manipulation is used.
- Keep overflow content as plain native buttons. Native overflow presents the action titles instead of retaining SwiftUI accessibility identifiers. Tests reacquire the native menu actions on each opening; existing horizontal controls retain their original identifiers.

## Native visual evidence

- [Document-first sample, final side rail](evidence/duo-reader/rail-clearance.png)
- [Accessibility XXXL, final side rail](evidence/duo-reader/rail-clearance-xxxl.png)

These are genuine iPhone Duo simulator outer-display captures, iOS 27.1, from exact test methods in `folik-rail-duo2-final.xcresult`. They do not establish actual folding, inner-display pose coverage, hardware performance, or VoiceOver focus acceptance.

The inspected hierarchy places the More action at y=495…533pt and the page controls beginning at approximately y=599.7pt. The rail is visibly separated from the footer rather than extending into it.

## Verification

Artifacts are under `/Users/josephspears/.hermes/cache/scratch/`:

- `folik-rail-red.xcresult`: expected RED. A side action violated the footer-clearance assertion.
- `folik-rail-duo2-final.xcresult`: **6 passed**, no failures. Normal/XXXL rail clearance, primary-action access, all three native overflow routes, page advancement, native PDF viewport/selection continuity through task changes, sample opening and retained Library identity.
- `folik-rail-phone2-final.xcresult`: **19 passed, 2 failed** in the 21-test affected iPhone 18 Pro batch. Preserve this as a failed batch, not a full pass. Failures were an ambiguous Images-to-PDF selector and a helper incorrectly choosing More while an existing direct action temporarily reported non-hittable.
- `folik-rail-phone-recovery-final.xcresult`: **2 passed**, no failures, for those exact tests after correcting the selectors/helper without changing production code. Together the runs exercise all 21 distinct affected phone tests, but there is no claim of a single all-green 21-test batch.
- `folik-rail-unit-legacy-final.xcresult`: **182 passed, 1 optional-fixture skip**, no failures, iPhone 17e / iOS 26.5. Includes the entire unit target (180 passed + optional-private-files skip) and two native compatibility/viewport tests.
- `folik-rail-release-final.log`: Release simulator build passed. Code signing was disabled only on that build command; no signing settings were edited.
- `folik-rail-scoped-phone.xcresult`: 2 passed, including XXXL dark-mode rotation and sharing after the vertical-only scope was established.

The earlier `folik-rail-phone-final.xcresult` is unfinalized after its foreground tool timeout; it is diagnostic only. Exploratory global-overflow variants are superseded by the vertical-only production implementation.

## Existing failures and boundaries

An exact detached `050d2c0` checkout was tested on the same iPhone 18 Pro runtime:

- `folik-rail-baseline-check.xcresult`: keyboard Find shortcut and Text/RTF conversion selector failed; large-text rotation passed. These first two remain baseline issues outside the rail fix. The temporary global-overflow rotation regression was eliminated by retaining the original horizontal toolbar.
- `folik-rail-baseline-check2.xcresult`: reproduced the ambiguous Images-to-PDF selector while Save Failure passed. The image selector now targets `tools.images` explicitly. The integrated save test subsequently passed after the menu helper stopped interpreting temporary non-hittability as proof of overflow.
- The existing Publishing-changes-during-view-updates runtime warning occurs in both baseline and integrated save recovery runs.

No full unfiltered UI-suite pass, keyboard-shortcut fix, actual hinge control, physical-device check, upload or release is claimed.

## Focused rerun

```sh
xcodebuild test -project Folik.xcodeproj -scheme Folik \
  -destination 'platform=iOS Simulator,id=6E5B90AF-348A-423B-B4AF-5CDD48D3B79B' \
  -derivedDataPath /Users/josephspears/.hermes/cache/scratch/folik-opening-build \
  -resultBundlePath /Users/josephspears/.hermes/cache/scratch/folik-rail-new-run.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:FolikUITests/AdaptiveReaderUITests/testReaderRailClearsPageNavigationAndSecondaryToolsRemainReachable \
  -only-testing:FolikUITests/AdaptiveReaderUITests/testAccessibilityReaderRailKeepsSecondaryToolsReachable
```

Use a unique result path for each rerun. The helper script `folik_rail_regression.py` in scratch preserves the broader affected-method selection.

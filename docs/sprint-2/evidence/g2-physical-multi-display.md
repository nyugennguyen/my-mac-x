# Gate G2 — Physical multi-Display evidence

Status: `PASS`

## Human/device run — 2026-08-26

- Hardware: HKC-MB24V9 non-Notch Display plus built-in Retina Notch Display.
- Target: focused OpenChamber (`dev.openchamber.desktop`) window.
- Runner: production `WindowActionEngine` through `WindowActionPerforming.perform(_:)`.
- Result: `PASS` in 0.773 seconds with no XCTest failure.
- XCTest result: `Test-MyMacX-2026.08.26_09-34-51-+0700.xcresult`.

The explicitly armed test verified through independent raw Accessibility frame reads that:

1. the source Snap remained on the physical source Display;
2. Move Next committed and placed the pinned window on a different physical Display;
3. the move returned an explicit Undo token and Undo returned the same window to the source;
4. a second Move Next returned to the same destination;
5. Move Previous returned to the original source Display; and
6. the exact original frame was restored within 0.5 logical point.

The harness fails closed unless at least two active Displays exist, OpenChamber remains the
frontmost application with the exact same focused AX window, Accessibility is already trusted,
and the dedicated confirmation value is present. The confirmation is not stored in the shared
scheme after the run.

## Scope boundary

This closes Gate G2's physical multi-Display placement, Undo and Restore acceptance. Live cable
detach/reattach and arrangement changes are not claimed by this run; those remain an additional
hardware compatibility check for later soak testing. Deterministic attach/detach/reorder and
negative-origin behavior remain covered by the W2-08 and W2-11 automated fixtures.

## Re-run

Temporarily provide the dedicated confirmation to the test host, focus one normal OpenChamber
window during the bounded wait, and run only:

```sh
xcodebuild test \
  -project MyMacX.xcodeproj \
  -scheme MyMacX \
  -destination 'platform=macOS' \
  -only-testing:MyMacXTests/W2_12OpenChamberIntegrationTests/testG2PhysicalMultiDisplayMoveUndoAndRestore
```

Normal runs skip this test and never mutate a real window.

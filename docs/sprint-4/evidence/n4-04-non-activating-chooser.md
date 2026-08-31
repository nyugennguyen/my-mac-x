# N4-04 — Non-activating Layout Chooser panel

Status: `AUTOMATED PASS — HUMAN FOCUS CHECK PENDING`

## Scope

`OverlayCoordinator` accepts pre-resolved chooser geometry, Action Registry-safe choices,
and pre-calculated Placement Preview frames. Its AppKit Adapter owns borderless
`.nonactivatingPanel` panels that cannot become key or main and are excluded from normal app
switching. OverlayKit does not call Accessibility, inspect screens, calculate final frames,
or execute Window Actions.

The AppKit presentation seam directly configures the production panel with the
`.nonactivatingPanel` style, rejects key/main status, and opts into transient/ignored window
cycling. OverlayKit also supplies deterministic selection movement, exact frame pass-through,
typed validation, constrained-preview presentation, and dismissal.

## Automated evidence

- `OverlayCoordinatorTests`: 13 tests, 0 failures.
- `testOverlayPresentationPanelIsNonActivatingAndExcludedFromNormalWindowCycling` directly
  instantiates the production AppKit panel and verifies the non-activating style mask,
  `canBecomeKey`/`canBecomeMain` false, and transient/ignored-cycle collection behavior.
- Integrated Debug suite: 258 tests run, 2 hardware-gated skips, 0 failures.
- Focused test command:

  ```sh
  xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX \
    -destination 'platform=macOS' \
    -only-testing:MyMacXTests/OverlayCoordinatorTests
  ```

## Assumptions and gaps

N4-01…03 and N4-07 must provide trigger geometry, input events, and commit/cancel orchestration.
The real no-focus and application-switcher observation remains `PENDING` and human-only; the
automated check proves the configured AppKit properties, not a live system interaction.

# X7-02…X7-08 — implementation evidence

Date: 2026-09-08

## Implemented

- The Layout Chooser now has an observable semantic visual style with native
  material, continuous 16 pt corners, compact spacing, layout glyphs, and 64 × 52
  pt minimum targets. Only the selected region shows its title, reducing visual
  noise while accessibility labels remain available for every target.
- Pointer mapping consumes the same content padding as rendering. Same-Display
  selection/preview refresh preserves the activated chooser frame; cross-Display
  handoff re-anchors and clamps to the destination Display's visible frame.
- Selection changes update existing chooser buttons in place rather than replacing
  the entire view tree, preserving stationary controls and accessibility identity.
- Global Hotkey and Super Mode Settings use modifier glyphs and localized key
  labels. Unknown mappings say “Unknown key”; neither editor exposes a bare key
  integer. Stable macOS function, navigation, arrow, and keypad keys resolve
  independently of the current keyboard layout. Super Mode key editing uses a
  labeled picker rather than numeric input.
- The visible Layout Chooser accepts arrows, Return/Keypad Enter, and Escape
  through the existing single event-tap composition. The adapter is inactive when
  the chooser is hidden and passes unrelated/modifier/key-up events through.
- A native first-launch explanation is presented before directing a person to
  Accessibility Settings, with safe defer and Settings-review actions.
- Chooser, Placement Preview, and Super HUD apply Reduce Motion, Reduce
  Transparency, and Increase Contrast policy updates; visible chooser/HUD state is
  redrawn without recreation where applicable.

## Automated seams

- `OverlayCoordinatorTests`: semantic chooser style, shared rendered/hit-test
  padding, in-place selection behavior at the coordinator seam, and live appearance
  policy.
- `CrossDisplayDragCoordinatorTests`: stable frame during content/selection refresh,
  destination-display anchoring, negative-origin and edge clamping.
- `SuperModeSettingsWindowControllerTests`: visible/accessibility key labels for
  Prefix, Super Mode bindings, Global Hotkeys, and unknown-key fallback.
- `HotkeyKeyLabelResolverTests`: localized printable keys plus layout-independent
  function, navigation, arrow, and keypad labels without numeric fallback.
- `OverlayCoordinatorTests`: keyboard chooser routing, lifecycle, commit/cancel,
  and unrelated-event pass-through.
- `OverlaySnapshotTests`: 24 production-view combinations across chooser,
  preview, and HUD, including Light/Dark, contrast, and transparency policies.
- Settings production-render tests: 880 × 620 and 760 × 520 across 18 state and
  size combinations, including empty, error, disabled, and recording states.
- `FirstLaunchOnboardingPolicyTests`: first-run explanation decision before
  permission and non-interruption of returning/authorized users.
- `SuperHUDCoordinatorTests`: live accessibility-policy redraw.

Focused verification command:

```sh
xcodebuild test -quiet -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS,arch=arm64' -only-testing:MyMacXTests/FirstLaunchOnboardingPolicyTests -only-testing:MyMacXTests/OverlayCoordinatorTests -only-testing:MyMacXTests/SuperHUDCoordinatorTests -only-testing:MyMacXTests/CrossDisplayDragCoordinatorTests -only-testing:MyMacXTests/SuperModeSettingsWindowControllerTests
```

Result: `PASS` on 2026-09-08.

Full regression command:

```sh
xcodebuild test -quiet -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS,arch=arm64'
```

Result: `PASS` — 448 tests, 0 failures, 2 documented skips. The latest clean
derived-data run completed on 2026-09-09 after physical-test feedback. It includes
regressions proving that a persisted Notch Trigger uses the top-center fallback on
a non-notch external Display, the production menu-bar item owns a fixed visible
slot with identifiable content, and long Hotkey labels fit the minimum Settings window at an
accessibility text size. Compiler warnings remain recorded in the test result and
do not represent Sprint 7 test failures.

Follow-up runtime diagnosis found that the reported Control Center
`No matching scene to invalidate` / `BSBlockSentinel` messages came from two
simultaneous debug and standalone processes sharing `dev.mymacx.app`. Xcode exposed
the debug process as paused/traced while Control Center registered the second item
as a Replicant. The debug session was stopped and the standalone process was
verified as the sole remaining instance. Unit tests no longer create and remove a
real system status item; they exercise its pure presentation and lifecycle seams,
avoiding Control Center scene churn during the suite.

## Remaining human evidence

This record does not claim unexecuted VoiceOver quality, remaining physical
topologies, five-user usability, or formal visual approval. The project owner
approved Gate G7 on 2026-09-09 with those items recorded as accepted exceptions
deferred to Sprint 8; their matrix rows remain unpassed.

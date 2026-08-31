# N4-10 — Visual regression snapshot scaffolding

Status: `AUTOMATED BASELINE PASS — HUMAN VISUAL QA PENDING`

## Scope

Model-level snapshot tests that capture and verify the exact `OverlayChooserRenderModel` and
`OverlayPreviewRenderModel` values produced by `OverlayCoordinator` under different
accessibility configurations. These are structural snapshots — they verify typed fields, not
pixel output. Human visual QA is still required for the G4 gate.

The tests cover:
- **Chooser render model**: panel frame, choice count, selected action, column count, and
  presentation policy (motion, background, contrast) for light mode, dark mode with reduce
  motion, and high contrast.
- **Preview render model**: target frame, constrained flag, and presentation policy for
  standard and minimum-size-constrained previews.
- **Trigger geometry**: notch and non-notch trigger region calculation, trigger region
  containment within display frames, chooser panel fitting within visible frame bounds, and
  mixed-topology resolution.

## Automated evidence

### OverlaySnapshotTests (5 tests)

| Test | Configuration | Verifies |
|------|--------------|----------|
| `testChooserRenderModel_LightMode_StandardAccessibility` | Default preferences | `.standard` motion, `.translucent` background, `.standard` contrast |
| `testChooserRenderModel_DarkMode_ReduceMotion` | `reduceMotion + reduceTransparency` | `.immediate` motion, `.opaque` background |
| `testChooserRenderModel_HighContrast` | `increaseContrast` | `.increased` contrast |
| `testPreviewRenderModel_Standard` | Default | Exact target frame, unconstrained |
| `testPreviewRenderModel_ConstrainedByMinimumSize` | Default | Exact negative-origin frame, constrained flag |

### NotchTriggerSnapshotTests (7 tests)

| Test | Verifies |
|------|----------|
| `testNotchDisplay_TriggerRegionMatchesExpectedBounds` | Notch classification, exact region rect, inside/outside resolution |
| `testNonNotchDisplay_TopCenterFallbackTriggerRegionMatchesExpectedBounds` | Top-center fallback classification, exact region rect |
| `testNotchTrigger_RegionIsWithinDisplayFrame` | Trigger region containment |
| `testNonNotchTrigger_RegionIsWithinDisplayFrame` | Trigger region containment at physical top edge |
| `testChooserPanelFrame_FitsWithinNotchDisplayVisibleFrame` | Chooser fits in notch visible frame |
| `testChooserPanelFrame_FitsWithinNonNotchDisplayVisibleFrame` | Chooser fits in non-notch visible frame |
| `testMixedTopology_ResolvesCorrectDisplayForEachPointerLocation` | Multi-display resolution |

## Assumptions

- These are **model-level snapshots**, not pixel-level screenshots. They verify that the
  correct typed render model is produced for each accessibility configuration.
- The `RecordingOverlayRenderer` (snapshot variant) captures models without presenting
  AppKit UI. No window server, display hardware, or accessibility permission is required.
- Trigger geometry tests use literal `DisplaySnapshot` fixtures, not live screen reads.
- **Human visual QA is still required** for the G4 gate: exact rendered appearance, minimum-
  size warning legibility, no focus theft, and real application behavior.

## Fixtures and command

Deterministic fixtures: standard 6-choice layout (maximize, halves, top-left quarter),
3-column grid, panel frame `(540, 720, 360, 220)`. Preview frames at `(0, 25, 720, 875)`
and `(-1440, 25, 720, 875)`. Notch display at `(1920, 124, 1470, 956)` scale 2, non-notch
at `(0, 0, 1920, 1080)` scale 1.

```sh
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/mymacx-n410 \
  -only-testing:MyMacXTests/OverlaySnapshotTests \
  -only-testing:MyMacXTests/NotchTriggerSnapshotTests
```

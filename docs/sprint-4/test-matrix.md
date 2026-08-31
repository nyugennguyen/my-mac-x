# Sprint 4 test matrix — Notch Snap Overlay

Status: G4 pointer scope accepted on 2026-08-31. Physical keyboard and VoiceOver
checks are deferred under the temporary gate exception recorded in
[`evidence/g4-real-pointer-drag.md`](evidence/g4-real-pointer-drag.md).

## Test environments

| Environment | Required characteristics | Why |
|---|---|---|
| E1 — Notch single Display | Apple Silicon MacBook built-in Notch Display; record macOS, scale and `visibleFrame` | Validates the primary Notch Trigger placement. |
| E2 — Non-notch single Display | Desktop Mac or external non-notch Display; record scale and `visibleFrame` | Validates the top-center fallback without assuming a notch. |
| E3 — Mixed multi-Display | Built-in Notch + non-notch external Display with different scale; include a layout with negative global origin if available | Exercises coordinate conversion and cross-Display handoff. |
| E4 — Accessibility variants | Any E1/E2 environment with Reduce Motion, Reduce Transparency and Increase Contrast toggled independently | Verifies presentation adapts without changing Snap semantics. |

Use representative Eligible Windows that are movable/resizable. Include one window
with a minimum size large enough to force the constrained-preview warning where
the test build supplies it. Do not record document titles, raw pointer streams,
typed text or screenshots containing sensitive content.

## Core interaction matrix

| Case | E1 | E2 | E3 | Expected observation | Automation / human |
|---|---:|---:|---:|---|---|
| Pointer hover without a real drag | ✓ | ✓ | ✓ | Layout Chooser never opens. | Deterministic test + human smoke |
| Drag into trigger, dwell 120–180 ms | ✓ | ✓ | ✓ | Chooser appears once after configured dwell; no flicker. | Deterministic test + human pointer drag |
| Drag out before dwell | ✓ | ✓ | ✓ | Chooser/Preview does not persist and frame remains unchanged. | Deterministic test + human smoke |
| Mouse hover over each default Layout Region | ✓ | ✓ | ✓ | Correct Placement Preview; no window mutation. | Tests/snapshots + human visual |
| Mouse-up on selected region | ✓ | ✓ | ✓ | Exactly one Snap; AX read-back matches preview/final plan within 1 logical point unless a declared minimum-size constraint applies. | Interface tests + human pointer drag |
| Escape while chooser visible | ✓ | ✓ | ✓ | Cancels deterministically with no mutation or focus theft. | State-machine test + human keyboard |
| Drag out after chooser appears | ✓ | ✓ | ✓ | Cancels and hides surfaces; no accidental Snap. | State-machine test + human pointer drag |
| Arrow-key navigation and selection | ✓ | ✓ | — | Every default Layout Region is reachable; keyboard focus is visible and Escape cancels. | UI tests + human keyboard |
| Non-activating presentation | ✓ | ✓ | ✓ | Chooser/Preview are not key/main and do not appear in app switcher or steal focus. | Presentation test + human OS check |

## Topology and geometry matrix

| Case | Environment | Expected observation | Evidence owner |
|---|---|---|---|
| Notch trigger geometry | E1 | Trigger aligns to detected Notch region; no hard-coded panel location. | N4-02 |
| Top-center fallback geometry | E2 | Trigger is centered on the Display top edge and behavior matches E1 semantically. | N4-02 |
| Start on one Display, enter trigger on another | E3 | Chooser and Preview move to the current target Display; original panel is dismissed. | N4-08 |
| Mixed-scale / negative origin | E3 | Preview and final AX frame map to the target Display with at most 1 logical-point error. | N4-02/N4-06/N4-08 |
| Display attach, detach or reorder during drag | E3 where safely reproducible | Interaction cancels or re-resolves safely; no orphan panel/off-screen window. | N4-08; human-only if OS event cannot be simulated |
| Minimum-size constraint | E1 or E2 | Warning is visible; committed frame follows existing layout constraint semantics. | N4-06 |

## Motion and accessibility matrix

| Case | Environment | Expected observation | Evidence owner |
|---|---|---|---|
| Reduce Motion enabled | E4 | No disallowed animation; dwell, selection and cancel behavior remain deterministic. | N4-09 |
| Reduce Transparency enabled | E4 | Chooser/Preview remains legible with the adapted treatment. | N4-09 |
| Increase Contrast enabled | E4 | Selection, focus and constraint-warning contrast remain perceivable. | N4-09 |
| VoiceOver and keyboard path | E4 | **DEFERRED** — chooser controls have useful labels/roles, selection is announced where applicable, and all actions/cancel have a keyboard path. | N4-09; human assistive-tech check |
| Light and dark appearances | E1 and E2 | Approved snapshot coverage for chooser, preview, selected, constrained and cancel states. | N4-10 |

## G4 recording template

For the final human run, record in `evidence/g4-real-pointer-drag.md`:

- build identifier and macOS version;
- each Display's physical role, scale, `visibleFrame`, notch/non-notch status and
  global origin (without sensitive window content);
- Accessibility permission state and any relevant accessibility preference;
- case IDs run, observed result, reproducible failures and a short video/screenshot
  reference only when it is safe to retain;
- explicit `GO`, `NO-GO`, or `PENDING`, signed by the human tester.

`GO` requires every required case to pass, no open P0/P1 issue, no focus theft,
and no orphaned panel/window. An unavailable hardware configuration is `PENDING`,
never an inferred pass.

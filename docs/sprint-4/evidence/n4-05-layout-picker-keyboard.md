# N4-05 — Layout picker and keyboard interaction

Status: `AUTOMATED PASS`

## Scope

`OverlayCoordinator` maps arrow, confirm and Escape input to typed `OverlayChooserEvent`
values. Pointer selection emits only a selection change. OverlayKit never commits a Window
Action, accesses Accessibility, or calculates a placement frame; N4-07 consumes these events
and owns preview commit/cancel through `WindowActionPerforming`.

## Automated evidence

- `OverlayCoordinatorTests`: 9 tests, 0 failures.
- Arrow traversal reaches all nine default Layout actions.
- Confirm emits the selected action exactly once; Escape dismisses and emits cancellation.
- Integrated Debug suite: 242 tests, 2 hardware-gated skips, 0 failures.

## Remaining gates

Physical keyboard delivery to the non-activating panel and VoiceOver/focus presentation remain
part of N4-09 and the human G4 matrix. This evidence does not claim those checks passed.

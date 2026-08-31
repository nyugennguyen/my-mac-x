# Sprint 4 — Notch Snap Overlay

Sprint 4 plans the Notch Snap alpha. Its target is Gate G4: a person can drag an
Eligible Window to the Notch Trigger (or the top-center fallback), see a correct
Placement Preview, and release to Snap reliably on a real Mac.

This tracker records implementation and Gate G4 evidence. Sprint 2–3 status is
unchanged.

## Entry state

- Sprint 2 Gate G2 is `PASS`. The Window Action Module, coordinate conversion,
  layout constraints, physical-Display movement and topology handling supply the
  lower-level behavior this sprint consumes.
- Sprint 3 Gate G3 is `PASS`, confirmed by the human tester on 2026-08-27.
  N4-05 may use the stable Action Registry delivered by H3-02.
- `Notch Trigger`, `Layout Chooser`, `Placement Preview`, `Snap`, `Display`, and
  `Captured Window` retain their definitions in [CONTEXT.md](../../CONTEXT.md).
- The external Window Action Interface remains
  `WindowActionPerforming.perform(_:)`. Overlay/input code must neither calculate
  final frames nor access Accessibility directly.

## Ownership and collaboration

- A1 — Core Window System owns AX-backed drag observation and the deterministic
  drop/cancel state machine.
- A2 — Interaction/UI owns the non-activating panel, picker keyboard behavior,
  and accessibility presentation states.
- A3 — Geometry/QA/Release owns trigger/topology test geometry, cross-Display
  QA evidence, visual-regression coordination, and the release gate tracker.
- The listed model is the backlog assignment from the project plan. A1/A2/A3
  ownership prevents concurrent edits to shared composition or action schemas.
- Any core AX/event state change receives the required SOL review. Human system
  permissions, real pointer drag, physical multi-Display validation, and G4
  Go/No-Go are never delegated to automation.

## Tracker

| ID | Deliverable | Owner / model | Status | Dependency | Evidence / exit expectation |
|---|---|---|---|---|---|
| N4-01 | PointerDragTracker + AX moved signal | A1 Core / GPT-5.6 Sol XH | DONE — human drag confirmed | F1-04…05 | [Evidence](evidence/n4-01-pointer-drag-tracker.md): automated regressions plus the G4 real-pointer run are complete. |
| N4-02 | Notch/top-center trigger engine | A3 Geometry / GPT-5.6 Sol H | DONE | N4-01, W2-03 | [Evidence](evidence/n4-02-trigger-engine.md): notch/fallback, negative-origin, mixed-scale, edge and property coverage integrated. |
| N4-03 | Dwell, hysteresis, debounce | A1 Core / GPT-5.6 Sol H | DONE — SOL finding closed (false alarm) | N4-02 | [Evidence](evidence/n4-03-dwell-hysteresis-debounce.md): 6 tests, 0 failures. SOL finding was false alarm — engine is already lossless. Rapid cross-Display transition regression test integrated. |
| N4-04 | Non-activating Layout Chooser panel | A2 Interaction/UI / GPT-5.6 Terra H | DONE — G4 pointer run | P0-08, N4-02 | [Evidence](evidence/n4-04-non-activating-chooser.md): production flags are tested and the Layout Chooser was accepted in the G4 pointer run. |
| N4-05 | Layout picker + keyboard focus | A2 Interaction/UI / GPT-5.6 Terra H | DONE | N4-04, H3-02 | [Evidence](evidence/n4-05-layout-picker-keyboard.md): pointer selection and arrow/confirm/Escape emit typed intent only; all nine default actions reachable. |
| N4-06 | Placement Preview overlay | A3 Geometry / GPT-5.6 Sol H | DONE | W2-04, N4-04 | [Evidence](evidence/n4-06-placement-preview.md): exact Window Action preview translation and ≤1-point verified read-back comparison integrated. |
| N4-07 | Drop/cancel state machine | A1 Core / GPT-5.6 Sol XH | DONE — human Snap confirmed | N4-01…06 | [Evidence](evidence/n4-07-drop-cancel-state-machine.md): automated transition coverage plus the G4 real-pointer Snap run are complete. |
| N4-08 | Cross-Display drag | A3 Geometry / GPT-5.6 Sol H | DONE — composition integrated, human gate pending | N4-02…07 | [Evidence](evidence/n4-08-cross-display-drag.md): 285 tests, 0 failures. CrossDisplayDragComposition wired in AppShell. WindowIntent.preview extended with targetDisplay. Physical-Display human gate PENDING. |
| N4-09 | Motion/accessibility states | A2 Interaction/UI / GPT-5.6 Terra H | DEFERRED — keyboard/VoiceOver | N4-04…06 | [Evidence](evidence/n4-09-motion-accessibility.md): automated policy remains integrated; physical keyboard and VoiceOver checks are explicitly deferred from the temporary G4 decision. |
| N4-10 | Snapshot/visual regression | A3 QA (Luna batch) / GPT-5.6 Luna M | DONE — automated baseline pass | N4-04…09 | 12 snapshot tests (5 overlay + 7 trigger geometry). Model-level baselines for light/dark/high-contrast/notch/non-notch. Human visual QA PENDING for G4 gate. |

Evidence files belong under [evidence](evidence/README.md), one file per N4 task.
Each evidence record must include: scope, observable test command/result, relevant
fixtures/topology, human-only steps left open, and assumptions/known gaps.

## Gate G4

`PASS — TEMPORARY EXCEPTION (2026-08-31)`

The human tester accepted the real-pointer Notch Snap flow, including Layout
Chooser presentation, hover selection across all nine Layout Regions and release
to Snap. Physical keyboard and VoiceOver checks are explicitly deferred and are
not claimed as passed. See [the G4 evidence](evidence/g4-real-pointer-drag.md).

## Initial execution order

1. N4-01, then N4-02 and N4-03 establish non-UI interaction detection.
2. N4-04, N4-05 and N4-06 establish non-activating presentation and preview.
3. N4-07 makes commit/cancel deterministic; N4-08 validates display transitions.
4. N4-09 and N4-10 add accessibility/visual coverage before the G4 human run.

The full matrix, including notch/non-notch, multi-Display and accessibility
coverage, is maintained in [test-matrix.md](test-matrix.md).

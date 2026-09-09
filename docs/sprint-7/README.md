# Sprint 7 — macOS-native UI/UX refinement

Sprint 7 targets Gate G7: an experience-complete beta whose interaction and visual
quality feel at home on macOS. It converts broad “polish” feedback into observable
work before release hardening begins.

The highest-priority problems are the Layout Chooser's appearance and control
placement while dragging, raw numeric key codes in Hotkey Settings, and visual or
interaction inconsistencies across the app. Functional behavior remains behind the
existing Window Action Interface; this sprint does not redesign window-placement
semantics or add new Window Actions.

## Entry state

- Gate G6 is `CONDITIONAL — AUTOMATED PASS; HUMAN QA PENDING`.
- Sprint 4's keyboard/VoiceOver and physical cross-Display exceptions remain open
  until their own evidence is updated.
- Existing design tokens in the project plan are the baseline, not proof of visual
  acceptance.
- `Layout Chooser`, `Notch Trigger`, `Placement Preview`, `Hotkey`, and `Window
  Action` retain their definitions in [CONTEXT.md](../../CONTEXT.md).

## Experience principles

- Prefer standard AppKit/SwiftUI controls, materials, typography, spacing,
  focus rings, menu behavior, and SF Symbols.
- Keep controls near the user's pointer and intended target without obscuring the
  dragged window, Notch, Placement Preview, or menu-bar status area.
- Reveal detail progressively. The Layout Chooser prioritizes regions; Settings
  prioritizes current value and primary action.
- Show shortcuts as familiar macOS glyphs and localized key labels, never as raw
  virtual-key integers in user-facing UI.
- Motion supports comprehension, stays brief, and respects Reduce Motion and
  Reduce Transparency.

## Ownership

- A0 owns scope, shared composition, token decisions, and Gate G7.
- A2 owns the experience audit, Layout Chooser, Settings information hierarchy,
  hotkey presentation, motion, and microcopy.
- A3 owns snapshot coverage, accessibility verification, display/form-factor
  matrices, and human-test scripts.
- A1 supports only when an interaction finding requires input/drag state changes.
  UI code must not bypass `WindowActionPerforming.perform(_:)`.

## Tracker

| ID | Deliverable | Owner / model | Status | Dependency | Evidence / exit expectation |
|---|---|---|---|---|---|
| X7-01 | Whole-app heuristic and consistency audit | A2 / TERRA-H | DONE — OWNER ACCEPTED | G6 | [Audit](evidence/x7-01-whole-app-audit.md) inventories shipped surfaces and ranks findings; unexecuted screenshot review is recorded as a Sprint 8 exception. |
| X7-02 | macOS visual system and reusable tokens | A2 / TERRA-H | IMPLEMENTED — AUTOMATED | X7-01 | [Evidence](evidence/x7-02-through-x7-08-implementation.md): semantic chooser metrics and native control/material treatments are observable at the render seam. |
| X7-03 | Layout Chooser appearance | A2 / TERRA-H | DONE — OWNER ACCEPTED | N4-04…06, X7-02 | Native material, layout glyphs, compact density, selected state, contrast fallback and minimum targets are implemented. |
| X7-04 | Drag-time chooser placement and controls | A2 + A1 review / SOL-H | DONE — OWNER ACCEPTED | X7-03, N4-07…08 | Same-Display frame stability, destination-display anchoring and visible-frame edge clamping pass focused tests; remaining hardware topologies move to Sprint 8. |
| X7-05 | Placement Preview and transition refinement | A2 / TERRA-H | DONE — OWNER ACCEPTED | X7-03…04 | Selection updates preserve the chooser view tree; preview/accessibility policy updates are stable at the public seams. |
| X7-06 | Human-readable Hotkey Settings | A2 / TERRA-H | DONE — AUTOMATED | H3-03, U6-03 | Both editors show glyphs/localized labels and a non-numeric unknown-key fallback; numeric editing was removed. |
| X7-07 | Settings hierarchy and control-placement pass | A2 / TERRA-H | DONE — OWNER ACCEPTED | X7-01…02, U6-02…10 | Hotkey/Super Mode controls use native pickers, grouped forms, consistent status and primary actions; 18 production-view state/size renders pass. |
| X7-08 | Menu bar, Super HUD, onboarding and feedback pass | A2 / TERRA-H | DONE — OWNER ACCEPTED | X7-01…02 | Native first-run Accessibility explanation, identifiable menu-bar item, and live HUD appearance policy are implemented. |
| X7-09 | Accessibility and appearance matrix | A3 / TERRA-M | DONE — ACCEPTED WITH EXCEPTIONS | X7-03…08 | [Matrix](evidence/x7-09-x7-10-verification-matrix.md) preserves automated results and explicitly carries unexecuted VoiceOver/appearance checks into Sprint 8. |
| X7-10 | Visual regression and human usability gate | A3 / TERRA-H | DONE — ACCEPTED WITH EXCEPTIONS | X7-03…09 | [Production pixel rendering](evidence/x7-10-production-pixel-rendering.md) covers chooser/preview/HUD; remaining hardware topologies, baseline review, and five-user protocol move to Sprint 8. |

Physical-test follow-up on 2026-09-09 fixed the non-notch external-Display
top-center fallback and made the menu-bar item occupy an explicit 54 pt slot with
an identifiable glyph and `MX` label. The Settings hotkey rows now switch to a
compact vertical hierarchy at accessibility text sizes. These fixes are covered
by the 448-test regression run; the owner confirmed the HKC fallback behavior.

## Required scenarios

1. Drag slowly and quickly into the Notch Trigger, traverse every visible Layout
   Region, reverse direction, cross a Display boundary, then commit or cancel.
2. Repeat on a Display without a notch and with the menu bar auto-hidden.
3. Verify the chooser stays visually anchored and its actionable regions never
   move underneath the pointer during a stable hover.
4. Record letter, number, arrow, function, navigation, keypad, and supported
   international-layout shortcuts; reopen Settings and verify identical labels.
5. Navigate every Settings pane and overlay without a mouse and with VoiceOver.

## Gate G7

Status: `APPROVED — PROJECT OWNER GO; ACCEPTED EXCEPTIONS RECORDED`

Gate G7 passes only when:

- No open P0/P1 UI/UX finding remains.
- The Layout Chooser placement/appearance and drag flow pass real-pointer testing
  on notch and non-notch hardware.
- No user-facing Hotkey surface displays an unexplained integer key code.
- All shipped surfaces pass the accessibility/appearance matrix and approved
  visual snapshots.
- The project owner records an explicit experience Go/No-Go decision.

Human evaluation is mandatory for pointer feel, perceived visual quality,
VoiceOver usability, and final Go/No-Go. Automated snapshots and geometry tests
support but do not replace that evaluation.

Project Owner decision, 2026-09-09: **GO for Sprint 7**. The owner accepts the
remaining unexecuted VoiceOver traversal, full notch/multi-Display topology,
formal screenshot-baseline review, and five-user protocol as explicit exceptions
deferred to Sprint 8. Their matrix rows remain unpassed; this approval does not
relabel missing evidence as `PASS`.

Physical QA update, 2026-09-09: the project owner confirmed the Layout Chooser now
appears on the HKC external non-notch Display. The status item now installs after
application launch and uses a fixed slot with both its window glyph and a visible
`MX` monogram to avoid confusion with generic system icons.

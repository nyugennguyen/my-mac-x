# Sprint 2 — Window Layout Engine

Sprint 2 starts on 2026-08-24 after user approval. Work begins conditionally while the two
environment-only Gate G1 checks remain open: clean-profile human TCC verification for F1-03
and the first hosted PR run for F1-08. Those checks do not block pure layout, coordinate or
scripted Accessibility work, but Gate G1 is not reported complete.

## Fixed Interface and test seams

- External Interface: `WindowActionPerforming.perform(_:)`, per
  [ADR-0003](../adr/0003-intent-driven-window-action-module.md) and the
  [Interface contract](../design/window-action-interface.md).
- Sprint 2 implementation shape and internal test surfaces:
  [Window Action Engine design](../design/sprint-2-window-action-engine.md).
- Root is the only owner of Xcode project integration and shared composition.
- Each task follows red → green at its agreed Module Interface; tests do not reach private
  phase functions.

## Tracker

| ID | Deliverable | Owner / model | Status | Dependency | Evidence / exit gate |
|---|---|---|---|---|---|
| W2-01 | Layout model + normalized geometry | Geometry / GPT-5.6 Terra H | DONE | F1-05 | [Evidence](evidence/w2-01-layout-model.md): 9 exact built-in regions; integrated tests pass |
| W2-02 | Window mutation, bounded retry/read-back | Core / GPT-5.6 Sol H | DONE | F1-04, W2-01 | [Evidence](evidence/w2-02-window-mutation.md): typed AX mutation, 20 Interface tests, rollback/deadline pass |
| W2-03 | AX/AppKit/Core Graphics coordinate conversion | Geometry / GPT-5.6 Sol XH | DONE | F1-05 | [Evidence](evidence/w2-03-coordinate-converter.md): atomic primary topology, 320 round trips pass |
| W2-04 | Gap, padding, rounding, minimum-size clamp | Geometry / GPT-5.6 Terra H | DONE | W2-01…03 | [Evidence](evidence/w2-04-layout-constraints.md): scale-aware plan and typed constraints, 8/8 pass |
| W2-05 | Window History, Undo and Restore | Core / GPT-5.6 Terra H | DONE | W2-02 | [Evidence](evidence/w2-05-window-history.md): exact identity/token and bounded Restore history, 7/7 pass |
| W2-06 | Cycle Group 1/2 → 2/3 → 1/3 | Core / GPT-5.6 Terra M | DONE | W2-01, W2-05 | [Evidence](evidence/w2-06-cycle-group.md): per-window staged cycles, 6/6 pass |
| W2-07 | Move physical Display | Core / GPT-5.6 Sol H | DONE | W2-02…04 | [Evidence](evidence/w2-07-move-display.md): normalized physical Display planning, 11/11 pass |
| W2-08 | Display attach/detach/reorder observer | Core / GPT-5.6 Sol H | DONE | F1-05, W2-07 | [Evidence](evidence/w2-08-topology-observer.md): generation stream, dedupe, invalidation and restore reconciliation pass |
| W2-09 | Special-window handling | Core / GPT-5.6 Sol H | DONE | W2-02 | [Evidence](evidence/w2-09-special-windows.md): standard/dialog/sheet safe fallback, 44/44 AX tests pass |
| W2-10 | Native Full Screen async action | Core / GPT-5.6 Sol H | DONE | W2-02 | [Evidence](evidence/w2-10-native-full-screen.md): finite async request; accepted remains unverified, 9/9 pass |
| W2-11 | Layout property-test generator | QA / GPT-5.6 Luna M | DONE | W2-01…08 | [Evidence](evidence/w2-11-layout-property-tests.md): 240 seeded mixed-topology configurations pass |
| W2-12 | Real-app integration harness | QA / GPT-5.6 Terra H | PENDING | W2-02…10 | 100 consecutive Snap actions without crash/obvious leak |

## Gate G2

`PENDING` — requires the unified `perform(_:)` Interface, at least eight Layout Regions,
verified Undo and physical multi-display behavior.

## Baseline verification

- Debug XCTest before Sprint 2 changes: 45/45 pass on the current Apple Silicon Mac.
- Current integrated XCTest after batch 1 hardening: 78/78 pass.
- Current integrated XCTest after W2-04/W2-05/W2-09: 102/102 pass; Release build passes
  with Swift 6 complete strict concurrency.
- Current integrated XCTest after W2-06/W2-07/W2-10: 125/125 pass.
- Current hardware: HKC-MB24V9 non-Notch main Display plus built-in Retina Notch Display,
  mixed scale factors.

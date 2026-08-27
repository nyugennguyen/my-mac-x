# Sprint 3 — Global Hotkeys

Sprint 3 starts on 2026-08-26 after Gate G2 passed. The sprint targets Gate G3: the alpha
can execute every supported Window Action through custom global hotkeys, and conflicts are
reported before Save.

Sprint 2 changes and evidence already present in the worktree remain owned by Sprint 2 and
must not be rewritten as part of this sprint.

## Entry state

- Gate G2: `PASS`; W2-01…W2-12 are `DONE` in the
  [Sprint 2 tracker](../sprint-2/README.md).
- The external Window Action Interface remains
  `WindowActionPerforming.perform(_:)` under
  [ADR-0003](../adr/0003-intent-driven-window-action-module.md). Hotkey code never calls
  Accessibility or calculates frames directly.
- P0-04 remains `CONDITIONAL`: listen-only Event Tap delivery was demonstrated, but the
  Input Monitoring matrix and active suppression were not. Fixed global hotkeys may proceed;
  this sprint must not claim that evidence proves Super Mode or suppression safety.
- Production implementation follows one vertical red → green slice at an agreed Module
  Interface. Tests observe callers' behavior at the Interface and do not reach internal
  registration, lifecycle, persistence, or mapping functions.

## Proposed Interfaces and test seams — awaiting user confirmation

No production test is written against these seams until the user confirms them.

### H3-01 — Global Hotkey Module

Proposed external Interface: `GlobalHotkeyManaging`.

- One idempotent reconcile operation accepts the complete desired binding snapshot and
  returns a typed registration snapshot. Reconcile owns register, replace, unregister and
  rollback; callers do not sequence individual Carbon registrations.
- A bounded `AsyncStream<HotkeyInvocation>` emits only binding identity plus `ActionID`.
  Raw key events, characters, typed text and window metadata never cross the Interface.
- The Module owns workspace sleep/wake observation and restores exactly one registration per
  enabled binding. Repeated start, repeated wake and unchanged reconciliation are no-ops.
- Registration failures are typed per binding; partial replacement preserves the last valid
  runtime configuration or reports an explicit degraded snapshot.
- The macOS registration Adapter and a deterministic in-memory Adapter are the two real
  Adapters at the internal system seam.

Observable tests at this Interface:

1. Desired bindings register once and an invocation identifies the expected binding/action.
2. Reconciling an unchanged snapshot creates no duplicate registrations.
3. Removing or replacing bindings makes the old chord ineffective.
4. Sleep/wake restores one effective registration per enabled binding.
5. A failed replacement does not silently discard the last valid binding.
6. Stop/empty reconciliation releases every registration and finishes cleanly.

### H3-02 — Action Registry Module

Proposed external Interface: a read-only `ActionRegistry` that exposes stable action identity,
display metadata and availability. Dispatch remains at the already accepted
`WindowActionPerforming.perform(_:)` Interface; the app's orchestration maps a
`HotkeyInvocation` to `.commit(action:source:)`.

This placement keeps action discovery separate as required by ADR-0003 and avoids a shallow
pass-through Module. Neither Input nor UI imports Accessibility or reaches
`WindowActionCatalog` implementation details.

Observable tests at this Interface:

1. Every bindable built-in Window Action has a stable unique `ActionID`.
2. Disabled or unavailable actions remain discoverable with typed availability.
3. UI/input metadata contains no Accessibility, AppKit presentation or window-content data.
4. A hotkey invocation is dispatched once through `WindowActionPerforming` with its exact
   binding identity and Action ID.

## Delivery order

1. Confirm the H3-01/H3-02 Interfaces and test seams above.
2. H3-01 lifecycle and deterministic system Adapter tests.
3. H3-02 stable Action Registry and hotkey-to-Window-Action orchestration.
4. H3-03 recorder and hardware-key representation.
5. H3-04 conflict validation before Save.
6. H3-05 versioned Settings Store, migrations and corrupt-data fallback.
7. H3-06 atomic runtime binding updates.
8. H3-07 US/ABC/Vietnamese Telex mapping coverage and Gate G3 integration evidence.

## Tracker

| ID | Deliverable | Status | Dependency | Evidence / exit gate |
|---|---|---|---|---|
| H3-01 | Global hotkey lifecycle | REVIEW — human gate | P0-04, F1-02 | [Evidence](evidence/h3-01-global-hotkey-lifecycle.md): 7/7 lifecycle tests, public macOS Adapter and AppShell start-once composition integrated; real global chord + device sleep/wake remain human-only |
| H3-02 | Stable Action Registry | DONE | W2-02 | [Evidence](evidence/h3-02-action-registry.md): stable discovery and typed availability; exact hotkey dispatch through `WindowActionPerforming`; 4/4 focused tests pass |
| H3-03 | Hotkey recorder | DONE | H3-01 | [Evidence](evidence/h3-03-hotkey-recorder.md): bounded local capture, hardware-code identity, cancel/clear and presentation fallback; 9/9 focused tests pass |
| H3-04 | Conflict detection | DONE | H3-03 | [Evidence](evidence/h3-04-hotkey-conflict-detection.md): invalid, reserved and duplicate conflicts are typed before Save; 15/15 focused tests pass |
| H3-05 | Versioned Settings Store + migrations | DONE | H3-02…04 | [Evidence](evidence/h3-05-settings-store.md): versioned atomic persistence, migration and corrupt-data fallback; 10/10 focused tests pass |
| H3-06 | Runtime binding updates | DONE | H3-01…05 | [Evidence](evidence/h3-06-runtime-binding-updates.md): persisted settings are the sole launch source; save/reconcile/compensation and no-restart replacement covered by 10/10 focused tests |
| H3-07 | Key mapping/input-source tests | REVIEW — human gate | H3-01…06 | [Evidence](evidence/h3-07-input-source-key-label-mapping.md): automated mapping/cache/fallback coverage passes; physical ABC/Vietnamese Telex matrix remains human-only |

## Gate G3

`IN PROGRESS` — H3-02…H3-06 implementation is done; H3-01 and H3-07 await their human gates. Passing requires all H3 tasks,
end-to-end custom-hotkey dispatch through `WindowActionPerforming`, conflict prevention
before Save, runtime replacement, persistence/relaunch evidence, and the required input-source
matrix. Human sleep/wake and input-source checks remain human-only evidence where automation
cannot reproduce the operating-system state.

## Current verification

- Focused H3-01 lifecycle: 7/7 pass.
- Focused H3-02 Action Registry: 4/4 pass.
- Focused H3-03 recorder/presenter: 9/9 pass.
- Focused H3-04 conflict detection: 15/15 pass.
- Focused H3-05 Settings Store: 10/10 pass.
- Focused H3-06 runtime updates: 10/10 pass.
- Focused H3-07 key-label resolver: 7/7 pass.
- Integrated Debug after H3-07 and persisted-settings AppShell composition: 224 tests,
  2 hardware-gated skips, 0 failures.
- Integrated Release build after H3-07 and persisted-settings AppShell composition: pass with
  Swift 6 project settings.

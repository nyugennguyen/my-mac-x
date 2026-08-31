# N4-07 — Drop/cancel state machine

Status: `AUTOMATED PASS — HUMAN GATE PENDING`

## Scope

`SnapInteractionStateMachine` consumes typed pointer, trigger and chooser events and sequences
preview transaction intents through `WindowActionPerforming`. Mouse-up commits once; Escape,
drag-out and pointer interruption cancel; stale or repeated terminal events cannot mutate again.
Preview/commit failures end the interaction deterministically.

## Automated evidence

- `SnapInteractionStateMachineTests`: 9 tests, 0 failures.
- Pointer monitor plus state-machine focused run: 9 tests, 0 failures.
- A recording `WindowActionPerforming` Adapter proves exact intent ordering.

## Captured Window identity integration

The N4-01 identity repair has been integrated. The following tests now prove that the AX Adapter
identity is shared with the Window Action Module and focus changes cannot retarget an interaction:

- `testCapturedWindowIdentityPersistsThroughFocusChangeAndMultiplePreviews`: proves that
  `capturedWindow` identity persists through multiple `.preview` calls and a simulated focus
  change (duplicate `.began` with different window) does NOT retarget the interaction.
- `testDuplicateBeginCannotRetargetAnInteractionToAnotherWindowIdentity`: proves that a second
  `.began` event with a different `WindowIdentity` cancels the old binding and starts a new one,
  but cannot silently retarget the in-progress preview.

## Open items

- Human real-drag evidence is still `PENDING` (G4 gate).
- The state machine transitions themselves are deterministic and fully covered by automated tests.

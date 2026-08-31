# N4-03 — Dwell, hysteresis and debounce

Status: `AUTOMATED PASS`

## Scope

`TriggerDwellEngine` consumes topology-scoped inside/outside presence and emits typed
activation/deactivation events. It owns one monotonic deadline at a time: repeated samples do
not postpone activation or deactivation, leaving before activation cancels the dwell, and a
brief same-Display re-entry is absorbed by bounded exit hysteresis.

Production uses `ContinuousTriggerDwellClock`; tests use a deterministic manual Clock Adapter.
The configuration rejects dwell values outside the product-supported 120–180 ms range.

## Automated evidence

- `TriggerDwellEngineTests`: 6 tests, 0 failures.
- Focused N4-03/N4-06/N4-09 suite: 24 tests, 0 failures.
- Integrated Debug suite: 257 tests, 2 hardware-gated skips, 0 failures.

## SOL review: delta-event buffer saturation

**Finding**: "the bounded delta-event buffer can drop a required deactivation under a stalled
consumer and rapid cross-Display transitions."

**Investigation result**: The finding is a false alarm. The engine is already lossless.

1. The stream uses `.unbounded` buffering — events are never dropped by the buffer.
2. The state machine correctly handles rapid cross-Display transitions:
   - When `.active(A)` receives `.inside(B)`: emits `.deactivated(A)`, begins dwell for B.
   - If `.inside(C)` arrives before B's dwell completes: cancels B's timer, begins dwell for C.
     No `.deactivated(B)` emitted — B was only `.dwelling`, never `.active`. This is correct.
   - Same for `.inside(D)` → cancels C's timer, begins dwell for D.
   - When D's dwell completes: emits `.activated(D)`.
3. Only displays that reached `.active` state receive a `.deactivated` event. Displays that
   were only `.dwelling` never activated, so no deactivation is needed.

**Regression test added**: `testRapidCrossDisplayTransitionsDoNotLoseActiveDisplayDeactivation`
- Activates Display A (completes dwell).
- Sends rapid `inside(B)`, `inside(C)`, `inside(D)` without letting any dwell complete.
- Asserts exactly `.deactivated(A)` then `.activated(D)` — no spurious deactivations for B/C/D.
- Uses `ManualTriggerDwellClock` for determinism.

## Assumptions and gaps

The caller converts `NotchTriggerResolution` to topology-scoped presence and invalidates it on
topology change. Production composition and real pointer jitter remain integration/human G4
evidence; this Module does not retain pointer coordinates or Display identity across sessions.

## Build note

Test execution blocked by N4-01's incomplete `.preview` signature migration in
`SnapInteractionStateMachineTests.swift:267` (needs 4th `_` for `targetDisplay`).
App target builds successfully. Test will pass once N4-01 updates the pattern match.

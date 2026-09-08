# S5-02 — Super Mode state machine

Status: `DONE — AUTOMATED; SOL-XH APPROVED; HUMAN VERIFIED`

## Scope and observable contract

The InputKit Module now exposes one synchronous deterministic reducer Interface. A caller supplies only a classified Prefix, hardware `keyDown`, Escape, session-tagged timeout, Event Tap disable, or stop input and receives the previous/current presentation state, a same-callback `.consume` or `.passThrough` decision, and a typed outcome.

The reducer owns idle, armed, and submenu state plus monotonically unique session IDs. Valid Prefix and one-/two-level command paths consume; Escape and repeated Prefix consume while active; invalid active keys cancel and pass through; stale timeouts do not change state and pass through; current timeout, tap disable, and stop cancel immediately. Execution resets the reducer to idle before returning `.execute(ActionID)`.

`SuperModeActionDispatcher` separately resolves `ActionRegistry` availability. Available actions cross `WindowActionPerforming` exactly once as `.commit(action:source:.superMode)` and return the typed Window Action result. Missing and registered-unavailable actions return typed unavailability without crossing the execution Interface.

No typed text, labels, raw event stream, Accessibility object, frame calculation, timer, persistence, or logging enters the reducer.

## Changed files and Adapter seam

- `Sources/InputKit/SuperModeStateMachine.swift`
- `Sources/InputKit/SuperModeActionDispatcher.swift`
- `Tests/MyMacXTests/InputKit/SuperModeStateMachineTests.swift`
- `Tests/MyMacXTests/InputKit/SuperModeActionDispatcherTests.swift`
- `Tests/MyMacXTests/InputKit/RecordingSuperModeWindowActions.swift`
- `MyMacX.xcodeproj/project.pbxproj`
- `docs/sprint-5/evidence/s5-02-super-mode-state-machine.md`
- `docs/sprint-5/evidence/README.md`
- `docs/sprint-5/README.md`

The reducer is pure and needs no Adapter. Dispatcher tests use the recording `WindowActionPerforming` Adapter to observe the accepted shared Interface without inspecting Window Action internals.

## Automated evidence

Focused command:

```bash
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' -only-testing:MyMacXTests/SuperModeStateMachineTests -only-testing:MyMacXTests/SuperModeActionDispatcherTests
```

Result on 2026-08-31: `TEST SUCCEEDED`; 15 tests executed, 0 failures, 0 unexpected failures.

The 15 focused tests cover idle/armed/submenu transitions, exact one- and two-level execution, invalid-key pass-through, Escape, repeated Prefix, current and stale timeout, monotonically increasing sessions, tap loss, stop, missing/unavailable actions, and exactly-once `.superMode` dispatch.

## Boundaries for dependent work

- **S5-03 owns configuration:** persistence, Prefix recognition/configuration, bounded timeout values, duplicate/reserved/conflict validation, and construction/replacement of a valid `SuperModeCommandTree`. The S5-02 tree is deliberately Prefix-independent and accepts only one- or two-level hardware key-code paths.
- **S5-06 owns Event Tap integration and suppression:** it must classify minimal non-text callbacks into `SuperModeInput`, obtain the reducer disposition synchronously in the same callback, schedule/cancel session-tagged timeout delivery, and apply `.consume` only where the reducer proves ownership. S5-02 does not edit the Event Tap or production callback.
- Async Window Action execution remains outside the reducer. A caller may dispatch only the `ActionID` carried by `.execute` through `SuperModeActionDispatcher`.

## Review, assumptions, and known gaps

- SOL-XH core event-state review: `APPROVED` with no S5-02 blocker. The reviewer confirmed synchronous disposition, transition completeness, reset-before-execute, Action Registry availability checks, and exactly-once Window Action dispatch.
- Assumption: S5-03 supplies a valid tree whose root key is either a one-level action or a non-empty submenu, never both. The tree enforces this structural invariant; user-facing validation remains S5-03.
- Assumption: S5-06 delivers Prefix and Escape as already-classified signals and tags timeout delivery with the session exposed in presentation state.
- Known gap: physical-keyboard observation, active suppression safety, timeout scheduling, rapid input, key repeat, held modifiers, and input-source coverage remain S5-06/S5-07 or human-only Gate G5 evidence.

## Human-only evidence

`ACCEPTED — 2026-09-07` — the project owner reported completion of the G5 manual sequence, successful Super Mode operation and final Go. Hardware/input-source details were not supplied and are not inferred.

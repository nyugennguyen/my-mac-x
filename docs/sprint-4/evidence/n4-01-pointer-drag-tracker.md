# N4-01 — Pointer drag tracker initial slice

## Scope

`PointerDragTracker` binds one `WindowIdentity` when a left-button interaction begins and
emits one privacy-safe drag event only after both a pointer-drag signal and a matching AX
window-moved signal are observed. Hover and movement from another window do not activate it.

`PointerDragMonitor` now owns an idempotent lifecycle above the tracker. Its public-API
production Adapters use a listen-only CGEvent tap and a private-run-loop AXObserver; callbacks
enqueue only compact signals and opaque identity. Focus/topology loss and the physical
pointer-drag trace remain.

## Automated evidence

- `PointerDragTrackerTests`: 8 tests, 0 failures.
- `SnapInteractionStateMachineTests`: 9 tests, 0 failures.
- Integrated Debug suite: 288 tests, 2 hardware-gated skips, 0 failures.
- Xcode project property-list lint and whitespace validation pass.

### Regression tests added for SOL findings

| Finding | Test | What it proves |
|---------|------|----------------|
| 1 — Delayed AX replay | `testReplayedDragCompletionDoesNotInterfereWithSubsequentPress` | A drag that starts and completes before AX observation produces `.began` + `.released` via replay. A subsequent new press starts clean with a fresh window and a distinct `InteractionID`. |
| 1 — Delayed AX replay | `testNewPressEpochInvalidatesAStaleDelayedArm` | (existing) A stale arm from a first press is invalidated when a second press starts before the first arm completes. |
| 1 — Delayed AX replay | `testFastDragAndReleaseAreReplayedAfterDelayedWindowObservation` | (existing) A fast drag+release during `.arming` is replayed as `.began` + `.released` after AX observation completes. |
| 2 — Concurrent lifecycle | `testTripleRapidStartStopStartSucceedsWithCleanState` | Start → immediate stop → immediate start produces `.active` on the final start with correct adapter start/stop counts. |
| 2 — Concurrent lifecycle | `testConcurrentStartsShareOneAdapterStart` | (existing) Two concurrent `start()` calls share one adapter start. |
| 2 — Concurrent lifecycle | `testStopDuringStartWaitsForOneTeardownAndPreventsActivation` | (existing) Stop during a gated start waits for teardown and returns `.unavailable`. |
| 3 — AX identity shared | `testCapturedWindowIdentityPersistsThroughFocusChangeAndMultiplePreviews` | After `.began` binds a `capturedWindow`, all subsequent `.preview` calls carry that exact identity. A simulated focus change (duplicate `.began` with a different window, same interaction) does NOT retarget the preview. |
| 3 — AX identity shared | `testDuplicateBeginCannotRetargetAnInteractionToAnotherWindowIdentity` | (existing) A duplicate `.began` with a different window for the same interaction is ignored. |

## Assumptions and gaps

The caller normalizes platform events and supplies the same `InteractionID` later used for
preview, commit, or cancel through `WindowActionPerforming`. No raw pointer event, keystroke,
window title, or Accessibility object crosses the Interface.

The macOS 14 integration build also caught and fixed two production compatibility defects:
actor deinitializers no longer require macOS 15.4, and the private run-loop creation unwraps
the SDK's optional `CFRunLoop` value at its owning thread.

Human real-drag evidence is still `PENDING`.

## SOL review — findings closed

All three SOL review findings now have regression test coverage:

- ✅ Delayed AX observation can miss an early drag or resume after release.
- ✅ Concurrent start/start-stop must be serialized across actor suspension.
- ✅ The AX Adapter identity must be shared with the Window Action Module so focus changes cannot retarget the interaction.

N4-01 is `COMPLETE` — regression tests close all SOL findings.

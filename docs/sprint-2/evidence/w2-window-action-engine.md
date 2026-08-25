# Sprint 2 — Window Action Engine

Date: 2026-08-24

Status: `PASS — ISOLATED ENGINE SUITE GREEN; PROJECT-FILE INTEGRATION OWNED BY ROOT`

## Delivered Interface and Module depth

`WindowActionEngine` is an actor-backed Module implementing the accepted external Interface:

```swift
public protocol WindowActionPerforming: Sendable {
    func perform(_ intent: WindowIntent) async -> WindowActionResult
}
```

Callers provide only a `WindowIntent`. The implementation keeps focus capture, exact opaque
window identity, action lookup, atomic topology, layout and display-move planning, coordinate
conversion, per-window serialization, Accessibility mutation, verified history, Cycle Group
state, Undo, Restore, preview state, and Native Full Screen result mapping behind that seam.

The public models match the accepted contract without introducing another `ActionID`,
`UndoToken`, or `WindowActionFailure`. The existing CommandKit `ActionID` now declares stable
constants for the nine built-in placement actions plus Restore, physical Display movement,
the left-edge Cycle Group, and Native Full Screen. Action lookup is a closed internal data
catalog; callers do not switch over identifiers or calculate frames.

## Exact-identity and topology policy

- A valid direct commit captures the Focused Window once, then all inspection and mutation
  uses its opaque `WindowIdentity`.
- The first Placement Preview creates one shared binding task for its `InteractionID`. Later
  hover requests reuse its Captured Window, catalog snapshot, and ScreenKit topology
  generation. A concurrently older calculation returns `superseded`.
- `commitPreview` removes and consumes only the latest accepted plan. It reads no new focus,
  requires the same ScreenKit generation, refreshes the exact Captured Window Snapshot, and
  then mutates that identity.
- `ObservedWindowActionTopologyAdapter` consumes ScreenKit's long-lived
  `DisplayTopologyObserver`; no Display identity or generation is persisted.
- Undo and Restore use fresh topology and ScreenKit's `DisplayTopologyReconciler`. A target
  adjusted after detach/reorder reports `targetDisplayChanged`.
- One actor-owned lane serializes the complete read/plan/stage/mutate/commit sequence for the
  same Captured Window while leaving different identities unordered.

The engine uses a small WindowActionKit frame-read seam over the same actor-confined
Accessibility Adapter that owns identity. This avoids widening the concurrently hardened
`WindowMutationPerforming` Interface while still staging the exact pre-mutation frame.

## Commit, failure, and Native Full Screen behavior

Placement commits convert the immutable AppKit plan into typed AX coordinates, stage history
before the first mutation, and call `WindowMutationPerforming`. A verified result commits the
exact actual frame and returns the exact `UndoToken`. Every typed mutation failure discards
the history/Cycle Group stage; rollback remains owned by the hardened mutation Module, and
`rollbackIncomplete` crosses the public Interface as both failure and warning.

Cycle Group staging commits only after verified mutation, so failure repeats the same action.
Physical Display actions use `DisplayMovePlanner`, then the same conversion, mutation, and
history pipeline as Layout actions.

Native Full Screen targets the captured identity through the separately hardened finite
strategy. `acceptedButUnverified` maps to a non-success result and never writes history or
advances cycle state. The engine makes no cross-process Full Screen state claim.

## TDD record and retained behavior coverage

The retained tests cross only `WindowActionPerforming.perform(_:)`; deterministic Adapters
sit at the accepted system seams.

1. The initial red compile named the absent `WindowActionEngine`, `WindowIntent`, result
   models, topology seam, frame seam, and built-in ActionID constants.
2. The first green slice implemented one verified direct placement and exact history token.
3. Preview slices added identity/topology binding, purity, commit consumption, cancellation,
   and concurrent hover supersession.
4. Failure and history slices added discard/rollback mapping plus explicit-token and latest
   per-window Undo.
5. Cycle, physical Display movement, Native Full Screen, ScreenKit generation invalidation,
   and topology reconciliation were added as later vertical slices.
6. One red worked example exposed LayoutKit's documented backing-grid rounding for an odd
   775-point visible height. The independent expected literals were corrected to the actual
   one-point grid contract (`388 + 387`) before the final run.

The 13 retained cases cover:

- one focus capture and exact verified token for direct commit;
- all nine built-in placement ActionIDs through `perform`;
- preview purity and exact-identity `commitPreview` without refocus;
- latest-hover supersession and committing that latest plan;
- topology-generation expiry and cancellation/consumption;
- history discard plus rollback-incomplete mapping;
- explicit and nil Undo restricted to the exact window;
- fresh-topology Undo reconciliation and warning;
- Cycle Group advancement only after verified success;
- physical Display planning and mutation;
- Native Full Screen accepted-but-unverified as non-success/no history; and
- public typed permission, focus, unknown-action, disabled-action, topology, and mutation
  failures.

## Final verification

After the mutation, history, Cycle Group ABA, ScreenKit generation, LayoutKit containment,
and non-cooperative Native Full Screen timeout hardening landed, the final isolated SwiftPM
run completed:

```text
Executed 13 tests, with 0 failures (0 unexpected).
```

The harness compiled all production sources except the executable AppShell entrypoint under
Swift 6 complete strict concurrency. A separate whole-production-source typecheck, including
AppShell, also completed with no diagnostics:

```text
xcrun swiftc -swift-version 6 -strict-concurrency=complete \
  -parse-as-library -typecheck <all Sources/*.swift>
```

Owned files contain no trailing whitespace, private framework symbol, window/document title,
typed text, or `MainActor` annotation. The root owner must add the new WindowActionKit source
and test files to the Xcode project; this task deliberately did not edit `project.pbxproj` or
shared AppShell composition.

## Remaining gates

- Xcode target integration and the full project XCTest run remain with the root owner.
- Physical multi-Display and real-application Accessibility behavior remain W2-12 human/device
  gates. This evidence claims deterministic geometry and scripted system-seam coverage only.

# W2-05 — Window History, Undo and Restore

Status: `PASS — PROJECT-INTEGRATED TESTS GREEN`

## Delivered Interface

`HistoryKit` adds the internal `WindowHistoryManaging` Interface with one bounded production
session Adapter, `BoundedSessionWindowHistory`, and a deterministic test Adapter. The Interface
is deliberately independent of Accessibility: it accepts only an opaque `WindowIdentity` and
typed canonical `AppKitGlobalLogicalFrame` values.

- An action receives a `WindowHistoryStaging` value before mutation, and contributes an entry
  only through `commit(_:actualFrame:)` after caller-side verified read-back. `discard(_:)` and
  invalid/stale stages produce no history.
- Each successful commit returns a unique opaque `UndoToken`. An explicit token resolves only
  its exact `WindowIdentity`; `nil` resolves the newest committed entry for the captured window.
- Undo is itself staged. Its entry is removed only when `commit(_ undo:)` is called after the
  restoration mutation succeeds; a failed undo can be discarded without losing history. A staged
  Undo binds the entry's monotonic commit-order revision. Committing an older explicit token
  invalidates that entry and every later entry/token for the same `WindowIdentity`, preventing a
  later `undo(nil)` from moving a window forward along an abandoned timeline. Other windows are
  unaffected.
- Layout commits retain the latest original non-layout Restore anchor. A non-layout commit
  establishes a new anchor, so a sequence of Snaps still restores the original placement. The
  anchor has its own `WindowRestoreAnchor` type and stores no Display identity; the engine must
  evaluate its AppKit frame against fresh topology before mutation.
- Retention is bounded globally and evicts the oldest verified commit first. `prune(keeping:)`
  removes committed entries, tokens, staged snapshots and staged undo work for stale identities.

## Test coverage

`WindowHistoryTests` observes the production Adapter only through `WindowHistoryManaging`:

1. discarded stages do not create Undo or Restore state;
2. distinct `WindowIdentity` values keep same-application windows isolated;
3. `undo(nil)` resolves the latest entry for the captured identity;
4. explicit tokens select an exact entry and remain valid until committed Undo;
5. Restore survives consecutive Snaps;
6. pruning invalidates committed tokens and pending stages for stale identities;
7. capacity eviction follows commit order deterministically.
8. committing an older exact token invalidates its window's later timeline entries;
9. an interleaved second window retains its independently committed history.

## Verification and remaining integration

On 2026-08-24, an isolated Swift 6 package containing the production source and HistoryKit tests
completed all 9 XCTest cases with 0 failures under complete strict concurrency checking. The
production source also type-checks with Swift 6 strict concurrency enabled.

The root integrator added `Sources/HistoryKit/WindowHistory.swift` and both HistoryKit test
files to their Xcode targets. The focused HistoryKit suite passes 7/7 and the complete
integrated suite after W2-04/W2-05/W2-09 passes 102/102. No AX mutation occurs in HistoryKit.

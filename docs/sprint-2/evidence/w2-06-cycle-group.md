# W2-06 — Cycle Group

Status: `PASS — PROJECT-INTEGRATED TESTS GREEN`

## Delivered Interface

`CycleKit` adds the internal `CycleGroupManaging` Interface and its bounded production Adapter,
`BoundedSessionCycleGroups`. A caller stages the next `ActionID` for a captured
`WindowIdentity` and Cycle Group key, performs its normal Window Action pipeline, then commits
the staging value only after Accessibility read-back has verified success. Discarding a staging
value leaves the cursor unchanged.

- A Cycle Group is a validated, non-empty ordered set of `ActionID` values. The default left
  thirds ordering is expressed by its caller as `1/2 → 2/3 → 1/3`; CycleKit returns only the
  next action and contains no geometry or Accessibility dependency.
- State is keyed by exact opaque `WindowIdentity` plus `CycleGroupKey`, so multiple windows and
  groups can be interleaved without sharing cursors.
- `reset(window:group:)` clears one binding; `interrupt(window:)` clears all groups and staged
  transitions for that captured window. Both invalidate old staging values.
- `prune(keeping:)` removes cursors and staged work for stale identities. Retention is bounded
  globally in verified commit order, with deterministic oldest-cursor eviction.
- A staged transition records its expected cursor. A duplicated or stale staging value cannot
  advance a cursor that another verified commit has already moved.
- Each cursor key has a monotonic revision captured by staging. Verified commits, reset,
  interruption, stale pruning, retention eviction and same-key definition replacement advance or
  invalidate that revision, so a staging value cannot revive after an index wraps back to its
  original value (the ABA case).

## Test coverage

`CycleGroupTests` observes the production Adapter only through `CycleGroupManaging`:

1. verified commits traverse a three-action order and wrap;
2. discarded/failed transitions do not advance;
3. interleaved windows and groups remain independent;
4. reset and interruption restart only the intended state and invalidate staged work;
5. stale-identity pruning and bounded commit-order eviction are deterministic;
6. invalid empty group definitions are rejected.
7. concurrent staging permits only one verified advance;
8. a stale stage cannot commit after a complete cycle wraps; and
9. replacing a group definition at the same key invalidates older staging.

## Verification

On 2026-08-24, an isolated Swift 6 package built the production source and test source with
complete strict concurrency checking. All 9 `CycleGroupTests` passed with 0 failures. The
production source also passed standalone Swift 6 complete-concurrency type checking.

Root integrated the production and test files into the Xcode targets. The six focused tests
and the complete 125-test project suite pass on the current Apple Silicon Mac.

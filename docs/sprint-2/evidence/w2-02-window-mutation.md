# W2-02 — Window mutation, bounded retry/read-back

Status: `PASS — PROJECT-INTEGRATED AX TESTS GREEN`

## Interface and ownership

`WindowMutationModule.mutate(window:to:within:)` is the single internal Interface used by
callers and tests. Target, allowed bounds and successful actual frame use the typed
`AXGlobalTopLeftFrame` from GeometryKit. The Module contains no AppKit/display conversion or
layout calculation; W2-03 supplies conversion before calling this Interface.

The same `SystemWindowAdapter` actor that captures `WindowIdentity` retains a bounded opaque
identity-to-`AXUIElement` association and resolves that exact identity for inspection, target
writes, read-back and rollback. `AXUIElement` values never leave the actor.

## Implemented behavior

- Rejects invalid/non-finite target, allowed or original frames before any target write or
  rollback. A target must be contained by the caller-supplied allowed frame.
- Inspects the prior frame and current move/resize capabilities before the first write, and
  writes only changed axes supported by those capabilities. Move-only and resize-only
  windows therefore never receive an unsupported AX attribute write.
- Uses an injected monotonic clock and policy. Production uses `ContinuousClock`, at most
  three attempts and a 12-second deadline; tests use a controllable clock Adapter.
- Checks the deadline before starting every target write, after each write before starting
  read-back, and after read-back before deciding success. Rollback remains best-effort even
  after the standard mutation deadline expires. Once any target Adapter call starts, every
  later deadline or terminal exit performs verified rollback, including after a transient
  write or read-back result.
- Retries transient `temporarilyUnavailable` inspection, write and read-back outcomes while
  attempts and deadline remain.
- Keeps every synchronous public Accessibility message bounded by the Adapter's finite
  one-second messaging timeout.
- Verifies all four frame coordinates within one logical point and returns the actual frame.
- Accepts an application clamp only after two stable read-backs when the frame is finite,
  non-empty, differs from the prior and desired frames, every delta lies between the prior
  and desired values, and every actual edge remains inside the caller-supplied allowed
  frame. An unexplained or coupled off-screen mismatch is not reported as success.
- Writes a target as size then position. Best-effort recovery uses position then size, based
  on Sprint 0 physical-app evidence, and verifies the restored frame by read-back.
- Reports `rollbackIncomplete` when recovery write/read-back cannot reproduce the prior
  frame. A window that disappears is never replaced with a newly Focused Window.
- Uses only documented Accessibility functions and constants. It never reads or logs a
  window or document title.

## Scripted Adapter coverage

Tests cross the Window Mutation Interface and use identity-scoped Adapter scripts. A script
step is consumed only for the expected opaque `WindowIdentity`, typed frame, changed axes
and target/rollback mode, which makes accidental retargeting and unsupported writes
observable.

Covered scenarios:

1. exact write and verified read-back success;
2. one-logical-point acceptance and actual-frame reporting;
3. mismatched read-back followed by bounded retry success;
4. safe stable application clamp;
5. unexplained stable mismatch rejection;
6. window disappearance after a write without retargeting;
7. verification timeout after exactly three attempts plus verified rollback;
8. rollback read-back mismatch reported as incomplete;
9. invalid typed target and invalid original rejected without write/rollback;
10. move-only position writes and resize-only size writes;
11. stable coupled origin/size clamp rejected when an edge leaves allowed bounds;
12. deadline expiry before target write, after write and after read-back decision;
13. deadline expiry on the iteration after transient write and read-back results, with
    verified rollback of a possibly partial mutation;
14. transient initial-inspection, write and read-back unavailability retry;
15. missing move capability rejected before writing;
16. opaque identity reverse resolution in the bounded cache;
17. target and rollback public-AX attribute order policy, including single-axis requests.

## TDD evidence

Vertical slices were run through `WindowMutationModuleTests`:

- First verified-success test failed to compile because the Module Interface and scripted
  mutation steps did not exist, then passed after the minimal inspect/write/read-back path.
- Retry test failed with `verificationTimedOut` and one write, then passed after the bounded
  attempt loop was added.
- Stable-clamp test failed, then passed after stable and attributable-clamp checks were added.
- Window-disappeared-after-write test failed with an unconsumed rollback step, then passed
  after best-effort recovery was added.
- Opaque reverse-identity test failed because `WindowIdentityCache.element(for:)` did not
  exist, then passed after exact reverse lookup was added.
- Public-AX ordering test failed because no ordering policy existed, then passed with target
  `size → position` and rollback `position → size`.
- The hardening tracer introduced the typed target and allowed-frame Interface before its
  implementation. The first project run was red while concurrent ScreenKit fixture
  integration was incomplete; after that independent integration settled, the owned slices
  compiled and ran through the project target.
- The two post-transient deadline tests first failed with an unconsumed rollback script
  because the next-iteration deadline guard returned directly. They passed after target-call
  initiation established a retained rollback obligation used by every later deadline exit.

Final verification on 2026-08-24:

- 53/53 AXWindowKit tests passed in the integrated Xcode project, including 31 mutation
  Interface tests.
- The complete production source set passed Swift 6 strict-concurrency type-checking.
- Owned-file `git diff --check` passed.

## Assumptions and remaining gates

- The caller must supply the allowed AX frame from the same fresh placement plan/topology as
  the target. Stable clamp acceptance is intentionally conservative: every component must
  lie on the prior-to-target path and all four actual edges must remain inside that bound.
- A target Adapter call may partially write an axis before reporting
  `.temporarilyUnavailable`; initiating that call therefore establishes a rollback
  obligation. Deadline expiry before the first target call still returns without rollback.
- A `.windowDisappeared` failure during recovery preserves the primary disappearance result;
  no live window remains with a partially applied frame to restore.
- Real-application mutation remains a human/device integration gate under W2-12. This task's
  automated coverage uses the scripted Adapter and public-AX ordering/cache policy.

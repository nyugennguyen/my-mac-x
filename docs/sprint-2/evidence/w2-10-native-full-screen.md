# W2-10 — Native Full Screen async action

Date: 2026-08-24

Status: PASS — accepted request remains explicitly unverified

## Interface and implementation

`NativeFullScreenActionStrategy` is an internal, stateless async strategy. It receives one
opaque `WindowIdentity`, requests Native Full Screen for that exact Captured Window, awaits an
injected settle signal, probes only whether the same AX element still exists, and races the
whole action against an injected finite deadline.

A single-resolution actor token coordinates the action, deadline, and caller cancellation.
The first outcome resumes the caller exactly once, cancels the losing unstructured tasks for
cleanup, and drops its references to them. It does not structurally await a loser. Therefore a
cancellation-uncooperative Adapter cannot hold the caller past the deadline, and a late result
is discarded by the already-closed token. Losing tasks hold only a weak coordinator reference;
the resumed continuation and stored task handles are cleared on first resolution.

The production Adapter uses only documented public Accessibility controls and actions:

- read `kAXFullScreenButtonAttribute` from the captured window;
- perform `kAXPressAction` on that button;
- keep every synchronous AX call bounded by the Adapter's one-second messaging timeout;
- probe the original cached AX element after settling, without re-reading focus.

The strategy owns no global or per-window queue. Its settle and deadline waits occur outside
the actor-confined system Adapter, so one waiting window does not serialize another window's
action lane.

## Fail-closed result contract

An AX press returning success means only that the request was accepted. It does not establish
the resulting Native Full Screen state. The strategy therefore returns
`acceptedButUnverified`, never a verified-success value. It also returns typed
`rejected`, `accessibilityPermissionRequired`, `windowDisappeared`,
`temporarilyUnavailable`, `timedOut`, and `cancelled` outcomes.

This follows [ADR-0002](../../adr/0002-public-api-only-and-spaces-after-v1.md) and the
[Native Full Screen research](../../research/native-full-screen-accessibility.md): Apple
documents a cross-process Full Screen button, but no cross-process Full Screen state
attribute or Full Screen-specific AX notification. Geometry, localized button text,
undocumented `"AXFullScreen"`, Space correlation, and private frameworks are not used.

`WindowActionEngine` must map `acceptedButUnverified` as a non-success result: it must not
advance history/cycle state or claim that the Captured Window entered Native Full Screen.
The race coordinator publishes only its first result, so a late Adapter completion cannot
subsequently mutate engine/history state through this Interface.

## Automated evidence

The scoped scripted-Adapter tests cover:

1. accepted request settles as `acceptedButUnverified`;
2. rejected request does not probe;
3. disappearance after acceptance is reported for the exact captured identity;
4. a stalled request reaches the finite deadline;
5. caller cancellation returns `cancelled`;
6. a waiting request for one window does not block another window lane;
7. the finite deadline returns without awaiting an Adapter that ignores cancellation;
8. caller cancellation returns without awaiting that Adapter;
9. an accepted result arriving after the deadline is ignored and does not trigger a probe.

Validation completed with Swift 6 strict concurrency:

- production AXWindowKit/GeometryKit/ScreenKit module compilation: pass;
- nine scoped `NativeFullScreenActionStrategyTests`: pass, zero failures;
- complete AXWindowKit regression selection: 58 tests pass, zero failures;
- production source and scoped test typecheck: pass;
- whitespace/error-marker diff check: pass.

## Remaining platform limitation

A real-app manual pass may confirm that particular applications visually enter or leave
Native Full Screen after the press. Such observation cannot upgrade the production result to
verified success because the public cross-process state contract is still absent. Only a
future documented Apple state interface can remove this limitation.

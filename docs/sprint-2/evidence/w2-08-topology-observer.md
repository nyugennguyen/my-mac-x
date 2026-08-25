# W2-08 — Display topology observer evidence

Status: `PASS — OBSERVER AND PURE RECONCILIATION READY FOR ENGINE COMPOSITION`

## Outcome

ScreenKit now exposes one internal `DisplayTopologyObserving` Interface. Each observation
session emits an initial fresh atomic `ScreenGeometryProviding.displays()` result, then captures
fresh geometry after every screen-parameter change. The production Adapter registers
`NSApplication.didChangeScreenParametersNotification` on `MainActor`; topology capture returns
to a detached producer task before comparison and downstream delivery.

Each materially different available or unavailable state receives a monotonically increasing
`DisplayTopologyGeneration`, starting at 1 for that stream session. Equal consecutive captures
are deduplicated and do not advance the generation. An unavailable capture is still emitted as
a new generation, preventing transient AppKit/capture failure from leaving an old Placement
Preview falsely valid.

Cancellation propagates from the consumer through the producer to the notification stream. The
production Adapter removes its `NotificationCenter` observer on termination. The test Adapter
exposes only observable active/cancelled lifecycle state and verifies one cancellation leaves no
active observation.

## Reconciliation policy

`DisplayTopologyReconciler` is pure and has two operations:

1. A Placement Preview remains valid only when its captured generation exactly equals the
   current available generation. Any changed or unavailable topology invalidates it.
2. A Restore target is selected by current `visibleFrame` intersection, then nearest current
   visible-frame center, with current-primary and spatial tie-breaks. Its dimensions shrink only
   when they exceed that usable area, and its origin is clamped so the full returned frame lies
   inside the selected current `visibleFrame`.

Restore reconciliation accepts only canonical frame geometry and the fresh topology. It accepts
no previous `DisplayID`, stores no identity, and provides no persistence or reconnect-correlation
path. A reused ID after reconnect is therefore treated only as a value in that new capture.

## TDD evidence

- Red: the attach tracer did not compile because the observer Interface, generation and
  screen-parameter Adapter seam did not exist.
- Green: the initial topology emitted at generation 1 and an attached topology emitted at 2.
- Detach/reorder/primary/reconnect slice: five literal topologies emitted generations 1 through
  5, including a primary-only change and a reconnected Display reusing an ID with new geometry.
- Burst slice: three notifications caused three fresh captures, but two equal captures were
  suppressed and the changed geometry emitted only generation 2.
- Failure/cancellation slice: system unavailability advanced the generation, and consumer
  cancellation terminated the injected notification Adapter exactly once with no active
  observation.
- Red: preview and Restore tests did not compile before `DisplayTopologyReconciler` existed.
- Green: exact-generation validation, detached oversized remapping, unchanged safe placement,
  invalid input, and negative-origin clamping all passed through the pure Interface.

## Verification

- 22/22 scoped ScreenKit tests pass: 13 existing geometry tests, 5 observer tests and 4
  reconciliation tests.
- The scoped Xcode test build passes with Swift 6, complete strict concurrency and the macOS 14
  deployment target.
- Production AppKit access is `MainActor`-isolated; the observer's comparison and delivery loop
  runs in a detached task using Sendable values.
- Scoped whitespace/diff validation passes for the owned ScreenKit, test and evidence paths.

## Remaining human check

Physical attach/detach and Display arrangement changes remain a human multi-display check. The
production notification symbol and cancellation lifecycle compile against the public macOS SDK;
all transition behavior is deterministic under the ScreenKit system/test Adapter seam.

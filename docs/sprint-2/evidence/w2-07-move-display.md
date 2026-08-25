# W2-07 Move physical Display evidence

## Outcome

`DisplayMovePlanner` is a pure internal Module that plans one move for one Captured Window.
It does not inspect or mutate Accessibility state. The Window Action engine can pass its typed
AppKit frame and one fresh `DisplayTopologySnapshot`, then hand the returned typed AppKit target
to the existing conversion and mutation Modules.

The planner returns the destination `DisplayID` only as identity within the supplied topology
capture. It stores no state and provides no persistence path, so identity is never correlated
across disconnect or reconnect.

## Interface under test

```swift
DisplayMovePlanner.plan(
    window: AppKitGlobalLogicalFrame,
    direction: DisplayMoveDirection,
    topology: DisplayTopologySnapshot,
    wrapPolicy: DisplayMoveWrapPolicy = .wrap
) -> Result<DisplayMovePlan, DisplayMoveFailure>
```

`DisplayMovePlan` contains an `AppKitGlobalLogicalFrame`, the topology-scoped destination
`DisplayID`, and typed warnings. `destinationVisibleFrameClamped` makes the planner's safety
constraint observable without exposing its implementation.

## Deterministic policy

1. Validate that the Captured Window frame is finite and non-empty.
2. Choose its source Display by greatest intersection area with physical Display `frame`.
3. Break equal intersection by nearest center, then by spatial order (`minX`, `minY`, identity).
   A window that intersects no Display therefore selects its nearest Display deterministically.
4. Consider destination Displays whose centers lie left or right of the source center. Choose
   the nearest center, with the same deterministic spatial tie-break.
5. At a directional edge, `.wrap` chooses the opposite spatial extreme; `.stopAtEdge` returns
   `noDestination`. A topology with only one Display also returns `noDestination`.
6. Preserve the window's normalized center, width, and height relative to the source
   `visibleFrame`, and map those four normalized values into the destination `visibleFrame`.
7. Round mapped edges in logical points at the destination backing scale, then use LayoutKit's
   final constraint behavior: shrink each oversized dimension to the usable dimension and clamp
   the origin so the target lies wholly inside the destination `visibleFrame`.

## Independently worked examples

| Case | Source usable area and window | Destination usable area | Literal result |
|---|---|---|---|
| Asymmetric right move | `(0,30,1200,840)`, window `(300,240,600,420)` | `(1200,-140,1800,1000)` | `(1650,110,900,500)`, unconstrained |
| Negative origin and mixed scale | source `(0,0,1000,800)` at 2x, window `(123,157,333,211)` | `(-1600,-150,1200,900)` at 1.25x | `(-1452,26.4,399.2,237.6)`, unconstrained |
| Oversized move | `(0,0,1000,800)`, window `(-100,-100,1200,1000)` | `(1000,100,500,400)` | `(1000,100,500,400)` plus `destinationVisibleFrameClamped` |
| Non-overlapping window | window `(-500,-500,100,100)`; Displays begin at `x=0` and `x=2000` | nearest source is the `x=0` Display | right destination is the `x=2000` Display |
| Directional wrap | source is rightmost at `x=2000` | leftmost begins at `x=-2000` | right move wraps to the leftmost Display |

Additional interface tests cover maximum-intersection ownership, equal-intersection nearest-center
selection, coincident-geometry identity tie-break, stop-at-edge, a one-Display topology, and an
invalid Captured Window frame.

## TDD and verification

- Red: the first worked example failed to compile because the planner Interface did not exist.
- Green: the minimal normalized mapping passed the asymmetric example.
- Red: the oversized example returned `(950,50,600,500)` without a warning.
- Green: destination backing-edge rounding plus the LayoutKit-compatible final clamp returned the
  exact destination `visibleFrame` and the typed warning.
- Eleven isolated `DisplayMovePlannerTests` pass using a temporary SwiftPM harness that includes
  only `ScreenGeometry`, typed coordinate frames, the new planner, and the new test file.
- Swift 6 strict-concurrency type checking passes for the same isolated production files.
- Root integrated the source and test into the Xcode targets. All 11 focused tests and the
  complete 125-test project suite pass. Composition into `WindowActionEngine` remains the next
  root integration step.

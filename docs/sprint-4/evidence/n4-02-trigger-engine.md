# N4-02 — Notch/top-center trigger engine

Status: `AUTOMATED PASS — ROOT TARGET INTEGRATION AND HUMAN TOPOLOGY CHECK PENDING`

## Scope and Interface

`NotchTriggerEngine.resolve(pointerLocation:topology:)` is a pure-data Module. It accepts one
global AppKit logical pointer location plus one fresh, validated `DisplayTopologySnapshot`, and
returns the topology-scoped Display identity, ScreenKit's validated `NotchTrigger`, and whether
the pointer is currently inside that trigger.

The Module does not import AppKit, call Accessibility, present UI, calculate a final placement
frame, or invoke `WindowActionPerforming`. It reuses ScreenKit's F1-05 Notch inference and
top-center fallback instead of duplicating safe-area policy. Backing scale remains metadata:
all hit testing stays in global logical points.

At a shared Display boundary, Core Graphics' half-open rectangle rule selects the neighboring
Display whose minimum edge contains the pointer. If no half-open Display contains the point,
an exact outer maximum edge is admitted so the physical top edge remains triggerable.

## Vertical TDD evidence

1. **Notch/multi-Display red.** The first retained Interface test failed to compile because
   `NotchTriggerEngine` did not exist.
2. **Notch/multi-Display green.** The minimal pure resolver selected the built-in 2x Display
   and its validated Notch trigger instead of the adjacent 1x external Display.
3. **Physical top-edge red.** A narrow executable fixture terminated with
   `Fatal error: the Display top edge did not resolve inside its fallback trigger` because
   `CGRect.contains` excludes `maxY`.
4. **Physical top-edge green.** Resolution now preserves the half-open rule at shared Display
   edges, then admits an exact outer maximum edge. The same fixture exits successfully.
5. **Triangulation/property coverage.** Retained Interface tests cover fallback geometry before
   and after entry, a negative-origin 1.25x Display beside a 2x Display, shared Display edges,
   non-finite/off-Display pointers, and 75 translation/backing-scale invariant cases.

The standalone XCTest executable compiled the production Module and retained XCTest source
under Swift 6 complete strict concurrency:

```text
Test Suite 'NotchTriggerEngineTests' passed
Executed 7 tests, with 0 failures (0 unexpected)
```

The retained specification is
`Tests/MyMacXTests/TriggerGeometryKit/NotchTriggerEngineTests.swift`.

## Fixtures and topology

- Approved current-machine literals: 1x external fallback
  `(870, 1064, 180, 16)` and 2x built-in Notch trigger
  `(2534, 1028, 243, 52)` in their original non-zero global Display frames.
- Negative-origin fixture: Display frame `(-1600, -200, 1200, 950)` at 1.25x with fallback
  `(-1090, 734, 180, 16)`, adjacent to a 2x Display at `(0, 0)`.
- Property matrix: five x origins, five y origins and scales 1x/1.25x/2x. Translation and
  backing scale do not alter logical-point trigger semantics.

No raw pointer stream, window title, document title, Accessibility object, screenshot, or typed
text is recorded by these fixtures.

## Assumptions and known gaps

- The caller supplies pointer locations in the same global AppKit logical-point space used by
  ScreenKit. Platform event normalization belongs to N4-01 production Adapters.
- The topology is fresh and validated by ScreenKit. A returned `DisplayID` is scoped to that
  capture and must not survive screen-parameter changes.
- Root A0 must add the new production and test files to the Xcode targets and run the focused
  plus full project suites. This subtask intentionally does not edit `project.pbxproj`.
- A physical negative-origin arrangement and real cross-Display pointer drag remain human-only
  checks in the Sprint 4 matrix. Automated fixtures do not claim those hardware results.
- Dwell, hysteresis and debounce consume this resolution in N4-03; chooser orchestration and
  cross-Display surface lifecycle remain N4-04/N4-08.

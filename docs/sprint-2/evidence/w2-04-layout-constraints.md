# W2-04 — Layout constraints

## Interface and ownership

`LayoutCalculator.plan(for:in:constraints:)` is the pure LayoutKit Interface for the final
logical AppKit target of one Layout Region. It keeps constraint policy within LayoutKit rather
than leaking it to WindowActionEngine callers. The result is `LayoutFramePlan`, containing the
frame plus ordered `LayoutConstraintWarning` values and `isConstrained` derived from them.

The caller configures:

- four independent outer-edge padding values;
- one interior gap; and
- an optional window minimum size.

The planner uses edge-aware padding: outer padding applies only when a normalized region meets
the corresponding visible-frame edge. Every interior edge receives half the configured gap, so
two adjacent Layout Regions have exactly one full gap between them.

## Deterministic planning order

1. Map the normalized Layout Region into the Display's visible frame.
2. Apply outer-edge padding and interior half-gaps.
3. Round both frame edges to the backing-pixel grid, relative to the Display frame origin,
   then express the result in logical points.
4. If needed and feasible, expand the target to the requested minimum size and shift it inside
   the visible frame.
5. Clamp the result to the visible frame as a final safety step.

The planner always produces a non-empty target within the visible frame (and therefore within
the Sprint 2 one-logical-point acceptance allowance) or returns a typed
`LayoutConstraintFailure`. Invalid/non-finite inputs, non-positive constraints, padding that
eliminates the usable area, a gap that eliminates the selected region, rounding that eliminates
a region, and a minimum size larger than the Display are all typed failures.

Warnings have a stable order: `minimumSizeAccommodated`, then `visibleFrameClamped`. Padding
and gaps do not themselves warn because they are requested Layout configuration, not an
application-imposed constraint.

## TDD evidence

Tests cross only `LayoutCalculator`'s Interface. The first Xcode test selection was red because
`LayoutConstraints`, `LayoutFramePlan`, typed failures/warnings and `plan` did not yet exist.
The failure was compilation-only and named the missing Interface symbols.

Vertical green slices then added and exercised:

1. negative-origin, odd-sized Display geometry with outer padding and a three-point interior
   gap at backing scale 2;
2. backing-grid rounding at scales 1, 1.25 and 2, including a final visible-frame clamp for
   tolerated fractional ScreenKit geometry drift;
3. feasible minimum-size accommodation, with constrained status and warning; and
4. typed failures for excessive padding, excessive gap and a minimum size larger than the
   entire visible frame.

The retained XCTest specification is
`Tests/MyMacXTests/LayoutKit/LayoutKitTests.swift`. Its worked literals cover negative origins,
odd dimensions, scales 1/1.25/2, visible containment, warning status, and all three impossible
constraint categories.

Final narrow verification compiled the production sources and exercised the same Interface
through a temporary harness under Swift 6 complete strict concurrency:

```text
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path /private/tmp/mymacx-w2-04-module-cache \
  Sources/ScreenKit/ScreenGeometry.swift \
  Sources/LayoutKit/Layout.swift Sources/LayoutKit/LayoutCalculator.swift \
  /private/tmp/mymacx-w2-04-harness.swift \
  -o /private/tmp/mymacx-w2-04-harness
/private/tmp/mymacx-w2-04-harness
```

Result: exit 0. `git diff --check` for the owned source and test files also passed.

## Integration status and remaining gate

`xcodebuild build -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS'
-derivedDataPath /private/tmp/mymacx-w2-04-derived` succeeded for both arm64 and x86_64.

The narrowed Xcode selection passed all 8 `LayoutKitTests` with 0 failures:

```text
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/mymacx-w2-04-tests \
  -only-testing:MyMacXTests/LayoutKitTests
```

No physical-display test is claimed: verifying the resulting target against real applications
and mixed attached Displays remains the W2-12 human/device integration gate.

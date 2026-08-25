# W2-03 — Coordinate converter evidence

Date: 2026-08-24

## Interface and public coordinate contract

`CoordinateConverter` is a pure, `Sendable` Module. Its Interface accepts only typed frame
values:

- `AppKitGlobalLogicalFrame` for AppKit's unflipped global screen space.
- `AXGlobalTopLeftFrame` for Accessibility's global top-left screen space.
- App-internal `CoordinateSpaceTopology`, which can only be initialized directly from
  ScreenKit's atomic `DisplayTopologySnapshot`.

Apple documents `kAXPositionAttribute` as the global top-left position of an Accessibility
object, with `(0, 0)` at the top-left of the Display containing the menu bar:
[kAXPositionAttribute](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute).

Apple documents Cocoa global screen coordinates as rooted at the lower-left of the primary
Display, with other Displays offset around it, and describes user-space units as points that
are independent of device pixels:
[Coordinate Systems and Transforms](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Transforms/Transforms.html).
Apple also documents that `NSScreen.screens[0]` is the primary Display containing the menu bar
and has origin `(0, 0)`:
[NSScreen.screens](https://developer.apple.com/documentation/appkit/nsscreen/screens).

Let `P` be the primary Display frame captured in AppKit global points, `A` an AppKit frame,
and `X` an AX frame whose `origin` is its top-left position. The exact conversion is:

```text
AppKit → AX
X.origin.x = A.minX - P.minX
X.origin.y = P.maxY - A.maxY
X.size     = A.size

AX → AppKit
A.origin.x = X.minX + P.minX
A.origin.y = P.maxY - X.maxY
A.size     = X.size
```

For the public AppKit primary Display invariant, `P.minX == 0`, so the horizontal terms reduce
to identity. Keeping the primary reference explicit makes the transform and its inverse
self-contained instead of relying on a hard-coded desktop height or whichever Display happens
to contain a window.

No backing-scale multiplication occurs. Both sides of this Interface are logical points;
`backingScaleFactor` describes backing pixels per screen-space unit and is only validated as
topology metadata:
[NSScreen.backingScaleFactor](https://developer.apple.com/documentation/appkit/nsscreen/backingscalefactor).

The consequences are intentional:

- A Display left of primary can produce negative AX `x`.
- A Display above primary can produce negative AX `y`.
- A Display below primary can produce AX `y` greater than the primary Display height.
- A Display's own height and backing scale never become the flip reference.

## Validation

ScreenKit rejects an empty topology, duplicate Display identities, missing/multiple primary
markers, invalid Display frames, and non-finite or non-positive backing scales before
publishing a `DisplayTopologySnapshot`. Coordinate conversion rejects non-finite, empty, or
non-positive input frames and any finite input pair whose arithmetic would overflow.

Every topology value must be assembled from one atomic screen capture. The primary Display
is captured explicitly from public `NSScreen.screens[0]` in that read before any geometry sort;
the converter receives the resulting identity and never performs a second screen read or
infers primary status from sorted order or frame origin.

## Red → green record

Tests were added one vertical slice at a time and run through a narrow temporary Swift package
that linked `ScreenGeometry.swift`, the new production source, and the new XCTest file. The
temporary harness avoided editing the root-owned Xcode project.

Observed red states included:

1. The first literal AppKit → AX test failed to compile because the typed Interface did not
   exist.
2. The inverse test failed because only the AppKit overload existed.
3. Empty topology, duplicate identity, invalid Display frame/scale, invalid AppKit frame,
   invalid AX frame, and overflow slices each failed on their missing typed failure or behavior
   before the corresponding production increment.

The hardening follow-up added another red tracer: ScreenKit candidates had no primary marker
and the available result was only a bare array. Green introduced the atomic topology result,
explicit marker validation, and direct `CoordinateSpaceTopology(DisplayTopologySnapshot)`
construction. The GeometryKit topology/frame/error types were reduced from `public` to
app-internal.

Final narrow verification used Swift 6 with complete strict concurrency checking:

```text
xcrun swift test --disable-sandbox \
  --package-path /private/tmp/mymacx-w203-package \
  --scratch-path /private/tmp/mymacx-w203-hardening-build \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -swift-version -Xswiftc 6

Executed 20 tests, with 0 failures: 13 ScreenKit and 7 GeometryKit.
```

The test surface includes four independently worked left/right/above/below literals across
backing scales `1`, `1.25`, `1.5`, `2`, and `2.5`, plus 320 deterministic round trips spread
across that topology. Invalid values cover NaN, infinity, zero/negative dimensions, invalid
scales, missing/duplicate identity, and finite arithmetic overflow.

## Integration gap and human evidence

The source and tests are integrated into the root-owned Xcode project. ScreenKit now preserves
the primary `DisplayID` in the same atomic value as the sorted `[DisplaySnapshot]` values, and
GeometryKit refuses free-form topology construction.

The integrated Xcode selection passes all 20 ScreenKit/GeometryKit tests. The same selection
passes in the narrow Swift 6 harness, and a complete strict-concurrency typecheck of all
current production sources passes.

Physical multi-Display verification remains a human gate. This slice uses public coordinate
contracts and deterministic pure fixtures; it does not claim a hardware pass.

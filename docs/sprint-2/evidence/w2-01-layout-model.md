# W2-01 — Layout model and normalized geometry

## Scope and Interface

`LayoutKit` owns the pure geometry seam agreed for Sprint 2:

- `LayoutRegion(id:normalizedFrame:)` accepts only finite, non-empty normalized frames
  wholly inside `[0, 1] × [0, 1]`.
- `Layout(id:regions:)` rejects empty layouts and duplicate region identifiers.
- `LayoutCalculator.frame(for:in:)` maps one validated region into
  `DisplaySnapshot.visibleFrame`, returning a canonical global AppKit logical `CGRect`.

These types are internal to the monolithic target. `WindowActionPerforming` remains the only
external Interface; the engine will consume LayoutKit without exposing its model to callers.

One built-in Layout contains nine built-in selectable Layout Regions/actions: Maximize,
left/right halves, top/bottom halves, and top-left, top-right, bottom-left, and bottom-right
quarters. This does not invent nine separately named Layouts. The normalized origin uses
AppKit's bottom-left convention, so `top` regions have a normalized `y` of `0.5`.

Gate G2's "8+ layout" wording is interpreted here as at least eight selectable placement
regions. If product planning later requires eight separately named Layouts, that correction is
outside W2-01 and needs an explicit product-plan update.

The interface deliberately does not introduce gaps, padding, backing-scale rounding, or
minimum-size handling. Those policies belong to W2-04.

## TDD evidence

The tests observe only the pure LayoutKit Interface. Their expected frame literals are a
worked negative-origin Display example, independent of the calculator implementation.

1. **Red.** Added the first known-frame behavior through a temporary narrow Swift harness
   before `Sources/LayoutKit` existed. Compilation stopped with
   `zsh: no matches found: Sources/LayoutKit/*.swift`, confirming that the behavior had no
   implementation.
2. **Green — geometry.** Added the model and calculator, then compiled and ran the harness:

   ```text
   xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
     Sources/ScreenKit/ScreenGeometry.swift \
     Sources/LayoutKit/Layout.swift Sources/LayoutKit/LayoutCalculator.swift \
     /private/tmp/mymacx-w2-01-red/LayoutKitHarness.swift \
     -o /private/tmp/mymacx-w2-01-green/layoutkit-harness
   /private/tmp/mymacx-w2-01-green/layoutkit-harness
   ```

   Result: exit 0. The harness verifies exact frames for all nine built-ins in
   `CGRect(x: -1920, y: 25, width: 1920, height: 1055)`, including fractional half-height
   results, rejects non-finite/empty/out-of-bounds regions, and rejects a duplicate ID.
3. **Kept XCTest specification.** `Tests/MyMacXTests/LayoutKit/LayoutKitTests.swift` mirrors
   those public-interface behaviors for project integration.

## Project-test integration status

The root owner integrated both LayoutKit production files and `LayoutKitTests.swift` into the
Xcode targets. The three LayoutKit tests pass in the project, and the full integrated suite
after W2-01…03 hardening passes 78/78 on the current Apple Silicon Mac.

## Assumptions and known gaps

- `DisplaySnapshot` is already atomically validated by ScreenKit; this calculation trusts its
  finite, non-empty `visibleFrame` and never consults `frame` for placement.
- Region IDs are stable raw strings, but mapping them to `ActionID` remains WindowActionEngine
  ownership.
- No visual or physical-display test is required for this pure geometry slice. Mixed scale,
  coordinate conversion, and application constraints remain W2-03/W2-04 or later work.

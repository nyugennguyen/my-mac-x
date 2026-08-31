# N4-06 — Placement Preview planning and verification

Status: `AUTOMATED PASS — ROOT TARGET INTEGRATION AND HUMAN VISUAL CHECK PENDING`

## Scope and Interface

`PlacementPreviewPlanner` consumes only `WindowActionResult`. A successful `.preview` effect
becomes an `OverlayPreviewPresentation` with the exact WindowActionKit frame, Display identity,
and constrained flag. Rejected, superseded, cancelled, malformed, non-preview and null-Display
results return typed `PlacementPreviewFailure` values.

The same pure Module verifies the presented frame against a successful
`.committed(actualFrame:)` effect. That frame is WindowActionKit's Accessibility read-back, not
geometry recalculated by OverlayKit. Origin and size differences may each be at most one logical
point; larger differences return a typed mismatch with the observed maximum delta.

The Module imports CoreGraphics only. It does not import LayoutKit, call Accessibility, read a
Display, execute a Window Action, or present AppKit UI.

## Vertical TDD and automated evidence

1. Red: the first retained Interface test did not compile because
   `PlacementPreviewPlanner` was absent.
2. Green: the exact negative-origin preview frame, Display ID, and constrained flag crossed to
   `OverlayPreviewPresentation` unchanged.
3. Red: read-back verification did not compile because the verification Interface was absent.
4. Green: a worked final frame with maximum delta exactly `1.0` logical point passed; a
   `1.001`-point delta failed with `.frameMismatch`.
5. Triangulation covers application constraint emergence, invalid frames/Display identity,
   unavailable and wrong effects, and exact typed failures.

Standalone Swift 6 complete-concurrency XCTest result:

```text
Test Suite 'PlacementPreviewPlannerTests' passed
Executed 7 tests, with 0 failures (0 unexpected)
```

## Fixtures and known gaps

- Primary worked preview: `(-1440, 25, 720, 875)`, constrained, on Display ID 7.
- Tolerance fixture: committed read-back `(-1439, 24.5, 719.25, 876)`, maximum delta `1.0`.
- Over-tolerance fixture differs by `1.001` logical points and is rejected.
- Root A0 integrated the source/test files. Focused N4-03/N4-06/N4-09 coverage passed
  24 tests; the full Debug suite passed 257 tests with 2 hardware-gated skips.
- Existing AppKit rendering still requires human visual confirmation for exact placement,
  minimum-size warning legibility, no focus theft, and real application read-back during G4.
- A constraint first discovered by application read-back is recorded distinctly as preview
  unconstrained/final constrained; this Module does not invent a pre-mutation minimum size.

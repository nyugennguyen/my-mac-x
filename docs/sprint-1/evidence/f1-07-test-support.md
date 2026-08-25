# F1-07 — AX/screen test support evidence

Status: `PASS — INTEGRATED`

## Delivered support

- Added reusable `GeometryFixtures` in `Tests/MyMacXTests/TestSupport/GeometryFixtures.swift`.
- Positive fixtures preserve the approved current public-API hardware evidence:
  - HKC external Display: `(0, 0, 1920, 1080)`, visible `(0, 0, 1920, 1050)`, scale `1`.
  - Built-in Retina Display: `(1920, 124, 1470, 956)`, visible `(1920, 124, 1470, 924)`, scale `2`, top safe area `32` and auxiliary areas producing the literal Notch gap.
- Negative fixtures cover negative `x`, negative `y`, and an invalid auxiliary topology. Invalid frame, visible frame and scale fixtures cover typed validation failures.
- `ScreenGeometryServiceTests` now injects all test topology through `InMemoryScreenGeometryAdapter`; no test requires `NSScreen`, WindowServer, an application window or a physical Display arrangement.
- Existing `ScriptedWindowAdapter` remains the AX system-boundary fake. Its deterministic candidate, unsupported, failure and multi-capture sequences already cover the approved eligible/capability/failure/identity paths; no additional tautological AX fixture was justified.

## Verification

- `GeometryFixtures.swift` compiles under Swift 6 strict concurrency and is included in the Xcode test target.
- The existing focused AX suite remains 17 tests and the integrated ScreenKit suite passes 12/12 with the reusable fixtures and subsequent geometry hardening; the final project suite passes 45/45.

## Assumptions and gaps

- Display IDs in fixtures are the literal IDs from the approved current-machine evidence; persistence across reconnect/dock/reboot remains out of scope.
- Negative-origin fixtures are deterministic point-coordinate checks, not a physical multi-display human verification.
- AX identity lifetime against Window Action/Undo semantics remains a later integration check; these fakes intentionally expose only the agreed system seam.

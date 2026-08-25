# F1-05 — Screen geometry evidence

Status: `PASS — MODULE INTEGRATED AND HARDENED`

## Delivered Interface

- `ScreenGeometryProviding.displays()` returns one fresh `DisplayTopologySnapshot` containing
  all physical Displays and the explicit primary `DisplayID` from that same capture.
- Each `DisplaySnapshot` preserves the topology-scoped public display identity, global `frame`, `visibleFrame`, backing scale, safe-area insets and auxiliary top areas.
- Available Displays have deterministic spatial ordering: global `minX`, then `minY`, then
  display identifier. Primary status is not inferred from that order.
- Empty topology, unavailable identity, duplicate identity, missing/multiple primary markers,
  invalid frame, invalid visible frame, invalid scale and Adapter failure are typed unavailable
  states. Invalid candidates fail the whole snapshot; callers never receive a partial topology.
- `ScreenGeometryService()` uses a production `NSScreen` Adapter. Tests use an in-memory Adapter at the same seam.

## Validation and Notch Trigger policy

- Frames and visible frames must be finite and non-empty. Geometry may exceed a Display edge by at most 0.5 logical point to absorb public-API rounding drift; accepted `visibleFrame` values are intersected with `frame` before publication. A 0.75-point literal overshoot is rejected, keeping the tolerance below the project's one-point acceptance threshold.
- Backing scale must be finite and positive.
- A Notch is inferred only when finite, bounded safe-area insets and two auxiliary top areas form a positive gap spanning the Display's top center. The same 0.5-point tolerance applies to auxiliary containment, top alignment and the center-gap comparison; accepted auxiliary rectangles are clamped before deriving regions.
- The inferred Notch Region is the validated public auxiliary gap with `safeAreaInsets.top` height. Its trigger expands 32 pt horizontally and 20 pt downward, matching the Sprint 0 spike, then intersects the Display frame.
- Every other valid Display uses a 16 pt-high top-center fallback, at most 180 pt or 25% of Display width. The fallback also intersects the Display frame.
- Trigger classification is typed as `notch` or `topCenterFallback`; both the inferred Notch Region and final trigger region are observable in the snapshot.

## TDD evidence

Tests observe only `ScreenGeometryProviding.displays()` results. Expected geometry uses independent literals from the approved fixtures and hardware evidence.

1. Enumeration/order red: the first test did not compile because the ScreenKit Interface did not exist. Green: the Interface and in-memory Adapter type-checked, and the executable harness later confirmed the ordering test passes.
2. Negative-origin/fallback red: expected `(-1050, 1064, 180, 16)` but the tracer implementation returned the whole `(-1920, 0, 1920, 1080)` frame. Green: 2/2 tests passed after adding the bounded fallback.
3. Validation red: six literal cases returned available data for empty/non-finite frames, invalid/out-of-frame visible frames and zero/NaN scale. Green: 3/3 tests passed with typed failures.
4. Notch red: the built-in fixture returned fallback `(645, 940, 180, 16)` instead of Notch `(646, 924, 179, 32)` and trigger `(614, 904, 243, 52)`. Green: 4/4 passed after validating and resolving the auxiliary gap.
5. Identity red: the duplicate-identity test did not compile because no typed duplicate failure existed. Green: 5/5 passed after deterministic duplicate detection.
6. Final standalone XCTest bundle: 7/7 passed, zero failures. It additionally covers no Displays, missing identity, system unavailability and invalid auxiliary-gap fallback.
7. Tolerance hardening red: a harmless 0.25-point `visibleFrame` overshoot was rejected and a 0.25-point auxiliary/top-center drift fell back to non-Notch. Green: both are accepted, their published/derived regions are clamped inside the Display, while 0.75-point overshoot/alignment drift remains rejected or falls back.
8. Null identity hardening red: raw ID `0` produced an available snapshot. Green: both the public seam and `NSScreen` Adapter map `kCGNullDirectDisplay` to `displayIdentityUnavailable`.
9. Atomic-primary hardening red: the Interface returned a bare sorted array and candidates had
   no explicit primary marker. Green: the result now returns sorted Displays plus the primary
   `DisplayID`; fixtures prove a primary Display remains primary after sorting moves it away
   from index zero. Missing and multiple primary markers are rejected with typed failures.

ScreenKit is integrated into the Xcode app and test targets. The original F1-05 narrow
integrated run passed 12/12 and its project suite passed 45/45. The atomic-primary hardening
now passes 13/13 integrated ScreenKit tests under Swift 6 complete strict concurrency; the
combined ScreenKit/GeometryKit selection passes 20/20.

## Current-machine public-API run — 2026-08-24

A temporary executable imported the production module, constructed `ScreenGeometryService()`, called `displays()`, and printed only geometry values. It ran outside the sandbox so `NSScreen.screens` could access WindowServer.

| Display | Public ID | Frame | Visible frame | Scale | Safe/auxiliary result | Classification / region |
|---|---:|---|---|---:|---|---|
| HKC external, current main | 2 | `(0, 0, 1920, 1080)` | `(0, 0, 1920, 1050)` | 1 | top 0; no auxiliary areas | fallback `(870, 1064, 180, 16)` |
| Built-in Retina | 1 | `(1920, 124, 1470, 956)` | `(1920, 124, 1470, 924)` | 2 | top 32; left `(1920, 1048, 646, 32)`; right `(2745, 1048, 645, 32)` | Notch `(2566, 1048, 179, 32)`; trigger `(2534, 1028, 243, 52)` |

The runtime returned two Displays in deterministic spatial order, retained both global origins,
and reported `triggerWithinFrame=true` for each. The system Adapter now reads
`NSScreen.screens` once, marks element zero as primary in that capture, and only then allows the
service to sort geometry.

## Assumptions and remaining checks

- `NSScreenNumber` supplies a topology-scoped Core Graphics display identity for the active topology; zero is rejected as `kCGNullDirectDisplay`. W2-08 must not correlate a Display across disconnect/reconnect by this ID. Any durable reconnect identity requires a separately validated strategy.
- The current two-Display arrangement has no negative origin. Negative `x` and `y` preservation is covered by in-memory fixtures; a physical negative-origin arrangement remains a human multi-display check.
- Dock/menu-bar variants, attach/detach observation and screen-change invalidation belong to
  later geometry/change-observer tasks. This Interface deliberately captures fresh values
  rather than caching them or performing a second screen read for primary status.

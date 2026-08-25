# P0-05 — Notch and multi-display geometry evidence

Status: `PARTIAL PASS — LIVE NOTCH + HKC NON-NOTCH + MIXED SCALE`

## Environment

- Tester/date: Codex automated read-only run with user authorization — 2026-08-24.
- macOS build: macOS 26.5.2 (25F84), arm64.
- Hardware/displays: MacBook Air (Apple M2), built-in Retina Display plus HKC-MB24V9.
- Current arrangement: HKC is the main Display at `(0, 0)`; the built-in Display is to its right at `(1920, 124)`. No Display currently has a negative origin.
- Current reserved-area observation: HKC `frame.maxY - visibleFrame.maxY = 30 pt`; built-in `frame.maxY - visibleFrame.maxY = 32 pt`. This run did not change or exhaustively classify Dock/menu bar settings.
- Prototype SHA-256: `268de8e8bd062640f9e0c8d14658908b1d8735132e8162fd35782cd5c14e19e7`.
- Privacy: output contains only public Display model/geometry data. No window titles, screen contents, screenshots, keystrokes, or document data were collected.

## Reproduction and actual result

```sh
xcrun swiftc -module-cache-path /private/tmp/mymacx-p0-05-module-cache \
  -typecheck prototypes/notch-geometry-poc.swift
xcrun swift -module-cache-path /private/tmp/mymacx-p0-05-module-cache \
  prototypes/notch-geometry-poc.swift --self-test
xcrun swift -module-cache-path /private/tmp/mymacx-p0-05-module-cache \
  prototypes/notch-geometry-poc.swift --inspect
```

- Type-check: pass.
- Self-test: 4/4 fixtures pass; both negative-x and negative-y fallbacks remain inside their fixture frame, the negative-origin Notch candidate remains inside its frame, and an invalid auxiliary-area gap falls back safely.
- Live inspect outside the sandbox: two Displays found; mixed backing scale factors `true`; negative physical origin `false`; both trigger regions are contained by their owning Display frame.
- A sandboxed inventory was inconsistent (`Screens: 2` on one run and `Screens: 0` on another). The outside-sandbox read-only run above is the authoritative hardware observation.

## Redacted live geometry

Display IDs are omitted because they are session-local and unnecessary for the finding.

### HKC-MB24V9 — external, main, non-Notch

- `frame`: `(0, 0, 1920, 1080)` pt.
- `visibleFrame`: `(0, 0, 1920, 1050)` pt.
- `backingScaleFactor`: `1.0`.
- display mode: `1920×1080` points, `1920×1080` pixels.
- `safeAreaInsets`: all zero.
- auxiliary top areas: both `nil`.
- classification: `top-center-fallback`.
- Trigger Region: `(870, 1064, 180, 16)` pt.
- `triggerWithinScreen`: `true`.

### Built-in Retina Display — Notch, right of main

- `frame`: `(1920, 124, 1470, 956)` pt.
- `visibleFrame`: `(1920, 124, 1470, 924)` pt.
- `backingScaleFactor`: `2.0`.
- display mode: `1470×956` points, `2940×1912` pixels.
- `safeAreaInsets.top`: `32` pt.
- auxiliary left area: `(1920, 1048, 646, 32)` pt.
- auxiliary right area: `(2745, 1048, 645, 32)` pt.
- inferred Notch Region: `(2566, 1048, 179, 32)` pt.
- Trigger Region: `(2534, 1028, 243, 52)` pt.
- `triggerWithinScreen`: `true`.
- topology relative to main: `right,y-overlap`.

## Automated fixture evidence

| Fixture | Classification | Trigger Region | Contained | Result |
|---|---|---:|---:|---:|
| Negative x, non-Notch frame `(-1920, 0, 1920, 1080)` | top-center fallback | `(-1050, 1064, 180, 16)` | Yes | Pass |
| Negative y, non-Notch frame `(320, -1080, 1920, 1080)` | top-center fallback | `(1190, -16, 180, 16)` | Yes | Pass |
| Negative origin, valid auxiliary areas | Notch candidate | `(-856, 704, 243, 52)` | Yes | Pass |
| Invalid/overlapping auxiliary gap | top-center fallback | `(410, 684, 180, 16)` | Yes | Pass |

These fixtures make the point-coordinate fallback calculation regression-checkable. They do not count as a physical negative-origin hardware pass.

## Geometry matrix

| Scenario | frame/visibleFrame valid | Safe/auxiliary areas | Trigger inside screen | Origin/topology observation | Result |
|---|---|---|---|---|---|
| Built-in Display with Notch | Yes | 32 pt + both auxiliary areas | Yes | Non-zero origin `(1920, 124)`; right of main | ☒ Pass ☐ Fail |
| HKC Display without Notch | Yes | Zero / `nil`; fallback used | Yes | Main at `(0, 0)` | ☒ Pass ☐ Fail |
| Current two-Display topology | Yes | Per-Display values retained | Yes on both | Right/y-overlap; no coordinate normalization applied | ☒ Pass ☐ Fail |
| Mixed scaling | Yes | Per-Display values retained | Yes on both | Live `1.0×` + `2.0×`; AppKit frames stay in points | ☒ Pass ☐ Fail |
| Physical Display at negative origin | Not observed | Fixture only | Fixture pass | Current arrangement has no negative origin | ☐ Pass ☐ Fail |
| Dock left/right/bottom + auto-hide | Current geometry only | Not varied | Current triggers pass | Variants not exercised | ☐ Pass ☐ Fail |
| Display attach/detach | Not exercised | Not exercised | Not exercised | Requires manual topology transition | ☐ Pass ☐ Fail |

## F1-05 implications

- Public `NSScreen` data is sufficient to inventory each current Display's `frame`, `visibleFrame`, backing scale, safe area, auxiliary top areas, display mode, and global AppKit origin.
- `ScreenGeometryService` must preserve point-space geometry and backing scale as separate facts; the live matrix contains both `1.0×` and `2.0×` Displays.
- The trigger resolver must calculate in each Display's global AppKit frame and clamp by that same frame. It must not normalize every Display to `(0, 0)`.
- F1-05/F1-07 now provide the production ScreenKit Adapter plus deterministic topology fixtures. Screen-parameter change observation and reconnect handling remain W2-08 work; this throwaway probe remains hardware evidence rather than production code.

## Overlay/focus follow-up

- [ ] Non-activating panel remains non-key/non-main.
- [ ] Active app and Captured Window stay unchanged while chooser appears.
- [ ] Cross-display drag relocates or closes the overlay deterministically.
- [ ] Mouse-up outside a Layout Region makes no window mutation.

## Verdict

- P0-05: `☐ PASS ☒ CONDITIONAL ☐ FAIL`.
- Passed on live hardware: built-in Notch inference, HKC non-Notch fallback, current two-Display topology, mixed `1.0×/2.0×` scaling, and trigger containment.
- Remaining conditions: physical negative-origin arrangement, Dock/menu bar variants, attach/detach, and actual non-activating overlay/focus behavior.
- Reviewer/date:

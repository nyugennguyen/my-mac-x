# N4-08 — Cross-Display drag

Status: `COMPOSITION INTEGRATED — HUMAN GATE PENDING`

## Scope and Interface

`CrossDisplayDragCoordinator.update(trigger:resolution:topology:chooserSize:preview:)` is the
pure cross-Display presentation seam. It consumes a topology-scoped Trigger Dwell transition,
the current `NotchTriggerResolution`, one versioned atomic ScreenKit topology, the requested
Layout Chooser size, and the currently requested Placement Preview. It returns typed
presentation work:

- `present` for first entry into a Notch Trigger;
- `replace` to dismiss the complete previous chooser/preview pair and present the new Display
  target atomically;
- `updatePreview` when the Display and chooser are stable, avoiding chooser recreation/flicker;
- `dismiss` on trigger exit, Display detach, unavailable topology, or invalid chooser geometry;
- `unchanged` when no rendering work is necessary.

TriggerDwellKit remains the sole owner of dwell and exit hysteresis. A missing Dwell transition
does not dismiss anything. When the old Display deactivates while the current resolution is
inside a different Display's trigger, the coordinator retains the old surface until the new
Display emits activation, then replaces the complete chooser/preview pair atomically. If that
pending entry is abandoned, ordinary deactivation dismisses the old surface.

Every Dwell transition and surface target carries its `DisplayTopologyGeneration`. The
coordinator never correlates a raw `DisplayID` across generations. A topology generation change
dismisses the old surface until a freshly generation-scoped activation arrives, even if macOS
reuses the same raw Display identity. Layout Chooser frames are anchored to the target Display's
trigger and fitted wholly inside its current `visibleFrame`.

The coordinator admits a supplied Placement Preview only when its Display identity matches the
current pointer target and its frame stays within that Display's usable area to the project's
one-logical-point tolerance. A stale preview from the previous Display or a materially off-screen
preview is omitted, so it cannot be forwarded to the renderer during handoff.

## TDD and automated evidence

The retained Interface test first failed because `CrossDisplayDragCoordinator` did not exist.
After the first green pass, a focused red/green slice changed same-Display preview delivery from a
full surface replacement to `updatePreview`, preserving the Layout Chooser and avoiding flicker.
A design-review red/green slice then moved exit authority from raw pointer hit-testing to
generation-scoped Trigger Dwell transitions, proving that the cross-Display Module cannot bypass
N4-03 hysteresis.

Focused command:

```text
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/mymacx-n408-derived \
  -only-testing:MyMacXTests/CrossDisplayDragCoordinatorTests
```

Result:

```text
Test Suite 'CrossDisplayDragCoordinatorTests' passed
Executed 8 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

The full Debug suite also succeeded after target integration: 285 tests executed, 2 existing
hardware-gated skips, and no test failures.

The retained specification is
`Tests/MyMacXTests/CrossDisplayKit/CrossDisplayDragCoordinatorTests.swift`.

## Composition evidence

### WindowIntent.preview target Display extension

`WindowIntent.preview` now accepts an optional `targetDisplay: DisplayID?` parameter. When
provided, `WindowActionEngine.compile()` uses that Display's topology for frame calculation
instead of the focused window's current Display. The parameter defaults to `nil`, preserving
backward compatibility for non-pointer preview callers.

`SnapInteractionStateMachine.preview()` passes the trigger-activated `DisplayID` from its
`.choosing`/`.previewed` state through to `WindowIntent.preview` as `targetDisplay`, so
cross-Display previews calculate frames on the correct Display.

### AppShell composition wiring

`CrossDisplayDragComposition` (`Sources/AppShell/CrossDisplayDragComposition.swift`) is a
`@MainActor` class that wires:

1. **ScreenKit topology observations** → `DisplayTopologyObserver.updates()` feeds
   `DisplayTopologyState` into `CrossDisplayDragCoordinator.update()`.
2. **TriggerDwellEngine events** → wrapped as `CrossDisplayTriggerEvent` with the current
   topology generation, then fed to the coordinator.
3. **CrossDisplayDragCoordinator transitions** → drive `OverlayCoordinator` presentation:
   - `present` → `presentChooser` + optional `showPreview`
   - `updatePreview` → `showPreview` only (chooser preserved)
   - `replace` → `dismiss` then `presentChooser` + optional `showPreview`
   - `dismiss` → `dismiss`
   - `unchanged` → no-op

The composition is instantiated in `MyMacXApplication.ApplicationDelegate.init()` alongside
the existing hotkey runtime and lifecycle coordinator.

### Integration tests

`Tests/MyMacXTests/CrossDisplayKit/CrossDisplayDragCompositionTests.swift` proves:

- **Topology change during cross-Display drag**: when the topology generation changes, the
  coordinator emits a `dismiss` (not `replace`), and a fresh generation-scoped activation
  produces a new `present`.
- **Atomic replace semantics**: old-Display deactivation with pointer inside new trigger keeps
  the old surface; new-Display activation emits one `replace` that dismisses the old
  chooser/preview pair before presenting the new target.
- **WindowIntent.preview carries targetDisplay**: the enum case correctly stores and retrieves
  the optional `DisplayID` parameter.
- **Default nil targetDisplay**: backward compatibility for non-pointer callers.

## Fixtures and topology

- Mixed-scale handoff: a 1.25x external Display at negative origin
  `(-1600, -200, 1200, 950)` and a 2x built-in Display at `(0, 0, 1000, 800)`.
- Shared boundary: the exact `x = 0` edge belongs to the right Display under the same half-open
  frame rule used by `NotchTriggerEngine`.
- Reorder: the same raw Display ID moves from `(0, 0)` at generation 7 to `(-1200, -300)` at
  generation 8; the old topology-scoped placement is dismissed and cannot reappear until a
  fresh generation-8 activation arrives.
- Detach/unavailable: the active negative-origin Display disappears, and a separate active
  surface receives an unavailable topology state; both produce explicit dismissal.
- Dwell handoff: old-Display deactivation plus a current resolution inside the new trigger keeps
  the old surface temporarily; new-Display activation emits one atomic replacement. A missing
  Dwell event does not bypass exit hysteresis.
- Off-screen safety: a requested `640 x 480` chooser is fitted to a `320 x 220` visible frame,
  while a materially off-screen preview is omitted.

All fixtures use global AppKit logical points. Backing scale is carried as Display metadata and
does not alter hit testing or chooser geometry. The tests record no raw pointer stream, window or
document title, Accessibility object, screenshot, clipboard content, or typed text.

## Remaining gaps

- N4-01, N4-03, and N4-07 remain open dependencies. This evidence therefore does not mark N4-08
  `DONE` or claim an end-to-end drag.
- Physical mixed-scale dragging, Display attach/detach/reorder during a real drag, focus behavior,
  and confirmation that no AppKit panel is orphaned are human-only checks in the Sprint 4 matrix.
  No hardware result is inferred from automated fixtures.

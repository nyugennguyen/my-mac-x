---
status: proposed
---

# Edge Snap is a Trigger, not a Window Action

Edge Snap joins Notch Snap as a second pointer trigger for window placement in My Mac X. Edge Snap is strictly an input Trigger rather than a Window Action: it detects drag gestures, resolves perimeter zones, evaluates seam crossing speed, and emits `WindowIntent` values across the existing deep `WindowActionPerforming.perform(_:)` Interface. Triggers never touch Accessibility APIs and never compute window frames.

## Context

My Mac X v1 introduced Notch Snap as its first pointer trigger alongside hotkeys, menu bar actions, and Super Mode. v1.x adds Edge Snap, allowing users to drag a window to display edges or corners to trigger snap placements.

Window management utilities often couple edge detection, multi-display boundary checks, Accessibility window positioning, and layout calculations into monolithic drag handlers. In My Mac X, all window placement is governed by strict domain invariants:
- A `Window Action` targets one `Captured Window`. Focus changes during execution never retarget it.
- `Placement Preview` never mutates a window or writes history.
- `Maximize` fills the current Display's usable area; it is distinct from `Native Full Screen`.
- Commit succeeds only after Accessibility read-back verifies the resulting `Settled Frame`.
- Undo restores the `Window Snapshot` recorded before the committed action.
- Failed actions preserve or best-effort restore the prior frame.

## Decision

1. **Trigger Boundary**: Edge Snap is an external client of the Window Action pipeline. It emits `WindowIntent.preview`, `WindowIntent.commit`, and `WindowIntent.cancel` targeting one `Captured Window`, exactly like Notch Snap, hotkeys, and Super Mode.
2. **No Accessibility in Triggers**: Edge Snap monitors pointer movement and window drags via event taps and window-server frame sampling (`CGWindowListCopyWindowInfo`). It never calls Accessibility APIs (`AXUIElement`) directly.
3. **No Frame Calculation in Triggers**: Triggers resolve a pointer drag to an `ActionID` or candidate `Layout Region`. Layout geometry calculation remains private to `LayoutKit` and `GeometryKit` behind `WindowActionKit`.
4. **Pure Swift Geometry in TriggerGeometryKit**: Perimeter zone mapping (8 zones, edge subdivision 1–4 areas, corner bands), pointer trail sampling, and velocity-based `Seam Gating` reside in `TriggerGeometryKit` as pure Swift with no AppKit or Accessibility dependencies.
5. **State Coordination**: The interaction lifecycle of a `Snap Run` (tracking, preview dwell, commit on drop, cancellation) reuses `SnapInteractionKit`'s state machine to serialize inputs and coordinate with `OverlayKit` for non-mutating `Placement Preview`.

## Considered Options

- **Autonomous Edge Snap Subsystem**: Calculate layout frames directly in the drag monitor and mutate the window via Accessibility. Rejected because it would bypass `WindowActionPerforming`, duplicate layout logic, risk desynchronization, bypass undo history snapshots, and violate the architectural rule that triggers never touch Accessibility.
- **Extend Notch Chooser Pipeline**: Treat edge snapping as a variation of the Notch Trigger. Rejected because the Notch Trigger opens a transient `Layout Chooser` overlay for interactive selection, whereas Edge Snap maps perimeter zones directly to candidate actions without displaying a picker grid.
- **Trigger-as-Client Pipeline (Selected)**: Treat Edge Snap as an independent trigger that feeds `WindowIntent` into `WindowActionPerforming`. Preserves the single-seam architecture, reuses the tested action pipeline, and ensures unified rollback and history semantics.

## Consequences

- **Conformance for v1.x-1 (Rules Sprint)**: `TriggerGeometryKit` will implement zone geometry resolution, pointer trail tracking, and `Seam Gating` as pure Swift functions tested exhaustively at the module interface with zero system dependencies, AppKit window references, or side effects.
- **Conformance for v1.x-2 (Runtime Sprint)**: Event-tap callbacks in `PointerDragKit` enqueue minimal data and return immediately. Off-thread target resolution uses bounded timeouts (~0.3 s) and generational cancellation. All preview and commit actions pass through `WindowActionPerforming.perform(_:)`. Commit succeeds only when Accessibility read-back verifies the resulting `Settled Frame`. System-tiling coexistence must stand down visibly when native macOS 15 tiling owns an edge.
- **Invariants Preserved**: The single-captured-window guarantee, preview non-mutation, Maximize distinction from Native Full Screen, and Window Snapshot undo restoration apply identically to Edge Snap as to all existing triggers.

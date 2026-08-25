# Sprint 2 Window Action Engine

This document fixes the implementation shape for Sprint 2 under
[ADR-0003](../adr/0003-intent-driven-window-action-module.md). It does not widen the external
Interface in [window-action-interface.md](window-action-interface.md).

## Selected shape

`WindowActionEngine` is one deep actor-backed Module implementing
`WindowActionPerforming.perform(_:)`. Pointer, hotkey, menu bar and Super Mode callers never
call Accessibility, screen topology, layout calculation, coordinate conversion, history or
cycle state directly.

An `ActionID` resolves to a closed, data-driven internal `ActionDefinition`. The engine
captures one Eligible Window and compiles that definition plus one atomic display topology
into an immutable `PlacementPlan`. The plan represents one transition for one Captured
Window; Sprint 2 does not introduce a general transaction graph or multi-window program.

## Execution order

```text
resolve intent and ActionID
→ capture or recover the exact Captured Window
→ capture fresh atomic display topology
→ compile one immutable plan using pure layout and coordinate math
→ stage Window Snapshot
→ perform bounded Accessibility mutation
→ read back and verify actual frame
→ commit history/cycle state or best-effort rollback
→ map to WindowActionResult
```

Preview stops after plan compilation. It never mutates Accessibility state or history.

## Internal ownership

- `LayoutKit`: normalized Layout definitions, deterministic layout calculation, gap/padding,
  scale-aware rounding and visible-frame constraints.
- `CoordinateConverter`: typed conversion between canonical global AppKit logical points and
  Accessibility's top-left coordinate space. Negative origins and mixed scale are inputs,
  not exceptional cases.
- `WindowMutationModule`: one confined Accessibility Adapter for inspect/write/read-back,
  bounded retry and rollback. The same Adapter owns opaque `WindowIdentity` resolution.
- `WindowHistory`: bounded entries keyed by exact `WindowIdentity`, exact opaque Undo token,
  Restore anchor and per-window Cycle Group cursor.
- `WindowActionEngine`: intent routing, preview ledger, topology generation, per-window
  serialization and public result mapping.

Layout and conversion are in-process implementations. Accessibility, physical Display
topology, history persistence and monotonic time are internal seams with production and test
Adapters. No AX object, raw AX error, title, typed text or document metadata crosses a seam.

## Preview and topology policy

The first preview binds its `InteractionID` to one Captured Window, one topology generation
and one catalog snapshot. Later hover calculations reuse that binding. Older calculations
complete as `superseded`. `commitPreview` consumes the latest accepted plan and never falls
back to a newly Focused Window.

If the physical Display topology changes before commit, the preview expires with
`previewMissingOrExpired`; the caller must request a fresh preview. Direct commits and Undo
always plan against fresh topology. A topology-scoped `DisplayID` is never persisted or used
to correlate a Display across disconnect/reconnect.

## Mutation and history invariants

- A direct commit captures focus exactly once.
- A Window Snapshot is staged before the first mutation.
- Mutation and read-back have bounded attempts and a finite deadline.
- Success requires verified read-back within the one-logical-point acceptance budget.
- Stable application clamping may succeed with `constrainedByApplication` and the actual
  frame; an invalid or unstable result rolls back.
- History and Cycle Group state advance only after verified success.
- Undo targets an exact entry/window, never a process ID alone.
- Actions for one Captured Window are serialized; different windows have no ordering promise.
- Native Full Screen uses a separate async observer/deadline strategy and must not claim a
  state that public APIs cannot verify.

## Agreed test surfaces

Tests observe behavior at these Module Interfaces:

1. `WindowActionPerforming.perform(_:)` for capture stability, preview purity, commit,
   supersession, topology invalidation, Undo, Restore, cycles and public failures.
2. The pure `LayoutKit` Interface for independently worked geometry examples and generated
   boundary properties.
3. The typed coordinate-conversion Interface for round trips across negative origins and
   mixed-scale topologies.
4. The Accessibility mutation Adapter contract with the system and scripted Adapters for
   write ordering, bounded retry, read-back and rollback.

Tests do not reach private phase functions or inspect internal ledgers.

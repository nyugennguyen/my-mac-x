---
status: accepted
---

# Use one intent-driven Window Action Interface

All pointer, hotkey, menu bar and Super Mode callers cross one deep Interface, `WindowActionPerforming.perform(_:)`, using intents for preview, preview commit/cancel, direct commit and undo. The Module captures window identity once and hides action lookup, screen selection, layout calculation, history, Accessibility mutation, read-back, retry and rollback; Accessibility, display topology, clock and persistence remain internal seams with production and test Adapters.

## Considered Options

- A one-shot `perform(ActionID)` Interface was smaller but split preview from commit and could let the two paths disagree about window identity or geometry.
- A declarative transaction DAG enabled batch tiling but exposed versioning, validation and migration complexity before v1 had a real caller for it.
- The selected hybrid retains a single entry point and common one-line calls while representing the Notch preview transaction and exact Undo token explicitly.

## Consequences

Action discovery is a separate read-only Module; new Layouts remain data rather than new intent cases. Batch programs stay internal or post-v1 until at least one real caller justifies expanding the Interface.

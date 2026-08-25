# W2-11 — Deterministic layout property tests

## Scope

`W2_11LayoutPropertyTests` exercises the pure Sprint 2 geometry seams with a fixed
`0x57211` seed. Each failing assertion includes its case index, so a failure is
reproducible without recording window titles, application metadata, or other user data.

The generator runs 240 configurations. Every case combines:

- a three-Display mixed-scale topology at 1x, 1.25x and 2x;
- reordered topology input and an explicit primary Display identity;
- negative origins and deterministic vertical offsets;
- one of all nine built-in Layout Regions;
- seeded gap, outer padding and optional minimum size;
- a seeded Window frame and left/right physical-Display move.

## Invariants

For every generated configuration, the test verifies:

1. the Layout plan is finite, non-empty and contained in the selected visible frame;
2. AppKit → AX → AppKit conversion round-trips within `1e-9` logical points;
3. repeated Display move planning with identical input is deterministic;
4. the moved frame is finite, non-empty and contained in the destination visible frame;
5. the destination identity exists in the same captured topology.

## Verification

On 2026-08-24, the integrated Xcode test passed on the current Apple Silicon Mac:

- XCTest methods: 1/1;
- generated configurations: 240/240;
- invariant failures: 0;
- project plist lint: pass.


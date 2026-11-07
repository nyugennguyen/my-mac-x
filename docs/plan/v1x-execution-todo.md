# v1.x Execution To-Do — Edge Snap + Settings Polish

Live orchestration tracker for [mymacx-v1x-combined-plan.md](./mymacx-v1x-combined-plan.md). Branch: `mymacx-v1x`. Orchestrator updates this file at wave boundaries.

Legend: ⏳ pending · 🔨 in progress · ✅ done · ⛔ blocked (needs human)

## Wave 1 — Phase A scoping (Track A) + v1.x-P1 (Track B)

| ID | Task | Agent | Output | Status |
|---|---|---|---|---|
| A1 | Feasibility research (event taps, window-server sampling, macOS 15 tiling coexistence, pointer velocity) | `dev-research` | `docs/research/screen-edge-snap-feasibility.md` (8f4d4fb) | ✅ |
| A2 | Behavioral spec extraction from vorssaint-utils tests (clean-room posture) | `dev-spec` | `docs/research/edge-snap-behavior-spec.md` (21fc5d2) | ✅ |
| A3 | Domain pass: CONTEXT.md terms + ADR draft "Edge Snap is a Trigger, not a Window Action" | `dev-domain` | `CONTEXT.md`, `docs/adr/0004-…` (1c26b0e) | ✅ |
| B-P1 | Token layer & primitives (SettingsCard, SettingsRow, Keycap, IconTile, StatusDot, CapsuleBadge, ShortcutRecorderButton) — TDD | `dev-tokens` | `Sources/AppShell/` + `Tests/MyMacXTests/AppShell/` | 🔨 |
| A4 | License decision gate | orchestrator → human | `docs/plan/v1x-license-gate-brief.md` | ✅ **DECIDED: clean-room reimplementation** (2026-11-07) |

## Wave 2 — v1.x-1 rules sprint + tester + P2

| ID | Task | Agent | Status |
|---|---|---|---|
| A-R1 | v1.x-1 rules sprint: TriggerGeometryKit zone geometry (fixed 8 zones first) + seam gating + velocity trail (S/Z cases); PointerDragKit drag-classification rule + `PointerPlatformSignal` timestamp payload (D cases). TDD, case-mapped tests from the A2 spec. Clean-room: implement ONLY from `docs/research/edge-snap-behavior-spec.md`; never open the vorssaint clone. | `dev-rules` | ⏳ |
| B-P2 | Settings shell upgrade: sidebar search + section anchors; Super Mode keycap/recorder rows replace key-code pickers; hotkey child-window visual unification. Keep `NavigationSplitView` shell. Runs in a worktree to avoid pbxproj contention with A-R1. | `dev-p2` | ⏳ |
| T1 | Tester pass: review wave 1 (docs + B-P1 diff) vs plan + AGENT.MD; run full test suite. | `agy-tester` | ⏳ |

## Decisions recorded (following plan recommendations; human may override)

- Fixed 8 zones first (Z-01/Z-02); remappable 1–4-area edge map deferred to v1.x-3 with the zone-map picker.
- Top-edge 1 pt coordinate rewrite trick (D-11) and Stage Manager strip reservation: **deferred from first cut** (plan candidates).
- Scratch-frame coercion (A-06): **held in reserve** — the forced robustness slice if clamped apps misbehave in v1.x-2.
- `PointerPlatformSignal` gains `timestamp: UInt64` (A1 finding) — approved for v1.x-1.

## Later waves (per plan)

- v1.x-1 Rules sprint: zone geometry, seam gating, velocity trail, drag classification (pure Swift) — **after license gate**.
- v1.x-2 Runtime sprint: event-tap wiring, off-thread target resolution, preview→commit, undo, system-tiling coexistence gate.
- v1.x-3 UX + hardening: zone-map picker (shared Track A/B component), per-zone disable, persistence migration, localization; human gates.
- v1.x-P3 Feature screens: Layout Library, Display Profiles, App Rules, copy fixes ("Stable Display ID", "Layout Region", "Native Full Screen" verbatim; Maximize ≠ Full Screen).

## Conventions for agents

- Git: stage only your own files (`git add <paths>`; never `-A`/`.`/`-a`). User WIP not to touch: `AGENT.MD`, `Sources/AXWindowKit/SystemWindowAdapter.swift`, untracked `skills/`, `docs/sprint-8/evidence/human-runs/`.
- Validation: narrowest `xcodebuild` build/test with signing disabled (see AGENT.MD); full suite before a task is marked done.
- Report: changed files, evidence (commands + results), remaining risk, open decisions.

## Log

- 2026-11-07: branch `mymacx-v1x` created from `dev`; plan committed as `docs/plan/mymacx-v1x-combined-plan.md`; OpenDesign prototype snapshotted to `docs/design/mymacx-settings-prototype.html` (visual source of truth for Track B). Wave 1 launched in Herdr workspace `mymacx-v1x`.

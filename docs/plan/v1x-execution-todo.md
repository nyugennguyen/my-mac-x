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
| A-R1 | v1.x-1 rules sprint: TriggerGeometryKit zone geometry (fixed 8 zones first) + seam gating + velocity trail (S/Z cases); PointerDragKit drag-classification rule + `PointerPlatformSignal` timestamp payload (D cases). TDD, case-mapped tests from the A2 spec. Clean-room: implement ONLY from `docs/research/edge-snap-behavior-spec.md`; never open the vorssaint clone. | `dev-rules` | ✅ d86c30b + fix round 4691c73 (2 majors + minor/nits from T1 turn 2); merged c702d0f |
| B-P2 | Settings shell upgrade: sidebar search + section anchors; Super Mode keycap/recorder rows replace key-code pickers; hotkey child-window visual unification. Keep `NavigationSplitView` shell. | `dev-p2` | ✅ d9b1ed0 + P1 fix batch 4aedf32 (tester findings 1–3, 5–7, TDD red-first) |
| T1 | Tester pass: review wave 1 (docs + B-P1 diff) vs plan + AGENT.MD; run full test suite. | `dev-tester` | ✅ turns 1–2 done (wave-1 verdict + rules-branch audit); turn 3 = integration review of merge c702d0f (incl. orchestrator's pbxproj conflict resolution) |
| INT | Integration merge `mymacx-v1x-rules` → `mymacx-v1x` (pbxproj ID collision 82–89 renumbered to 90–97 by orchestrator); full suite on merged tree: **513 tests / 0 failures** | orchestrator | ✅ c702d0f |

## Decisions recorded (following plan recommendations; human may override)

- Fixed 8 zones first (Z-01/Z-02); remappable 1–4-area edge map deferred to v1.x-3 with the zone-map picker.
- Top-edge 1 pt coordinate rewrite trick (D-11) and Stage Manager strip reservation: **deferred from first cut** (plan candidates).
- Scratch-frame coercion (A-06): **held in reserve** — the forced robustness slice if clamped apps misbehave in v1.x-2.
- `PointerPlatformSignal` gains `timestamp: UInt64` (A1 finding) — approved for v1.x-1.

## Wave 3 — v1.x-2 runtime sprint + v1.x-P3 feature screens

| ID | Task | Agent | Status |
|---|---|---|---|
| A-R2 | v1.x-2 runtime: event-tap wiring (enqueue-minimal), off-thread AX resolution (280 ms bounded + generational cancellation), Snap Run transaction → WindowActionPerforming, overlay preview, undo/history, lenient acceptance (A-01..A-05), tiling coexistence gate (fail visible, nil=enabled), AppRuleKit exclusions. WindowActionKit/AXWindowKit/HistoryKit unchanged; A-06/D-11/Z-06 deferred. | `dev-runtime` | ✅ 885d68c (suite 549/0; + `docs/plan/v1x-2-human-verification.md`, human gates explicitly unpassed) |
| B-P3 | Feature screens: Layout Library (notch-glyph-family thumbnails, Split/Merge), Display Profiles (verbatim "Stable Display ID", gap steppers), App Rules (icon rows, bundle-ID entry, Included/Excluded), copy fixes. | `dev-p3` | ✅ 987a365 on `mymacx-v1x-p3` (suite 521/0 in worktree) |
| INT3 | Merge `mymacx-v1x-p3` → `mymacx-v1x` (pbxproj collision 98/99 renumbered to A0/A1); merged suite **559 / 0 failures** | orchestrator | ✅ 0d3b1de |
| T1.4 | Tester wave-3 gate: runtime invariant audit, spec scope check, merge audit, full suite, human-gate readiness | `dev-tester` | ✅ PASS-WITH-FIXES (2 dead-code acceptance paths + doc nit) → hotfix 9925790 (red-green, suite 561/0) |

## Wave 4 — v1.x-3 hardening (final implementation sprint)

| ID | Task | Agent | Status |
|---|---|---|---|
| A/B-P4a | Z-06 persistence: `EdgeSnapZoneConfigurationStore` (compact delta schema, back-compat migration, import/export, DiagnosticsKit anomalies) + picker integration contract | `dev-persist` | ✅ e417498 (suite 584/0; needed 3 continuation nudges — agent kept ending turns mid-background-build) |
| A/B-P4b | Zone-map picker (3×3 miniature, partition editor 1–4 areas/edge, per-zone off, resets, debounced saves) + Z-03/Z-04 partition geometry + tiling stand-down banner | `dev-zone` | ✅ 4e4695b (suite 601/0, single clean turn) |
| T1.5 | Final acceptance gate + whole-program plan checklist | `dev-tester` | ✅ **PASS / PASS** — zero blocker/major/minor; 1 NIT (maintenance: `MacOSSystemTilingPreferencesAdapter` sits in `TriggerGeometryKit` with `import AppKit`; core geometry pure — extract to AppShell in a future pass). Clean-room sweep: zero foreign code. Checklist: every plan item DONE or DEFERRED-WITH-DECISION, **zero MISSING**. Suite 601/0. |

## PROGRAM STATUS: implementation complete (2026-11-08)

All Track A and Track B plan items are delivered and tester-gated (6 gates, all findings fixed with red-first regressions). Deferred-by-decision items: D-11 top-edge rewrite, Stage Manager strip reservation, A-06 scratch-frame coercion (reserve). Remaining: human gates only (see below) + optional Opus integration review (in flight).

## Wave 5 — Independent integration audits + fix round

| ID | Task | Agent | Status |
|---|---|---|---|
| AUD-A | Adversarial correctness & concurrency audit (races, backpressure, invariants, edge-case math) | `audit-a` (Gemini; Opus blocked by weekly quota ~5d) | ✅ SHIP-WITH-FIXES — 1 blocker (cross-app retargeting), 3 majors, 3 minors, 2 nits |
| AUD-B | Persistence/hostile-input, architecture, cross-agent seams, test quality | `audit-b` | ✅ SHIP-WITH-FIXES — 3 majors (master toggle ignored, acceptance policy dead code, migration false quarantine), 2 minors, 4 nits |
| FIX | Consolidated fix round (15 findings) | `dev-fixes` | ✅ 346fc3d (13 fixed incl. additive acceptance seam in `WindowMutationModule` — orchestrator-approved, default-strict; 2 deferred: keycap wrappers still have callers, adapter extraction) |
| INTFIX | Orchestrator integration repairs after ground-truth verification | orchestrator | ✅ 1556f77 — de-recursed `WindowMutationPerforming` defaults (hang), mock witness, zero-timestamp normalization + first-sample seeding (real residual bug in finding #7's fix), test API repair. **Suite: 612 tests / 0 failures** |

Lesson recorded: the audits found real bugs only at seams BETWEEN agents' work (each sprint tested green in isolation); the fix round itself needed ground-truth verification (claimed green while the test target did not compile and one suite hung). Full-suite foreground verification is now the close gate for every round.

Human gates (never self-certified): `docs/plan/v1x-2-human-verification.md` (PZ/SG/Z-09/CA sections), pixel/focus review x7-09/x7-10 vs `docs/design/mymacx-settings-prototype.html`, and `scripts/release/complete-human-gates.sh` for release QA.

Maintenance backlog: extract `MacOSSystemTilingPreferencesAdapter` from `TriggerGeometryKit` to `AppShell` (NIT, keeps the kit 100% pure).

## Later waves (per plan)

- None — all code sprints are complete. Remaining work is human gates (above), the optional Opus integration review, and the maintenance backlog.

## Conventions for agents

- Git: stage only your own files (`git add <paths>`; never `-A`/`.`/`-a`). User WIP not to touch: `AGENT.MD`, `Sources/AXWindowKit/SystemWindowAdapter.swift`, untracked `skills/`, `docs/sprint-8/evidence/human-runs/`.
- Validation: narrowest `xcodebuild` build/test with signing disabled (see AGENT.MD); full suite before a task is marked done.
- Report: changed files, evidence (commands + results), remaining risk, open decisions.

## Log

- 2026-11-07: branch `mymacx-v1x` created from `dev`; plan committed as `docs/plan/mymacx-v1x-combined-plan.md`; OpenDesign prototype snapshotted to `docs/design/mymacx-settings-prototype.html` (visual source of truth for Track B). Wave 1 launched in Herdr workspace `mymacx-v1x`.
- 2026-11-07: Claude quota exhausted mid-wave-1 (agy = Antigravity CLI, Google AI Pro); fleet switched to Gemini 3.8 Flash High (probe-verified separate quota). Parked Opus sessions reserved for post-reset integration review. Wave 1 deliverables A1/A2/A3/B-P1/A4 landed (see table).
- 2026-11-07: license gate DECIDED (human): clean-room reimplementation. Wave 2 launched: `dev-rules` (v1.x-1, worktree `mymacx-v1x-rules`), `dev-p2` (B-P2, main tree), `dev-tester` (T1). T1 returned PASS-WITH-FIXES across the board; fix batch (tester findings 1–3, 5–7) queued to `dev-p2`; finding 4 fixed here.
- 2026-11-07: wave 2 closed (v1.x-1 + B-P2 + both fix rounds merged at c702d0f; integration gate PASS; suite 513/0). Wave 3 launched: `dev-runtime` (v1.x-2, main tree) + `dev-p3` (v1.x-P3, worktree `mymacx-v1x-p3`). Both landed (885d68c, 987a365); merged at 0d3b1de (pbxproj 98/99 → A0/A1); merged suite **559/0**. Tester gate T1.4 running.
- 2026-11-08: wave-3 gate PASS-WITH-FIXES (2 dead acceptance paths in EdgeSnapAcceptancePolicy — raw strings vs canonical ActionID) → hotfix 9925790 (561/0). Wave 4 landed: `dev-persist` e417498 (store + migration; 584/0) and `dev-zone` 4e4695b (zone-map picker + partition map + tiling banner; 601/0). ALL PLAN IMPLEMENTATION IS NOW DELIVERED. Final acceptance gate T1.5 running; Opus integration review armed for quota reset.
- 2026-11-08: T1.5 final gate PASS/PASS — whole-program checklist clean (zero MISSING), clean-room sweep clean, suite 601/0. PROGRAM COMPLETE pending human gates. Fleet parked; Opus integration review remains queued for quota reset.

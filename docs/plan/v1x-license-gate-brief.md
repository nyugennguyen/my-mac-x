# v1.x License Decision Gate — Brief (Task A4)

Status: **DECIDED 2026-11-07 (human) — Option 1: Clean-room reimplementation.** Track A implementation sprints (v1.x-1 onward) are unblocked. Prior art (vorssaint-utils) stays cited as prior art; no code reuse; tests re-derived from `docs/research/edge-snap-behavior-spec.md` (our own re-expression), not from upstream test code. MyMacX license posture unchanged (LICENSE choice remains a separate, future decision).
Prepared: 2026-11-07 by orchestrator, from `docs/research/edge-snap-behavior-spec.md` (A2) and `docs/research/screen-edge-snap-feasibility.md` (A1).

## Facts

- MyMacX has **no LICENSE file** — all-rights-reserved by default. Distribution is Developer ID + Hardened Runtime + notarization (ADR-0001); no App Store track.
- Prior art **vorssaint-utils** is **GPL-3.0-or-later**; its name/logo/look are covered separately by upstream TRADEMARKS.md (forks need their own identity).
- The behavioral spec (A2) was extracted under a **clean-room posture**: behavior re-expressed in our own words, zero code reuse, only pinpoint identifier citations with file:line. The vorssaint clone lives outside the repo (scratch only).
- Track A implementation starts at sprint v1.x-1 (rules sprint). Nothing in Phase A wrote code.

## Options

### 1. Clean-room reimplementation — RECOMMENDED
Re-express techniques and behavior behind MyMacX seams (`TriggerGeometryKit`, `PointerDragKit`, …), citing vorssaint-utils as prior art only.
- MyMacX license posture unchanged (defer choosing an open-source license to a separate decision).
- No forced source publication; trademark terms do not apply (we don't use their name/look).
- Cost: ongoing hygiene — implementation must not copy code; tests re-derived from our own spec doc, not theirs.
- Residual risk: copyright protects expression, not behavior/techniques; constant values (e.g. 400 pt/s, 12 pt activation) are unprotectable facts/tunables, but wholesale distinctive structure copied verbatim would be a risk — the A2 case list is the clean-room boundary.

### 2. GPL-3.0-or-later relicense of MyMacX
Literal code reuse allowed; MyMacX as a whole must be distributed under GPL-3.0-or-later with complete corresponding source.
- Forces open-sourcing the entire app (including Track B settings work and everything else).
- Forks/distributors need own name/icon per upstream TRADEMARKS.md.
- Compatible with Developer ID distribution; makes any future App Store or proprietary-adjacent plan impossible.
- Cost: relicensing decision is hard to reverse; must add LICENSE + source-availability process.

### 3. GPL helper process, distributed separately
Keep MyMacX proprietary; put edge-snap code in a separate GPL helper binary shipped alongside, communicating via documented IPC/XPC. Helper ships with its source.
- Preserves the main app's posture while allowing literal reuse.
- Cost: process boundary + IPC in the hot input path (event-tap timing constraints in A1 make this awkward); two build/release tracks (the repo already separates demo vs Developer ID release flows, so precedent exists).
- Risk: aggregate-vs-derivative boundary is a legal judgment; needs review before committing.

## Decision needed

Pick one. If 1: Track A implementation unblocks immediately (sprint v1.x-1 can start after wave 2). If 2 or 3: additional setup (LICENSE, source-availability process / helper architecture ADR) precedes v1.x-1.

## Related open items feeding v1.x-1 scoping (decide with or after the gate)

- Top-edge 1 pt coordinate rewrite trick (D-11): adopt event rewrite vs stand down top-edge (plan already deferred the trick as "own candidate").
- Scratch-frame coercion (A-06): admit into `AXWindowKit` retry adapters vs strict single-pass atomic rollback (plan holds it in reserve as the robustness slice).
- Fixed 8 zones first (plan recommendation) vs full remappable map immediately.
- `PointerPlatformSignal` timestamp payload (from A1) — mechanical, recommend approving for v1.x-1.

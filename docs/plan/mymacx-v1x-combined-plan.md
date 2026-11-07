# MyMacX v1.x Combined Plan — Edge Snap + Settings Polish

Status: draft for review (2026-11-07)
Source: analysis of vorssaint-utils (GPL-3.0) teardown + OpenDesign prototype "MyMacX Settings — Polished Redesign"
Sequencing rule: nothing here touches the Sprint 8 release track. All work starts after v1 ships (Gate G8; 0.1.0-beta is "DEMO GO; V1 NO-GO"). Two tracks run in parallel, joined by one shared component.

Intended final home of this document: `docs/plan/` in the MyMacX repo (pending agent switch; written here because Plan mode cannot modify the repo).

---

## Track A — Edge Snap zones + seam logic

Goal: edge/corner snap triggers with a remappable zone map and seam-aware multi-display behavior — a second trigger type alongside Notch Snap, feeding the existing `WindowActionPerforming` pipeline.

### Phase A — Scoping (read-only; gates everything else)

1. Feasibility research → `docs/research/screen-edge-snap-feasibility.md` (research skill, Apple primary sources):
   - Event taps during window drags (extend the existing `.listenOnly` `PointerDragMonitor` pattern).
   - Window-server frame sampling (`CGWindowListCopyWindowInfo`) on input paths; no AX while dragging.
   - macOS 15 system-tiling coexistence: `com.apple.WindowManager` `EnableTilingByEdgeDrag` / `EnableTilingOptionAccelerator` / `EnableTopTilingByEdgeDrag` (unwritten = enabled) and `com.apple.spaces` `spans-displays`.
   - Pointer-velocity tracking for seam gating (public `CGEvent` location sampling).
2. Behavioral spec extraction from Vorssaint's test suites (~2,900 lines; their `expect` sentences read as an executable spec):
   - Zone model and fallback behavior (unknown zone/action entries degrade to defaults; max 4 areas per edge; per-zone off switches).
   - Seam rules: outer walls snap at any flick speed; shared display seams only below ~400 pt/s over a 50 ms pointer trail; velocity along an edge ignored; deferred "still check" for a pointer that stops at a seam.
   - Drag classification: cosine alignment ≥ 0.6 and distance ratio 0.2–1.8 identify a real window move; content drags and native resizes never snap.
   - Acceptance/settle behavior (lenient per-action acceptance so clamped windows count as placed).
3. Domain pass (domain-modeling skill): propose CONTEXT.md terms — `Edge Snap Zone`, `Display Seam`, `Settled Frame`, `Snap Run`; draft ADR "Edge Snap is a Trigger, not a Window Action" (it emits `WindowIntent` through `WindowActionPerforming`; triggers never touch Accessibility or compute frames).
4. License decision gate — settle before any implementation code:
   - Clean-room reimplementation (default recommendation; techniques and behavior re-expressed behind MyMacX seams, citing vorssaint-utils as prior art).
   - GPL-3.0 relicense of MyMacX (literal code reuse; forces open-sourcing; forks need own identity per upstream TRADEMARKS.md).
   - GPL helper process distributed separately (must ship its source).
   Note: MyMacX currently has no LICENSE file (all-rights-reserved default). Upstream is GPL-3.0-or-later.

### Phase B — Design (codebase-design skill)

| Concern | Home | Reuse/new |
|---|---|---|
| Zone resolution (8 zones, edge split 1–4 areas, corner bands) | `TriggerGeometryKit` (pure Swift) | New |
| Seam velocity gating + pointer trail | `TriggerGeometryKit` (pure) | New |
| Drag classification (is the window actually moving?) | `PointerDragKit` | New rule; window-server sampling replaces the AX "moved" signal |
| Preview/commit/cancel transaction | `SnapInteractionKit` state machine | Reuse |
| Placement preview overlay | `OverlayKit` | Reuse |
| Execute / read-back verify / rollback; pre-snap frame to history | `WindowActionKit` / `AXWindowKit` / `HistoryKit` | Reuse unchanged |
| Per-app exclusions | `AppRuleKit` | Reuse (bundle-ID rules, fail closed) |
| Zone→action mapping persistence | `PersistenceKit` | New schema entry — coordinate before editing shared persistence |

Deferred from first cut (own candidates): top-drag 1 pt rewrite trick (suppresses macOS "drag top = overview"; potentially surprising), Stage Manager strip reservation (cooperative usable-frame inset).

Open decision at scoping: fixed 8 zones first vs full remappable 1–4-areas-per-edge map. Recommendation: fixed zones first; remap lands with the zone-map picker in v1.x-3.

### Phase C — Implementation sprints (TDD per AGENT.MD)

- v1.x-1 Rules sprint: zone geometry, seam gating, velocity trail, drag classification as pure Swift behind Kit interfaces; exhaustive tests at module interfaces (Vorssaint tests double as the case list).
- v1.x-2 Runtime sprint: event-tap wiring (minimal data enqueued; callbacks return immediately), off-thread target resolution (bounded AX timeouts ~0.3 s, generational cancellation), preview → commit through `WindowActionPerforming`, undo integration, system-tiling coexistence gate that stands down visibly when macOS owns the edge.
- v1.x-3 UX + hardening sprint: zone-map picker UI (shared with Track B), per-zone disable, persistence migration + import/export, localization strings; then human gates (real pointer-drag evaluation is human-only per AGENT.MD).

Possible forced slice: deferred settle / scratch-frame coercion (Vorssaint's fix for minimum-size-bound apps) if clamped apps misbehave during v1.x-2; this is the "robustness hardening" candidate held in reserve.

---

## Track B — Settings polish

Goal: "as if Apple shipped MyMacX's settings pane itself." Visual source of truth = OpenDesign prototype "MyMacX Settings — Polished Redesign" (project `mymacx-settings-polished-redesign-7a87`, artifact `mymacx-settings.html`) + Vorssaint settings design patterns (reimplemented, not copied; MyMacX keeps its own identity). Notch-bar overlay UX stays untouched.

### v1.x-P1 — Token layer & primitives

Fixes Sprint 7 audit P2 "visual tokens duplicated, not semantic" (x7-01-whole-app-audit.md:145–155). Production stays SwiftUI/AppKit; the prototype is a spec, not code.

- Semantic tokens per project plan §5.2: SF Pro / SF Mono, 4 pt base spacing, semantic colors; light/dark + Reduce Transparency / Increase Contrast handling.
- `SettingsCard`: 16 pt padding, 16 pt continuous radius, quaternary ~35% fill, no border/shadow; 20 pt card stack gap; max 760 pt content column.
- `SettingsRow`: 26×26 accent-tinted icon tile (r7, 12% fill, 12 pt semibold SF Symbol) + title + one-line caption (captions wrap, never truncate) + trailing control; 38 pt text inset for sub-content; thin dividers.
- `Keycap` chips (min 20×22, r6, subtle fill + hairline) chained with arrows; `IconTile`; `StatusDot` (5–6 pt, green/grey); `CapsuleBadge` (BETA / EXPERIMENTAL, 8–9 pt bold).
- `ShortcutRecorderButton`: fixed width (~108 pt), single font in all states (no width jitter), "Press keys…" listening state, clear (×) + text Reset column-aligned; inline orange caption for conflicts.
- Motion budget: 0.1–0.22 s micro-interactions only; honor `prefers-reduced-motion`.

### v1.x-P2 — Settings shell upgrade

- Keep the current `NavigationSplitView` shell (SettingsShell.swift:751–796); do not adopt a browser-style history model in v1.x.
- Sidebar search field (pill, magnifier + clear) with macOS-Settings-style grouped results; section-anchor landing highlight (scroll-to-center + transient accent frame, fades ~1.8 s).
- Replace Super Mode raw key-code Pickers (SuperModeSettingsWindowController.swift:622–631, audit P0 remnant) with keycap / recorder-button rows.
- Unify the two standalone hotkey child windows' visual language with the shell (audit gap x7-01:157–170): same card/row primitives, same Save/status placement.

### v1.x-P3 — Feature screens

- Layout Library: normalized region thumbnails (mini-screen split glyphs — same renderer family as the notch chooser's snap glyphs), Split Columns / Split Rows / Merge actions, custom layout treatment ("Coding" example in prototype).
- Display Profiles: Stable Display ID captions (copy fix — must appear verbatim), connected/disconnected status treatment, gap steppers, layout assignment toggles.
- App Rules: app-icon rows + bundle-ID entry, default Included/Excluded segmented control.
- Zone-map picker (3×3 screen miniature, per-cell placement glyphs, hover states, per-zone off, reset button) — the component joining both tracks: behavior/spec from Track A Phase A, visuals from the prototype. Lands with v1.x-3.
- Copy fixes found in prototype critique: "Stable Display ID", "Layout Region", "Native Full Screen" labels appear verbatim; Maximize is never called Full Screen.

---

## Cross-cutting

- Human gates (AGENT.MD): pixel-baseline renders + human visual/focus review (x7-09/x7-10 outstanding), real pointer-drag evaluation, physical multi-display verification. Automated PASS text alone never promotes a gate.
- Validation: narrowest relevant `xcodebuild … build` / `… test` per change (signing disabled); full suite before sprint close.
- Risks:
  - macOS 15 system-tiling default semantics (unwritten keys = enabled) must fail visible, not silently (ADR-0002 experimental rule).
  - Clamped-app frame behavior may force the robustness slice into v1.x-2.
  - License gate slips would block Track A implementation (Track B is unaffected — design patterns are not code).
  - Prototype copy gaps (three terminology labels) are tracked above so they don't get lost in implementation.
- Prior art: vorssaint-utils (GPL-3.0), `Sources/Vorssaint/Services/WindowLayout/` + tests. Cite as inspiration; do not copy code until/unless the license gate says GPL.

## Timeline shape (post-v1)

- Weeks 1–2: Phase A scoping (Track A) + v1.x-P1 tokens/primitives (Track B).
- Weeks 3–5: v1.x-1 rules sprint + v1.x-P2 shell upgrade.
- Weeks 6–8: v1.x-2 runtime sprint + v1.x-P3 feature screens (zone map waits on v1.x-1).
- Weeks 9–10: v1.x-3 hardening + human gates.
- License gate unblocks all Track A implementation; decision expected end of Phase A.

# My Mac X — Agent Guide

## Mission

Build a local-first native macOS window manager that feels like a missing system feature: Notch Snap for pointer users, customizable hotkeys, and a prefix-driven Super Mode for keyboard users.

## Read by branch

- **Scope, milestones, backlog or UI specs:** read [my-mac-x_projectplan.md](./my-mac-x_projectplan.md).
- **Domain terms or naming:** read [CONTEXT.md](./CONTEXT.md) before naming types, actions or UI copy.
- **Architectural decisions:** read the relevant record in [docs/adr](./docs/adr).
- **Active sprint status and gate evidence:** read current sprint tracker [docs/sprint-8/README.md](./docs/sprint-8/README.md) (prior sprint trackers in `docs/sprint-0` through `docs/sprint-7`).
- **macOS API feasibility and research:** read [docs/research](./docs/research) (`macos-window-management-feasibility.md`, `native-full-screen-accessibility.md`, `macos-input-source-key-labels.md`). Use primary Apple sources for new claims.
- **Release notes, privacy and user communications:** read [docs/release](./docs/release) (`release-notes-0.1.0-beta.md`, `privacy.md`, `faq.md`).
- **Throwaway experiments:** read [prototypes/README.md](./prototypes/README.md). Prototype code is evidence, not production code.

## Skill routing

Skills live in `.agents/skills`; `skills-lock.json` records their source and hash. Read a matching `SKILL.md` completely before acting.

- Use `domain-modeling` when terminology changes, `CONTEXT.md` changes, or an ADR is justified.
- Use `codebase-design` when placing a seam or designing an Interface; optimize for deep Modules, Leverage and Locality.
- Use `research` for Apple API, platform, permission or distribution facts; save cited findings in `docs/research`.
- Use `prototype` for throwaway state/UI experiments; keep them in `prototypes` and state the question they answer.
- Use `tdd` when production implementation or a bug fix begins.
- Use `diagnosing-bugs` when behavior fails, crashes, hangs or regresses.
- Use `code-review` for changes since a fixed commit, branch, tag or merge base.
- Use `writing-for-agents` when editing skills, `AGENT.MD`, `AGENTS.md`, or context pointers.
- Use `wizard` when authoring or revising interactive operator workflows (such as release gates).
- Use `grilling` when stress-testing architectural decisions, plans, or trade-offs.
- Use `resolving-merge-conflicts` only for an active merge/rebase conflict.
- Use setup or migration skills only when their named workflow is requested.

## Domain invariants

- `Maximize` fills the current Display's usable area; it is distinct from `Native Full Screen`.
- A `Window Action` targets one captured eligible window. Focus changes during execution never retarget it.
- Preview never mutates a window or writes history.
- Commit succeeds only after Accessibility read-back verifies the resulting frame.
- Undo is tied to a window identity or explicit undo token, not a process ID alone.
- A failed action preserves or best-effort restores the prior frame.
- `Stable Display ID` binds Display Profiles across hardware reconnects and topology changes, distinct from transient `DisplayID`.
- v1 moves windows between physical Displays. Space-specific actions remain experimental and off by default.

## Architectural seams

- External callers cross one deep Interface: `WindowActionPerforming.perform(_:)`.
- `WindowIntent` models preview, preview commit/cancel, direct commit and undo.
- Accessibility, screen topology, clock and persistence are internal seams with production and test Adapters.
- Layout calculation is pure Swift behind the Window Action Module.
- Hotkey, Notch, menu bar and Super Mode never call Accessibility or calculate frames directly.
- UI and panels run on `MainActor`; Accessibility work runs off the main thread on a confined executor.
- Event tap callbacks enqueue minimal data and return immediately.
- Source kits (`Sources/`) follow clear layering:
  - **Action pipeline**: `WindowActionKit`, `AXWindowKit`, `ScreenKit`, `GeometryKit`, `HistoryKit`, `CycleKit`, `DisplayMoveKit`, `CrossDisplayKit`.
  - **Triggers & Overlays**: `PointerDragKit`, `TriggerGeometryKit`, `TriggerDwellKit`, `SnapInteractionKit`, `OverlayKit`.
  - **Input & Modes**: `InputKit` (hotkeys, event taps), `CommandKit` (prefix/Super Mode).
  - **Rules & Layout**: `LayoutKit`, `ProfileKit`, `AppRuleKit`, `PersistenceKit`.
  - **Shell & Runtime**: `AppShell`, `DiagnosticsKit`, `PerformanceKit`, `PermissionKit`.

## Platform, security and privacy constraints

- Minimum deployment target: macOS 14 Sonoma (Swift 6 mode, Xcode 16+).
- Production uses public macOS APIs and contains no private framework or SkyLight symbol.
- AppKit handles system integration and SwiftUI handles settings/onboarding.
- Distribution defaults to Developer ID, Hardened Runtime and notarization.
- Separation of release tracks: local ad-hoc demo beta packaging (`scripts/release/build-app.sh`) is distinct from Developer ID signed/notarized releases (`scripts/release/release-developer-id.sh`).
- Accessibility is requested only after explaining its purpose. Screen Recording is outside v1 scope.
- Raw keystrokes, typed text, window/document titles, clipboard and screenshots never enter logs.
- Config and history are local. Network access is limited to a disclosed update path unless an ADR changes this.

## Working agreement

1. Resolve the task against the project plan and current sprint tracker (`docs/sprint-8/README.md`).
2. Read the triggered skills and pointed source-of-truth documents.
3. Preserve Module ownership; coordinate before editing shared composition, action schema or persistence schema.
4. Keep production changes behind an existing Interface or justify a new seam with two real Adapters.
5. Add observable tests at the Module Interface. Do not test past the seam.
6. Update `CONTEXT.md` immediately when domain language changes; add an ADR only for a hard-to-reverse, surprising trade-off.
7. Validate with the narrowest relevant command, then report changed files, evidence and remaining risk:
   - Full test suite: `xcodebuild -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" test`
   - Fast build: `xcodebuild -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build`

## Human-only gates

An agent may prepare instructions and diagnostics, but a human performs Accessibility/Input Monitoring approval, real pointer-drag evaluation, physical multi-display verification, signing credential access and stable-release Go/No-Go.

For release QA and demo verification, run the interactive wizard:
```sh
scripts/release/complete-human-gates.sh
```
Operator records and artifacts are written to `docs/sprint-8/evidence/human-runs/`. Automated checks or self-reported PASS text alone do not promote Gate G8.

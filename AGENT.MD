# My Mac X — Agent Guide

## Mission

Build a local-first native macOS window manager that feels like a missing system feature: Notch Snap for pointer users, customizable hotkeys, and a prefix-driven Super Mode for keyboard users.

## Read by branch

- **Scope, milestones, screens, backlog or model assignment:** read [my-mac-x_projectplan.md](./my-mac-x_projectplan.md).
- **Domain terms or naming:** read [CONTEXT.md](./CONTEXT.md) before naming types, actions or UI copy.
- **Architectural or scope decisions:** read the relevant record in [docs/adr](./docs/adr).
- **Current Sprint 0 status or evidence:** read [docs/sprint-0/README.md](./docs/sprint-0/README.md).
- **macOS API claims:** read [docs/research/macos-window-management-feasibility.md](./docs/research/macos-window-management-feasibility.md) when present; use primary Apple sources for new claims.
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
- Use `resolving-merge-conflicts` only for an active merge/rebase conflict.
- Use setup or migration skills only when their named workflow is requested.

## Domain invariants

- `Maximize` fills the current Display's usable area; it is distinct from `Native Full Screen`.
- A `Window Action` targets one captured eligible window. Focus changes during execution never retarget it.
- Preview never mutates a window or writes history.
- Commit succeeds only after Accessibility read-back verifies the resulting frame.
- Undo is tied to a window identity or explicit undo token, not a process ID alone.
- A failed action preserves or best-effort restores the prior frame.
- v1 moves windows between physical Displays. Space-specific actions remain experimental and off by default.

## Architectural seams

- External callers cross one deep Interface: `WindowActionPerforming.perform(_:)`.
- `WindowIntent` models preview, preview commit/cancel, direct commit and undo.
- Accessibility, screen topology, clock and persistence are internal seams with production and test Adapters.
- Layout calculation is pure Swift behind the Window Action Module.
- Hotkey, Notch, menu bar and Super Mode never call Accessibility or calculate frames directly.
- UI and panels run on `MainActor`; Accessibility work runs off the main thread on a confined executor.
- Event tap callbacks enqueue minimal data and return immediately.

## Platform and privacy constraints

- Production uses public macOS APIs and contains no private framework or SkyLight symbol.
- v1 uses native Swift 6, AppKit for system integration and SwiftUI for settings/onboarding.
- Distribution defaults to Developer ID, Hardened Runtime and notarization.
- Accessibility is requested only after explaining its purpose. Screen Recording is outside v1 scope.
- Raw keystrokes, typed text, window/document titles, clipboard and screenshots never enter logs.
- Config and history are local. Network access is limited to a disclosed update path unless an ADR changes this.

## Working agreement

1. Resolve the task against the project plan and current sprint tracker.
2. Read the triggered skills and pointed source-of-truth documents.
3. Preserve Module ownership; coordinate before editing shared composition, action schema or persistence schema.
4. Keep production changes behind an existing Interface or justify a new seam with two real Adapters.
5. Add observable tests at the Module Interface. Do not test past the seam.
6. Update `CONTEXT.md` immediately when domain language changes; add an ADR only for a hard-to-reverse, surprising trade-off.
7. Validate with the narrowest relevant build/typecheck/test, then report changed files, evidence and remaining risk.

## Human-only gates

An agent may prepare instructions and diagnostics, but a human performs Accessibility/Input Monitoring approval, real pointer-drag evaluation, physical multi-display verification, signing credential access and stable-release Go/No-Go.


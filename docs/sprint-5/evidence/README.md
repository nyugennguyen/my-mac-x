# Sprint 5 evidence index

S5-01 through S5-07 are complete; S5-06/S5-07 SOL reviews are approved. Native menu-bar and Super Mode Settings access, Input Monitoring request/recovery and Prefix-driven `app.open-settings` are implemented. The project owner reported completion of manual testing and approved Gate G5 on 2026-09-07.

| Task | Planned evidence file | Owner / model and review | Required automated evidence | Required human or review evidence |
|---|---|---|---|---|
| S5-01 | [`s5-01-event-tap-lifecycle.md`](s5-01-event-tap-lifecycle.md) | A1 / SOL-H | Actor Interface start/stop/status contract; production CoreGraphics and in-memory Adapter behavior; idempotent start/stop; timeout/user-disable re-enable without duplicate installation; callback emits only minimal non-text metadata and performs no Accessibility, I/O or logging. | Input Monitoring/Accessibility grant, deny and revoke behavior; sleep/wake and fast-user-switch recovery on a real Mac; SOL-H call-site review. |
| S5-02 | [`s5-02-super-mode-state-machine.md`](s5-02-super-mode-state-machine.md) | A2 / SOL-XH — 15 focused tests pass; review approved | Deterministic idle/armed/submenu/execute/cancel transitions; Prefix, one-/two-level sequence, invalid input, Escape, timeout, disable/recovery and exact single Window Action dispatch. | `HUMAN VERIFIED — 2026-09-07`; SOL-XH review found no S5-02 blocker. |
| S5-03 | [`s5-03-prefix-sequence-config.md`](s5-03-prefix-sequence-config.md) | A2 / TERRA-H — configuration review approved; Settings-access extension has 32 passing focused tests | Schema-v2 Prefix/timeout/command-tree persistence and migration; validation; actor-isolated runtime replacement; native Settings editor loads, edits, validates, saves and hot-applies Prefix configuration through the existing Module/Store seam. | `HUMAN VERIFIED — 2026-09-07`. |
| S5-04 | [`s5-04-super-hud.md`](s5-04-super-hud.md) | A2 / TERRA-H — 3 focused tests pass; review approved (0.91) | Session-safe waiting/submenu/pending/success/error/timeout mapping; stale-result guards; non-activating panel flags; dismissal and appearance/accessibility policy. | `HUMAN VERIFIED — 2026-09-07`. |
| S5-05 | [`s5-05-advanced-actions.md`](s5-05-advanced-actions.md) | A2 / TERRA-M — production composition complete; optional app Adapters deferred | Stable Restore/cycle/Display/settings/gap/profile ID resolution and binding validation; exactly-once Window Action dispatch; typed unavailable/failure results; production completed-sequence composition; menu and Prefix Open Settings are operational. | `HUMAN VERIFIED — 2026-09-07`. Gap/profile Adapters remain Sprint 6 scope. |
| S5-06 | [`s5-06-input-safety-policy.md`](s5-06-input-safety-policy.md) | A1 / SOL-H — 19 core tests pass; safety review approved | Swallow only proven-owned events; pass through outside armed/recognized states; cancel/timeout/invalid/disable cleanup; no retained/logged text or raw key stream; stale generations fail open; production Event Tap/HUD/dispatch composition. | `HUMAN VERIFIED — 2026-09-07`; SOL review found no automated blocker. |
| S5-07 | [`s5-07-timeout-rapid-input-tests.md`](s5-07-timeout-rapid-input-tests.md) | A3 / LUNA-M batch + SOL review approved | Deterministic timeout, rapid sequence, key repeat, held/released modifier, invalid input, Escape, tap disable, stop and recovery; assertions for resumed pass-through and no duplicate dispatch. | `HUMAN VERIFIED — 2026-09-07`. |
| G5 | [`g5-prefix-sequence-beta.md`](g5-prefix-sequence-beta.md) | A0 integration / SOL-H gate review | S5-01…07 automated evidence complete; production Prefix path reaches the shared Window Action Interface and app-action Adapter; complete suite passes 349 tests with 2 skips; no unresolved automated core/input-safety finding. | `PASS — 2026-09-07` — project owner completed manual testing, confirmed Super Mode operates successfully and explicitly approved G5. |

## Current manual-access status

- Status-item menu: implemented with runtime/permission status, **Open Settings…** (`⌘,`), Pause/Resume Super Mode, Open System Settings and Quit.
- Super Mode Settings: implemented as one reusable native window with Prefix recording, modifier controls, 250–5000 ms timeout, one-/two-key binding editing, Action selection, Reload, Save and **Load Test Preset**.
- Persistence/runtime: Save uses `SuperModeConfigurationModule` and the sole `SettingsStore`; successful writes replace the live `SuperModeInputSafetyController` snapshot while preserving Hotkey bindings.
- Automated result on 2026-09-04: complete suite passed 349 tests, 0 failures and 2 documented skips.
- Human verification: manual testing completed and accepted by the project owner on 2026-09-07; G5 decision is `GO`.
- Known deferred scope: gap/profile Prefix commands remain typed unavailable until Sprint 6 production Adapters exist.

## Evidence record requirements

Every evidence file must include:

1. Scope and the observable contract being proved.
2. Exact changed files and the production/test Adapter boundary used.
3. Exact focused command and result, including test count, failures and skips; never infer hardware behavior from automation.
4. Fixtures, clocks, event metadata, input source and hardware/topology relevant to the result, without recording text or a raw key stream.
5. SOL reviewer and finding disposition where required.
6. Human-only steps as `PENDING` until a person records date, hardware/input source, observed result and sign-off.
7. Assumptions, known gaps and dependency evidence links.

Use project domain terms from [CONTEXT.md](../../../CONTEXT.md): `Super Mode`, `Prefix`, `Window Action` and `Display`. Preserve “Leader state machine” only when quoting the S5-02 backlog label.

## Inherited open human evidence

Sprint 4 passed Gate G4 only under a temporary exception on 2026-08-31. Its deferred physical keyboard/VoiceOver checks and physical cross-Display human check remain open. Sprint 5 evidence may reference a separately completed Sprint 4 record, but must not claim those gaps are closed merely because a Sprint 5 keyboard, HUD or Display scenario passes.

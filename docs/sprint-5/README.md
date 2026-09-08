# Sprint 5 — Super Mode

Sprint 5 targets Gate G5: a feature-complete beta that a person can operate entirely through a Prefix sequence. Super Mode remains a temporary keyboard mode: a configured Prefix arms it for a bounded time, and a registered one- or two-level key sequence completes a Window Action.

This tracker is the source of truth for S5-01 through S5-07. S5-01 through S5-07 are complete, S5-06/S5-07 SOL reviews are approved, and Gate G5 is `PASS` following project-owner manual verification on 2026-09-07. Native menu-bar and Super Mode Settings access is implemented, Settings exposes the required Input Monitoring request/recovery flow, and Prefix-driven `app.open-settings` has a production Adapter.

## Entry state

- Gate G2 is `PASS`; the Window Action Module and W2-05…07 supply the shared Restore, cycle and Display-movement behavior consumed by S5-05. Super Mode must dispatch through `WindowActionPerforming.perform(_:)` and must not call Accessibility or calculate final frames directly.
- Gate G3 is `PASS`; H3-01, H3-02 and H3-05 supply the global-hotkey lifecycle, stable Action Registry and versioned Settings Store required by this sprint.
- P0-04 proved listen-only Event Tap delivery, but its Input Monitoring matrix and active-suppression safety remained partial/conditional. That evidence does not establish S5-01, S5-06 or Gate G5.
- Gate G4 is `PASS — TEMPORARY EXCEPTION (2026-08-31)`. Sprint 4's deferred physical keyboard/VoiceOver checks and physical cross-Display human check remain open. Sprint 5 does not inherit, close or claim those checks merely by starting.
- `Super Mode`, `Prefix`, `Window Action`, `Display` and the Window Action Interface retain their definitions in [CONTEXT.md](../../CONTEXT.md) and [ADR-0003](../adr/0003-intent-driven-window-action-module.md).

## Agent ownership

At most four agents run concurrently. The Section 7 topology and default ownership remain unchanged:

| Agent | Full role | Default model | Ownership |
|---|---|---|---|
| A0 | Orchestrator/Integrator | SOL-H | Task breakdown, Interfaces, dependencies, shared composition, merge and quality gates |
| A1 | Core Window System | SOL-H | PermissionKit, AXWindowKit, Window mutation and history; in Sprint 5, Event Tap lifecycle and input-safety review |
| A2 | Interaction/UI | TERRA-H | InputKit integration, OverlayKit, Settings and HUD; in Sprint 5, Super Mode behavior and presentation |
| A3 | Geometry/QA/Release | TERRA-M | ScreenKit, LayoutKit, tests, CI/signing and release evidence; SOL review at release |

Sprint 5 assigns one implementation owner to each backlog item:

- A1 owns S5-01 and S5-06.
- A2 owns S5-02, S5-03, S5-04 and S5-05.
- A3 owns S5-07 and coordinates its Luna batch and Gate evidence.
- A0 owns shared composition, dependency sequencing, integration and the G5 Go/No-Go record; A0 does not create a second implementation owner for a Module.

A0 is the sole integration owner for shared composition. No two agents edit shared composition, `ActionRegistry` or persistence schema concurrently. Core event state, input suppression and security-sensitive changes require SOL-H/XH review.

## Full model setup

The project-plan model codes are used exactly as follows:

| Code | Full model assignment | Intended use |
|---|---|---|
| SOL-XH | `gpt-5.6-sol`, reasoning `xhigh` | Core architecture, coordinate/event state and security/release blockers |
| SOL-H | `gpt-5.6-sol`, reasoning `high` | Accessibility, Event Tap, concurrency and complex debugging/review |
| SOL-M | `gpt-5.6-sol`, reasoning `medium` | Product/design synthesis requiring high judgment |
| TERRA-H | `gpt-5.6-terra`, reasoning `high` | SwiftUI/AppKit interaction and stateful feature implementation |
| TERRA-M | `gpt-5.6-terra`, reasoning `medium` | Default implementation, persistence, CI and clearly scoped refactors |
| LUNA-M | `gpt-5.6-luna`, reasoning `medium` | Fixtures, test matrices and schema checks with dependencies |
| LUNA-L | `gpt-5.6-luna`, reasoning `low` | Scaffolding, microcopy, documentation, release notes and mechanical checks |
| SOL-MAX | `gpt-5.6-sol`, reasoning `max` | Exceptional severe hard-to-reproduce failures or Spaces feasibility |

Luna may replace one implementation agent for batched fixtures, test cases, microcopy or documentation. Luna must not decide entitlements, architecture or Accessibility behavior. Every agent handoff records changed files, test results, assumptions and known gaps. Reasoning may be reduced only after measured task success, review count, latency and cost show no quality loss.

## Tracker

| ID | Deliverable | Owner / backlog model | Status | Dependency | Evidence / exit expectation |
|---|---|---|---|---|---|
| S5-01 | Event Tap lifecycle and recovery | A1 Core / SOL-H (`gpt-5.6-sol`, `high`) | **DONE — AUTOMATED; HUMAN VERIFIED** | P0-04, H3-01 | [Evidence](evidence/s5-01-event-tap-lifecycle.md): actor Interface, production CoreGraphics Adapter and deterministic in-memory Adapter integrated; callback packages only non-text key metadata and returns the raw event; 8 focused tests pass. SOL review's in-flight stop/restart race is fixed and covered. Project-owner manual verification accepted 2026-09-07. |
| S5-02 | Super Mode state machine (backlog label: “Leader state machine”) | A2 Interaction/UI / SOL-XH (`gpt-5.6-sol`, `xhigh`) | **DONE — AUTOMATED; SOL-XH APPROVED; HUMAN VERIFIED** | S5-01, H3-02 | [Evidence](evidence/s5-02-super-mode-state-machine.md): synchronous deterministic reducer covers idle/armed/submenu state, monotonically unique sessions, same-callback consume/pass-through decisions and typed outcomes for Prefix, one-/two-level sequences, invalid input, Escape, timeout, repeated Prefix, tap disable and stop. Separate availability-aware dispatcher crosses `WindowActionPerforming` exactly once only for available actions. Fifteen focused tests pass; SOL-XH review found no S5-02 blocker. Project-owner manual verification accepted 2026-09-07. |
| S5-03 | Prefix/sequence configuration | A2 Interaction/UI / TERRA-H (`gpt-5.6-terra`, `high`) | **DONE — AUTOMATED; REVIEW APPROVED; HUMAN VERIFIED** | S5-02, H3-05 | [Evidence](evidence/s5-03-prefix-sequence-config.md): schema-v2 Prefix, bounded timeout and one-/two-level command paths; v0/v1 migration; typed invalid, duplicate, ambiguous, reserved and Hotkey/Prefix conflict rejection before Save; actor-isolated runtime revisions and exact activated-session tokens prevent stale capture. Fifteen focused tests pass; final review approved with confidence 0.96. Project-owner manual verification accepted 2026-09-07. |
| S5-04 | Super HUD | A2 Interaction/UI / TERRA-H (`gpt-5.6-terra`, `high`) | **DONE — AUTOMATED; REVIEW APPROVED; HUMAN VERIFIED** | S5-02, N4-04 | [Evidence](evidence/s5-04-super-hud.md): session-safe waiting, submenu, pending, success, error and timeout states; stale results cannot replace current presentation; non-activating panel and accessibility appearance policies verified. Three focused tests pass and review approved. Project-owner manual verification accepted 2026-09-07. |
| S5-05 | Advanced actions | A2 Interaction/UI / TERRA-M (`gpt-5.6-terra`, `medium`) | **DONE — AUTOMATED; PRODUCTION COMPOSED; OPTIONAL APP ADAPTERS DEFERRED** | W2-05…07, S5-02 | [Evidence](evidence/s5-05-advanced-actions.md): stable Restore/cycle/Display/settings/gap/profile IDs resolve and validate for persisted Super Mode bindings; production completed sequences reach the advanced dispatcher; Window Actions dispatch exactly once through the Window Action Interface. Prefix-driven `app.open-settings` is connected; gap and profile actions remain typed unavailable for Sprint 6. |
| S5-06 | Input safety policy | A1 Core / SOL-H (`gpt-5.6-sol`, `high`) | **DONE — AUTOMATED; SOL APPROVED** | S5-01…03 | [Evidence](evidence/s5-06-input-safety-policy.md): same-callback suppression consumes only reducer-proven ownership; stale/stopped/disabled/invalid/timeout/repeat/release/modifier paths fail open; callbacks retain no text, raw event or key stream. Production Event Tap, HUD and advanced dispatch composition is active. SOL review found no automated blocker. |
| S5-07 | Timeout and rapid-input tests | A3 QA, Luna batch / LUNA-M (`gpt-5.6-luna`, `medium`) + SOL review | **DONE — AUTOMATED; SOL APPROVED; HUMAN VERIFIED** | S5-01…06 | [Evidence](evidence/s5-07-timeout-rapid-input-tests.md): deterministic timeout, stale timeout, rapid sequence, repeat, held/released modifier, invalid input, Escape, disable/stop and recovery coverage proves software dispositions and resumed pass-through. Final focused integration run: 33 tests, 0 failures. Project-owner physical manual verification was accepted for G5 on 2026-09-07. |

Evidence belongs under [evidence](evidence/README.md), one record per S5 item plus one G5 record. Automated evidence must state the exact observable command and result; hardware-gated evidence remains `PENDING` until a person performs it.

## Execution order

1. A0 freezes the S5-01 actor Interface, Adapter boundary, ownership and shared composition seam before parallel implementation begins.
2. A1 completed S5-01 with SOL-H implementation ownership and A0 review. S5-02 must not infer active-suppression safety from P0-04's listen-only evidence or S5-01's pass-through callback.
3. A2 completed S5-02; 15 focused tests pass and SOL-XH event-state review approved it with no S5-02 blocker.
4. A2 completed S5-03 through S5-05. S5-06 supplies production callback composition. Native menu-bar access and a reusable Super Mode Settings window load, validate, persist and hot-apply Prefix configuration. The Settings surface reports Input Monitoring, requests it only from an explicit user action and retries the runtime after grant. Prefix-driven `app.open-settings` is connected; real gap/profile Adapters remain deferred to Sprint 6.
5. A1 completed S5-06 with synchronous proven-ownership suppression, fail-open lifecycle/configuration behavior and production Event Tap composition. SOL safety review approved with no automated blocker.
6. A3 completed the S5-07 deterministic matrix after S5-06 integration. Timeout/rapid/repeat/modifier/recovery coverage passes, SOL review approved, and project-owner physical testing was accepted on 2026-09-07.
7. A0 integrated shared composition and completed the automated evidence index. The project owner completed manual testing and recorded G5 Go on 2026-09-07.

## Gate G5

Status: `PASS — 2026-09-07`

S5-01 through S5-07 automated evidence and SOL input-safety review are complete. A native status-item menu and reusable Super Mode Settings window make configuration and Input Monitoring recovery available without editing JSON. Prefix-driven `app.open-settings` is connected. The project owner reported successful Super Mode operation and completion of the manual test sequence on 2026-09-07, then explicitly approved G5. Sprint 5 is complete.

### Manual testing access

1. Build and launch My Mac X.
2. Click **My Mac X** in the macOS menu bar.
3. Choose **Open Settings…** (`⌘,`).
4. In **Super Mode Settings**, choose **Load Test Preset**, then **Save**.
5. Use Control-Space as the Prefix. Saved changes validate through `SuperModeConfigurationModule`, persist through the sole `SettingsStore` and replace the live input-safety snapshot without a relaunch.
6. Use the same menu to Pause/Resume Super Mode, inspect runtime/permission status, open System Settings and quit.

Automated status on 2026-09-04: the complete suite passed 349 tests with 0 failures and 2 documented skips. The two delayed Pointer Drag scenarios also passed a 20-iteration/40-execution stress run after ordered replay and deterministic timeout-test fixes. The test preset includes `S → app.open-settings`, and that Prefix action opens the same reusable Settings window as the menu. Project-owner manual verification and G5 approval were recorded on 2026-09-07.

### Human-only checks — completed and accepted 2026-09-07

- Explicitly grant, deny and revoke required Input Monitoring/Accessibility permissions on a real Mac; verify status, recovery and fail-closed behavior.
- Exercise Prefix entry, one- and two-level sequences, invalid input, Escape, timeout, rapid input, key repeat and held modifiers on physical built-in and external keyboards; verify normal typing resumes without lost characters or sticky modifiers.
- Exercise supported input sources, including US/ABC, Vietnamese Telex and at least one non-Latin layout, without recording text or a key stream.
- Observe sleep/wake and fast-user-switch recovery and confirm only one effective Event Tap remains installed.
- Confirm the Super HUD never steals focus and that its waiting, submenu, success/error and dismissal states are perceivable with keyboard and VoiceOver.
- Exercise advanced Window Actions, including physical cross-Display movement, through Prefix sequences and confirm typed failure/availability feedback.
- Final decision: `GO`, recorded by the project owner on 2026-09-07. This G5 approval does not close Sprint 4's temporary keyboard/VoiceOver or physical cross-Display exceptions; their own Sprint 4 evidence must be updated separately if the same manual run is intended to satisfy them.

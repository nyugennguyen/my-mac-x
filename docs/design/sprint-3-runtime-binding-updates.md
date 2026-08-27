# Sprint 3 — H3-06 Runtime binding updates: proposed Interface

**Status:** Proposal. No production code or tests are authorized until the seam and failure
policy below are confirmed.

## Purpose and ownership

H3-06 makes one complete, H3-04-validated `HotkeySettings` snapshot effective without an
application restart. It is an AppShell-owned deep Module: it serializes the durable save,
the H3-01 atomic runtime reconcile, compensating rollback, and typed reporting that otherwise
would be spread across Settings UI callbacks and launch code.

The Module's success contract is deliberately narrow: after `.applied`, the persisted snapshot
and the effective global-hotkey snapshot are the exact desired bindings. It does **not** claim
an OS-wide transaction spanning the filesystem and Carbon registration. A process crash or an
I/O failure between those two independently atomic operations can leave a recoverable split;
the Interface makes that state explicit rather than silently declaring success.

H3-06 does not record or display a chord, decide duplicate/reserved/invalid policy, mutate a
Settings draft, encode/decode files, register individual Carbon hotkeys, own sleep/wake,
dispatch a Window Action, or call Accessibility. `GlobalHotkeyManaging` continues to own its
event stream and lifecycle recovery; `SettingsStoring` continues to own schema, migration,
atomic file replacement and corrupt-document recovery.

## Proposed external seam — confirmation required

```swift
public protocol HotkeyRuntimeBindingUpdating: Actor {
    /// Loads the durable snapshot and reconciles it for this running process.
    func start() async -> HotkeyRuntimeStartResult

    /// Makes one complete snapshot that H3-04 has already accepted durable and effective.
    func applyValidated(_ desired: HotkeySettings) async -> HotkeyRuntimeUpdateResult
}

public enum HotkeyRuntimeStartResult: Equatable, Sendable {
    case active(settings: HotkeySettings, origin: SettingsLoadOrigin)
    case degraded(settings: HotkeySettings, origin: SettingsLoadOrigin,
                  registration: HotkeyRegistrationSnapshot)
}

public enum HotkeyRuntimeUpdateResult: Equatable, Sendable {
    case applied(HotkeyRegistrationSnapshot)
    case saveFailed(SettingsSaveFailure)
    case rolledBackAfterRegistrationFailure(
        registration: HotkeyRegistrationSnapshot
    )
    case recoveryRequired(HotkeyRuntimeRecovery)
}

public enum HotkeyRuntimeRecovery: Equatable, Sendable {
    case runtimeRollbackFailed(
        attempted: HotkeyRegistrationSnapshot,
        rollback: HotkeyRegistrationSnapshot
    )
    case persistenceRollbackFailed(
        registration: HotkeyRegistrationSnapshot,
        save: SettingsSaveFailure
    )
}
```

`start()` is idempotent for an unchanged loaded snapshot: it may ask the already-confirmed
H3-01 manager to reconcile, but must not write settings or create a second event consumer.
`HotkeyRuntimeCoordinator` remains the one AppShell object that retains the manager event
stream and routes invocations through `HotkeyActionDispatcher` to
`WindowActionPerforming.perform(_:)`; the updater never dispatches an invocation.

`applyValidated(_:)` takes a complete replacement snapshot, not a row edit or an individual
register/unregister instruction. Its precondition is that the Settings draft coordinator has
validated the final, complete snapshot with H3-04, including any explicit Replace Existing
decision. H3-06 may rely on H3-05's defensive structural validation, but it must not turn a
structural save failure into conflict UI or reimplement H3-04 policy.

The Module is an actor so a launch reconciliation, two rapid Save presses, and a retry cannot
interleave their save/reconcile/rollback sequences. The Settings UI awaits one result before
offering another Save; it renders the typed result and never calls `SettingsStoring.save` or
`GlobalHotkeyManaging.reconcile` itself.

## Required update algorithm and atomicity boundary

For `applyValidated(desired)`, the Module performs this serialized sequence:

1. `load()` the prior structurally valid durable snapshot. A future-schema or recovery-blocked
   store is not overwritten; return its typed save/recovery result without touching runtime.
2. `save(desired)`. If it fails, return `.saveFailed`; the prior runtime registration remains
   the only effective configuration and no reconcile is attempted.
3. `reconcile(desired.bindings)`. Only `.active(bindingIDs:)` exactly matching `desired` is
   `.applied`. An empty desired snapshot is a successful release only when the active IDs are
   empty.
4. For any `.degraded` registration result, first explicitly reconcile the prior bindings.
   This is required even though H3-01 stages changed chords and preserves prior registrations
   on common staging failures: an unregister/release failure can report a degraded mixed active
   snapshot, so H3-06 must not assume the old runtime snapshot is still exact.
5. If runtime rollback returns the exact prior active snapshot, save the prior settings
   snapshot as a compensating atomic replacement. A successful compensation returns
   `.rolledBackAfterRegistrationFailure`; the user-visible durable and effective settings are
   again the prior snapshot.
6. If either compensation fails, return `.recoveryRequired` with both typed results. Do not
   hide the mismatch, retry in a tight loop, overwrite a future/corrupt document, or issue
   individual registrations from the caller. The next explicit retry or relaunch starts from
   `SettingsStoring.load()` and reconciles that durable snapshot.

The order is intentionally **validated save → atomic runtime reconcile**. It means a normal
success survives a relaunch, while an ordinary runtime registration rejection is compensated
back to the previously saved configuration. The brief internal interval after step 2 is not
observable as success. No result called `.applied` may describe a split state.

## Failure and rollback semantics

| Situation | Runtime operation | Durable operation | Result callers observe |
|---|---|---|---|
| Pre-save structural/I/O/recovery failure | None | Prior snapshot remains | `.saveFailed(...)` |
| Desired registration is exact | Exact desired bindings active | Desired snapshot saved | `.applied(...)` |
| Desired registration degrades; runtime and persistence compensation both succeed | Prior bindings restored exactly | Prior snapshot atomically restored | `.rolledBackAfterRegistrationFailure(...)` |
| Desired registration degrades; prior runtime cannot be restored exactly | Explicit degraded/mixed snapshot reported | Desired snapshot remains (no speculative overwrite) | `.recoveryRequired(.runtimeRollbackFailed(...))` |
| Prior runtime is restored; compensating save fails | Prior bindings active | Desired snapshot may remain durable | `.recoveryRequired(.persistenceRollbackFailed(...))` |

H3-01 failures stay typed as `HotkeyRegistrationSnapshot` / `HotkeyRegistrationFailure`.
`eventHotKeyExistsErr` or another registration rejection is a runtime availability failure, not
proof that H3-04 conflict validation was incorrect. Settings can say that the new binding could
not be activated and that the previous configuration was retained only for the explicit
rollback-success result; recovery-required copy must avoid asserting which snapshot will win
until the user retries or relaunches.

## Caller ownership and composition

```text
Settings draft + H3-03 capture
          │ complete candidate snapshot
          ▼
H3-04 validation and explicit Replace / Cancel choice
          │ validated HotkeySettings
          ▼
HotkeyRuntimeBindingUpdating.applyValidated
    ├── SettingsStoring.load / save (H3-05)
    └── GlobalHotkeyManaging.reconcile (H3-01)
          │
          ├── exact desired active ──> UI: saved and effective, no restart
          ├── compensated prior active ──> UI: save rejected at runtime; prior retained
          └── recovery required ──> UI: typed retry/relaunch recovery state

AppShell launch ──> HotkeyRuntimeBindingUpdating.start
                  └── one retained manager event stream ──> dispatcher ──>
                      WindowActionPerforming.perform(_:)
```

- The Settings draft coordinator owns validation, user choice, progress/error presentation and
  calling `applyValidated` exactly once per committed draft.
- H3-06 owns operation ordering and compensation. It coordinates a compensating `save`, but
  does not own persistence *semantics*: only H3-05 performs the atomic replacement and reports
  its failure.
- H3-01 owns atomic registration reconciliation, release, lifecycle observation and the raw
  runtime failure details. H3-06 never reaches `GlobalHotkeySystem` or Carbon.
- AppShell constructs the one updater with the one store and manager, calls `start()` once, and
  keeps the sole hotkey-event dispatcher alive. It must replace the current hard-coded
  `DefaultHotkeyBindings.initial` startup reconcile; H3-05's loaded snapshot is the launch
  source of truth. Defaults, if product-approved later, belong to H3-05's documented initial
  snapshot—not a second AppShell configuration source.

## Observable test matrix — no tests until confirmation

Tests cross only `HotkeyRuntimeBindingUpdating`. They use the existing deterministic
`SettingsStoring` and `GlobalHotkeyManaging` Adapters with observable call controls. They do
not inspect JSON, files, Carbon registrations, manager cache, event stream internals, or the
Settings view model. H3-05 and H3-01 retain their own Interface tests.

| ID | Known setup at the Interface | Expected observable result |
|---|---|---|
| R-01 | Prior saved snapshot A; validated snapshot B; store save and reconcile B succeed | `.applied(.active(B IDs))`; a fresh load returns B and B invocation works without relaunch |
| R-02 | Prior A; store rejects B | `.saveFailed(...)`; manager receives no B reconcile and A remains effective |
| R-03 | Prior A; save B succeeds; manager rejects B; rollback A and save A succeed | `.rolledBackAfterRegistrationFailure(...)`; fresh load is A and only A invokes |
| R-04 | Desired B changes one chord; manager returns degraded mixed active IDs; explicit rollback A succeeds | Compensated result and only the exact A bindings remain effective—proves H3-06 does not merely trust staging rollback |
| R-05 | Same as R-03, but rollback reconcile fails/degrades | `.recoveryRequired(.runtimeRollbackFailed(...))`; no compensating overwrite is attempted |
| R-06 | Same as R-03, but rollback A is active and save A fails | `.recoveryRequired(.persistenceRollbackFailed(...))`; runtime A and the unresolved durable state are not reported as applied |
| R-07 | Launch with persisted A | `start()` reports `.active(A, .persisted(...))`, does not write, and a second `start()` creates neither duplicate registration nor a second dispatcher |
| R-08 | Launch with H3-05 missing/corrupt defaults | `start()` reconciles exactly the returned default snapshot; no AppShell default binding bypasses the store outcome |
| R-09 | Two `applyValidated` calls arrive while first is paused at reconcile | Actor serialization yields one complete result before the next begins; no interleaved A/B compensation sequence is observable |
| R-10 | Successful update B, then fresh AppShell/updater over the same durable Adapter | `start()` activates B without any Settings Save, demonstrating no-restart update plus relaunch continuity |

The first vertical red → green slice after confirmation is R-01: a validated replacement is
saved, reconciled, and returned as `.applied` without restarting the process.

## Confirmation requested

Please confirm the following H3-06 seam and policy before the first red test:

1. `HotkeyRuntimeBindingUpdating` is the sole AppShell-owned actor Interface for `start()` and
   `applyValidated(HotkeySettings)`; Settings UI never sequences store and runtime calls.
2. `applyValidated` requires a complete snapshot already accepted by H3-04, then performs
   **save desired → reconcile desired**; `.applied` is returned only when both durable and
   active snapshots exactly equal the desired bindings.
3. On a degraded desired reconcile, H3-06 explicitly reconciles and atomically re-saves the
   prior snapshot. Full compensation returns a typed rollback result; either failed
   compensation returns an explicit recovery-required result rather than claiming success.
4. App launch loads through H3-05 and reconciles that result; the current AppShell default
   binding source is retired so persisted settings are the single launch source of truth.
5. Tests cross only `HotkeyRuntimeBindingUpdating` with deterministic existing store/manager
   Adapters, beginning with R-01. This document authorizes neither tests nor production code
   until you confirm it.

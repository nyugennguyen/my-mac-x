# H3-06 — Runtime Binding Updates

## Confirmed seam and policy

The user confirmed the AppShell-owned `HotkeyRuntimeBindingUpdating` actor and its
save-then-reconcile compensating-rollback policy on 2026-08-26. The updater is the only
H3-06 caller of `SettingsStoring.save(_:)` and `GlobalHotkeyManaging.reconcile(_:)`; it does
not own the manager event stream, dispatch an invocation, inspect persistence documents or
perform per-hotkey registration.

## Implemented behavior

- `start()` loads the one durable H3-05 snapshot and reconciles exactly its bindings. It never
  writes settings; an exact active snapshot returns `.active`, and any other registration
  outcome is carried as `.degraded`.
- `applyValidated(_:)` loads the prior safe snapshot, saves the complete desired snapshot, then
  reconciles it. Only exactly active desired binding IDs return `.applied`.
- Any non-exact runtime result explicitly reconciles the prior bindings. When that succeeds,
  the prior durable snapshot is atomically re-saved and the result is
  `.rolledBackAfterRegistrationFailure`.
- A failed runtime rollback or compensating save returns a typed `.recoveryRequired` result;
  neither path is reported as applied.
- An internal FIFO operation gate makes the entire load/save/reconcile/compensate sequence
  serial even across Swift actor suspension points. R-09 first failed (`2 != 1` saves while the
  first reconciliation was paused), demonstrating that actor isolation alone was insufficient.
- Future-schema and recovery-locked load origins return `.saveFailed(.recoveryRequired)` before
  either desired save or runtime reconciliation.

## Red → green and automated evidence

`Tests/MyMacXTests/AppShell/HotkeyRuntimeBindingUpdaterTests.swift` crosses only the confirmed
updater Interface with deterministic store and manager adapters. It covers R-01 through R-10:
successful no-restart apply, save failure, compensated registration failure, mixed degraded
runtime state, both compensation failures, persisted/default launch ownership, rapid-save
serialization, and fresh-updater relaunch continuity.

Focused command:

```text
xcodebuild -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS' \
  -only-testing:MyMacXTests/HotkeyRuntimeBindingUpdaterTests test -quiet
```

Result: **10 tests, 0 failures** on 2026-08-26.

## Integration boundary

AppShell now constructs one `SettingsStore` at
`Application Support/My Mac X/settings.json`, one updater sharing the production hotkey manager,
and injects that updater into `HotkeyRuntimeCoordinator`. Coordinator startup first calls
`HotkeyRuntimeBindingUpdating.start()` and then remains the sole manager-event dispatcher.
There is no second hard-coded launch snapshot: H3-05 persisted/default settings are the only
startup binding source.

Integrated verification on 2026-08-27: **224 tests, 2 hardware-gated skips, 0 failures** and
the Release build succeeded with the Swift 6 project settings.

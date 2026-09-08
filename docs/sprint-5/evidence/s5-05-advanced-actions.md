# S5-05 — Advanced actions

Status: `DONE — AUTOMATED; PRODUCTION COMPOSED; HUMAN VERIFIED`

## Scope

`SuperModeAdvancedActionResolver` resolves stable IDs for Restore, left-edge cycle, move next/previous physical Display, open settings, toggle gaps and profile selection. Registered Window Actions retain Action Registry availability and `SuperModeAdvancedActionDispatcher` delegates them to `SuperModeActionDispatcher`, preserving exactly one `WindowActionPerforming.perform(.commit(..., source: .superMode))` call.

App-level actions remain separate from the Window Action Registry. `app.open-settings` now crosses a dedicated production app-action Adapter and opens the same reusable Settings window as the menu without calling the Window Action Interface. Gap/profile IDs still fail closed with typed `productionAdapterUnavailable`; their Adapters remain Sprint 6 scope.

S5-06 composes the production Event Tap/completed-sequence path with this dispatcher. `SuperModeConfigurationValidator` accepts both Window Action Registry IDs and built-in app-action catalog IDs, so persisted settings/gap/profile bindings reach typed production availability rather than failing validation.

## Automated evidence

```bash
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' -only-testing:MyMacXTests/SuperModeAdvancedActionsTests
```

Combined S5-04/S5-05 run on 2026-09-03: `TEST SUCCEEDED`. `SuperModeAdvancedActionsTests`: 3 tests, 0 failures.

Coverage proves required ID resolution, exactly-once Restore dispatch, typed app-action unavailability, unknown-ID rejection, and zero Window Action calls from unavailable app actions.

## Changed files

- `Sources/CommandKit/ActionID.swift`
- `Sources/InputKit/SuperModeAdvancedActions.swift`
- `Tests/MyMacXTests/InputKit/SuperModeAdvancedActionsTests.swift`
- `MyMacX.xcodeproj/project.pbxproj`

## Production composition and human evidence

- `DONE S5-06` — completed Prefix sequences reach the advanced dispatcher through the production input composition.
- `DONE — AUTOMATED` — Prefix-driven Open Settings uses the production app-action Adapter.
- `DEFERRED TO SPRINT 6` — gap and profile effects require their production Interfaces/Adapters; until then typed unavailability is required.
- `HUMAN VERIFIED — 2026-09-07` — accepted through the project owner's completed G5 manual testing and Go decision. Hardware/topology details were not supplied and are not inferred.

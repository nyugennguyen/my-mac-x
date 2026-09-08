# S5-06 — Input safety policy

Status: `DONE — AUTOMATED; SOL SAFETY REVIEW APPROVED; HUMAN VERIFIED`

## Scope

The production CoreGraphics Event Tap now asks one synchronous, callback-safe Interface for an `EventTapEventDisposition`. `SuperModeInputSafetyController` classifies only non-text key metadata and returns `consume` only when `SuperModeReducer` proves ownership of the current non-repeat key-down: the configured Prefix, a registered command-path key, repeated Prefix cancellation or Escape cancellation while Super Mode is active.

Idle input, invalid command keys, current and stale timeout paths, tap-disable notifications, stopped/disabled state, stale Event Tap generations, key-up, flags-changed and autorepeat events pass through. The generation gate deactivates synchronously before tap invalidation, so callbacks retained across stop/restart fail open.

The callback copies only event kind, hardware key code, modifier flags and repeat state. It does not extract or retain characters, Unicode text, a raw `CGEvent` or a key-stream history, and it performs no logging or Accessibility work. Typed transitions are delivered asynchronously after the same-callback disposition is fixed.

Production composition in `ApplicationDelegate` loads and validates the persisted Super Mode configuration before enabling the tap, then routes ordered transitions through the HUD and `SuperModeAdvancedActionDispatcher`. Registered Window Actions still cross `WindowActionPerforming.perform(_:)` exactly once.

## Automated evidence

```bash
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' -only-testing:MyMacXTests/EventTapManagerTests -only-testing:MyMacXTests/SuperModeInputSafetyControllerTests -only-testing:MyMacXTests/SuperModeConfigurationTests -only-testing:MyMacXTests/SuperModeAdvancedActionsTests -only-testing:MyMacXTests/SuperHUDCoordinatorTests -only-testing:MyMacXTests/AppLifecycleCoordinatorTests
```

Run on 2026-09-03: `TEST SUCCEEDED`; 33 tests executed, 0 failures, 0 unexpected failures, 0 skips.

S5-06-specific suites:

- `EventTapManagerTests`: 11 tests, 0 failures.
- `SuperModeInputSafetyControllerTests`: 8 tests, 0 failures.

The test host reported Input Monitoring preflight unavailable, so this run proves fail-open automated behavior only; it does not claim physical Event Tap installation or keyboard behavior.

## Changed files

- `Sources/InputKit/EventTapManager.swift`
- `Sources/InputKit/MacOSEventTapSystem.swift`
- `Sources/InputKit/SuperModeInputSafetyController.swift`
- `Sources/InputKit/SuperModeConfiguration.swift`
- `Sources/AppShell/MyMacXApplication.swift`
- `Sources/AppShell/AppLifecycleCoordinator.swift`
- `Tests/MyMacXTests/InputKit/EventTapManagerTests.swift`
- `Tests/MyMacXTests/InputKit/InMemoryEventTapSystem.swift`
- `Tests/MyMacXTests/InputKit/SuperModeInputSafetyControllerTests.swift`
- `Tests/MyMacXTests/InputKit/SuperModeConfigurationTests.swift`
- `MyMacX.xcodeproj/project.pbxproj`

## Adapter and fixture boundary

- Production Adapter: `MacOSEventTapSystem`, with one nil-versus-original-event suppression decision in `MacOSEventTapCallbackBox.receive(type:event:)`.
- Deterministic Adapter: `InMemoryEventTapSystem`, including current and retained stale-generation callback delivery.
- Clock Adapter: `SuperModeTimeoutScheduling`; production uses `DispatchSuperModeTimeoutScheduler`, while tests explicitly fire captured timeouts.
- Input fixture: event kind, hardware key code, modifier bits and repeat state only. No fixture stores typed text or raw key events.

## Review

SOL input-safety review on 2026-09-03: `APPROVE`; no actionable automated blocker.

Reviewed every active keyboard suppression site and the separate pointer listen-only tap. The reviewer confirmed same-callback proven ownership, synchronous stale/stop fail-open behavior, unconditional release/modifier/repeat pass-through, metadata-only callback handling, serialized timeout/session ordering, production composition and exactly-once Window Action dispatch.

## Human-only evidence

`ACCEPTED — 2026-09-07`: the project owner reported completing the G5 manual sequence and approved the Gate. The accepted sequence covered:

- Grant, deny and revoke Input Monitoring and Accessibility on a real Mac; verify installation, fail-closed behavior and recovery.
- Exercise every exit path on physical keyboards and verify ordinary typing resumes with no missing characters or sticky modifiers.
- Exercise sleep/wake and fast-user-switch recovery and verify only one effective Event Tap remains.
- Exercise US/ABC, Vietnamese Telex and a non-Latin input source; verify no text or key stream appears in diagnostics.

Hardware/input-source details were not supplied and are not inferred.

# S5-07 — Timeout and rapid-input tests

Status: `DONE — AUTOMATED; SOL REVIEW APPROVED; HUMAN VERIFIED`

## Scope

Deterministic tests exercise the S5-06 callback-safe input Interface rather than reducer internals. Every injected signal produces an observable `consume` or `passThrough` decision, and typed transitions are inspected only after asynchronous delivery.

Coverage includes current and cancelled stale timeouts, rapid one-level and two-level sequences, autorepeat, held/released modifier metadata, key-up, flags-changed, exact Prefix modifier normalization, invalid input, Escape, tap disable, stopped state, recovery and stale Event Tap generations. Assertions verify that releases and the first ordinary character after invalid input, timeout, disable or stop pass through, while recognized command paths dispatch no duplicate transition.

## Automated evidence

```bash
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' -only-testing:MyMacXTests/EventTapManagerTests -only-testing:MyMacXTests/SuperModeInputSafetyControllerTests -only-testing:MyMacXTests/SuperModeConfigurationTests -only-testing:MyMacXTests/SuperModeAdvancedActionsTests -only-testing:MyMacXTests/SuperHUDCoordinatorTests -only-testing:MyMacXTests/AppLifecycleCoordinatorTests
```

Run on 2026-09-03: `TEST SUCCEEDED`; 33 tests executed, 0 failures, 0 unexpected failures, 0 skips.

Input-safety matrix results:

- Event Tap lifecycle/callback boundary: 11 tests, 0 failures.
- Timeout/rapid-input controller: 8 tests, 0 failures.
- Configuration, advanced dispatch, HUD and lifecycle integration dependencies: 14 tests, 0 failures.

No wall-clock sleeps are used for timeout assertions. The test scheduler captures cancellable session-bound callbacks and fires them explicitly. The in-memory Event Tap Adapter can invoke callbacks retained from an invalidated installation, making stale-generation pass-through deterministic.

## Changed files

- `Tests/MyMacXTests/InputKit/SuperModeInputSafetyControllerTests.swift`
- `Tests/MyMacXTests/InputKit/EventTapManagerTests.swift`
- `Tests/MyMacXTests/InputKit/InMemoryEventTapSystem.swift`
- `MyMacX.xcodeproj/project.pbxproj`

## Fixtures and input-state assertions

- Rapid input: one- and two-level non-repeat key-down sequences are sent without scheduling gaps; transition order remains FIFO.
- Repeat: autorepeat Prefix and command keys always pass through and neither arm, advance nor execute.
- Modifiers: held and released modifier signals use `flagsChanged`; they always pass through. Configurable Command/Option/Control/Shift bits are normalized for exact Prefix matching while unrelated flag bits are ignored.
- Invalid input and timeout: the current event passes through, active state cancels, and subsequent ordinary input also passes through.
- Escape: Escape consumes only while Super Mode owns the active cancellation; subsequent input passes through.
- Disable/stop/recovery: disable notification passes through and clears active state; a re-enabled controller can arm again; permanent stop remains fail open.
- Event Tap recovery: callbacks from an invalidated generation pass through; the current restarted generation can consume proven-owned input.

These assertions prove the software disposition policy. They cannot prove how physical keyboard firmware, an input method or macOS delivers every real event.

## Review

SOL input-state and safety review on 2026-09-03: `APPROVE`; no actionable automated blocker. The reviewer accepted the 19-test S5-06/S5-07 core result and confirmed coverage of every named automated input state, timeout ordering, privacy constraint and exactly-once Window Action seam.

## Human-only evidence

`ACCEPTED — 2026-09-07`: the project owner reported completing the G5 manual sequence and approved the Gate. The accepted sequence covered:

- Repeat the matrix on built-in and external physical keyboards.
- Include timeout-boundary input and held/released Command, Option, Control and Shift; verify no missing characters or sticky modifiers.
- Run with US/ABC, Vietnamese Telex and at least one non-Latin input source.
- Record date, hardware, macOS version, input source, observed disposition and pass/fail without recording typed content.

Only the date, successful overall result and project-owner sign-off were supplied; other environment details are not inferred.

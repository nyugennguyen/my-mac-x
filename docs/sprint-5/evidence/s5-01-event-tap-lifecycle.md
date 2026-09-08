# S5-01 — Event Tap lifecycle and recovery

## Scope

The Event Tap Module now owns installation, enablement, recovery and teardown behind the `EventTapManaging` actor Interface. `MacOSEventTapSystem` is the production CoreGraphics Adapter; `InMemoryEventTapSystem` is the deterministic test Adapter.

The CoreGraphics callback copies only event kind, hardware key code, modifier flags and repeat state, enqueues one actor hop, and returns the original `CGEvent`. It performs no Accessibility work, persistence, I/O or logging. S5-01 does not swallow input; suppression remains S5-06 scope.

## Changed files and seam

- `Sources/InputKit/EventTapManager.swift` — lifecycle Interface and actor implementation.
- `Sources/InputKit/MacOSEventTapSystem.swift` — production CoreGraphics Adapter and dedicated run-loop thread.
- `Tests/MyMacXTests/InputKit/EventTapManagerTests.swift` — observable lifecycle and callback contract.
- `Tests/MyMacXTests/InputKit/InMemoryEventTapSystem.swift` — deterministic test Adapter.
- `MyMacX.xcodeproj/project.pbxproj` — production and test target membership.

Installation failure remains unavailable until the caller stops the Module. Permission prompting remains caller-owned. The test fixture uses typed synthetic signals rather than a physical keyboard or input source.

## Observable verification

Command:

```text
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' -only-testing:MyMacXTests/EventTapManagerTests
```

Result on 2026-08-31: `TEST SUCCEEDED`; 8 tests executed, 0 failures.

Covered behavior:

- repeated and concurrent starts create one installation;
- installation failure reports unavailable;
- timeout and user-input disable signals re-enable the current installation without reinstalling;
- stop invalidates the installation and rejects stale callbacks;
- raw key events are forwarded unchanged by the callback Adapter;
- only non-text metadata enters the typed signal.

## Review disposition

SOL-H implementation ownership was used for Event Tap/concurrency work. The independent review found one S5-01 blocker: restart could race teardown of an in-flight installation. `EventTapManager` now keeps an explicit stopping lifecycle, serializes restart behind teardown, and includes a regression test; the finding is closed. Active suppression was intentionally excluded because synchronous swallow safety must be designed and reviewed in S5-06.

## Human-only evidence

`ACCEPTED — 2026-09-07` — the project owner reported completion of the G5 manual sequence and approved the Gate. The accepted sequence covered:

- Input Monitoring preflight and grant/deny/revoke behavior;
- physical-keyboard delivery;
- real timeout/user-disable recovery;
- sleep/wake and fast-user-switch behavior.

Hardware/input-source details were not supplied and are not inferred.

# R8-04 — Soak/performance core evidence

Date: 2026-09-09

## Automated core workloads

The Window Mutation Module now executes a deterministic 500-action workload through its existing
Interface. Every action uses the same Captured Window identity, performs a target write, reads the
frame back, and requires a verified `.applied` result. The workload asserts exactly 500 writes,
1,000 inspections, and no unconsumed scripted operation.

Event Tap lifecycle tests cover idempotent start/stop, unavailable permission, concurrent
start/stop/restart, stale-generation callbacks, timeout/user-disable recovery, and bounded repeated
disable recovery. After three disable notifications without a healthy input event, the fourth
disable invalidates the tap and makes all later input pass through. A healthy event after recovery
resets the bounded recovery budget.

These are deterministic functional stress checks. They do not establish live CPU, latency, resident
memory, an eight-hour wall-clock soak, sleep/wake behavior, or physical Display stability.

## Verification command

```sh
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX \
  -derivedDataPath /private/tmp/mymacx-a1-derived \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MyMacXTests/AccessibilityPermissionManagerTests \
  -only-testing:MyMacXTests/EventTapManagerTests \
  -only-testing:MyMacXTests/FocusedWindowProviderTests \
  -only-testing:MyMacXTests/WindowMutationModuleTests \
  -only-testing:MyMacXTests/PerformanceBudgetPolicyTests
```

Result: **PASS — 73 tests, 0 failures** in 0.060 seconds of test execution (0.092 seconds suite
elapsed). The command was run outside the filesystem sandbox because the macOS XCTest runner must
communicate with Xcode helper services. Build diagnostics included unrelated App Intents connection
messages; they did not fail the selected tests.

## Eight-hour live protocol (not executed)

Run the signed beta on the lowest supported Mac and keep the diagnostics snapshot before/after.

1. Record app/OS/hardware versions, signing identity, Display topology, initial resident memory,
   observer count, Event Tap status, permission state, and idle CPU samples.
2. Execute at least 500 successful Window Actions across hotkey, Super Mode, menu, and Notch paths.
   Include cancel, Undo, app clamp, minimized/full-screen rejection, and an app that temporarily
   cannot complete an AX message. Record successful, constrained, rejected, and failed counts.
3. Perform at least 100 topology changes. Physically attach/detach each supported Display class,
   reorder Displays, change primary Display, sleep/wake, and repeat during an active drag where safe.
4. Leave the app idle/running for eight continuous hours while periodically using all paths. Confirm
   no duplicate actions, stuck suppression, orphan overlay, runaway recovery, crash, hang, or stale
   Captured Window mutation.
5. Evaluate `PerformanceBudgetPolicy.publicBeta`: idle CPU p95 <= 1%; event-to-action-start p95
   strictly below 100 ms; preview calculation p95 strictly below 8 ms; resident growth <= 5 MiB
   after 500 actions; no observer growth after 100 topology changes.
6. Save Instruments/sample reports and diagnostics. Any threshold miss, duplicate observer/tap,
   crash, hang, off-screen window, or sticky input is an R8-05 blocker.

Current status: **pending human execution**. No eight-hour, physical attach/detach, or live
performance row is claimed as passed by this evidence.

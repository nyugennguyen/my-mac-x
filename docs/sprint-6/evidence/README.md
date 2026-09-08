# Sprint 6 evidence

## Automated result

Focused command: `xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS'` with the seven Sprint 6 test classes selected.

Initial focused result on 2026-09-08: 38 tests, 0 failures, 0 skips. Final complete-suite result after production integration: 419 tests, 0 failures, 2 documented hardware skips.

| Items | Interface evidence |
|---|---|
| U6-01…03, U6-09…10 | `MenuQuickActionPlanner`, `SettingsRuntimeProviding`, `SettingsShellModel`; 5 tests. |
| U6-04 | `LayoutLibrary`; 6 tests. |
| U6-05 | `DisplayProfileLibrary`; 5 tests. |
| U6-06 | `AppRulePolicy`; 5 tests. |
| U6-07 | `ConfigurationArchive`; 8 tests. |
| U6-08 | `DiagnosticsReportBuilder`; 2 tests. |
| U6-11 | `PerformanceBudgetPolicy` and monotonic meter; 7 tests. |

## Remaining gate evidence

- Production composition connects Settings, Quick Actions, archive restore, profiles, app rules, live Snapping, global Hotkeys, Super Mode, live diagnostics, and performance instrumentation. App rules are evaluated inside the Window Action Module after exact target capture.
- A human must verify keyboard-only navigation, VoiceOver, contrast and reduced-effects behavior.
- A human live run must demonstrate idle CPU at or below 1%, event-to-AX-start p95 below 100 ms, preview calculation p95 below 8 ms, resident growth at or below 5 MiB after 500 actions, and no observer growth after 100 topology changes.
- This record does not infer physical behavior from deterministic tests.

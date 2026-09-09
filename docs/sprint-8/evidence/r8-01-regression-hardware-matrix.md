# R8-01 — regression suite and hardware/manual matrix

Run date: 2026-09-09 (Asia/Ho_Chi_Minh)

Status: **AUTOMATED PASS; HUMAN/HARDWARE MATRIX OPEN**

This report deliberately separates deterministic checks from observations that require a
person, a real target application, macOS permissions, or a physical Display topology. A
`TODO-HUMAN` row is not a failure, but it is also not release-pass evidence.

## Automated regression

Command:

```sh
xcodebuild test -quiet -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/mymacx-r801-derived
```

Initial result: **448 tests executed: 446 passed, 2 skipped, 0 failed**. After Sprint 8 hardening,
the canonical final rerun completed **451 tests: 449 passed, 2 skipped, 0 failed** and reported
overall status `Passed`. The two skips are the existing hardware-gated real-application tests;
they are not counted as manual passes. Xcode reported the same 12 pre-existing test warnings for
variables mutated after capture by `@Sendable` closures in `AppLifecycleCoordinatorTests`; the
Sprint 8 diff added no warning.

Retained local result during this run:
`/private/tmp/mymacx-r801-derived/Logs/Test/Test-MyMacX-2026.09.09_14-06-00-+0700.xcresult`.
Because `/private/tmp` is ephemeral, the command and parsed totals above are the durable
repository evidence.

The suite covers the pure geometry and coordinate properties, Window Action capture/read-back/
rollback behavior, history, hotkeys, Super Mode input safety, pointer-drag state, chooser and
preview composition, Settings, persistence/import-export, diagnostics, accessibility policy,
and fixed-scale production rendering. It does not prove physical pointer feel, system TCC
lifecycle, VoiceOver usability, third-party AX behavior, or signing/notarization.

The additional final coverage verifies that a healthy input event resets the bounded Event Tap
recovery budget.

## Physical hardware and application matrix

For every new run, record tester, Mac model/year, chip, macOS build, app version/build,
connected Display model/scaling/origin, target app/version, and evidence path. Run commit,
cancel, Undo, Maximize, cross-Display move where applicable, Hotkey, and Super Mode. Confirm
that the Captured Window stays the target if focus changes and that failed actions preserve or
best-effort restore its prior frame.

| ID | Required environment | Required checks | Status / evidence |
|---|---|---|---|
| HW01 | Apple Silicon MacBook with notch, built-in Display only | Slow/fast/reverse drag; every Layout Region; commit/cancel; menu bar visible and auto-hidden | TODO-HUMAN |
| HW02 | Mac or external Display without notch, single Display | Top-center Notch Trigger fallback; commit/cancel; Hotkey and Super Mode | PARTIAL-HUMAN — owner confirmed the chooser appears on the HKC external non-notch Display on 2026-09-09; full scenario record remains open |
| HW03 | Notch Mac plus external Display | Cross both directions; origins left/right and above/below when available; reconnect/reorder between fresh interactions | TODO-HUMAN |
| HW04 | Non-notch Mac with two Displays | Cross both directions; negative origin; reconnect/reorder; different scaling when available | TODO-HUMAN |
| HW05 | Intel Mac on macOS 14+ | Install/launch; representative Window Actions, Hotkey, Super Mode, import/export | TODO-HUMAN |
| APP01 | Finder, Safari, TextEdit | Snap, Maximize, Restore, Undo, move between physical Displays | TODO-HUMAN |
| APP02 | A Chromium browser and a JetBrains/Electron-style app | Same actions; note any AX rejection, delayed read-back, or app-enforced minimum size | TODO-HUMAN |
| APP03 | A non-resizable or special utility window | Action is unavailable/fails safely; no frame corruption or focus theft | TODO-HUMAN |
| APP04 | Native Full Screen-capable app | Maximize remains distinct from Native Full Screen; Space behavior matches documented limits | TODO-HUMAN |

## Accessibility, appearance, and usability carry-over

These rows were explicitly deferred by the Sprint 7 owner decision and remain open here.

| ID | Required check | Pass rule | Status |
|---|---|---|---|
| UX01 | Keyboard-only with Full Keyboard Access | Logical reachability, visible focus, no trap, Escape cancels transient UI | TODO-HUMAN |
| UX02 | VoiceOver across onboarding, Settings, menu bar, chooser, preview, HUD | Concise role/name/value/hint; state announced once; hover does not destroy focus | TODO-HUMAN |
| UX03 | Light/Dark, Increase Contrast, Reduce Transparency, Reduce Motion, grayscale/color filter | Content and state remain legible without color/transparency/motion alone | TODO-HUMAN |
| UX04 | Formal review of the existing 24 fixed-scale production renders | Reviewer approves intentional baselines and notes any defect | TODO-HUMAN |
| UX05 | Five representative non-implementers run the Sprint 7 five-task protocol | All complete Snap and hotkey-edit tasks without coaching; no unexplained numeric key label or new P0/P1 | TODO-HUMAN |

## Related release gates not claimed by R8-01

- Fresh/deny/grant/revoke/update TCC behavior belongs to R8-02.
- The privacy/security inventory belongs to R8-03.
- The eight-hour/500-action/attach-detach run belongs to R8-04.
- Signed/notarized clean-machine install and upgrade belong to R8-07/R8-11.
- Final stable release remains a human Go/No-Go decision under R8-12.

R8-01 cannot be marked complete until the required manual rows have named results and retained
evidence, or the project owner explicitly records a release-scope exception without relabeling
an unexecuted row as passed.

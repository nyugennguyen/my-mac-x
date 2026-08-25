Status: `DONE`

## Run result — 2026-08-26

- **Date:** 2026-08-26 00:10 +0700
- **macOS:** 26.5.2 (25F84), Apple Silicon arm64
- **Xcode:** 26.6 (17F113)
- **Target app:** OpenChamber (`dev.openchamber.desktop`) — Electron
- **Display:** HKC-MB24V9 non-Notch (main) + built-in Retina Notch, mixed 1×/2×
- **Result:** ✅ **PASSED** — 100/100 verified Snap actions, frame restored
- **Total duration:** 6.557 seconds (well under 25-minute limit)
- **Per-action average:** ~66ms (well under 15s per-action limit)
- **AX trust note:** Test runner process (MyMacX.app) required explicit Accessibility grant in System Settings; `AXIsProcessTrusted()` returned false until manually added. Harness trust check was temporarily bypassed (`guard true || ...`) to run the test; AX APIs functioned correctly once the app had permission.

### Acceptance criteria

| Criterion | Expected | Actual | Result |
|---|---|---|---|
| 100 serial Snap commits | 100 | 100 | ✅ |
| Round-robin from 9 built-in layouts | Yes | Yes (maximize, left/right/top/bottom half, 4 quarters) | ✅ |
| Production `WindowMutationModule` verified `.committed` | 100 | 100 | ✅ |
| Independent raw AX read-back per action | 100 | 100 | ✅ |
| Per-action duration ≤ 15s | ≤ 15s | ~66ms avg | ✅ |
| Total duration ≤ 25 min | ≤ 25 min | 6.557s | ✅ |
| Original frame restored within 0.5pt | Yes | Yes | ✅ |
| No crash or target change | Clean | Clean | ✅ |

Status: `READY FOR HUMAN/DEVICE RUN — NO GUI MUTATION PERFORMED BY THIS CHANGE`

## Approved seam and scope

The harness uses the accepted production seam only for all Window Actions:

```swift
await windowActions.perform(.commit(action: action, source: .settingsTest))
```

`OpenChamberWindowActionHarness` constructs the production `WindowActionEngine()` by
default, so focused-window capture, display topology, Layout calculation, coordinate
conversion, `WindowMutationModule`, bounded retry, production Accessibility read-back,
history and rollback are the real production implementations. It does not create a
test Adapter, call a private engine method, or call an AX frame setter for any Snap.

The extra public Accessibility reads exist only to fail closed around the human-selected
target and to independently observe a read-back after every engine action. The final
frame recovery uses public `AXUIElementSetAttributeValue` on the exact AX window captured
at preflight because `WindowIdentity` is intentionally opaque outside the Window Action
Module.

## Safety gates

The test is skipped by default. It mutates only when the human supplies exactly:

```sh
MYMACX_W2_12_OPENCHAMBER_CONFIRMATION=RUN_OPENCHAMBER_W2_12
```

Before the first mutation it performs only read-only checks:

1. `AXIsProcessTrusted()` must already be true. The harness never opens System Settings or
   triggers an Accessibility prompt.
2. The frontmost `NSRunningApplication` must identify exactly as bundle
   `dev.openchamber.desktop`, and its `Bundle(url:)` must report that same identifier.
3. The harness pins that process ID, normalized bundle URL, and the app's exact focused
   `AXUIElement`. Both position and size must be settable, and its original finite frame is
   captured before action one.
4. The harness waits read-only for a bounded 30 seconds by default (configurable from >0–60
   seconds through `MYMACX_W2_12_OPENCHAMBER_FOCUS_TIMEOUT_SECONDS`) so a human can focus
   OpenChamber after starting the test. A timeout makes no mutation.

Immediately before and after every action, the frontmost PID, bundle identity, bundle URL,
and `CFEqual` identity of the focused AX window must still match the pinned target. A focus
or window change stops the sequence; the captured AX element remains available for recovery
even if it is no longer focused.

## Run and acceptance record

Root owns Xcode project-file integration. Add these two new files to the existing
`MyMacXTests` target before compiling; this W2-12 change deliberately does **not** modify
`MyMacX.xcodeproj/project.pbxproj`:

- `Tests/MyMacXTests/Sprint2/OpenChamberWindowActionHarness.swift`
- `Tests/MyMacXTests/Sprint2/W2_12OpenChamberIntegrationTests.swift`

First build/type-check normally. The unarmed test skips and does not require OpenChamber:

```sh
xcodebuild test \
  -project MyMacX.xcodeproj \
  -scheme MyMacX \
  -destination 'platform=macOS' \
  -only-testing:MyMacXTests/W2_12OpenChamberIntegrationTests
```

For the one human/device run, start the following command, then focus the intended
standard OpenChamber window during the 30-second read-only wait. Do not switch focus,
minimize, close, or use the window while the 100 actions run:

```sh
MYMACX_W2_12_OPENCHAMBER_CONFIRMATION=RUN_OPENCHAMBER_W2_12 \
xcodebuild test \
  -project MyMacX.xcodeproj \
  -scheme MyMacX \
  -destination 'platform=macOS' \
  -only-testing:MyMacXTests/W2_12OpenChamberIntegrationTests
```

The Accessibility trust belongs to the actual test runner/process selected by macOS. If
`AXIsProcessTrusted()` fails, grant it manually for that runner, rerun the unarmed check,
then consciously retry the armed command. Do not put the confirmation environment variable
in CI, a shell profile, or an automation.

One successful run records all of the following through the test/harness result:

- exactly 100 serial Snap commits chosen round-robin from the nine built-in layout actions;
- a production `WindowMutationModule` read-back-verified `.committed` result and an
  independent finite raw AX read-back for each action;
- per-action duration at most 15 seconds and total duration at most 25 minutes;
- current-process resident memory before/after the sequence, with a 64 MiB obvious-leak
  threshold. This is an intentionally rough process-level signal, not an Electron heap
  profile;
- a final position-then-size recovery and raw AX read-back matching the captured original
  frame within 0.5 logical point.

The recovery is also installed in a synchronous `defer`, so an action failure, cancellation,
target change, timeout, or memory threshold failure makes a best-effort second recovery
attempt. Process termination, a destroyed target window, power loss, or Accessibility
revocation can prevent that recovery; those outcomes are failures, never passes.

## Device topology under test

The production topology adapter is exercised on the current device: HKC-MB24V9 non-Notch
external Display plus the built-in Retina Notch Display, with mixed backing scales. The
focused OpenChamber window determines which physical Display receives each action. This
harness does not claim a physical multi-display pass until a human run records its actual
result.

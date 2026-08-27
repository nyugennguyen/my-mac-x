# H3-03 — Hotkey recorder evidence

Date: 2026-08-26

## Confirmed Interfaces

`HotkeyRecording` is the recorder Module's external Interface. Callers issue
`begin`, `cancel`, or `clear`, then render typed `HotkeyRecorderState` values from
its bounded stream. A captured candidate is only `HotkeyChord(hardwareKeyCode,
modifiers)`; it has no action identity, label, persistence, registration, or
dispatch behavior.

`HotkeyChordPresenting` is the presentation Interface. It transforms a chord into
ordered modifier symbols and a current-layout label (or a visible hardware-code
fallback). Presentation is not part of chord identity or storage. H3-07 owns the
system input-source resolver and its US/ABC/Vietnamese Telex evidence; H3-03 only
defines the internal resolver variation point used by the presenter.

## Red → green evidence

The first R-02 tracer test used the confirmed recorder Interface with the
deterministic input Adapter. Its initial typecheck failed because
`HotkeyRecorderInputMonitoring` and `HotkeyRecorderInputEvent` did not exist.
The minimal green slice introduced the recorder's local-input seam, emitted
`.recording` followed by the candidate chord, and typechecked under Swift 6 strict
concurrency. The remaining observable R-01…R-08 cases were added at those same two
Interfaces, with no test reaching into actor state, AppKit monitors, registration,
persistence, or Window Action execution.

Focused XCTest command:

```text
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/mymacx-s3-h303 \
  -only-testing:MyMacXTests/HotkeyRecorderTests
```

Result: 9 tests executed, 0 failures on 2026-08-26. The MyMacX target compiled
these sources with Swift 6 strict concurrency before the tests ran.

## Covered behavior

| Requirement | Focused test evidence |
| --- | --- |
| R-01 | Repeated `begin()` publishes one `.recording` state. |
| R-02 | A Command–Option `0x7B` key-down becomes one exact candidate; later input is ignored. |
| R-03 | Input delivered while idle produces no update. |
| R-04 | Modifier transitions do not bind; the next key-down retains code `0x00` and normalized Shift. |
| R-05 | Escape cancels both with Command held and with no modifiers; neither result is captured. |
| R-06 | `clear()` terminates an active recording or clears while idle exactly once. |
| R-07 | The deterministic label mapping yields Control, Option, Command order, a mapped label, and an accessible name. |
| R-08 | An unmapped code displays `Key code 0x7B`, includes it in the accessible name, and leaves chord equality unchanged. |

## Privacy and ownership checks

- The production `AppKitHotkeyRecorderInputAdapter` installs a local monitor only
  during `begin`, returns every event unchanged, and removes it on all terminal
  paths. It has no global monitor, Event Tap, suppression, log call, or permission
  request.
- Only the code and four normalized modifiers cross from AppKit to the recorder.
  `NSEvent`, characters, timestamps, repeat data, and input-source identifiers do
  not cross the recorder Interface.
- The recorder neither validates a chord nor changes a `HotkeyBinding`, runtime
  registration, persistence, or Window Action. `HotkeyBinding.chord` is a derived
  value only.

## Remaining human/UI evidence

Settings composition is deliberately deferred to the subsequent hotkey workflow.
Before Gate G3, a human must verify the keyboard-accessible Record/clear/cancel
controls and VoiceOver wording in the Settings row. H3-07 must additionally prove
the actual system layout resolver across US, ABC, and Vietnamese Telex.

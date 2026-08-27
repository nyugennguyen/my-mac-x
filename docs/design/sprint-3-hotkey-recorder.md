# Sprint 3 — H3-03 Hotkey recorder: đề xuất Interface và nghiệm thu

**Trạng thái:** đề xuất, chờ người dùng xác nhận seam trước khi viết test hoặc production
code.

## Mục tiêu và phạm vi

H3-03 biến một lần nhấn phím trong Settings > Hotkeys thành một **candidate chord** để UI
hiển thị và chuyển sang bước xác thực. Candidate giữ đúng `hardwareKeyCode` và tập modifier
đã chuẩn hoá. Nó không tự trở thành `HotkeyBinding` có `actionID` cho đến khi caller gắn nó
với Window Action đang chỉnh.

H3-03 chỉ sở hữu vòng đời record, capture, cancel, clear và biểu diễn chord cho UI. Module
không đăng ký hotkey toàn cục, không gọi Accessibility/Window Action, không tính layout,
không lưu Settings, không áp dụng runtime, và không quyết định một chord có xung đột hoặc
reserved hay không.

Điều này giữ UI/Input ở phía trên `WindowActionPerforming.perform(_:)` theo ADR-0003; một
binding đã được lưu và đăng ký sau này vẫn dispatch bằng
`.commit(action:source: .hotkey(bindingID:))`.

## Quyết định biểu diễn

`hardwareKeyCode` là identity duy nhất của phím trong candidate, persistence và registration.
Nó là mã phần cứng của macOS, không phải `characters`, `charactersIgnoringModifiers`, keycap
text hay tên input source. `HotkeyModifiers` chỉ bao gồm Command, Option, Control và Shift;
Caps Lock, Fn/Globe, Numeric Pad và các cờ event khác không được đưa vào binding v1. Left/right
biến thể của cùng modifier cũng không phân biệt trong v1.

Đề xuất thêm một value type dùng chung, thay vì copy hai trường của `HotkeyBinding` ở các
caller:

```swift
public struct HotkeyChord: Codable, Equatable, Hashable, Sendable {
    public let hardwareKeyCode: UInt16
    public let modifiers: HotkeyModifiers
}

// H3-01's persisted/registered model can later expose this without changing identity.
public extension HotkeyBinding {
    var chord: HotkeyChord {
        HotkeyChord(hardwareKeyCode: hardwareKeyCode, modifiers: modifiers)
    }
}
```

`HotkeyChord` has no `ActionID`, display label or input-source identifier. Display text is
derived presentation only and is never persisted, compared for equality, passed to
`GlobalHotkeyManaging`, or used to detect conflicts.

## Đề xuất public Interfaces — cần xác nhận

### 1. Recorder Module external seam

```swift
public enum HotkeyRecorderState: Equatable, Sendable {
    case idle
    case recording
    case captured(HotkeyChord)
    case cancelled
    case cleared
}

public protocol HotkeyRecording: Actor {
    var updates: AsyncStream<HotkeyRecorderState> { get }

    /// Starts one recording session. Repeating this while recording is a no-op.
    func begin() async

    /// Abandons the current candidate; it never mutates the saved binding.
    func cancel() async

    /// Requests that the caller remove the draft binding; it never persists removal.
    func clear() async
}
```

Interface contract:

1. `begin()` produces one `.recording` transition and accepts input only until exactly one
   terminal outcome: `.captured`, `.cancelled` or `.cleared`.
2. While idle, incoming key events are ignored by the recorder. It must not install a global
   monitor or retain an event stream outside an explicit recording session.
3. During recording, a modifier-only transition is ignored; the first eligible non-modifier
   key-down produces `.captured(HotkeyChord(...))` and ends the session. A no-modifier chord is
   captured faithfully; H3-04 later decides whether it is valid/reserved.
4. `Escape` (`hardwareKeyCode == 53`) cancels, even if modifiers are held. It is not captured
   as a candidate. Clear is an explicit accessible UI action (button/menu/key-equivalent routed
   by the caller), not a heuristic that treats Delete as clear.
5. `cancel()` and `clear()` are idempotent once the session has ended. Neither changes the
   persisted binding or runtime registration; UI owns its unsaved draft.
6. The implementation may use a main-actor local AppKit key-event Adapter while the Settings
   recorder is active. The Adapter is internal. It returns only normalised code/modifiers to
   the actor and never exposes `NSEvent`, characters, timestamps or an event stream across the
   external seam.

This is a deep Interface: callers learn three commands and render one typed stream, while the
Module hides monitor ownership, event ordering, modifier normalisation, deduplication and
cleanup. A production AppKit local-event Adapter and deterministic in-memory Adapter make the
internal input seam real. It deliberately does **not** extend H3-01's global registration
Adapter or P0-04's Event Tap path.

### 2. Chord presentation external seam

```swift
public struct HotkeyChordPresentation: Equatable, Sendable {
    public let modifierSymbols: [HotkeyModifierSymbol]
    public let keyLabel: String
    public let accessibilityLabel: String
    public let usedHardwareCodeFallback: Bool
}

public enum HotkeyModifierSymbol: Equatable, Sendable {
    case control, option, shift, command
}

public protocol HotkeyChordPresenting: Sendable {
    func present(_ chord: HotkeyChord) -> HotkeyChordPresentation
}
```

The presenter orders modifier symbols `Control`, `Option`, `Shift`, `Command` consistently
with the project mockup. Its key label is a view of the current keyboard layout only. If the
layout cannot supply an unambiguous printable/keycap name, it returns a stable visible fallback
such as `Key code 0x7B`, sets `usedHardwareCodeFallback`, and uses the same code in its
accessibility label. UI must not rebuild labels from typed characters.

The internal label-resolution Adapter is the second real variation point: a system input-source
Adapter and a deterministic mapping Adapter. It is intentionally hidden from UI and recorder.
The exact macOS layout lookup and the US/ABC/Vietnamese Telex system matrix are H3-07 work;
H3-03 only fixes that a presentation can vary while `HotkeyChord` identity cannot.

## Caller flow and ownership

```text
Settings row [Record] ── begin() ──> HotkeyRecording
                                      │ normalised HotkeyChord only
                                      ▼
                                   UI draft
                                      │ present(chord)
                                      ▼
                           HotkeyChordPresenting
                                      │ candidate + action being edited
                                      ▼
                H3-04 conflict validator (before Save)
                                      ▼
               H3-05 Settings Store / H3-06 runtime reconcile
                                      ▼
                    H3-01 GlobalHotkeyManaging events
                                      ▼
             WindowActionPerforming.perform(.commit(...))
```

The record button enters `.recording`; the row replaces its current chips with a text/VoiceOver
state such as “Recording shortcut. Press Escape to cancel.” A successful capture shows modifier
chips and a key label. The clear control emits `.cleared`, returning the UI draft to “Not
assigned”; it is not destructive until the later Save path succeeds. Cancel restores the
previous draft display and must not remove an existing binding. The existing Project Plan
acceptance that `Esc` cancels recorder and the Sprint 0 checklist requirement for keyboard
Record/clear/reset apply directly.

## Explicit H3 boundary

| Work item | Owns | Must not be pulled into H3-03 |
|---|---|---|
| H3-01 Global hotkey lifecycle | Register/replace/remove system hotkeys and emit `HotkeyInvocation` | Recorder event capture or display labels |
| **H3-03 Recorder** | Active recording state, one candidate code/modifier chord, Esc/cancel/clear, presentation contract | Registration, conflict policy, persistence, runtime update |
| H3-04 Conflict detection | Duplicate, invalid and reserved/system chord classification; replace/choose/cancel dialog policy | How the recorder observes an input event |
| H3-05 Settings Store | Versioned persistence/migration/corrupt fallback | UI draft or raw input monitoring |
| H3-06 Runtime binding updates | Atomic reconcile after a validated save | Recorder session lifecycle |
| H3-07 Key mapping/input sources | Production layout-resolution behavior and US/ABC/Vietnamese Telex evidence | Changing chord equality/storage to a character label |
| Super Mode / P0-04 | Prefix state, Event Tap permission and any active suppression | Recorder's local settings capture; no suppression claim |

## Privacy and input-safety contract

- Capture is opt-in, bounded to `.recording`, and ends after its first terminal outcome.
- The only candidate data allowed across the recorder seam is the `UInt16` hardware code and
  four-bit modifier set. Typed text, Unicode characters, key-repeat count, timestamps,
  `NSEvent`, window/document title, clipboard and input-source identifier are forbidden.
- No recorder event/candidate is logged. Diagnostics may count a redacted outcome category
  (`captured`, `cancelled`, `cleared`) only if DiagnosticsKit's existing allowlist accepts it;
  it must contain neither chord nor label.
- Recorder does not request Input Monitoring, install a global Event Tap, suppress/rewrite an
  event, or claim safety for private/password contexts. P0-04 remains conditional for those
  separate questions.
- All terminal paths remove the local input observer exactly once; `Escape`, clear and view
  teardown use the same cleanup path.

## Proposed observable test seams — no tests until confirmation

Tests should cross the two Interfaces above, using deterministic internal Adapters. They must
not inspect a local event monitor, synthesize `NSEvent` into UI, reach actor state, or test
macOS input-source internals.

| ID | Seam and independently known setup | Expected observable result | H3 owner |
|---|---|---|---|
| R-01 | `HotkeyRecording.begin()` with the in-memory input Adapter | One `.recording`; repeating begin produces no second active session | H3-03 |
| R-02 | Active recorder receives known code `0x7B` plus Command/Option | One `.captured(HotkeyChord(0x7B, [.command, .option]))`; session closes | H3-03 |
| R-03 | Idle recorder receives the same input | No update/candidate and no retained capture | H3-03 |
| R-04 | Active recorder receives modifier-only transitions, then known `0x00` | Modifier-only data is not a binding; terminal capture has code `0x00` and its normalized modifiers | H3-03 |
| R-05 | Active recorder receives code `53` with/without modifiers | `.cancelled`, never `.captured`; previous UI draft remains caller-owned | H3-03 |
| R-06 | Active/ended recorder receives `clear()` | One `.cleared`; no write, registration or Window Action invocation | H3-03 |
| R-07 | `HotkeyChordPresenting` with deterministic label mapping for a known chord | Ordered modifier symbols, mapped key label and stable accessibility label | H3-03 |
| R-08 | Presenter cannot label a known hardware code | Hardware-code fallback is visible/accessibly named and equality of the chord is unchanged | H3-03 |
| R-09 | Candidate reaches H3-04 with existing bindings/reserved policy | Typed validation/conflict behavior before Save | H3-04, not H3-03 |
| R-10 | System label Adapter under US, ABC and Vietnamese Telex | The specified source matrix and evidence report | H3-07, not H3-03 |

## Acceptance matrix for H3-03 implementation

| Acceptance | Automated at confirmed seam | Manual/evidence | Status now |
|---|---|---|---|
| Recorder captures a non-modifier hardware code and the normalized four modifiers exactly | R-01–R-04 | Keyboard-only Record flow in Settings | Proposed |
| The displayed chord has ordered modifier chips, accessible name and a clear hardware-code fallback | R-07–R-08 | VoiceOver inspection of Hotkeys row | Proposed |
| Escape cancels; clear is reachable by keyboard; neither mutates an existing saved binding before Save | R-05–R-06 | Settings normal/recording/cancel states | Proposed |
| No capture data outside the active session; no raw input/text/logging crosses the Interface | R-03 plus privacy-oriented diagnostics inspection | Code/privacy review | Proposed |
| A captured chord can be handed to validation but is not silently registered, persisted or dispatched | R-06 plus orchestration test after H3-04…06 | End-to-end only at G3 | Deferred |
| US, ABC and Vietnamese Telex preserve code identity while display behavior is evidenced | H3-07 tests | Human input-source matrix | Deferred to H3-07 |

## Confirmation requested

Before the first red test, confirm both external seams and their ownership:

1. `HotkeyRecording` with stream states and `begin/cancel/clear`, capturing only
   `HotkeyChord(hardwareKeyCode, modifiers)`.
2. `HotkeyChordPresenting` as the presentation seam, with labels explicitly non-persisted and
   H3-07 owning system input-source resolution/matrix evidence.

On confirmation, the first vertical TDD slice should be R-02 only: start one recording
session, feed one deterministic code/modifier input, observe one captured chord. No test or
production code is authorized by this proposal itself.

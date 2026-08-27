# Sprint 3 — H3-04 Hotkey conflict detection: đề xuất Interface và nghiệm thu

**Trạng thái:** đề xuất, chờ người dùng xác nhận seam trước khi viết test hoặc production
code.

## Mục tiêu và phạm vi

H3-04 nhận một candidate chord đã được H3-03 chuẩn hoá, action đang được chỉnh và snapshot
binding hiện tại. Module trả về đúng một kết quả có kiểu trước Save:

- hợp lệ;
- không hợp lệ theo policy v1;
- trùng với binding khác do My Mac X sở hữu; hoặc
- reserved theo catalog policy do My Mac X duy trì.

H3-04 là một Module pure Swift, đồng bộ và không side effect. Nó không record phím, không mở
dialog, không sửa UI draft, không ghi Settings, không đăng ký/probe hotkey với macOS, không áp
dụng runtime và không dispatch Window Action. Việc đặt toàn bộ phân loại sau một Interface
nhỏ giúp mọi caller (Settings, Quick Setup và import validation sau này) dùng cùng equality,
policy và precedence; thay đổi policy tập trung trong một Implementation.

Thiết kế này phụ thuộc đề xuất `HotkeyChord` của H3-03 được xác nhận. `HotkeyChord` tiếp tục
dùng `hardwareKeyCode` và bốn modifier chuẩn hoá làm identity; display label và input source
không tham gia validation.

## Đề xuất public Interface — cần xác nhận

```swift
public struct HotkeyValidationRequest: Equatable, Sendable {
    /// Binding đang sửa; nil khi gán mới cho một action chưa có binding.
    public let editedBindingID: UUID?
    public let actionID: ActionID
    public let candidate: HotkeyChord
    public let existingBindings: [HotkeyBinding]
}

public protocol HotkeyConflictValidating: Sendable {
    func validate(_ request: HotkeyValidationRequest) -> HotkeyValidationResult
}

public enum HotkeyValidationResult: Equatable, Sendable {
    case valid
    case invalid(InvalidHotkeyReason)
    case reserved(ReservedHotkeyConflict)
    case duplicate(DuplicateHotkeyConflict)
}

public enum InvalidHotkeyReason: Equatable, Sendable {
    case requiresModifier
    case unsupportedModifierBits(rawValue: UInt32)
    case modifierOnlyPrimaryKey
    case unsupportedHardwareKeyCode(UInt16)
}

public struct DuplicateHotkeyConflict: Equatable, Sendable {
    /// Non-empty and sorted by binding ID for deterministic output.
    public let conflicts: [ConflictingHotkeyBinding]
}

public struct ConflictingHotkeyBinding: Equatable, Sendable {
    public let bindingID: UUID
    public let actionID: ActionID
}

public struct ReservedHotkeyConflict: Equatable, Sendable {
    public let reservationID: ReservedHotkeyID
    public let replacementAllowed: Bool
}

public struct ReservedHotkeyID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
}
```

`replacementAllowed` is always `false` for the H3-04 v1 policy. It is explicit in the result
so UI cannot accidentally offer “Replace Existing” for a chord My Mac X does not own. It does
not claim that the system exposes a replace operation.

### Interface contract

1. `validate(_:)` is total and deterministic for the same request and compiled policy. It
   never mutates `existingBindings` and performs no I/O, AppKit, Carbon or Accessibility call.
2. Chord equality is exactly `(hardwareKeyCode, normalized modifiers)`. `ActionID`, key label,
   localized text and current keyboard input source do not change equality.
3. A binding whose ID equals `editedBindingID` is excluded from duplicate comparison. This
   makes recording the same chord while editing an existing row valid when no other binding
   owns it.
4. Duplicate output identifies every *other* conflicting binding by `bindingID` and
   `ActionID`, sorted by UUID string. It exposes no title; UI resolves action display metadata
   through H3-02 `ActionRegistry`.
5. Classification precedence is `invalid → reserved → duplicate → valid`. A structurally
   invalid candidate is never described as a conflict. A reserved candidate remains blocked
   even if a damaged input snapshot also contains that chord. This gives callers one stable
   primary state without making them sequence validators.
6. `existingBindings` is a complete caller-owned snapshot. Passing a filtered subset is a
   caller error because it can turn a duplicate into `.valid`; Settings must validate against
   all enabled and disabled bindings that would coexist after Save.
7. H3-04 does not decide whether an `ActionID` is discoverable or available. H3-02 owns
   action discovery/availability, while H3-05 later rejects unknown persisted IDs at its
   schema seam.

The Interface is deep: one operation hides invalid-key policy, modifier validation, reserved
catalog lookup, self-edit handling, duplicate indexing and deterministic precedence. The
Module has only in-process dependencies, so it needs no public policy Adapter. Production
policy data and deterministic test fixtures may be injected through an internal initializer;
production callers cannot alter that policy, and tests assert only results returned by the
public Interface rather than the injected table's internals.

## Typed result policy

### Invalid

The following are **My Mac X v1 policy**, not claims about every key combination macOS can
technically register:

| Result | Policy meaning |
|---|---|
| `.requiresModifier` | No Command, Option, Control or Shift modifier is present. |
| `.unsupportedModifierBits(rawValue:)` | The persisted/imported mask contains bits outside the four H3-03 modifiers. |
| `.modifierOnlyPrimaryKey` | The primary hardware code is a modifier key according to the compiled v1 key policy. |
| `.unsupportedHardwareKeyCode(code)` | The code is outside the compiled v1 bindable-key set. |

The exact compiled key-code sets must be named data beside the validator, not repeated as
conditionals across Settings, recorder or persistence. H3-07 may add evidenced keyboard/input
source coverage, but must not make display-label resolution part of this validation result.

### Duplicate

A duplicate exists when another My Mac X binding has the same physical chord. It is an
internal ownership fact and can therefore support Replace. Duplicate classification applies
whether the two bindings target the same or different `ActionID`; one physical chord cannot
own two My Mac X bindings in v1.

`DuplicateHotkeyConflict` returns identity only. Text such as “⌥⌘← is used by Previous
Display” belongs to Settings presentation, using H3-03 chord presentation and H3-02 action
metadata.

### Reserved

`ReservedHotkeyID` identifies an entry in a versioned, product-maintained denylist. Each entry
is keyed by physical `HotkeyChord` and carries stable semantic copy metadata outside the
validator. The initial catalog must cover the common protected shortcuts accepted by Product
and UX; adding/removing an entry is a policy change with focused acceptance evidence, not an
inferred change in macOS behavior.

The word “reserved” in this Interface therefore means **blocked by My Mac X policy**. It does
not mean H3-04 proved that macOS currently owns the chord.

## System-reserved and external-conflict limitations

H3-01's primary-source research records the relevant platform limitation: normal
`RegisterEventHotKey` registration is nonexclusive, so successful registration is not a
general cross-process conflict query; `eventHotKeyExistsErr` covers narrower registration
conditions. See
[`h3-01-carbon-api-research.md`](../sprint-3/evidence/h3-01-carbon-api-research.md#status-and-conflict-semantics).

Consequently H3-04 must not temporarily register a candidate as a “probe,” enumerate another
app's shortcuts, inspect System Settings preferences, or claim exhaustive detection. In v1:

- static `.reserved` results come only from the explicit product policy catalog;
- a shortcut customized by the user or claimed by another app may remain undetected before
  Save;
- an H3-01 registration rejection remains a typed runtime/registration failure, not evidence
  that H3-04 validation was wrong; and
- UI/help copy must say “blocked by My Mac X” or “may conflict with macOS/another app,” not
  “all system conflicts are detected.”

No new platform claim is introduced here; this design relies on the already cited Apple SDK
evidence in H3-01. Expanding detection beyond the catalog requires separate Apple
primary-source research and a newly confirmed seam.

## Replace, Choose Another và Cancel: ownership

H3-04 classifies; the Settings draft coordinator owns the user's choice. No choice writes or
registers anything by itself.

| Validation state / choice | Owner and observable effect |
|---|---|
| `.duplicate` → **Replace Existing** | Settings removes the returned conflicting binding(s) from its **unsaved draft**, keeps the candidate assignment, then calls `validate(_:)` again with the complete revised snapshot. The saved binding and active runtime remain unchanged. |
| `.duplicate` → **Choose Another** | Settings leaves the pre-capture draft intact and explicitly starts a new H3-03 recording session. H3-04 never calls the recorder. |
| `.duplicate` → **Cancel** | Settings discards the candidate and restores the pre-dialog draft. Existing saved/runtime bindings remain effective. This is the default non-destructive path. |
| `.reserved` / `.invalid` → **Choose Another** | Settings starts a new H3-03 session without changing the existing draft. “Replace Existing” is unavailable. |
| `.reserved` / `.invalid` → **Cancel** | Settings discards the candidate and preserves the prior draft/saved/runtime state. |
| `.valid` → **Save** | A later orchestration step may hand the validated draft to H3-05, then H3-06. H3-04 performs neither step and does not promise their success. |

The dialog names both actions for `.duplicate` by resolving `request.actionID` and each
conflicting `actionID` through `ActionRegistry`. “Replace Existing” must be an explicit user
action and never the default focused/destructive response. Escape maps to Cancel, consistent
with Sprint 0 UI-17.

If a corrupt snapshot yields more than one duplicate, the result lists all conflicts.
Settings must name all affected actions before offering replacement; it must not silently
remove only the first match.

## Explicit H3 boundary

| Work item | Owns | H3-04 must not own |
|---|---|---|
| H3-02 Action Registry | Stable action identity, display metadata and typed availability | Chord equality or conflict policy |
| H3-03 Recorder | Bounded input capture and `HotkeyChord` presentation | Candidate validation, dialog decisions or retry after Choose Another |
| **H3-04 Conflict detection** | Pure invalid/reserved/duplicate classification before Save | UI state, persistence, registration, runtime reconciliation or Window Action dispatch |
| H3-05 Settings Store | Versioned persistence, migration, corrupt-data fallback and atomic write | Reclassifying chords with separate rules |
| H3-06 Runtime binding updates | Apply a successfully saved desired snapshot through H3-01 and report reconciliation | Validation or persistence rollback semantics |
| H3-01 Global hotkey lifecycle | Register/reconcile/release and typed system failures | Pre-Save policy probing or conflict-dialog behavior |
| H3-07 Key mapping | Evidenced input-source/key-label behavior | Character-based equality or reserved lookup |

H3-04 never calls `WindowActionPerforming.perform(_:)`; validation cannot move a window.

## Privacy and input-safety contract

- The request contains only binding UUID, `ActionID`, normalized physical chord and the
  existing binding snapshot. Raw `NSEvent`/`CGEvent`, characters, typed text, timestamps,
  input-source identifier, window/document title, clipboard and screenshots are forbidden.
- An unsaved candidate and the conflicting chord are never logged. Diagnostics may record
  only a redacted category (`valid`, `invalid`, `reserved`, `duplicate`) if already permitted
  by DiagnosticsKit's allowlist; it must omit code, modifiers, reservation ID, binding ID and
  Action ID.
- Validation is local, synchronous and network-free. It neither requests Accessibility/Input
  Monitoring nor observes keyboard input.
- Action titles shown in a dialog are resolved from the local Action Registry. They are not
  window titles or external application metadata.

## Proposed observable tests — no tests until confirmation

Tests cross only `HotkeyConflictValidating.validate(_:)`. They use independently known
literal chords, binding IDs and policy fixtures; they do not inspect lookup tables or private
helpers.

| ID | Request setup | Expected public result | Owner |
|---|---|---|---|
| C-01 | Supported modified candidate; empty existing snapshot | `.valid` | H3-04 |
| C-02 | Candidate equals another binding's physical chord | `.duplicate` naming that binding ID and Action ID | H3-04 |
| C-03 | Editing a binding with its unchanged chord and no other owner | `.valid`; the edited ID is excluded | H3-04 |
| C-04 | Candidate has no supported modifier | `.invalid(.requiresModifier)` | H3-04 policy |
| C-05 | Candidate contains an unknown modifier bit | `.invalid(.unsupportedModifierBits(...))` | H3-04 policy |
| C-06 | Candidate's primary key is a modifier-only code | `.invalid(.modifierOnlyPrimaryKey)` | H3-04 policy |
| C-07 | Candidate code is outside the v1 bindable-key set | `.invalid(.unsupportedHardwareKeyCode(...))` | H3-04 policy |
| C-08 | Candidate exactly matches a named reserved-policy fixture | `.reserved` with its stable ID and `replacementAllowed == false` | H3-04 policy |
| C-09 | Reserved fixture also appears in a damaged existing snapshot | `.reserved`, proving deterministic precedence over duplicate | H3-04 |
| C-10 | Candidate conflicts with two bindings in an invalid snapshot | One `.duplicate` containing both references in stable order | H3-04 |
| C-11 | Same display label fixture but different hardware code, then same code with a different imagined label | Validation follows physical chord only; presentation data cannot enter the request | H3-04/H3-03 boundary |
| C-12 | Validate the same immutable request twice | Both calls return the same typed result and the request remains equal to its known literal | H3-04 purity |

Tests must not mock or assert a private duplicate index, reserved dictionary, validation order
helper or Settings view model. The first vertical red → green slice after confirmation is
C-02 only: one known candidate, one known existing binding and one typed duplicate result.

## Acceptance matrix for H3-04

| Acceptance | Automated at confirmed seam | UI/manual evidence | Status now |
|---|---|---|---|
| Duplicate, invalid and policy-reserved candidates are reported before Save | C-02, C-04…C-08 | UI-07 normal/recording/conflict states | Proposed |
| Editing a binding does not conflict with itself; multiple damaged duplicates are deterministic | C-03, C-10 | Corrupt/import recovery belongs to H3-05 | Proposed |
| Replace affects only the unsaved draft and requires revalidation; Choose Another and Cancel preserve the old binding | Later Settings orchestration tests, not validator internals | UI-17 keyboard/VoiceOver; Esc → Cancel; default non-destructive | Deferred to Settings composition |
| Reserved/invalid states never offer Replace Existing | C-08 result contract | UI-17 state inspection | Proposed |
| No raw input, display text, input source, persistence, runtime update or Window Action crosses the Interface | C-11 plus source dependency/privacy review; C-12 verifies deterministic purity | Diagnostics allowlist review | Proposed |
| Cross-app/customized-system conflicts are described as a known limitation, not promised as detected | H3-01 system failure tests remain separate | Human check of help/conflict copy | Proposed limitation |
| Accepted Save later persists and updates runtime without restart | Not owned by H3-04 | Gate G3 integration/relaunch evidence | Deferred to H3-05/H3-06 |

## Confirmation requested

Trước red test đầu tiên, vui lòng xác nhận `HotkeyConflictValidating.validate(_:)` là public
test seam của H3-04, với typed `valid` / `invalid` / `reserved` / `duplicate` results và
ownership sau: H3-04 chỉ phân loại pure trước Save; Settings sở hữu Replace Existing / Choose
Another / Cancel trên unsaved draft; H3-05 sở hữu persistence; H3-06 sở hữu runtime update.

Khi được xác nhận, slice TDD đầu tiên chỉ là C-02: candidate trùng một binding khác trả về
typed duplicate chứa đúng `bindingID` và `ActionID`. Tài liệu này tự nó không cho phép viết test
hoặc production code.

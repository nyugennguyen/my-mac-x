# H3-04 — Hotkey conflict detection evidence

Date: 2026-08-27

## Confirmed Interface

`HotkeyConflictValidating.validate(_:)` is the H3-04 test seam. It accepts one
`HotkeyValidationRequest` containing the edited binding identity, target `ActionID`, candidate
physical `HotkeyChord`, and the caller's complete binding snapshot. It returns exactly one typed
`HotkeyValidationResult`: `valid`, `invalid`, `reserved`, or `duplicate`.

The validator is a pure, synchronous InputKit Module. It does not record keys, present Settings
UI, persist or register bindings, update runtime state, or dispatch a Window Action. Settings
owns Replace Existing / Choose Another / Cancel, H3-05 owns persistence, and H3-06 owns runtime
reconciliation.

## Confirmed v1 policy

- Bindable hardware key codes are the inclusive range `0...126`.
- Hardware key codes `54...63` are rejected as modifier-only primary keys.
- A chord requires at least one of Command, Option, Control, or Shift; bits outside that mask are
  rejected with the unsupported bits preserved in the typed reason.
- The protected catalog contains exactly six physical chords: Command-Space (Spotlight),
  Command-Tab (app switcher), Command-Option-Escape (Force Quit), and Command-Shift-3/4/5
  (screenshot full/selection/options).
- Common app commands Command-Q/W/H/M are deliberately not in the protected global catalog.
- Classification precedence is invalid, then reserved, then duplicate, then valid.
- Duplicate results exclude `editedBindingID`, include every other owner, and sort conflicts by
  UUID string for deterministic output.

“Reserved” means blocked by the compiled My Mac X policy. It is not a claim that every macOS or
third-party shortcut can be discovered before Save; no registration probe or cross-process
inspection occurs.

## Focused automated evidence

Focused XCTest selector:

```text
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX \
  -only-testing:MyMacXTests/HotkeyConflictDetectorTests
```

Result on 2026-08-27: 15 tests executed, 0 failures, `TEST SUCCEEDED`.

| Acceptance behavior | Observable focused coverage |
| --- | --- |
| Supported policy boundary | Codes `0` and `126` with Command are valid. |
| Duplicate classification | A matching physical chord returns the other binding's exact UUID and `ActionID`, including when both bindings target the same action. |
| Self-edit handling | Revalidating an edited binding's unchanged chord excludes that binding and returns valid. |
| Missing modifier | A candidate with no supported modifier returns `requiresModifier`. |
| Unknown modifier bits | A mask containing an unsupported bit returns that bit in `unsupportedModifierBits`. |
| Modifier-only primary key | Both boundaries, codes `54` and `63`, return `modifierOnlyPrimaryKey`. |
| Unsupported key code | Code `127` returns `unsupportedHardwareKeyCode(127)`. |
| Reserved catalog | All six entries return their stable reservation ID with `replacementAllowed == false`. |
| Negative reserved cases | Command-Q/W/H/M remain valid. |
| Deterministic precedence | Invalid wins over a damaged duplicate snapshot; reserved wins over a matching damaged duplicate snapshot. |
| Damaged duplicate snapshot | Every conflicting binding is returned in stable UUID order. |
| Physical identity | Hardware code and normalized modifiers alone determine equality; changing either prevents a duplicate. |
| Purity | Repeating validation returns the same result and leaves the value request equal to its known literal. |

## Ownership and privacy audit

- `HotkeyConflictDetector.swift` imports only Foundation and performs value-only checks over the
  request. It has no AppKit, Carbon, Accessibility, filesystem, network, registration, logging,
  or Window Action dependency.
- The request and result contain no raw event, characters, typed text, display label, input-source
  identifier, timestamp, window title, clipboard content, or screenshot.
- Duplicate output contains identity only. Settings must resolve user-facing action names through
  H3-02 `ActionRegistry` and must revalidate a revised unsaved draft after an explicit replacement.
- `reserved` and `invalid` never authorize replacement; the six catalog entries all expose
  `replacementAllowed == false`.

## Deferred integration evidence

The validator does not prove Settings dialog behavior, Save, replacement, persistence, runtime
registration, or relaunch behavior. Those remain composition evidence for the Settings workflow,
H3-05, H3-06, and Gate G3. Cross-app and user-customized system conflicts remain the documented
v1 limitation from H3-01.

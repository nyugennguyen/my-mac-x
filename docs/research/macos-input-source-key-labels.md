# macOS input-source and key-label research

Date: 2026-08-26

Scope: public Apple APIs that can support H3-07's system implementation of the
existing `HotkeyKeyLabelResolving` seam. This note intentionally does not claim that
an input-source label is a hotkey identity.

## Findings

1. AppKit exposes both a key event's virtual `keyCode` and its generated character
   values. `charactersIgnoringModifiers` is specifically described as a basic,
   hardware-independent value for keyboard equivalents, so it must not replace the
   stored physical code for this product. It also describes dead-key behavior, which
   means generated text is not a reliable keycap identity.
   [Apple: `charactersIgnoringModifiers`](https://developer.apple.com/documentation/appkit/nsevent/charactersignoringmodifiers)

2. Apple's public Core Services `UCKeyTranslate` function maps a virtual key code,
   modifier state, keyboard type, and dead-key state through a Unicode keyboard-layout
   (`'uchr'`) resource. Its output may contain multiple Unicode characters. Apple
   currently marks this function as discouraged for general event processing and points
   applications toward `NSEvent.characters(byApplyingModifiers:)`; however, the same
   documentation describes `UCKeyTranslate` as the public operation for translating a
   *specified virtual key code* against a supplied layout. H3-07 may use it behind the
   adapter, with a narrow fallback and no raw text crossing the presenter seam.
   [Apple: `UCKeyTranslate`](https://developer.apple.com/documentation/coreservices/1390584-uckeytranslate)

3. `UCKeyboardLayout` documents that a Unicode keyboard-layout resource contains the
   data needed to map virtual key codes to Unicode characters, and includes keyboard
   type headers. A resolver therefore has to treat layout data and keyboard type as
   inputs, not assume one hard-coded US table.
   [Apple: `UCKeyboardLayout`](https://developer.apple.com/documentation/coreservices/uckeyboardlayout?language=objc)

4. AppKit's `NSTextInputContext` exposes the selected keyboard input-source identifier,
   available keyboard input sources, a localized source name, and
   `keyboardSelectionDidChangeNotification`. The selected source can change while the
   app remains running; a resolver cache must be invalidated on that notification and
   must re-read the selected source before the next presentation.
   [Apple: `NSTextInputContext`](https://developer.apple.com/documentation/appkit/nstextinputcontext)

5. AppKit states that some system-level function keys are handled below the app and may
   never arrive as ordinary events. A resolver must therefore allow “no label” for
   unsupported/special codes and use the presenter's visible hardware-code fallback.
   [Apple: `NSEvent.SpecialKey`](https://developer.apple.com/documentation/appkit/nsevent/specialkey-swift.struct)

6. The project can observe AppKit input-source selection through the documented
   `NSTextInputContext.keyboardSelectionDidChangeNotification`. Workspace and app
   activation notifications are separate environment events; they may be useful as
   conservative refresh triggers, but they do not prove that the selected keyboard
   source changed.
   [Apple: `NSTextInputContext.current`](https://developer.apple.com/documentation/appkit/nstextinputcontext/current)
   [Apple: `NSWorkspace.didActivateApplicationNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)

## Consequences for H3-07

- `HotkeyChord.hardwareKeyCode` and its four normalized modifiers remain the identity;
  the resolver returns presentation-only text.
- The system adapter should snapshot the selected input source/layout for one lookup,
  translate only the requested code with a neutral display state, and reject empty,
  multi-character, dead-key, or otherwise ambiguous output as a label.
- H3-07 should treat Carbon/Unicode layout APIs as a contained legacy-public adapter,
  not expose them to UI or persistence. If the selected source has no usable Unicode
  layout data (a plausible case for an input method such as Vietnamese Telex), return
  `nil` and let `HotkeyChordPresenter` display `Key code 0xNN`.
- Automated tests should use a deterministic mapping adapter for behavior and a fake
  source provider for cache/invalidation. Only the OS matrix is manual evidence because
  the selected input source and IME state are external OS state.

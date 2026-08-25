# F1-04 — Focused Window and capabilities evidence

Status: `PASS — DOCUMENTED NATIVE FULL SCREEN LIMITATION ACCEPTED`

## Delivered behavior

- `FocusedWindowProviding.focusedWindow()` captures focus exactly once per request and returns only domain values.
- `WindowIdentity` is opaque and contains no title/document metadata.
- `WindowCapabilities` distinguishes movable/resizable plus tri-state minimized and Native Full Screen knowledge.
- System Adapter uses documented AX trust, focused application/window, role, minimized, position-settable and size-settable functions/constants.
- The P0-03 frontmost-process PID fallback is retained when system-wide focus lookup fails.
- `AXUIElement` and raw `AXError` values remain inside `SystemWindowAdapter`.
- A bounded 64-record LRU `CFEqual` identity cache reuses the same opaque identity for a retained live AX window.
- Every synchronous AX read is bounded by a one-second public messaging timeout.
- Only documented standard-window role/subrole is eligible; sheets/dialogs fail closed.

## Public-API decision

[Primary-source research](../../research/native-full-screen-accessibility.md) confirms that the SDK exposes no documented Native Full Screen state attribute for another application's window. Production therefore returns `.unavailable`; it does not use a string-literal `AXFullScreen` key or infer state from geometry. This is accepted under ADR-0002's public-API-only rule rather than leaving an impossible implementation requirement open.

## TDD and verification on 2026-08-24

- Initial sub-agent suite covered focus capture, role filtering, capabilities, typed failures and single capture per request.
- Root review added a red test proving `isMinimized` is a state, not by itself evidence that a window can perform a Window Action.
- Eligibility was corrected to movable, resizable or known-active Native Full Screen.
- AXWindowKit XCTest: 17/17 pass after hardening.
- Root caught and fixed a real regression where `cannotComplete` no longer used the P0-03 frontmost-PID fallback; policy test went red→green while fallback reads remain timeout-bounded.
- Production harness on the current trusted app window: found, identity stable across two captures, movable/resizable true, minimized inactive, Native Full Screen unavailable.
- Current full integrated XCTest suite: 45/45 pass; Debug tests and Release build pass.
- Swift 6 complete strict-concurrency production/test typechecks pass.

## Remaining checks

- Run real sheet/dialog/minimized and hung-app fault injection across the compatibility matrix.
- F1-07 fixtures are finalized; validate identity lifetime against Window Action/Undo semantics during their later integration.

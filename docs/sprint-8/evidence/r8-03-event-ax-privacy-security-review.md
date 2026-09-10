# R8-03 — Event/AX privacy-security review

Date: 2026-09-09

## Result

Source review passes the code-level privacy inventory with one lifecycle hardening change: repeated
Event Tap disable notifications are now bounded to three recovery attempts, after which the tap is
invalidated, its callback gate fails open, and status becomes unavailable. A signed Release archive
entitlement inspection is intentionally left to R8-06/R8-07.

## Accessibility call-site inventory

All production `AXUIElement` ownership is confined to
`Sources/AXWindowKit/SystemWindowAdapter.swift`; permission preflight is additionally confined to
`Sources/PermissionKit/AccessibilityPermissionManager.swift`.

| Purpose | Public calls/attributes | Data leaving Adapter |
|---|---|---|
| Trust preflight | `AXIsProcessTrusted` | Typed permission state only |
| Capture exact Focused Window | system-wide/application elements; focused application/window; PID | Opaque `WindowIdentity`, role-derived `WindowKind`, capabilities |
| Eligibility/capabilities | role, subrole, minimized, position/size settable | Typed kind/capabilities; no raw role string |
| Inspect/mutate/read-back | position, size, minimized; set position/size | Geometry, typed result/failure |
| Pointer movement observation | `AXObserverCreate`, moved notification add/remove | Captured opaque identity only |
| Native Full Screen action | full-screen button and press action | Typed accepted/failure result |
| App-rule lookup | PID to `NSRunningApplication.bundleIdentifier` | Bundle identifier only, used by local policy |

Every synchronous AX messaging path applies a one-second messaging timeout before attribute work.
The Adapter rejects own-process windows, validates returned CF types, bounds its identity cache to 64,
and never reads title, document, URL, description, help, selected text, or value attributes.

Apple's public Accessibility functions and attributes are documented at
[AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement),
[kAXFocusedWindowAttribute](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute),
[kAXPositionAttribute](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute), and
[kAXSizeAttribute](https://developer.apple.com/documentation/applicationservices/kaxsizeattribute).

## Event-input call-site inventory

| Path | Scope | Retained/emitted data | Suppression |
|---|---|---|---|
| `MacOSEventTapSystem` | key down/up and flags changed only | event kind, hardware key code, modifier flags, repeat bit | Original event is returned unless the safety controller proves ownership |
| `SuperModeInputSafetyController` | non-repeat key-down while enabled | reducer state and validated configured key paths; no raw stream/text | Prefix, registered sequence, Escape/cancel only |
| `MacOSGlobalHotkeySystem` | registered configured chord | configured hardware key code/modifiers | Carbon hotkey delivery, no global raw stream |
| `HotkeyRecorder` | local recorder session | candidate hardware key code/modifiers | local monitor only while recorder is active |
| `MacOSHotkeyKeyLabelResolver` | presentation of a configured key code | one display label derived from keyboard layout | none; it does not observe typed events |
| `PointerDragMonitor` | left-button drag/up metadata | pointer location/button phase | none |

`MacOSEventTapCallbackBox` never exposes a `CGEvent` outside the callback, never extracts Unicode
text, and performs no logging or AX work. Disabled notifications are fail-open and schedule only a
bounded actor recovery. Apple documents that a tap may be disabled on timeout and should be
re-enabled with `CGEvent.tapEnable` in
[CGEventTapCallBack](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback) and
[CGEvent.tapEnable](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)).

## Logs and data inventory

Static review found no production reads of AX title/document/content attributes, clipboard APIs,
screen-capture APIs, telemetry, or network clients. The apparent `characters` buffer in
`MacOSHotkeyKeyLabelResolver` converts a configured virtual key through the current keyboard layout;
it is not sourced from an input event and is retained only as a display label.

Diagnostics use a closed `DiagnosticsCode` allowlist and log only the public code value. Raw OS
error descriptions, `CGEvent`, `AXUIElement`, window titles, document paths, clipboard contents,
screenshots, and key streams cannot cross that logging Interface.

Data retained by these Modules is local and bounded:

- permission onboarding/grant history: two booleans in `UserDefaults`;
- AX identities: opaque, in-memory LRU cache, maximum 64;
- current AX movement observer: one window, stopped/replaced explicitly;
- Event Tap callback: one installation/generation and handler; invalidated on stop/unhealthy loop;
- Super Mode state: current validated configuration/session only; cleared on execute/cancel/timeout.

## Entitlements and private interfaces

- Debug build output generates only `com.apple.security.get-task-allow` for local testing.
- Project settings enable Hardened Runtime for Debug and Release.
- The Release configuration points `CODE_SIGN_ENTITLEMENTS` at `Configs/MyMacX.entitlements`, whose
  entitlement dictionary is empty; no Screen Recording, automation, network, JIT,
  library-validation exception, or sandbox entitlement is declared.
- Static scan found no `SkyLight`, CGS/SLS private symbols, `dlopen`, `dlsym`, or `@_silgen_name` in
  production source/project settings.
- `scripts/release/security-audit.sh` makes the private API, network, prohibited-content API and
  entitlement checks repeatable. The project has no third-party package or vendored binary;
  `docs/release/MyMacX-0.1.0-beta.4.spdx.json` records that release inventory.
- R8-06 must inspect the entitlements extracted from the actual Release archive. This source/config
  result is not a substitute for archive verification.

## Verification

Focused tests cover privacy packaging, suppression, stale callbacks, idempotent start/stop, timeout
recovery, bounded recovery failure, permission lifecycle, exact AX identity, read-back and rollback.
The combined command/result is recorded in `r8-04-soak-performance-core.md`.

# H3-01 — Carbon hotkey API research

Date: 2026-08-26

## Decision

`RegisterEventHotKey`, `UnregisterEventHotKey`, and the required Carbon Event Manager
handler APIs are public, 64-bit-callable APIs in Apple's installed macOS SDK and can back a
Developer ID macOS 14+ Swift Adapter. They are legacy C APIs, but the inspected declarations
are neither marked deprecated nor unavailable. The Adapter should isolate them behind the
existing system seam, serialize every Carbon call on one main-actor-owned lifecycle, and
retain all returned references until explicit teardown. [S1][S2][S3]

This establishes API/linkage suitability, not hardware behavior. Apple does not document
whether a hotkey registration is lost across sleep; unregister-on-sleep and restore-on-wake
must therefore be described as the Module's defensive lifecycle policy, not an OS guarantee.

## Public API and Swift import evidence

- `RegisterEventHotKey` and `UnregisterEventHotKey` are declared available from macOS 10.0.
  Their declarations sit outside the header's `!__LP64__` exclusions. `RegisterEventHotKey`
  accepts a virtual key code, a 32-bit modifier mask, an app-defined `EventHotKeyID`, an
  `EventTargetRef`, options, and an output `EventHotKeyRef`. [S1]
- `GetApplicationEventTarget`, `InstallEventHandler`, `RemoveEventHandler`, and
  `GetEventParameter` are likewise available from macOS 10.0 and not marked deprecated.
  Apple's 64-bit guide directs developers to the Carbon Event Manager headers to determine
  individual 64-bit availability. [S2][S3][S6]
- The current HIToolbox text-based stub exports `_RegisterEventHotKey`,
  `_UnregisterEventHotKey`, `_InstallEventHandler`, and `_RemoveEventHandler` for macOS
  targets. [S5]
- A compile-and-link-only probe importing `AppKit` and `Carbon.HIToolbox`, installing the
  handler, extracting `EventHotKeyID`, registering/unregistering a hotkey, removing the
  handler, and observing both workspace notifications passed with Xcode 26.6 / macOS 26.5
  SDK using:

  ```text
  xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 -swift-version 6 \
    -strict-concurrency=complete -warnings-as-errors <probe.swift> -o <probe>
  ```

  The executable was not run; this is import, availability, strict-concurrency, and linker
  evidence only.

## Registration and callback lifecycle

1. On the main actor, obtain `GetApplicationEventTarget()` and install one handler for
   `EventTypeSpec(eventClass: kEventClassKeyboard, eventKind: kEventHotKeyPressed)`. Store
   the successful `EventHandlerRef`. Carbon says these APIs are not thread-safe. [S1][S2]
2. Register each chord against that same target. Give each live registration one stable,
   unique `EventHotKeyID` (`signature` plus `UInt32 id`) and store the successful
   `EventHotKeyRef` beside the binding lookup entry. The registration reference is required
   for later unregistration. [S1]
3. In the C callback, extract `kEventParamDirectObject` as `typeEventHotKeyID` using
   `GetEventParameter`, validate the signature/id, and enqueue only the matching binding and
   action identity. Return `noErr` only when handled; return `eventNotHandledErr` when the
   event cannot be decoded or is not owned. Apple specifies those return semantics. [S1][S2]
4. Any Swift object passed through `inUserData` must outlive the installed handler. This is a
   Swift ownership consequence of Carbon retaining only a raw `void *`: use a stable
   noncapturing C callback and either an unretained pointer with owner-enforced lifetime, or
   a retained pointer released only after handler removal. [S2]
5. For reconfiguration/stop, prevent new dispatch in Module state, unregister every owned
   nonnull `EventHotKeyRef` exactly once, remove the stored handler exactly once, remove
   notification observers, then release callback context. `RemoveEventHandler` invalidates
   its reference; `UnregisterEventHotKey` is unnecessary only at process termination, not
   for runtime replacement. [S1][S2]

The same handler proc/user-data pair cannot be installed twice for the same event type;
`InstallEventHandler` returns `eventHandlerAlreadyInstalledErr`. This supports one handler
per Adapter lifecycle rather than one per binding. [S2]

## Modifier mapping

The project model's bits are not Carbon bits and must be translated explicitly:

| `HotkeyModifiers` | Carbon mask |
|---|---:|
| `.command` | `UInt32(cmdKey)` (`1 << 8`) |
| `.shift` | `UInt32(shiftKey)` (`1 << 9`) |
| `.option` | `UInt32(optionKey)` (`1 << 11`) |
| `.control` | `UInt32(controlKey)` (`1 << 12`) |

Combine mapped masks with bitwise OR. Carbon also defines Caps Lock, Fn, and numeric-lock
masks, but those are outside the current four-modifier model. Its right-side modifier masks
are explicitly documented as unsupported on macOS, so this API cannot promise left/right
modifier distinction. [S4]

## Status and conflict semantics

- Treat `noErr` as success and retain the returned reference only on success. Preserve every
  other `OSStatus` long enough to classify/report it; do not map every failure to a chord
  conflict. The headers give generic `OSStatus` results for registration, unregistration,
  installation, and removal. [S1][S2]
- `eventHotKeyExistsErr` (`-9878`) is documented for a duplicate chord in the current
  process and for an exclusive-registration collision with another exclusive registration.
  `eventHotKeyInvalidErr` (`-9879`) is explicitly documented as unused. [S2]
- A normal (`kEventHotKeyNoOptions`) registration is nonexclusive. Apple says the same chord
  may be registered by multiple applications and all may be notified. Therefore success is
  not a general cross-process conflict check. `kEventHotKeyExclusive` changes delivery and
  collision behavior, but can suppress nonexclusive registrants while active; choosing it is
  product policy, not a transparent validation query. [S1]
- For atomic replacement, reuse an existing registration when its physical chord is
  unchanged and only binding metadata changes; trying to register the identical chord again
  in the same process can return `eventHotKeyExistsErr`. For changed chords, stage successful
  new registrations before releasing old ones, and roll back staged refs if any registration
  fails. [S1][S2]

## Sleep and wake notifications

Use `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification` from
`NSWorkspace.shared.notificationCenter`. Apple identifies these as device sleep/wake
notifications and explicitly requires workspace notifications to be registered on that
notification center. `screensDidSleepNotification` and `screensDidWakeNotification` describe
display sleep/wake, so they are not the appropriate trigger for device-level hotkey teardown
and restore. [S7][S8][S9]

Install the observation once, unregister the active Carbon refs on the first `willSleep`, and
reconcile the saved desired snapshot on the first following `didWake`; repeated notifications
must be state-guarded no-ops. On a macOS 14 deployment target, use the classic notification
names. The newer typed `NSWorkspace.WillSleepMessage`/`DidWakeMessage` observation surface in
the inspected SDK is macOS 26-era API and is unnecessary for this Adapter. [S8][S9]

## Primary sources

- **[S1]** Apple Xcode 26.6 macOS 26.5 SDK,
  `Carbon.framework/Frameworks/HIToolbox.framework/Headers/CarbonEvents.h`, especially
  lines 4675–4712 and 15387–15521.
- **[S2]** Same SDK, `HIToolbox.framework/Headers/CarbonEventsCore.h`, especially lines
  55–171, 843–900, and 2430–2631.
- **[S3]** Same SDK, `HIToolbox.framework/Headers/CarbonEvents.h`, lines 14950–14969
  (`GetApplicationEventTarget`).
- **[S4]** Same SDK, `HIToolbox.framework/Headers/Events.h`, lines 91–130, plus
  `CarbonEvents.h`, lines 4716–4746.
- **[S5]** Same SDK, `HIToolbox.framework/HIToolbox.tbd`, exported-symbol lists.
- **[S6]** Apple, [64-Bit Guide for Carbon Developers — Changes in the Human Interface
  Toolbox](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/Carbon64BitGuide/HIToolboxChanges/HIToolboxChanges.html).
- **[S7]** Apple, [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
  and the same SDK's `AppKit.framework/Headers/NSWorkspace.h`, lines 26–34 and 317–329.
- **[S8]** Apple, [willSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification)
  and [didWakeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification).
- **[S9]** Apple, [screensDidSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidsleepnotification)
  and [screensDidWakeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidwakenotification).

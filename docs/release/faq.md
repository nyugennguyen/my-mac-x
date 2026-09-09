# My Mac X beta FAQ

## What does My Mac X do?

It places the focused eligible window into a Layout Region using a menu action, Hotkey, the
top-edge Notch Trigger, or Super Mode. Maximize fills the current Display's usable area; it is
not macOS Native Full Screen.

## What does this beta require?

macOS 14 or later. Accessibility is required to move and resize other apps' windows. Input
Monitoring is requested only when runtime preflight proves the configured Event Tap path needs it;
registered global Hotkeys do not require it by themselves. macOS keeps these permissions under
System Settings > Privacy & Security.

## Does it read what I type or see my screen?

No. The app recognizes configured hardware-key sequences but does not record typed text or raw
keystroke streams. It does not request Screen Recording and does not collect screenshots,
clipboard contents, window titles, document titles, or window contents. See the privacy policy
for the full data summary.

## Where is my data stored?

Configuration and placement history stay on your Mac. There is no telemetry in this beta.
Export happens only when you choose it; review and protect the exported settings file before
sharing it.

## Why did a Window Action stop working?

Check the menu-bar status and About/Diagnostics. Common causes are revoked Accessibility or
Input Monitoring access, a non-resizable/special target window, an app that limits its own
window size, or a target app that does not expose the required Accessibility behavior. Re-enable
the permission in System Settings and retry with a normal document window.

## Why doesn't a window match the requested region exactly?

Some apps enforce minimum sizes or reject one resize axis. My Mac X verifies the resulting
frame and reports constrained or failed actions rather than silently claiming the requested
placement. A failed action preserves or best-effort restores the prior frame.

## Does it manage macOS Spaces?

Version 1 moves windows between physical Displays. Moving an external app to a particular
Space is outside scope because the production app uses public APIs only. Stage Manager and
individual apps may also adjust a frame after placement.

## What is the Notch Trigger on a Display without a notch?

It falls back to the top-center of that Display. The Layout Chooser should remain inside the
visible frame and should not activate or steal focus from the Captured Window.

## How do updates work?

The beta uses manual updates. Quit My Mac X, install the newer signed release over the existing
app while keeping the same bundle identity, then launch it and verify permissions and settings.
Keep the previous installer and a configuration export until the upgrade is verified. Exact
download, signature, checksum, and rollback instructions will accompany the release artifact.

## How do I report a problem safely?

Include the app version, macOS version, Mac model, Display arrangement/scaling, target app and
steps to reproduce. The Diagnostics report is redacted by design, but review it before sharing.
Do not include confidential screenshots or documents unless you intentionally choose to.

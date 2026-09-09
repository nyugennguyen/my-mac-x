# My Mac X privacy policy — beta

Last updated: 2026-09-09

My Mac X is a local-first macOS window manager. It moves and resizes windows only when you use
a configured Window Action through the menu bar, a Hotkey, the Notch Trigger, or Super Mode.

## Permissions

**Accessibility** lets My Mac X identify the focused eligible window, inspect the window
properties needed for placement, and ask macOS to move or resize it. My Mac X explains this
before opening System Settings. You can revoke access at any time; window placement then stops
until access is restored.

**Input Monitoring** is requested only if macOS runtime preflight shows it is required for the
configured Event Tap path, such as Super Mode's bounded Prefix sequences or pointer-drag metadata
while other apps are active. Global Hotkeys use registered system shortcuts and do not by
themselves require raw event listening. My Mac X works with hardware key codes needed to recognize
configured shortcuts. It does not record the text you type.

My Mac X does not request Screen Recording for its v1 feature set.

## Data we do not collect

My Mac X has no telemetry in this beta. It does not collect or log typed text, raw keystroke
streams, window or document titles, clipboard contents, screenshots, or the contents of your
windows. It does not sell personal information or use it for advertising.

## Data stored on your Mac

Settings, Display Profiles, app rules, custom Layouts, Hotkeys, Super Mode configuration, and
window-placement history are stored locally. A configuration export contains configuration you
choose to export; treat that file like any other personal settings backup. Diagnostic reports
are designed to contain app/OS/permission status and stable error categories, not the sensitive
content listed above. Review a report before sharing it.

Window identity and Window Snapshots are used to keep a Window Action bound to the intended
Captured Window and to support Undo/Restore. They are not an activity history or content log.

## Network and updates

This beta does not send telemetry. Updates are manual unless a later release clearly discloses
and enables an update path. Any future network behavior must be disclosed here before release.

## Your controls

You can pause My Mac X, disable individual interaction features, export or replace its local
configuration, revoke macOS permissions in System Settings, and remove the app. Removing the
app does not automatically remove macOS permission entries or local settings; macOS and your
user account control those separately.

This policy is release-candidate copy. Before public distribution it must be reconciled with
the final R8-03 security/data inventory and include the publisher's support contact.

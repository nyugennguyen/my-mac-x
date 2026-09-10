# My Mac X 0.1.0 beta release notes

My Mac X 0.1.0 beta is a local-first, native macOS window manager for macOS 14 and later.

## Highlights

- Snap a Captured Window through the top-edge Notch Trigger and native Layout Chooser, with a
  top-center fallback on Displays without a notch.
- Run Window Actions from configurable global Hotkeys, the menu bar, or bounded Super Mode
  Prefix sequences.
- Use built-in and custom Layouts, Display Profiles, app rules, Cycle Groups, Maximize,
  Restore, Undo, and movement between physical Displays.
- Configure snapping, Hotkeys, Super Mode, Layouts, profiles, app rules, and local import/export
  from Settings.
- Inspect redacted permission/runtime diagnostics without logging typed text, window titles,
  clipboard data, or screenshots.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast, keyboard navigation, and
  current keyboard-layout labels at the tested production seams.

## Privacy and permissions

Accessibility is needed to identify, move, resize, and verify eligible windows. Input Monitoring
is requested only when runtime preflight proves the configured Event Tap path requires it; global
Hotkeys alone use registered system shortcuts. Screen Recording is not requested.
Configuration and history stay local, and this beta has no telemetry. Read `privacy.md` before
enabling permissions.

## Known limitations and beta status

- Version 1 targets physical Displays, not moving external-app windows to a specific macOS Space.
- Some apps reject Accessibility changes or enforce minimum sizes; actions can be constrained or
  fail safely instead of reaching the exact requested frame.
- Stage Manager or a target app may reposition a window after My Mac X finishes an action.
- Full VoiceOver, appearance, notch/multi-Display, Intel, five-user usability, TCC lifecycle,
  soak, signing/notarization, clean-machine install, and final Go/No-Go evidence remain release
  gates. This note does not claim those checks passed.
- The demo candidate is 0.1.0-beta.4 (build 4), including the new Mac-and-X application icon.
  Use only the versioned artifact and checksum
  supplied by the release owner; a development build is not a notarized release.

## Verification snapshot

On 2026-09-09 the final arm64 regression suite completed 451 tests: 449 passed, two
hardware-dependent tests were skipped, and none failed. Manual and physical checks remain
tracked separately in the R8-01 matrix.

## Updating and rollback

This beta uses manual update. Export configuration and keep the prior versioned installer before
updating. After replacement, launch the app, verify macOS permissions and settings, and run a
representative Window Action. If a release regression appears, quit the app and follow the
version-specific rollback instructions packaged by the release owner.

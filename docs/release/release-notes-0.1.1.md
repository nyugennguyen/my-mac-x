# My Mac X 0.1.1 Release Notes

My Mac X 0.1.1 introduces an Open Design first-launch permission onboarding window and enhancements to the permission lifecycle.

## Highlights

- **First-Launch Permission Onboarding (Open Design)**: Replaces legacy modal alert dialogs with a modern, frameless 580×560 pt native macOS window featuring subtle material vibrancy, rounded interactive cards, and drag-by-background support.
- **Dual Permission Guidance**: Visual status cards for both Accessibility and Input Monitoring permissions with live badges (`Granted` vs `Required`/`Recommended`), clear purpose explanations, and direct deep-linking to macOS System Settings.
- **Live Auto-Refresh**: Dynamic state observers and active-application notifications update permission badges in real-time when toggled in System Settings without requiring an application restart.
- **Privacy & Security Trust Guarantee**: Reassuring upfront callout ensuring all operations remain local-first, offline, and privacy-preserving with no logging of typed text, keystrokes, window titles, or screen content.

## Requirements

- **Operating System**: macOS 14.0 Sonoma or later.
- **Permissions**: Accessibility (required for window inspection, move, resize, and snapping); Input Monitoring (recommended for global hotkeys, Super Mode chords, and cursor drag-to-snap transitions).

## Verification Snapshot

- 634 unit and integration tests passing on macOS 14/15 runner matrix.
- Clean-room implementation using public Apple AppKit and Accessibility APIs.

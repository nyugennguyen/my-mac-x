# My Mac X 0.1.0 Release Notes

My Mac X 0.1.0 is the official release of the local-first, native macOS window manager for macOS 14 Sonoma and later.

## Highlights

- **Notch Snap & Fallback**: Snap captured windows via the top-edge Notch Trigger and native Layout Chooser, with automatic top-center fallback on displays without a notch.
- **Screen Edge Snap**: Drag windows to screen edges and corners with customizable dwell/threshold triggers, remappable zone partitions, and visual overlay feedback. Coexists seamlessly with native macOS 15 tiling.
- **Global Hotkeys & Super Mode**: Full keyboard navigation through customizable global hotkeys, status menu bar quick actions, and bounded modal prefix sequences (Super Mode).
- **Multi-Display & Profile Persistence**: Move windows across physical displays with persistent, stable display topology profiling across hardware reconnects.
- **Deep Customization**: Built-in and user-defined layouts, display profiles, per-app rules, cycle groups, Maximize, and safe single-action Undo.
- **Settings Experience**: Modern, unified SwiftUI Settings shell with real-time search, anchor highlights, interactive Hotkey Recorder, and visual Zone-Map picker.
- **Privacy by Design**: Strictly local configuration and history with zero telemetry, zero private APIs, and redaction of all sensitive window contents, titles, and keystrokes.

## Requirements

- **Operating System**: macOS 14.0 Sonoma or later (Universal binary: Apple Silicon arm64 & Intel x86_64).
- **Permissions**: Accessibility (required for window querying and geometry updates); Input Monitoring (requested only when specific global event taps require it).

## Verification Snapshot

- 624 unit and integration test assertions passing on macOS 14/15 runner matrix.
- Clean-room implementation using public Apple AppKit and Accessibility APIs.

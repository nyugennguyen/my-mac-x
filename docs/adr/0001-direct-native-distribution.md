---
status: accepted
---

# Build native and distribute directly

My Mac X will be a native Swift 6 macOS utility using AppKit for system integration and SwiftUI for settings, distributed first with Developer ID, Hardened Runtime and notarization. The Accessibility-driven product scope conflicts with important App Sandbox restrictions, so a Mac App Store build is a separate feasibility track rather than a v1 release dependency.

## Consequences

The release process owns signing, notarization, update integrity and privacy communication. Bundle identity and signing identity must remain stable so updates do not unnecessarily disrupt Accessibility trust.


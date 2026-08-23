---
status: accepted
---

# Keep production on public APIs and defer Space control

Production builds will use public macOS APIs only. v1 moves windows between physical Displays but does not promise moving another application's window to an arbitrary Space because macOS has no supported public interface that meets the product requirement; Space actions remain feature-flagged R&D until a stable public approach is proven.

## Consequences

Private SkyLight symbols are excluded from every production target and release scan. Experimental failure must preserve the window's current placement and can never become a silent fallback in v1.


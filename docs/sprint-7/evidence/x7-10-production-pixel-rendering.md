# X7-10 — production pixel-render integrity

## Result

`PASS-AUTO` on 2026-09-08. The previous model-recording-only snapshot test was
replaced by a pixel test registered in the `MyMacXTests` target.

The AppKit panel adapters and tests share `OverlayProductionViewFactory`, so the
test renders the same `LayoutChooserView`, `PlacementPreviewView`, and
`SuperHUDView` hierarchies used in production. It does not use a test facsimile.

## Coverage

- 24 fixed-size, 2× pixel renders: three production overlays across Light/Dark,
  normal/increased contrast, and translucent/reduced-transparency treatments.
- Determinism: identical opaque chooser inputs produce the same fixed dimensions,
  alpha coverage, and coarse RGB histogram. This deliberately excludes AppKit's
  byte-level antialiasing noise.
- Mutation sensitivity: changing chooser selection (glyph/title/accent), adding
  the constrained-preview warning, and changing the HUD from waiting to error
  each produces a different RGBA digest.
- Signatures contain dimensions, visible-pixel count, a quantized RGB histogram,
  and an FNV-1a digest over raw RGBA bytes. The stable comparison uses the first
  three; the raw digest is used only for same-run mutation sensitivity. They
  contain no hostname, OS build, timestamp, display identity, or image-file
  metadata.

## Automated command

```sh
xcodebuild test -quiet -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MyMacXTests/OverlaySnapshotTests
```

Result: 3 tests passed, 0 failures.

## Remaining human gate

These signatures prove that production views render across the required matrix
and that meaningful visual state changes are detectable. They do not approve
visual quality. A named reviewer must still approve representative renders,
including material quality, legibility, color-independent cues, and real panel
compositing. The notch/non-notch pointer matrix, VoiceOver checks, physical
multi-Display checks, and five-user protocol also remain open.

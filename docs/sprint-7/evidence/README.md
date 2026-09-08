# Sprint 7 evidence index

This directory separates code-level evidence from checks that require rendered UI,
assistive technology, physical Displays, or human judgment. A checked automated
item is never evidence that a corresponding human-only item passed.

## Artifacts

- [X7-01 whole-app audit](x7-01-whole-app-audit.md) — shipped-surface inventory
  and P0–P2 findings from source and test inspection.
- [X7-09/X7-10 verification matrix](x7-09-x7-10-verification-matrix.md) — exact
  automated and human checks, environments, evidence to retain, and pass rules.
- [X7-10 production pixel rendering](x7-10-production-pixel-rendering.md) — fixed
  2× production-view signatures and meaningful-diff verification.
- [X7-02…X7-08 implementation](x7-02-through-x7-08-implementation.md) — chooser,
  hotkey presentation, onboarding, accessibility policy, and focused test evidence.

## Current conclusion

Gate G7 has an automated implementation candidate but remains **HUMAN QA
PENDING**. No VoiceOver, real-pointer, physical notch/non-notch, multi-Display,
approved pixel snapshot, or representative-user result is claimed here. Automated
pixel signatures are regression evidence, not aesthetic approval.

## Evidence conventions

- `CODE` means the source directly establishes the behavior or gap.
- `AUTO` means a repeatable test must pass and its command/output is retained.
- `RENDER` means an image generated from production rendering is compared and
  reviewed; inspecting a render model is not a rendered snapshot.
- `HUMAN` means a named tester records hardware, macOS version, steps, result,
  and notes. Human-only gates cannot be waived by unit tests.

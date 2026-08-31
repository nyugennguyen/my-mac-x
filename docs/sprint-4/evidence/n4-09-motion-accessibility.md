# N4-09 — Motion and accessibility presentation states

Status: `AUTOMATED PASS — HUMAN ACCESSIBILITY CHECK PENDING`

## Scope

`OverlayCoordinator` turns caller-supplied accessibility preferences into one typed
`OverlayPresentationPolicy` for both the Layout Chooser and Placement Preview. Reduce
Motion requests immediate presentation; Reduce Transparency requests an opaque surface;
Increase Contrast requests stronger borders and labels. The policy is display- and
geometry-independent: OverlayKit does not access Accessibility, calculate frames, or
execute a Window Action.

## Automated evidence

- `OverlayCoordinatorTests`: 12 tests, 0 failures.
- Dedicated tests inject each preference independently and verify that both render
  models receive the matching motion, background, or contrast treatment.
- Integrated Debug suite: 257 tests run, 2 hardware-gated skips, 0 failures.

## Fixtures and command

The deterministic recording renderer receives a standard three-choice Layout Chooser
and a pre-resolved Placement Preview frame; no physical Display, Accessibility
permission, or system preference is read.

```sh
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS' \
  -only-testing:MyMacXTests/OverlayCoordinatorTests

xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS'
```

## Remaining gates and assumptions

- Application composition must supply the current system accessibility preferences and
  refresh the presentation when they change.
- A human must inspect the rendered Layout Chooser and Placement Preview with each
  macOS setting enabled, including legibility and absence of unwanted motion.
- VoiceOver roles, announcements, and physical keyboard delivery to the non-activating
  panel remain human assistive-technology checks. This record does not claim they pass.

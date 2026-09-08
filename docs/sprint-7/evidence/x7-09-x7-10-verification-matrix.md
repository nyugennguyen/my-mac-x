# X7-09/X7-10 — accessibility, appearance, and usability matrix

Status legend: `PASS-AUTO`, `TODO-RENDER`, and `TODO-HUMAN`. Automated evidence is
recorded only where the production seam is exercised; visual approval remains human-owned.

## Automated and rendered checks

| ID | Scope and variants | Method | Pass rule | Status / retained evidence |
|---|---|---|---|---|
| A01 | Shortcut labels: letters, number row, arrows, F1/F12, Home/End/Page keys, keypad, unknown code; representative keyboard layouts | Unit-test the shared production presenter and every UI presentation model | No user-facing string contains a bare numeric key code; accessible and visible labels describe the same chord; reopen round trip is identical | PASS-AUTO — resolver and Settings presentation tests; human international-layout spot check remains in the gate |
| A02 | Chooser geometry: notch/non-notch; 1280×720 through large Displays; negative origins; menu bar/Dock edges; 1–9 regions | Pure placement/hit-region tests | Panel is inside visible frame; rendered and pointer regions are identical; target minimum is met; stable hover does not move targets | PASS-AUTO — placement, shared-padding, minimum-target, negative-origin, and edge-clamp tests |
| A03 | Drag state: slow/fast movement, reverse direction, leave/re-enter, cancel, release, Display crossing | Composition/interface tests | One selection per entered target; no focus activation; correct Captured Window; preview never commits; cancel dismisses all overlays | PASS-AUTO — drag composition/state tests; real pointer feel remains P01–P04 |
| A04 | Keyboard chooser: arrows, wrap/clamp policy, Return, Escape, focus loss | Production input adapter integration test | Inputs reach the visible chooser only; Return commits selected action; Escape cancels; unrelated keystrokes are not retained/logged | PASS-AUTO — production adapter lifecycle, routing, commit/cancel, and pass-through tests |
| A05 | Accessibility preference propagation | Adapter/composition tests toggling Reduce Motion, Reduce Transparency, Increase Contrast while visible | Chooser, preview, and HUD update live and consistently; motion policy is actually consumed by renderer | PASS-AUTO — live chooser/preview/HUD policy and redraw tests |
| A06 | Settings at 880×620 and 760×520; empty/error/loading/disabled/recording states | Render production SwiftUI/AppKit hierarchy | No clipping/overlap; primary actions visible; focus indicators unobscured | PASS-AUTO / TODO-HUMAN — 18 production-view render combinations pass; visual/focus approval remains open |
| A07 | Chooser/preview/HUD in Light/Dark × normal/high contrast × transparency/reduced transparency | Render production views at fixed backing scale | Approved pixel baselines exist; diffs are intentional; selected/hover/disabled states remain color-independent | PASS-AUTO / TODO-HUMAN — [production pixel-render evidence](x7-10-production-pixel-rendering.md) covers all 24 fixed-scale render combinations; baseline review and visual approval remain open |
| A08 | Menu bar: granted/denied/revoked, active/paused, enabled/disabled quick actions | Menu hierarchy assertions plus captured menus | Native shortcuts/state/checkmarks are correct; disabled reason is available; no truncation at supported locale | TODO-AUTO + TODO-RENDER — test log and captures |
| A09 | Dynamic content stress: longest supported localized labels, large accessibility text where macOS permits | Render at minimum sizes | No clipped critical text or unreachable action; labels wrap or expand predictably | TODO-RENDER — PNGs and review record |
| A10 | Real pixel snapshot integrity | Test must instantiate the production renderer, not only `OverlayRenderModel` | A deliberate padding/color/glyph change causes a meaningful image diff | PASS-AUTO — [production pixel-render evidence](x7-10-production-pixel-rendering.md); selected glyph/title, constrained warning, and HUD state changes each produce a non-equal RGBA digest |

## Human accessibility and appearance checks (X7-09)

Run each applicable row on the Settings shell, Global Hotkey editor, Super Mode
editor, menu bar, Layout Chooser, Placement Preview, Super HUD, and onboarding.

| ID | Environment / task | Pass rule | Status / retained evidence |
|---|---|---|---|
| H01 | Keyboard-only, Full Keyboard Access on | Every control is reachable in logical order; focus is visible; Space/Return activates; Escape cancels transient UI; no keyboard trap | TODO-HUMAN — tester, macOS/hardware, checklist, notes |
| H02 | VoiceOver on | Every control has concise role/name/value/hint; selection and status changes are announced once; focus is not destroyed on chooser hover | TODO-HUMAN — VoiceOver transcript/notes |
| H03 | Light then Dark appearance | Text, glyphs, material, separators, selection and preview remain legible and native-looking | TODO-HUMAN — paired screenshots and reviewer approval |
| H04 | Increase Contrast on | Boundaries/focus/selection/status remain distinguishable without color alone | TODO-HUMAN — screenshots and notes |
| H05 | Reduce Transparency on | No translucent-only information; opaque fallback is visually coherent across chooser, preview and HUD | TODO-HUMAN — screenshots and notes |
| H06 | Reduce Motion on | Chooser/preview/HUD avoid spatial animation; state change remains understandable; no flashing/jump | TODO-HUMAN — screen recording and notes |
| H07 | Appearance changes while Settings/overlay is visible | Surfaces update without reopen, stale colors, or unreadable transition frames | TODO-HUMAN — screen recording and notes |
| H08 | Color differentiation check (including grayscale/color-filter spot check) | Error/success/selected/constrained states retain text, symbol, shape, or border cues | TODO-HUMAN — screenshots and notes |

## Physical pointer and usability gate (X7-10)

### Required hardware matrix

| ID | Hardware/topology | Required scenarios | Status |
|---|---|---|---|
| P01 | Apple Silicon MacBook with notch, single Display | Slow/fast drag, traverse all regions, reverse, commit, cancel; menu bar visible/auto-hidden | TODO-HUMAN |
| P02 | Mac without notch (desktop or non-notch MacBook), single Display | Top-center fallback; same traversal and commit/cancel scenarios | TODO-HUMAN |
| P03 | Notch Mac + external Display | Cross both directions; Display origins left/right and, if available, above/below | TODO-HUMAN |
| P04 | Non-notch Mac + two Displays | Cross both directions; reconnect/reorder Displays during a fresh interaction | TODO-HUMAN |

For P01–P04, pass only when the chooser stays visibly anchored, targets do not
move under a stable pointer, no target is hidden beyond an edge or under the
preview, the app does not steal focus, and the released window lands in the
region visibly selected immediately before release.

### Five-user task protocol

Use five representative users who did not implement the feature. Do not coach
after reading the task prompt.

1. “Place this window on the left half using the top edge.”
2. “Cancel a placement after the chooser appears.”
3. “Change the Maximize shortcut to a shortcut of your choice, save it, close
   Settings, reopen it, and tell us what shortcut is assigned.”
4. “Use that shortcut to maximize the test window.”
5. “Turn on Super Mode and identify its Prefix without interpreting a number.”

Record completion, errors, hesitation points, accidental actions, elapsed time,
and verbatim confusion. Pass only if all five users complete Snap and hotkey-edit
tasks without coaching, no user encounters an unexplained numeric key label, and
no P0/P1 issue is opened from observation.

## Final acceptance record

Gate G7 may be proposed only when:

- A01–A10 have retained passing evidence;
- H01–H08 and P01–P04 have named human results;
- five-user protocol results meet the rule above;
- all P0/P1 audit findings are closed with links to their proving evidence; and
- the project owner records an explicit experience Go/No-Go decision.

# X7-01 — whole-app heuristic, accessibility, and appearance audit

Audit basis: current working tree inspected on 2026-09-08. This is a code-level
audit of production surfaces and their tests. It does not claim that Light/Dark,
compact-size, VoiceOver, pointer-feel, or physical-Display checks passed.

## Shipped-surface inventory

| Surface | Production source | Existing evidence | Code-level assessment |
|---|---|---|---|
| Menu bar status and quick actions | `Sources/AppShell/AppLifecycleCoordinator.swift:235`; `Sources/AppShell/SettingsShell.swift:153` | Menu planning/routing tests | Uses native menus, labels, tooltips and standard shortcuts. No rendered/VoiceOver evidence. |
| Settings shell: General, Snapping, Hotkeys summary, Layouts, Displays, App Rules, Transfer, About | `Sources/AppShell/SettingsShell.swift:665` | Model and routing tests | Native split view/forms and minimum size exist. No compact-size rendered proof or full keyboard/VoiceOver traversal. |
| Global Hotkey editor | `Sources/AppShell/SuperModeSettingsWindowController.swift:520` | Model tests | Separate window; visible shortcut string still exposes a numeric code. |
| Super Mode editor | `Sources/AppShell/SuperModeSettingsWindowController.swift:1` | Model/window tests | Separate window; prefix and command editing expose raw numeric hardware codes. |
| Layout Chooser | `Sources/OverlayKit/OverlayCoordinator.swift:383`; composed at `Sources/AppShell/CrossDisplayDragComposition.swift:276` | Coordinator/render-model assertions | Non-activating native panel exists, but placement, hit testing, runtime accessibility preferences, and keyboard wiring are incomplete. |
| Placement Preview | `Sources/OverlayKit/OverlayCoordinator.swift:397` | Coordinator/render-model assertions | Semantic colors and constrained warning exist. No proof it stays behind/clear of chooser. |
| Super HUD | `Sources/OverlayKit/SuperHUDCoordinator.swift:199` | Coordinator/render-model tests | Label and state-specific symbol exist. Runtime system appearance/accessibility wiring is not demonstrated. |
| Permission/onboarding | Menu and General-pane permission actions only (`Sources/AppShell/AppLifecycleCoordinator.swift:275`; `Sources/AppShell/SettingsShell.swift:1012`) | Permission state/model tests | No first-run onboarding surface or guided permission sequence was found in production sources. |

## Ranked findings

### P0 — user-facing shortcut editors expose raw hardware codes

**Evidence:** Super Mode displays `Text(String(model.prefix.hardwareKeyCode))`
and accepts numeric `TextField("Code", …)` values with an accessibility label of
“Hardware key code” at
`Sources/AppShell/SuperModeSettingsWindowController.swift:361-363` and
`:474-479`. Global Hotkeys formats the visible value as `Key
\(chord.hardwareKeyCode)` at `:669-671` even though its accessibility label uses
`HotkeyChordPresenter`.

**Impact:** This directly violates X7-06 and Gate G7. Sighted users see confusing
integers, while VoiceOver and visible presentation disagree.

**Expected behavior:** Every visible, recorded, persisted, and reopened shortcut
uses modifier glyphs and a localized key label. Unknown keys use a descriptive
fallback without the integer. Editing is recorder-led, not numeric-entry-led.

### P0 — required first-run onboarding is absent

**Evidence:** The production UI inventory contains Settings, menu, chooser, preview,
and HUD surfaces, but no onboarding controller/view. Permission actions exist only
in the menu and General Settings at
`Sources/AppShell/AppLifecycleCoordinator.swift:275-282` and
`Sources/AppShell/SettingsShell.swift:1012-1050`.

**Impact:** A new user can reach a non-working window manager without an in-context
explanation before macOS Accessibility approval; the project plan's required
onboarding/permission surface and X7-08 cannot be accepted.

**Expected behavior:** On first run, explain why Accessibility is needed before
requesting it, show current state and recovery, allow safe deferral, and route to
System Settings. Re-entry after denied/revoked status remains clear.

### P1 — chooser placement is fixed and not constrained to the visible Display

**Evidence:** Composition hard-codes `360 × 220` and places the panel from the
trigger midpoint/minimum Y without clamping or collision avoidance at
`Sources/AppShell/CrossDisplayDragComposition.swift:73-75` and `:301-306`.
The plan baseline is 420–560 × 110–150 pt and X7-04 requires edge, dragged-window,
Notch, and menu-bar avoidance.

**Impact:** The chooser can feel oversized/tall, sit outside a short visible frame,
or obscure the dragged window. There is no code-level evidence for non-notch,
auto-hidden menu bar, negative-origin, or compact Display placement.

**Expected behavior:** A pure placement policy chooses a compact size and anchors
near the trigger, then clamps to the current Display's visible frame and avoids the
preview/dragged-window critical area without jumping during stable hover.

### P1 — pointer hit regions can diverge from actual controls

**Evidence:** Pointer tracking divides an inset panel into mathematically uniform
cells (`Sources/OverlayKit/OverlayCoordinator.swift:246-270`), while the renderer
uses an intrinsic-content `NSGridView` of titled `NSButton`s
(`:458-481`, `:493-522`). The hit-test does not query rendered button frames.

**Impact:** With localized or unequal titles, the highlighted/selected Layout
Region can differ from the control under the pointer, reinforcing the reported
clunky feel.

**Expected behavior:** Pointer mapping and visible targets derive from the same
layout geometry. Each stable hover maps to exactly one stationary target and
selection never changes outside a rendered target.

### P1 — each hover selection rebuilds the chooser's entire view tree

**Evidence:** `select` calls `renderChooser` (`Sources/OverlayKit/OverlayCoordinator.swift:337-343`),
and the production renderer replaces `chooserPanel.contentView` on every render
(`:388-394`).

**Impact:** Replacing all controls during pointer movement risks visible churn,
lost accessibility focus, and unstable hover/pressed state.

**Expected behavior:** Present the panel once per interaction and update selection
state in place. Button frames, accessibility elements, and pointer targets remain
stable until dismissal or a real topology change.

### P1 — Layout Chooser keyboard API is not wired into production

**Evidence:** `OverlayCoordinator.handleKeyboard` exists at
`Sources/OverlayKit/OverlayCoordinator.swift:273-294`, but no production caller
was found. The panel explicitly cannot become key/main at `:411-429`.

**Impact:** Arrow/Return/Escape behavior is unit-testable but unavailable through
the shipped composition, so X7-09 keyboard-only acceptance is unsupported.

**Expected behavior:** A privacy-safe production input route forwards only chooser
navigation/confirm/cancel events while visible, without activating the app or
capturing typed text.

### P1 — system accessibility appearance settings are not fully connected

**Evidence:** `OverlayPresentationPolicy` supports Reduce Motion, Reduce
Transparency, and Increase Contrast (`Sources/OverlayKit/OverlayCoordinator.swift:86-129`).
Production composition maps only the app's `usesReducedEffects` toggle to the
first two and never supplies Increase Contrast
(`Sources/AppShell/CrossDisplayDragComposition.swift:247-251`). Super HUD is
constructed with defaults in production and keeps an immutable policy
(`Sources/OverlayKit/SuperHUDCoordinator.swift:52-76`).

**Impact:** System accessibility preferences may not affect overlays/HUD unless a
separate app setting happens to be enabled; Increase Contrast cannot reach the
production chooser/preview path shown here.

**Expected behavior:** System settings are observed and combined with any app
override, then applied live to every overlay/HUD. Increase Contrast has a
color-independent outline/state treatment.

### P1 — “snapshot” tests do not render pixels

**Evidence:** `Tests/MyMacXTests/OverlayKit/OverlaySnapshotTests.swift:9-28`
records render models in arrays. Assertions inspect frames, selections and policy
enums; they do not instantiate the production view, render a bitmap, or compare an
approved image.

**Impact:** Regressions in material, spacing, typography, clipping, glyphs,
selection visuals, and Light/Dark appearance are invisible to the suite. X7-10's
approved snapshot requirement remains open.

**Expected behavior:** Render production chooser, preview, HUD, and Settings
surfaces at a fixed scale/appearance into deterministic images; compare them with
reviewed baselines and retain diffs.

### P2 — visual tokens are duplicated and not semantic

**Evidence:** Chooser and HUD separately hard-code material, 12 pt radius, borders,
font sizes, and spacing in `Sources/OverlayKit/OverlayCoordinator.swift:438-481`
and `Sources/OverlayKit/SuperHUDCoordinator.swift:225-270`.

**Impact:** Refinements can drift across signature surfaces and do not yet satisfy
X7-02's one semantic visual system.

**Expected behavior:** Both use a shared semantic token/presentation vocabulary
for material fallback, padding, radius, typography, borders and target states.

### P2 — Settings hierarchy splits related editing into separate windows

**Evidence:** The Hotkeys summary launches two standalone editors
(`Sources/AppShell/SettingsShell.swift:1137-1156`), each with its own window size,
heading, save controls, and copy in
`Sources/AppShell/SuperModeSettingsWindowController.swift:1-60` and `:520-551`.

**Impact:** Users lose sidebar context and encounter inconsistent save/reload
placement. This increases navigation cost and makes the Settings experience feel
less like one macOS preferences app.

**Expected behavior:** Prefer in-shell editing or a clearly modal/detail workflow
with consistent title, status, recorder, save/cancel/reset placement and keyboard
behavior.

## Audit disposition

- Remediated and covered by automated production-seam tests in the Sprint 7
  candidate: numeric Hotkey/Super Mode presentation, first-run Accessibility
  explanation, visible-frame chooser clamping, same-Display frame stability,
  render/hit-test padding alignment, chooser view-tree churn, live overlay/HUD
  accessibility policy, and privacy-safe keyboard forwarding to the
  non-activating chooser.
- Production chooser, preview, HUD, and Settings views now render through automated
  appearance/state matrices. Human baseline approval, keyboard/VoiceOver traversal,
  and physical pointer evaluation remain intentionally open; automation cannot
  approve perceived visual quality or real interaction feel.
- The shortcut editors remain focused child windows by deliberate scope decision:
  they retain the Settings shell as their launch context and now share consistent
  native presentation, recording, save/cancel, status, and accessible hotkey
  semantics. Embedding them is a future information-architecture option, not an
  open P0/P1 Sprint 7 defect.
- X7-01 has code-level inventory and findings, but screenshot and human review
  remain in the companion matrix. Gate G7 stays open until those human-only rows
  are executed.

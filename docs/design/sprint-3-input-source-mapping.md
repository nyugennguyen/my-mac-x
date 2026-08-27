# Sprint 3 — H3-07 input-source/key-label mapping design

**Status:** design and confirmation request only. No H3-07 tests or production code are
authorized until the seam below is confirmed.

## Scope and ownership

H3-07 owns the system input-source Adapter behind the existing
`HotkeyKeyLabelResolving` seam. H3-03 owns `HotkeyChordPresenter`, modifier ordering,
accessibility composition, and the visible hardware-code fallback. H3-07 must not alter
`HotkeyChord` equality, persistence, registration, conflict detection, or recorder input.

The current seam is deliberately small:

```swift
protocol HotkeyKeyLabelResolving: Sendable {
    func label(for hardwareKeyCode: UInt16) -> String?
}
```

Its contract is:

- Input is only a macOS virtual/hardware key code. No `NSEvent`, characters, typed text,
  timestamps, input-source identifiers, or window context crosses the seam.
- A non-`nil` result is one short, deterministic, user-facing key label for the current
  selected keyboard source. It must not be used as identity.
- Return `nil` for unavailable, ambiguous, dead-key, multi-character, special, or failed
  translation. The caller then renders `Key code 0xNN` and marks the presentation as a
  hardware-code fallback.
- The method is side-effect free from the caller's perspective and safe to call more than
  once for the same code. It may use an internal cache.

This is a real internal seam because there are two Adapters: the AppKit/macOS system
Adapter and a deterministic mapping Adapter used by tests. UI and recorder remain unaware
of both implementations. The Interface stays shallow in type surface but deep in useful
behavior: current-source lookup, layout translation, normalization, caching, invalidation,
and fallback remain local to one Adapter.

## Proposed system Adapter behavior

1. On a cache miss, read the current selected keyboard input source from the public AppKit
   text-input system and obtain the source's Unicode keyboard-layout data when available.
   Translate the requested virtual key code through the layout using the public Apple
   translation operation documented in [the H3-07 research note](../research/macos-input-source-key-labels.md).
2. Use a neutral display translation (no Command/Option/Control/Shift) because the presenter
   resolves the key label separately from modifier chips. Preserve non-printing names only
   where the adapter has a stable explicit mapping (for example arrows); otherwise return
   `nil`.
3. Accept a result only when it is a single, printable, stable label. Empty output,
   dead-key state, composed/multi-character output, or an input method with no suitable
   layout data returns `nil`.
4. Normalize display labels for UI (for example uppercase keycap labels where the layout
   yields lowercase base letters), but never normalize the stored code or modifiers.
5. Never log the source identifier, generated characters, or the requested code. The
   adapter may expose only the returned label to `HotkeyChordPresenter`.

The Carbon Unicode-layout API is a contained public-API adapter despite Apple's warning
that general applications should prefer AppKit event character methods. The presenter has
only a code, not an event; using an event-character property would reintroduce event/text
data into the seam. This trade-off is local and reversible if Apple supplies a supported
code-to-keycap API later.

## Cache and invalidation contract

- Cache key: `(selected input-source generation, hardwareKeyCode)`; do not key only by code.
- Cache value: either a label or an explicit “unresolvable” result, so repeated failures do
  not repeatedly query the OS.
- The system Adapter observes `NSTextInputContext.keyboardSelectionDidChangeNotification`.
  On receipt, discard the entire cache and increment an internal generation. The next
  lookup reads the newly selected source lazily.
- Also clear the cache when the adapter is recreated or its source/layout provider reports
  unavailable data. App activation may trigger a refresh as a conservative measure, but is
  not a substitute for the input-source selection notification.
- Invalidation is idempotent and safe during a presentation call: an in-flight lookup
  completes with its captured source snapshot; subsequent calls use the new generation.
- The presenter remains synchronous. Notification observation and cache mutation belong to
  the adapter's confined implementation, not to `HotkeyChordPresenter` or Settings UI.

## Fallback and privacy

`HotkeyChordPresenter` is the single fallback owner. When the resolver returns `nil`, it
must continue to produce `Key code 0xNN`, include that same text in the accessibility label,
and leave the `HotkeyChord` untouched. There is no second character-based fallback in UI.

The resolver runs only while Settings needs to render a candidate. It does not install a
global monitor or Event Tap, request Input Monitoring, capture typed text, inspect the
focused window, access the clipboard, or write diagnostics. Generated characters are
ephemeral inside the adapter and must never be persisted or logged. Input-source names and
identifiers are test evidence metadata only, not product state.

## Required source matrix

The matrix is split between deterministic automation and human OS evidence:

| Source | Automated fixture expectation | Human evidence |
|---|---|---|
| U.S. — ABC | Code `0x00` resolves to `A`; code `0x06` resolves to `Z`; `0x7B` resolves to `Left Arrow` or the documented stable special-key label; identity remains the same code/modifiers. | Select “ABC” in macOS Input Sources, record `⌘A`, `⌘Z`, and `⌘←`; switch away/back and verify labels refresh without re-recording. |
| ABC (explicit source selection) | Same code fixture as U.S.; proves source ID participates in cache generation rather than assuming locale. | Select the explicit ABC source and repeat the three captures; record source name/identifier and OS version in evidence, not in app logs. |
| Vietnamese — Telex | Fixture source with no usable Unicode layout returns `nil`; presenter displays `Key code 0x00` fallback; code/modifier identity is unchanged. | Select Vietnamese — Telex, record `⌘A`, `⌘Z`, `⌘←`; verify no typed Vietnamese text is persisted/logged and that switching to ABC changes presentation after notification. |

The human check is required because IME composition and selected-source state are OS-owned;
it is not replaced by a test that merely injects a label string.

## Exact observable test cases (after seam confirmation)

All tests cross `HotkeyChordPresenting` or the agreed resolver seam. They use a deterministic
source provider/mapping Adapter; none synthesize `NSEvent` or reach into Carbon internals.

| ID | Setup | Expected result |
|---|---|---|
| M-01 | ABC fixture, code `0x00` | `present` returns label `A`, no fallback; chord equality is unchanged. |
| M-02 | ABC fixture, code `0x06` | `present` returns `Z`, no fallback. |
| M-03 | ABC fixture, code `0x7B` | Stable `Left Arrow` label if provided by the mapping; otherwise exact hardware fallback, never empty text. |
| M-04 | Vietnamese Telex fixture reports no usable layout | Presenter returns `Key code 0x00`, accessibility label contains the same fallback, and `usedHardwareCodeFallback == true`. |
| M-05 | Same code queried twice under one source generation | Provider performs one source/layout lookup; both returned presentations are equal. |
| M-06 | Query code `0x00`, switch fake source ABC → Vietnamese Telex, emit selection-change invalidation, query again | Second result is the Telex fallback, proving stale ABC label is not served. |
| M-07 | Invalidate twice, then query an unmapped code | No duplicate failure or notification effect; one deterministic fallback. |
| M-08 | Mapping returns empty, multi-character, dead-key, or unsupported result | Resolver returns `nil`; presenter uses exact hardware-code fallback for each case. |
| M-09 | Same physical code/modifiers with two different fixture labels | Presentation changes only; `HotkeyChord` equality/hash and any binding identity remain equal. |
| M-10 | Source provider temporarily unavailable | Resolver returns `nil` without throwing/logging; later successful lookup repopulates cache. |
| M-11 | Human ABC/Telex/ABC sequence | Evidence records labels and refresh behavior; no raw characters, source IDs, or titles appear in diagnostics/config. |

## Confirmation requested

Please confirm this H3-07 seam and ownership before implementation:

> Confirm `HotkeyKeyLabelResolving.label(for:)` as the only presenter-facing seam; authorize
> a macOS system Adapter based on public AppKit text-input source selection and contained
> Unicode keyboard-layout translation, with generation-keyed caching, invalidation on
> `NSTextInputContext.keyboardSelectionDidChangeNotification`, `nil` for ambiguous/IME
> results, and `HotkeyChordPresenter` as the sole hardware-code fallback owner. Confirm the
> M-01…M-11 test matrix and the human ABC/Vietnamese Telex evidence gate. No tests or
> production implementation are included in this design.

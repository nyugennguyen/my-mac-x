# H3-07 input-source/key-label mapping evidence

Date: 2026-08-26

Automated coverage is in `HotkeyKeyLabelResolverTests`. It exercises ABC labels,
arrow labels, cached successes and failures, generation-keyed invalidation, and
presenter-owned hardware-code fallback for unavailable or ambiguous results.

## Human OS gate — pending

Run this check on a signed/debug build with Settings rendering the same chord:

1. Select **ABC** in macOS Input Sources and verify `⌘A`, `⌘Z`, and `⌘←` render
   as `A`, `Z`, and `Left Arrow` while the stored hardware codes remain unchanged.
2. Switch to **Vietnamese — Telex** and repeat the captures. Verify an input
   method without a usable Unicode keyboard layout uses `Key code 0xNN` fallback.
3. Switch back to ABC and verify labels refresh after the input-source selection
   notification without re-recording the chord.
4. Confirm no typed Vietnamese text, source identifiers/names, titles, or raw
   characters appear in diagnostics or persisted configuration.

Record the macOS version, selected source names/identifiers, and observed labels
here after a human performs the check. This document intentionally does not claim
that the OS matrix has passed.

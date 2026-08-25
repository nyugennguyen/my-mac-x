# F1-06 — Privacy-safe diagnostics evidence

Status: `PASS`

## Delivered behavior

- Diagnostics accepts typed Accessibility, Input and Window Action failures only.
- Entries contain one allowlisted stable code and severity; the API has no raw keystroke, typed text, title, clipboard, screenshot or free-form message field.
- Public `AXError` values map to the application taxonomy without preserving OS descriptions.
- `unknownAction(ActionID)` and `actionDisabled(ActionID)` preserve the approved Window Action contract, while diagnostics deliberately discard the identifier value.
- Production output uses `OSLog` with a fixed subsystem/category and public allowlisted code.

## Verification on 2026-08-24

- Table coverage exercises all 25 diagnostics failure variants, all stable codes and all 16 current public `AXError` cases.
- Test confirms an `ActionID` value never appears in the emitted entry.
- Concurrent writer test verifies 100 synchronized writes; mutable test storage is lock-protected.
- Current full integrated suite: 45/45 pass.
- Debug and Release app builds pass after integration.

## Remaining work

- F1-04 and input implementation will connect raw platform failures to this taxonomy.
- Release review must keep the logging API typed; do not add a general-purpose string logger.

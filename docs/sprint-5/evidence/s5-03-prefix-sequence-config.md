# S5-03 — Prefix and sequence configuration

Status: `DONE — AUTOMATED; REVIEW APPROVED; HUMAN VERIFIED`

## Scope and observable contract

The InputKit configuration Module validates and applies a Prefix, a timeout bounded to 250...5000 milliseconds, and one- or two-level hardware-key-code paths. The default is Control-Space (hardware key code 49) with a 1000-millisecond timeout.

Validation returns typed failures for an invalid timeout, Prefix, path, hardware key code or Action ID; Escape and modifier-only sequence keys; duplicate paths; roots that ambiguously mix a one-level action with a submenu; protected system Prefixes; and Prefix collisions with a Hotkey. Prefix policy delegates to `HotkeyConflictDetector`, so S5-03 does not introduce a second reserved-hotkey catalog. Rejection occurs before `SettingsStoring.save` and before runtime replacement.

`SettingsStore` remains the only `SettingsDocumentPersisting` writer. Schema v2 stores Hotkeys plus the Prefix, timeout and command paths. Valid schema-v0 and schema-v1 documents are atomically migrated to v2 with the default Super Mode configuration; future-version recovery locking and corrupt-document quarantine behavior remain in place.

A successful apply persists first, then atomically assigns one immutable runtime snapshot inside the runtime actor. Each replacement receives a monotonically increasing revision and clears active-session identity. Runtime freshness requires an explicitly activated token whose configuration revision and `SuperModeSessionID` both match; replacement, stale-revision activation, reused IDs and forged or unactivated tokens cannot remain current.

## Changed files and Adapter seam

- `Sources/InputKit/SuperModeConfiguration.swift`
- `Sources/PersistenceKit/SettingsStore.swift`
- `Tests/MyMacXTests/InputKit/SuperModeConfigurationTests.swift`
- `Tests/MyMacXTests/PersistenceKit/SettingsStoreTests.swift`
- `Tests/MyMacXTests/PersistenceKit/InMemorySettingsDocumentAdapter.swift`
- `MyMacX.xcodeproj/project.pbxproj`
- `docs/sprint-5/evidence/s5-03-prefix-sequence-config.md`
- `docs/sprint-5/evidence/README.md`
- `docs/sprint-5/README.md`

Tests cross the `SuperModeConfigurationModule`, `SettingsStoring` and runtime configuration Interfaces. `InMemorySettingsDocumentAdapter` is the persistence Adapter and exposes only document state and atomic replacement count needed to prove no write. The production `LocalSettingsDocumentAdapter` remains unchanged. No Accessibility or Event Tap Interface is used.

## Automated evidence

Focused command:

```bash
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' -only-testing:MyMacXTests/SuperModeConfigurationTests -only-testing:MyMacXTests/SettingsStoreTests
```

Result: `TEST SUCCEEDED` on 2026-08-31 — 15 tests, 0 failures: 11 `SettingsStoreTests` and 4 `SuperModeConfigurationTests`. Coverage includes exact v2 Prefix/timeout/one- and two-level path persistence, v0/v1 migration, invalid timeout/path/key/Action ID, Escape and modifier-only keys, duplicates, root ambiguity, protected Prefix, Hotkey/Prefix conflict, zero document/runtime replacement on rejection, persistence-failure isolation, atomic runtime replacement, and exact activated-token freshness.

Independent final review: `APPROVE` with confidence `0.96`. The reviewer confirmed exact revision-plus-session-ID matching, replacement invalidation, stale-revision activation rejection, reused-ID isolation, and forged/unactivated-token rejection.

## Assumptions and known gaps

- Hardware key codes are layout-independent metadata. S5-03 stores no typed text, labels or raw key stream.
- Registered-but-unavailable Action IDs remain structurally loadable, matching the H3-05 Settings Store contract; unregistered Action IDs are rejected.
- S5-06 still owns Event Tap integration and same-callback suppression. S5-07 still owns rapid-input and timeout scheduling evidence.
- Project-owner human verification was accepted as part of the G5 Go decision on 2026-09-07.

## Human-only evidence

`ACCEPTED — 2026-09-07` — the project owner reported completing manual testing and successfully using Super Mode. Hardware/input-source details were not supplied and are not inferred.

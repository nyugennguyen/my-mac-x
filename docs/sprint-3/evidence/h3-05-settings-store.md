# H3-05 — Versioned Settings Store

## Scope

`SettingsStoring` is the sole external persistence Interface. It atomically persists a
validated `HotkeySettings` binding snapshot; it does not implement H3-04 conflict policy or
H3-06 hotkey reconciliation.

## Implemented contract

- UTF-8 JSON v1 with a strict allowlist, a 256 KiB document limit, a depth limit of four and
  duplicate-key rejection before values reach callers.
- Exact versionless v0-to-v1 migration. The migrated v1 document is atomically written before
  reporting the migrated outcome.
- Unsupported future versions are preserved and lock saving for that store instance.
- Corrupt documents are quarantined before empty defaults are returned; a quarantine failure
  blocks later saves rather than overwriting recoverable bytes.
- Binding validation allows only a UUID, `UInt16` hardware code, four modifier bits and a
  known registry Action ID. An unavailable registered action remains valid.
- The production adapter uses user-only directory/file modes and a unique sibling temporary
  file. Tests use the deterministic in-memory adapter and observe only `SettingsStoring`.

## Automated evidence

Focused tests are in `Tests/MyMacXTests/PersistenceKit/SettingsStoreTests.swift` and cover
S-01 through S-10 except the H3-06-owned runtime assertion (S-11). The persistence production
sources passed a strict Swift 6 module compile. The integrated focused XCTest run passed:
**10 tests, 0 failures**.

## Remaining scope

Physical filesystem permission and atomic-replacement behavior remains a human/release
environment verification concern. This delivery makes no power-loss/fsync durability claim.

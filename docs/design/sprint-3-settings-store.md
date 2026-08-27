# Sprint 3 — H3-05 Versioned Settings Store: proposed Interface

**Status:** Proposal. No production code or tests are authorized until the seam below is
confirmed.

## Purpose and ownership

H3-05 owns durable, local persistence of the **last validated hotkey settings snapshot**. It
loads a known-good snapshot, migrates one supported prior schema, and makes one replacement
visible atomically. It turns a missing or corrupt local document into a typed recovery outcome;
it never crashes at launch because of user-editable filesystem data.

This is deliberately one deep Module rather than a collection of `UserDefaults` keys. Callers
learn two operations and typed outcomes. The implementation owns encoding, bounded decoding,
schema dispatch, sequential migration, validation of persisted structure, atomic replacement,
file permissions, corrupt-file quarantine and recovery reporting. That produces leverage for
the Settings UI, H3-06 runtime coordinator, relaunch tests and future import/export without
allowing each caller to decode or repair configuration differently.

H3-05 does **not** own a Settings UI draft, recording, chord labels, conflict policy, hotkey
registration, runtime reconcile, Window Action dispatch, Accessibility, history, layouts,
import/export or cloud sync.

## Proposed external seam — confirmation required

```swift
public struct HotkeySettings: Equatable, Sendable {
    public let bindings: [HotkeyBinding]

    public init(bindings: [HotkeyBinding]) {
        self.bindings = bindings
    }
}

public enum SettingsLoadResult: Equatable, Sendable {
    case loaded(HotkeySettings, origin: SettingsLoadOrigin)
}

public enum SettingsLoadOrigin: Equatable, Sendable {
    case persisted(schemaVersion: UInt16)
    case migrated(fromVersion: UInt16, toVersion: UInt16)
    case defaults(reason: SettingsDefaultsReason)
}

public enum SettingsDefaultsReason: Equatable, Sendable {
    case noDocument
    case corruptDocumentQuarantined
    case corruptDocumentCouldNotBeQuarantined
    case unsupportedFutureVersion
}

public enum SettingsSaveResult: Equatable, Sendable {
    case saved(schemaVersion: UInt16)
    case failed(SettingsSaveFailure)
}

public enum SettingsSaveFailure: Equatable, Sendable {
    case structurallyInvalid
    case documentNotWritable
    case atomicReplacementFailed
    case recoveryRequired
}

public protocol SettingsStoring: Actor {
    /// Returns a structurally valid persisted snapshot or the documented defaults.
    func load() async -> SettingsLoadResult

    /// Persists one H3-04-validated snapshot as one atomic local replacement.
    func save(_ settings: HotkeySettings) async -> SettingsSaveResult
}
```

`HotkeySettings` has one durable field in H3-05: `bindings`. Its order is user-visible settings
order and is preserved. The snapshot stores the existing `HotkeyBinding` identity (`id`),
hardware key code, normalised modifier bitset and stable `ActionID`. It stores neither a chord
label nor an input-source identifier. Future settings domains require a new documented schema
field and migration; they are not silently absorbed as an untyped dictionary.

The actor serializes `load` and `save`. A completed `.saved` means that a subsequent `load` by
this store sees the entire new document or an explicit I/O recovery result—never a mixture of
old and new bindings. It is an atomic-visibility guarantee, not an fsync/power-loss durability
claim beyond the operating system's documented local-file semantics.

## Schema and migration contract

The on-disk document is UTF-8 JSON. It has a size limit of 256 KiB, maximum nesting depth of
four, and no executable payloads. Decoding rejects duplicate keys, unknown top-level fields and
unknown binding fields before any value reaches a caller.

| Version | Wire shape | Status |
|---:|---|---|
| 0 | A versionless legacy object: `bindings` with `id`, `keyCode`, `modifiers`, `actionID` | Recognized only for one migration |
| 1 | `{ "schemaVersion": 1, "hotkeyBindings": [{ "id", "hardwareKeyCode", "modifiers", "actionID" }] }` | Current write format |

Migration is pure and sequential: decode v0 → construct v1 → structurally validate v1 →
atomically replace the original document with v1 → return `.migrated(fromVersion: 0,
toVersion: 1)`. A migration write failure leaves the source document unchanged and returns
defaults only with the typed recovery state; it must not claim that a migration succeeded.

A version greater than the latest supported version is **not** treated as corrupt and is never
overwritten. The store returns defaults with `.unsupportedFutureVersion` and a recovery-required
save state so an older app does not destroy settings written by a newer app.

Structural validation at decode time is limited to persistence safety:

- a binding UUID is well-formed and unique;
- `hardwareKeyCode` is representable as `UInt16`;
- modifier raw value uses only the four supported H3-03 bits;
- `actionID` is a non-empty stable identifier and is known to the read-only `ActionRegistry`;
- no persisted label, input-source name, raw event, typed text, window metadata or title is
  present.

`ActionRegistry` is injected into the Module as read-only discovery, never coupled to
`WindowActionCatalog` or Accessibility. An unavailable Action remains structurally valid and
persistable: availability may change between launches and the Settings UI must be able to show
that binding rather than erase it.

## Defaults, corrupt fallback and local-file safety

The default snapshot is `HotkeySettings(bindings: [])`. A missing document returns
`.loaded(defaults, origin: .defaults(reason: .noDocument))` and performs no write. This lets a
first launch remain read-only until the user commits a validated change.

For a malformed, oversized, duplicate-key, invalid-structure or failed-migration document, the
store attempts to rename it in the same directory to a non-user-controlled
`settings.corrupt.<UUID>.json` with user-only permissions. It then returns default settings with
`.corruptDocumentQuarantined`. The original bytes are never parsed into diagnostics or UI copy;
only a fixed recovery category may be logged.

If quarantine cannot be completed, the store returns default settings with
`.corruptDocumentCouldNotBeQuarantined`, but `save` returns `.failed(.recoveryRequired)` until
the app can preserve the source or the user resets it through a later explicit recovery flow.
This avoids silently overwriting potentially recoverable user configuration.

The production Adapter creates the containing directory with user-only permissions, writes a
new encoded document to a uniquely named temporary sibling, closes it, applies user-only file
permissions, and replaces the destination in the same directory. On any failure it removes only
its uniquely named temporary sibling. No broad-directory deletion, in-place truncation or
best-effort partial document write is permitted.

## Validation and runtime boundaries

```text
Settings UI draft + H3-03 candidate
                │
                ▼
 H3-04 conflict/validity validator ── invalid ──> UI renders typed error; no save
                │ valid HotkeySettings
                ▼
       H3-05 SettingsStoring.save
                │ saved snapshot only
                ▼
 H3-06 runtime coordinator ──> GlobalHotkeyManaging.reconcile(bindings)
```

H3-04 is the policy gate before `save`: duplicate chords, no-modifier policy, reserved chords,
replace confirmation and binding-level user feedback are all H3-04. H3-05 does not reimplement
that policy or mutate a draft. Its defensive structural checks protect a tampered document and
return `.structurallyInvalid`; callers must not interpret that as a conflict UI decision.

H3-06 starts only after `.saved`. It owns reconciliation and its rollback/degraded behavior.
If runtime registration fails after a successful save, H3-06 reports runtime state and decides
whether/how to restore a prior saved snapshot through another `save`; H3-05 never calls
`GlobalHotkeyManaging` itself. This prevents filesystem state and runtime lifecycle from being
partially sequenced by Settings UI code.

## Internal persistence seam and real Adapters

The external seam is `SettingsStoring`. Inside its implementation, one persistence seam is
justified because production local files and deterministic fault injection genuinely vary:

```swift
protocol SettingsDocumentPersisting: Sendable {
    func readDocument() async throws -> Data?
    func replaceDocumentAtomically(with data: Data) async throws
    func quarantineCorruptDocument() async throws
}
```

- `LocalSettingsDocumentAdapter` uses the app-support directory and the atomic local-file
  protocol above.
- `InMemorySettingsDocumentAdapter` holds bytes and can deterministically inject missing,
  corrupt, read, quarantine and replacement outcomes.

The adapter never exposes paths, raw bytes or filesystem errors through `SettingsStoring`.
Those are implementation facts, which keeps caller and test locality at the external seam.

## Privacy and diagnostics

The persisted allowlist is: schema version, binding UUID, hardware key code, four modifier
bits and stable Action ID. The store must never persist raw keystrokes, typed characters,
chord labels, input-source identifiers, window/document titles, application content, clipboard,
screenshots, permission data, analytics, account identifiers or filesystem error text.

Diagnostics may contain only fixed categories such as `settings.migrated.v0-to-v1`,
`settings.recovered.corrupt`, or `settings.save.atomic-replacement-failed`. It may not include
a chord, Action ID, file path, document bytes or decoder/OS free text. This enforces threat
model TB-03 and T-08/T-14 without turning config recovery into a data leak.

## Proposed observable test matrix — no tests until confirmation

Tests cross only `SettingsStoring` using the deterministic persistence Adapter. They do not
inspect temporary files, JSON encoder calls, actor state, `FileManager`, `UserDefaults`, or
`GlobalHotkeyManaging` internals.

| ID | Known setup at the Interface | Expected observable result |
|---|---|---|
| S-01 | Missing document | Empty default bindings and `.defaults(.noDocument)`; no write occurs |
| S-02 | Save one H3-04-valid binding, construct a fresh store over its bytes | `.saved(1)` then the exact binding snapshot loads as `.persisted(1)` |
| S-03 | Valid v0 fixture | Exact v1-equivalent snapshot loads as `.migrated(0, 1)`; reopening reports `.persisted(1)` |
| S-04 | Malformed/oversized/duplicate-key document and successful quarantine | Empty defaults with `.corruptDocumentQuarantined`; later save is allowed |
| S-05 | Same corrupt document but injected quarantine failure | Empty defaults with `.corruptDocumentCouldNotBeQuarantined`; save returns `.failed(.recoveryRequired)` |
| S-06 | Replacement failure after a previously valid document | `.failed(.atomicReplacementFailed)`; a fresh store still loads the prior exact snapshot |
| S-07 | Structurally invalid persisted binding (unknown ActionID, unsupported modifier bit, duplicate UUID) | Corrupt recovery path; invalid data is never returned to a caller |
| S-08 | Structurally valid binding for currently unavailable Action | It loads unchanged; availability is not converted into deletion |
| S-09 | Future schema version | It is preserved and cannot be overwritten; typed future-version outcome is returned |
| S-10 | Save receives a snapshot that H3-04 did not validate | Store rejects structurally unsafe shape only; no conflict-policy assertion is made here |
| S-11 | Successful save followed by H3-06 failure | Store's result remains `.saved`; no registration/reconcile is observed at this seam |

Implementation proceeds in vertical red → green slices only after confirmation: S-01, then
S-02, then S-03, followed by one recovery/failure slice at a time.

## Confirmation requested

Please confirm the following H3-05 seam and policy before the first red test:

1. `SettingsStoring` is an actor with only `load()` and `save(HotkeySettings)`; H3-05 persists
   the last H3-04-validated hotkey binding snapshot and never reconciles runtime state.
2. The current schema is JSON v1, with a single supported v0→v1 migration as specified above;
   future schema versions are preserved and save-blocked rather than reset/overwritten.
3. Missing config returns empty defaults without writing; corrupt config is quarantined then
   defaults returned, while a failed quarantine blocks save to avoid overwriting source data.
4. H3-04 owns hotkey conflict/reserved-chord policy before save; H3-06 owns runtime reconcile
   after a successful save; H3-05 only performs defensive persistence validation.
5. The internal persistence seam uses both a local atomic-file Adapter and deterministic
   in-memory Adapter; tests observe only `SettingsStoring` outcomes.

If confirmed, the first vertical slice will be S-01: a missing document returns the empty
default snapshot and performs no write.

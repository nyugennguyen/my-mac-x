# Sprint 6 — Settings, profiles and polish

Sprint 6 targets Gate G6: a public beta with complete Settings, portable configuration backup, and keyboard/VoiceOver paths.

## Ownership

- A0 owns shared composition, the Xcode project, schema coordination and the gate.
- A1 owns U6-06, U6-08 and U6-11.
- A2 owns U6-01, U6-02, U6-03, U6-09 and U6-10.
- A3 owns U6-04, U6-05 and U6-07.

## Tracker

| ID | Status | Evidence |
|---|---|---|
| U6-01 | DONE — AUTOMATED | Quick Actions distinguish active, absent and unsupported Focused Windows per action capability. |
| U6-02 | DONE — AUTOMATED | General/Snapping shell exposes runtime and permission state. |
| U6-03 | DONE — AUTOMATED | Recorder and command-tree presentation have accessible paths. |
| U6-04 | DONE — AUTOMATED | Split/merge Layout Library rejects overlap and out-of-bounds saves. |
| U6-05 | DONE — AUTOMATED | Display Profiles can be created for connected displays and use validated reconnect-stable identifiers. |
| U6-06 | DONE — AUTOMATED | Bundle-ID-only rules fail closed for missing/invalid/conflicting identities. |
| U6-07 | DONE — AUTOMATED | Strict versioned import/export restores and hot-applies runtime settings without machine secrets. |
| U6-08 | DONE — AUTOMATED | Diagnostics reads live app/Event Tap state and emits typed, redacted status tokens only. |
| U6-09 | DONE — AUTOMATED; HUMAN QA PENDING | Keyboard/VoiceOver semantics, runtime reduced-effects updates and accessible navigation are implemented. |
| U6-10 | DONE — AUTOMATED | Settings copy is centralized and localizable with consistent empty/error states. |
| U6-11 | IMPLEMENTED; LIVE MEASUREMENT PENDING | Production instrumentation and budget evaluation pass; physical measurements remain human-gated. |

See [the evidence index](evidence/README.md) for exact automated results and remaining production/manual gates.

## Gate G6

Status: `CONDITIONAL — AUTOMATED PASS; HUMAN QA PENDING`

The complete suite passes 419 tests with 0 failures and 2 documented hardware skips. Production wiring is complete. Gate G6 is not claimed as PASS until a person verifies the keyboard/VoiceOver path; U6-11 additionally needs live performance measurements.

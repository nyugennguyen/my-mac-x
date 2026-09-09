# R8-10 — privacy, FAQ, and release communications

Status: **COMPLETE FOR DEMO; R8-03 CROSS-CHECKED**

The user-facing documents are in `docs/release/`:

- `privacy.md` explains why Accessibility and Input Monitoring are requested and what data is
  intentionally excluded.
- `faq.md` covers setup, safety, limitations, configuration, troubleshooting, and removal.
- `release-notes-0.1.0-beta.md` describes the demo beta without claiming release gates that
  still require a person, hardware, signing, or notarization.

The copy uses the project glossary (`Display`, `Window Action`, `Captured Window`, `Snap`,
`Maximize`, `Native Full Screen`, `Super Mode`, and `Prefix`) and the current release default:
macOS 14+, direct distribution, local configuration/history, no telemetry, manual update, and
physical Displays only.

R8-03's final call-site, log, entitlement and data inventory was cross-checked on 2026-09-09;
permission language was narrowed to the runtime-preflight Event Tap requirement. Before external
publishing, R8-07/R8-08 must add the actual Developer ID/notarized artifact identity, checksum and
download location.

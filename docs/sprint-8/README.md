# Sprint 8 — QA, security and release

Sprint 8 follows Gate G7 and preserves the project plan's separation between automated evidence and
human-only release approval.

## Tracker

| ID | Deliverable | Owner | Status | Evidence |
|---|---|---|---|---|
| R8-01 | Regression + hardware matrix | A2 | AUTOMATED PASS; HUMAN OPEN | [Matrix](evidence/r8-01-regression-hardware-matrix.md) |
| R8-02 | Permission/TCC lifecycle | A1 | AUTOMATED PASS; HUMAN OPEN | [TCC](evidence/r8-02-permission-tcc-lifecycle.md) |
| R8-03 | Event/AX privacy-security | A1 + A0 review | CODE PASS | [Security](evidence/r8-03-event-ax-privacy-security-review.md) |
| R8-04 | Soak/performance | A1 | 500-ACTION PASS; 8H/HARDWARE OPEN | [Soak](evidence/r8-04-soak-performance-core.md) |
| R8-05 | Crash/hang/race triage | A0/A1/A2 | AUTOMATED PASS; LIVE BUFFER OPEN | [Triage](evidence/r8-05-triage.md) |
| R8-06 | Hardened Runtime/entitlements | A3 + A0 review | AD-HOC PASS; DEV ID OPEN | [Runtime](evidence/r8-06-hardened-runtime-entitlements.md) |
| R8-07 | Signing/notarization/staple | A3 + SOL review | PIPELINE READY; HUMAN OPEN | [Signing](evidence/r8-07-signing-notarization.md) |
| R8-08 | DMG/ZIP/checksum | A3 | DEMO ARTIFACT PASS | [Artifacts](evidence/r8-08-versioned-artifacts.md) |
| R8-09 | Manual update/rollback | A3 | TOOLING PASS; HUMAN OPEN | [Rollback](evidence/r8-09-manual-update-rollback.md) |
| R8-10 | Privacy/FAQ/release notes | A2 + A0 review | COMPLETE FOR DEMO | [Communications](evidence/r8-10-release-communications.md) |
| R8-11 | Clean install/upgrade smoke | A3 | HUMAN OPEN | [Smoke](evidence/r8-11-clean-install-upgrade-smoke.md) |
| R8-12 | Go/No-Go | A0 | DEMO GO; V1 NO-GO | [Decision](evidence/r8-12-go-no-go.md) |

## Gate G8

Status: **NOT PASSED — CONTROLLED DEMO BETA READY**

The local ad-hoc beta is suitable for the requested demo. It is not suitable for external
distribution. Gate G8 requires a real Developer ID signature, notarization/staple, clean-machine
Gatekeeper pass, completed human/hardware/TCC/accessibility/soak evidence, no P0/P1, rollback
verification, and the project owner's stable-release Go/No-Go.

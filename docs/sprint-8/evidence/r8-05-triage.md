# R8-05 — beta crash/hang/race triage

Date: 2026-09-09

Status: **AUTOMATED TRIAGE PASS; LIVE BETA BUFFER OPEN**

The 448-test baseline had no failure. Sprint 8 review found and resolved three release-quality
issues before packaging: Event Tap recovery now resets after healthy input while remaining bounded
during repeated disables; packaged DMG and ZIP app bundles are signature-verified directly; and
permission copy no longer overstates Input Monitoring requirements.

No automated P0/P1 defect remains open. The human TCC, eight-hour soak, physical hardware,
VoiceOver/usability, Developer ID/notary and clean-machine runs remain release blockers, not defects
that can be closed by unit tests. Any failure from those runs reopens R8-05 and blocks stable release.

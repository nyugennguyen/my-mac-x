# R8-12 — Go/No-Go review

Date: 2026-09-09

## Decision

- **GO — controlled local demo beta:** the versioned ad-hoc DMG/ZIP and checksum passed build,
  integrity, embedded-bundle signature and automated regression checks.
- **NO-GO — external beta/v1.0:** Developer ID signing, notarization/staple, clean-machine
  Gatekeeper, the full TCC/hardware/accessibility matrix and eight-hour live soak remain pending.

There is no open automated P0/P1 defect. Known limits are recorded in the release notes and R8-01,
R8-02, R8-04, R8-07, R8-09 and R8-11 evidence. The rollback procedure and immutable prior-artifact
requirement are prepared, but real signed current/update/rollback artifacts still require a human run.

Gate G8 is therefore **NOT PASSED**. The project owner must perform the human-only checks and make
the stable-release Go/No-Go decision; a demo approval must not be relabeled as v1.0 approval.

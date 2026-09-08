# My Mac X — session handoff

## Current state

Sprint 2 and Sprint 3 updates were committed and pushed to the `dev` branch.

- Commit: `196e325` (`feat: complete Sprint 2-3 hotkey workflow`)
- Remote branch: `origin/dev`
- Push completed successfully.
- Local `build/` remains untracked and was intentionally excluded from the commit.

The Sprint 3 tracker and evidence are in [docs/sprint-3/README.md](/Users/mac/Projects/mymac-x/docs/sprint-3/README.md). Detailed implementation, test seams, and acceptance notes are already captured in the Sprint 3 evidence/design documents; consult those instead of duplicating their content.

## Verification completed

- Full Debug suite: 224 tests executed, 2 hardware-gated skips, 0 failures.
- Release build: succeeded.
- `MyMacX.xcodeproj/project.pbxproj`: `plutil -lint` passed.
- `git diff --check`: passed before commit.

H3-04, H3-05, and H3-06 are marked implementation-complete in the tracker. H3-01 and H3-07 remain human-gated. Gate G3 is still `IN PROGRESS` pending real global-hotkey/sleep-wake checks and the physical US/ABC/Vietnamese Telex input-source matrix.

## Important constraints

- Preserve existing Sprint 2 user changes and evidence.
- Do not add `build/` or derived data to Git.
- Do not claim Gate G3 complete until the human-only checks are performed and recorded.
- The AppShell runtime now constructs the persisted settings store/updater; persisted settings are the launch binding source. See H3-06 evidence for the composition details.

## Suggested skills

- `code-review` — review the pushed Sprint 2–3 commit or compare `dev` against its base.
- `tdd` — if implementing the next feature or adding integration coverage.
- `diagnosing-bugs` — if the human smoke checks expose runtime failures.
- `domain-modeling` — if updating project terminology, context, or ADRs.

## Likely next actions

1. Run/record the remaining H3-01 and H3-07 human gates.
2. Add the corresponding evidence to `docs/sprint-3/evidence/` and update the tracker/G3 status.
3. If G3 passes, plan Sprint 4 from the project plan while retaining the clean `dev` remote baseline.

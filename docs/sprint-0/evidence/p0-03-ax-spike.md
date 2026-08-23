# P0-03 — Accessibility window spike evidence

Status: `NOT RUN`

## Environment

- Tester/date:
- macOS build:
- Hardware:
- Prototype revision/checksum:
- Accessibility state before run:

## Safety

- [ ] Use a disposable, resizable test window with no unsaved work.
- [ ] Run `--inspect` before enabling both mutation flags.
- [ ] Keep the original frame visible and recoverable.
- [ ] Redact window/document titles and user content.

## Compatibility matrix

| App | Version | Focused window found | Position/size readable | Both settable | Apply/read-back | Observed AX error | Result |
|---|---|---|---|---|---|---|---|
| Finder | | | | | | | ☐ Pass ☐ Fail |
| Safari | | | | | | | ☐ Pass ☐ Fail |
| Terminal | | | | | | | ☐ Pass ☐ Fail |
| Xcode | | | | | | | ☐ Pass ☐ Fail |
| Chrome | | | | | | | ☐ Pass ☐ Fail |
| Electron app | | | | | | | ☐ Pass ☐ Fail |

## Edge cases

- [ ] Non-resizable window fails safely.
- [ ] App closes during inspection/mutation without crashing the PoC.
- [ ] Two windows in one process are distinguishable.
- [ ] Permission revoke/regrant is reflected without reinstall.

## Verdict

- P0-03: `☐ PASS ☐ CONDITIONAL ☐ FAIL`
- Unknowns/conditions:
- Reviewer/date:


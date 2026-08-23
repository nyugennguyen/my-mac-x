# P0-04 — Event Tap and Super Mode evidence

Status: `NOT RUN`

## Environment

- Tester/date:
- macOS build:
- Hardware/keyboard/input source:
- Prototype revision/checksum:

## Permission matrix

| Accessibility | Input Monitoring | Tap created | Key down/up observed | Permission UI observed | Result |
|---|---|---|---|---|---|
| Off | Off | | | | |
| On | Off | | | | |
| Off | On | | | | |
| On | On | | | | |

## State and safety cases

| Case | Expected | Actual | Result |
|---|---|---|---|
| Prefix then valid command | Executes once, returns Idle | | ☐ Pass ☐ Fail |
| Prefix then Escape | Cancels and releases input | | ☐ Pass ☐ Fail |
| Prefix then timeout | Returns Idle, next key unaffected | | ☐ Pass ☐ Fail |
| Invalid sequence | Matches selected pass-through policy | | ☐ Pass ☐ Fail |
| Tap disabled event | State resets before bounded re-enable | | ☐ Pass ☐ Fail |
| Modifier held across timeout | No sticky/lost modifier | | ☐ Pass ☐ Fail |

> The current Swift PoC is listen-only and cannot satisfy suppression cases. Implement a separately reviewed active-filter spike before marking this report complete.

## Privacy checks

- [ ] No typed characters or raw event stream persisted/logged.
- [ ] Test performed outside password/token/private-input contexts.
- [ ] Tap stopped completely after the process exits.

## Verdict

- P0-04: `☐ PASS ☐ CONDITIONAL ☐ FAIL`
- Unknowns/conditions:
- Reviewer/date:


# P0-04 — Event Tap and Super Mode evidence

Status: `PARTIAL PASS — LISTEN-ONLY DELIVERY AND STATE MACHINE VERIFIED`

## Environment

- Tester/date: Codex automated run with user authorization — 2026-08-24
- macOS build: macOS 26.5.2 (25F84)
- Hardware/keyboard/input source: Apple Silicon arm64; active input source not captured
- Prototype revision/checksum: workspace listen-only prototype, type-check passed

## Automated run result

- The listen-only session Event Tap was created outside the sandbox.
- The run loop stayed active for 15 seconds and stopped cleanly with `Control+C`.
- No user key event was observed during that manual window.
- The prototype did not suppress, rewrite or persist input.
- A second self-test posted one synthetic `Escape` down/up pair. The listen-only tap observed both events (`keyCode 53`) and exited successfully.
- Eight pure Super Mode cases passed: quick action, deep command, cancel, timeout, invalid-cancel, repeated prefix, disabled mode and invalid-keep-listening.

## Permission matrix

| Accessibility | Input Monitoring | Tap created | Key down/up observed | Permission UI observed | Result |
|---|---|---|---|---|---|
| On after user grant | Unknown | Yes | Synthetic key-down/up observed | No Input Monitoring prompt observed | Partial pass |
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

- P0-04: `☐ PASS ☒ CONDITIONAL ☐ FAIL`
- Unknowns/conditions: Input Monitoring matrix and active-filter suppression/pass-through remain untested; listen-only delivery and state logic are proven on this machine.
- Reviewer/date:

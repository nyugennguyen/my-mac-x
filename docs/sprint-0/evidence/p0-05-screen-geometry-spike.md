# P0-05 — Notch and multi-display geometry evidence

Status: `NOT RUN`

## Environment

- Tester/date:
- macOS build:
- Hardware/displays/scaling:
- Dock/menu bar configuration:
- Prototype revision/checksum:

## Geometry matrix

| Scenario | frame/visibleFrame valid | Safe/auxiliary areas | Trigger inside screen | Origin conversion | Result |
|---|---|---|---|---|---|
| Built-in display with Notch | | | | | ☐ Pass ☐ Fail |
| Display without Notch | | N/A/fallback | | | ☐ Pass ☐ Fail |
| External display left/origin negative | | | | | ☐ Pass ☐ Fail |
| Mixed scaling | | | | | ☐ Pass ☐ Fail |
| Dock left/right/bottom + auto-hide | | | | | ☐ Pass ☐ Fail |
| Display attach/detach | | | | | ☐ Pass ☐ Fail |

## Overlay/focus follow-up

- [ ] Non-activating panel remains non-key/non-main.
- [ ] Active app and Captured Window stay unchanged while chooser appears.
- [ ] Cross-display drag relocates or closes the overlay deterministically.
- [ ] Mouse-up outside a Layout Region makes no window mutation.

## Verdict

- P0-05: `☐ PASS ☐ CONDITIONAL ☐ FAIL`
- Unknowns/conditions:
- Reviewer/date:

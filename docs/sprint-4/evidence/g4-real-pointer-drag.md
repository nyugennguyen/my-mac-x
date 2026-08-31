# G4 — Real-pointer Notch Snap gate

Status: `PASS — TEMPORARY EXCEPTION`

Decision date: 2026-08-31
Decision owner: human tester

## Accepted evidence

- Input Monitoring and Accessibility permissions allowed the production pointer
  and Captured Window pipeline to run.
- Dragging an Eligible Window into the Notch Trigger presented the Layout Chooser.
- The chooser remained available while the pointer moved from the trigger into
  the chooser.
- Pointer hover selection worked across the nine default Layout Regions.
- Releasing the pointer performed the selected Snap.
- The human tester accepted the overlay behavior and directed Gate G4 to pass.

## Temporary exception

Physical keyboard and VoiceOver checks are deferred by explicit human decision.
They remain open N4-09 evidence and are **not** represented as passing in this
record. This exception must be revisited before a release gate that requires the
complete accessibility matrix.

## Evidence limits

No window titles, raw pointer stream, typed text, screenshots, or other sensitive
content were retained. Detailed machine, Display topology and macOS build metadata
were not recorded during this run, so this record does not independently establish
coverage beyond the hardware configuration used by the human tester.

## Gate result

`PASS` for the Sprint 4 pointer interaction scope, with keyboard and VoiceOver
explicitly deferred.

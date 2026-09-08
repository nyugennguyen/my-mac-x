# Gate G5 — Prefix-sequence beta

Status: `PASS — GO RECORDED 2026-09-07`

## Automated integration decision

S5-01 through S5-07 have automated evidence. The production path is composed as:

```text
CoreGraphics Event Tap
  → metadata-only synchronous input-safety decision
  → Super Mode reducer and session timeout
  → ordered transition stream
  → Super HUD
  → advanced action resolver/dispatcher
  → WindowActionPerforming.perform(_:)
```

The only suppressing keyboard callback returns nil only for a proven-owned event. Stale, stopped, disabled, invalid, timeout, repeat, key-up and flags-changed paths fail open as defined by S5-06. SOL safety and specification reviews report `APPROVE` with no unresolved automated input-state finding.

Built-in app-action IDs validate and reach the advanced dispatcher. `app.open-settings` uses a production Adapter; gap-toggle and profile-selection intentionally return typed `productionAdapterUnavailable` until Sprint 6.

## Automated evidence map

- [S5-01 — Event Tap lifecycle](s5-01-event-tap-lifecycle.md)
- [S5-02 — Super Mode state machine](s5-02-super-mode-state-machine.md)
- [S5-03 — Prefix/sequence configuration](s5-03-prefix-sequence-config.md)
- [S5-04 — Super HUD](s5-04-super-hud.md)
- [S5-05 — Advanced actions](s5-05-advanced-actions.md)
- [S5-06 — Input safety policy](s5-06-input-safety-policy.md)
- [S5-07 — Timeout and rapid-input tests](s5-07-timeout-rapid-input-tests.md)

Final focused integration command on 2026-09-03:

```bash
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX -destination 'platform=macOS' -only-testing:MyMacXTests/EventTapManagerTests -only-testing:MyMacXTests/SuperModeInputSafetyControllerTests -only-testing:MyMacXTests/SuperModeConfigurationTests -only-testing:MyMacXTests/SuperModeAdvancedActionsTests -only-testing:MyMacXTests/SuperHUDCoordinatorTests -only-testing:MyMacXTests/AppLifecycleCoordinatorTests
```

Final complete-suite result on 2026-09-04: `TEST SUCCEEDED`; 351 total tests, 349 passed, 0 failures and 2 documented skips. The delayed Pointer Drag replay scenarios also passed 20 iterations each (40 executions) after fixing ordered replay, long-lived composition retain cycles and the competing-consumer test harness.

## Human check sequence

Use a disposable text document containing no sensitive data. Do not paste its contents into evidence; record only whether events were preserved.

### H5-01 — Permission lifecycle

1. Start with Input Monitoring and Accessibility denied. Open Super Mode Settings, confirm it explains why Input Monitoring is needed, then choose **Enable Input Monitoring**.
2. Launch My Mac X and type normally; verify no input is swallowed and Window Actions fail closed.
3. Grant both permissions using System Settings, relaunch if macOS requires it, and verify Super Mode becomes available.
4. Revoke each permission separately while the app is running, then relaunch; verify normal typing remains intact and recovery is explicit.
5. Record macOS version, permission state transitions and pass/fail.

### H5-02 — Prefix and exit-path matrix

For each built-in and external keyboard:

1. Enter the configured Prefix; verify the HUD appears without moving focus.
2. Run one-level and two-level registered sequences; verify the expected Window Action executes once.
3. While armed and while in a submenu, test an invalid printable key. The invalid key must appear normally, Super Mode must cancel, and the next character must also appear.
4. Test Escape while armed and in a submenu. Escape must cancel without reaching the frontmost app; the next character must appear.
5. Let the timeout expire, then type immediately at and after the boundary; no character may be lost.
6. Hold the Prefix and registered sequence keys to trigger repeat. Repeats must not arm, advance or execute additional actions.
7. Hold and release Command, Option, Control and Shift across cancellation, timeout and action completion; no modifier may remain sticky.
8. Send rapid one- and two-level sequences repeatedly; each completed sequence must execute at most once.

### H5-03 — Input sources and privacy

Repeat Prefix, invalid-key, timeout, rapid-input and modifier-release cases with:

- US/ABC;
- Vietnamese Telex;
- at least one non-Latin input source.

Inspect available app diagnostics. Record only that no typed text, characters or raw key stream appeared; never copy the typed sample into evidence.

### H5-04 — Event Tap recovery

1. With Super Mode active, sleep and wake the Mac; verify Prefix handling recovers and a normal key is not swallowed.
2. Perform a fast-user-switch round trip; verify recovery.
3. Repeat launch/quit and permission recovery several times; confirm behavior indicates only one effective Event Tap—no duplicate action or duplicate swallowed key.

### H5-05 — HUD and accessibility

1. Keep focus in another application and arm Super Mode; confirm the HUD never becomes key/main and typing focus stays in the original application.
2. Observe waiting, submenu, pending, success, error and timeout states.
3. Enable VoiceOver and verify state labels are perceivable without duplicate or misleading announcements.
4. Check Reduce Motion, Reduce Transparency and Increase Contrast appearances.

### H5-06 — Window Actions and Displays

1. With an eligible Window focused, execute Restore and left-edge cycle through Prefix sequences.
2. On a physical multi-Display setup, execute move-to-next and move-to-previous Display and verify the captured Window—not a later-focused Window—is moved.
3. Exercise unavailable/rejected cases and verify typed error feedback rather than false success.
4. Bind and invoke settings and verify the reusable Settings window opens. Bind gap-toggle and profile-selection IDs and verify explicit unavailable feedback and no Window Action mutation; those Adapters remain Sprint 6 scope.

## Human record

- Date: 2026-09-07.
- Tester/sign-off: project owner.
- Reported result: Super Mode is operational and the manual testing sequence is complete.
- Decision: `GO`; Gate G5 approved.
- Hardware, input-source and topology details were not supplied in the approval message and are therefore not inferred here.

Gate G5 is `PASS`. This approval does not automatically close Sprint 4's separate temporary exceptions; update Sprint 4 evidence independently if the same run is accepted there.

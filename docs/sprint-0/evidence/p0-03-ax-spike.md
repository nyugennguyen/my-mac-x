# P0-03 — Accessibility window spike evidence

Status: `PASS — 6/6 REQUIRED APPS VERIFIED ON THIS MAC`

## Environment

- Tester/date: Codex automated run with user authorization — 2026-08-24
- macOS build: macOS 26.5.2 (25F84)
- Hardware: Apple Silicon arm64
- Xcode/toolchain: Xcode 26.6 (17F113), active developer directory `/Applications/Xcode.app/Contents/Developer`
- Prototype revision/checksum: workspace prototype, type-check passed
- Accessibility state before run: initially not trusted; user granted access during the run

## Automated preflight result

Command: read-only `--inspect`; mutation flags were not used.

Initial result: `Accessibility permission is not granted.` System Settings was opened at Privacy & Security → Accessibility and the user granted access. The system-wide `AXFocusedApplication` lookup then returned `kAXErrorCannotComplete`; the public frontmost-process PID fallback succeeded consistently.

The first mutation exposed a restore-order bug: restoring size while the window was still offset caused macOS to clamp the frame by 24 pt. The prototype was changed to restore `position → size`, the test window was explicitly recovered to `(0,33,1470,923)`, and the full mutation/read-back/restore test then passed. No tested window was left resized.

## Safety

- [x] Mutate frame geometry only; do not touch document/app content.
- [x] Run `--inspect` before enabling both mutation flags.
- [x] Capture the original frame and verify the recovery frame by read-back.
- [x] Redact window/document titles and user content.

## Compatibility matrix

| App | Version | Focused window found | Position/size readable | Both settable | Apply/read-back | Observed AX error | Result |
|---|---|---|---|---|---|---|---|
| Finder | macOS 26.5.2 | Yes via fallback | Yes | Yes | Exact; restore exact after ordering fix | Initial system-wide lookup `-25204` | ☒ Pass ☐ Fail |
| Safari | system version | Yes via fallback | Yes | Yes | Exact; restore exact | System-wide lookup `-25204` | ☒ Pass ☐ Fail |
| Terminal | system version | Yes via fallback | Yes | Yes | Exact; restore exact | System-wide lookup `-25204` | ☒ Pass ☐ Fail |
| Xcode | 26.6 (17F113) | Yes via fallback | Yes | Yes | Exact; restore exact | System-wide lookup `-25204` | ☒ Pass ☐ Fail |
| Chrome | installed version | Yes via fallback | Yes | Yes | Exact; restore exact | System-wide lookup `-25204` | ☒ Pass ☐ Fail |
| OpenChamber (Electron) | 1.16.2 | Yes via fallback | Yes | Yes | Exact; restore exact | System-wide lookup `-25204` | ☒ Pass ☐ Fail |

For Xcode and OpenChamber, the original frame was `(0,33,1470,923)`, the requested test frame was `(24,57,1422,875)`, read-back matched the request exactly, and the final frame matched the original exactly. OpenChamber's bundle declares `NSPrincipalClass = AtomApplication` and `ElectronAsarIntegrity`, confirming that it is the representative Electron app for this matrix.

## Failure taxonomy carried into production design

- `permissionDenied`: Accessibility trust is absent or revoked.
- `focusedWindowUnavailable`: neither the system-wide focused-app lookup nor the frontmost-process fallback yields an eligible window.
- `unsupportedCapability`: position or size is not settable for the captured window.
- `targetGone`: the app/window disappears during mutation or read-back.
- `readBackMismatch`: the resulting frame differs from the requested frame after system constraints are applied.
- `restoreFailed`: best-effort recovery cannot reproduce the captured frame; surface this prominently and never report the action as successful.

## Edge cases

- [ ] Non-resizable window fails safely.
- [ ] App closes during inspection/mutation without crashing the PoC.
- [ ] Two windows in one process are distinguishable.
- [ ] Permission revoke/regrant is reflected without reinstall.

## Verdict

- P0-03 technical acceptance: `☒ PASS ☐ CONDITIONAL ☐ FAIL`
- Remaining non-blocking coverage: special-window, close-during-mutation, two-window identity and permission revoke/regrant cases remain open for production adapter tests.
- Reviewer/date: User approved technical acceptance and Sprint transition — 2026-08-24.

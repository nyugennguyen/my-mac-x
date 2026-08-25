# F1-03 — Accessibility permission evidence

Status: `AUTOMATED + CURRENT-MACHINE RUNTIME PASS — CLEAN-PROFILE TCC MATRIX PENDING`

## Delivered behavior

- Fresh untrusted install reports `notRequested`; persisted onboarding/request history distinguishes later `denied`.
- Runtime refresh supports `notRequested/denied → granted → revoked` without relaunch.
- System trust is read through public `AXIsProcessTrusted()` without automatically prompting at launch.
- Request/grant history persists locally through `UserDefaults`; AX trust alone is never treated as denial history.
- Production opens only the general System Settings app through documented `NSWorkspace` APIs; the undocumented preference-pane URL was removed.
- The application composition refreshes permission state on each app activation, with no polling.

## Verification on 2026-08-24

- PermissionKit XCTest: 8/8 pass.
- AppShell permission-activation test: pass.
- Current full integrated suite: 45/45 pass.
- Production source compiled under Swift 6 complete strict concurrency.
- Current-machine production harness: initial `granted`, refresh `granted`, general System Settings open returned `true`; the app opened and was then closed after verification.

## Human checks remaining

- Observe fresh `notRequested`, directed-but-untrusted `denied`, revoke and regrant on a clean test profile; do not revoke Codex's active permission during an agent session.
- Confirm onboarding includes manual navigation instructions because public API does not expose a documented direct Accessibility-pane route.
- Confirm UI copy and onboarding timing when the permission surface is implemented.

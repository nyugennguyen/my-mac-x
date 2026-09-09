# R8-02 — Permission/TCC lifecycle matrix

Date: 2026-09-09

## Scope and acceptance

R8-02 requires evidence for fresh install, denial, grant, revocation, and update. The deterministic
rows below exercise the public Permission Module Interface. TCC database manipulation, granting
permissions, and preserving trust across a signed-app update remain human-only operations and are
not represented as passed by unit tests.

Apple documents that Accessibility trust is queried with `AXIsProcessTrusted` (or
`AXIsProcessTrustedWithOptions`) and that listening event access is preflighted/requested with
`CGPreflightListenEventAccess` / `CGRequestListenEventAccess`:

- [AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrusted)
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459138-axisprocesstrustedwithoptions)
- [CGPreflightListenEventAccess](https://developer.apple.com/documentation/coregraphics/3180988-cgpreflightlisteneventaccess)
- [CGRequestListenEventAccess](https://developer.apple.com/documentation/coregraphics/3180989-cgrequestlisteneventaccess)

## Evidence matrix

| Lifecycle | Expected product state | Automated evidence | Human TCC evidence | Status |
|---|---|---|---|---|
| Fresh, not trusted | `.notRequested`; no prompt is triggered by refresh | `testFreshUntrustedInstallIsNotRequested` | Not run | Automated pass; human pending |
| User directed, still untrusted/denied | `.denied`; directed history persists | `testDirectingUserToGrantPermissionChangesUntrustedStateToDenied`, `testDirectedHistoryPersistsAcrossManagerRecreation`, `testRefreshRemainsDeniedUntilTrustHasBeenGranted` | Not run | Automated pass; human pending |
| Grant | Refresh changes state to `.granted` and records prior grant | `testRefreshReportsGrantAfterUserWasDirected` | Not run | Automated pass; human pending |
| Revoke while running | Next refresh changes `.granted` to `.revoked` | `testRefreshReportsRevokedAfterARecordedGrantIsLost` | Not run | Automated pass; human pending |
| Relaunch after revoke | Persisted grant history produces `.revoked` | `testGrantedHistoryReportsRevokedAfterManagerRecreation` | Not run | Automated pass; human pending |
| App update, identity unchanged | Permission history remains meaningful and TCC trust should remain bound to stable signed identity | Manager recreation covers local history only | Must install signed old build, grant, replace with signed update using the same bundle/signing identity, relaunch, and verify both Accessibility and Input Monitoring | Pending human signed-update run |

## Human protocol (not executed)

Use a disposable macOS user or test Mac. Record OS version, app version, bundle identifier,
Team ID/designated requirement, timestamps, and screenshots with unrelated applications hidden.

1. Reset only My Mac X's Accessibility and Input Monitoring entries using System Settings (or an
   approved test-machine TCC reset), then launch. Confirm the app explains purpose before directing
   the user to Settings and does not claim a system prompt was shown.
2. Decline/leave both permissions disabled. Relaunch and confirm degraded controls and `.denied`.
3. Grant Accessibility, return to the running app, refresh/activate it, and verify window actions
   become available without restart. Grant Input Monitoring only when enabling Super Mode and
   verify the Event Tap becomes active.
4. Revoke Accessibility while the app runs. Confirm the next action fails closed and UI reports
   revoked. Revoke Input Monitoring and confirm input passes through and the tap becomes unavailable.
5. Install the next signed build over the prior build without changing bundle identifier or signing
   identity. Confirm settings/history are preserved and record whether each TCC grant survives.
6. If either grant does not survive update, capture the old/new designated requirements and treat
   this as an R8-05/R8-07 blocker; do not repeatedly prompt.

## Automated command

```sh
xcodebuild test -project MyMacX.xcodeproj -scheme MyMacX \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MyMacXTests/AccessibilityPermissionManagerTests
```

The focused command is rerun in the R8-02/R8-03/R8-04 combined verification recorded in
`r8-04-soak-performance-core.md`.


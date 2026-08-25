# F1-02 — AppShell lifecycle evidence

Status: `PASS`

## Delivered behavior

- `ApplicationDelegate` starts one `AppLifecycleCoordinator` during `applicationWillFinishLaunching`.
- The coordinator applies `.accessory` activation policy and installs one `NSStatusItem`.
- Repeated `start()` calls are idempotent.
- Generated `Info.plist` uses `LSUIElement = true` to avoid a Dock icon from process launch.
- AppShell never calls `activate`, `orderFront` or `makeKey`.

## Verification on 2026-08-24

- AppShell XCTest: 2/2 pass.
- Current full integrated suite after ScreenKit integration: 45/45 pass.
- Cold launch: one `dev.mymacx.app` process, activation policy raw value `1` (`accessory`), `active=false`; frontmost app remained `com.openai.codex`.
- Two explicit `open` requests: still one process, confirming LaunchServices single-instance behavior.
- The exact Debug process opened for runtime checks was terminated after verification.

## Known behavior

A second explicit `open` request activates the already-running accessory app. This is an intentional external reopen event rather than cold-launch focus theft; no window is ordered front. Revisit the reopen policy if usability testing expects repeated Finder/CLI launches to preserve the previous frontmost application.

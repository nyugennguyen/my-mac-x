# G6 public-beta gate

Automated result on 2026-09-08: 419 tests passed, 0 failed, and 2 hardware-dependent tests were skipped. The Xcode project builds, its project file validates, and configuration backup/restore is composed through the production runtime.

Gate status: **conditional — human accessibility verification pending**.

Before marking G6 passed, verify on a real session:

- Navigate every Settings section, Quick Actions, the Hotkey recorder, and the Super Mode command tree using only the keyboard.
- With VoiceOver enabled, confirm controls have meaningful names, state/value announcements, and a predictable focus order.
- Check light/dark appearance and Increase Contrast for readable text, selection, error, and disabled states.
- Enable Reduce Motion and confirm preview/HUD changes avoid unnecessary animation while remaining understandable.

U6-11 also requires a live run that records idle CPU, event-to-action-start p95, preview-calculation p95, memory growth after 500 actions, and observer growth after 100 topology changes against `PerformanceBudgetPolicy.publicBeta`.

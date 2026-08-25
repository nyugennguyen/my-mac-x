# Sprint 1 — Foundation và quyền hệ thống

Sprint 1 bắt đầu ngày 2026-08-24 theo phê duyệt của user. Sprint được mở theo hướng có kiểm soát: F1-01 và các task chỉ phụ thuộc bằng chứng đã đạt có thể chạy; P0-04/P0-05 tiếp tục là dependency bắt buộc cho input suppression, overlay và screen geometry production.

## Test seams đã được phê duyệt

- Seam production cấp cao: `WindowActionPerforming.perform(_:)`, theo [ADR-0003](../adr/0003-intent-driven-window-action-module.md) và [interface contract](../design/window-action-interface.md).
- System boundaries có production/test Adapter: Accessibility, screen topology, action catalog, window history và monotonic time.
- F1-01 chỉ kiểm tra cấu trúc build và behavior công khai tối thiểu của domain value; không test implementation detail của app shell.

## Tracker

| ID | Deliverable | Owner / model | Agent | Trạng thái | Dependency | Evidence / exit gate |
|---|---|---|---|---|---|---|
| F1-01 | Xcode project, configs, folders/modules, test targets | Foundation / GPT-5.6 Terra M | root | DONE | P0-06 | [Build evidence](evidence/f1-01-build.md): Debug/Release build và unit tests pass; independent review không có blocker |
| F1-02 | Menu bar lifecycle, accessory policy, single instance | AppShell / GPT-5.6 Terra M | `f1_02_appshell` | DONE | F1-01 | [Evidence](evidence/f1-02-app-shell.md): unit 2/2; cold launch accessory/no focus; double-open giữ một process |
| F1-03 | `AccessibilityPermissionManager` | PermissionKit / GPT-5.6 Sol H | `f1_03_permission` + `f1_03_hardening` | REVIEW | P0-03, F1-01 | [Evidence](evidence/f1-03-accessibility-permission.md): 8/8 + real granted/refresh/settings-open pass; chờ clean-profile human TCC matrix |
| F1-04 | `FocusedWindowProvider` + `WindowCapabilities` | AXWindowKit / GPT-5.6 Sol H | `f1_04_axwindow` + `f1_04_hardening` | DONE | P0-03 | [Evidence](evidence/f1-04-focused-window.md): 17/17 + production harness pass; `.unavailable` là documented Full Screen limitation được chấp nhận |
| F1-05 | `ScreenGeometryService` | ScreenKit / GPT-5.6 Sol H | `f1_05_screenkit` + `f1_05_core_review` | DONE | P0-05 | [Evidence](evidence/f1-05-screen-geometry.md): 12/12 + live HKC/non-Notch + built-in Notch/mixed-scale pass; independent re-review không còn P0/P1/P2 |
| F1-06 | Privacy-safe logging và error taxonomy | DiagnosticsKit / GPT-5.6 Terra M | `f1_06_diagnostics` + `f1_06_hardening` | DONE | F1-01 | [Evidence](evidence/f1-06-diagnostics.md): exhaustive typed mappings, privacy allowlist và concurrent writer test pass |
| F1-07 | AX/screen fakes và geometry fixtures | Test Support / GPT-5.6 Luna M | `f1_07_test_support` | DONE | F1-04…F1-05 | [Evidence](evidence/f1-07-test-support.md): AX/screen Adapters và geometry fixtures không phụ thuộc app/Display thật |
| F1-08 | CI skeleton | Foundation / GPT-5.6 Terra M | `f1_08_ci` | REVIEW | F1-01 | [Evidence](evidence/f1-08-ci.md): workflow validated locally; chờ hosted PR run đầu tiên |

## Gate G1

`PENDING` — AppShell, PermissionKit, AXWindowKit, ScreenKit, test support và DiagnosticsKit đã tích hợp; còn clean-profile human TCC sign-off cho F1-03 và hosted F1-08 run.

## Current integrated verification

- Debug build: pass.
- Release build: pass.
- XCTest: the Sprint 1 baseline passed 45/45; the current integrated suite after Sprint 2
  batch 1 passes 78/78 on the current Apple Silicon Mac.
- CI workflow YAML: parses locally; hosted run pending.
- Runtime AppShell: accessory cold launch does not take focus; test process cleaned up.

## Môi trường

- macOS 26.5.2 (25F84), Apple Silicon.
- Xcode 26.6 (17F113), active developer directory `/Applications/Xcode.app/Contents/Developer`.
- Minimum deployment target: macOS 14 theo default đã duyệt trong Project Plan.
- Bundle identifier dùng provisional value `dev.mymacx.app` cho local build; chốt reverse-DNS identifier trước signing/notarization.

## Multi-agent ownership

- Root là integrator duy nhất cho `MyMacX.xcodeproj/project.pbxproj`, shared scheme, build config và shared composition.
- Mỗi sub-agent chỉ sửa module và test folder được giao; không hai agent cùng sở hữu một file.
- Mỗi kết quả phải kèm changed files, test result, assumptions và known gaps trước khi root tích hợp.

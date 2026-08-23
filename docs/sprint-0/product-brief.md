# Product Brief — Sprint 0

## 1. Product statement

My Mac X là tiện ích menu bar native cho macOS, giúp người dùng đặt kích thước và vị trí cửa sổ nhanh bằng thao tác kéo lên Notch/top-center, global hotkey hoặc chuỗi lệnh Super Mode. Mọi interaction gọi chung một action/layout engine và phải có đường Undo/Restore an toàn.

Phần vision, persona và success metrics đầy đủ nằm trong [Project Plan — Product vision](../../my-mac-x_projectplan.md#2-product-vision). Brief này chốt phần cần dùng để ra quyết định Sprint 0.

## 2. Người dùng và job-to-be-done

| Persona ưu tiên | Job-to-be-done | Tín hiệu thành công ban đầu |
|---|---|---|
| Knowledge worker | Chia cửa sổ đang dùng thành vùng làm việc quen thuộc mà không mất ngữ cảnh | Thực hiện được trong một drag hoặc một hotkey; có Undo |
| Developer/power user | Điều khiển window action sâu hoàn toàn bằng bàn phím | Prefix → command có HUD, timeout/cancel không làm mất input |
| Người dùng phổ thông | Hiểu và chọn layout bằng preview trực quan | Notch/top-center chooser không lấy focus, drop mới áp dụng |
| Người dùng nhiều màn hình | Chuyển cửa sổ giữa display vật lý an toàn | Cửa sổ không rơi khỏi visible frame; behavior dự đoán được |

## 3. Thuật ngữ chuẩn

| Thuật ngữ | Định nghĩa dùng trong sản phẩm | Không dùng để chỉ |
|---|---|---|
| **Maximize** | Đặt cửa sổ vào `NSScreen.visibleFrame`, vẫn thuộc Space hiện tại | Native Full Screen |
| **Native Full Screen** | Action bất đồng bộ của macOS, có thể tạo/chuyển Space | Maximize |
| **Display** | Màn hình vật lý do macOS báo cáo | Desktop/Space |
| **Desktop/Space** | Không gian làm việc ảo của Mission Control | Màn hình vật lý |
| **Layout** | Vùng đích chuẩn hóa trong usable/visible frame | Workspace nhiều app |
| **Notch trigger** | Vùng kích hoạt ở top-center dựa trên geometry/safe area | Tọa độ notch hard-code |
| **Super Mode** | Prefix mở state machine nhận chuỗi command trong thời gian hữu hạn | Ghi lại bàn phím liên tục |
| **Restore** | Trả window về frame ổn định đã lưu trước layout action | Undo toàn hệ thống |
| **Undo** | Hoàn tác action window gần nhất theo identity đủ phân biệt | Dựa riêng vào process ID |

## 4. MVP contract

### Must ship trong technical MVP

- Accessibility onboarding/health state và focused-window capability.
- Maximize, halves, quarters, top/bottom; clamp theo `visibleFrame`.
- Undo/Restore cho từng cửa sổ.
- Move next/previous **physical display**.
- Notch/top-center chooser, preview, drop/cancel.
- Custom global hotkeys, recorder và conflict detection.
- Settings tối thiểu để cấu hình các tính năng trên.
- Privacy-safe diagnostics đủ để xác định permission/capability failure.

### v1, không phải điều kiện của technical MVP

- Super Mode + HUD hoàn chỉnh.
- Thirds/two-thirds/center/increments, layout editor, app rules, display profiles.
- Import/export, schema migration, launch-at-login hardening, Native Full Screen advanced action.
- Release signing/notarization/update/rollback gate.

### Ngoài v1

- Tạo/xóa/đổi tên Space hoặc chuyển tùy ý external-app window sang Space N.
- Private SkyLight APIs trong production.
- Stage Manager set management đầy đủ, multi-window tiling, workspace restore.
- Account, cloud sync, telemetry mặc định, rules theo title/nội dung document.

Danh mục feature/release đầy đủ: [Project Plan — Feature matrix](../../my-mac-x_projectplan.md#31-feature-matrix).

## 5. Product invariants

1. Không action nào được để cửa sổ hoàn toàn ngoài vùng nhìn thấy.
2. Preview không mutate cửa sổ; chỉ drop/confirm/action rõ ràng mới mutate.
3. Overlay/HUD không lấy focus từ app/cửa sổ đích.
4. Mọi input capture có timeout, cancel và cleanup; không capture ngoài trạng thái armed.
5. Không lưu/log nội dung phím, window title, document content, clipboard hoặc screenshot.
6. Chỉ dùng public API trong production target.
7. Unsupported window/permission loss phải fail closed và có feedback; không retry vô hạn.
8. Mouse, hotkey, menu bar và Super Mode cùng gọi một Window Action Interface.

## 6. Success measures áp dụng cho Sprint 0

| Measure | Mục tiêu | Cách chứng minh Sprint 0 |
|---|---:|---|
| AX feasibility | Focus/move/resize trên 6 app đại diện | P0-03 manual matrix + read-back |
| Geometry feasibility | Sai lệch target/read-back ≤ 1 logical point, trừ minimum-size constraint được ghi nhận | P0-05 fixtures + máy thật |
| Overlay focus safety | Không thay đổi active app/key window | P0-05 focus trace/manual report |
| Input safety | Không mất phím/modifier ở success/cancel/timeout/tap disabled | P0-04 scripted + manual cases |
| Scope safety | Spaces N và private API không đi vào production v1 | Product/architecture sign-off |
| UX coverage | 20 surfaces và primary flows có owner/sign-off | UX checklist |

## 7. Quyết định Sprint 0

| ID | Quyết định | Default đề xuất | Người duyệt | Hạn | Trạng thái |
|---|---|---|---|---|---|
| D-01 | Minimum macOS | macOS 14+ | Product + Tech | 2026-08-23 | Approved default; verify SDK/hardware in spikes |
| D-02 | Import/export | v1, không thuộc technical MVP | Product | 2026-08-23 | Approved |
| D-03 | Update bản đầu | Manual download/check version cho beta; đánh giá updater trước v1 | Product + Release | 2026-08-23 | Approved default |
| D-04 | Super prefix | `⌃Space`, configurable | Product + UX | 2026-08-23 | Approved default; test conflicts |
| D-05 | Notch defaults | Dwell/gap/layout set quyết định sau usability PoC | UX | `[TBD]` | ☐ |
| D-06 | Diagnostics | Offline/local; user chủ động copy report đã redaction | Security + Product | 2026-08-23 | Approved default; security review pending |
| D-07 | Display identity | Stable display ID + fallback cần PoC reconnect | Tech | `[TBD]` | ☐ |
| D-08 | Native Full Screen | Advanced action, không nằm default chooser | Product | 2026-08-23 | Approved |
| D-09 | Beta matrix | App list theo P0-03; size/version TBD | QA + Product | `[TBD]` | ☐ |
| D-10 | Brand/bundle/Developer ID owner | `[TBD]` | Sponsor | `[TBD]` | ☐ |

## 8. Factual unknowns cần PoC/research

| ID | Unknown thực tế | Mức ảnh hưởng | Cách đóng | Owner / liên quan |
|---|---|---|---|---|
| U-01 | Với target macOS/hardware thực tế, Event Tap nào cần Accessibility và trường hợp nào cần Input Monitoring? | Blocker cho permission UX/distribution | P0-04 trên máy sạch, từng permission state | Input / P0-04 |
| U-02 | `AXPosition`/`AXSize` set/read-back khác nhau thế nào giữa 6 app và custom-titlebar window? | Blocker cho Window Core | P0-03 compatibility matrix | Core / P0-03 |
| U-03 | Coordinate system AX/AppKit/CoreGraphics và safe-area thay đổi ra sao với origin âm, mixed scaling, menu bar/Dock auto-hide? | Blocker cho geometry | P0-05 fixtures + hardware | Geometry / P0-05 |
| U-04 | Non-activating overlay có giữ focus ổn định trong drag xuyên màn hình/Space và khi display disconnect không? | High | P0-05 lifecycle tests | Overlay / P0-05 |
| U-05 | Accessibility + Event Tap + direct Developer ID distribution cần entitlements/hardened-runtime exceptions chính xác nào? | Blocker cho release policy | Apple-doc research + signed PoC | Security/Release / P0-07 |
| U-06 | Có window identity công khai đủ ổn định cho hai window cùng process và app đóng/reopen không? | High | P0-03 prototype/history research | Core |
| U-07 | Stable display identifier tồn tại qua reconnect/dock/reboot ở mức nào? | Medium | reconnect PoC trên ≥2 display setup | Geometry |
| U-08 | UX dwell duration và hit zone nào ít kích hoạt nhầm nhất? | Medium | usability test, không suy ra từ Windows 11 | UX / P0-08 |

## 9. Sign-off

- Product owner: `Project owner` — `Approved via Project Plan` — ngày `2026-08-23`
- Tech lead: `[TBD]` — `☐ Feasible ☐ Conditional ☐ Not feasible` — ngày `[TBD]`
- Ghi chú/điều kiện: `[TBD]`

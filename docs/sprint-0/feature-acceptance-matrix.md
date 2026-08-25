# Feature Acceptance Matrix — P0

Matrix này cụ thể hóa các feature ưu tiên P0 trong [Project Plan — Feature matrix](../../my-mac-x_projectplan.md#31-feature-matrix). `Release` giữ nguyên ranh giới MVP/v1; priority P0 không đồng nghĩa mọi feature đều phải vào technical MVP.

## Quy tắc nghiệm thu

- Mỗi AC có thể trả lời Pass/Fail, không dùng từ chủ quan như “mượt” nếu không có ngưỡng.
- Evidence phải trỏ tới test/report/build cụ thể; ô trống nghĩa là chưa đạt.
- Sai khác do minimum window size chỉ được chấp nhận nếu capability/read-back phát hiện và UI báo constrained target.
- Test yêu cầu thao tác hệ thống hoặc hardware được đánh dấu `Manual`; phần logic còn lại phải ưu tiên automation.

## Matrix

| Feature | Release | Acceptance criteria đo được | Verify | Evidence / owner | Status |
|---|---|---|---|---|---|
| SYS-01 Permission | MVP | Trạng thái not-requested/denied/granted/revoked cập nhật runtime; mở System Settings bằng public API kèm hướng dẫn điều hướng; action bị chặn an toàn khi thiếu quyền | Unit state + Manual máy sạch | [F1-03 evidence](../sprint-1/evidence/f1-03-accessibility-permission.md) / Core | REVIEW |
| SYS-02 Window Core | MVP | Lấy đúng focused standard window; phân biệt movable/resizable/minimized và Full Screen knowledge (`unavailable` khi public signal không tồn tại); 6 app P0-03 pass hoặc có unsupported reason xác định | Adapter test + Manual matrix | [P0-03](evidence/p0-03-ax-spike.md), [F1-04](../sprint-1/evidence/f1-04-focused-window.md) / Core | PASS |
| SYS-03 Layout cơ bản | MVP | Maximize/halves/quarters/top-bottom nằm trong `visibleFrame`; target math ≤1 logical point trên fixtures origin âm/scaling | Unit/property + Manual read-back | `[TBD]` / Geometry | TODO |
| SYS-05 History | MVP | Hai cửa sổ cùng process không dùng nhầm history; Undo/Restore trả frame hợp lệ; closed window fail an toàn | Unit + Integration | `[TBD]` / Core | TODO |
| SYS-06 Physical display | MVP | Next/previous display deterministic; cửa sổ còn nhìn thấy; single-display là no-op có feedback; reconnect không crash | Property + Manual multi-display | `[TBD]` / Geometry | TODO |
| SYS-07 Notch Snap | MVP | Dwell mở chooser; hover/preview không mutate; drop áp dụng; Esc/kéo ra hủy; overlay không key/main/focus | UI/state + Manual drag | P0-05 + UX evidence / Overlay | TODO |
| SYS-08 Non-Notch fallback | MVP | Top-center trigger cung cấp cùng action/cancel semantics; hit zone không phụ thuộc tọa độ hard-code | Unit geometry + Manual non-Notch | P0-05 / Overlay | TODO |
| SYS-09 Custom hotkeys | MVP | Register/unregister/replace runtime; binding giữ qua restart; action bắt đầu <100 ms p95 trên máy support thấp nhất | Integration + performance | P0-04, `[TBD]` / Input | TODO |
| SYS-10 Recorder/conflict | MVP | Không lưu duplicate/invalid binding; conflict dialog có replace/choose/cancel; recorder không ghi nội dung ngoài chord đang record | Unit/UI + privacy review | `[TBD]` / Input + UX | TODO |
| SYS-11 Super Mode | v1 | Prefix arm state machine; sequence 1–2 cấp; Esc/timeout/invalid luôn cleanup; không capture ngoài armed state | State-machine + P0-04 Manual | `[TBD]` / Input | TODO |
| SYS-12 Super HUD | v1 | HUD phản ánh waiting/submenu/success/invalid/timeout; không lấy focus; keyboard-only path đầy đủ | UI/snapshot + Manual focus | UX evidence / Overlay | TODO |
| SYS-16 Settings | MVP | General/Snapping/Hotkeys có states active/paused/permission-missing; thay đổi quan trọng có hiệu lực runtime và persist | UI + integration/relaunch | `[TBD]` / UI | TODO |
| SYS-21 Accessibility UX | v1 | Settings/chooser/HUD có keyboard path; VoiceOver labels; contrast đạt WCAG AA cho text; Reduce Motion loại animation không thiết yếu | Accessibility audit + Manual | UX evidence / QA | TODO |
| SYS-22 Release | v1 | Release signed/notarized; Gatekeeper pass máy sạch; entitlements khớp threat model; không private API; rollback artifact sẵn sàng | CI + Manual clean Mac | `[TBD]` / Release + Security | TODO |

## Cross-feature scenarios bắt buộc

| ID | Scenario | Expected | Method | Status |
|---|---|---|---|---|
| CF-01 | Quyền Accessibility bị thu hồi ngay trước action | Không mutate/retry loop; hiện permission-lost feedback; phục hồi không cần restart | Manual + integration fake | ☐ |
| CF-02 | App đích đóng/treo giữa size và position | Pipeline bounded timeout; không crash; error được redaction | Fault injection + Manual | ☐ |
| CF-03 | Display bị rút khi chooser đang mở | Overlay đóng hoặc relocate an toàn; window không off-screen | Manual hardware | ☐ |
| CF-04 | Hai window cùng app, action xen kẽ | Focus target và Undo không lẫn nhau | Integration + Manual | ☐ |
| CF-05 | Super Mode timeout khi modifier vẫn đang giữ | Event flow trở lại bình thường, không sticky/lost modifier | P0-04 scripted + Manual | ☐ |
| CF-06 | Window không resizable/minimum-size lớn hơn target | Không cố retry vô hạn; preview/final feedback constrained/unsupported | Adapter fake + Manual | ☐ |
| CF-07 | Stage Manager on/off | Không crash/mất window; unsupported behavior được ghi trong limitation | Manual research | ☐ |
| CF-08 | Sleep/wake hoặc fast user switch | Không duplicate tap/observer; hotkeys phục hồi hoặc báo degraded | Soak/manual | ☐ |

## Definition of Accepted

Một feature chỉ chuyển `DONE` khi:

- [ ] Tất cả AC của dòng pass trên minimum supported macOS.
- [ ] Có test tự động hoặc lý do/manual report rõ ràng.
- [ ] Permission loss, unsupported và error path đã test.
- [ ] Không log dữ liệu cấm theo threat model.
- [ ] Evidence có commit/build, environment và người chạy.
- [ ] Review độc lập; core/input/security phải có SOL-H trở lên review.

## Open validation items

- `[PoC: P0-03]` AX behavior trên từng app/version chưa được coi là fact cho đến khi test máy thật.
- `[PoC: P0-04]` Permission behavior của Event Tap/Input Monitoring chưa được chốt.
- `[PoC: P0-05]` Ngưỡng ≤1 point và focus safety cần kiểm tra trên hardware có Notch/mixed scaling.
- `[Research]` VoiceOver behavior của non-activating overlay cần prototype; nếu không thể vừa không focus vừa truy cập keyboard/VoiceOver, UX phải tách interaction mode và ghi ADR.

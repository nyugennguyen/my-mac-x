# UX Sign-off Checklist — Sprint 0

Checklist này dùng để review 20 product surfaces và primary flows đã inventory trong [Project Plan — UX architecture](../../my-mac-x_projectplan.md#4-ux-architecture-và-số-lượng-màn-hình). Mockup tham chiếu ở [Project Plan — Wireframe & mockup](../../my-mac-x_projectplan.md#5-wireframe--mockup-project-design); không sao chép lại toàn bộ wireframe tại đây.

## 1. Nguyên tắc review

- Reviewer kiểm tra từng state bằng prototype/mock tương ứng, không sign-off chỉ từ tên surface.
- `N/A` cần lý do và người duyệt.
- Overlay không focus và accessibility keyboard/VoiceOver có thể tạo trade-off; factual behavior phải được PoC, không giả định.
- Microcopy quyền phải nói rõ app làm gì, không hứa thay macOS prompt và không gây áp lực cấp quyền.

## 2. Checklist 20 surfaces

| UI | Surface | States phải review | Check UX bắt buộc | Evidence | Sign-off |
|---|---|---|---|---|---|
| UI-01 | Welcome | First launch | Value proposition; local-first; CTA và Skip/close behavior rõ | `[link TBD]` | ☐ |
| UI-02 | Accessibility Permission | not requested, denied, granted, revoked | Why-before-prompt; Open Settings/Retry; trạng thái tự refresh; không dead-end | `[link TBD]` | ☐ |
| UI-03 | Quick Setup & Test | recording, conflict, success | Có default an toàn; recorder feedback; test không mutate ngoài consent | `[link TBD]` | ☐ |
| UI-04 | Menu Bar Popover | active, no window, unsupported | Action availability đúng capability; pause/settings/quit discoverable; lý do disabled | `[link TBD]` | ☐ |
| UI-05 | General | active, paused, permission missing | Status/launch behavior; permission recovery; reset/pause rõ | `[link TBD]` | ☐ |
| UI-06 | Snapping | Notch, non-Notch, disabled | Trigger preview; dwell/hit-zone controls; fallback wording; test action | `[link TBD]` | ☐ |
| UI-07 | Hotkeys | normal, recording, conflict | Scan nhanh; keyboard navigation; clear/reset; duplicate/invalid response | `[link TBD]` | ☐ |
| UI-08 | Super Mode | disabled, enabled, invalid prefix | Prefix explanation; timeout; command tree; safe reset | `[link TBD]` | ☐ |
| UI-09 | Layout Library | defaults, custom, empty custom | Default/custom distinction; preview; duplicate/delete/restore default | `[link TBD]` | ☐ |
| UI-10 | Displays & Spaces | single, multiple, disconnected | Dùng từ Display/Space đúng; reconnect state; Spaces experimental/ngoài v1 rõ | `[link TBD]` | ☐ |
| UI-11 | Appearance | system, light, dark, reduced effects | Contrast; Reduce Motion; overlay opacity/visibility | `[link TBD]` | ☐ |
| UI-12 | About & Diagnostics | healthy, permission missing, tap disabled | Health giải thích được; copy report redacted; version/update/privacy links | `[link TBD]` | ☐ |
| UI-13 | Layout Editor | create, edit, invalid, unsaved | Constraint/validation inline; keyboard path; discard/save confirmation | `[link TBD]` | ☐ |
| UI-14 | Notch Layout Chooser | trigger, hover, keyboard focus, cancel | Không lấy focus mặc định; target dễ hiểu; Esc/kéo ra; multi-display placement | `[link TBD]` | ☐ |
| UI-15 | Layout Preview | mouse, hotkey, constrained | Preview khác final; visible/high contrast; min-size constraint feedback | `[link TBD]` | ☐ |
| UI-16 | Super Mode HUD | waiting, submenu, success, invalid, timeout | State/remaining keys rõ; không sticky; không che focus content quá lâu | `[link TBD]` | ☐ |
| UI-17 | Hotkey Conflict | replace, choose another, cancel | Nêu hai action xung đột; default không phá binding cũ | `[link TBD]` | ☐ |
| UI-18 | Experimental Spaces Warning | acknowledge, enabled, failed test | Không quảng bá như v1; risk/fallback/disable rõ; public API policy | `[link TBD]` | ☐ |
| UI-19 | Undo/Failure Feedback | undo, unsupported, failed | Ngắn, actionable, không đổ lỗi; Undo deadline/behavior rõ | `[link TBD]` | ☐ |
| UI-20 | Permission Lost Banner | revoked, open settings, recovered | Không spam; action bị chặn an toàn; banner tự biến mất khi recovered | `[link TBD]` | ☐ |

## 3. Primary flow sign-off

### Flow A — First launch & permission

- [ ] Welcome giải thích giá trị trước yêu cầu quyền.
- [ ] Accessibility screen nói rõ app điều khiển position/size window và không đọc nội dung.
- [ ] Denied/revoked có đường Open Settings + Retry, không yêu cầu restart.
- [ ] Skip/close dẫn đến trạng thái degraded dễ hiểu.
- [ ] Quick Setup không bắt buộc custom hotkey để hoàn tất onboarding.
- [ ] Hoàn tất flow mục tiêu ≤90 giây khi người dùng chủ động cấp quyền.

### Flow B — Notch/top-center snap

- [ ] Dwell/hit-zone có feedback trước khi chooser xuất hiện.
- [ ] Chooser nằm trên display của dragged window/pointer theo quy tắc đã định.
- [ ] Hover chỉ preview; drop mới mutate.
- [ ] Esc, kéo ra, app đóng, display disconnect đều cancel/cleanup.
- [ ] Non-Notch dùng top-center với cùng semantics.
- [ ] Không lấy focus của dragged/target app trong supported path.

### Flow C — Custom hotkey

- [ ] Record/clear/reset dùng được bằng keyboard.
- [ ] Duplicate/system conflict phản hồi trước save.
- [ ] Save có hiệu lực runtime và qua relaunch.
- [ ] Unsupported/no-window/permission-lost có feedback riêng.
- [ ] Repeated action/cycle không gây frame drift ngoài tolerance.

### Flow D — Super Mode

- [ ] Prefix vào armed state và HUD xuất hiện mà không focus.
- [ ] HUD chỉ hiện command hợp lệ theo node hiện tại.
- [ ] Success, invalid, Esc và timeout đều thoát rõ ràng.
- [ ] Phím không được capture ngoài armed state.
- [ ] Invalid prefix không được lưu; có reset về default.

### Flow E — Move physical display & recovery

- [ ] Dùng thuật ngữ Display, không gọi là Desktop/Space.
- [ ] Single-display no-op có feedback ngắn.
- [ ] Target frame luôn nằm trong visible frame đích hoặc báo constrained.
- [ ] Disconnect/reconnect không làm settings screen hoặc overlay crash.
- [ ] Undo/Restore behavior sau move-display được ghi rõ.

## 4. Cross-cutting UX quality

### Input và focus

- [ ] Overlay/panel không xuất hiện trong app switcher/Dock.
- [ ] Không steal focus mặc định; focus mode riêng nếu accessibility PoC yêu cầu.
- [ ] Keyboard path cho toàn bộ Settings và action quan trọng.
- [ ] Escape/cancel nhất quán; destructive reset/delete có confirm hoặc Undo.
- [ ] Không tạo shortcut mặc định xung đột phổ biến mà không cảnh báo.

### Accessibility và visual

- [ ] VoiceOver labels, roles, values và announcement plan cho controls/states.
- [ ] Text contrast đạt WCAG AA; selected/hover/disabled không chỉ phân biệt bằng màu.
- [ ] Reduce Motion loại/bớt animation không thiết yếu.
- [ ] Text scale/localization không truncate action quan trọng.
- [ ] Notch/non-Notch/mixed scaling visual QA có screenshot theo hardware matrix.

### Privacy, errors và trust

- [ ] Permission copy khớp data inventory/threat model.
- [ ] Không UI nào ngụ ý app cần Screen Recording hoặc đọc document title.
- [ ] Diagnostics export nói rõ nội dung được copy và đã redaction.
- [ ] Error phân biệt permission/capability/conflict/system failure.
- [ ] Experimental/unsupported có nhãn và đường tắt/disable.

## 5. Tokens cần chốt

Không cần đóng băng toàn design system trong Sprint 0; chỉ cần tokens ảnh hưởng feasibility và state clarity.

| Token/behavior | Cần quyết định | Evidence | Status |
|---|---|---|---|
| Trigger dwell | Default + min/max, tránh accidental activation | Usability PoC ≥5 sessions hoặc quyết định timeboxed | ☐ |
| Trigger/hit zone | Notch và non-Notch geometry, tolerance | P0-05 screenshots/fixtures | ☐ |
| Gap/padding default | Logical points và per-display scaling behavior | Geometry PoC | ☐ |
| Preview visual | Fill/border/opacity/contrast, constrained state | Light/dark/Reduce Motion mock | ☐ |
| Chooser layout order | Default set, Maximize vs Native Full Screen | Product review | ☐ |
| HUD timeout | Default + user configuration range | Input/UX test | ☐ |
| Feedback duration | Success/failure/Undo visibility | UX review | ☐ |

## 6. Factual unknowns cần PoC/research

- `[P0-05 PoC]` Non-activating panel có giữ focus ổn định trong drag giữa displays/Spaces và khi Mission Control/Stage Manager thay đổi không?
- `[Accessibility PoC]` VoiceOver/keyboard focus cho UI-14/UI-16 có cần một chế độ activatable riêng không?
- `[Usability research]` Dwell, hit-zone và layout order tối ưu chưa có dữ liệu; không copy nguyên behavior Windows 11 mà chưa test trên macOS.
- `[P0-04 PoC]` Event suppression có thể cung cấp Super Mode an toàn trong mọi cancel/timeout path không?
- `[P0-03 PoC]` Minimum size/custom title bar của app đích ảnh hưởng preview-to-final feedback ra sao?

## 7. Review record

| Vai trò | Người review | Kết quả | Ngày | Điều kiện/notes |
|---|---|---|---|---|
| Product Design | `Project owner` | Approve Project Plan mockups | `2026-08-23` | Usability tokens remain evidence-driven |
| Product | `Project owner` | Approve 20-surface scope | `2026-08-23` | — |
| Accessibility | `[TBD]` | ☐ Approve ☐ Conditional ☐ Reject | `[TBD]` | `[TBD]` |
| Engineering | `[TBD]` | ☐ Feasible ☐ Conditional ☐ Not feasible | `[TBD]` | `[TBD]` |
| Security/Privacy | `[TBD]` | ☐ Approve ☐ Changes requested | `[TBD]` | `[TBD]` |

**P0-08 status:** `DONE — 20 surfaces và primary flows được approve trong Project Plan; unresolved dwell/hit-zone tokens thuộc P0-05 usability evidence.`

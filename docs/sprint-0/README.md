# Sprint 0 — Discovery, Feasibility và UX

Tài liệu này là bảng điều khiển cho Sprint 0 của My Mac X. Phạm vi và estimate gốc nằm tại [Project Plan — Phase 0](../../my-mac-x_projectplan.md#phase-0--sprint-0--discovery-feasibility-và-ux); thư mục này chỉ lưu quyết định, tiêu chí kiểm chứng và bằng chứng thực thi.

## Quy ước trạng thái

- `TODO`: chưa bắt đầu hoặc chưa có artifact.
- `IN PROGRESS`: đang thực hiện, chưa đủ acceptance/evidence.
- `REVIEW`: artifact đã sẵn sàng, cần người có thẩm quyền duyệt hoặc test thủ công.
- `BLOCKED`: dependency chưa đạt; ghi rõ điều kiện gỡ block.
- `DONE`: acceptance đạt, evidence có thể mở/kiểm tra và người duyệt đã ký.

Không chuyển task sang `DONE` chỉ dựa trên mô tả hoặc mock. Spike phải có build/commit, log kết quả và manual test report trên máy thật.

## Tracker P0-01…P0-08

| ID | Deliverable | Owner / model | Trạng thái | Dependency | Evidence bắt buộc | Exit gate của task |
|---|---|---|---|---|---|---|
| P0-01 | Chốt persona, thuật ngữ và MVP | Product / TERRA-M | DONE | — | [Product brief](product-brief.md), user approved Project Plan 2026-08-23 | Product scope và canonical terms đã được ghi vào `CONTEXT.md` |
| P0-02 | Feature matrix và acceptance criteria | Product + QA / TERRA-M | DONE | P0-01 | [Feature acceptance matrix](feature-acceptance-matrix.md), user approved Project Plan 2026-08-23 | Mọi `SYS-*` P0 có AC đo được, phương pháp verify và owner |
| P0-03 | AX focused-window + resize spike trên 6 app | Core / SOL-H | IN PROGRESS | P0-01 | [AX PoC](../../prototypes/accessibility-window-poc.swift), [research](../research/macos-window-management-feasibility.md), [manual evidence template](evidence/p0-03-ax-spike.md) | PoC type-check pass; còn manual 6-app matrix và read-back trên máy thật |
| P0-04 | Global hotkey/Event Tap spike | Input / SOL-H | IN PROGRESS | P0-01 | [Event Tap PoC](../../prototypes/event-tap-poc.swift), [Super Mode prototype](../../prototypes/super-mode-logic-prototype.html), [manual evidence template](evidence/p0-04-event-tap-spike.md) | Listen-only PoC type-check pass; còn permission matrix, active suppression và hardware test |
| P0-05 | Notch/safe-area/multi-display coordinates spike | Geometry / SOL-XH | IN PROGRESS | P0-03 | [Geometry PoC](../../prototypes/notch-geometry-poc.swift), [manual evidence template](evidence/p0-05-screen-geometry-spike.md) | Read-only PoC type-check pass; còn overlay/focus, origin âm, mixed scaling và Notch hardware evidence |
| P0-06 | Module/protocol/ADR | Architecture / SOL-XH | REVIEW | P0-03…P0-05 | [Window Action Interface](../design/window-action-interface.md), [ADR-0003](../adr/0003-intent-driven-window-action-module.md) | Deep Interface đã thiết kế; final sign-off chờ kết luận ba spike |
| P0-07 | Threat model, data inventory, distribution | Security / SOL-H | REVIEW | P0-03…P0-04 để kết luận | [Threat model](threat-model.md), evidence từ P0-03/04, sign-off security | Security gates TM-G01…TM-G10 có kết quả; residual risks có owner; distribution/entitlement được chốt |
| P0-08 | UX flows, tokens và mockup review | Product Design / SOL-M | DONE | P0-01…P0-02 | [UX sign-off checklist](ux-signoff-checklist.md), mockup trong [Project Plan](../../my-mac-x_projectplan.md#5-project-design-mockup), user approved Project Plan 2026-08-23 | 20 surfaces và primary flows đã được approve; usability tokens vẫn cần P0-05 evidence |

> P0-03/P0-04/P0-05 chỉ được nâng lên `DONE` sau test thủ công. Type-check chứng minh source hợp lệ với SDK hiện tại, không chứng minh TCC, hardware, focus safety hoặc compatibility app thật.

## Gate G0 — điều kiện ra Sprint 0

| Gate | Tiêu chí checkable | Evidence | Kết quả |
|---|---|---|---|
| G0-01 | Resize được cửa sổ của app khác trên máy thật bằng public Accessibility API | P0-03 report + build/commit | ☐ Pass ☐ Fail |
| G0-02 | Overlay top-center/Notch PoC hiển thị mà không thành key/main window và không lấy focus app đích | P0-05 report + screen recording | ☐ Pass ☐ Fail |
| G0-03 | Event Tap/prefix PoC không làm mất phím hoặc modifier khi success, Esc, timeout và tap bị disable | P0-04 report | ☐ Pass ☐ Fail |
| G0-04 | Spaces/Desktop N được xác nhận ngoài v1; production không dùng SkyLight/private API | Product sign-off + architecture decision | ☐ Pass ☐ Fail |
| G0-05 | P0 feature AC, threat model và 20-surface UX checklist được duyệt | Ba artifact trong thư mục này | ☐ Pass ☐ Fail |
| G0-06 | Không còn unknown mức `Blocker` chưa có owner/ngày xử lý | Decision/unknown logs | ☐ Pass ☐ Fail |

**Kết luận G0:** `PENDING`

- Người quyết định Go/No-Go: `[TBD — Product + Tech Lead]`
- Ngày review: `[TBD]`
- Kết quả: `☐ GO  ☐ CONDITIONAL GO  ☐ NO-GO`
- Điều kiện nếu Conditional Go: `[TBD]`

## Trình tự thực hiện và song song hóa

1. P0-01 và P0-02: review ngay các artifact sản phẩm.
2. Chạy song song P0-03 và P0-04 trên máy thật.
3. Sau first-pass P0-03, chạy P0-05; cập nhật threat model bằng kết quả P0-03/P0-04.
4. Chốt P0-06 từ bằng chứng ba spike; không thiết kế adapter dựa trên giả định chưa kiểm chứng.
5. Review P0-08 song song với spike, rồi tổ chức G0 review.

## Trạng thái môi trường hiện tại

- Swift CLI: Apple Swift 6.3.3; ba Swift PoC đã type-check thành công.
- `xcodebuild`: chưa khả dụng vì active developer directory hiện là Command Line Tools, không phải full Xcode.
- Git: workspace chưa được khởi tạo repository.

Full Xcode selection/installation và repository bootstrap là prerequisite trước Sprint 1; chúng không ngăn Sprint 0 research, interface design hoặc CLI type-check.

## Quy tắc evidence

Mỗi báo cáo spike tối thiểu phải ghi: ngày, macOS/build, hardware, app/version, quyền đã cấp, commit/build, bước tái hiện, expected/actual, log đã redaction, kết luận và factual unknowns còn lại. Không ghi window title, phím người dùng ngoài phiên test, clipboard hay nội dung màn hình.

## Liên kết

- [Product brief](product-brief.md)
- [Feature acceptance matrix](feature-acceptance-matrix.md)
- [Threat model](threat-model.md)
- [UX sign-off checklist](ux-signoff-checklist.md)
- [macOS API feasibility research](../research/macos-window-management-feasibility.md)
- [Window Action Interface](../design/window-action-interface.md)
- [Prototype runbook](../../prototypes/README.md)
- [Project Plan — quyết định cần xác nhận ở Sprint 0](../../my-mac-x_projectplan.md#15-các-quyết-định-cần-xác-nhận-ở-sprint-0)

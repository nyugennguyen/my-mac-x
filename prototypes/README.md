# My Mac X — Sprint 0 throwaway prototypes

> **THROWAWAY / KHÔNG PHẢI PRODUCTION CODE.** Các prototype trong thư mục này chỉ dùng để trả lời câu hỏi feasibility và UX của Sprint 0. Sau khi có kết luận, quyết định đã được xác nhận phải được chuyển thành ADR/implementation; không nâng trực tiếp các file này thành mã production.

## Mục tiêu Sprint 0

Các prototype trả lời bốn câu hỏi trước khi khóa kiến trúc:

1. Super Mode nên chuyển trạng thái thế nào khi nhận prefix, submenu, lệnh hợp lệ, phím sai, `Escape`, timeout và khi bị tắt?
2. Public Accessibility API có đọc được focused window, xác định khả năng move/resize và — chỉ khi người thử chủ động xác nhận — đặt frame cửa sổ hay không?
3. Public CoreGraphics event tap có quan sát chuỗi phím và phân biệt trạng thái quyền trên các máy/macOS mục tiêu không?
4. Public `NSScreen` geometry có đủ dữ liệu để suy ra trigger region cho màn hình có Notch, không Notch, và màn hình có origin âm không?

Không prototype nào dùng private API, Spaces/SkyLight API, persistence, analytics hoặc network.

## Danh sách prototype

### `super-mode-logic-prototype.html`

Mở file bằng cách double-click trong Finder. Không cần server hay dependency.

Quan sát:

- Prefix chỉ arm Super Mode khi tính năng đang bật.
- Lệnh một cấp thực thi rồi luôn quay lại `Idle`.
- Submenu giữ command path rõ ràng; `Escape` và timeout luôn thoát.
- Phím sai tuân theo policy đang chọn (`Cancel immediately` hoặc `Keep listening`).
- Prefix được nhấn lại sẽ reset về root và làm mới timeout.
- Panel trạng thái hiển thị đầy đủ state và quyết định có consume event hay không sau mỗi thao tác.

Kịch bản hướng dẫn cố tình bao phủ happy path, lệnh sâu, timeout/cancel, phím sai và trạng thái disabled. Sau khi review, ghi lại policy được chọn; không copy nguyên HTML shell vào app.

### `accessibility-window-poc.swift`

Mục tiêu chính là kiểm tra focused-window discovery, thuộc tính position/size và cờ settable bằng public Accessibility API.

Type-check an toàn (không chạy):

```sh
xcrun swiftc -typecheck prototypes/accessibility-window-poc.swift
```

Chạy chế độ chỉ đọc:

```sh
xcrun swift prototypes/accessibility-window-poc.swift --inspect
```

Chế độ resize được khóa bằng **hai cờ xác nhận** và vẫn phải được thực hiện trên một cửa sổ test có thể khôi phục:

```sh
xcrun swift prototypes/accessibility-window-poc.swift --apply --confirm-I-understand
```

Khi cần kiểm thử read-back tự động mà không để lại frame đã thay đổi, thêm `--restore-after-readback`. Prototype sẽ đọc lại cả frame test và frame khôi phục:

```sh
xcrun swift prototypes/accessibility-window-poc.swift --apply --confirm-I-understand --restore-after-readback
```

Không chạy chế độ `--apply` qua automation. Người thử phải tự focus từng app trong test matrix, chạy lệnh, quan sát frame trước/sau và tự khôi phục cửa sổ. Kết quả cần ghi: permission state, focused window có lấy được không, position/size có settable không, AX error, frame read-back và app/macOS đang thử.

### `event-tap-poc.swift`

Prototype chỉ dùng event tap `.listenOnly`: không sửa, chặn hoặc nuốt phím. Type-check an toàn:

```sh
xcrun swiftc -typecheck prototypes/event-tap-poc.swift
```

Người thử có thể chạy thủ công:

```sh
xcrun swift prototypes/event-tap-poc.swift --listen
```

Kiểm tra delivery an toàn, không cần nhập phím người dùng:

```sh
xcrun swift prototypes/event-tap-poc.swift --self-test
```

Self-test chỉ post một cặp `Escape` tổng hợp vào session, xác nhận tap nhìn thấy key-down/key-up rồi tự dừng sau tối đa hai giây. Nó không chứng minh active suppression.

Nhấn `Control+Space`, vài phím tiếp theo, rồi `Control+C` trong Terminal để dừng. Quan sát: tap tạo được không, macOS yêu cầu quyền nào, event có đến ổn định không, modifier flags và key code có đúng không, tap có bị timeout/disable không. Prototype không chứng minh suppression; suppression phải là một spike riêng có review an toàn trước khi triển khai.

### `notch-geometry-poc.swift`

Prototype chỉ đọc danh sách màn hình và in geometry; không mở overlay và không thay đổi cấu hình display.

```sh
xcrun swiftc -typecheck prototypes/notch-geometry-poc.swift
xcrun swift prototypes/notch-geometry-poc.swift --inspect
```

Chạy fixture read-only để regression-check fallback với origin âm và auxiliary-area không hợp lệ:

```sh
xcrun swift prototypes/notch-geometry-poc.swift --self-test
```

`--self-test` chỉ chứng minh phép tính thuần với dữ liệu fixture; nó không thay thế việc bố trí màn hình thật ở origin âm. `--inspect` in tên Display, scale, display mode và vị trí tương đối so với màn hình chính để lưu evidence topology mà không đọc nội dung màn hình.

Chạy lần lượt với màn hình MacBook, external display, menu bar/Dock ở các vị trí khác nhau và arrangement làm xuất hiện origin âm. Quan sát:

- `frame`, `visibleFrame`, `safeAreaInsets` và auxiliary top areas.
- Notch region suy ra có nằm giữa hai auxiliary top areas không.
- Màn hình không Notch dùng top-center fallback hợp lệ.
- Trigger region luôn được clamp trong screen frame và đúng hệ tọa độ AppKit.

## Kỷ luật thử nghiệm

- Chỉ chạy trên máy và cửa sổ test mà người thử kiểm soát.
- Không nhập password, token hoặc dữ liệu nhạy cảm khi event-tap prototype đang chạy.
- Không dùng PoC trong login item, CI hoặc bản phân phối.
- Không commit kết luận giả định. Mọi kết quả phần cứng/quyền phải ghi từ thử nghiệm thủ công trên máy thật.
- Sau Sprint 0, giữ prototype trên throwaway branch làm primary source; main chỉ giữ quyết định đã được xác nhận và production implementation mới.

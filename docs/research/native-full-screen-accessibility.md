# Native Full Screen qua Accessibility của cửa sổ app khác

Ngày xác minh: 2026-08-24

Phạm vi: macOS 14 trở lên; public API dùng được cho cửa sổ của tiến trình khác

SDK đối chiếu: Xcode 26.6 (build 17F113), macOS SDK 26.5

## Kết luận ngắn

**Không có public API hoặc AX attribute được Apple document để một app xác định trực tiếp trạng thái Native Full Screen hiện tại của cửa sổ thuộc app khác.**

- **FACT.** AppKit có signal chính xác cho `NSWindow` mà app đang sở hữu: `styleMask` mô tả style hiện tại và `.fullScreen` được tự động bật/tắt khi `toggleFullScreen(_:)` chạy. Tuy nhiên `NSApplication.windows` chỉ trả về các window object của chính app, không tạo bridge tới `NSWindow` của tiến trình khác. Nguồn: [Apple — `NSWindow.styleMask`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.property), [Apple — `NSWindow.StyleMask.fullScreen`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullscreen), [Apple — `NSApplication.windows`](https://developer.apple.com/documentation/appkit/nsapplication/windows), [Apple — Full-Screen API in `NSWindow`](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/FullScreenApp/FullScreenApp.html).
- **FACT.** Public Accessibility API có `kAXFullScreenButtonAttribute`, nhưng giá trị của nó là accessibility element đại diện cho **nút** Full Screen, không phải Boolean cho biết window đang ở Native Full Screen. Nguồn: [Apple — `kAXFullScreenButtonAttribute`](https://developer.apple.com/documentation/applicationservices/kaxfullscreenbuttonattribute), [Apple — danh sách `NSAccessibilityAttributeName`](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/attribute), [Apple — `accessibilityFullScreenButton`](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol).
- **FACT.** SDK hiện tại không khai báo `kAXFullScreenAttribute`, `kAXFullscreenAttribute`, hay constant có giá trị `"AXFullScreen"`. Chuỗi `"AXFullScreen"` được dùng trong một số implementation ngoài tài liệu Apple vì thế là undocumented string key.
- **INFERENCE có độ tin cậy cao.** Với ràng buộc production chỉ dùng public API, `NativeFullScreenState.unavailable` là kết quả đúng và ổn định cho cửa sổ app khác. Không nên đổi nó thành `.active`/`.inactive` từ chuỗi AX không được document hoặc từ hình học cửa sổ.

## Cách kiểm tra

Nghiên cứu đối chiếu ba bề mặt public có khả năng cung cấp signal:

1. Accessibility client API (`AXUIElement` và các constant AX).
2. AppKit (`NSWindow`, `NSApplication` và Full Screen lifecycle).
3. Quartz Window Services (`CGWindowListCopyWindowInfo`).

Ngoài tài liệu Apple công khai, toàn bộ header liên quan trong macOS SDK 26.5 đã được tìm với cả `FullScreen`, `Fullscreen` và literal `AXFullScreen`:

- `ApplicationServices.framework/.../HIServices.framework/.../Headers/AXAttributeConstants.h`
- `ApplicationServices.framework/.../HIServices.framework/.../Headers/AXRoleConstants.h`
- `AppKit.framework/.../Headers/NSAccessibilityConstants.h`
- `AppKit.framework/.../Headers/NSAccessibilityProtocols.h`
- `CoreGraphics.framework/.../Headers/CGWindow.h`

Trong Accessibility headers, các kết quả duy nhất liên quan Full Screen là `kAXFullScreenButtonAttribute`, `kAXFullScreenButtonSubrole` và các tên AppKit tương ứng cho **button**. Việc không tìm thấy symbol là bằng chứng SDK âm tính, không phải lời hứa rằng một provider sẽ không bao giờ tự xuất thêm attribute riêng.

## 1. Accessibility: public button, không có public state

### Public contract

**FACT.** `AXUIElementCopyAttributeNames` trả về các attribute mà một accessibility object cụ thể hỗ trợ tại runtime; `AXUIElementCopyAttributeValue` nhận tên attribute dưới dạng `CFString`. Nguồn: [Apple — `AXUIElementCopyAttributeNames`](https://developer.apple.com/documentation/applicationservices/1459475-axuielementcopyattributenames), [Apple — `AXUIElement`](https://developer.apple.com/documentation/applicationservices/axuielement).

**FACT.** Danh sách public `NSAccessibilityAttributeName` phân biệt rõ các state Boolean đã được công bố, ví dụ `NSAccessibilityMinimizedAttribute`, với `NSAccessibilityFullScreenButtonAttribute`, được mô tả là element đại diện cho nút Full Screen. Danh sách này không có Full Screen state attribute. Nguồn: [Apple — `NSAccessibilityAttributeName`](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/attribute).

**FACT.** `kAXFullScreenButtonAttribute` có contract là:

- giá trị: một `AXUIElementRef` của nút Full Screen;
- chỉ đọc;
- được yêu cầu đối với window element có nút Full Screen.

Nó cho biết có control tương ứng, không cho biết window đang ở state nào. Nguồn: [Apple — `kAXFullScreenButtonAttribute`](https://developer.apple.com/documentation/applicationservices/kaxfullscreenbuttonattribute), cùng header Apple `AXAttributeConstants.h` của SDK hiện tại.

### Undocumented string key

**FACT.** Không tồn tại public SDK symbol `kAXFullScreenAttribute` hay `kAXFullscreenAttribute` trong SDK đã kiểm tra. Literal `"AXFullScreen"` cũng không được định nghĩa trong public Accessibility headers hoặc liệt kê trong Apple API reference.

**INFERENCE.** Vì `AXUIElementCopyAttributeValue` nhận một `CFString`, code dùng `"AXFullScreen" as CFString` vẫn có thể compile và một số accessibility provider có thể trả về giá trị. Điều đó chỉ chứng minh hành vi quan sát được của provider và OS đang chạy; nó không tạo availability, kiểu dữ liệu, semantics hay compatibility contract của Apple.

**INFERENCE.** Ngay cả khi `AXUIElementCopyAttributeNames` tình cờ trả về `"AXFullScreen"`, việc match tên rồi diễn giải nó như Boolean vẫn là sử dụng API không được document. Dynamic discovery không biến tên hoặc semantics của attribute thành public contract.

### Những signal từ button không đủ

**INFERENCE.** Sự hiện diện của `kAXFullScreenButtonAttribute` chỉ là dấu hiệu window có một Full Screen control. Apple document `NSWindow.CollectionBehavior.fullScreenPrimary` theo cùng hướng capability: window **có thể** vào Full Screen, không phải đang ở Full Screen. Nguồn: [Apple — `fullScreenPrimary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenprimary).

**INFERENCE.** Đọc title, help, description hoặc action description của nút để phân biệt “Enter” và “Exit” không phải state contract: các giá trị này phục vụ người dùng, có thể localized, do app/accessibility provider cung cấp, và Apple không document phép ánh xạ chúng sang Native Full Screen state.

**INFERENCE.** Thực hiện press action lên nút rồi quan sát hậu quả không phải phép đọc capability; nó làm thay đổi cửa sổ, có race với focus/Space transition và vi phạm nguyên tắc capture không gây mutation.

## 2. AppKit: state chính xác nhưng chỉ trong app sở hữu window

**FACT.** Apple document `NSWindow.styleMask` là các flag mô tả style hiện tại, bao gồm việc window ở Full Screen; `.fullScreen` được tự động toggle khi gọi `toggleFullScreen(_:)`. Nguồn: [Apple — `styleMask`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.property), [Apple — `.fullScreen`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullscreen), [Apple — Implementing the Full-Screen Experience](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/FullScreenApp/FullScreenApp.html).

**FACT.** Full Screen notifications của AppKit mang chính `NSWindow` làm notification object. `NSApplication.windows` là mảng window object của **app đó**. Nguồn: [Apple — `willEnterFullScreenNotification`](https://developer.apple.com/documentation/appkit/nswindow/willenterfullscreennotification), [Apple — `NSApplication.windows`](https://developer.apple.com/documentation/appkit/nsapplication/windows).

**INFERENCE có độ tin cậy cao.** Đây là giải pháp đúng khi code chạy trong app sở hữu window, nhưng không đáp ứng My Mac X: public AppKit không cung cấp `NSWindow` object của một process khác từ `AXUIElement` hay `CGWindowID`.

**FACT.** `NSWindow.CollectionBehavior` mô tả preference/capability cho Mission Control, Spaces, Stage Manager và Full Screen; `fullScreenPrimary` có nghĩa window có thể vào Full Screen. Nó không phải state hiện tại. Nguồn: [Apple — `NSWindow.CollectionBehavior`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct), [Apple — `fullScreenPrimary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenprimary).

## 3. Quartz Window Services: metadata không có Full Screen state

**FACT.** `CGWindowListCopyWindowInfo` trả về dictionary metadata cho window trong user session. Apple công bố tập required keys gồm ID, backing-store type, layer, bounds, sharing state, alpha, owner PID và memory usage. Optional keys gồm deprecated workspace, owner name, window name, onscreen state và backing-store location. Không tập nào có Native Full Screen state. Nguồn: [Apple — `CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo%28_%3A_%3A%29), [Apple — Required Window List Keys](https://developer.apple.com/documentation/coregraphics/required-window-list-keys), [Apple — Optional Window List Keys](https://developer.apple.com/documentation/coregraphics/optional-window-list-keys).

**FACT.** `kCGWindowBounds` chỉ cung cấp rectangle trong screen space. Nguồn: [Apple — `kCGWindowBounds`](https://developer.apple.com/documentation/coregraphics/kcgwindowbounds).

**INFERENCE.** So sánh bounds với `NSScreen.frame`, `visibleFrame` hoặc safe area không phân biệt được một cách tổng quát giữa:

- Native Full Screen;
- Maximize/fill do window manager thực hiện;
- borderless/custom full-screen;
- window tile/Split View;
- layout chịu ảnh hưởng của menu bar auto-hide, camera housing hoặc Stage Manager.

Geometry có thể là heuristic UI, nhưng không đủ để tạo `.active`/`.inactive` trong capability model yêu cầu correctness.

## 4. Phân loại kết quả

### FACT

- Public AppKit có state chính xác qua `NSWindow.styleMask.contains(.fullScreen)` cho window object thuộc app.
- Public Accessibility chỉ công bố Full Screen **button element/subrole**, không công bố Full Screen state attribute cho cross-process window.
- Public Quartz window dictionaries không có Full Screen state key.
- SDK hiện tại không khai báo `kAXFullScreenAttribute`, `kAXFullscreenAttribute` hoặc literal constant `"AXFullScreen"`.

### INFERENCE

- Không thể triển khai detector tổng quát, ổn định cho Native Full Screen của cửa sổ app khác chỉ bằng public API hiện có.
- `"AXFullScreen"`, nội dung text của nút, frame matching và Space/window-server correlations đều không đạt public-contract bar của production.
- Trạng thái tri-state hiện tại là đúng: giữ `.unavailable` thay vì trả một Boolean có thể sai.

### UNKNOWN

- App hoặc macOS version nào hiện đang tự xuất `"AXFullScreen"`, kiểu giá trị nào, và hành vi đó có ổn định qua update hay không.
- Apple có bổ sung public cross-process Full Screen state attribute trong SDK tương lai hay không.
- Hành vi chi tiết của custom accessibility provider; không thể suy rộng từ một app sang mọi app.

Các unknown này không cần spike production vì dù kết quả thực nghiệm có thuận lợi, chúng không tạo public contract.

## Quyết định đề xuất cho F1-04

**Đề xuất chuyển F1-04 từ `CONDITIONAL PASS` sang `PASS — DOCUMENTED PLATFORM LIMITATION ACCEPTED`.**

Lý do: câu hỏi còn mở đã được đóng ở mức contract. Không có public cross-process signal để chờ triển khai. `SystemWindowAdapter` hiện trả `nativeFullScreen: .unavailable`, không dùng `"AXFullScreen"` và không suy luận từ geometry; cách này phù hợp với policy public API của dự án.

Điều kiện khi cập nhật tracker/evidence:

- ghi rõ `.unavailable` là platform limitation, không phải lỗi runtime;
- chỉ thay đổi sang `.active`/`.inactive` nếu một SDK Apple tương lai công bố state attribute/function với semantics và availability rõ ràng;
- nếu acceptance criterion bắt buộc phải biết trạng thái Native Full Screen thay vì cho phép `.unavailable`, F1-04 không thể PASS dưới constraint public API và criterion đó phải được đổi phạm vi, không được lấp bằng heuristic.
